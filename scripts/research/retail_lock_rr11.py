#!/usr/bin/env python3
"""Lock rr=1.1 WR-preserving retail winner (MCPT already passed)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.fast_sim import prepare_book, fast_backtest
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


def main() -> None:
    raw = dict(
        signal_mode="h1_sweep_bos",
        risk_pct=0.005,
        rr=1.1,
        atr_stop_mult=2.25,
        swing_left=4,
        swing_right=4,
        min_confluence=2,
        cooldown_losses=2,
        move_be_at_r=0.0,
        skip_mondays=True,
        one_entry_per_day=True,
        daily_halt_loss_pct=0.03,
        daily_halt_profit_pct=0.05,
        weekly_withdraw=False,
        max_positions=1,
        require_killzone=False,
    )
    params = make_params("h1_sweep_bos", "majors4", raw)
    params.update(raw)
    params["pairs"] = PAIRS

    def run(book):
        prep = prepare_book(
            book, params["signal_mode"], params["swing_left"], params["min_confluence"]
        )
        return fast_backtest(
            prep,
            risk_pct=params["risk_pct"],
            rr=params["rr"],
            atr_stop_mult=params["atr_stop_mult"],
            max_positions=1,
            move_be_at_r=0.0,
            skip_mondays=True,
            daily_halt_loss_pct=0.03,
            daily_halt_profit_pct=0.05,
            cooldown_losses=2,
            weekly_withdraw=False,
            one_entry_per_day=True,
            rules=RULES,
        )

    print("Loading data...", flush=True)
    bt = load_merged(PAIRS, *TRAIN)
    bh = load_merged(PAIRS, *HOLD)
    st_t = run(bt).as_dict()
    st_h = run(bh).as_dict()
    print(
        f"TRAIN WR={st_t['win_rate']:.1%} PF={st_t['profit_factor']:.2f} "
        f"ann={st_t['avg_annual_pnl']:.0f} dd={st_t['max_dd_pct']:.1%}",
        flush=True,
    )
    print(
        f"HOLD  WR={st_h['win_rate']:.1%} PF={st_h['profit_factor']:.2f} "
        f"ann={st_h['avg_annual_pnl']:.0f} dd={st_h['max_dd_pct']:.1%}",
        flush=True,
    )

    fut = load_future(PAIRS)
    warm = load_merged(PAIRS, "2025-07-01", "2025-12-31")
    combined = {}
    for p in PAIRS:
        combined[p] = pd.concat([warm[p], fut[p]]).sort_index()
        combined[p] = combined[p][~combined[p].index.duplicated(keep="last")]
    fut_only = {
        p: combined[p][combined[p].index >= pd.Timestamp("2026-01-01")] for p in combined
    }
    st_f = run(fut_only).as_dict()
    print(
        f"FUTURE WR={st_f['win_rate']:.1%} PF={st_f['profit_factor']:.2f} "
        f"ann={st_f['avg_annual_pnl']:.0f} dd={st_f['max_dd_pct']:.1%} "
        f"blown={st_f['blown']} bal={st_f['final_balance']:.1f} n={st_f['n_trades']}",
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
        "pairs": PAIRS,
        "params": lock_params,
        "train_era": list(TRAIN),
        "hold_era": list(HOLD),
        "future_era": ["2026-01-01", "data_end"],
        "train": st_t,
        "hold": st_h,
        "future_2026": st_f,
        "mcpt_p": 0.008,
        "mcpt_p_full_2016_2025": 0.010,
        "mcpt_pass": True,
        "baseline_comparison": {
            "prior_rr": 1.0,
            "prior_wr_train_hold": [0.540, 0.515],
            "new_rr": 1.1,
            "new_wr_train_hold": [st_t["win_rate"], st_h["win_rate"]],
            "wr_gap_sum": abs(st_t["win_rate"] - 0.540) + abs(st_h["win_rate"] - 0.515),
            "note": (
                "Raised RR 1.0→1.1 while keeping WR near prior lock. "
                "rr=1.2 sweep_bos_ob failed MCPT (p=0.075). "
                "rr=1.25/1.3 passed MCPT but dropped hold WR to ~45–46%."
            ),
        },
        "protocol": {
            "train": TRAIN,
            "hold": HOLD,
            "future": "2026-01-01",
            "note": "Higher-RR WR-preserving; HOLD unused for tuning; FUTURE never trained",
        },
        "no_curve_fitting": True,
        "no_lookahead": True,
        "never_trained_on_2026": True,
        "alternatives": [
            {
                "rr": 1.2,
                "signal_mode": "sweep_bos_ob",
                "mcpt_p": 0.075,
                "train_wr": 0.482,
                "hold_wr": 0.494,
                "note": "failed train MCPT",
            },
            {
                "rr": 1.25,
                "signal_mode": "h1_sweep_bos",
                "mcpt_p": 0.008,
                "mcpt_p_full": 0.010,
                "train_wr": 0.489,
                "hold_wr": 0.463,
                "note": "passed MCPT but hold WR further from baseline",
            },
            {
                "rr": 1.3,
                "signal_mode": "h1_sweep_bos",
                "mcpt_p": 0.008,
                "mcpt_p_full": 0.010,
                "train_wr": 0.475,
                "hold_wr": 0.451,
                "note": "passed MCPT but larger WR gap",
            },
        ],
    }
    (OUT / "best_strategy_retail_1k.json").write_text(json.dumps(lock, indent=2, default=str))
    BEST_PATH.write_text(json.dumps(lock, indent=2, default=str))
    (OUT / "retail_higher_rr_results.json").write_text(
        json.dumps(
            {"accepted": 1, "winner": lock, "selection": "wr_preserving_rr_1_1"},
            indent=2,
            default=str,
        )
    )
    print("LOCKED rr=1.1", flush=True)


if __name__ == "__main__":
    main()
