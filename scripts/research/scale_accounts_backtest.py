#!/usr/bin/env python3
"""Backtest monthly scale-in: +1x $100k eval each month; trade all that pass & survive."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.portfolio_scale import simulate_monthly_scale
from mcpt.forex.strategy_funded import load_best

DATA = ROOT / "data" / "forex"
OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)


def load_book(pairs: list[str], start: str, end: str, source: str) -> dict[str, pd.DataFrame]:
    book = {}
    s, e = pd.Timestamp(start), pd.Timestamp(end)
    suffix = "_1h_hist.parquet" if source == "hist" else "_1h.parquet"
    for p in pairs:
        path = DATA / f"{p}{suffix}"
        if not path.exists() and source == "hist":
            path = DATA / f"{p}_1h.parquet"
        if not path.exists():
            continue
        df = pd.read_parquet(path)
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        df = df[(df.index >= s) & (df.index <= e)]
        df = df[~df.index.duplicated(keep="last")].sort_index()
        if len(df) >= 200:
            book[p] = df
    return book


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--window",
        choices=["yahoo_2024_2025", "hist_2020_2022", "hist_2016_2019", "all"],
        default="all",
    )
    ap.add_argument("--eval-max-days", type=int, default=90)
    args = ap.parse_args()

    best = load_best()
    pairs = best.get("pairs") or [
        "EURUSD",
        "GBPUSD",
        "USDJPY",
        "AUDUSD",
        "USDCHF",
        "USDCAD",
    ]
    params = best["params"]

    windows = {
        "yahoo_2024_2025": {
            "source": "yahoo",
            "start": "2024-01-01",
            "end": "2025-12-31",
            "warmup": "2023-10-02",
            "out": "scale_portfolio_2024_2025.json",
        },
        "hist_2020_2022": {
            "source": "hist",
            "start": "2020-01-01",
            "end": "2022-03-04",
            "warmup": "2019-10-01",
            "out": "scale_portfolio_2020_2022.json",
        },
        "hist_2016_2019": {
            "source": "hist",
            "start": "2016-01-01",
            "end": "2019-12-31",
            "warmup": "2016-01-01",
            "out": "scale_portfolio_2016_2019.json",
        },
    }
    keys = list(windows) if args.window == "all" else [args.window]
    # Prefer Yahoo first (user focus), then hist eras
    combined = {}

    for key in keys:
        cfg = windows[key]
        print(f"\n=== {key} ===")
        book = load_book(pairs, cfg["warmup"], cfg["end"], cfg["source"])
        if len(book) < 3:
            print(f"  skip: insufficient data ({list(book)})")
            continue
        # Restrict bars after warmup via simulate warmup_start
        report = simulate_monthly_scale(
            book,
            params,
            start=cfg["start"],
            end=cfg["end"],
            pairs=list(book.keys()),
            eval_max_days=args.eval_max_days,
            warmup_start=cfg["warmup"],
        )
        path = OUT / cfg["out"]
        path.write_text(json.dumps(report.to_dict(), indent=2, default=str))
        s = report.summary
        print(
            f"  started={s['accounts_started']} passed={s['evals_passed']} "
            f"({s['eval_pass_rate']:.0%}) blown={s['funded_blown']} "
            f"survived={s['funded_survived_to_end']}"
        )
        print(
            f"  total payouts ${s['total_payouts_usd']:,.2f} | "
            f"avg/mo ${s['avg_monthly_portfolio_payout_usd']:,.2f} | "
            f"median/mo ${s['median_monthly_portfolio_payout_usd']:,.2f}"
        )
        print(
            f"  peak funded active={s['peak_funded_active']} "
            f"(~${s['notional_peak_usd']:,.0f} notional) | "
            f"median eval days={s['median_eval_days']}"
        )
        print(
            f"  buffer personal ~${s['recommended_personal_buffer_usd']:,.0f} | "
            f"keep/account ${s['recommended_keep_per_account_above_initial_usd']:,.0f}"
        )
        print("  monthly:")
        for m in report.monthly:
            if m["payout_usd"] or m["evals_passed"] or m["accounts_started"]:
                print(
                    f"    {m['month']}: start={m['accounts_started']} "
                    f"pass={m['evals_passed']} active={m['funded_active']} "
                    f"payout=${m['payout_usd']:,.2f} cum=${m['cumulative_payout_usd']:,.2f}"
                )
        print(f"  wrote {path}")
        combined[key] = {
            "summary": s,
            "monthly": report.monthly,
            "path": str(path.relative_to(ROOT)),
        }

    index_path = OUT / "scale_portfolio_index.json"
    index_path.write_text(
        json.dumps(
            {
                "strategy": best.get("name"),
                "params": params,
                "pairs": pairs,
                "eval_max_days": args.eval_max_days,
                "windows": combined,
            },
            indent=2,
            default=str,
        )
    )
    print(f"\nIndex: {index_path}")


if __name__ == "__main__":
    main()
