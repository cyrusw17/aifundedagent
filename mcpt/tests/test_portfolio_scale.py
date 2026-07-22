"""Smoke tests for scale-in portfolio simulator."""

from __future__ import annotations

import numpy as np
import pandas as pd

from mcpt.forex.portfolio_scale import simulate_monthly_scale, simulate_scale


def _synth_book(n: int = 2500, seed: int = 1) -> dict[str, pd.DataFrame]:
    rng = np.random.default_rng(seed)
    idx = pd.date_range("2024-01-01", periods=n, freq="h")
    book = {}
    for pair, px0 in [("EURUSD", 1.10), ("GBPUSD", 1.25)]:
        rets = rng.normal(0, 0.0004, size=n)
        close = px0 * np.exp(np.cumsum(rets))
        high = close * (1 + rng.uniform(0, 0.0005, n))
        low = close * (1 - rng.uniform(0, 0.0005, n))
        open_ = np.roll(close, 1)
        open_[0] = px0
        book[pair] = pd.DataFrame(
            {"open": open_, "high": high, "low": low, "close": close}, index=idx
        )
    return book


PARAMS = {
    "signal_mode": "sweep_bos_ob",
    "risk_pct": 0.0065,
    "rr": 1.8,
    "atr_stop_mult": 1.5,
    "max_positions": 1,
    "min_confluence": 2,
    "swing_left": 3,
    "swing_right": 3,
    "require_killzone": False,
    "move_be_at_r": 0.0,
    "skip_mondays": False,
    "daily_halt_loss_pct": 0.025,
    "daily_halt_profit_pct": 0.04,
    "cooldown_losses": 2,
    "one_entry_per_day": False,
}


def test_monthly_scale_runs():
    book = _synth_book()
    report = simulate_monthly_scale(
        book,
        PARAMS,
        start="2024-01-01",
        end="2024-03-31",
        eval_max_days=60,
        warmup_start="2024-01-01",
    )
    assert report.summary["accounts_started"] >= 3
    assert len(report.monthly) == 3
    assert "total_payouts_usd" in report.summary


def test_biweekly_capped_respects_caps():
    book = _synth_book(n=4000)
    report = simulate_scale(
        book,
        PARAMS,
        start="2024-01-01",
        end="2024-06-30",
        eval_max_days=60,
        start_every_days=14,
        max_concurrent_evals=5,
        max_concurrent_funded=5,
        warmup_start="2024-01-01",
    )
    assert report.config["max_concurrent_evals"] == 5
    assert report.config["max_concurrent_funded"] == 5
    assert report.summary["peak_evals_concurrent"] <= 5
    assert report.summary["peak_funded_concurrent"] <= 5
    assert "starts_skipped_eval_cap" in report.summary
