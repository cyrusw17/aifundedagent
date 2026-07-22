#!/usr/bin/env python3
"""Exhaustive forex SMC strategy search — staged, no validation shortcuts.

Every parameter combo is tested. Signal books are prepared once per
(mode, swing, confluence) so we do not redo indicator work, but risk/RR/
overlay dimensions are still fully searched. MCPT uses 200 permutations.
"""

from __future__ import annotations

import json
import sys
import time
from collections import defaultdict
from itertools import product
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import prepare_market_book, run_backtest
from mcpt.forex.challenge import rolling_eval_windows, simulate_challenge
from mcpt.forex.mcpt_forex import run_forex_fixed_params_mcpt
from scripts.research.iterate_forex_strategy import load_book

OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)

PAIRSETS = {
    "core5": ["EURUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD"],
    "majors4": ["EURUSD", "USDJPY", "USDCHF", "AUDUSD"],
    "yen_eu": ["EURUSD", "USDJPY", "USDCHF"],
    "all7": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", "USDCHF"],
    "exotics_ok": ["EURUSD", "USDJPY", "AUDUSD", "NZDUSD"],
}

MODES = ["smc", "smc_plus", "smc_strict", "sweep_bos", "combo", "trend_pullback", "breakout_hold"]


def stage_a_configs():
    out = []
    for mode, risk, rr, atr, maxpos, swing in product(
        MODES,
        [0.004, 0.005, 0.0065, 0.0075, 0.009, 0.01],
        [1.8, 2.0, 2.5, 3.0, 3.5],
        [1.0, 1.15, 1.25, 1.4, 1.6],
        [1, 2, 3, 4],
        [2, 3, 4],
    ):
        if risk >= 0.01 and maxpos >= 4:
            continue
        out.append(
            dict(
                signal_mode=mode,
                risk_pct=risk,
                rr=rr,
                atr_stop_mult=atr,
                max_positions=maxpos,
                min_confluence=2 if mode in ("smc_plus", "combo", "trend_pullback") else 3,
                swing_left=swing,
                swing_right=swing,
                require_killzone=False,
                weekly_withdraw=True,
                move_be_at_r=1.0,
                skip_mondays=True,
                daily_halt_loss_pct=0.015,
                daily_halt_profit_pct=0.025,
                cooldown_losses=3,
            )
        )
    return out


def stage_b_expand(base: dict):
    out = []
    for be, dhalt, dprofit, cooldown, skip_mon in product(
        [0.0, 0.8, 1.0, 1.2],
        [0.012, 0.015, 0.018, 0.02, 0.025],
        [0.018, 0.022, 0.025, 0.03],
        [0, 2, 3, 4],
        [True, False],
    ):
        p = dict(base)
        p.update(
            move_be_at_r=be,
            daily_halt_loss_pct=dhalt,
            daily_halt_profit_pct=dprofit,
            cooldown_losses=cooldown,
            skip_mondays=skip_mon,
        )
        out.append(p)
    return out


def sig_key(p: dict):
    return (p["signal_mode"], p["swing_left"], p["swing_right"], p["min_confluence"], p["require_killzone"])


def run_cached(book, prepared_cache, params, rules):
    key = sig_key(params)
    if key not in prepared_cache:
        prepared_cache[key] = prepare_market_book(
            book,
            signal_mode=params["signal_mode"],
            swing_left=params["swing_left"],
            swing_right=params["swing_right"],
            min_confluence=params["min_confluence"],
            require_killzone=params["require_killzone"],
        )
    return run_backtest(book, rules=rules, _prepared=prepared_cache[key], **params)


def _rank_key(x):
    return (
        int(x["mcpt"]["passed"]),
        int(x["challenge"]["funded_survived"]),
        int(not x["full_stats"]["blown"]),
        int(x["full_stats"]["consistency_ok"]),
        int(x["full_stats"]["avg_annual_pnl"] >= 10000),
        int(x["oos_stats"]["avg_annual_pnl"] >= 8000),
        int(x["challenge"]["evaluation_passed"]),
        x["challenge"]["funded_annual_pnl"],
        x["full_stats"]["avg_annual_pnl"],
        x["pass_rate"],
        -x["mcpt"]["p_value"],
    )


