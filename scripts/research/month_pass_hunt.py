#!/usr/bin/env python3
"""Hunt configs that pass The5ers eval (+10%) within ~35 days, then survive funded."""

from __future__ import annotations

import json
import random
import sys
import time
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.challenge import simulate_challenge
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.month_challenge import fast_rolling_month_eval, rolling_month_eval
from mcpt.forex.mcpt_forex import permute_forex_book
from scripts.research.h1_hunt import load_h1, maybe_write_best, rank_key

OUT = ROOT / "data" / "research"
PAIRSETS = {
    "h1_majors4": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"],
    "h1_core5": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF"],
    "h1_all6": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF", "USDCAD"],
}
MODES = ["h1_sweep_bos", "kz_active", "kz_fvg", "london_asia_sweep", "killzone_smc", "active_smc"]
SWING = 3
WINDOW = 35
STEP = 21  # screen
MAX_DAYS = 35


def sample(rng: random.Random) -> dict:
    return dict(
        signal_mode=rng.choice(MODES),
        risk_pct=rng.choice([0.0075, 0.009, 0.01, 0.012, 0.015, 0.018, 0.02]),
        rr=rng.choice([1.5, 1.8, 2.0, 2.5, 3.0]),
        atr_stop_mult=rng.choice([0.7, 0.8, 1.0, 1.2]),
        max_positions=rng.choice([1, 2, 3, 4]),
        min_confluence=2,
        swing_left=SWING,
        swing_right=SWING,
        require_killzone=False,
        weekly_withdraw=True,
        move_be_at_r=rng.choice([0.0, 1.0]),
        skip_mondays=rng.choice([True, False]),
        daily_halt_loss_pct=rng.choice([0.015, 0.02, 0.025, 0.03]),
        daily_halt_profit_pct=rng.choice([0.03, 0.04, 0.05]),
        cooldown_losses=rng.choice([0, 2, 3]),
        one_entry_per_day=rng.choice([True, False]),
    )


def sim_kwargs(p: dict) -> dict:
    return dict(
        risk_pct=p["risk_pct"],
        rr=p["rr"],
        atr_stop_mult=p["atr_stop_mult"],
        max_positions=p["max_positions"],
        move_be_at_r=p["move_be_at_r"],
        skip_mondays=p["skip_mondays"],
        daily_halt_loss_pct=p["daily_halt_loss_pct"],
        daily_halt_profit_pct=p["daily_halt_profit_pct"],
        cooldown_losses=p["cooldown_losses"],
        one_entry_per_day=p["one_entry_per_day"],
    )


def lean_mcpt(book, params, n=80, seed=11):
    import pandas as pd

    cut = pd.Timestamp("2020-06-30")
    train = {k: v[v.index <= cut] for k, v in book.items()}

    def run(b):
        prep = prepare_book(b, params["signal_mode"], params["swing_left"], 2)
        return fast_backtest(prep, weekly_withdraw=True, **sim_kwargs(params))

    def obj(st):
        if st.blown:
            return -1
        if not st.consistency_ok:
            return 0
        return min(st.profit_factor, 5) * 0.2 + (st.avg_annual_pnl / 10000) * 0.5 + min(st.n_trades / 200, 1) * 0.1

    real = run(train)
    rs = obj(real)
    better = 1
    for i in range(1, n):
        if obj(run(permute_forex_book(train, seed=seed + i))) >= rs:
            better += 1
    return better / n


