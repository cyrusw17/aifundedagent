#!/usr/bin/env python3
from __future__ import annotations

import json
import random
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.challenge import rolling_eval_windows, simulate_challenge
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.mcpt_forex import permute_forex_book
from scripts.research.iterate_forex_strategy import load_book

DATA = ROOT / "data" / "forex"
OUT = ROOT / "data" / "research"
pairs = ["EURUSD", "USDJPY", "USDCHF", "AUDUSD"]


def work(params):
    import pandas as pd

    book = {}
    for p in pairs:
        df = pd.read_parquet(DATA / f"{p}_1d.parquet")
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        book[p] = df[(df.index >= "2018-01-01") & (df.index <= "2023-12-31")]
    prep = prepare_book(book, params["signal_mode"], params["swing_left"], 2)
    st = fast_backtest(
        prep,
        risk_pct=params["risk_pct"],
        rr=params["rr"],
        atr_stop_mult=params["atr_stop_mult"],
        max_positions=params["max_positions"],
        move_be_at_r=params["move_be_at_r"],
        skip_mondays=params["skip_mondays"],
        daily_halt_loss_pct=params["daily_halt_loss_pct"],
        daily_halt_profit_pct=0.03,
        cooldown_losses=params["cooldown_losses"],
        weekly_withdraw=True,
        one_entry_per_day=True,
    )
    return params, st.as_dict()


def mcpt(book, p, n=100):
    def run(b):
        prep = prepare_book(b, p["signal_mode"], p["swing_left"], 2)
        return fast_backtest(
            prep,
            risk_pct=p["risk_pct"],
            rr=p["rr"],
            atr_stop_mult=p["atr_stop_mult"],
            max_positions=p["max_positions"],
            move_be_at_r=p["move_be_at_r"],
            skip_mondays=p["skip_mondays"],
            daily_halt_loss_pct=p["daily_halt_loss_pct"],
            daily_halt_profit_pct=0.03,
            cooldown_losses=p["cooldown_losses"],
            weekly_withdraw=True,
            one_entry_per_day=True,
        )

    def obj(st):
        if st.blown:
            return -1
        if not st.consistency_ok:
            return 0
        return (
            min(st.profit_factor, 5) * 0.3
            + (st.avg_annual_pnl / 10000) * 0.6
            + min(st.n_trades / 100, 1) * 0.1
        )

    real = run(book)
    rs = obj(real)
    better = 1
    for i in range(1, n):
        if obj(run(permute_forex_book(book, seed=7 + i))) >= rs:
            better += 1
    return better / n


