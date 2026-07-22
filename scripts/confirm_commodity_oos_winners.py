#!/usr/bin/env python3
"""Confirm OOS commodity winners: train gates + blind 2026 + no look-ahead."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import _simulate_limit_entry_and_exit
from strategy.config import RESULTS_DIR
from strategy.data_loader import RESEARCH_MAX_END, load_universe
from strategy.run_commodity_oos_filter import HOLD_2026, ok_2026, ok_train
from strategy.run_commodity_search import run, year_period
from strategy.strategies.commodity_oos_winners import PAIRS, STRATEGIES, prop_params_for

TRAIN_YEARS = ("2021", "2022", "2023", "2024", "2025")


def main() -> int:
    print("=== Confirm commodity OOS winners (train 24/25, blind 2026) ===\n")
    if len(STRATEGIES) < 5:
        print(f"FAIL: only {len(STRATEGIES)} strategies")
        return 1

    failed = []
    rows = []
    for name, fn in STRATEGIES.items():
        pairs = PAIRS[name]
        uni_train = load_universe(pairs, max_end=RESEARCH_MAX_END)
        for p, fr in uni_train.items():
            if fr["m1"].index.max().year > 2025:
                print(f"FAIL {name}: train leak on {p}")
                return 1
        params = prop_params_for(name)
        yrs = {y: run(uni_train, fn, year_period(y), params) for y in TRAIN_YEARS}
        train_ok = ok_train(yrs)
        # Blind 2026 on full data
        uni_full = load_universe(pairs, max_end=None)
        r26 = run(uni_full, fn, HOLD_2026, params)
        hold_ok = ok_2026(r26)
        print(
            f"{name}: train={'PASS' if train_ok else 'FAIL'} "
            f"21={yrs['2021']['ann']}% 22={yrs['2022']['ann']}% 23={yrs['2023']['ann']}% "
            f"24={yrs['2024']['ann']}% 25={yrs['2025']['ann']}% | "
            f"2026H1_ann={r26['ann']}% pf={r26['pf']} n={r26['trades']} "
            f"hold={'PASS' if hold_ok else 'FAIL'}"
        )
        if not train_ok:
            failed.append(f"{name}:train")
        if not hold_ok:
            failed.append(f"{name}:2026")

        # look-ahead check on 2024 signals
        pair0 = pairs[0]
        m15 = uni_train[pair0]["m15"]
        m1 = uni_train[pair0]["m1"]
        sigs = [s for s in fn(pair0, m15, params) if str(s.time)[:4] == "2024"][:40]
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

        rows.append(
            {
                "id": name,
                "train_ok": train_ok,
                "hold_ok": hold_ok,
                "years": {y: yrs[y] for y in TRAIN_YEARS},
                "hold_2026": r26,
            }
        )

    out_path = Path(RESULTS_DIR) / "commodity_oos_confirm.json"
    out_path.write_text(json.dumps({"winners": rows, "failed": failed}, indent=2, default=str))
    print(f"\nWrote {out_path}")

    if failed:
        print(f"\nFAILED: {failed}")
        return 1
    print(f"\nALL {len(STRATEGIES)} OOS WINNERS PASS (train + 2026 + no look-ahead)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
