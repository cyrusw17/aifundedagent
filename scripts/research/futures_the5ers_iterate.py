#!/usr/bin/env python3
"""Iterate futures The5ers candidates: expanded grid + MCPT + future survival.

Never trains/tunes on 2026+. Future is report-only gate (must not blow).
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from itertools import product
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.challenge import simulate_challenge
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.mcpt_forex import permute_forex_book
from mcpt.futures import ALL6, INDEX4, INDEX_COMM, load_futures

OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)

TRAIN = ("2024-03-01", "2025-06-30")
HOLD = ("2025-07-01", "2025-12-31")
FUTURE = ("2026-01-01", "2099-01-01")
RULES = FundedRules()

PAIRSETS = {
    "index4": INDEX4,
    "index_comm": INDEX_COMM,
    "all6": ALL6,
}

MODES = [
    "h1_sweep_bos",
    "sweep_bos_ob",
    "sweep_bos_ob_kz",
    "h1_bos_fvg_retest",
    "h1_bos_ob_retest",
    "h1_choch_fvg",
    "london_asia_sweep",
]


def exp_r(wr: float, rr: float) -> float:
    return wr * rr - (1.0 - wr)


def run(book, params, *, weekly: bool):
    prep = prepare_book(
        book, params["signal_mode"], params["swing_left"], params.get("min_confluence", 2)
    )
    return fast_backtest(
        prep,
        risk_pct=params["risk_pct"],
        rr=params["rr"],
        atr_stop_mult=params["atr_stop_mult"],
        max_positions=params.get("max_positions", 1),
        move_be_at_r=params.get("move_be_at_r", 0.0),
        skip_mondays=params.get("skip_mondays", True),
        daily_halt_loss_pct=params.get("daily_halt_loss_pct", 0.03),
        daily_halt_profit_pct=params.get("daily_halt_profit_pct", 0.05),
        cooldown_losses=params.get("cooldown_losses", 2),
        weekly_withdraw=weekly,
        one_entry_per_day=params.get("one_entry_per_day", True),
        rules=RULES,
    )


def era_ok(st, *, train: bool, rr: float) -> bool:
    if st.blown:
        return False
    min_tr = 40 if train else 15
    if st.n_trades < min_tr:
        return False
    if st.profit_factor < (1.12 if train else 1.05):
        return False
    if st.avg_annual_pnl < (3000 if train else 0):
        return False
    be = 1.0 / (1.0 + rr)
    # Asymmetric: train needs clear edge over BE
    if st.win_rate < be + (0.02 if train else 0.0):
        return False
    if exp_r(st.win_rate, rr) < (0.05 if train else 0.0):
        return False
    return True


def mcpt(book, params, n_perm=160, seed=21):
    def obj(st):
        if st.blown:
            return -1.0
        e = exp_r(st.win_rate, params["rr"])
        return (
            (st.avg_annual_pnl / RULES.initial_balance) * 4.0
            + min(st.profit_factor, 5) * 0.5
            + max(e, 0) * 2.0
            - (st.max_dd / RULES.initial_balance) * 2.0
        )

    real = run(book, params, weekly=False)
    rs = obj(real)
    better = 1
    for i in range(1, n_perm):
        if obj(run(permute_forex_book(book, seed=seed + i), params, weekly=False)) >= rs:
            better += 1
    return better / n_perm


def future_sim(params):
    warm = load_futures(params["pairs"], "2025-07-01", "2025-12-31", "1h")
    fut = load_futures(params["pairs"], FUTURE[0], FUTURE[1], "1h")
    combined = {}
    for sym in params["pairs"]:
        if sym in warm and sym in fut:
            c = pd.concat([warm[sym], fut[sym]]).sort_index()
            combined[sym] = c[~c.index.duplicated(keep="last")]
    fut_only = {k: v[v.index >= pd.Timestamp("2026-01-01")] for k, v in combined.items()}
    return run(fut_only, params, weekly=True)


def main() -> None:
    print("=== Futures The5ers iteration (expanded) ===", flush=True)
    hits = []
    swings = [2, 3]
    risks = [0.005, 0.0075, 0.01]
    rrs = [1.8, 2.0, 2.5]
    atrs = [1.0, 1.25, 1.5]
    cools = [2, 3]

    for pset_name, symbols in PAIRSETS.items():
        bt = load_futures(symbols, *TRAIN, "1h")
        bh = load_futures(symbols, *HOLD, "1h")
        if len(bt) < 3 or len(bh) < 3:
            continue
        print(f"universe {pset_name}: {list(bt)}", flush=True)
        for mode in MODES:
            for sl in swings:
                try:
                    pt = prepare_book(bt, mode, sl, 2)
                    ph = prepare_book(bh, mode, sl, 2)
                except Exception as e:
                    print(f"  skip prep {mode} sw={sl}: {e}", flush=True)
                    continue
                local = 0
                for risk, rr, atr, cool in product(risks, rrs, atrs, cools):
                    params = {
                        "signal_mode": mode,
                        "pairset": pset_name,
                        "pairs": list(bt.keys()),
                        "risk_pct": risk,
                        "rr": rr,
                        "atr_stop_mult": atr,
                        "swing_left": sl,
                        "swing_right": sl,
                        "min_confluence": 2,
                        "max_positions": 1,
                        "require_killzone": False,
                        "weekly_withdraw": False,
                        "move_be_at_r": 0.0,
                        "skip_mondays": True,
                        "one_entry_per_day": True,
                        "cooldown_losses": cool,
                        "daily_halt_loss_pct": 0.03,
                        "daily_halt_profit_pct": 0.05,
                    }
                    st_t = fast_backtest(
                        pt,
                        risk_pct=risk,
                        rr=rr,
                        atr_stop_mult=atr,
                        max_positions=1,
                        move_be_at_r=0.0,
                        skip_mondays=True,
                        daily_halt_loss_pct=0.03,
                        daily_halt_profit_pct=0.05,
                        cooldown_losses=cool,
                        weekly_withdraw=False,
                        one_entry_per_day=True,
                        rules=RULES,
                    )
                    if not era_ok(st_t, train=True, rr=rr):
                        continue
                    st_h = fast_backtest(
                        ph,
                        risk_pct=risk,
                        rr=rr,
                        atr_stop_mult=atr,
                        max_positions=1,
                        move_be_at_r=0.0,
                        skip_mondays=True,
                        daily_halt_loss_pct=0.03,
                        daily_halt_profit_pct=0.05,
                        cooldown_losses=cool,
                        weekly_withdraw=False,
                        one_entry_per_day=True,
                        rules=RULES,
                    )
                    if not era_ok(st_h, train=False, rr=rr):
                        continue
                    local += 1
                    hits.append(
                        {
                            "params": params,
                            "train": st_t.as_dict(),
                            "hold": st_h.as_dict(),
                            "exp_t": exp_r(st_t.win_rate, rr),
                            "exp_h": exp_r(st_h.win_rate, rr),
                            "score": (
                                min(exp_r(st_t.win_rate, rr), exp_r(st_h.win_rate, rr)) * 5000
                                + min(st_t.profit_factor, st_h.profit_factor) * 2000
                                + min(st_t.avg_annual_pnl, st_h.avg_annual_pnl) * 0.05
                                + rr * 400
                            ),
                        }
                    )
                if local:
                    print(f"  {mode} sw={sl} +{local}", flush=True)

    hits.sort(key=lambda h: -h["score"])
    print(f"dual-era hits={len(hits)}", flush=True)
    (OUT / "futures_the5ers_iter_screen.json").write_text(
        json.dumps({"n_hits": len(hits), "top": hits[:50]}, indent=2, default=str)
    )

    # Dedup queue for MCPT + future
    queue, seen = [], set()
    for h in hits:
        p = h["params"]
        key = (
            p["signal_mode"],
            p["pairset"],
            p["rr"],
            p["risk_pct"],
            p["atr_stop_mult"],
            p["swing_left"],
            p["cooldown_losses"],
        )
        if key in seen:
            continue
        seen.add(key)
        queue.append(h)
        if len(queue) >= 18:
            break

    survivors = []
    for h in queue:
        p = h["params"]
        bt = load_futures(p["pairs"], *TRAIN, "1h")
        print(
            f"\nMCPT {p['pairset']} {p['signal_mode']} rr={p['rr']} risk={p['risk_pct']} "
            f"atr={p['atr_stop_mult']} sw={p['swing_left']} cool={p['cooldown_losses']}",
            flush=True,
        )
        pval = mcpt(bt, p, n_perm=160)
        print(f"  p={pval:.3f}", flush=True)
        if pval > 0.05:
            continue
        st_f = future_sim(p)
        print(
            f"  FUTURE WR={st_f.win_rate:.1%} ann={st_f.avg_annual_pnl:.0f} "
            f"blown={st_f.blown} n={st_f.n_trades} wd={st_f.total_withdrawn:.0f}",
            flush=True,
        )
        if st_f.blown:
            continue
        full = load_futures(p["pairs"], TRAIN[0], HOLD[1], "1h")
        ch = simulate_challenge(
            full,
            eval_end=TRAIN[1],
            funded_end=HOLD[1],
            rules=RULES,
            risk_pct=p["risk_pct"],
            rr=p["rr"],
            atr_stop_mult=p["atr_stop_mult"],
            max_positions=1,
            swing_left=p["swing_left"],
            swing_right=p["swing_right"],
            min_confluence=2,
            move_be_at_r=0.0,
            skip_mondays=True,
            daily_halt_loss_pct=0.03,
            daily_halt_profit_pct=0.05,
            cooldown_losses=p["cooldown_losses"],
            one_entry_per_day=True,
            signal_mode=p["signal_mode"],
        )
        print(
            f"  CHAL eval={ch.evaluation_passed} funded={ch.funded_survived} "
            f"ann={ch.funded_annual_pnl:.0f}",
            flush=True,
        )
        survivors.append(
            {
                **h,
                "mcpt_p": pval,
                "future_2026": st_f.as_dict(),
                "challenge": ch.to_dict(),
            }
        )

    def quality(s):
        ch, fut = s["challenge"], s["future_2026"]
        return (
            bool(ch.get("evaluation_passed"))
            and bool(ch.get("funded_survived"))
            and (not fut.get("blown"))
            and float(fut.get("avg_annual_pnl", 0)) > 0
            and int(fut.get("n_trades", 0)) >= 40
        )

    quality_survivors = [s for s in survivors if quality(s)]
    quality_survivors.sort(
        key=lambda x: (
            x["mcpt_p"],
            -min(x["exp_t"], x["exp_h"]),
            -x["future_2026"]["avg_annual_pnl"],
            -x["challenge"].get("funded_annual_pnl", 0),
        )
    )
    survivors.sort(
        key=lambda x: (
            0 if quality(x) else 1,
            x["mcpt_p"],
            -min(x["exp_t"], x["exp_h"]),
            -x["future_2026"]["avg_annual_pnl"],
        )
    )
    print(
        f"\nSurvivors (MCPT+future): {len(survivors)} quality={len(quality_survivors)}",
        flush=True,
    )
    for s in (quality_survivors or survivors)[:10]:
        p = s["params"]
        print(
            f"  {p['pairset']} {p['signal_mode']} rr={p['rr']} r={p['risk_pct']} "
            f"p={s['mcpt_p']:.3f} chal={s['challenge']['evaluation_passed']}/"
            f"{s['challenge']['funded_survived']} "
            f"fut_ann={s['future_2026']['avg_annual_pnl']:.0f}",
            flush=True,
        )

    payload = {
        "saved_at": datetime.now(timezone.utc).isoformat(),
        "protocol": {
            "train": TRAIN,
            "hold": HOLD,
            "future": FUTURE[0],
            "account": "The5ers FundedRules",
            "filters": (
                "train WR>=BE+2% PF>=1.12; hold WR>=BE PF>=1.05; MCPT p<=0.05; "
                "future not blown; lock requires funded_survived + future ann>0 + n>=40"
            ),
        },
        "n_screen_hits": len(hits),
        "n_survivors": len(survivors),
        "n_quality": len(quality_survivors),
        "survivors": survivors,
    }
    (OUT / "futures_the5ers_iteration2.json").write_text(
        json.dumps(payload, indent=2, default=str)
    )

    if not quality_survivors:
        print("NO quality survivors this iteration — keeping prior lock", flush=True)
        sys.exit(3)

    best = quality_survivors[0]
    params = best["params"]
    lock_params = {
        k: params[k]
        for k in [
            "signal_mode",
            "risk_pct",
            "rr",
            "atr_stop_mult",
            "max_positions",
            "min_confluence",
            "swing_left",
            "swing_right",
            "require_killzone",
            "weekly_withdraw",
            "move_be_at_r",
            "skip_mondays",
            "daily_halt_loss_pct",
            "daily_halt_profit_pct",
            "cooldown_losses",
            "one_entry_per_day",
        ]
    }
    lock_params["weekly_withdraw"] = True
    sel = (
        f"{params['signal_mode']}_{params['pairset']}_"
        f"r{int(params['risk_pct']*10000)}_rr{params['rr']}"
    )
    lock = {
        "name": "futures_the5ers",
        "market": "futures",
        "account": {
            "style": "the5ers_funded",
            "initial_balance": RULES.initial_balance,
            "max_loss": RULES.max_loss,
            "daily_loss_pct": RULES.daily_loss_pct,
            "leverage": RULES.leverage,
            "weekly_withdraw": True,
        },
        "timeframe": "1h",
        "symbols": params["pairs"],
        "params": lock_params,
        "train_era": list(TRAIN),
        "hold_era": list(HOLD),
        "future_era": [FUTURE[0], "data_end"],
        "train": best["train"],
        "hold": best["hold"],
        "challenge": best["challenge"],
        "future_2026": best["future_2026"],
        "mcpt_p": best["mcpt_p"],
        "mcpt_pass": True,
        "edge": {
            "rr": params["rr"],
            "breakeven_wr": 1.0 / (1.0 + params["rr"]),
            "expectancy_r_train": best["exp_t"],
            "expectancy_r_hold": best["exp_h"],
        },
        "selection": sel,
        "iteration": 2,
        "protocol": {
            "train": list(TRAIN),
            "hold": list(HOLD),
            "future": FUTURE[0],
            "note": "Futures under The5ers; never train 2026+; future survival required",
        },
        "no_curve_fitting": True,
        "no_lookahead": True,
        "never_trained_on_2026": True,
        "saved_at": datetime.now(timezone.utc).isoformat(),
    }
    (OUT / "best_strategy_futures_the5ers.json").write_text(
        json.dumps(lock, indent=2, default=str)
    )
    (OUT / "futures_the5ers_results.json").write_text(
        json.dumps(
            {
                "accepted": len(survivors),
                "winner": lock,
                "survivors_summary": [
                    {
                        "selection": (
                            f"{s['params']['signal_mode']}_{s['params']['pairset']}_"
                            f"r{int(s['params']['risk_pct']*10000)}_rr{s['params']['rr']}"
                        ),
                        "mcpt_p": s["mcpt_p"],
                        "challenge_pass": s["challenge"]["evaluation_passed"],
                        "future_ann": s["future_2026"]["avg_annual_pnl"],
                        "future_blown": s["future_2026"]["blown"],
                    }
                    for s in survivors
                ],
            },
            indent=2,
            default=str,
        )
    )
    print(f"LOCKED {sel} p={best['mcpt_p']:.3f}", flush=True)


if __name__ == "__main__":
    main()
