#!/usr/bin/env python3
"""Causal strategy comparison — DEV 2024-25, VAL 2023, HOLD 2026.

All fills enforced after knowable_at. No parameter optimizer.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import edge_stats, simulate_challenge
from strategy.config import DEV_PERIOD, HOLD_2026, PARAMS, PURE_OOS, RESULTS_DIR, VAL_PERIOD
from strategy.data_loader import load_universe
from strategy.strategies import STRATEGIES, STRATEGY_DESC


def _pf(df) -> float:
    if df is None or df.empty:
        return 0.0
    g = float(df.loc[df.pnl > 0, "pnl"].sum())
    l = float(-df.loc[df.pnl < 0, "pnl"].sum())
    if l <= 1e-9:
        return 99.0 if g > 0 else 0.0
    return round(g / l, 3)


def _brief(res) -> dict:
    return {
        "passed": res.passed,
        "fail_reason": res.fail_reason,
        "profit": round(res.profit, 2),
        "end_equity": round(res.end_equity, 2),
        "max_dd": round(res.max_dd, 2),
        "trades": res.trades,
        "win_rate": round(res.win_rate, 4),
        "avg_trades_per_day": round(res.avg_trades_per_day, 3),
        "days_to_target": res.days_to_target,
        "consistency_ok": res.consistency_ok,
        "total_withdrawn": round(res.total_withdrawn, 2),
        "weekly_withdrawals": res.weekly_withdrawals,
        "total_made": round(res.total_made, 2),
        "pf": _pf(res.trades_df),
    }


WINDOWS = [
    ("dev_2024_2025", DEV_PERIOD),  # develop / train window
    ("pure_oos_2023", PURE_OOS),
    ("val_2023_2024", VAL_PERIOD),
    ("hold_2026", HOLD_2026),
]


def is_winning(row: dict) -> bool:
    """Pass eval on develop + pure 2023 + 2026 holdout (strict)."""
    for k in ("dev_2024_2025", "pure_oos_2023", "hold_2026"):
        ev = row["windows"].get(k, {}).get("evaluation")
        if not (ev and ev["passed"]):
            return False
    return True


def main() -> None:
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Assert no look-ahead...", flush=True)
    from scripts.assert_no_lookahead import main as guard

    if guard() != 0:
        raise SystemExit("look-ahead guard failed")

    print("Loading universe...", flush=True)
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    for p, fr in universe.items():
        print(
            f"  {p}: {fr['m1'].index.min().date()} -> {fr['m1'].index.max().date()}",
            flush=True,
        )

    rows = []
    for name, fn in STRATEGIES.items():
        print(f"\n======== {name} ========", flush=True)
        block = {"name": name, "description": STRATEGY_DESC[name], "windows": {}}
        for label, period in WINDOWS:
            print(f"  {label}...", flush=True)
            chal = simulate_challenge(universe, period[0], period[1], signal_fn=fn)
            edge = edge_stats(universe, period[0], period[1], signal_fn=fn)
            block["windows"][label] = {
                "edge": {
                    "profit": round(edge.profit, 2),
                    "pf": _pf(edge.trades_df),
                    "win_rate": round(edge.win_rate, 4),
                    "trades": edge.trades,
                    "avg_trades_per_day": round(edge.avg_trades_per_day, 3),
                    "max_dd": round(edge.max_dd, 2),
                },
                "evaluation": _brief(chal["evaluation"]),
                "funded": _brief(chal["funded"]) if "funded" in chal else None,
            }
            ev = block["windows"][label]["evaluation"]
            ed = block["windows"][label]["edge"]
            print(
                f"    edge {ed['profit']:+.0f} PF={ed['pf']} | "
                f"eval pass={ev['passed']} days={ev['days_to_target']} "
                f"({ev['fail_reason']})",
                flush=True,
            )
        rows.append(block)

    winners = [r for r in rows if is_winning(r)]
    summary = {
        "causal": True,
        "fill_rule": "knowable_at = bar close; no fill before",
        "develop": list(DEV_PERIOD),
        "strategies": rows,
        "winners": [w["name"] for w in winners],
    }
    (out_dir / "causal_comparison.json").write_text(json.dumps(summary, indent=2))

    # Markdown report
    lines = [
        "# Causal strategy comparison (no look-ahead)",
        "",
        "**Fill law:** `entry_time >= signal.knowable_at` (M15 bar close).",
        f"**Develop / train window:** {DEV_PERIOD[0]} → {DEV_PERIOD[1]}",
        f"**Pure OOS:** {PURE_OOS[0]} → {PURE_OOS[1]}",
        f"**Holdout:** {HOLD_2026[0]} → {HOLD_2026[1]}",
        "",
        "No parameter grid search. Fixed a-priori params in `strategy/config.py`.",
        "",
        "## Edge PnL (full window, causal fills)",
        "",
        "| Strategy | 2024–25 PF / PnL | 2023 PF / PnL | 2026 H1 PF / PnL |",
        "| --- | ---: | ---: | ---: |",
    ]
    for r in rows:
        d = r["windows"]["dev_2024_2025"]["edge"]
        o = r["windows"]["pure_oos_2023"]["edge"]
        h = r["windows"]["hold_2026"]["edge"]
        lines.append(
            f"| {r['name']} | {d['pf']:.2f} / {d['profit']:+.0f} | "
            f"{o['pf']:.2f} / {o['profit']:+.0f} | {h['pf']:.2f} / {h['profit']:+.0f} |"
        )

    lines += [
        "",
        "## Eval pass (+$10k, The5ers rules)",
        "",
        "| Strategy | DEV 24–25 | OOS 2023 | HOLD 2026 | Winner |",
        "| --- | --- | --- | --- | --- |",
    ]
    for r in rows:
        cells = []
        for k in ("dev_2024_2025", "pure_oos_2023", "hold_2026"):
            ev = r["windows"][k]["evaluation"]
            cells.append("PASS" if ev["passed"] else f"FAIL({ev['fail_reason']})")
        win = "YES" if r["name"] in summary["winners"] else "no"
        lines.append(f"| {r['name']} | {cells[0]} | {cells[1]} | {cells[2]} | {win} |")

    lines += [
        "",
        f"## Winners (pass DEV + 2023 + 2026): {', '.join(summary['winners']) or '*(none)*'}",
        "",
        "See `LOOKAHEAD_FILL_BUG.md` / `NO_LOOKAHEAD.md` for why old S1–S6 green numbers are invalid.",
        "",
    ]
    (out_dir / "CAUSAL_COMPARISON.md").write_text("\n".join(lines))
    print("\nWinners:", summary["winners"] or "(none)")
    print("Wrote results/CAUSAL_COMPARISON.md")


if __name__ == "__main__":
    main()
