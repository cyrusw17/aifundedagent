#!/usr/bin/env python3
"""Fail the build if any trade fills before its signal is knowable."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import _simulate_limit_entry_and_exit
from strategy.common import pack_signal
from strategy.config import PARAMS
from strategy.data_loader import load_universe
from strategy.strategies.eq_liquidity_fade import generate_signals


def main() -> int:
    uni = load_universe(("EURUSD",), data_dir=ROOT / "data" / "raw")
    m15 = uni["EURUSD"]["m15"].loc["2024-01-01":"2024-03-31"]
    m1 = uni["EURUSD"]["m1"]
    sigs = generate_signals("EURUSD", m15, PARAMS)
    assert sigs, "expected some signals in sample window"

    violations = 0
    for s in sigs:
        assert s.knowable_at is not None, "signal missing knowable_at"
        assert s.knowable_at == s.time + pd_timedelta15(s), "knowable_at must be bar close"
        out = _simulate_limit_entry_and_exit(m1, s, PARAMS)
        if out is None:
            continue
        entry_time = out[0]
        if entry_time < s.knowable_at:
            print(f"VIOLATION {s.pair} {s.reason} entry={entry_time} knowable={s.knowable_at}")
            violations += 1

    # Explicit regression: filling from bar open must be impossible via API
    s0 = sigs[0]
    forged = pack_signal(
        s0.time, s0.pair, s0.side, s0.entry, s0.stop, s0.reward_risk, "forge"
    )
    assert forged is not None
    # If someone forces search from open by clearing knowable_at, engine still defaults to +15m
    forged.knowable_at = None
    out = _simulate_limit_entry_and_exit(m1, forged, PARAMS)
    if out is not None and out[0] < forged.time + pd_timedelta15(forged):
        print("VIOLATION: fill before default bar close when knowable_at cleared")
        violations += 1

    if violations:
        print(f"FAIL: {violations} look-ahead fill(s)")
        return 1
    print(f"OK: {len(sigs)} signals checked, zero fills before knowable_at")
    return 0


def pd_timedelta15(s) -> object:
    import pandas as pd

    return pd.Timedelta(minutes=getattr(s, "signal_tf_minutes", 15))


if __name__ == "__main__":
    raise SystemExit(main())
