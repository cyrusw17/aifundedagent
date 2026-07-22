#!/usr/bin/env python3
"""Confirm ANN10 winners are The5ers prop-floor safe (causal fills)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import _simulate_limit_entry_and_exit, run_period
from strategy.config import PARAMS, PROP
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import FULL_2020_2025, TRAIN_EARLY, TEST_LATE, pf
from strategy.strategies.ann10_winners import (
    ANN10_H1,
    ANN10_ICT,
    ANN10_HALTS,
    STRATEGIES,
    prop_params_for,
)


def main() -> int:
    print("=== Confirm prop-floor-safe ANN10 winners ===\n")
    print(f"Floor=${PROP.initial_balance - PROP.max_loss:,.0f}  daily=${PROP.daily_loss_limit:,.0f}\n")
    universe = load_universe(PARAMS.pairs)
    failed = []
    floor = PROP.initial_balance - PROP.max_loss

    for name in list(ANN10_H1) + list(ANN10_ICT):
        fn = STRATEGIES[name]
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
        ok = floor_ok and dd_ok
        print(
            f"{name}: {'PASS' if ok else 'FAIL'} floor_ok={floor_ok} dd_ok={dd_ok} "
            f"dd=${r.max_dd:,.0f} min_eq=${min_eq:,.0f} ann={ann:.2f}% "
            f"PF={pf(r.trades_df)} n={r.trades} halt=${ANN10_HALTS[name]:,.0f} "
            f"risk={params.risk_pct*100:.2f}%"
        )
        if not ok:
            failed.append(name)

        # early/late floor check
        for label, period in (("early", TRAIN_EARLY), ("late", TEST_LATE)):
            rr = run_period(
                universe, period[0], period[1], fn, "prop", prop=PROP, params=params,
                stop_at_profit_target=False,
            )
            me = float(rr.equity_curve.min()) if len(rr.equity_curve) else PROP.initial_balance
            fok = me > floor and rr.fail_reason != "max_loss"
            dok = rr.max_dd <= PROP.max_loss + 1e-6
            print(f"  {label}: floor_ok={fok} dd_ok={dok} dd=${rr.max_dd:,.0f}")
            if not fok or not dok:
                failed.append(f"{name}_{label}")

        # look-ahead spot check
        m15 = universe["EURUSD"]["m15"]
        m1 = universe["EURUSD"]["m1"]
        sigs = [s for s in fn("EURUSD", m15, params) if str(s.time)[:4] == "2024"][:25]
        viol = checked = 0
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
            failed.append(name + "_LA")

    print()
    if failed:
        print("FAILED:", sorted(set(failed)))
        return 1
    print("ALL FIVE WINNERS PROP-FLOOR SAFE (max_dd<=$6k, never hit floor, no look-ahead)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
