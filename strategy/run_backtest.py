#!/usr/bin/env python3
"""Run development (2024-2025) and validation (2023-2024) challenge sims."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period, simulate_challenge
from strategy.config import DEV_PERIOD, PARAMS, PROP, PURE_OOS, RESULTS_DIR, VAL_PERIOD
from strategy.data_loader import load_universe


def _result_to_dict(res) -> dict:
    return {
        "phase": res.phase,
        "passed": res.passed,
        "fail_reason": res.fail_reason,
        "start_equity": res.start_equity,
        "end_equity": res.end_equity,
        "profit": round(res.profit, 2),
        "max_dd": round(res.max_dd, 2),
        "trades": res.trades,
        "win_rate": round(res.win_rate, 4),
        "avg_trades_per_day": round(res.avg_trades_per_day, 3),
        "trading_days": res.trading_days,
        "days_to_target": res.days_to_target,
        "consistency_ok": res.consistency_ok,
        "max_day_profit_share": round(res.max_day_profit_share, 4),
        "daily_pauses": res.daily_pauses,
    }


def edge_report(universe, start, end, label: str) -> dict:
    """Full-period stats without stopping at profit target (expectancy check)."""
    # Monkey: temporarily huge profit target via copy of rules — use run_period but
    # we need unlimited target. Implement lightweight by calling run_period with
    # mutated prop through a simple subclass pattern.
    from dataclasses import replace
    from strategy.config import PropRules

    loose = replace(PROP, profit_target=10_000_000.0, consistency_pct=1.0)
    res = run_period(universe, start, end, phase_name=label, prop=loose, params=PARAMS)
    df = res.trades_df
    out = _result_to_dict(res)
    if df is not None and len(df):
        out["total_pnl"] = round(float(df["pnl"].sum()), 2)
        out["avg_pnl"] = round(float(df["pnl"].mean()), 2)
        out["median_pnl"] = round(float(df["pnl"].median()), 2)
        out["profit_factor"] = round(
            float(df.loc[df.pnl > 0, "pnl"].sum() / max(1e-9, -df.loc[df.pnl < 0, "pnl"].sum())),
            3,
        )
        out["avg_r"] = round(float(df["r_multiple"].mean()), 3)
        by_pair = df.groupby("pair")["pnl"].agg(["count", "sum", "mean"]).round(2)
        out["by_pair"] = by_pair.to_dict()
    return out, res


def main() -> None:
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Loading universe...")
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    for p, fr in universe.items():
        print(f"  {p}: M1={len(fr['m1'])} M15={len(fr['m15'])} "
              f"{fr['m1'].index.min()} -> {fr['m1'].index.max()}")

    summary = {
        "prop": PROP.__dict__,
        "params": {
            k: (list(v) if isinstance(v, tuple) else v)
            for k, v in PARAMS.__dict__.items()
            if k not in ("spreads", "contract_sizes")
        },
        "spreads": PARAMS.spreads,
        "methodology": {
            "no_lookahead": True,
            "no_curve_fit": True,
            "signal_tf": "M15",
            "fill_tf": "M1",
            "model": "ICT sweep -> MSS -> FVG limit mid, RR=2, killzones London/NY",
            "dev_period": DEV_PERIOD,
            "val_period": VAL_PERIOD,
            "pure_oos": PURE_OOS,
        },
    }

    print("\n=== DEV EDGE 2024-2025 (no target stop) ===")
    edge_dev, edge_dev_res = edge_report(universe, *DEV_PERIOD, "edge_dev")
    summary["edge_dev"] = edge_dev
    print(json.dumps(edge_dev, indent=2, default=str))
    if not edge_dev_res.trades_df.empty:
        edge_dev_res.trades_df.to_csv(out_dir / "trades_edge_dev_2024_2025.csv", index=False)

    print("\n=== DEV CHALLENGE 2024-2025 (eval + funded) ===")
    chal_dev = simulate_challenge(universe, *DEV_PERIOD)
    summary["challenge_dev"] = {k: _result_to_dict(v) for k, v in chal_dev.items()}
    print(json.dumps(summary["challenge_dev"], indent=2))
    for name, res in chal_dev.items():
        if not res.trades_df.empty:
            res.trades_df.to_csv(out_dir / f"trades_challenge_dev_{name}.csv", index=False)

    print("\n=== VAL EDGE 2023-2024 (no target stop) ===")
    edge_val, edge_val_res = edge_report(universe, *VAL_PERIOD, "edge_val")
    summary["edge_val"] = edge_val
    print(json.dumps(edge_val, indent=2, default=str))
    if not edge_val_res.trades_df.empty:
        edge_val_res.trades_df.to_csv(out_dir / "trades_edge_val_2023_2024.csv", index=False)

    print("\n=== VAL CHALLENGE 2023-2024 (eval + funded) ===")
    chal_val = simulate_challenge(universe, *VAL_PERIOD)
    summary["challenge_val"] = {k: _result_to_dict(v) for k, v in chal_val.items()}
    print(json.dumps(summary["challenge_val"], indent=2))
    for name, res in chal_val.items():
        if not res.trades_df.empty:
            res.trades_df.to_csv(out_dir / f"trades_challenge_val_{name}.csv", index=False)

    print("\n=== PURE OOS EDGE 2023 ===")
    edge_oos, edge_oos_res = edge_report(universe, *PURE_OOS, "edge_oos_2023")
    summary["edge_pure_oos_2023"] = edge_oos
    print(json.dumps(edge_oos, indent=2, default=str))
    if not edge_oos_res.trades_df.empty:
        edge_oos_res.trades_df.to_csv(out_dir / "trades_edge_2023.csv", index=False)

    print("\n=== PURE OOS CHALLENGE 2023 ===")
    chal_oos = simulate_challenge(universe, *PURE_OOS)
    summary["challenge_pure_oos_2023"] = {k: _result_to_dict(v) for k, v in chal_oos.items()}
    print(json.dumps(summary["challenge_pure_oos_2023"], indent=2))

    with open(out_dir / "summary.json", "w") as f:
        json.dump(summary, f, indent=2, default=str)
    print(f"\nWrote {out_dir / 'summary.json'}")


if __name__ == "__main__":
    main()
