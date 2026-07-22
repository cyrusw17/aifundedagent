#!/usr/bin/env python3
"""Compare strategies on DEV / VAL / 2026 with eval + funded weekly withdrawals."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import edge_stats, simulate_challenge
from strategy.config import (
    DEV_PERIOD,
    HOLD_2026,
    PARAMS,
    PROP,
    RESULTS_DIR,
    VAL_PERIOD,
)
from strategy.data_loader import load_universe
from strategy.strategies import STRATEGIES, STRATEGY_DESC


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
        "max_day_profit_share": round(res.max_day_profit_share, 4),
        "total_withdrawn": round(res.total_withdrawn, 2),
        "weekly_withdrawals": res.weekly_withdrawals,
        "total_made": round(res.total_made, 2),
        "pf": _pf(res.trades_df),
    }


def _pf(df: pd.DataFrame) -> float:
    if df is None or df.empty:
        return 0.0
    gains = float(df.loc[df.pnl > 0, "pnl"].sum())
    losses = float(-df.loc[df.pnl < 0, "pnl"].sum())
    if losses <= 1e-9:
        return 99.0 if gains > 0 else 0.0
    return round(gains / losses, 3)


def run_strategy(universe, name, fn) -> dict:
    print(f"\n======== {name} ========", flush=True)
    out = {"name": name, "description": STRATEGY_DESC[name], "windows": {}}

    for label, period in [
        ("dev_2024_2025", DEV_PERIOD),
        ("val_2023_2024", VAL_PERIOD),
        ("hold_2026", HOLD_2026),
    ]:
        print(f"  {label} challenge...", flush=True)
        chal = simulate_challenge(universe, period[0], period[1], signal_fn=fn)
        edge = edge_stats(universe, period[0], period[1], signal_fn=fn)
        block = {
            "edge": {
                "profit": round(edge.profit, 2),
                "pf": _pf(edge.trades_df),
                "win_rate": round(edge.win_rate, 4),
                "trades": edge.trades,
                "avg_trades_per_day": round(edge.avg_trades_per_day, 3),
                "max_dd": round(edge.max_dd, 2),
            },
            "evaluation": _brief(chal["evaluation"]) if "evaluation" in chal else None,
            "funded": _brief(chal["funded"]) if "funded" in chal else None,
        }
        out["windows"][label] = block
        ev = block["evaluation"]
        fu = block["funded"]
        print(
            f"    edge PnL={block['edge']['profit']} PF={block['edge']['pf']} | "
            f"eval pass={ev['passed']} days={ev['days_to_target']} | "
            f"funded withdrawn={(fu or {}).get('total_withdrawn')} "
            f"made={(fu or {}).get('total_made')}",
            flush=True,
        )
    return out


def is_winning(row: dict) -> bool:
    """Winning = passes eval on DEV, VAL, and 2026 holdout."""
    for k in ("dev_2024_2025", "val_2023_2024", "hold_2026"):
        ev = row["windows"][k]["evaluation"]
        if not (ev and ev["passed"]):
            return False
    return True


def main() -> None:
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    print("Loading universe...", flush=True)
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    for p, fr in universe.items():
        print(
            f"  {p}: {fr['m1'].index.min().date()} -> {fr['m1'].index.max().date()} "
            f"M15={len(fr['m15'])}",
            flush=True,
        )

    all_rows = []
    for name, fn in STRATEGIES.items():
        all_rows.append(run_strategy(universe, name, fn))

    winners = [r for r in all_rows if is_winning(r)]
    # If fewer than 5 winners, keep best by DEV+VAL eval pass then edge PF sum
    if len(winners) < 5:
        def score(r):
            w = r["windows"]
            s = 0
            for k in ("dev_2024_2025", "val_2023_2024", "hold_2026"):
                ev = w[k]["evaluation"]
                if ev and ev["passed"]:
                    s += 10
                s += w[k]["edge"]["pf"]
                fu = w[k]["funded"]
                if fu:
                    s += fu["total_made"] / 10000.0
            return s

        ranked = sorted(all_rows, key=score, reverse=True)
        winners = ranked[:5]

    # Side-by-side table
    rows = []
    for r in winners:
        for window, label in [
            ("dev_2024_2025", "2024-2025"),
            ("val_2023_2024", "2023-2024"),
            ("hold_2026", "2026 H1"),
        ]:
            w = r["windows"][window]
            ev, fu = w["evaluation"], w["funded"]
            rows.append(
                {
                    "strategy": r["name"],
                    "window": label,
                    "edge_pnl": w["edge"]["profit"],
                    "edge_pf": w["edge"]["pf"],
                    "eval_pass": ev["passed"] if ev else False,
                    "eval_days": ev["days_to_target"] if ev else None,
                    "eval_profit": ev["profit"] if ev else None,
                    "funded_survived": fu["passed"] if fu else False,
                    "funded_withdrawn": fu["total_withdrawn"] if fu else 0.0,
                    "funded_weeks_paid": fu["weekly_withdrawals"] if fu else 0,
                    "funded_total_made": fu["total_made"] if fu else 0.0,
                    "funded_end_equity": fu["end_equity"] if fu else None,
                    "trades_per_day": w["edge"]["avg_trades_per_day"],
                }
            )
    table = pd.DataFrame(rows)
    table.to_csv(out_dir / "comparison_table.csv", index=False)

    summary = {
        "prop": PROP.__dict__,
        "causality": {
            "m15_closed_bars_only": True,
            "swing_confirm_delay": "pivot+right",
            "h1_bias_shift": "1h",
            "london_range_used_only_after_12utc": True,
            "fills_after_signal_time_on_m1": True,
            "same_bar_sl_before_tp": True,
            "no_optimizer": True,
        },
        "funded_rule": "Each week, all equity above $101,000 is withdrawn (min $250).",
        "all_strategies": all_rows,
        "reported_winners": [r["name"] for r in winners],
    }
    with open(out_dir / "comparison_summary.json", "w") as f:
        json.dump(summary, f, indent=2, default=str)

    # Markdown report
    md = ["# Strategy Side-by-Side Comparison", ""]
    md.append("## Rules")
    md.append("- Eval: +$10k target, $6k max loss, $3k daily pause, 50% consistency")
    md.append("- Funded: weekly withdraw **all** equity above **$101,000** (min $250)")
    md.append("- No look-ahead / no curve-fit optimizer")
    md.append("")
    md.append("## Strategies")
    for r in winners:
        md.append(f"- **{r['name']}**: {r['description']}")
    md.append("")
    md.append("## Comparison table")
    md.append("")
    md.append(table.to_markdown(index=False))
    md.append("")
    md.append("## 2026 H1 highlight")
    md.append("")
    sub = table[table.window == "2026 H1"][
        [
            "strategy",
            "eval_pass",
            "eval_days",
            "funded_withdrawn",
            "funded_total_made",
            "edge_pf",
            "edge_pnl",
        ]
    ]
    md.append(sub.to_markdown(index=False))
    md.append("")
    path = out_dir / "COMPARISON.md"
    path.write_text("\n".join(md))
    print(f"\nWrote {path}")
    print(table.to_string(index=False))


if __name__ == "__main__":
    main()
