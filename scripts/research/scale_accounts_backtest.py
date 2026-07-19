#!/usr/bin/env python3
"""Backtest scale-in portfolios (monthly uncapped or biweekly with caps)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.portfolio_scale import simulate_monthly_scale, simulate_scale
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


WINDOWS = {
    "yahoo_2024_2025": {
        "source": "yahoo",
        "start": "2024-01-01",
        "end": "2025-12-31",
        "warmup": "2023-10-02",
    },
    "hist_2020_2022": {
        "source": "hist",
        "start": "2020-01-01",
        "end": "2022-03-04",
        "warmup": "2019-10-01",
    },
    "hist_2016_2019": {
        "source": "hist",
        "start": "2016-01-01",
        "end": "2019-12-31",
        "warmup": "2016-01-01",
    },
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--window",
        choices=list(WINDOWS) + ["all"],
        default="all",
    )
    ap.add_argument("--eval-max-days", type=int, default=90)
    ap.add_argument(
        "--mode",
        choices=["monthly", "biweekly_capped", "both"],
        default="biweekly_capped",
        help="monthly=uncapped 1/mo; biweekly_capped=every 14d, max 5 eval + 5 funded",
    )
    ap.add_argument("--every-days", type=int, default=14)
    ap.add_argument("--max-evals", type=int, default=5)
    ap.add_argument("--max-funded", type=int, default=5)
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
    keys = list(WINDOWS) if args.window == "all" else [args.window]
    modes = ["monthly", "biweekly_capped"] if args.mode == "both" else [args.mode]
    combined: dict = {}

    for mode in modes:
        combined[mode] = {}
        for key in keys:
            cfg = WINDOWS[key]
            print(f"\n=== {mode} | {key} ===")
            book = load_book(pairs, cfg["warmup"], cfg["end"], cfg["source"])
            if len(book) < 3:
                print(f"  skip: insufficient data ({list(book)})")
                continue
            if mode == "monthly":
                report = simulate_monthly_scale(
                    book,
                    params,
                    start=cfg["start"],
                    end=cfg["end"],
                    pairs=list(book.keys()),
                    eval_max_days=args.eval_max_days,
                    warmup_start=cfg["warmup"],
                )
                out_name = f"scale_portfolio_{key.replace('yahoo_', '').replace('hist_', '')}.json"
                # keep legacy names for monthly
                legacy = {
                    "yahoo_2024_2025": "scale_portfolio_2024_2025.json",
                    "hist_2020_2022": "scale_portfolio_2020_2022.json",
                    "hist_2016_2019": "scale_portfolio_2016_2019.json",
                }
                out_name = legacy[key]
            else:
                report = simulate_scale(
                    book,
                    params,
                    start=cfg["start"],
                    end=cfg["end"],
                    pairs=list(book.keys()),
                    eval_max_days=args.eval_max_days,
                    start_every_days=args.every_days,
                    max_concurrent_evals=args.max_evals,
                    max_concurrent_funded=args.max_funded,
                    warmup_start=cfg["warmup"],
                )
                tag = key.replace("yahoo_", "").replace("hist_", "")
                out_name = (
                    f"scale_biweekly_cap{args.max_evals}e{args.max_funded}f_{tag}.json"
                )

            path = OUT / out_name
            path.write_text(json.dumps(report.to_dict(), indent=2, default=str))
            s = report.summary
            print(
                f"  started={s.get('accounts_started')} "
                f"attempts={s.get('start_attempts', s.get('accounts_started'))} "
                f"skipped={s.get('starts_skipped_eval_cap', 0)} "
                f"passed={s.get('evals_passed')} "
                f"({s.get('eval_pass_rate', 0):.0%}) "
                f"funded={s.get('funded_started', s.get('evals_passed'))} "
                f"blown={s.get('funded_blown')} "
                f"queued_never={s.get('queued_never_funded', 0)}"
            )
            print(
                f"  total payouts ${s['total_payouts_usd']:,.2f} | "
                f"avg/mo ${s['avg_monthly_portfolio_payout_usd']:,.2f} | "
                f"median/mo ${s['median_monthly_portfolio_payout_usd']:,.2f}"
            )
            print(
                f"  peak funded concurrent={s.get('peak_funded_concurrent', s['peak_funded_active'])} | "
                f"peak evals concurrent={s.get('peak_evals_concurrent', 'n/a')} | "
                f"queue peak={s.get('peak_funded_queue', 0)} | "
                f"buffer ~${s['recommended_personal_buffer_usd']:,.0f}"
            )
            print("  monthly (nonzero / starts):")
            for m in report.monthly:
                if (
                    m["payout_usd"]
                    or m.get("accounts_started")
                    or m.get("evals_passed")
                    or m.get("starts_skipped_eval_cap")
                ):
                    print(
                        f"    {m['month']}: start={m.get('accounts_started', 0)} "
                        f"skip={m.get('starts_skipped_eval_cap', 0)} "
                        f"pass={m.get('evals_passed', 0)} "
                        f"eval={m.get('evals_active', '-')} "
                        f"funded={m.get('funded_active', 0)} "
                        f"payout=${m['payout_usd']:,.2f} "
                        f"cum=${m['cumulative_payout_usd']:,.2f}"
                    )
            print(f"  wrote {path}")
            combined[mode][key] = {
                "summary": s,
                "config": report.config,
                "monthly": report.monthly,
                "path": str(path.relative_to(ROOT)),
            }

    index_path = OUT / "scale_portfolio_index.json"
    prev = {}
    if index_path.exists():
        try:
            prev = json.loads(index_path.read_text())
        except Exception:
            prev = {}
    prev.update(
        {
            "strategy": best.get("name"),
            "params": params,
            "pairs": pairs,
            "eval_max_days": args.eval_max_days,
            "modes": combined,
            # keep top-level windows pointer to latest biweekly if present
            "latest_mode": args.mode if args.mode != "both" else "biweekly_capped",
        }
    )
    if "biweekly_capped" in combined:
        prev["windows_biweekly_capped"] = combined["biweekly_capped"]
    if "monthly" in combined:
        prev["windows"] = combined["monthly"]
    index_path.write_text(json.dumps(prev, indent=2, default=str))
    print(f"\nIndex: {index_path}")


if __name__ == "__main__":
    main()
