#!/usr/bin/env python3
"""Validate H1 screen hits with full backtest first, then lean MCPT."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.challenge import simulate_challenge
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.mcpt_forex import permute_forex_book
from scripts.research.h1_hunt import is_hard_winner, load_h1, maybe_write_best, rank_key

OUT = ROOT / "data" / "research"
PAIRSETS = {
    "h1_majors4": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"],
    "h1_core5": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF"],
    "h1_all6": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF", "USDCAD"],
}


def lean_mcpt(book, params, n=60, seed=7):
    import pandas as pd

    cut = pd.Timestamp("2020-06-30")
    train = {k: v[v.index <= cut] for k, v in book.items()}

    def run(b):
        prep = prepare_book(b, params["signal_mode"], params["swing_left"], 2)
        return fast_backtest(
            prep,
            risk_pct=params["risk_pct"],
            rr=params["rr"],
            atr_stop_mult=params["atr_stop_mult"],
            max_positions=params["max_positions"],
            move_be_at_r=params["move_be_at_r"],
            skip_mondays=params["skip_mondays"],
            daily_halt_loss_pct=params["daily_halt_loss_pct"],
            daily_halt_profit_pct=params["daily_halt_profit_pct"],
            cooldown_losses=params["cooldown_losses"],
            weekly_withdraw=True,
            one_entry_per_day=bool(params.get("one_entry_per_day", True)),
        )

    def obj(st):
        if st.blown:
            return -1
        if not st.consistency_ok:
            return 0
        return (
            min(st.profit_factor, 5) * 0.25
            + (st.avg_annual_pnl / 10000) * 0.65
            + min(st.n_trades / 200, 1) * 0.1
        )

    real = run(train)
    rs = obj(real)
    better = 1
    for i in range(1, n):
        if obj(run(permute_forex_book(train, seed=seed + i))) >= rs:
            better += 1
    return better / n


def main():
    t0 = time.time()
    hits = json.loads((OUT / "h1_lean_hits.json").read_text())
    # Prefer modes where full≈fast, and high full expectancy
    ranked = sorted(
        hits,
        key=lambda h: (
            1 if h["params"]["signal_mode"] in {"h1_sweep_bos", "kz_active", "killzone_smc"} else 0,
            h["ann"],
        ),
        reverse=True,
    )
    seen = set()
    cands = []
    for h in ranked:
        p = h["params"]
        key = (
            h["pairset"],
            p["signal_mode"],
            p["risk_pct"],
            p["rr"],
            p["max_positions"],
            p["one_entry_per_day"],
            p.get("move_be_at_r"),
        )
        if key in seen:
            continue
        seen.add(key)
        cands.append(h)
        if len(cands) >= 15:
            break

    best = None
    hard = None
    rows = []
    for h in cands:
        ps = h["pairset"]
        p = h["params"]
        pairs = PAIRSETS[ps]
        book = load_h1(pairs)
        print(
            f"\n== {ps}|{p['signal_mode']} screen=${h['ann']:.0f} "
            f"risk={p['risk_pct']} rr={p['rr']} mp={p['max_positions']} one={p['one_entry_per_day']}",
            flush=True,
        )
        full = run_backtest(book, rules=FundedRules(), **p)
        fs = full.stats
        print(
            f"  full ann=${fs['avg_annual_pnl']:.0f} tr={fs['n_trades']} pf={fs['profit_factor']:.2f} "
            f"blown={fs['blown']} cons={fs['consistency_ok']}",
            flush=True,
        )
        if fs["blown"] or not fs["consistency_ok"] or fs["avg_annual_pnl"] < 8000:
            continue

        import pandas as pd

        oos = {k: v[v.index > pd.Timestamp("2020-06-30")] for k, v in book.items()}
        oos_bt = run_backtest(oos, rules=FundedRules(), **p)
        print(
            f"  oos ann=${oos_bt.stats['avg_annual_pnl']:.0f} blown={oos_bt.stats['blown']} "
            f"tr={oos_bt.stats['n_trades']}",
            flush=True,
        )
        if oos_bt.stats["blown"] or oos_bt.stats["avg_annual_pnl"] < 0:
            continue

        funded_end = str(min(v.index.max() for v in book.values()).date())
        ch = simulate_challenge(
            book, eval_end="2020-06-30", funded_end=funded_end, rules=FundedRules(), **p
        )
        print(
            f"  challenge eval={ch.evaluation_passed} survived={ch.funded_survived} "
            f"fund_ann=${ch.funded_annual_pnl:.0f}",
            flush=True,
        )
        if not ch.funded_survived:
            continue

        print("  MCPT n=60...", flush=True)
        p_val = lean_mcpt(book, p, n=60)
        print(f"  MCPT p={p_val:.3f}", flush=True)
        if p_val <= 0.08:
            print("  MCPT confirm n=120...", flush=True)
            p_val = lean_mcpt(book, p, n=120)
            print(f"  MCPT p={p_val:.3f}", flush=True)

        recent = load_h1(pairs, recent=True)
        recent_stats = None
        if recent:
            recent_stats = run_backtest(recent, rules=FundedRules(), **p).stats
            print(
                f"  recent ann=${recent_stats['avg_annual_pnl']:.0f} blown={recent_stats['blown']} "
                f"tr={recent_stats['n_trades']}",
                flush=True,
            )

        rec = dict(
            pairset=ps,
            pairs=list(book.keys()),
            timeframe="1h",
            data_window="2018-01-01..2022-03-04",
            params=p,
            mcpt_p=p_val,
            mcpt_pass=p_val <= 0.05,
            full_stats=fs,
            oos_stats=oos_bt.stats,
            recent_stats=recent_stats,
            challenge=ch.to_dict(),
            pass_rate=None,
            data_end=funded_end,
        )
        rows.append(rec)
        (OUT / "h1_grid_latest.json").write_text(json.dumps(rec, indent=2, default=str))
        if best is None or rank_key(rec) > best[0]:
            best = (rank_key(rec), rec)
            (OUT / "h1_best.json").write_text(json.dumps(rec, indent=2, default=str))
        wrote, _ = maybe_write_best(rec)
        if wrote:
            print("  WROTE best_strategy.json", flush=True)
        if is_hard_winner(rec):
            hard = rec
            print("  HARD WINNER", flush=True)
            break

    (OUT / "h1_validated.json").write_text(json.dumps(rows, indent=2, default=str))
    summary = {
        "hard": bool(hard),
        "validated": len(rows),
        "elapsed_s": time.time() - t0,
        "best_ann": None if not best else best[1]["full_stats"]["avg_annual_pnl"],
        "best_mcpt": None if not best else best[1]["mcpt_p"],
        "best_pass": None if not best else best[1]["mcpt_pass"],
        "best_mode": None if not best else best[1]["params"]["signal_mode"],
        "best_fund": None if not best else best[1]["challenge"]["funded_annual_pnl"],
        "oos": None if not best else best[1]["oos_stats"]["avg_annual_pnl"],
    }
    print("\nDONE", json.dumps(summary, indent=2), flush=True)
    (OUT / "h1_lean_summary.json").write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
