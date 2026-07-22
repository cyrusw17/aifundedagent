#!/usr/bin/env python3
"""Confirm high-return champion: static floor + causal fills."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import _simulate_limit_entry_and_exit, run_period
from strategy.config import PARAMS, PROP
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import FULL_2020_2025, TEST_LATE, TRAIN_EARLY, pf
from strategy.strategies.high_return import CHAMPION_ID, META, STRATEGIES, prop_params_for

FLOOR = PROP.initial_balance - PROP.max_loss


def eval_period(universe, fn, period, params):
    r = run_period(
        universe,
        period[0],
        period[1],
        fn,
        "prop",
        prop=PROP,
        params=params,
        stop_at_profit_target=False,
    )
    min_eq = float(r.equity_curve.min()) if len(r.equity_curve) else PROP.initial_balance
    years = (pd_years := __import__("strategy.run_cagr25_search", fromlist=["pd_years"]).pd_years)(
        period[0], period[1]
    )
    profit = float(r.profit)
    ann = profit / PROP.initial_balance / years * 100 if years else 0.0
    cagr = ((1 + profit / PROP.initial_balance) ** (1 / years) - 1) * 100 if years and profit > -PROP.initial_balance else float("nan")
    return {
        "floor_ok": min_eq > FLOOR and r.fail_reason != "max_loss",
        "min_eq": min_eq,
        "max_dd": r.max_dd,
        "profit": profit,
        "ann": ann,
        "cagr": cagr,
        "pf": pf(r.trades_df),
        "trades": r.trades,
        "end": r.end_equity,
    }


def main() -> int:
    print("=== Confirm high-return champion (static floor) ===\n")
    print(f"Floor=${FLOOR:,.0f}  (trailing DD may exceed $6k)\n")
    fn = STRATEGIES[CHAMPION_ID]
    params = prop_params_for()
    universe = load_universe(PARAMS.pairs)

    full = eval_period(universe, fn, FULL_2020_2025, params)
    early = eval_period(universe, fn, TRAIN_EARLY, params)
    late = eval_period(universe, fn, TEST_LATE, params)

    print(
        f"{CHAMPION_ID}: full ann={full['ann']:.2f}% cagr={full['cagr']:.2f}% "
        f"end=${full['end']:,.0f} dd=${full['max_dd']:,.0f} min=${full['min_eq']:,.0f} "
        f"pf={full['pf']} n={full['trades']} floor_ok={full['floor_ok']}"
    )
    print(f"  early: ann={early['ann']:.2f}% floor_ok={early['floor_ok']} min=${early['min_eq']:,.0f}")
    print(f"  late:  ann={late['ann']:.2f}% floor_ok={late['floor_ok']} min=${late['min_eq']:,.0f}")

    # look-ahead spot check
    m15 = universe["EURUSD"]["m15"]
    m1 = universe["EURUSD"]["m1"]
    sigs = [s for s in fn("EURUSD", m15, params) if str(s.time)[:4] == "2024"][:40]
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

    ok = (
        full["floor_ok"]
        and early["floor_ok"]
        and late["floor_ok"]
        and full["ann"] >= 10.0
        and full["pf"] >= 1.05
        and viol == 0
    )
    if not ok:
        print("\nFAIL")
        return 1
    print(f"\nPASS: {CHAMPION_ID} ≥10% ann, static-floor safe, no look-ahead")
    print(f"(meta expected ~{META[CHAMPION_ID]['simple_ann_pct']}% ann)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
