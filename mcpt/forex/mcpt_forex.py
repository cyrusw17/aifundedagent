"""MCPT adapted for forex SMC strategies with $ / challenge objectives."""

from __future__ import annotations

from typing import Any, Callable

import numpy as np
import pandas as pd

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.permute import get_permutation
from mcpt.pipeline import McptResult


def permute_forex_book(
    data: dict[str, pd.DataFrame],
    seed: int | None = None,
) -> dict[str, pd.DataFrame]:
    """Joint permutation across pairs (preserves cross-market correlation structure)."""
    pairs = list(data.keys())
    frames = [data[p][["open", "high", "low", "close"]].copy() for p in pairs]
    # Align to common index
    common = frames[0].index
    for f in frames[1:]:
        common = common.intersection(f.index)
    frames = [f.loc[common] for f in frames]
    permuted = get_permutation(frames, start_index=0, seed=seed)
    if not isinstance(permuted, list):
        permuted = [permuted]
    return {p: permuted[i] for i, p in enumerate(pairs)}


def objective_from_backtest(bt) -> float:
    """Higher is better. Heavily penalize blown accounts and consistency fails."""
    s = bt.stats
    if s.get("blown"):
        return -1.0
    if not s.get("consistency_ok", True):
        return 0.0
    # Blend profit factor and annualized $ (scaled)
    pf = min(float(s.get("profit_factor", 0.0)), 5.0)
    ann = float(s.get("avg_annual_pnl", 0.0))
    trades = float(s.get("n_trades", 0))
    # Prefer strategies with enough trades
    trade_bonus = min(trades / 50.0, 1.0)
    return pf * 0.35 + (ann / 10_000.0) * 0.55 + trade_bonus * 0.10


def run_forex_insample_mcpt(
    data: dict[str, pd.DataFrame],
    param_grid: list[dict[str, Any]],
    n_permutations: int = 100,
    threshold: float = 0.05,
    seed: int = 42,
    progress: Callable[[int, int], None] | None = None,
) -> tuple[dict[str, Any], McptResult, Any]:
    """Optimize params on real data, then MCPT by re-optimizing on permutations."""

    def optimize(book: dict[str, pd.DataFrame]) -> tuple[dict, float, Any]:
        best_params, best_score, best_bt = None, -1e18, None
        for params in param_grid:
            bt = run_backtest(book, **params)
            score = objective_from_backtest(bt)
            if score > best_score:
                best_score, best_params, best_bt = score, params, bt
        return best_params, best_score, best_bt

    real_params, real_score, real_bt = optimize(data)
    perm_better = 1
    perm_scores: list[float] = []

    for i in range(1, n_permutations):
        book = permute_forex_book(data, seed=seed + i)
        _, perm_score, _ = optimize(book)
        if perm_score >= real_score:
            perm_better += 1
        perm_scores.append(float(perm_score))
        if progress:
            progress(i, n_permutations)

    p_value = perm_better / n_permutations
    result = McptResult(
        real_score=float(real_score),
        p_value=float(p_value),
        n_permutations=n_permutations,
        perm_scores=perm_scores,
        passed=p_value <= threshold,
        threshold=threshold,
        label="Forex In-sample MCPT",
    )
    return real_params, result, real_bt


def run_forex_fixed_params_mcpt(
    data: dict[str, pd.DataFrame],
    params: dict[str, Any],
    n_permutations: int = 200,
    threshold: float = 0.05,
    seed: int = 42,
) -> tuple[McptResult, Any]:
    """MCPT without re-optimization — tests fixed strategy config (weaker but faster).

    Still valid for live: asks whether this exact rule set beats noise.
    """
    real_bt = run_backtest(data, **params)
    real_score = objective_from_backtest(real_bt)
    perm_better = 1
    perm_scores = []
    for i in range(1, n_permutations):
        book = permute_forex_book(data, seed=seed + i)
        bt = run_backtest(book, **params)
        score = objective_from_backtest(bt)
        if score >= real_score:
            perm_better += 1
        perm_scores.append(float(score))
    p_value = perm_better / n_permutations
    result = McptResult(
        real_score=float(real_score),
        p_value=float(p_value),
        n_permutations=n_permutations,
        perm_scores=perm_scores,
        passed=p_value <= threshold,
        threshold=threshold,
        label="Forex Fixed-Params MCPT",
    )
    return result, real_bt
