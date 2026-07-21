#!/usr/bin/env python3
"""Run the locked funded SMC strategy on research data (daily or H1)."""

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


def load_h1_book(pairs):
    from scripts.research.h1_hunt import load_h1

    return load_h1(pairs, recent=False)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--recent-h1", action="store_true", help="Also report recent yfinance H1 window")
    args = ap.parse_args()

    best = load_best()
    pairs = best.get("pairs") or ["EURUSD", "USDJPY", "USDCHF", "AUDUSD"]
    params = best["params"]
    tf = best.get("timeframe", "1d")
    if tf == "1h":
        book = load_h1_book(pairs)
    else:
        book = load_book(pairs)
    rules = FundedRules()

    bt = run_backtest(book, rules=rules, **params)
    # Align challenge windows to available data (H1 hist ends early 2022)
    data_end = str(min(v.index.max() for v in book.values()).date())
    eval_end = best.get("challenge_eval_end") or ("2020-06-30" if tf == "1h" else "2020-12-31")
    ch = simulate_challenge(
        book, eval_end=eval_end, funded_end=data_end, rules=rules, **params
    )
    out = {
        "pairs": pairs,
        "timeframe": tf,
        "params": params,
        "research_mcpt_p": best.get("mcpt_p"),
        "research_mcpt_pass": best.get("mcpt_pass"),
        "full_stats": bt.stats,
        "challenge": {
            "evaluation_passed": ch.evaluation_passed,
            "funded_survived": ch.funded_survived,
            "funded_annual_pnl": ch.funded_annual_pnl,
            "consistency_ok": ch.consistency_ok,
            "eval_end": eval_end,
            "funded_end": data_end,
        },
        "total_withdrawn": bt.account.total_withdrawn,
        "final_balance": bt.account.balance,
    }
    if args.recent_h1 or tf == "1h":
        from scripts.research.h1_hunt import load_h1

        recent = load_h1(pairs, recent=True)
        if recent:
            out["recent_h1_stats"] = run_backtest(recent, rules=rules, **params).stats
    if args.json:
        print(json.dumps(out, indent=2, default=str))
        return
    print(f"Pairs: {pairs} timeframe={tf}")
    print(f"Mode: {params.get('signal_mode')} risk={params.get('risk_pct')} rr={params.get('rr')}")
    print(f"MCPT (research): p={best.get('mcpt_p')} pass={best.get('mcpt_pass')}")
    print(
        f"Full: ann=${bt.stats['avg_annual_pnl']:.0f} pf={bt.stats['profit_factor']:.2f} "
        f"trades={bt.stats['n_trades']} blown={bt.stats['blown']} cons={bt.stats['consistency_ok']}"
    )
    print(
        f"Challenge: eval={ch.evaluation_passed} days={ch.evaluation_days} "
        f"funded_survived={ch.funded_survived} funded_ann=${ch.funded_annual_pnl:.0f}"
    )
    mp = best.get("month_pass") or {}
    if mp:
        print(
            f"Month-pass: rate={mp.get('pass_rate'):.2f} "
            f"median_days={mp.get('median_days')} p90={mp.get('p90_days')} "
            f"windows={mp.get('n_passed')}/{mp.get('n_windows')}"
        )
    if "recent_h1_stats" in out:
        rs = out["recent_h1_stats"]
        print(
            f"Recent H1: ann=${rs['avg_annual_pnl']:.0f} trades={rs['n_trades']} "
            f"blown={rs['blown']} pf={rs.get('profit_factor', 0):.2f}"
        )
    print(f"Withdrawn: ${bt.account.total_withdrawn:.0f} final_balance=${bt.account.balance:.0f}")


if __name__ == "__main__":
    main()
