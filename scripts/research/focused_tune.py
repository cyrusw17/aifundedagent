#!/usr/bin/env python3
"""Focused tune on safer risk / MCPT-friendly modes."""

from __future__ import annotations

import json
import sys
import time
from itertools import product
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

PAIRSETS = {
    "core5": ["EURUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD"],
    "majors4": ["EURUSD", "USDJPY", "USDCHF", "AUDUSD"],
    "all7": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD", "USDCHF"],
}


def mcpt(book, mode, swing, params, n=120, seed=3):
    def run(b):
        prep = prepare_book(b, mode, swing, 2)
        return fast_backtest(prep, **params)

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
        if obj(run(permute_forex_book(book, seed=seed + i))) >= rs:
            better += 1
    return better / n, real


def main():
    t0 = time.time()
    results = []
    for ps, pairs in PAIRSETS.items():
        book = load_book(pairs)
        print(f"=== {ps} ===", flush=True)
        for mode in ["weekly_smc", "smc", "smc_plus", "active_smc", "donchian_smc", "asia_sweep", "combo"]:
            for swing in [2, 3, 4]:
                prep = prepare_book(book, mode, swing, 2)
                local = 0
                for risk, rr, atr, mp, be, dhalt, skip_mon in product(
                    [0.004, 0.005, 0.0065, 0.0075, 0.009, 0.01],
                    [1.8, 2.0, 2.5, 3.0],
                    [1.1, 1.25, 1.4],
                    [1, 2, 3],
                    [0.0, 1.0],
                    [0.012, 0.015, 0.02],
                    [True, False],
                ):
                    params = dict(
                        risk_pct=risk,
                        rr=rr,
                        atr_stop_mult=atr,
                        max_positions=mp,
                        move_be_at_r=be,
                        skip_mondays=skip_mon,
                        daily_halt_loss_pct=dhalt,
                        daily_halt_profit_pct=0.03,
                        cooldown_losses=2,
                        weekly_withdraw=True,
                    )
                    st = fast_backtest(prep, **params)
                    if st.blown or not st.consistency_ok:
                        continue
                    if st.n_trades < 70:
                        continue
                    if st.avg_annual_pnl < 2000:
                        continue
                    results.append((st.avg_annual_pnl, ps, mode, swing, params, st.as_dict()))
                    local += 1
                if local:
                    print(f"  {mode}/swing{swing} hits={local}", flush=True)

    results.sort(key=lambda x: x[0], reverse=True)
    print(f"\nScreened {len(results)}", flush=True)
    for r in results[:20]:
        print(
            f"ann=${r[0]:.0f} tr={r[5]['n_trades']} pf={r[5]['profit_factor']:.2f} "
            f"dd={r[5]['max_dd']:.0f} {r[1]}|{r[2]} risk={r[4]['risk_pct']} rr={r[4]['rr']} mp={r[4]['max_positions']}",
            flush=True,
        )

    if not results:
        print("No screen hits — relaxing", flush=True)
        return

    finals = []
    for ann, ps, mode, swing, params, st in results[:20]:
        book = load_book(PAIRSETS[ps])
        train = {k: v[(v.index >= "2018-01-01") & (v.index <= "2021-06-30")] for k, v in book.items()}
        oos = {k: v[(v.index >= "2021-07-01") & (v.index <= "2023-12-31")] for k, v in book.items()}
        print(f"MCPT {ps}|{mode} screen=${ann:.0f}", flush=True)
        pval, _ = mcpt(train, mode, swing, params, n=120)
        full_params = dict(
            params,
            signal_mode=mode,
            swing_left=swing,
            swing_right=swing,
            min_confluence=2,
            require_killzone=False,
        )
        full = run_backtest(book, rules=FundedRules(), **full_params)
        oos_bt = run_backtest(oos, rules=FundedRules(), **full_params)
        ch = simulate_challenge(book, rules=FundedRules(), **full_params)
        rolls = rolling_eval_windows(
            book,
            window_days=400,
            step_days=120,
            rules=FundedRules(),
            **{k: v for k, v in full_params.items() if k != "weekly_withdraw"},
        )
        pr = sum(1 for x in rolls if x["passed"]) / max(len(rolls), 1)
        rec = dict(
            pairset=ps,
            pairs=PAIRSETS[ps],
            params=full_params,
            mcpt_p=pval,
            mcpt_pass=pval <= 0.05,
            full_stats=full.stats,
            oos_stats=oos_bt.stats,
            challenge=ch.to_dict(),
            pass_rate=pr,
        )
        finals.append(rec)
        print(
            f"  p={pval:.3f} full=${full.stats['avg_annual_pnl']:.0f} "
            f"oos=${oos_bt.stats['avg_annual_pnl']:.0f} fund=${ch.funded_annual_pnl:.0f} "
            f"eval={ch.evaluation_passed} pr={pr:.2f}",
            flush=True,
        )

    finals.sort(
        key=lambda r: (
            int(r["mcpt_pass"]),
            int(r["challenge"]["funded_survived"]),
            int(not r["full_stats"]["blown"]),
            max(r["full_stats"]["avg_annual_pnl"], r["challenge"]["funded_annual_pnl"]),
            r["oos_stats"]["avg_annual_pnl"],
            -r["mcpt_p"],
        ),
        reverse=True,
    )
    best = finals[0]
    (OUT / "best_strategy.json").write_text(json.dumps(best, indent=2, default=str))
    (OUT / "focused_tune.json").write_text(json.dumps(finals, indent=2, default=str))
    print("\nBEST", flush=True)
    print(
        json.dumps(
            {
                "pairset": best["pairset"],
                "params": best["params"],
                "mcpt_p": best["mcpt_p"],
                "mcpt_pass": best["mcpt_pass"],
                "full_ann": best["full_stats"]["avg_annual_pnl"],
                "oos_ann": best["oos_stats"]["avg_annual_pnl"],
                "fund_ann": best["challenge"]["funded_annual_pnl"],
                "eval": best["challenge"]["evaluation_passed"],
                "funded_survived": best["challenge"]["funded_survived"],
                "pr": best["pass_rate"],
                "trades": best["full_stats"]["n_trades"],
                "pf": best["full_stats"]["profit_factor"],
            },
            indent=2,
        ),
        flush=True,
    )
    print(f"Elapsed {time.time()-t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
