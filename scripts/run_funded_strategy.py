#!/usr/bin/env python3
"""Run the locked funded SMC strategy on 2018–2023 forex data."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.challenge import simulate_challenge
from mcpt.forex.strategy_funded import load_best
from scripts.research.iterate_forex_strategy import load_book


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    best = load_best()
    pairs = best.get("pairs") or ["EURUSD", "USDJPY", "USDCHF", "AUDUSD"]
    params = best["params"]
    book = load_book(pairs)
    rules = FundedRules()

    bt = run_backtest(book, rules=rules, **params)
    ch = simulate_challenge(book, rules=rules, **params)
    out = {
        "pairs": pairs,
        "params": params,
        "research_mcpt_p": best.get("mcpt_p"),
        "research_mcpt_pass": best.get("mcpt_pass"),
        "full_stats": bt.stats,
        "challenge": {
            "evaluation_passed": ch.evaluation_passed,
            "funded_survived": ch.funded_survived,
            "funded_annual_pnl": ch.funded_annual_pnl,
            "consistency_ok": ch.consistency_ok,
        },
        "total_withdrawn": bt.account.total_withdrawn,
        "final_balance": bt.account.balance,
    }
    if args.json:
        print(json.dumps(out, indent=2, default=str))
        return
    print(f"Pairs: {pairs}")
    print(f"Mode: {params.get('signal_mode')} risk={params.get('risk_pct')} rr={params.get('rr')}")
    print(f"MCPT (research): p={best.get('mcpt_p')} pass={best.get('mcpt_pass')}")
    print(
        f"Full: ann=${bt.stats['avg_annual_pnl']:.0f} pf={bt.stats['profit_factor']:.2f} "
        f"trades={bt.stats['n_trades']} blown={bt.stats['blown']} cons={bt.stats['consistency_ok']}"
    )
    print(
        f"Challenge: eval={ch.evaluation_passed} funded_survived={ch.funded_survived} "
        f"funded_ann=${ch.funded_annual_pnl:.0f}"
    )
    print(f"Withdrawn: ${bt.account.total_withdrawn:.0f} final_balance=${bt.account.balance:.0f}")


if __name__ == "__main__":
    main()