def screen_month(prepared, p) -> tuple[float, object]:
    # skip binary-search days during screen: monkey via local copy of loop
    from mcpt.forex.month_challenge import slice_prepared
    from mcpt.forex.fast_sim import fast_backtest as fb
    from mcpt.forex.account import FundedRules

    rules = FundedRules()
    pairs = prepared["__meta__"]["pairs"]
    start_ts = max(__import__("pandas").Timestamp(prepared[x]["index"].min()) for x in pairs)
    end_ts = min(__import__("pandas").Timestamp(prepared[x]["index"].max()) for x in pairs)
    pd = __import__("pandas")
    cursor = start_ts
    n = n_pass = blown = 0
    while cursor + pd.Timedelta(days=WINDOW) <= end_ts:
        sl = slice_prepared(prepared, cursor, cursor + pd.Timedelta(days=WINDOW))
        if not sl or len(sl["__meta__"]["timeline"]) < 80:
            cursor += pd.Timedelta(days=STEP)
            continue
        st = fb(sl, weekly_withdraw=False, rules=rules, **sim_kwargs(p))
        n += 1
        if st.blown:
            blown += 1
        elif st.hit_eval_target and st.consistency_ok:
            n_pass += 1
        cursor += pd.Timedelta(days=STEP)
    rate = n_pass / n if n else 0.0
    return rate, {"n": n, "n_pass": n_pass, "blown": blown}


