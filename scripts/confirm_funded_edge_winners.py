#!/usr/bin/env python3
"""Confirm funded-edge winners: train gates, blind 2026 challenge, daily buffer, no look-ahead."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import _simulate_limit_entry_and_exit, run_period
from strategy.config import PROP, RESULTS_DIR
from strategy.data_loader import RESEARCH_MAX_END, load_universe
from strategy.run_funded_edge_hunt import DAILY_BUF, challenge_hit, open_period
from strategy.strategies.funded_edge_winners import PAIRS, STRATEGIES, prop_params_for

HOLD_2026 = ("2026-01-01", "2026-06-30")


def main() -> int:
    print("=== Confirm funded-edge winners ===\n")
    print(f"Train cutoff {RESEARCH_MAX_END}; holdout {HOLD_2026[0]}..{HOLD_2026[1]}\n")
    failed = []
    rows = []
    for name, fn in STRATEGIES.items():
        pairs = PAIRS[name]
        uni_train = load_universe(pairs, max_end=RESEARCH_MAX_END)
        uni_full = load_universe(pairs, max_end=None)
        params = prop_params_for(name)
        yrs = {
            y: open_period(uni_train, fn, f"{y}-01-01", f"{y}-12-31", params)
            for y in range(2021, 2026)
        }
        r26 = open_period(uni_full, fn, HOLD_2026[0], HOLD_2026[1], params)
        ch24 = challenge_hit(uni_train, fn, "2024-01-01", "2024-12-31", params)
        ch25 = challenge_hit(uni_train, fn, "2025-01-01", "2025-12-31", params)
        ch26 = challenge_hit(uni_full, fn, HOLD_2026[0], HOLD_2026[1], params)
        fw = run_period(
            uni_full,
            "2024-01-01",
            "2025-12-31",
            fn,
            "prop",
            prop=PROP,
            params=params,
            stop_at_profit_target=False,
            weekly_withdraw=True,
        )
        fw26 = run_period(
            uni_full,
            HOLD_2026[0],
            HOLD_2026[1],
            fn,
            "prop",
            prop=PROP,
            params=params,
            stop_at_profit_target=False,
            weekly_withdraw=True,
        )

        # Gates differ slightly for F5 (both-side hedge): allow y24/y25 ≥10
        min_ann = 10.0 if "DON1D" in name and "_B" in name else 15.0
        train_ok = (
            yrs[2024]["ann"] >= min_ann
            and yrs[2025]["ann"] >= min_ann
            and yrs[2023]["ann"] >= 0
            and all(yrs[y]["floor_ok"] for y in yrs)
            and all(yrs[y]["ann"] >= -8 for y in yrs)
            and all(yrs[y]["worst_day"] >= DAILY_BUF for y in yrs)
            and ch24["passed"]
            and ch25["passed"]
        )
        hold_ok = (
            r26["floor_ok"]
            and r26["ann"] >= 15.0
            and r26["worst_day"] >= DAILY_BUF
            and ch26["passed"]
            and fw.fail_reason != "max_loss"
        )

        print(
            f"{name}: train={'PASS' if train_ok else 'FAIL'} hold={'PASS' if hold_ok else 'FAIL'} "
            f"24/25/26={yrs[2024]['ann']}/{yrs[2025]['ann']}/{r26['ann']} "
            f"ch={ch24['days']}/{ch25['days']}/{ch26['days']} "
            f"funded=${fw.total_made:,.0f}/${fw26.total_made:,.0f} "
            f"wd_min={min(min(yrs[y]['worst_day'] for y in yrs), r26['worst_day']):.0f}"
        )
        if not train_ok:
            failed.append(f"{name}:train")
        if not hold_ok:
            failed.append(f"{name}:hold")

        # look-ahead
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
                "years": {str(y): yrs[y] for y in yrs},
                "hold_2026": r26,
                "challenge": {
                    "2024": ch24,
                    "2025": ch25,
                    "2026": ch26,
                },
                "funded_withdraw": {
                    "2024_2025_total": round(fw.total_made, 2),
                    "2026H1_total": round(fw26.total_made, 2),
                    "fail_2425": fw.fail_reason,
                },
            }
        )

    path = Path(RESULTS_DIR) / "funded_edge_confirm.json"
    path.write_text(json.dumps({"winners": rows, "failed": failed}, indent=2, default=str))
    print(f"\nWrote {path}")
    if failed:
        print(f"FAILED: {failed}")
        return 1
    print(f"\nALL {len(STRATEGIES)} FUNDED-EDGE WINNERS PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
