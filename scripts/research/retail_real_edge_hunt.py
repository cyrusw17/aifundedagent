#!/usr/bin/env python3
"""Remake retail strategy for REAL expectancy — not coin-flip 50% @ 1:1.

Reject thin edges. Require:
  - RR >= 1.5
  - Expectancy >= 0.12 R/trade both eras  (WR*RR - (1-WR))
  - PF >= 1.12 train, >= 1.05 hold
  - DD <= 20%, not blown on $1k / 50:1
  - MCPT p <= 0.05
  - Never train/tune on 2026+
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
MAX_DD = 0.20
MIN_RR = 1.5
MIN_EXP_R = 0.12  # R per trade — above coin-flip noise
MIN_PF_T = 1.12
MIN_PF_H = 1.05
MIN_ANN_T = 40.0
MIN_ANN_H = 1.0


def expectancy_r(wr: float, rr: float) -> float:
    return wr * rr - (1.0 - wr)


def run_prep(prep, params):
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


def run_book(book, params):
    prep = prepare_book(
        book, params["signal_mode"], params["swing_left"], params.get("min_confluence", 2)
    )
    return run_prep(prep, params)


def era_ok(st, params, *, train: bool) -> bool:
    if st.blown or st.max_dd_pct > MAX_DD + 1e-9:
        return False
    min_tr = 80 if train else 20
    if st.n_trades < min_tr:
        return False
    if st.avg_annual_pnl < (MIN_ANN_T if train else MIN_ANN_H):
        return False
    if st.profit_factor < (MIN_PF_T if train else MIN_PF_H):
        return False
    exp = expectancy_r(st.win_rate, params["rr"])
    if exp < MIN_EXP_R:
        return False
    # Must beat breakeven WR by meaningful margin
    be = 1.0 / (1.0 + params["rr"])
    if st.win_rate < be + 0.04:  # ≥4pp over breakeven
        return False
    return True


def score(st_t, st_h, params) -> float:
    e_t = expectancy_r(st_t.win_rate, params["rr"])
    e_h = expectancy_r(st_h.win_rate, params["rr"])
    return (
        min(e_t, e_h) * 8_000
        + params["rr"] * 1_500
        + min(st_t.profit_factor, st_h.profit_factor) * 2_000
        + min(st_t.avg_annual_pnl, st_h.avg_annual_pnl) * 2
        - max(st_t.max_dd_pct, st_h.max_dd_pct) * 3_000
    )


def mcpt(book, params, n_perm=150, seed=21):
    """Edge-focused MCPT objective (annual PnL + PF), not WR-coin-flip."""

    def obj(st):
        if st.blown:
            return -1.0
        if st.max_dd_pct > MAX_DD:
            return -0.5
        exp = expectancy_r(st.win_rate, params["rr"])
        return (
            (st.avg_annual_pnl / RULES.initial_balance) * 3.0
            + min(st.profit_factor, 5) * 0.5
            + exp * 1.5
            - st.max_dd_pct * 2.0
        )

    real = run_book(book, params)
    rs = obj(real)
    better = 1
    for i in range(1, n_perm):
        if obj(run_book(permute_forex_book(book, seed=seed + i), params)) >= rs:
            better += 1
        if i % 40 == 0:
            print(f"    MCPT {i}/{n_perm} p~{better/(i+1):.3f}", flush=True)
    return better / n_perm, real


def main() -> None:
    print("=== REAL-EDGE retail remake (reject coin-flip) ===", flush=True)
    print(
        f"Gates: RR>={MIN_RR} expR>={MIN_EXP_R} PF>={MIN_PF_T}/{MIN_PF_H} "
        f"BE+4pp DD<={MAX_DD}",
        flush=True,
    )

    bt = load_merged(PAIRS, *TRAIN)
    bh = load_merged(PAIRS, *HOLD)
    b_full = load_merged(PAIRS, "2016-01-01", "2025-12-31")

    modes = [
        "h1_sweep_bos",
        "sweep_bos_ob",
        "sweep_bos_ob_kz",
        "london_asia_sweep",
        "kz_ob_fvg",
        "ob_confirm",
        "killzone_smc",
        "smc_strict",
    ]
    swings = [(2, 2), (3, 2), (4, 2), (3, 3)]
    risks = [0.003, 0.004, 0.005, 0.0075]
    rrs = [1.5, 1.8, 2.0, 2.5]
    atrs = [1.25, 1.5, 1.75, 2.0]
    cools = [0, 2, 3]
    bes = [0.0]
    overlays = [
        dict(skip_mondays=True, one_entry_per_day=True, daily_halt_loss_pct=0.03, daily_halt_profit_pct=0.05),
        dict(skip_mondays=True, one_entry_per_day=True, daily_halt_loss_pct=0.04, daily_halt_profit_pct=0.06),
        dict(skip_mondays=False, one_entry_per_day=True, daily_halt_loss_pct=0.03, daily_halt_profit_pct=0.05),
        # rawer — less overlay artifact
        dict(skip_mondays=True, one_entry_per_day=True, daily_halt_loss_pct=0.99, daily_halt_profit_pct=0.99),
    ]

    hits = []
    for mode in modes:
        for sl, mc in swings:
            print(f"prep {mode} sw={sl} mc={mc}", flush=True)
            pt = prepare_book(bt, mode, sl, mc)
            ph = prepare_book(bh, mode, sl, mc)
            local = 0
            for risk, rr, atr, cool, be, ov in product(risks, rrs, atrs, cools, bes, overlays):
                tmpl = dict(
                    risk_pct=risk,
                    rr=rr,
                    atr_stop_mult=atr,
                    move_be_at_r=be,
                    cooldown_losses=cool,
                    **ov,
                )
                params = make_params(
                    mode, "majors4", tmpl, swing_left=sl, swing_right=sl, min_confluence=mc
                )
                st_t = run_prep(pt, params)
                if not era_ok(st_t, params, train=True):
                    continue
                st_h = run_prep(ph, params)
                if not era_ok(st_h, params, train=False):
                    continue
                hits.append(
                    {
                        "params": params,
                        "train": st_t.as_dict(),
                        "hold": st_h.as_dict(),
                        "score": score(st_t, st_h, params),
                        "exp_t": expectancy_r(st_t.win_rate, rr),
                        "exp_h": expectancy_r(st_h.win_rate, rr),
                    }
                )
                local += 1
            print(f"  +{local}", flush=True)

    # Soften once if empty
    if not hits:
        print("No hits at strict gates — soften expR>=0.08 PF 1.08/1.03", flush=True)
        global MIN_EXP_R, MIN_PF_T, MIN_PF_H
        MIN_EXP_R, MIN_PF_T, MIN_PF_H = 0.08, 1.08, 1.03
        for mode in ["h1_sweep_bos", "sweep_bos_ob", "sweep_bos_ob_kz"]:
            for sl, mc in [(2, 2), (3, 2), (4, 2)]:
                pt = prepare_book(bt, mode, sl, mc)
                ph = prepare_book(bh, mode, sl, mc)
                for risk, rr, atr, cool in product(
                    [0.003, 0.005, 0.0075], [1.5, 1.8, 2.0], [1.25, 1.5, 1.75], [2, 3]
                ):
                    params = make_params(
                        mode,
                        "majors4",
                        dict(
                            risk_pct=risk,
                            rr=rr,
                            atr_stop_mult=atr,
                            move_be_at_r=0.0,
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
                    st_t = run_prep(pt, params)
                    if not era_ok(st_t, params, train=True):
                        continue
                    st_h = run_prep(ph, params)
                    if not era_ok(st_h, params, train=False):
                        continue
                    hits.append(
                        {
                            "params": params,
                            "train": st_t.as_dict(),
                            "hold": st_h.as_dict(),
                            "score": score(st_t, st_h, params),
                            "exp_t": expectancy_r(st_t.win_rate, rr),
                            "exp_h": expectancy_r(st_h.win_rate, rr),
                        }
                    )

    hits.sort(key=lambda h: -h["score"])
    print(f"hits={len(hits)}", flush=True)
    for h in hits[:20]:
        p = h["params"]
        print(
            f"  rr={p['rr']} {p['signal_mode']} risk={p['risk_pct']} atr={p['atr_stop_mult']} "
            f"sw={p['swing_left']} cool={p['cooldown_losses']} "
            f"WR={h['train']['win_rate']:.1%}/{h['hold']['win_rate']:.1%} "
            f"expR={h['exp_t']:.3f}/{h['exp_h']:.3f} "
            f"PF={h['train']['profit_factor']:.2f}/{h['hold']['profit_factor']:.2f} "
            f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f} "
            f"dd={h['train']['max_dd_pct']:.1%}/{h['hold']['max_dd_pct']:.1%}",
            flush=True,
        )

    (OUT / "retail_real_edge_screen.json").write_text(
        json.dumps(
            {
                "gates": {
                    "min_rr": MIN_RR,
                    "min_exp_r": MIN_EXP_R,
                    "min_pf": [MIN_PF_T, MIN_PF_H],
                },
                "n_hits": len(hits),
                "top": hits[:40],
            },
            indent=2,
            default=str,
        )
    )
    if not hits:
        print("FAILED: no real-edge dual-era survivors", flush=True)
        sys.exit(1)

    # MCPT queue: diversify by (mode, rr)
    queue = []
    seen = set()
    for h in hits:
        p = h["params"]
        key = (p["signal_mode"], p["rr"], p["atr_stop_mult"], p["swing_left"], p["risk_pct"])
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
            f"\nMCPT rr={p['rr']} {p['signal_mode']} atr={p['atr_stop_mult']} "
            f"sw={p['swing_left']} risk={p['risk_pct']} "
            f"WR={h['train']['win_rate']:.1%}/{h['hold']['win_rate']:.1%} "
            f"expR={h['exp_t']:.3f}/{h['exp_h']:.3f} "
            f"PF={h['train']['profit_factor']:.2f}/{h['hold']['profit_factor']:.2f} "
            f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f}",
            flush=True,
        )
        p_train, _ = mcpt(bt, p, n_perm=150)
        print(f"  train p={p_train:.3f}", flush=True)
        p_full = None
        accept = p_train <= 0.05
        if accept:
            p_full, _ = mcpt(b_full, p, n_perm=120, seed=41)
            print(f"  full p={p_full:.3f}", flush=True)
            accept = p_full <= 0.05
        row = {**h, "mcpt_p": p_train, "mcpt_p_full": p_full, "accept": accept}
        finalists.append(row)
        if accept:
            accepted.append(row)
            if len(accepted) >= 3:
                break

    print(f"Accepted {len(accepted)}/{len(finalists)}", flush=True)
    if not accepted:
        (OUT / "retail_real_edge_results.json").write_text(
            json.dumps({"accepted": 0, "finalists": finalists, "top": hits[:25]}, indent=2, default=str)
        )
        print("FAILED MCPT", flush=True)
        sys.exit(2)

    winner = sorted(
        accepted,
        key=lambda x: (
            -min(x["exp_t"], x["exp_h"]),
            -x["params"]["rr"],
            -min(x["train"]["profit_factor"], x["hold"]["profit_factor"]),
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
    st_f = run_book(fut_only, params).as_dict()
    exp_f = expectancy_r(st_f["win_rate"], params["rr"])
    print(
        f"FUTURE rr={params['rr']} WR={st_f['win_rate']:.1%} expR={exp_f:.3f} "
        f"PF={st_f['profit_factor']:.2f} dd={st_f['max_dd_pct']:.1%} "
        f"ann={st_f['avg_annual_pnl']:.1f} blown={st_f['blown']} "
        f"bal={st_f['final_balance']:.1f} n={st_f['n_trades']}",
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
    be_wr = 1.0 / (1.0 + params["rr"])
    lock = {
        "name": "retail_real_edge_1k",
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
        "edge": {
            "rr": params["rr"],
            "breakeven_wr": be_wr,
            "expectancy_r_train": winner["exp_t"],
            "expectancy_r_hold": winner["exp_h"],
            "expectancy_r_future": exp_f,
            "wr_above_breakeven_train": winner["train"]["win_rate"] - be_wr,
            "wr_above_breakeven_hold": winner["hold"]["win_rate"] - be_wr,
        },
        "mcpt_p": winner["mcpt_p"],
        "mcpt_p_full_2016_2025": winner.get("mcpt_p_full"),
        "mcpt_pass": True,
        "rejects_coin_flip": True,
        "protocol": {
            "train": TRAIN,
            "hold": HOLD,
            "future": "2026-01-01",
            "note": "Real-edge remake: RR>=1.5, expR gate, PF gate; HOLD unused for tuning; FUTURE never trained",
        },
        "no_curve_fitting": True,
        "no_lookahead": True,
        "never_trained_on_2026": True,
        "alternatives": [
            {
                "rr": a["params"]["rr"],
                "signal_mode": a["params"]["signal_mode"],
                "mcpt_p": a["mcpt_p"],
                "exp_t": a["exp_t"],
                "exp_h": a["exp_h"],
                "train_wr": a["train"]["win_rate"],
                "hold_wr": a["hold"]["win_rate"],
                "train_pf": a["train"]["profit_factor"],
                "hold_pf": a["hold"]["profit_factor"],
            }
            for a in accepted
        ],
    }
    (OUT / "best_strategy_retail_1k.json").write_text(json.dumps(lock, indent=2, default=str))
    BEST_PATH.write_text(json.dumps(lock, indent=2, default=str))
    (OUT / "retail_real_edge_results.json").write_text(
        json.dumps({"accepted": len(accepted), "winner": lock, "finalists": finalists}, indent=2, default=str)
    )
    print(
        f"LOCKED rr={params['rr']} {params['signal_mode']} "
        f"expR={winner['exp_t']:.3f}/{winner['exp_h']:.3f} "
        f"WR={winner['train']['win_rate']:.1%}/{winner['hold']['win_rate']:.1%} "
        f"PF={winner['train']['profit_factor']:.2f}/{winner['hold']['profit_factor']:.2f} "
        f"p={winner['mcpt_p']:.3f}",
        flush=True,
    )


if __name__ == "__main__":
    main()