def funded_after_month_passes(book, params, month: object, hold_days: int = 90) -> dict:
    """For each month-pass window, run funded (withdraw on) for hold_days after window start+days."""
    import pandas as pd

    rules = FundedRules()
    surv = 0
    checked = 0
    fund_anns = []
    for d in month.details:
        if not d["passed"] or d["days_to_target"] is None:
            continue
        start = pd.Timestamp(d["start"]) + pd.Timedelta(days=int(d["days_to_target"]))
        end = start + pd.Timedelta(days=hold_days)
        sl = {k: v[(v.index > start) & (v.index <= end)].copy() for k, v in book.items()}
        if min(len(x) for x in sl.values()) < 50:
            continue
        p = dict(params)
        p["weekly_withdraw"] = True
        bt = run_backtest(sl, rules=rules, **p)
        checked += 1
        if not bt.stats["blown"] and bt.stats["consistency_ok"]:
            surv += 1
            fund_anns.append(bt.stats["avg_annual_pnl"])
    return {
        "n_checked": checked,
        "n_survived": surv,
        "survive_rate": surv / checked if checked else 0.0,
        "median_fund_ann": float(sorted(fund_anns)[len(fund_anns) // 2]) if fund_anns else None,
    }


def main():
    t0 = time.time()
    rng = random.Random(99)
    n_screen = 2500
    books = {ps: load_h1(pairs) for ps, pairs in PAIRSETS.items()}
    prep = {}
    for ps, book in books.items():
        for mode in MODES:
            print(f"prepare {ps}|{mode}", flush=True)
            prep[(ps, mode)] = prepare_book(book, mode, SWING, 2)

    # seed with current best
    seeds = []
    best_path = OUT / "best_strategy.json"
    if best_path.exists():
        cur = json.loads(best_path.read_text())
        if cur.get("timeframe") == "1h":
            seeds.append((cur.get("pairset", "h1_core5"), cur["params"]))

    hits = []
    for i in range(n_screen):
        if seeds and i < len(seeds) * 40:
            base_ps, base_p = seeds[i % len(seeds)]
            ps = base_ps if base_ps in PAIRSETS else rng.choice(list(PAIRSETS))
            p = deepcopy(base_p)
            # mutate aggressively toward faster eval
            if rng.random() < 0.8:
                p["risk_pct"] = rng.choice([0.01, 0.012, 0.015, 0.018, 0.02])
            if rng.random() < 0.5:
                p["max_positions"] = rng.choice([2, 3, 4])
            if rng.random() < 0.5:
                p["one_entry_per_day"] = False
            if rng.random() < 0.4:
                p["rr"] = rng.choice([1.5, 1.8, 2.0, 2.5])
            if rng.random() < 0.4:
                p["signal_mode"] = rng.choice(MODES)
            if rng.random() < 0.3:
                p["daily_halt_loss_pct"] = rng.choice([0.02, 0.025, 0.03])
        else:
            ps = rng.choice(list(PAIRSETS))
            p = sample(rng)
        if p["risk_pct"] >= 0.018 and p["max_positions"] >= 3 and not p["one_entry_per_day"]:
            p["one_entry_per_day"] = True  # safety

        rate, meta = screen_month(prep[(ps, p["signal_mode"])], p)
        if (i + 1) % 100 == 0:
            top = max((h[0] for h in hits), default=0)
            print(
                f"  screened {i+1}/{n_screen} hits={len(hits)} top_rate={top:.2f} "
                f"elapsed={time.time()-t0:.0f}s",
                flush=True,
            )
        if rate < 0.35:
            continue
        # full-period health via fast
        st = fast_backtest(prep[(ps, p["signal_mode"])], weekly_withdraw=True, **sim_kwargs(p))
        if st.blown or not st.consistency_ok:
            continue
        hits.append((rate, st.avg_annual_pnl, ps, p, meta, st.as_dict()))

    hits.sort(key=lambda x: (x[0], x[1]), reverse=True)
    print(f"screen hits>={0.35}: {len(hits)}", flush=True)
    for h in hits[:25]:
        print(
            f"rate={h[0]:.2f} ann=${h[1]:.0f} {h[2]}|{h[3]['signal_mode']} "
            f"risk={h[3]['risk_pct']} rr={h[3]['rr']} mp={h[3]['max_positions']} "
            f"one={h[3]['one_entry_per_day']} dhalt={h[3]['daily_halt_loss_pct']}",
            flush=True,
        )
    (OUT / "month_pass_hits.json").write_text(
        json.dumps(
            [
                {
                    "month_pass_rate": h[0],
                    "screen_ann": h[1],
                    "pairset": h[2],
                    "params": h[3],
                    "screen_meta": h[4],
                    "full_fast": h[5],
                }
                for h in hits[:80]
            ],
            indent=2,
            default=str,
        )
    )

    # Validate top diverse with full month eval + challenge + MCPT
    best = None
    hard = None
    seen = set()
    cands = []
    for h in hits:
        p = h[3]
        key = (h[2], p["signal_mode"], p["risk_pct"], p["rr"], p["max_positions"], p["one_entry_per_day"])
        if key in seen:
            continue
        seen.add(key)
        cands.append(h)
        if len(cands) >= 12:
            break

    rows = []
    for rate, sann, ps, p, meta, fst in cands:
        book = books[ps]
        print(
            f"\nvalidate {ps}|{p['signal_mode']} screen_rate={rate:.2f} ann=${sann:.0f}",
            flush=True,
        )
        month = rolling_month_eval(
            book,
            window_days=WINDOW,
            step_days=14,
            max_days_to_pass=MAX_DAYS,
            rules=FundedRules(),
            **{**p, "weekly_withdraw": False},
        )
        print(
            f"  full month rate={month.pass_rate:.2f} ({month.n_passed}/{month.n_windows}) "
            f"median_days={month.median_days} p90={month.p90_days} blown={month.n_blown}",
            flush=True,
        )
        if month.pass_rate < 0.40 or month.n_passed < 8:
            continue
        if month.median_days > 30:
            continue

        full = run_backtest(book, rules=FundedRules(), **p)
        print(
            f"  full ann=${full.stats['avg_annual_pnl']:.0f} blown={full.stats['blown']} "
            f"cons={full.stats['consistency_ok']} tr={full.stats['n_trades']}",
            flush=True,
        )
        if full.stats["blown"] or not full.stats["consistency_ok"]:
            continue

        fund = funded_after_month_passes(book, p, month, hold_days=90)
        print(
            f"  post-pass funded90 surv={fund['survive_rate']:.2f} "
            f"({fund['n_survived']}/{fund['n_checked']}) med_ann={fund['median_fund_ann']}",
            flush=True,
        )
        if fund["n_checked"] < 5 or fund["survive_rate"] < 0.5:
            continue

        ch = simulate_challenge(
            book,
            eval_end="2020-06-30",
            funded_end=str(min(v.index.max() for v in book.values()).date()),
            rules=FundedRules(),
            **p,
        )
        print(
            f"  challenge eval={ch.evaluation_passed} days={ch.evaluation_days} "
            f"surv={ch.funded_survived} fund_ann=${ch.funded_annual_pnl:.0f}",
            flush=True,
        )

        print("  MCPT80...", flush=True)
        pv = lean_mcpt(book, p, n=80)
        print(f"  p={pv:.3f}", flush=True)
        if pv <= 0.10:
            pv = lean_mcpt(book, p, n=120)
            print(f"  p120={pv:.3f}", flush=True)

        recent = load_h1(PAIRSETS[ps], recent=True)
        recent_stats = None
        if recent:
            recent_stats = run_backtest(recent, rules=FundedRules(), **p).stats
            print(
                f"  recent ann=${recent_stats['avg_annual_pnl']:.0f} blown={recent_stats['blown']}",
                flush=True,
            )

        rec = dict(
            pairset=ps,
            pairs=list(book.keys()),
            timeframe="1h",
            data_window="2018-01-01..2022-03-04",
            params=p,
            mcpt_p=pv,
            mcpt_pass=pv <= 0.05,
            full_stats=full.stats,
            oos_stats=full.stats,  # filled below
            recent_stats=recent_stats,
            challenge=ch.to_dict(),
            month_pass=month.to_dict(),
            post_pass_funded90=fund,
            challenge_eval_end="2020-06-30",
            goal="pass_eval_within_~35_days",
        )
        import pandas as pd

        oos = {k: v[v.index > pd.Timestamp("2020-06-30")] for k, v in book.items()}
        rec["oos_stats"] = run_backtest(oos, rules=FundedRules(), **p).stats

        rows.append(rec)
        (OUT / "month_pass_latest.json").write_text(json.dumps(rec, indent=2, default=str))

        # hard winner: month rate>=0.45, median days<=30, funded surv>=0.55, not blown, prefer mcpt
        hard_ok = (
            month.pass_rate >= 0.45
            and month.median_days <= 30
            and fund["survive_rate"] >= 0.55
            and not full.stats["blown"]
            and full.stats["consistency_ok"]
            and ch.evaluation_passed
            and ch.evaluation_days != -1
            and ch.evaluation_days <= 40
        )
        key = (
            int(hard_ok),
            int(rec["mcpt_pass"]),
            month.pass_rate,
            fund["survive_rate"],
            -month.median_days if month.median_days == month.median_days else -99,
            full.stats["avg_annual_pnl"],
        )
        if best is None or key > best[0]:
            best = (key, rec)
            (OUT / "month_pass_best.json").write_text(json.dumps(rec, indent=2, default=str))
            # write best_strategy if improves month-pass goal over existing
            wrote, _ = maybe_write_best(rec)
            # always write if hard_ok
            if hard_ok:
                (OUT / "best_strategy.json").write_text(json.dumps(rec, indent=2, default=str))
                print("  WROTE best_strategy.json (month-pass winner)", flush=True)
                hard = rec
                break
            elif wrote:
                print("  wrote best_strategy via rank", flush=True)

    (OUT / "month_pass_validated.json").write_text(json.dumps(rows, indent=2, default=str))
    summary = {
        "hard": bool(hard),
        "screen_hits": len(hits),
        "validated": len(rows),
        "elapsed_s": time.time() - t0,
        "best_month_rate": None if not best else best[1]["month_pass"]["pass_rate"],
        "best_median_days": None if not best else best[1]["month_pass"]["median_days"],
        "best_mcpt": None if not best else best[1]["mcpt_p"],
        "best_mode": None if not best else best[1]["params"]["signal_mode"],
        "best_ann": None if not best else best[1]["full_stats"]["avg_annual_pnl"],
        "eval_days": None if not best else best[1]["challenge"]["evaluation_days"],
        "eval_passed": None if not best else best[1]["challenge"]["evaluation_passed"],
    }
    print("\nDONE", json.dumps(summary, indent=2), flush=True)
    (OUT / "month_pass_summary.json").write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
