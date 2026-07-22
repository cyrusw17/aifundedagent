#!/usr/bin/env python3
"""Aggressive fast hunter — maximize trade frequency × edge under funded rules."""

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
OUT.mkdir(parents=True, exist_ok=True)
DATA_DIR = ROOT / "data" / "forex"

PAIRSETS = {
    "core5": ["EURUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD"],
    "majors4": ["EURUSD", "USDJPY", "USDCHF", "AUDUSD"],
    "all7": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", "USDCHF"],
    "exotics_ok": ["EURUSD", "USDJPY", "AUDUSD", "NZDUSD"],
}

MODES = [
    "active_smc",
    "smc_plus",
    "trend_pullback",
    "donchian_smc",
    "combo",
    "weekly_smc",
    "smc",
    "sweep_bos",
    "asia_sweep",
    "breakout_hold",
]


def sample_params(rng: random.Random) -> dict:
    mode = rng.choice(MODES)
    swing = rng.choice([2, 3, 4])
    return dict(
        signal_mode=mode,
        risk_pct=rng.choice([0.005, 0.0065, 0.0075, 0.009, 0.01, 0.012]),
        rr=rng.choice([1.5, 1.8, 2.0, 2.2, 2.5, 3.0]),
        atr_stop_mult=rng.choice([0.9, 1.0, 1.15, 1.25, 1.4]),
        max_positions=rng.choice([2, 3, 4, 5]),
        min_confluence=2,
        swing_left=swing,
        swing_right=swing,
        require_killzone=False,
        weekly_withdraw=True,
        move_be_at_r=rng.choice([0.0, 0.8, 1.0]),
        skip_mondays=rng.choice([True, False]),
        daily_halt_loss_pct=rng.choice([0.015, 0.018, 0.02, 0.025]),
        daily_halt_profit_pct=rng.choice([0.025, 0.03, 0.04]),
        cooldown_losses=rng.choice([0, 2, 3]),
    )


def mutate(p: dict, rng: random.Random) -> dict:
    q = dict(p)
    opts = {
        "risk_pct": [0.005, 0.0065, 0.0075, 0.009, 0.01, 0.012],
        "rr": [1.5, 1.8, 2.0, 2.2, 2.5, 3.0],
        "atr_stop_mult": [0.9, 1.0, 1.15, 1.25, 1.4],
        "max_positions": [2, 3, 4, 5],
        "move_be_at_r": [0.0, 0.8, 1.0],
        "daily_halt_loss_pct": [0.015, 0.018, 0.02, 0.025],
        "skip_mondays": [True, False],
        "cooldown_losses": [0, 2, 3],
        "signal_mode": MODES,
    }
    k = rng.choice(list(opts))
    q[k] = rng.choice(opts[k])
    if k == "signal_mode":
        q["min_confluence"] = 2
    return q


def score(s: dict) -> float:
    if s.get("blown") or not s.get("consistency_ok", True):
        return -1e12
    # prioritize annual $, then PF, then trade count
    return (
        s["avg_annual_pnl"] * 1.0
        + min(s.get("profit_factor", 0), 3) * 1500
        + min(s.get("n_trades", 0), 400) * 8
        - max(0.0, s.get("max_dd", 0) - 6500) * 0.8
    )


def _eval_one(payload):
    pair_names, params = payload
    import pandas as pd

    book = {}
    for p in pair_names:
        df = pd.read_parquet(DATA_DIR / f"{p}_1d.parquet")
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        book[p] = df[(df.index >= "2018-01-01") & (df.index <= "2023-12-31")]
    prep = prepare_book(book, mode=params["signal_mode"], swing=params["swing_left"], min_conf=2)
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
    )
    return params, st.as_dict()


