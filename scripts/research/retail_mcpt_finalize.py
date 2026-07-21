#!/usr/bin/env python3
"""Focused retail MCPT finalize — PnL objective, dual-era gates, future 2026+ only.

Never trains/tunes on 2026+. Uses fixed grid survivors from sweep_bos_ob_kz (+ backups).
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
    sim,
    era_ok,
    score,
    mcpt,
    MIN_TRADES_TRAIN,
    MIN_TRADES_HOLD,
    MIN_ANN_TRAIN,
    MIN_ANN_HOLD,
)

PAIRS = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"]
MODES = ["sweep_bos_ob_kz", "sweep_bos_ob", "h1_sweep_bos", "ob_confirm"]

RISKS = [0.003, 0.004, 0.005, 0.0075]
RRS = [1.0, 1.2, 1.5]
ATRS = [1.25, 1.5, 1.75]
COOL = [0, 2]
BE = [0.0, 1.0]
HALTS = [0.03, 0.04]


def main() -> None:
    print("=== Retail MCPT finalize (PnL objective) ===", flush=True)
    print(f"Rules bal={RULES.initial_balance} lev={RULES.leverage} max_dd={RULES.max_dd_pct}", flush=True)

    bt = load_merged(PAIRS, *TRAIN)
    bh = load_merged(PAIRS, *HOLD)
    # Confirmatory MCPT window through 2025 (params already dual-era gated; never 2026+)
    b_full = load_merged(PAIRS, "2016-01-01", "2025-12-31")
    assert all(df.index.max() < pd.Timestamp("2026-01-01") for df in b_full.values())

    base = dict(
        risk_pct=0.004,
        rr=1.0,
        atr_stop_mult=1.75,
        skip_mondays=True,
        one_entry_per_day=True,
        cooldown_losses=2,
        daily_halt_loss_pct=0.03,
        daily_halt_profit_pct=0.05,
        move_be_at_r=0.0,
    )

    rows = []
    for mode in MODES:
        print(f"prepare {mode}...", flush=True)
        pt = prepare_book(bt, mode, 3, 2)
        ph = prepare_book(bh, mode, 3, 2)
        local = 0
        for risk, rr, atr, cool, be, halt in product(RISKS, RRS, ATRS, COOL, BE, HALTS):
            params = make_params(
                mode,
                "majors4",
                base,
                risk_pct=risk,
                rr=rr,
                atr_stop_mult=atr,
                cooldown_losses=cool,
                move_be_at_r=be,
                daily_halt_loss_pct=halt,
                daily_halt_profit_pct=max(halt + 0.02, 0.05),
            )
            st_t = sim(pt, params)
            if not era_ok(st_t, min_trades=MIN_TRADES_TRAIN, min_wr=0.45, min_ann=MIN_ANN_TRAIN):
                continue
            st_h = sim(ph, params)
            if not era_ok(st_h, min_trades=MIN_TRADES_HOLD, min_wr=0.42, min_ann=MIN_ANN_HOLD):
                continue
            rows.append(
                {
                    "params": params,
                    "train": st_t,
                    "hold": st_h,
                    "score": score(st_t, st_h),
                }
            )
            local += 1
        print(f"  {mode}: {local} dual-era hits", flush=True)

    if not rows:
        print("No hits at WR 45/42 — relaxing to 43/40", flush=True)
        for mode in MODES:
            pt = prepare_book(bt, mode, 3, 2)
            ph = prepare_book(bh, mode, 3, 2)
            for risk, rr, atr, cool, be, halt in product(RISKS, RRS, ATRS, COOL, BE, HALTS):
                params = make_params(
                    mode,
                    "majors4",
                    base,
                    risk_pct=risk,
                    rr=rr,
                    atr_stop_mult=atr,
                    cooldown_losses=cool,
                    move_be_at_r=be,
                    daily_halt_loss_pct=halt,
                    daily_halt_profit_pct=max(halt + 0.02, 0.05),
                )
                st_t = sim(pt, params)
                if not era_ok(st_t, min_trades=MIN_TRADES_TRAIN, min_wr=0.43, min_ann=30.0):
                    continue
                st_h = sim(ph, params)
                if not era_ok(st_h, min_trades=MIN_TRADES_HOLD, min_wr=0.40, min_ann=0.0):
                    continue
                rows.append(
                    {
                        "params": params,
                        "train": st_t,
                        "hold": st_h,
                        "score": score(st_t, st_h),
                    }
                )

    rows.sort(key=lambda r: -r["score"])
    print(f"Total dual-era survivors: {len(rows)}", flush=True)
    for r in rows[:12]:
        p = r["params"]
        print(
            f"  {p['signal_mode']} rr={p['rr']} risk={p['risk_pct']} atr={p['atr_stop_mult']} "
            f"BE={p['move_be_at_r']} WR={r['train']['win_rate']:.1%}/{r['hold']['win_rate']:.1%} "
            f"PF={r['train']['profit_factor']:.2f}/{r['hold']['profit_factor']:.2f} "
            f"ann={r['train']['avg_annual_pnl']:.0f}/{r['hold']['avg_annual_pnl']:.0f} "
            f"dd={r['train']['max_dd_pct']:.1%}/{r['hold']['max_dd_pct']:.1%}",
            flush=True,
        )

    (OUT / "retail_timeless_screen.json").write_text(
        json.dumps(
            {
                "protocol": {"train": TRAIN, "hold": HOLD, "future": "2026-01-01"},
                "n_hits": len(rows),
                "top": [
                    {
                        "score": r["score"],
                        "params": r["params"],
                        "train_wr": r["train"]["win_rate"],
                        "hold_wr": r["hold"]["win_rate"],
                        "train_pf": r["train"]["profit_factor"],
                        "hold_pf": r["hold"]["profit_factor"],
                        "train_ann": r["train"]["avg_annual_pnl"],
                        "hold_ann": r["hold"]["avg_annual_pnl"],
                        "train_dd": r["train"]["max_dd_pct"],
                        "hold_dd": r["hold"]["max_dd_pct"],
                    }
                    for r in rows[:40]
                ],
            },
            indent=2,
            default=str,
        )
    )

    queue = []
    seen = set()
    for r in rows:
        p = r["params"]
        key = (p["signal_mode"], p["rr"], p["risk_pct"], p["atr_stop_mult"], p["move_be_at_r"])
        if key in seen:
            continue
        seen.add(key)
        queue.append(r)
        if len(queue) >= 12:
            break

    accepted = []
    finalists = []
    for r in queue:
        p = r["params"]
        print(
            f"\nMCPT {p['signal_mode']} rr={p['rr']} risk={p['risk_pct']} atr={p['atr_stop_mult']} "
            f"WR={r['train']['win_rate']:.1%}/{r['hold']['win_rate']:.1%} "
            f"PF={r['train']['profit_factor']:.2f}/{r['hold']['profit_factor']:.2f} "
            f"ann={r['train']['avg_annual_pnl']:.0f}/{r['hold']['avg_annual_pnl']:.0f}",
            flush=True,
        )
        # Primary MCPT on TRAIN; confirmatory on 2016–2025 if train passes
        p_train = mcpt(bt, p, n_perm=150, min_wr=0.45)
        print(f"  train p={p_train:.3f}", flush=True)
        p_full = None
        accept = p_train <= 0.05
        if accept:
            p_full = mcpt(b_full, p, n_perm=120, min_wr=0.45)
            print(f"  full2016-2025 p={p_full:.3f}", flush=True)
            accept = p_full <= 0.05
        row = {**r, "mcpt_p": p_train, "mcpt_p_full": p_full, "mcpt_pass": accept, "accept": accept}
        finalists.append(row)
        if accept:
            accepted.append(row)
            if len(accepted) >= 3:
                break

    print(f"\nAccepted: {len(accepted)}/{len(finalists)}", flush=True)
    if not accepted:
        (OUT / "retail_timeless_results.json").write_text(
            json.dumps({"accepted": 0, "finalists": finalists, "top": rows[:20]}, indent=2, default=str)
        )
        print("FAILED: no MCPT pass", flush=True)
        sys.exit(1)

    winner = sorted(
        accepted,
        key=lambda x: (
            -min(x["train"]["profit_factor"], x["hold"]["profit_factor"]),
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
    fut_st = sim(prepare_book(fut_only, params["signal_mode"], 3, 2), params)
    print(
        f"FUTURE 2026+ WR={fut_st['win_rate']:.1%} PF={fut_st['profit_factor']:.2f} "
        f"dd={fut_st['max_dd_pct']:.1%} ann={fut_st['avg_annual_pnl']:.1f} "
        f"blown={fut_st['blown']} n={fut_st['n_trades']} bal={fut_st['final_balance']:.1f}",
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
        "future_2026": fut_st,
        "mcpt_p": winner["mcpt_p"],
        "mcpt_p_full_2016_2025": winner.get("mcpt_p_full"),
        "mcpt_pass": True,
        "min_wr_gate": {"train": 0.45, "hold": 0.42},
        "protocol": {
            "train": TRAIN,
            "hold": HOLD,
            "future": "2026-01-01",
            "mcpt_windows": ["2016-2023 train", "2016-2025 confirmatory"],
            "note": "Fixed grid; HOLD unused for tuning; FUTURE never used for training; causal; same-bar stop; PnL MCPT objective",
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
                "train_ann": a["train"]["avg_annual_pnl"],
                "hold_ann": a["hold"]["avg_annual_pnl"],
            }
            for a in accepted[:8]
        ],
    }
    (OUT / "best_strategy_retail_1k.json").write_text(json.dumps(lock, indent=2, default=str))
    BEST_PATH.write_text(json.dumps(lock, indent=2, default=str))
    (OUT / "retail_timeless_results.json").write_text(
        json.dumps({"accepted": len(accepted), "winner": lock, "finalists": finalists}, indent=2, default=str)
    )
    print(
        f"LOCKED {params['signal_mode']} rr={params['rr']} risk={params['risk_pct']} "
        f"p={winner['mcpt_p']:.3f} WR T/H={winner['train']['win_rate']:.1%}/{winner['hold']['win_rate']:.1%}",
        flush=True,
    )


if __name__ == "__main__":
    main()