def main():
    rng = random.Random(123)
    batch = []
    for _ in range(500):
        swing = rng.choice([2, 3, 4])
        batch.append(
            dict(
                signal_mode=rng.choice(["smc", "weekly_smc", "smc_plus"]),
                risk_pct=rng.choice([0.005, 0.0065, 0.0075, 0.009, 0.01, 0.012]),
                rr=rng.choice([2.0, 2.5, 3.0]),
                atr_stop_mult=rng.choice([1.1, 1.25, 1.4]),
                max_positions=rng.choice([1, 2, 3]),
                min_confluence=2,
                swing_left=swing,
                swing_right=swing,
                require_killzone=False,
                weekly_withdraw=True,
                move_be_at_r=rng.choice([0.0, 1.0]),
                skip_mondays=rng.choice([True, False]),
                daily_halt_loss_pct=rng.choice([0.012, 0.015, 0.02]),
                daily_halt_profit_pct=0.03,
                cooldown_losses=rng.choice([0, 2]),
                one_entry_per_day=True,
            )
        )
    print(f"batch={len(batch)}", flush=True)
    hits = []
    with ProcessPoolExecutor(max_workers=4) as ex:
        futs = [ex.submit(work, p) for p in batch]
        done = 0
        for fut in as_completed(futs):
            p, s = fut.result()
            done += 1
            if (
                not s["blown"]
                and s["consistency_ok"]
                and s["n_trades"] >= 70
                and s["avg_annual_pnl"] >= 4000
            ):
                hits.append((s["avg_annual_pnl"], p, s))
            if done % 100 == 0:
                top = max((h[0] for h in hits), default=0)
                print(f"  {done}/{len(batch)} hits={len(hits)} top=${top:.0f}", flush=True)
    hits.sort(reverse=True)
    print(f"hits={len(hits)}", flush=True)
    for ann, p, s in hits[:12]:
        print(
            f"screen ${ann:.0f} tr={s['n_trades']} pf={s['profit_factor']:.2f} "
            f"{p['signal_mode']} risk={p['risk_pct']} rr={p['rr']} mp={p['max_positions']}",
            flush=True,
        )

    book = load_book(pairs)
    train = {k: v[(v.index >= "2018-01-01") & (v.index <= "2021-06-30")] for k, v in book.items()}
    oos = {k: v[(v.index >= "2021-07-01") & (v.index <= "2023-12-31")] for k, v in book.items()}
    best = None
    for ann, p, s in hits[:20]:
        full = run_backtest(book, rules=FundedRules(), **p)
        if full.stats["blown"]:
            print(f"skip blown full {p['signal_mode']} screen=${ann:.0f}", flush=True)
            continue
        oos_bt = run_backtest(oos, rules=FundedRules(), **p)
        ch = simulate_challenge(book, rules=FundedRules(), **p)
        pv = mcpt(train, p, n=100)
        rolls = rolling_eval_windows(
            book,
            window_days=400,
            step_days=120,
            rules=FundedRules(),
            **{k: v for k, v in p.items() if k != "weekly_withdraw"},
        )
        pr = sum(1 for r in rolls if r["passed"]) / max(len(rolls), 1)
        print(
            f"p={pv:.3f} full=${full.stats['avg_annual_pnl']:.0f} oos=${oos_bt.stats['avg_annual_pnl']:.0f} "
            f"fund=${ch.funded_annual_pnl:.0f} eval={ch.evaluation_passed} pr={pr:.2f} "
            f"{p['signal_mode']} risk={p['risk_pct']}",
            flush=True,
        )
        rec = dict(
            pairset="majors4",
            pairs=pairs,
            params=p,
            mcpt_p=pv,
            mcpt_pass=pv <= 0.05,
            full_stats=full.stats,
            oos_stats=oos_bt.stats,
            challenge=ch.to_dict(),
            pass_rate=pr,
        )
        key = (
            int(rec["mcpt_pass"]),
            int(rec["challenge"]["funded_survived"]),
            int(not rec["full_stats"]["blown"]),
            rec["full_stats"]["avg_annual_pnl"],
            rec["challenge"]["funded_annual_pnl"],
            rec["oos_stats"]["avg_annual_pnl"],
        )
        if best is None or key > best[0]:
            best = (key, rec)
            (OUT / "best_strategy.json").write_text(json.dumps(rec, indent=2, default=str))

    if best:
        rec = best[1]
        print("\nBEST", flush=True)
        print(
            json.dumps(
                {
                    "params": rec["params"],
                    "mcpt_p": rec["mcpt_p"],
                    "mcpt_pass": rec["mcpt_pass"],
                    "full_ann": rec["full_stats"]["avg_annual_pnl"],
                    "oos_ann": rec["oos_stats"]["avg_annual_pnl"],
                    "fund_ann": rec["challenge"]["funded_annual_pnl"],
                    "eval": rec["challenge"]["evaluation_passed"],
                    "survived": rec["challenge"]["funded_survived"],
                    "pr": rec["pass_rate"],
                    "trades": rec["full_stats"]["n_trades"],
                    "pf": rec["full_stats"]["profit_factor"],
                    "blown": rec["full_stats"]["blown"],
                },
                indent=2,
            ),
            flush=True,
        )


if __name__ == "__main__":
    main()
