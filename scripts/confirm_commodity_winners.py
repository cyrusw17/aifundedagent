#!/usr/bin/env python3
"""Confirm ≥5 commodity winners: 2024/25 ≥10%, consistency gates, no 2026, no look-ahead."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import _simulate_limit_entry_and_exit
from strategy.config import PROP
from strategy.data_loader import RESEARCH_MAX_END, load_universe
from strategy.run_commodity_search import YEARS, eval_years, is_winner
from strategy.strategies.commodity_winners import PAIRS, STRATEGIES, prop_params_for

FLOOR = PROP.initial_balance - PROP.max_loss


def main() -> int:
    print("=== Confirm commodity winners ===\n")
    print(f"Research cutoff: {RESEARCH_MAX_END} (no 2026+ data)\n")
    if len(STRATEGIES) < 5:
        print(f"FAIL: only {len(STRATEGIES)} strategies")
        return 1

    failed = []
    for name, fn in STRATEGIES.items():
        pairs = PAIRS[name]
        universe = load_universe(pairs, max_end=RESEARCH_MAX_END)
        for p, fr in universe.items():
            if fr["m1"].index.max().year > 2025:
                print(f"FAIL {name}: future data on {p}")
                return 1
        params = prop_params_for(name)
        ev = eval_years(universe, fn, params)
        ok = is_winner(ev)
        y = ev["years"]
        print(
            f"{name}: {'PASS' if ok else 'FAIL'} "
            f"21={y['2021']['ann']}% 22={y['2022']['ann']}% 23={y['2023']['ann']}% "
            f"24={y['2024']['ann']}% 25={y['2025']['ann']}% "
            f"pf2425={ev['w2425']['pf']} floor={ev['w2425']['floor_ok']}"
        )
        if not ok:
            failed.append(name)
            continue
        # look-ahead spot check on first pair
        pair0 = pairs[0]
        m15 = universe[pair0]["m15"]
        m1 = universe[pair0]["m1"]
        sigs = [s for s in fn(pair0, m15, params) if str(s.time)[:4] == "2024"][:30]
        viol = 0
        checked = 0
        for s in sigs:
            assert s.knowable_at is not None
            assert s.knowable_at.year <= 2025
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
    print(f"\nALL {len(STRATEGIES)} COMMODITY WINNERS PASS (2024/25≥10%, no 2026, no look-ahead)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
