#!/usr/bin/env python3
"""Validate month-pass screen hits for ~35-day eval pass + funded survival."""

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
from mcpt.forex.month_challenge import rolling_month_eval
from scripts.research.h1_hunt import load_h1
from scripts.research.month_pass_hunt import PAIRSETS, funded_after_month_passes, lean_mcpt

OUT = ROOT / "data" / "research"


def main():
    hits = json.loads((OUT / "month_pass_hits.json").read_text())
    cands = []
    seen = set()
    for h in sorted(hits, key=lambda x: (x["month_pass_rate"], x["screen_ann"]), reverse=True):
        if h["screen_ann"] < 2000:
            continue
        p = h["params"]
        key = (
            h["pairset"],
            p["signal_mode"],
            p["risk_pct"],
            p["rr"],
            p["max_positions"],
            p["one_entry_per_day"],
            p.get("daily_halt_loss_pct"),
        )
        if key in seen:
            continue
        seen.add(key)
        cands.append(h)
        if len(cands) >= 15:
            break
    print(f"cands {len(cands)}", flush=True)

    best = None
    hard = None
    rows = []
    t0 = time.time()
    for h in cands:
        ps = h["pairset"]
        p = h["params"]
        book = load_h1(PAIRSETS[ps])
        print(
            f"\n== {ps}|{p['signal_mode']} screen_rate={h['month_pass_rate']:.2f} "
            f"ann=${h['screen_ann']:.0f} risk={p['risk_pct']} rr={p['rr']} mp={p['max_positions']}",
            flush=True,
        )
        month = rolling_month_eval(
            book,
            window_days=35,
            step_days=14,
            max_days_to_pass=35,
            rules=FundedRules(),
            **{**p, "weekly_withdraw": False},
        )
        print(
            f"  month rate={month.pass_rate:.2f} ({month.n_passed}/{month.n_windows}) "
            f"med={month.median_days} p90={month.p90_days} blown={month.n_blown}",
            flush=True,
        )
        if month.pass_rate < 0.40 or month.median_days > 30 or month.n_passed < 10:
            print("  skip month", flush=True)
            continue
        full = run_backtest(book, rules=FundedRules(), **p)
        print(
            f"  full ann=${full.stats['avg_annual_pnl']:.0f} blown={full.stats['blown']} "
            f"cons={full.stats['consistency_ok']} tr={full.stats['n_trades']} "
            f"pf={full.stats['profit_factor']:.2f}",
            flush=True,
        )
        if full.stats["blown"] or not full.stats["consistency_ok"] or full.stats["avg_annual_pnl"] < 0:
            print("  skip full", flush=True)
            continue
        fund = funded_after_month_passes(book, p, month, hold_days=90)
        print(
            f"  post90 surv={fund['survive_rate']:.2f} "
            f"({fund['n_survived']}/{fund['n_checked']}) med_ann={fund['median_fund_ann']}",
            flush=True,
        )
        if fund["n_checked"] < 8 or fund["survive_rate"] < 0.50:
            print("  skip fund", flush=True)
            continue

        data_end = str(min(v.index.max() for v in book.values()).date())
        ch_best = None
        ch_best_ee = None
        for ee in ["2019-06-30", "2019-12-31", "2020-06-30", "2020-12-31"]:
            ch = simulate_challenge(
                book, eval_end=ee, funded_end=data_end, rules=FundedRules(), **p
            )
            print(
                f"  ch ee={ee} eval={ch.evaluation_passed} days={ch.evaluation_days} "
                f"surv={ch.funded_survived} fund=${ch.funded_annual_pnl:.0f}",
                flush=True,
            )
            if (
                ch.evaluation_passed
                and ch.evaluation_days != -1
                and ch.evaluation_days <= 40
                and ch.funded_survived
            ):
                if ch_best is None or (
                    ch.evaluation_days,
                    -ch.funded_annual_pnl,
                ) < (ch_best.evaluation_days, -ch_best.funded_annual_pnl):
                    ch_best = ch
                    ch_best_ee = ee
        if ch_best is None:
            for ee in ["2019-06-30", "2019-12-31", "2020-06-30", "2020-12-31"]:
                ch = simulate_challenge(
                    book, eval_end=ee, funded_end=data_end, rules=FundedRules(), **p
                )
                if ch.evaluation_passed and 0 < ch.evaluation_days <= 40:
                    ch_best = ch
                    ch_best_ee = ee
                    break
        if ch_best is None:
            print("  skip no month-speed eval pass on splits", flush=True)
            continue
        print(
            f"  selected ch ee={ch_best_ee} days={ch_best.evaluation_days} "
            f"surv={ch_best.funded_survived}",
            flush=True,
        )
        print("  MCPT60...", flush=True)
        pv = lean_mcpt(book, p, n=60)
        print(f"  p={pv:.3f}", flush=True)
        if pv <= 0.12:
            pv = lean_mcpt(book, p, n=100)
            print(f"  p100={pv:.3f}", flush=True)

        import pandas as pd

        oos = {k: v[v.index > pd.Timestamp("2020-06-30")] for k, v in book.items()}
        oos_bt = run_backtest(oos, rules=FundedRules(), **p)
        recent = load_h1(PAIRSETS[ps], recent=True)
        rs = run_backtest(recent, rules=FundedRules(), **p).stats if recent else None
        if rs:
            print(f"  recent ann=${rs['avg_annual_pnl']:.0f} blown={rs['blown']}", flush=True)

        rec = dict(
            pairset=ps,
            pairs=list(book.keys()),
            timeframe="1h",
            data_window="2018-01-01..2022-03-04",
            params=p,
            mcpt_p=pv,
            mcpt_pass=pv <= 0.05,
            full_stats=full.stats,
            oos_stats=oos_bt.stats,
            recent_stats=rs,
            challenge=ch_best.to_dict(),
            month_pass=month.to_dict(),
            post_pass_funded90=fund,
            challenge_eval_end=ch_best_ee,
            goal="pass_eval_within_~35_days",
            notes="Optimized for ~1-month funded-challenge eval pass rate.",
        )
        rows.append(rec)
        (OUT / "month_pass_latest.json").write_text(json.dumps(rec, indent=2, default=str))

        hard_ok = (
            month.pass_rate >= 0.45
            and month.median_days <= 28
            and fund["survive_rate"] >= 0.55
            and ch_best.evaluation_passed
            and ch_best.evaluation_days <= 35
            and ch_best.funded_survived
            and full.stats["avg_annual_pnl"] > 0
        )
        soft_ok = (
            month.pass_rate >= 0.40
            and month.median_days <= 30
            and fund["survive_rate"] >= 0.50
            and ch_best.evaluation_passed
            and ch_best.evaluation_days <= 40
            and full.stats["avg_annual_pnl"] > 0
        )
        key = (
            int(hard_ok),
            int(soft_ok),
            int(ch_best.funded_survived),
            month.pass_rate,
            fund["survive_rate"],
            -ch_best.evaluation_days,
            full.stats["avg_annual_pnl"],
            int(pv <= 0.05),
        )
        if best is None or key > best[0]:
            best = (key, rec)
            (OUT / "month_pass_best.json").write_text(json.dumps(rec, indent=2, default=str))
            print(f"  NEW BEST {key}", flush=True)
        if hard_ok:
            (OUT / "best_strategy.json").write_text(json.dumps(rec, indent=2, default=str))
            print("  HARD_WINNER wrote best_strategy.json", flush=True)
            hard = rec
            break

    if best and not hard:
        rec = best[1]
        (OUT / "best_strategy.json").write_text(json.dumps(rec, indent=2, default=str))
        print("  PROMOTED soft best to best_strategy.json", flush=True)

    (OUT / "month_pass_validated.json").write_text(json.dumps(rows, indent=2, default=str))
    summary = {"hard": bool(hard), "validated": len(rows), "elapsed_s": time.time() - t0}
    if best:
        r = best[1]
        summary.update(
            month_rate=r["month_pass"]["pass_rate"],
            median_days=r["month_pass"]["median_days"],
            eval_days=r["challenge"]["evaluation_days"],
            eval=r["challenge"]["evaluation_passed"],
            surv=r["challenge"]["funded_survived"],
            ann=r["full_stats"]["avg_annual_pnl"],
            mcpt=r["mcpt_p"],
            mode=r["params"]["signal_mode"],
            post90=r["post_pass_funded90"]["survive_rate"],
        )
    print("DONE_SUMMARY", json.dumps(summary, indent=2), flush=True)
    (OUT / "month_pass_summary.json").write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
