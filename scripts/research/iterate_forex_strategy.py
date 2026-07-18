#!/usr/bin/env python3
"""Iterate SMC/forex strategy configs until challenge + MCPT goals are met."""

from __future__ import annotations

import json
import sys
import time
from itertools import product
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.challenge import rolling_eval_windows, simulate_challenge
from mcpt.forex.mcpt_forex import run_forex_fixed_params_mcpt

DATA_DIR = ROOT / "data" / "forex"
OUT_DIR = ROOT / "data" / "research"
OUT_DIR.mkdir(parents=True, exist_ok=True)

PAIRS = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", "USDCHF"]


def load_book(pairs=None) -> dict[str, pd.DataFrame]:
    pairs = pairs or PAIRS
    book = {}
    for p in pairs:
        path = DATA_DIR / f"{p}_1d.parquet"
        df = pd.read_parquet(path)
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        df = df.sort_index()
        df = df[(df.index >= "2018-01-01") & (df.index <= "2023-12-31")]
        book[p] = df
    return book


def param_grid():
    modes = ["smc", "smc_strict", "sweep_bos", "trend_pullback", "breakout_hold", "combo"]
    grid = []
    for mode, risk_pct, rr, atr_stop_mult, max_positions, swing in product(
        modes,
        [0.005, 0.0075, 0.01],
        [2.0, 2.5, 3.0],
        [1.25, 1.5],
        [2, 3],
        [3],
    ):
        min_conf = 3 if mode == "smc" else 2
        grid.append(
            {
                "risk_pct": risk_pct,
                "rr": rr,
                "atr_stop_mult": atr_stop_mult,
                "min_confluence": min_conf,
                "max_positions": max_positions,
                "swing_left": swing,
                "swing_right": swing,
                "require_killzone": False,
                "weekly_withdraw": True,
                "signal_mode": mode,
            }
        )
    return grid


def score_candidate(stats: dict, challenge: dict, pass_rate: float) -> float:
    if stats.get("blown"):
        return -1e6
    ann = stats.get("avg_annual_pnl", 0)
    pf = min(stats.get("profit_factor", 0), 5)
    cons = 1.0 if stats.get("consistency_ok") else -2.0
    trades = min(stats.get("n_trades", 0) / 100.0, 2.0)
    dd_pen = -3.0 if stats.get("max_dd", 0) > 6000 else 0.0
    ch = 3.0 if challenge.get("evaluation_passed") else 0.0
    ch += 2.0 if challenge.get("funded_survived") else -2.0
    ch += min(max(challenge.get("funded_annual_pnl", 0), 0) / 10_000.0, 3.0)
    return ann / 1000.0 + pf * 1.2 + cons + trades + ch + pass_rate * 6.0 + dd_pen