def quick_mcpt(book, params, n=60, seed=5):
    rules = FundedRules()

    def run(b):
        prep = prepare_book(b, mode=params["signal_mode"], swing=params["swing_left"], min_conf=2)
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
            rules=rules,
        )

    def obj(st):
        if st.blown:
            return -1.0
        if not st.consistency_ok:
            return 0.0
        return min(st.profit_factor, 5) * 0.3 + (st.avg_annual_pnl / 10000) * 0.6 + min(st.n_trades / 80, 1) * 0.1

    real = run(book)
    real_s = obj(real)
    better = 1
    for i in range(1, n):
        st = run(permute_forex_book(book, seed=seed + i))
        if obj(st) >= real_s:
            better += 1
    return better / n, real.as_dict()


def validate(ps_name, pairs, params):
    book = load_book(pairs)
    rules = FundedRules()
    full = run_backtest(book, rules=rules, **params)
    ch = simulate_challenge(book, rules=rules, **params)
    rolls = rolling_eval_windows(
        book, window_days=400, step_days=120, rules=rules,
        **{k: v for k, v in params.items() if k != "weekly_withdraw"},
    )
    pr = sum(1 for r in rolls if r["passed"]) / max(len(rolls), 1)
    train = {k: v[(v.index >= "2018-01-01") & (v.index <= "2021-06-30")] for k, v in book.items()}
    oos = {k: v[(v.index >= "2021-07-01") & (v.index <= "2023-12-31")] for k, v in book.items()}
    p_val, _ = quick_mcpt(train, params, n=80, seed=9)
    if p_val <= 0.07:
        p_val, _ = quick_mcpt(train, params, n=150, seed=9)
    oos_bt = run_backtest(oos, rules=rules, **params)
    return dict(
        pairset=ps_name,
        pairs=pairs,
        params=params,
        mcpt_p=p_val,
        mcpt_pass=p_val <= 0.05,
        full_stats=full.stats,
        oos_stats=oos_bt.stats,
        challenge=ch.to_dict(),
        pass_rate=pr,
    )


def winner(rec) -> bool:
    fs, oos, ch = rec["full_stats"], rec["oos_stats"], rec["challenge"]
    if not rec["mcpt_pass"] or fs["blown"] or oos["blown"] or not fs["consistency_ok"]:
        return False
    if not ch["funded_survived"]:
        return False
    return (fs["avg_annual_pnl"] >= 10000) or (ch["funded_annual_pnl"] >= 10000 and oos["avg_annual_pnl"] >= 4000)


