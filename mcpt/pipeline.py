"""Four-step MCPT strategy development pipeline.

1. In-sample excellence (optimize + equity curve)
2. In-sample Monte Carlo permutation test
3. Walk-forward test
4. Walk-forward Monte Carlo permutation test
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Callable

import numpy as np
import pandas as pd

from mcpt.metrics import cumulative_log_returns, profit_factor, sharpe_ratio, strategy_returns
from mcpt.permute import get_permutation
from mcpt.strategies.donchian import (
    donchian_breakout,
    optimize_donchian,
    walkforward_donchian,
)
from mcpt.strategies.moving_average import ma_crossover, optimize_ma_crossover
from mcpt.strategies.tree import train_tree, tree_strategy


@dataclass
class McptResult:
    real_score: float
    p_value: float
    n_permutations: int
    perm_scores: list[float]
    passed: bool
    threshold: float
    label: str

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        # Cap payload size for API responses
        scores = d["perm_scores"]
        if len(scores) > 500:
            d["perm_scores_sample"] = scores[:: max(1, len(scores) // 200)]
        else:
            d["perm_scores_sample"] = scores
        del d["perm_scores"]
        d["perm_scores_count"] = len(scores)
        d["perm_mean"] = float(np.mean(scores)) if scores else None
        d["perm_std"] = float(np.std(scores)) if scores else None
        return d


@dataclass
class PipelineResult:
    strategy: str
    data_source: str
    n_bars: int
    train_start: str
    train_end: str
    insample: dict[str, Any] = field(default_factory=dict)
    insample_mcpt: dict[str, Any] | None = None
    walkforward: dict[str, Any] | None = None
    walkforward_mcpt: dict[str, Any] | None = None
    verdict: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _series_for_chart(s: pd.Series, max_points: int = 800) -> list[dict]:
    s = s.dropna()
    if len(s) == 0:
        return []
    step = max(1, len(s) // max_points)
    sampled = s.iloc[::step]
    return [
        {"t": idx.isoformat() if hasattr(idx, "isoformat") else str(idx), "v": float(val)}
        for idx, val in sampled.items()
    ]


def run_insample_mcpt(
    ohlc: pd.DataFrame,
    optimize_fn: Callable[[pd.DataFrame], tuple[Any, float]],
    n_permutations: int = 200,
    threshold: float = 0.01,
    seed: int = 0,
    progress: Callable[[int, int], None] | None = None,
) -> McptResult:
    """In-sample MCPT: optimize on real vs many permutations.

    Null hypothesis: strategy is garbage (excellence is data-mining bias).
    Low p-value → reject null → patterns in real data matter.
    """
    _, best_real = optimize_fn(ohlc)
    perm_better = 1  # include real observation (conservative)
    perm_scores: list[float] = []

    for i in range(1, n_permutations):
        perm = get_permutation(ohlc, seed=seed + i if seed is not None else None)
        _, best_perm = optimize_fn(perm)
        if best_perm >= best_real:
            perm_better += 1
        perm_scores.append(float(best_perm))
        if progress:
            progress(i, n_permutations)

    p_value = perm_better / n_permutations
    return McptResult(
        real_score=float(best_real),
        p_value=float(p_value),
        n_permutations=n_permutations,
        perm_scores=perm_scores,
        passed=p_value <= threshold,
        threshold=threshold,
        label="In-sample MCPT",
    )


def run_walkforward_mcpt(
    ohlc: pd.DataFrame,
    walkforward_fn: Callable[[pd.DataFrame], pd.Series],
    train_lookback: int,
    n_permutations: int = 100,
    threshold: float = 0.05,
    seed: int = 0,
    progress: Callable[[int, int], None] | None = None,
) -> tuple[float, McptResult, pd.Series]:
    """Walk-forward MCPT: permute only after first training fold."""
    signal = walkforward_fn(ohlc)
    rets = strategy_returns(signal, ohlc["close"])
    real_pf = profit_factor(rets)

    perm_better = 1
    perm_scores: list[float] = []

    for i in range(1, n_permutations):
        perm = get_permutation(
            ohlc,
            start_index=train_lookback,
            seed=seed + i if seed is not None else None,
        )
        perm_sig = walkforward_fn(perm)
        perm_rets = strategy_returns(perm_sig, perm["close"])
        perm_pf = profit_factor(perm_rets)
        if perm_pf >= real_pf:
            perm_better += 1
        perm_scores.append(float(perm_pf))
        if progress:
            progress(i, n_permutations)

    p_value = perm_better / n_permutations
    result = McptResult(
        real_score=float(real_pf),
        p_value=float(p_value),
        n_permutations=n_permutations,
        perm_scores=perm_scores,
        passed=p_value <= threshold,
        threshold=threshold,
        label="Walk-forward MCPT",
    )
    return float(real_pf), result, signal


def _optimize_donchian_bound(lookback_min: int, lookback_max: int):
    def _fn(df: pd.DataFrame):
        return optimize_donchian(df, lookback_min=lookback_min, lookback_max=lookback_max)

    return _fn


def run_full_pipeline(
    ohlc: pd.DataFrame,
    strategy: str = "donchian",
    data_source: str = "unknown",
    n_insample_perms: int = 100,
    n_walkforward_perms: int = 50,
    train_years: int = 4,
    bars_per_day: int = 24,
    lookback_min: int = 12,
    lookback_max: int = 72,
    insample_threshold: float = 0.01,
    walkforward_threshold: float = 0.05,
    run_walkforward: bool = True,
    seed: int = 42,
) -> PipelineResult:
    """Run the four-step process for a built-in strategy."""
    if len(ohlc) < bars_per_day * 365:
        raise ValueError("Need at least ~1 year of bars for a meaningful test")

    train_lookback = bars_per_day * 365 * train_years
    # If series is shorter than train window, use 60% for train
    if train_lookback >= len(ohlc):
        train_lookback = max(bars_per_day * 90, int(len(ohlc) * 0.6))

    train_df = ohlc.iloc[:train_lookback].copy()
    result = PipelineResult(
        strategy=strategy,
        data_source=data_source,
        n_bars=len(ohlc),
        train_start=str(train_df.index[0]),
        train_end=str(train_df.index[-1]),
    )

    if strategy == "donchian":
        opt_fn = _optimize_donchian_bound(lookback_min, lookback_max)
        best_param, best_pf = opt_fn(train_df)
        signal = donchian_breakout(train_df, best_param)
        rets = strategy_returns(signal, train_df["close"])
        result.insample = {
            "param": best_param,
            "param_name": "lookback",
            "profit_factor": float(best_pf),
            "sharpe": sharpe_ratio(rets),
            "equity": _series_for_chart(cumulative_log_returns(rets)),
            "price": _series_for_chart(np.log(train_df["close"]) - np.log(train_df["close"].iloc[0])),
        }

        mcpt = run_insample_mcpt(
            train_df,
            opt_fn,
            n_permutations=n_insample_perms,
            threshold=insample_threshold,
            seed=seed,
        )
        result.insample_mcpt = mcpt.to_dict()

        if run_walkforward and len(ohlc) > train_lookback + bars_per_day * 30:
            train_step = bars_per_day * 30

            def wf_fn(df: pd.DataFrame) -> pd.Series:
                return walkforward_donchian(
                    df,
                    train_lookback=train_lookback,
                    train_step=train_step,
                    lookback_min=lookback_min,
                    lookback_max=lookback_max,
                )

            real_wf_pf, wf_mcpt, wf_signal = run_walkforward_mcpt(
                ohlc,
                wf_fn,
                train_lookback=train_lookback,
                n_permutations=n_walkforward_perms,
                threshold=walkforward_threshold,
                seed=seed + 10_000,
            )
            wf_rets = strategy_returns(wf_signal, ohlc["close"])
            # Out-of-sample portion only for equity display
            oos = wf_rets.iloc[train_lookback:]
            result.walkforward = {
                "profit_factor": real_wf_pf,
                "sharpe": sharpe_ratio(oos),
                "equity": _series_for_chart(cumulative_log_returns(oos)),
                "train_lookback": train_lookback,
                "train_step": train_step,
            }
            result.walkforward_mcpt = wf_mcpt.to_dict()

    elif strategy == "ma_crossover":
        best_params, best_pf = optimize_ma_crossover(train_df)
        signal = ma_crossover(train_df, best_params[0], best_params[1])
        rets = strategy_returns(signal, train_df["close"])
        result.insample = {
            "param": {"fast": best_params[0], "slow": best_params[1]},
            "param_name": "fast/slow",
            "profit_factor": float(best_pf),
            "sharpe": sharpe_ratio(rets),
            "equity": _series_for_chart(cumulative_log_returns(rets)),
            "price": _series_for_chart(np.log(train_df["close"]) - np.log(train_df["close"].iloc[0])),
        }
        mcpt = run_insample_mcpt(
            train_df,
            optimize_ma_crossover,
            n_permutations=n_insample_perms,
            threshold=insample_threshold,
            seed=seed,
        )
        result.insample_mcpt = mcpt.to_dict()

    elif strategy == "tree":
        model = train_tree(train_df)
        signal, best_pf = tree_strategy(train_df, model)
        rets = strategy_returns(signal, train_df["close"])
        result.insample = {
            "param": {"min_samples_leaf": 5},
            "param_name": "tree",
            "profit_factor": float(best_pf),
            "sharpe": sharpe_ratio(rets),
            "equity": _series_for_chart(cumulative_log_returns(rets)),
            "price": _series_for_chart(np.log(train_df["close"]) - np.log(train_df["close"].iloc[0])),
        }

        def tree_opt(df: pd.DataFrame):
            m = train_tree(df)
            _, pf = tree_strategy(df, m)
            return None, pf

        mcpt = run_insample_mcpt(
            train_df,
            tree_opt,
            n_permutations=n_insample_perms,
            threshold=insample_threshold,
            seed=seed,
        )
        result.insample_mcpt = mcpt.to_dict()
    else:
        raise ValueError(f"Unknown strategy: {strategy}")

    result.verdict = _build_verdict(result)
    # Convert nested dataclasses already flattened via to_dict calls
    return result


def _build_verdict(result: PipelineResult) -> str:
    parts = []
    is_mcpt = result.insample_mcpt
    if is_mcpt:
        if is_mcpt["passed"]:
            parts.append(
                f"In-sample MCPT PASSED (p={is_mcpt['p_value']:.3f}). "
                "Optimized performance is unlikely to be pure data-mining bias."
            )
        else:
            parts.append(
                f"In-sample MCPT FAILED (p={is_mcpt['p_value']:.3f}). "
                "Excellence looks like overfitting — rethink the strategy."
            )
    wf = result.walkforward_mcpt
    if wf:
        if wf["passed"]:
            parts.append(
                f"Walk-forward MCPT PASSED (p={wf['p_value']:.3f}). "
                "OOS edge is unlikely pure luck."
            )
        else:
            parts.append(
                f"Walk-forward MCPT FAILED (p={wf['p_value']:.3f}). "
                "Walk-forward results could easily be chance."
            )
    if not parts:
        return "Incomplete run."
    return " ".join(parts)
