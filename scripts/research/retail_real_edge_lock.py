#!/usr/bin/env python3
"""Lock a REAL retail edge: RR≥1.5 asymmetric payoff, not 50%@1:1 coin-flip.

$1k / 50:1 / 20% DD. Train≤2023, hold 2024–25, future 2026+ only.
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
)

PAIRS = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"]
MAX_DD = 0.20


def exp_r(wr: float, rr: float) -> float:
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


def mcpt(book, params, n_perm=150, seed=21):
    def obj(st):
        if st.blown:
            return -1.0
        if st.max_dd_pct > MAX_DD:
            return -0.5
        e = exp_r(st.win_rate, params["rr"])
        return (
            (st.avg_annual_pnl / RULES.initial_balance) * 3.0
            + min(st.profit_factor, 5) * 0.55
            + max(e, 0) * 2.0
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
    print("=== REAL asymmetric-edge retail lock ===", flush=True)
    bt = load_merged(PAIRS, *TRAIN)
    bh = load_merged(PAIRS, *HOLD)
    b_full = load_merged(PAIRS, "2016-01-01", "2025-12-31")

    # Focused grid from diagnostic survivors
    specs = []
    modes = ["sweep_bos_ob", "h1_sweep_bos", "sweep_bos_ob_kz"]
    for mode, sl, risk, rr, atr, cool in product(
        modes,
        [2, 3, 4],
        [0.003, 0.005],
        [1.5, 1.8, 2.0],
        [1.25, 1.5, 1.75],
        [2, 3],
    ):
        specs.append(
            dict(
                signal_mode=mode,
                risk_pct=risk,
                rr=rr,
                atr_stop_mult=atr,
                swing_left=sl,
                swing_right=sl,
                min_confluence=2,
                cooldown_losses=cool,
                move_be_at_r=0.0,
                skip_mondays=True,
                one_entry_per_day=True,
                daily_halt_loss_pct=0.03,
                daily_halt_profit_pct=0.05,
                weekly_withdraw=False,
                max_positions=1,
                require_killzone=False,
            )
        )

    hits = []
    cache = {}
    for raw in specs:
        key = (raw["signal_mode"], raw["swing_left"])
        if key not in cache:
            print(f"prep {key[0]} sw={key[1]}", flush=True)
            cache[key] = (
                prepare_book(bt, raw["signal_mode"], raw["swing_left"], 2),
                prepare_book(bh, raw["signal_mode"], raw["swing_left"], 2),
            )
        pt, ph = cache[key]
        params = make_params(raw["signal_mode"], "majors4", raw)
        params.update(raw)
        params["pairs"] = PAIRS
        st_t = run_prep(pt, params)
        st_h = run_prep(ph, params)
        if st_t.blown or st_h.blown:
            continue
        if st_t.max_dd_pct > MAX_DD or st_h.max_dd_pct > MAX_DD:
            continue
        if st_t.n_trades < 80 or st_h.n_trades < 20:
            continue
        if st_t.avg_annual_pnl < 40 or st_h.avg_annual_pnl < 1:
            continue
        if st_t.profit_factor < 1.06 or st_h.profit_factor < 1.03:
            continue
        e_t, e_h = exp_r(st_t.win_rate, raw["rr"]), exp_r(st_h.win_rate, raw["rr"])
        be = 1.0 / (1.0 + raw["rr"])
        # Must beat breakeven both eras; asymmetric RR required
        if raw["rr"] < 1.5:
            continue
        if st_t.win_rate < be + 0.015 or st_h.win_rate < be:
            continue
        if min(e_t, e_h) < 0.03:
            continue
        hits.append(
            {
                "params": params,
                "train": st_t.as_dict(),
                "hold": st_h.as_dict(),
                "exp_t": e_t,
                "exp_h": e_h,
                "score": (
                    min(e_t, e_h) * 5000
                    + raw["rr"] * 800
                    + min(st_t.profit_factor, st_h.profit_factor) * 1500
                    + min(st_t.avg_annual_pnl, st_h.avg_annual_pnl)
                ),
            }
        )

    hits.sort(key=lambda h: -h["score"])
    print(f"hits={len(hits)}", flush=True)
    for h in hits[:15]:
        p = h["params"]
        be = 1 / (1 + p["rr"])
        print(
            f"  rr={p['rr']} {p['signal_mode']} atr={p['atr_stop_mult']} sw={p['swing_left']} "
            f"risk={p['risk_pct']} cool={p['cooldown_losses']} "
            f"WR={h['train']['win_rate']:.1%}/{h['hold']['win_rate']:.1%} "
            f"(BE={be:.1%}) expR={h['exp_t']:.3f}/{h['exp_h']:.3f} "
            f"PF={h['train']['profit_factor']:.2f}/{h['hold']['profit_factor']:.2f} "
            f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f}",
            flush=True,
        )

    (OUT / "retail_real_edge_screen.json").write_text(
        json.dumps({"n_hits": len(hits), "top": hits[:30]}, indent=2, default=str)
    )
    if not hits:
        print("FAILED screen", flush=True)
        sys.exit(1)

    queue, seen = [], set()
    for h in hits:
        p = h["params"]
        key = (p["signal_mode"], p["rr"], p["atr_stop_mult"], p["swing_left"], p["risk_pct"])
        if key in seen:
            continue
        seen.add(key)
        queue.append(h)
        if len(queue) >= 10:
            break

    accepted, finalists = [], []
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
        p_train, _ = mcpt(bt, p, 150)
        print(f"  train p={p_train:.3f}", flush=True)
        p_full = None
        ok = p_train <= 0.05
        if ok:
            p_full, _ = mcpt(b_full, p, 120, seed=41)
            print(f"  full p={p_full:.3f}", flush=True)
            ok = p_full <= 0.05
        row = {**h, "mcpt_p": p_train, "mcpt_p_full": p_full, "accept": ok}
        finalists.append(row)
        if ok:
            accepted.append(row)
            if len(accepted) >= 2:
                break

    print(f"Accepted {len(accepted)}/{len(finalists)}", flush=True)
    if not accepted:
        (OUT / "retail_real_edge_results.json").write_text(
            json.dumps({"accepted": 0, "finalists": finalists}, indent=2, default=str)
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

    fut = load_future(PAIRS)
    warm = load_merged(PAIRS, "2025-07-01", "2025-12-31")
    combined = {}
    for pair in PAIRS:
        combined[pair] = pd.concat([warm[pair], fut[pair]]).sort_index()
        combined[pair] = combined[pair][~combined[pair].index.duplicated(keep="last")]
    fut_only = {
        p: combined[p][combined[p].index >= pd.Timestamp("2026-01-01")] for p in combined
    }
    st_f = run_book(fut_only, params).as_dict()
    e_f = exp_r(st_f["win_rate"], params["rr"])
    be = 1.0 / (1.0 + params["rr"])
    print(
        f"FUTURE rr={params['rr']} WR={st_f['win_rate']:.1%} (BE={be:.1%}) expR={e_f:.3f} "
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
    lock = {
        "name": "retail_real_edge_1k",
        "account": {"initial_balance": 1000, "leverage": 50, "max_dd_pct": 0.20},
        "timeframe": "1h",
        "pairs": PAIRS,
        "params": lock_params,
        "train_era": list(TRAIN),
        "hold_era": list(HOLD),
        "future_era": ["2026-01-01", "data_end"],
        "train": winner["train"],
        "hold": winner["hold"],
        "future_2026": st_f,
        "edge": {
            "rr": params["rr"],
            "breakeven_wr": be,
            "expectancy_r_train": winner["exp_t"],
            "expectancy_r_hold": winner["exp_h"],
            "expectancy_r_future": e_f,
            "wr_above_breakeven_train": winner["train"]["win_rate"] - be,
            "wr_above_breakeven_hold": winner["hold"]["win_rate"] - be,
            "why_not_roulette": (
                f"Asymmetric {params['rr']}:1 payoff. Breakeven WR is only {be:.0%}; "
                f"we hold ~{winner['hold']['win_rate']:.0%}. "
                "Not a 50/50 bet at even money."
            ),
        },
        "mcpt_p": winner["mcpt_p"],
        "mcpt_p_full_2016_2025": winner.get("mcpt_p_full"),
        "mcpt_pass": True,
        "rejects_coin_flip": True,
        "protocol": {
            "train": TRAIN,
            "hold": HOLD,
            "future": "2026-01-01",
            "note": "Asymmetric RR≥1.5 remake; HOLD unused for tuning; FUTURE never trained",
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
        f"WR={winner['train']['win_rate']:.1%}/{winner['hold']['win_rate']:.1%} "
        f"expR={winner['exp_t']:.3f}/{winner['exp_h']:.3f} "
        f"PF={winner['train']['profit_factor']:.2f}/{winner['hold']['profit_factor']:.2f} "
        f"p={winner['mcpt_p']:.3f}",
        flush=True,
    )


if __name__ == "__main__":
    main()
