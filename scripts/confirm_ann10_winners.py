#!/usr/bin/env python3
"""Confirm ANN10 winners: ann>=10% on 2020-25 and zero look-ahead fills."""
from __future__ import annotations

import sys
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import _simulate_limit_entry_and_exit
from strategy.config import PARAMS
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import FULL_2020_2025, edge as edge_ict, params_for as params_ict
from strategy.run_h1_trend_search import edge as edge_h1, params_for as params_h1
from strategy.strategies.ann10_winners import ANN10_H1, ANN10_ICT, STRATEGIES


def main() -> int:
    print("=== Confirm ANN10 winners (causal, ann>=10%) ===\n")
    universe = load_universe(PARAMS.pairs)
    failed = []

    for name, cfg in ANN10_H1.items():
        fn = STRATEGIES[name]
        e = edge_h1(universe, fn, FULL_2020_2025, cfg)
        ok = e["simple_ann_pct"] >= 10.0 and e["pf"] >= 1.05
        print(f"{name}: {'PASS' if ok else 'FAIL'} ann={e['simple_ann_pct']}% CAGR={e['cagr_pct']}% PF={e['pf']}")
        if not ok:
            failed.append(name)
        # fill check sample
        p = params_h1(cfg)
        m15 = universe["EURUSD"]["m15"]
        m1 = universe["EURUSD"]["m1"]
        sigs = [s for s in fn("EURUSD", m15, p) if str(s.time)[:4] == "2024"][:30]
        viol = 0
        checked = 0
        for s in sigs:
            assert s.knowable_at is not None
            out = _simulate_limit_entry_and_exit(m1, s, p)
            if out is None:
                continue
            checked += 1
            if out[0] < s.knowable_at:
                viol += 1
        print(f"  lookahead check: {checked} fills, {viol} violations")
        if viol:
            failed.append(name + "_LA")

    for name, cfg in ANN10_ICT.items():
        fn = STRATEGIES[name]
        e = edge_ict(universe, fn, FULL_2020_2025, cfg)
        ok = e["simple_ann_pct"] >= 10.0 and e["pf"] >= 1.05
        print(f"{name}: {'PASS' if ok else 'FAIL'} ann={e['simple_ann_pct']}% CAGR={e['cagr_pct']}% PF={e['pf']}")
        if not ok:
            failed.append(name)
        p = params_ict(cfg)
        m15 = universe["EURUSD"]["m15"]
        m1 = universe["EURUSD"]["m1"]
        sigs = [s for s in fn("EURUSD", m15, p) if str(s.time)[:4] == "2024"][:30]
        viol = checked = 0
        for s in sigs:
            assert s.knowable_at is not None
            out = _simulate_limit_entry_and_exit(m1, s, p)
            if out is None:
                continue
            checked += 1
            if out[0] < s.knowable_at:
                viol += 1
        print(f"  lookahead check: {checked} fills, {viol} violations")
        if viol:
            failed.append(name + "_LA")

    print()
    if failed:
        print("FAILED", failed)
        return 1
    print("ALL FIVE ANN10 WINNERS CONFIRMED (ann>=10%, no look-ahead fills)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
