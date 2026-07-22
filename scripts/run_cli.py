#!/usr/bin/env python3
"""CLI runner for MCPT pipeline (quick terminal tests)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from mcpt.data import get_default_dataset, slice_years
from mcpt.pipeline import run_full_pipeline


def main() -> None:
    p = argparse.ArgumentParser(description="MCPT Trading Strategy Tester")
    p.add_argument("--strategy", default="donchian", choices=["donchian", "ma_crossover", "tree"])
    p.add_argument("--source", default="synthetic", choices=["synthetic", "yfinance", "cache"])
    p.add_argument("--symbol", default="BTC-USD")
    p.add_argument("--start", default="2018-01-01")
    p.add_argument("--insample-perms", type=int, default=40)
    p.add_argument("--walkforward-perms", type=int, default=20)
    p.add_argument("--train-years", type=int, default=3)
    p.add_argument("--no-walkforward", action="store_true")
    p.add_argument("--start-year", type=int, default=None)
    p.add_argument("--end-year", type=int, default=None)
    p.add_argument("--json", action="store_true")
    args = p.parse_args()

    df, label = get_default_dataset(source=args.source, symbol=args.symbol, start=args.start)
    if args.start_year and args.end_year:
        df = slice_years(df, args.start_year, args.end_year)

    print(f"Data: {label} | bars={len(df)} | {df.index[0]} → {df.index[-1]}")

    result = run_full_pipeline(
        df,
        strategy=args.strategy,
        data_source=label,
        n_insample_perms=args.insample_perms,
        n_walkforward_perms=args.walkforward_perms,
        train_years=args.train_years,
        run_walkforward=not args.no_walkforward and args.strategy == "donchian",
    )

    if args.json:
        print(json.dumps(result.to_dict(), indent=2, default=str))
        return

    print(f"\nStrategy: {result.strategy}")
    print(f"In-sample PF: {result.insample.get('profit_factor'):.4f}  param={result.insample.get('param')}")
    if result.insample_mcpt:
        m = result.insample_mcpt
        print(f"In-sample MCPT: p={m['p_value']:.4f}  {'PASS' if m['passed'] else 'FAIL'}")
    if result.walkforward:
        print(f"Walk-forward PF: {result.walkforward['profit_factor']:.4f}")
    if result.walkforward_mcpt:
        m = result.walkforward_mcpt
        print(f"Walk-forward MCPT: p={m['p_value']:.4f}  {'PASS' if m['passed'] else 'FAIL'}")
    print(f"\nVerdict: {result.verdict}")


if __name__ == "__main__":
    main()
