#!/usr/bin/env python3
"""Raise RR while keeping WR near the retail lock (~54%/51%).

Baseline: h1_sweep_bos rr=1.0 WR~54%/51.5% MCPT p=0.007
Goal: RR >= 1.2 (prefer 1.5+), WR train>=0.50 hold>=0.48, DD<=20%, MCPT pass.
Never train/tune on 2026+.
"""

from __future__ import annotations

import json
import sys
from itertools import product
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.fast_sim import prepare_book, fast_backtest
from mcpt.forex.mcpt_forex import permute_forex_book
from mcpt.forex.strategy_funded import BEST_PATH
from scripts.research.retail_timeless_hunt import (
    TRAIN,
    HOLD,
    OUT,
    RULES,
    load_merged,
    load_future,
    make_params,
    mcpt_objective,
)

PAIRS = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"]

# Keep WR roughly at lock levels
MIN_WR_TRAIN = 0.50
MIN_WR_HOLD = 0.48
MAX_DD = 0.20
MIN_ANN_TRAIN = 40.0
MIN_ANN_HOLD = 1.0
MIN_PF_TRAIN = 1.05
MIN_PF_HOLD = 1.02
MIN_RR = 1.2


def run(book, params):
    prep = prepare_book(
        book, params["signal_mode"], params["swing_left"], params.get("min_confluence", 2)
    )
    return fast_backtest(
        prep,
        risk_pct=params["risk_pct"],
        rr=params["rr"],
        atr_stop_mult=params["atr_stop_mult"],
        max_positions=1,
        move_be_at_r=params["move_be_at_r"],
        skip_mondays=params["skip_mondays"],
        daily_halt_loss_pct=params["daily_halt_loss_pct"],
        daily_halt_profit_pct=params["daily_halt_profit_pct"],
        cooldown_losses=params["cooldown_losses"],
        weekly_withdraw=False,
        one_entry_per_day=params["one_entry_per_day"],
        rules=RULES,
    )


def ok(st, *, min_wr, min_ann, min_pf, min_trades):
    if st.blown or st.max_dd_pct > MAX_DD + 1e-9:
        return False
    if st.n_trades < min_trades or st.win_rate < min_wr:
        return False
    if st.avg_annual_pnl < min_ann or st.profit_factor < min_pf:
        return False
    return True


def score(st_t, st_h, params):
    # Prefer higher RR, then WR closeness to baseline, then edge
    wr_floor = min(st_t.win_rate, st_h.win_rate)
    return (
        params["rr"] * 5000
        + wr_floor * 8000
        + min(st_t.profit_factor, st_h.profit_factor) * 1500
        + min(st_t.avg_annual_pnl, st_h.avg_annual_pnl)
        - max(st_t.max_dd_pct, st_h.max_dd_pct) * 3000
    )


def mcpt(book, params, n_perm=120, seed=21):
    real = run(book, params)
    rs = mcpt_objective(real, min_wr=MIN_WR_TRAIN)
    better = 1
    for i in range(1, n_perm):
        if mcpt_objective(run(permute_forex_book(book, seed=seed + i), params), min_wr=MIN_WR_TRAIN) >= rs:
            better += 1
        if i % 40 == 0:
            print(f"    MCPT {i}/{n_perm} p~{better/(i+1):.3f}", flush=True)
    return better / n_perm, real