def main():
    t0 = time.time()
    print("Loading forex book 2018-2023...")
    book = load_book()
    for p, df in book.items():
        print(f"  {p}: {len(df)} bars")

    rules = FundedRules()
    grid = param_grid()
    print(f"Searching {len(grid)} configurations...")

    screened = []
    for i, params in enumerate(grid):
        bt = run_backtest(book, rules=rules, **params)
        s = bt.stats
        if (i + 1) % 100 == 0:
            print(
                f"  {i+1}/{len(grid)} kept={len(screened)} "
                f"last_ann=${s['avg_annual_pnl']:.0f} trades={s['n_trades']} mode={params['signal_mode']}"
            )
        if s["n_trades"] < 50:
            continue
        if s["blown"]:
            continue
        if s["avg_annual_pnl"] < 4_000:
            continue
        if not s["consistency_ok"]:
            continue
        if s["max_dd"] > 9_000:
            continue
        screened.append((params, s))

    print(f"Phase-1 survivors: {len(screened)}")
    if len(screened) < 10:
        print("Relaxing filters for top annual PnL...")
        all_runs = []
        for params in grid[::2]:  # denser already; subsample if needed
            bt = run_backtest(book, rules=rules, **params)
            s = bt.stats
            if not s["blown"] and s["n_trades"] >= 30 and s["consistency_ok"]:
                all_runs.append((params, s))
        all_runs.sort(key=lambda x: x[1]["avg_annual_pnl"], reverse=True)
        screened = all_runs[:40]
        print(f"Relaxed top: {len(screened)} best_ann=${screened[0][1]['avg_annual_pnl']:.0f}")

    screened = sorted(screened, key=lambda x: x[1]["avg_annual_pnl"], reverse=True)[:50]
    ranked = []
    for params, s in screened:
        ch = simulate_challenge(
            book,
            eval_end="2020-12-31",
            funded_end="2023-12-31",
            rules=rules,
            **params,
        )
        rolls = rolling_eval_windows(
            book,
            start="2018-01-01",
            end="2023-12-31",
            window_days=420,
            step_days=150,
            rules=rules,
            **{k: v for k, v in params.items() if k != "weekly_withdraw"},
        )
        pass_rate = sum(1 for r in rolls if r["passed"]) / max(len(rolls), 1)
        sc = score_candidate(s, ch.to_dict(), pass_rate)
        ranked.append(
            {
                "score": sc,
                "params": params,
                "full_stats": s,
                "challenge": ch.to_dict(),
                "pass_rate": pass_rate,
            }
        )
        print(
            f"  [{params['signal_mode']}] ann=${s['avg_annual_pnl']:.0f} pf={s['profit_factor']:.2f} "
            f"tr={s['n_trades']} dd={s['max_dd']:.0f} eval={ch.evaluation_passed} "
            f"fund_ann=${ch.funded_annual_pnl:.0f} pass_rate={pass_rate:.2f} "
            f"rr={params['rr']} risk={params['risk_pct']}"
        )

    ranked.sort(key=lambda x: x["score"], reverse=True)
    (OUT_DIR / "phase2_ranked.json").write_text(json.dumps(ranked[:20], indent=2, default=str))

    mcpt_candidates = [
        r
        for r in ranked
        if r["full_stats"]["avg_annual_pnl"] >= 7_000
        and r["challenge"]["funded_survived"]
        and r["full_stats"]["consistency_ok"]
    ][:10]
    if not mcpt_candidates:
        mcpt_candidates = ranked[:6]

    print(f"\nPhase-3 MCPT on {len(mcpt_candidates)} candidates...")
    mcpt_results = []
    for r in mcpt_candidates:
        params = dict(r["params"])
        train = {
            p: df[(df.index >= "2018-01-01") & (df.index <= "2021-12-31")].copy()
            for p, df in book.items()
        }
        oos = {
            p: df[(df.index >= "2022-01-01") & (df.index <= "2023-12-31")].copy()
            for p, df in book.items()
        }
        print(f"  MCPT {params['signal_mode']} rr={params['rr']} risk={params['risk_pct']}")
        mcpt, bt = run_forex_fixed_params_mcpt(
            train, {**params, "rules": rules}, n_permutations=100, threshold=0.05, seed=11
        )
        oos_bt = run_backtest(oos, rules=rules, **params)
        full_bt = run_backtest(book, rules=rules, **params)
        rec = {
            "params": params,
            "mcpt": mcpt.to_dict(),
            "train_stats": bt.stats,
            "oos_stats": oos_bt.stats,
            "full_stats": full_bt.stats,
            "challenge": r["challenge"],
            "pass_rate": r["pass_rate"],
            "score": r["score"],
        }
        mcpt_results.append(rec)
        print(
            f"    p={mcpt.p_value:.3f} pass={mcpt.passed} "
            f"full_ann=${full_bt.stats['avg_annual_pnl']:.0f} "
            f"oos_ann=${oos_bt.stats['avg_annual_pnl']:.0f} "
            f"oos_blown={oos_bt.stats['blown']} cons={full_bt.stats['consistency_ok']}"
        )

    def rank_key(x):
        return (
            int(x["mcpt"]["passed"]),
            int(x["oos_stats"].get("avg_annual_pnl", 0) >= 8000 and not x["oos_stats"].get("blown")),
            x["full_stats"].get("avg_annual_pnl", 0),
            -x["mcpt"]["p_value"],
        )

    mcpt_results.sort(key=rank_key, reverse=True)
    (OUT_DIR / "mcpt_results.json").write_text(json.dumps(mcpt_results, indent=2, default=str))
    best = mcpt_results[0]
    (OUT_DIR / "best_strategy.json").write_text(json.dumps(best, indent=2, default=str))

    print("\n=== BEST ===")
    print(
        json.dumps(
            {
                "params": best["params"],
                "mcpt_p": best["mcpt"]["p_value"],
                "mcpt_pass": best["mcpt"]["passed"],
                "full": best["full_stats"],
                "oos": best["oos_stats"],
                "challenge": {
                    "evaluation_passed": best["challenge"]["evaluation_passed"],
                    "funded_survived": best["challenge"]["funded_survived"],
                    "funded_annual_pnl": best["challenge"]["funded_annual_pnl"],
                },
                "pass_rate": best["pass_rate"],
            },
            indent=2,
            default=str,
        )
    )
    print(f"\nElapsed {time.time()-t0:.1f}s  results -> {OUT_DIR}")


if __name__ == "__main__":
    main()