def main():
    t0 = time.time()
    rng = random.Random(7)
    workers = max(2, min(8, os.cpu_count() or 4))
    print(f"Fast hunt workers={workers}", flush=True)

    elites = []  # (params, stats, ps_name, score)
    selected = None

    for round_i in range(1, 25):
        batch = []
        for _ in range(160):
            ps = rng.choice(list(PAIRSETS))
            batch.append((PAIRSETS[ps], sample_params(rng), ps))
        for params, stats, ps, _ in elites[:20]:
            for _ in range(5):
                batch.append((PAIRSETS[ps], mutate(params, rng), ps))

        print(f"\n=== Round {round_i} batch={len(batch)} ===", flush=True)
        hits = []
        with ProcessPoolExecutor(max_workers=workers) as ex:
            futs = {
                ex.submit(_eval_one, (pairs, params)): ps
                for pairs, params, ps in batch
            }
            done = 0
            for fut in as_completed(futs):
                ps = futs[fut]
                params, stats = fut.result()
                done += 1
                sc = score(stats)
                if sc > -1e11:
                    hits.append((params, stats, ps, sc))
                if done % 50 == 0:
                    top = max((h[1]["avg_annual_pnl"] for h in hits), default=0)
                    print(
                        f"  {done}/{len(batch)} tracked={len(hits)} top_ann=${top:.0f}",
                        flush=True,
                    )

        hits.sort(key=lambda x: x[3], reverse=True)
        print(
            f"  best screen: ann=${hits[0][1]['avg_annual_pnl']:.0f} "
            f"tr={hits[0][1]['n_trades']} pf={hits[0][1]['profit_factor']:.2f} "
            f"{hits[0][2]}|{hits[0][0]['signal_mode']}",
            flush=True,
        )
        elites = (hits[:30] + elites)[:50]
        elites.sort(key=lambda x: x[3], reverse=True)

        # validate anything promising
        to_val = [h for h in hits if h[1]["avg_annual_pnl"] >= 5000][:10]
        if not to_val:
            to_val = hits[:5]
        for params, stats, ps, sc in to_val:
            print(
                f"  validate {ps}|{params['signal_mode']} screen=${stats['avg_annual_pnl']:.0f} tr={stats['n_trades']}",
                flush=True,
            )
            rec = validate(ps, PAIRSETS[ps], params)
            print(
                f"    p={rec['mcpt_p']:.3f} full=${rec['full_stats']['avg_annual_pnl']:.0f} "
                f"oos=${rec['oos_stats']['avg_annual_pnl']:.0f} "
                f"fund=${rec['challenge']['funded_annual_pnl']:.0f} "
                f"eval={rec['challenge']['evaluation_passed']} pr={rec['pass_rate']:.2f}",
                flush=True,
            )
            (OUT / "fast_hunt_latest.json").write_text(json.dumps(rec, indent=2, default=str))
            if winner(rec) or (
                rec["mcpt_pass"]
                and not rec["full_stats"]["blown"]
                and rec["challenge"]["funded_survived"]
                and (
                    rec["full_stats"]["avg_annual_pnl"] >= 9000
                    or rec["challenge"]["funded_annual_pnl"] >= 9000
                )
                and rec["oos_stats"]["avg_annual_pnl"] >= 3000
            ):
                selected = rec
                break
        if selected:
            break

    if selected is None:
        print("\nDeep-validate top elites", flush=True)
        ranked = []
        for params, stats, ps, sc in elites[:15]:
            rec = validate(ps, PAIRSETS[ps], params)
            ranked.append(rec)
            print(
                f"  {ps}|{params['signal_mode']} p={rec['mcpt_p']:.3f} "
                f"full=${rec['full_stats']['avg_annual_pnl']:.0f} "
                f"fund=${rec['challenge']['funded_annual_pnl']:.0f}",
                flush=True,
            )
        ranked.sort(
            key=lambda r: (
                int(r["mcpt_pass"]),
                int(r["challenge"]["funded_survived"]),
                max(r["full_stats"]["avg_annual_pnl"], r["challenge"]["funded_annual_pnl"]),
                r["oos_stats"]["avg_annual_pnl"],
                -r["mcpt_p"],
            ),
            reverse=True,
        )
        selected = ranked[0]
        (OUT / "fast_hunt_top.json").write_text(json.dumps(ranked, indent=2, default=str))

    (OUT / "best_strategy.json").write_text(json.dumps(selected, indent=2, default=str))
    print("\n=== SELECTED ===", flush=True)
    print(
        json.dumps(
            {
                "pairset": selected["pairset"],
                "pairs": selected["pairs"],
                "params": selected["params"],
                "mcpt_p": selected["mcpt_p"],
                "mcpt_pass": selected["mcpt_pass"],
                "full_ann": selected["full_stats"]["avg_annual_pnl"],
                "oos_ann": selected["oos_stats"]["avg_annual_pnl"],
                "funded_annual": selected["challenge"]["funded_annual_pnl"],
                "eval_passed": selected["challenge"]["evaluation_passed"],
                "funded_survived": selected["challenge"]["funded_survived"],
                "pass_rate": selected["pass_rate"],
                "trades": selected["full_stats"]["n_trades"],
                "pf": selected["full_stats"]["profit_factor"],
                "hard_winner": winner(selected),
            },
            indent=2,
        ),
        flush=True,
    )
    print(f"Elapsed {time.time()-t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
