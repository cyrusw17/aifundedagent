#!/usr/bin/env python3
"""Lightning hunt: parallel random search on proven modes, then MCPT gate."""

from __future__ import annotations

import json
import os
import random
import sys
import time
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

OUT = ROOT / "data" / "research"
DATA = ROOT / "data" / "forex"
OUT.mkdir(parents=True, exist_ok=True)

PAIRSETS = {
    "core5": ["EURUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD"],
    "majors4": ["EURUSD", "USDJPY", "USDCHF", "AUDUSD"],
    "all7": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", "USDCHF"],
}
MODES = ["weekly_smc", "smc", "smc_plus"]


def sample(rng):
    swing = rng.choice([2, 3, 4])
    return dict(
        signal_mode=rng.choice(MODES),
        risk_pct=rng.choice([0.004, 0.005, 0.0065, 0.0075, 0.009, 0.01]),
        rr=rng.choice([1.8, 2.0, 2.5, 3.0]),
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
    )


def mutate(p, rng):
    q = dict(p)
    for k, vals in [
        ("risk_pct", [0.004, 0.005, 0.0065, 0.0075, 0.009, 0.01]),
        ("rr", [1.8, 2.0, 2.5, 3.0]),
        ("atr_stop_mult", [1.1, 1.25, 1.4]),
        ("max_positions", [1, 2, 3]),
        ("move_be_at_r", [0.0, 1.0]),
        ("daily_halt_loss_pct", [0.012, 0.015, 0.02]),
        ("skip_mondays", [True, False]),
    ]:
        if rng.random() < 0.35:
            q[k] = rng.choice(vals)
    return q


def _work(args):
    pairs, params = args
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
        daily_halt_profit_pct=params["daily_halt_profit_pct"],
        cooldown_losses=params["cooldown_losses"],
        weekly_withdraw=True,
        one_entry_per_day=True,
    )
    return params, st.as_dict()


def mcpt(book, params, n=100, seed=3):
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
            one_entry_per_day=True,
        )

    def obj(st):
        if st.blown:
            return -1
        if not st.consistency_ok:
            return 0
        return min(st.profit_factor, 5) * 0.3 + (st.avg_annual_pnl / 10000) * 0.6 + min(st.n_trades / 100, 1) * 0.1

    real = run(book)
    rs = obj(real)
    better = 1
    for i in range(1, n):
        if obj(run(permute_forex_book(book, seed=seed + i))) >= rs:
            better += 1
    return better / n


def validate(ps, pairs, params):
    book = load_book(pairs)
    rules = FundedRules()
    full = run_backtest(book, rules=rules, **params)
    ch = simulate_challenge(book, rules=rules, **params)
    rolls = rolling_eval_windows(
        book,
        window_days=400,
        step_days=120,
        rules=rules,
        **{k: v for k, v in params.items() if k != "weekly_withdraw"},
    )
    pr = sum(1 for r in rolls if r["passed"]) / max(len(rolls), 1)
    train = {k: v[(v.index >= "2018-01-01") & (v.index <= "2021-06-30")] for k, v in book.items()}
    oos = {k: v[(v.index >= "2021-07-01") & (v.index <= "2023-12-31")] for k, v in book.items()}
    p_val = mcpt(train, params, n=120)
    oos_bt = run_backtest(oos, rules=rules, **params)
    return dict(
        pairset=ps,
        pairs=pairs,
        params=params,
        mcpt_p=p_val,
        mcpt_pass=p_val <= 0.05,
        full_stats=full.stats,
        oos_stats=oos_bt.stats,
        challenge=ch.to_dict(),
        pass_rate=pr,
    )