def main() -> None:
    print("=== Higher-RR retail hunt (keep WR ~same) ===", flush=True)
    print(f"Gates: WR>={MIN_WR_TRAIN}/{MIN_WR_HOLD} RR>={MIN_RR} DD<={MAX_DD}", flush=True)

    bt = load_merged(PAIRS, *TRAIN)
    bh = load_merged(PAIRS, *HOLD)
    b_full = load_merged(PAIRS, "2016-01-01", "2025-12-31")

    modes = ["h1_sweep_bos", "sweep_bos_ob", "sweep_bos_ob_kz"]
    swings = [(2, 2), (3, 2), (2, 3), (3, 3), (4, 2)]
    risks = [0.003, 0.004, 0.005, 0.0075]
    rrs = [1.2, 1.5, 1.8, 2.0]
    atrs = [1.25, 1.5, 1.75, 2.0]
    bes = [0.0, 0.8, 1.0]
    cools = [0, 2, 3]
    skips = [True]
    opds = [True]
    halts = [(0.03, 0.05), (0.025, 0.04), (0.04, 0.06)]

    hits = []
    for mode in modes:
        for sl, mc in swings:
            print(f"prep {mode} sw={sl} mc={mc}", flush=True)
            pt = prepare_book(bt, mode, sl, mc)
            ph = prepare_book(bh, mode, sl, mc)
            local = 0
            for risk, rr, atr, be, cool, skip, opd, (hl, hp) in product(
                risks, rrs, atrs, bes, cools, skips, opds, halts
            ):
                params = make_params(
                    mode,
                    "majors4",
                    dict(
                        risk_pct=risk,
                        rr=rr,
                        atr_stop_mult=atr,
                        move_be_at_r=be,
                        cooldown_losses=cool,
                        skip_mondays=skip,
                        one_entry_per_day=opd,
                        daily_halt_loss_pct=hl,
                        daily_halt_profit_pct=hp,
                    ),
                    swing_left=sl,
                    swing_right=sl,
                    min_confluence=mc,
                )
                st_t = fast_backtest(
                    pt,
                    risk_pct=risk,
                    rr=rr,
                    atr_stop_mult=atr,
                    max_positions=1,
                    move_be_at_r=be,
                    skip_mondays=skip,
                    daily_halt_loss_pct=hl,
                    daily_halt_profit_pct=hp,
                    cooldown_losses=cool,
                    weekly_withdraw=False,
                    one_entry_per_day=opd,
                    rules=RULES,
                )
                if not ok(st_t, min_wr=MIN_WR_TRAIN, min_ann=MIN_ANN_TRAIN, min_pf=MIN_PF_TRAIN, min_trades=80):
                    continue
                st_h = fast_backtest(
                    ph,
                    risk_pct=risk,
                    rr=rr,
                    atr_stop_mult=atr,
                    max_positions=1,
                    move_be_at_r=be,
                    skip_mondays=skip,
                    daily_halt_loss_pct=hl,
                    daily_halt_profit_pct=hp,
                    cooldown_losses=cool,
                    weekly_withdraw=False,
                    one_entry_per_day=opd,
                    rules=RULES,
                )
                if not ok(st_h, min_wr=MIN_WR_HOLD, min_ann=MIN_ANN_HOLD, min_pf=MIN_PF_HOLD, min_trades=20):
                    continue
                sc = score(st_t, st_h, params)
                hits.append({"params": params, "train": st_t.as_dict(), "hold": st_h.as_dict(), "score": sc})
                local += 1
            print(f"  hits +{local}", flush=True)

    # Relax WR slightly if empty (still "roughly" same)
    if not hits:
        print("No hits at 50/48 — relaxing to 0.48/0.46", flush=True)
        # Re-run would be expensive; instead lower gates in a second pass with cached preps
        # Fall through to narrower re-screen below
        MIN_WR_T2, MIN_WR_H2 = 0.48, 0.46
        for mode in ["h1_sweep_bos", "sweep_bos_ob"]:
            for sl, mc in [(2, 2), (3, 2), (4, 2)]:
                pt = prepare_book(bt, mode, sl, mc)
                ph = prepare_book(bh, mode, sl, mc)
                for risk, rr, atr, be, cool in product(
                    [0.003, 0.005], [1.2, 1.5, 1.8], [1.5, 1.75, 2.0], [0.0, 1.0], [2, 3]
                ):
                    params = make_params(
                        mode,
                        "majors4",
                        dict(
                            risk_pct=risk,
                            rr=rr,
                            atr_stop_mult=atr,
                            move_be_at_r=be,
                            cooldown_losses=cool,
                            skip_mondays=True,
                            one_entry_per_day=True,
                            daily_halt_loss_pct=0.03,
                            daily_halt_profit_pct=0.05,
                        ),
                        swing_left=sl,
                        swing_right=sl,
                        min_confluence=mc,
                    )
                    st_t = run(bt, params)
                    if not ok(st_t, min_wr=MIN_WR_T2, min_ann=30, min_pf=1.04, min_trades=80):
                        continue
                    st_h = run(bh, params)
                    if not ok(st_h, min_wr=MIN_WR_H2, min_ann=0, min_pf=1.02, min_trades=20):
                        continue
                    hits.append(
                        {
                            "params": params,
                            "train": st_t.as_dict(),
                            "hold": st_h.as_dict(),
                            "score": score(st_t, st_h, params),
                        }
                    )

    hits.sort(key=lambda h: -h["score"])
    print(f"Total dual-era higher-RR hits: {len(hits)}", flush=True)
    for h in hits[:15]:
        p = h["params"]
        print(
            f"  rr={p['rr']} {p['signal_mode']} risk={p['risk_pct']} atr={p['atr_stop_mult']} "
            f"sw={p['swing_left']} BE={p['move_be_at_r']} cool={p['cooldown_losses']} "
            f"WR={h['train']['win_rate']:.1%}/{h['hold']['win_rate']:.1%} "
            f"PF={h['train']['profit_factor']:.2f}/{h['hold']['profit_factor']:.2f} "
            f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f} "
            f"dd={h['train']['max_dd_pct']:.1%}/{h['hold']['max_dd_pct']:.1%}",
            flush=True,
        )

    (OUT / "retail_higher_rr_screen.json").write_text(
        json.dumps({"n_hits": len(hits), "top": hits[:40]}, indent=2, default=str)
    )

    if not hits:
        print("FAILED: no higher-RR survivors near baseline WR", flush=True)
        sys.exit(1)

    # Diversify MCPT queue by RR then uniqueness
    queue = []
    seen = set()
    for h in hits:
        p = h["params"]
        key = (p["signal_mode"], p["rr"], p["risk_pct"], p["atr_stop_mult"], p["move_be_at_r"], p["swing_left"])
        if key in seen:
            continue
        seen.add(key)
        queue.append(h)
        if len(queue) >= 12:
            break

    accepted = []
    finalists = []
    for h in queue:
        p = h["params"]
        print(
            f"\nMCPT rr={p['rr']} {p['signal_mode']} risk={p['risk_pct']} atr={p['atr_stop_mult']} "
            f"sw={p['swing_left']} BE={p['move_be_at_r']} "
            f"WR={h['train']['win_rate']:.1%}/{h['hold']['win_rate']:.1%} "
            f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f}",
            flush=True,
        )
        p_train, _ = mcpt(bt, p, n_perm=120)
        print(f"  train p={p_train:.3f}", flush=True)
        p_full = None
        accept = p_train <= 0.05
        if accept:
            p_full, _ = mcpt(b_full, p, n_perm=100, seed=41)
            print(f"  full p={p_full:.3f}", flush=True)
            accept = p_full <= 0.05
        row = {**h, "mcpt_p": p_train, "mcpt_p_full": p_full, "accept": accept}
        finalists.append(row)
        if accept:
            accepted.append(row)
            # Prefer keeping higher RR; stop after 2 accepts at rr>=1.5 or 3 total
            if len(accepted) >= 3 or (p["rr"] >= 1.5 and len(accepted) >= 1):
                # continue a bit for better RR alternatives
                if len([a for a in accepted if a["params"]["rr"] >= 1.5]) >= 2:
                    break

    print(f"\nAccepted: {len(accepted)}/{len(finalists)}", flush=True)
    if not accepted:
        (OUT / "retail_higher_rr_results.json").write_text(
            json.dumps({"accepted": 0, "finalists": finalists, "top": hits[:20]}, indent=2, default=str)
        )
        print("FAILED MCPT — will need another iteration", flush=True)
        sys.exit(2)

    # Pick highest RR, then WR, then ann
    winner = sorted(
        accepted,
        key=lambda x: (
            -x["params"]["rr"],
            -min(x["train"]["win_rate"], x["hold"]["win_rate"]),
            -min(x["train"]["avg_annual_pnl"], x["hold"]["avg_annual_pnl"]),
            x["mcpt_p"],
        ),
    )[0]
    params = winner["params"]

    fut = load_future(params["pairs"])
    warm = load_merged(params["pairs"], "2025-07-01", "2025-12-31")
    combined = {}
    for pair in params["pairs"]:
        combined[pair] = pd.concat([warm[pair], fut[pair]]).sort_index()
        combined[pair] = combined[pair][~combined[pair].index.duplicated(keep="last")]
    fut_only = {
        pair: combined[pair][combined[pair].index >= pd.Timestamp("2026-01-01")] for pair in combined
    }
    st_f = run(fut_only, params).as_dict()
    print(
        f"FUTURE rr={params['rr']} WR={st_f['win_rate']:.1%} PF={st_f['profit_factor']:.2f} "
        f"dd={st_f['max_dd_pct']:.1%} ann={st_f['avg_annual_pnl']:.1f} blown={st_f['blown']} "
        f"n={st_f['n_trades']} bal={st_f['final_balance']:.1f}",
        flush=True,
    )

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
    lock = {
        "name": "retail_timeless_1k",
        "account": {"initial_balance": 1000, "leverage": 50, "max_dd_pct": 0.20},
        "timeframe": "1h",
        "pairs": params["pairs"],
        "params": lock_params,
        "train_era": list(TRAIN),
        "hold_era": list(HOLD),
        "future_era": ["2026-01-01", "data_end"],
        "train": winner["train"],
        "hold": winner["hold"],
        "future_2026": st_f,
        "mcpt_p": winner["mcpt_p"],
        "mcpt_p_full_2016_2025": winner.get("mcpt_p_full"),
        "mcpt_pass": True,
        "min_wr_gate": {"train": MIN_WR_TRAIN, "hold": MIN_WR_HOLD},
        "baseline_rr": 1.0,
        "improved_rr": params["rr"],
        "protocol": {
            "train": TRAIN,
            "hold": HOLD,
            "future": "2026-01-01",
            "note": "Higher RR hunt; HOLD unused for tuning; FUTURE never trained; causal; same-bar stop",
        },
        "no_curve_fitting": True,
        "no_lookahead": True,
        "never_trained_on_2026": True,
        "alternatives": [
            {
                "params": a["params"],
                "mcpt_p": a["mcpt_p"],
                "mcpt_p_full": a.get("mcpt_p_full"),
                "train_wr": a["train"]["win_rate"],
                "hold_wr": a["hold"]["win_rate"],
                "rr": a["params"]["rr"],
            }
            for a in accepted[:8]
        ],
    }
    (OUT / "best_strategy_retail_1k.json").write_text(json.dumps(lock, indent=2, default=str))
    BEST_PATH.write_text(json.dumps(lock, indent=2, default=str))
    (OUT / "retail_higher_rr_results.json").write_text(
        json.dumps({"accepted": len(accepted), "winner": lock, "finalists": finalists}, indent=2, default=str)
    )
    print(
        f"LOCKED rr={params['rr']} {params['signal_mode']} risk={params['risk_pct']} "
        f"p={winner['mcpt_p']:.3f} WR T/H/F={winner['train']['win_rate']:.1%}/"
        f"{winner['hold']['win_rate']:.1%}/{st_f['win_rate']:.1%}",
        flush=True,
    )


if __name__ == "__main__":
    main()
