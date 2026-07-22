#!/usr/bin/env python3
"""Focused refinement: winner pairs + risk overlays + MCPT/challenge gates."""

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
from mcpt.forex.mcpt_forex import run_forex_fixed_params_mcpt
from scripts.research.iterate_forex_strategy import load_book

OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)

# Empirically stronger majors from first pass
WINNER_PAIRS = ["EURUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD"]


def grid():
    configs = []
    for mode, risk, rr, atr, maxpos, be, dhalt, skip_mon in product(
        ["smc", "smc_strict", "sweep_bos", "combo"],
        [0.006, 0.0075, 0.009],
        [2.0, 2.5, 3.0],
        [1.25, 1.4],
        [2, 3],
        [0.0, 1.0],
        [0.015, 0.02],
        [True],
    ):
        configs.append(
            dict(
                signal_mode=mode,
                risk_pct=risk,
                rr=rr,
                atr_stop_mult=atr,
                max_positions=maxpos,
                min_confluence=3 if mode == "smc" else 2,
                swing_left=3,
                swing_right=3,
                require_killzone=False,
                weekly_withdraw=True,
                move_be_at_r=be,
                skip_mondays=skip_mon,
                daily_halt_loss_pct=dhalt,
                daily_halt_profit_pct=0.025,
                cooldown_losses=3,
            )
        )
    return configs


def main():
    t0 = time.time()
    book = load_book(WINNER_PAIRS)
    rules = FundedRules()
    configs = grid()
    print(f"Pairs={WINNER_PAIRS} configs={len(configs)}")

    survivors = []
    for i, p in enumerate(configs):
        bt = run_backtest(book, rules=rules, **p)
        s = bt.stats
        if (i + 1) % 150 == 0:
            print(f"  {i+1}/{len(configs)} surv={len(survivors)} ann=${s['avg_annual_pnl']:.0f}")
        if s["blown"] or not s["consistency_ok"]:
            continue
        if s["n_trades"] < 80:
            continue
        if s["avg_annual_pnl"] < 8_000:
            continue
        if s["max_dd"] > 7_500:
            continue
        survivors.append((p, s))

    print(f"Survivors >=$8k/yr: {len(survivors)}")
    if len(survivors) < 5:
        # take best by annual even if below target
        all_ok = []
        for p in configs:
            bt = run_backtest(book, rules=rules, **p)
            s = bt.stats
            if not s["blown"] and s["consistency_ok"] and s["n_trades"] >= 60:
                all_ok.append((p, s))
        all_ok.sort(key=lambda x: x[1]["avg_annual_pnl"], reverse=True)
        survivors = all_ok[:25]
        print(f"Fallback top25 best_ann=${survivors[0][1]['avg_annual_pnl']:.0f}")

    survivors.sort(key=lambda x: x[1]["avg_annual_pnl"], reverse=True)
    ranked = []
    for p, s in survivors[:30]:
        ch = simulate_challenge(book, rules=rules, **p)
        rolls = rolling_eval_windows(
            book,
            window_days=400,
            step_days=120,
            rules=rules,
            **{k: v for k, v in p.items() if k != "weekly_withdraw"},
        )
        pr = sum(1 for r in rolls if r["passed"]) / max(len(rolls), 1)
        score = (
            s["avg_annual_pnl"] / 1000
            + (5 if ch.evaluation_passed else 0)
            + (3 if ch.funded_survived else -2)
            + ch.funded_annual_pnl / 1000
            + pr * 8
            + min(s["profit_factor"], 4)
        )
        ranked.append(dict(score=score, params=p, stats=s, challenge=ch.to_dict(), pass_rate=pr))
        print(
            f"  [{p['signal_mode']}] ann=${s['avg_annual_pnl']:.0f} pf={s['profit_factor']:.2f} "
            f"tr={s['n_trades']} dd={s['max_dd']:.0f} eval={ch.evaluation_passed} "
            f"fund_ann=${ch.funded_annual_pnl:.0f} pr={pr:.2f} be={p['move_be_at_r']} risk={p['risk_pct']}"
        )

    ranked.sort(key=lambda x: x["score"], reverse=True)
    (OUT / "refine_ranked.json").write_text(json.dumps(ranked[:20], indent=2, default=str))

    finals = []
    for r in ranked[:8]:
        p = r["params"]
        train = {k: v[(v.index >= "2018-01-01") & (v.index <= "2021-12-31")] for k, v in book.items()}
        oos = {k: v[(v.index >= "2022-01-01") & (v.index <= "2023-12-31")] for k, v in book.items()}
        mcpt, tr_bt = run_forex_fixed_params_mcpt(
            train, {**p, "rules": rules}, n_permutations=120, threshold=0.05, seed=21
        )
        oos_bt = run_backtest(oos, rules=rules, **p)
        full_bt = run_backtest(book, rules=rules, **p)
        # challenge-style eval on rolling already have; also pure eval window 2018-2019
        eval_book = {k: v[(v.index >= "2018-01-01") & (v.index <= "2019-12-31")] for k, v in book.items()}
        eval_bt = run_backtest(eval_book, rules=rules, **{**p, "weekly_withdraw": False})
        rec = dict(
            params=p,
            pairs=WINNER_PAIRS,
            mcpt=mcpt.to_dict(),
            train_stats=tr_bt.stats,
            oos_stats=oos_bt.stats,
            full_stats=full_bt.stats,
            eval_2018_2019=eval_bt.stats,
            challenge=r["challenge"],
            pass_rate=r["pass_rate"],
            score=r["score"],
        )
        finals.append(rec)
        print(
            f"MCPT [{p['signal_mode']}] p={mcpt.p_value:.3f} pass={mcpt.passed} "
            f"full=${full_bt.stats['avg_annual_pnl']:.0f} oos=${oos_bt.stats['avg_annual_pnl']:.0f} "
            f"eval_hit={eval_bt.stats['hit_eval_target']} eval_max={eval_bt.equity_curve.max() if len(eval_bt.equity_curve) else 0:.0f}"
        )

    finals.sort(
        key=lambda x: (
            int(x["mcpt"]["passed"]),
            int(x["full_stats"]["avg_annual_pnl"] >= 10000),
            int(x["oos_stats"]["avg_annual_pnl"] > 0 and not x["oos_stats"]["blown"]),
            x["full_stats"]["avg_annual_pnl"],
            -x["mcpt"]["p_value"],
        ),
        reverse=True,
    )
    (OUT / "refine_mcpt.json").write_text(json.dumps(finals, indent=2, default=str))
    best = finals[0]
    (OUT / "best_strategy.json").write_text(json.dumps(best, indent=2, default=str))
    print("\nBEST:", json.dumps({
        "params": best["params"],
        "pairs": best["pairs"],
        "mcpt_p": best["mcpt"]["p_value"],
        "mcpt_pass": best["mcpt"]["passed"],
        "full_ann": best["full_stats"]["avg_annual_pnl"],
        "oos_ann": best["oos_stats"]["avg_annual_pnl"],
        "full_trades": best["full_stats"]["n_trades"],
        "consistency_ok": best["full_stats"]["consistency_ok"],
        "blown": best["full_stats"]["blown"],
        "eval_hit": best["eval_2018_2019"]["hit_eval_target"],
        "pass_rate": best["pass_rate"],
        "challenge": {
            "evaluation_passed": best["challenge"]["evaluation_passed"],
            "funded_survived": best["challenge"]["funded_survived"],
            "funded_annual_pnl": best["challenge"]["funded_annual_pnl"],
        },
    }, indent=2))
    print(f"Elapsed {time.time()-t0:.1f}s")


if __name__ == "__main__":
    main()