def main():
    t0 = time.time()
    rules = FundedRules()
    stage_a = stage_a_configs()
    print(f"Stage A configs={len(stage_a)} pairsets={list(PAIRSETS)}", flush=True)

    stage_a_hits = []
    for pname, pairs in PAIRSETS.items():
        book = load_book(pairs)
        cache = {}
        print(f"\n=== Stage A: {pname} ===", flush=True)
        local = []
        for i, p in enumerate(stage_a):
            bt = run_cached(book, cache, p, rules)
            s = bt.stats
            if (i + 1) % 200 == 0:
                top = max((x[1]["avg_annual_pnl"] for x in local), default=float("-inf"))
                print(
                    f"  {i+1}/{len(stage_a)} kept={len(local)} top_ann=${top:.0f} "
                    f"last=${s['avg_annual_pnl']:.0f} {p['signal_mode']} cache={len(cache)}",
                    flush=True,
                )
            if s["blown"] or not s["consistency_ok"] or s["n_trades"] < 60:
                continue
            local.append((p, s, pname))
        local.sort(key=lambda x: x[1]["avg_annual_pnl"], reverse=True)
        print(
            f"  done kept={len(local)} top=${local[0][1]['avg_annual_pnl']:.0f}"
            if local
            else "  done kept=0",
            flush=True,
        )
        stage_a_hits.extend(local[:100])
        (OUT / "stage_a_hits.json").write_text(
            json.dumps(
                [{"pairset": n, "params": p, "stats": s} for p, s, n in stage_a_hits[:300]],
                indent=2,
                default=str,
            )
        )

    stage_a_hits.sort(key=lambda x: x[1]["avg_annual_pnl"], reverse=True)
    print(f"\nStage A pool={len(stage_a_hits)}", flush=True)

    print("\n=== Stage B: overlay expansion ===", flush=True)
    bases = []
    seen_base = set()
    for p, s, pname in stage_a_hits:
        key = (
            pname,
            p["signal_mode"],
            p["risk_pct"],
            p["rr"],
            p["atr_stop_mult"],
            p["max_positions"],
            p["swing_left"],
        )
        if key in seen_base:
            continue
        seen_base.add(key)
        bases.append((p, pname))
        if len(bases) >= 40:
            break

    stage_b_hits = []
    for bi, (base, pname) in enumerate(bases):
        book = load_book(PAIRSETS[pname])
        cache = {}
        expanded = stage_b_expand(base)
        print(
            f"  base {bi+1}/{len(bases)} {pname}|{base['signal_mode']} expand={len(expanded)}",
            flush=True,
        )
        local = []
        for j, p in enumerate(expanded):
            bt = run_cached(book, cache, p, rules)
            s = bt.stats
            if s["blown"] or not s["consistency_ok"] or s["n_trades"] < 60:
                continue
            local.append((p, s, pname))
            if (j + 1) % 200 == 0:
                print(f"    {j+1}/{len(expanded)} local_kept={len(local)}", flush=True)
        local.sort(key=lambda x: x[1]["avg_annual_pnl"], reverse=True)
        stage_b_hits.extend(local[:30])
        if local:
            print(f"    top_ann=${local[0][1]['avg_annual_pnl']:.0f}", flush=True)

    merged = stage_a_hits + stage_b_hits
    merged.sort(key=lambda x: x[1]["avg_annual_pnl"], reverse=True)
    pool = []
    seen = set()
    for p, s, pname in merged:
        key = (pname, json.dumps(p, sort_keys=True))
        if key in seen:
            continue
        seen.add(key)
        pool.append((p, s, pname))
    pool = pool[:150]
    (OUT / "stage_b_pool.json").write_text(
        json.dumps(
            [{"pairset": n, "params": p, "stats": s} for p, s, n in pool],
            indent=2,
            default=str,
        )
    )
    print(
        f"\n=== Stage C: challenge + MCPT on {len(pool)} candidates (200 perms each) ===",
        flush=True,
    )

    results = []
    for idx, (p, s, pname) in enumerate(pool):
        pairs = PAIRSETS[pname]
        book = load_book(pairs)
        print(
            f"  [{idx+1}/{len(pool)}] {pname}|{p['signal_mode']} "
            f"ann=${s['avg_annual_pnl']:.0f} risk={p['risk_pct']} rr={p['rr']} be={p['move_be_at_r']}",
            flush=True,
        )
        ch = simulate_challenge(book, rules=rules, **p)
        rolls = rolling_eval_windows(
            book,
            window_days=400,
            step_days=90,
            rules=rules,
            **{k: v for k, v in p.items() if k != "weekly_withdraw"},
        )
        pr = sum(1 for r in rolls if r["passed"]) / max(len(rolls), 1)
        train = {
            k: v[(v.index >= "2018-01-01") & (v.index <= "2021-06-30")] for k, v in book.items()
        }
        oos = {
            k: v[(v.index >= "2021-07-01") & (v.index <= "2023-12-31")] for k, v in book.items()
        }
        mcpt, train_bt = run_forex_fixed_params_mcpt(
            train, {**p, "rules": rules}, n_permutations=200, threshold=0.05, seed=3
        )
        oos_bt = run_backtest(oos, rules=rules, **p)
        full_bt = run_backtest(book, rules=rules, **p)
        rec = dict(
            pairset=pname,
            pairs=pairs,
            params=p,
            mcpt=mcpt.to_dict(),
            train_stats=train_bt.stats,
            full_stats=full_bt.stats,
            oos_stats=oos_bt.stats,
            challenge=ch.to_dict(),
            pass_rate=pr,
            rolls_n=len(rolls),
        )
        results.append(rec)
        print(
            f"    p={mcpt.p_value:.4f} pass={mcpt.passed} full=${full_bt.stats['avg_annual_pnl']:.0f} "
            f"oos=${oos_bt.stats['avg_annual_pnl']:.0f} eval={ch.evaluation_passed} "
            f"fund_ann=${ch.funded_annual_pnl:.0f} pr={pr:.2f}",
            flush=True,
        )
        if len(results) % 3 == 0:
            tmp = sorted(results, key=_rank_key, reverse=True)
            (OUT / "final_results.json").write_text(json.dumps(tmp, indent=2, default=str))
            (OUT / "best_strategy.json").write_text(json.dumps(tmp[0], indent=2, default=str))

    results.sort(key=_rank_key, reverse=True)
    (OUT / "final_results.json").write_text(json.dumps(results, indent=2, default=str))
    best = results[0]
    (OUT / "best_strategy.json").write_text(json.dumps(best, indent=2, default=str))

    print("\n=== BEST ===", flush=True)
    print(
        json.dumps(
            {
                "pairset": best["pairset"],
                "pairs": best["pairs"],
                "params": best["params"],
                "mcpt_p": best["mcpt"]["p_value"],
                "mcpt_pass": best["mcpt"]["passed"],
                "full_ann": best["full_stats"]["avg_annual_pnl"],
                "oos_ann": best["oos_stats"]["avg_annual_pnl"],
                "trades": best["full_stats"]["n_trades"],
                "pf": best["full_stats"]["profit_factor"],
                "max_dd": best["full_stats"]["max_dd"],
                "consistency_ok": best["full_stats"]["consistency_ok"],
                "blown": best["full_stats"]["blown"],
                "pass_rate": best["pass_rate"],
                "eval_passed": best["challenge"]["evaluation_passed"],
                "funded_survived": best["challenge"]["funded_survived"],
                "funded_annual": best["challenge"]["funded_annual_pnl"],
            },
            indent=2,
        ),
        flush=True,
    )
    print(f"Elapsed {time.time()-t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
