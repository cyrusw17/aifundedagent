#!/usr/bin/env python3
import json
import sys
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.challenge import rolling_eval_windows, simulate_challenge
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.mcpt_forex import permute_forex_book
from scripts.research.iterate_forex_strategy import load_book

base = json.load(open(ROOT / "data/research/best_strategy.json"))["params"]
pairs = ["EURUSD", "USDJPY", "USDCHF", "AUDUSD"]
book = load_book(pairs)
train = {k: v[(v.index >= "2018-01-01") & (v.index <= "2021-06-30")] for k, v in book.items()}
oos = {k: v[(v.index >= "2021-07-01") & (v.index <= "2023-12-31")] for k, v in book.items()}


def mcpt(p, n=100):
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
            daily_halt_profit_pct=p["daily_halt_profit_pct"],
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

    real = run(train)
    rs = obj(real)
    better = 1
    for i in range(1, n):
        if obj(run(permute_forex_book(train, seed=11 + i))) >= rs:
            better += 1
    return better / n


def main():
    rows = []
    for risk in [0.0075, 0.009, 0.01, 0.012, 0.015, 0.018, 0.02]:
        for rr in [2.5, 3.0, 3.5]:
            for dhalt in [0.015, 0.02, 0.025]:
                p = deepcopy(base)
                p.update(risk_pct=risk, rr=rr, max_positions=1, daily_halt_loss_pct=dhalt)
                full = run_backtest(book, rules=FundedRules(), **p)
                s = full.stats
                if s["blown"] or not s["consistency_ok"]:
                    continue
                oos_bt = run_backtest(oos, rules=FundedRules(), **p)
                if oos_bt.stats["blown"]:
                    continue
                ch = simulate_challenge(book, rules=FundedRules(), **p)
                if not ch.funded_survived:
                    continue
                print(
                    f"full=${s['avg_annual_pnl']:.0f} oos=${oos_bt.stats['avg_annual_pnl']:.0f} "
                    f"fund=${ch.funded_annual_pnl:.0f} eval={ch.evaluation_passed} "
                    f"risk={risk} rr={rr} dhalt={dhalt} tr={s['n_trades']}",
                    flush=True,
                )
                rows.append((s["avg_annual_pnl"], p, s, oos_bt.stats, ch))

    rows.sort(reverse=True)
    print("kept", len(rows), flush=True)
    if not rows:
        return
    finals = []
    for ann, p, s, os_, ch in rows[:8]:
        pv = mcpt(p, n=120)
        rolls = rolling_eval_windows(
            book,
            window_days=400,
            step_days=120,
            rules=FundedRules(),
            **{k: v for k, v in p.items() if k != "weekly_withdraw"},
        )
        pr = sum(1 for r in rolls if r["passed"]) / max(len(rolls), 1)
        print(
            f"MCPT p={pv:.3f} full=${ann:.0f} oos=${os_['avg_annual_pnl']:.0f} "
            f"fund=${ch.funded_annual_pnl:.0f} pr={pr:.2f} risk={p['risk_pct']}",
            flush=True,
        )
        finals.append(
            dict(
                pairset="majors4",
                pairs=pairs,
                params=p,
                mcpt_p=pv,
                mcpt_pass=pv <= 0.05,
                full_stats=s,
                oos_stats=os_,
                challenge=ch.to_dict(),
                pass_rate=pr,
            )
        )

    finals.sort(
        key=lambda r: (
            int(r["mcpt_pass"]),
            r["full_stats"]["avg_annual_pnl"],
            r["challenge"]["funded_annual_pnl"],
        ),
        reverse=True,
    )
    best = finals[0]
    (ROOT / "data/research/best_strategy.json").write_text(
        json.dumps(best, indent=2, default=str)
    )
    print(
        "BEST",
        json.dumps(
            {
                "params": best["params"],
                "mcpt_p": best["mcpt_p"],
                "full_ann": best["full_stats"]["avg_annual_pnl"],
                "oos_ann": best["oos_stats"]["avg_annual_pnl"],
                "fund_ann": best["challenge"]["funded_annual_pnl"],
                "eval": best["challenge"]["evaluation_passed"],
                "survived": best["challenge"]["funded_survived"],
                "pr": best["pass_rate"],
                "trades": best["full_stats"]["n_trades"],
                "pf": best["full_stats"]["profit_factor"],
            },
            indent=2,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
