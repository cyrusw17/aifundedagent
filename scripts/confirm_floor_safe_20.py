#!/usr/bin/env python3
"""Confirm all floor_safe_20 registry strategies under PROP + no look-ahead."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import _simulate_limit_entry_and_exit, run_period
from strategy.config import PARAMS, PROP
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import FULL_2020_2025, TEST_LATE, TRAIN_EARLY, pf
from strategy.strategies.floor_safe_20 import HALTS, STRATEGIES, prop_params_for


def main() -> int:
    print("=== Confirm 20 prop-floor-safe winners ===\n")
    print(f"Floor=${PROP.initial_balance - PROP.max_loss:,.0f}  daily=${PROP.daily_loss_limit:,.0f}\n")
    if len(STRATEGIES) < 20:
        print(f"FAIL: registry has {len(STRATEGIES)} strategies, need 20")
        return 1
    universe = load_universe(PARAMS.pairs)
    floor = PROP.initial_balance - PROP.max_loss
    failed = []
    for name, fn in STRATEGIES.items():
        params = prop_params_for(name)
        r = run_period(
            universe,
            FULL_2020_2025[0],
            FULL_2020_2025[1],
            fn,
            "prop",
            prop=PROP,
            params=params,
            stop_at_profit_target=False,
        )
        min_eq = float(r.equity_curve.min()) if len(r.equity_curve) else PROP.initial_balance
        floor_ok = min_eq > floor and r.fail_reason != "max_loss"
        dd_ok = r.max_dd <= PROP.max_loss + 1e-6
        profit = r.profit
        ann = profit / PROP.initial_balance / 6 * 100
        ok = floor_ok and dd_ok and profit > 0 and pf(r.trades_df) >= 1.05
        print(
            f"{name}: {'PASS' if ok else 'FAIL'} floor_ok={floor_ok} dd_ok={dd_ok} "
            f"dd=${r.max_dd:,.0f} ann={ann:.2f}% PF={pf(r.trades_df)} n={r.trades} "
            f"halt=${HALTS[name]:,.0f} risk={params.risk_pct*100:.2f}%"
        )
        if not ok:
            failed.append(name)
            continue
        for label, period in (("early", TRAIN_EARLY), ("late", TEST_LATE)):
            rr = run_period(
                universe, period[0], period[1], fn, "prop", prop=PROP, params=params, stop_at_profit_target=False
            )
            me = float(rr.equity_curve.min()) if len(rr.equity_curve) else PROP.initial_balance
            fok = me > floor and rr.fail_reason != "max_loss"
            dok = rr.max_dd <= PROP.max_loss + 1e-6
            print(f"  {label}: floor_ok={fok} dd_ok={dok} dd=${rr.max_dd:,.0f}")
            if not (fok and dok):
                failed.append(f"{name}:{label}")
        # look-ahead spot check
        m15 = universe["EURUSD"]["m15"]
        m1 = universe["EURUSD"]["m1"]
        sigs = [s for s in fn("EURUSD", m15, params) if str(s.time)[:4] == "2024"][:25]
        viol = 0
        checked = 0
        for s in sigs:
            assert s.knowable_at is not None
            out = _simulate_limit_entry_and_exit(m1, s, params)
            if out is None:
                continue
            checked += 1
            if out[0] < s.knowable_at:
                viol += 1
        print(f"  lookahead: {checked} fills, {viol} violations")
        if viol:
            failed.append(f"{name}:lookahead")

    if failed:
        print(f"\nFAILED: {failed}")
        return 1
    print(f"\nALL {len(STRATEGIES)} WINNERS PROP-FLOOR SAFE (max_dd<=$6k, never hit floor, no look-ahead)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
