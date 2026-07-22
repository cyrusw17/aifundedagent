#!/usr/bin/env python3
"""Fail the build if any trade fills before its signal is knowable.

Triple-check coverage:
- EQ fade (classic wick look-ahead regression)
- H1 Donchian (60m knowable_at)
- Daily swing (1440m knowable_at)
- ANN10 / ICT SB pack_signal paths
- S5 dual merge preserves knowable_at
- Engine rejects missing / forged-early knowable_at
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import pandas as pd

from strategy.backtest import _simulate_limit_entry_and_exit
from strategy.common import pack_signal
from strategy.config import PARAMS
from strategy.data_loader import load_universe
from strategy.strategies.ann10_winners import STRATEGIES as ANN10
from strategy.strategies.eq_liquidity_fade import generate_signals as gen_eq
from strategy.strategies.h1_models import H1Cfg, make_fn as make_h1
from strategy.strategies.ote_pullback import generate_signals as gen_s5
from strategy.strategies.swing_retail import SwingCfg, make_swing_fn as make_swing


def _tf_delta(s) -> pd.Timedelta:
    return pd.Timedelta(minutes=int(getattr(s, "signal_tf_minutes", 15) or 15))


def _check_signals(label: str, sigs, m1, *, expect_tf: int | None = None) -> int:
    assert sigs, f"{label}: expected some signals"
    violations = 0
    for s in sigs:
        if s.knowable_at is None:
            print(f"VIOLATION {label}: missing knowable_at {s.reason} {s.time}")
            violations += 1
            continue
        expected = s.time + _tf_delta(s)
        if expect_tf is not None and int(s.signal_tf_minutes) != expect_tf:
            print(
                f"VIOLATION {label}: tf={s.signal_tf_minutes} expected {expect_tf} "
                f"{s.reason} {s.time}"
            )
            violations += 1
        if abs((s.knowable_at - expected).total_seconds()) > 1:
            print(
                f"VIOLATION {label}: knowable_at {s.knowable_at} != bar close {expected} "
                f"{s.reason}"
            )
            violations += 1
        out = _simulate_limit_entry_and_exit(m1, s, PARAMS)
        if out is None:
            continue
        entry_time = out[0]
        if entry_time < s.knowable_at:
            print(
                f"VIOLATION {label}: entry {entry_time} < knowable {s.knowable_at} "
                f"{s.pair} {s.reason}"
            )
            violations += 1
        # Structural: fill must not use M1 bars strictly inside the signal TF window
        last_inside = s.time + _tf_delta(s) - pd.Timedelta(minutes=1)
        if entry_time <= last_inside:
            print(
                f"VIOLATION {label}: entry {entry_time} inside signal bar "
                f"[{s.time}, {s.knowable_at}) {s.reason}"
            )
            violations += 1
    print(f"  {label}: {len(sigs)} signals, checked fills OK" if not violations else f"  {label}: FAIL")
    return violations


def main() -> int:
    uni = load_universe(("EURUSD",), data_dir=ROOT / "data" / "raw")
    m15 = uni["EURUSD"]["m15"].loc["2024-01-01":"2024-03-31"]
    m1 = uni["EURUSD"]["m1"]
    violations = 0

    print("=== Assert no look-ahead (multi-TF + engine guards) ===\n")

    # 1) Classic M15 equal-fade
    sigs = gen_eq("EURUSD", m15, PARAMS)
    violations += _check_signals("EQ_fade_M15", sigs, m1, expect_tf=15)

    # 2) H1 Donchian
    h1_fn = make_h1(
        H1Cfg(tag="assert_don", model="don_h1", don_len=20, rr=3.0, session_only=True)
    )
    violations += _check_signals("H1_Donchian", h1_fn("EURUSD", m15, PARAMS), m1, expect_tf=60)

    # 3) Daily swing
    sw_fn = make_swing(SwingCfg(tag="assert_don_d", model="don_daily", don_len=20, rr=3.0))
    m15_year = uni["EURUSD"]["m15"].loc["2023-01-01":"2024-12-31"]
    violations += _check_signals(
        "Daily_Donchian", sw_fn("EURUSD", m15_year, PARAMS), m1, expect_tf=1440
    )

    # 4) ANN10 ICT + H1 sample
    for name, fn in list(ANN10.items())[:3]:
        sample = [s for s in fn("EURUSD", m15, PARAMS) if str(s.time)[:4] == "2024"][:40]
        if not sample:
            sample = fn("EURUSD", m15_year, PARAMS)[:40]
        violations += _check_signals(f"ANN10_{name}", sample, m1)

    # 5) S5 must preserve knowable_at
    s5 = gen_s5("EURUSD", m15, PARAMS)
    missing = sum(1 for s in s5 if s.knowable_at is None)
    if missing:
        print(f"VIOLATION S5: {missing}/{len(s5)} signals missing knowable_at")
        violations += missing
    else:
        violations += _check_signals("S5_dual", s5[:80], m1, expect_tf=15)

    # 6) Engine must reject cleared knowable_at
    s0 = sigs[0]
    forged = pack_signal(s0.time, s0.pair, s0.side, s0.entry, s0.stop, s0.reward_risk, "forge")
    assert forged is not None
    forged.knowable_at = None
    try:
        _simulate_limit_entry_and_exit(m1, forged, PARAMS)
        print("VIOLATION: engine accepted missing knowable_at")
        violations += 1
    except RuntimeError as e:
        if "missing knowable_at" not in str(e):
            print(f"VIOLATION: wrong error for missing knowable_at: {e}")
            violations += 1
        else:
            print("  engine_reject_missing_knowable_at: OK")

    # 7) Engine must reject forged-early knowable_at (fill-during-signal-bar class)
    forged2 = pack_signal(s0.time, s0.pair, s0.side, s0.entry, s0.stop, s0.reward_risk, "forge_early")
    assert forged2 is not None
    forged2.knowable_at = forged2.time  # bar open — classic look-ahead forge
    try:
        _simulate_limit_entry_and_exit(m1, forged2, PARAMS)
        print("VIOLATION: engine accepted forged-early knowable_at")
        violations += 1
    except RuntimeError as e:
        if "earlier than" not in str(e) and "LOOK-AHEAD" not in str(e):
            print(f"VIOLATION: wrong error for early knowable_at: {e}")
            violations += 1
        else:
            print("  engine_reject_early_knowable_at: OK")

    # 8) Static: ban raw Signal( constructions outside pack_signal (heuristic)
    strat_dir = ROOT / "strategy" / "strategies"
    raw_hits = []
    for p in strat_dir.glob("*.py"):
        text = p.read_text()
        # allow Signal imports / type hints; flag constructor calls that are not pack_signal
        for i, line in enumerate(text.splitlines(), 1):
            if "Signal(" in line and "pack_signal" not in line and "Optional[Signal]" not in line:
                if "from" in line or "import" in line or "List[Signal]" in line:
                    continue
                # ote_pullback rebuild is allowed only if it copies knowable_at (checked above)
                if p.name == "ote_pullback.py":
                    continue
                raw_hits.append(f"{p.name}:{i}: {line.strip()}")
    if raw_hits:
        print("VIOLATION: raw Signal( constructions outside pack_signal:")
        for h in raw_hits:
            print(f"  {h}")
        violations += len(raw_hits)
    else:
        print("  raw_Signal_ban: OK")

    if violations:
        print(f"\nFAIL: {violations} look-ahead issue(s)")
        return 1
    print("\nOK: multi-TF signals + engine guards — zero look-ahead fills")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