def main():
    t0 = time.time()
    rng = random.Random(99)
    workers = max(2, min(8, os.cpu_count() or 4))
    print(f"Lightning workers={workers}", flush=True)
    elites = []
    best_rec = None

    for rnd in range(1, 16):
        batch = []
        for _ in range(200):
            ps = rng.choice(list(PAIRSETS))
            batch.append((PAIRSETS[ps], sample(rng), ps))
        for p, s, ps, _ in elites[:25]:
            for _ in range(6):
                batch.append((PAIRSETS[ps], mutate(p, rng), ps))

        print(f"\n=== Round {rnd} n={len(batch)} ===", flush=True)
        hits = []
        with ProcessPoolExecutor(max_workers=workers) as ex:
            futs = {ex.submit(_work, (pairs, params)): ps for pairs, params, ps in batch}
            done = 0
            for fut in as_completed(futs):
                ps = futs[fut]
                params, stats = fut.result()
                done += 1
                if stats["blown"] or not stats["consistency_ok"]:
                    continue
                if stats["n_trades"] < 70:
                    continue
                sc = stats["avg_annual_pnl"] + min(stats["profit_factor"], 3) * 1000
                hits.append((params, stats, ps, sc))
                if done % 80 == 0:
                    top = max((h[1]["avg_annual_pnl"] for h in hits), default=0)
                    print(f"  {done}/{len(batch)} hits={len(hits)} top=${top:.0f}", flush=True)

        hits.sort(key=lambda x: x[3], reverse=True)
        if hits:
            print(
                f"  top ${hits[0][1]['avg_annual_pnl']:.0f} tr={hits[0][1]['n_trades']} "
                f"pf={hits[0][1]['profit_factor']:.2f} {hits[0][2]}|{hits[0][0]['signal_mode']}",
                flush=True,
            )
        elites = (hits[:40] + elites)[:60]
        elites.sort(key=lambda x: x[3], reverse=True)

        cand = [h for h in hits if h[1]["avg_annual_pnl"] >= 4000][:8] or hits[:5]
        for params, stats, ps, sc in cand:
            print(f"  validate {ps}|{params['signal_mode']} ${stats['avg_annual_pnl']:.0f}", flush=True)
            rec = validate(ps, PAIRSETS[ps], params)
            print(
                f"    p={rec['mcpt_p']:.3f} full=${rec['full_stats']['avg_annual_pnl']:.0f} "
                f"oos=${rec['oos_stats']['avg_annual_pnl']:.0f} fund=${rec['challenge']['funded_annual_pnl']:.0f} "
                f"eval={rec['challenge']['evaluation_passed']} pr={rec['pass_rate']:.2f}",
                flush=True,
            )
            (OUT / "lightning_latest.json").write_text(json.dumps(rec, indent=2, default=str))
            rank = (
                int(rec["mcpt_pass"]),
                int(rec["challenge"]["funded_survived"]),
                max(rec["full_stats"]["avg_annual_pnl"], rec["challenge"]["funded_annual_pnl"]),
                rec["oos_stats"]["avg_annual_pnl"],
            )
            if best_rec is None or rank > best_rec[0]:
                best_rec = (rank, rec)
            if (
                rec["mcpt_pass"]
                and rec["challenge"]["funded_survived"]
                and not rec["full_stats"]["blown"]
                and (
                    rec["full_stats"]["avg_annual_pnl"] >= 10000
                    or rec["challenge"]["funded_annual_pnl"] >= 10000
                )
                and rec["oos_stats"]["avg_annual_pnl"] >= 3000
            ):
                print("HARD WINNER FOUND", flush=True)
                (OUT / "best_strategy.json").write_text(json.dumps(rec, indent=2, default=str))
                print(json.dumps({"params": rec["params"], "mcpt_p": rec["mcpt_p"], "full": rec["full_stats"], "oos": rec["oos_stats"], "ch": rec["challenge"]}, indent=2, default=str), flush=True)
                print(f"Elapsed {time.time()-t0:.1f}s", flush=True)
                return

    rec = best_rec[1]
    (OUT / "best_strategy.json").write_text(json.dumps(rec, indent=2, default=str))
    print("\nBEST EFFORT", flush=True)
    print(
        json.dumps(
            {
                "pairset": rec["pairset"],
                "params": rec["params"],
                "mcpt_p": rec["mcpt_p"],
                "mcpt_pass": rec["mcpt_pass"],
                "full_ann": rec["full_stats"]["avg_annual_pnl"],
                "oos_ann": rec["oos_stats"]["avg_annual_pnl"],
                "fund_ann": rec["challenge"]["funded_annual_pnl"],
                "eval": rec["challenge"]["evaluation_passed"],
                "funded_survived": rec["challenge"]["funded_survived"],
                "pr": rec["pass_rate"],
                "trades": rec["full_stats"]["n_trades"],
                "pf": rec["full_stats"]["profit_factor"],
            },
            indent=2,
        ),
        flush=True,
    )
    print(f"Elapsed {time.time()-t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
