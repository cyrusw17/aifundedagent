"""Evaluation + funded phase simulator under The5ers-style card rules."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import pandas as pd

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import BacktestResult, run_backtest


@dataclass
class ChallengeReport:
    evaluation_passed: bool
    funded_survived: bool
    evaluation_days: int
    funded_annual_pnl: float
    consistency_ok: bool
    details: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "evaluation_passed": self.evaluation_passed,
            "funded_survived": self.funded_survived,
            "evaluation_days": self.evaluation_days,
            "funded_annual_pnl": self.funded_annual_pnl,
            "consistency_ok": self.consistency_ok,
            "details": self.details,
        }


def simulate_challenge(
    data: dict[str, pd.DataFrame],
    eval_end: str = "2020-12-31",
    funded_end: str = "2023-12-31",
    **backtest_kwargs,
) -> ChallengeReport:
    """Run evaluation on early window, then funded (with weekly withdraw) on later window."""
    rules: FundedRules = backtest_kwargs.get("rules") or FundedRules()

    eval_data = {
        p: df[df.index <= pd.Timestamp(eval_end)].copy() for p, df in data.items()
    }
    # Evaluation: no weekly withdraw — need to reach +10% on account
    eval_kwargs = dict(backtest_kwargs)
    eval_kwargs["weekly_withdraw"] = False
    eval_kwargs["rules"] = rules
    eval_bt = run_backtest(eval_data, **eval_kwargs)

    # Prop-style: pass on first hit of +10% without blowing (not final equity).
    eq = eval_bt.equity_curve
    hit_idx = None
    for t, v in eq.items():
        if v >= rules.evaluation_target:
            hit_idx = t
            break
    evaluation_days = int((hit_idx - eq.index[0]).days) if hit_idx is not None and len(eq) else -1
    eval_passed = (
        hit_idx is not None
        and not eval_bt.account.blown
        and eval_bt.account.consistency_ok()
    )

    funded_data = {
        p: df[(df.index > pd.Timestamp(eval_end)) & (df.index <= pd.Timestamp(funded_end))].copy()
        for p, df in data.items()
    }
    funded_kwargs = dict(backtest_kwargs)
    # Honor caller setting; default True for The5ers-style funded withdrawals.
    funded_kwargs.setdefault("weekly_withdraw", True)
    funded_kwargs["rules"] = rules
    funded_bt = run_backtest(funded_data, **funded_kwargs)

    funded_survived = not funded_bt.account.blown and funded_bt.account.consistency_ok()
    funded_annual = float(funded_bt.stats.get("avg_annual_pnl", 0.0))

    return ChallengeReport(
        evaluation_passed=bool(eval_passed),
        funded_survived=bool(funded_survived),
        evaluation_days=evaluation_days,
        funded_annual_pnl=funded_annual,
        consistency_ok=bool(
            eval_bt.account.consistency_ok() and funded_bt.account.consistency_ok()
        ),
        details={
            "eval": eval_bt.to_dict(),
            "eval_stats": eval_bt.stats,
            "funded": funded_bt.to_dict(),
            "funded_stats": funded_bt.stats,
        },
    )


def rolling_eval_windows(
    data: dict[str, pd.DataFrame],
    start: str = "2018-01-01",
    end: str = "2023-12-31",
    window_days: int = 365,
    step_days: int = 90,
    **backtest_kwargs,
) -> list[dict]:
    """Walk evaluation attempts across calendar — estimates pass rate."""
    rules = backtest_kwargs.get("rules") or FundedRules()
    start_ts = pd.Timestamp(start)
    end_ts = pd.Timestamp(end)
    results = []
    cursor = start_ts
    while cursor + pd.Timedelta(days=window_days) <= end_ts:
        w_end = cursor + pd.Timedelta(days=window_days)
        slice_data = {
            p: df[(df.index >= cursor) & (df.index <= w_end)].copy() for p, df in data.items()
        }
        kwargs = dict(backtest_kwargs)
        kwargs["weekly_withdraw"] = False
        kwargs["rules"] = rules
        bt = run_backtest(slice_data, **kwargs)
        passed = (
            not bt.account.blown
            and bt.equity_curve.max() >= rules.evaluation_target
            and bt.account.consistency_ok()
        )
        results.append(
            {
                "start": str(cursor.date()),
                "end": str(w_end.date()),
                "passed": passed,
                "max_equity": float(bt.equity_curve.max()) if len(bt.equity_curve) else 0,
                "blown": bt.account.blown,
                "n_trades": len(bt.trades),
                "ann_pnl": bt.stats.get("avg_annual_pnl", 0),
            }
        )
        cursor += pd.Timedelta(days=step_days)
    return results
