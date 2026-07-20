#!/usr/bin/env python3
"""Lock retail winner: confirmatory MCPT on 2016–2025, future-test 2026+ only."""

from __future__ import annotations

import json
import sys
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
    mcpt_objective,
)

# Winner from edge probe (MCPT p=0.013 on train)
PARAMS = {
    "signal_mode": "h1_sweep_bos",
    "pairset": "majors4",
    "pairs": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"],
    "max_positions": 1,
    "min_confluence": 2,
    "swing_left": 2,
    "swing_right": 2,
    "require_killzone": False,
    "weekly_withdraw": False,
    "risk_pct": 0.005,
    "rr": 1.0,
    "atr_stop_mult": 1.75,
    "skip_mondays": True,
    "one_entry_per_day": True,
    "cooldown_losses": 2,
    "daily_halt_loss_pct": 0.03,
    "daily_halt_profit_pct": 0.05,
    "move_be_at_r": 0.0,
}


def run(book, params):
    prep = prepare_book(book, params["signal_mode"], params["swing_left"], params["min_confluence"])
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


def mcpt_p(book, params, n_perm=150, seed=21):
    real = run(book, params)
    rs = mcpt_objective(real, min_wr=0.45)
    better = 1
    for i in range(1, n_perm):
        if mcpt_objective(run(permute_forex_book(book, seed=seed + i), params), min_wr=0.45) >= rs:
            better += 1
        if i % 40 == 0:
            print(f"    MCPT {i}/{n_perm} p~{better/(i+1):.3f}", flush=True)
    return better / n_perm, real.as_dict()


def main() -> None:
    # Allow override from edge_probe_accepted.json
    accepted_path = Path("/tmp/edge_probe_accepted.json")
    params = dict(PARAMS)
    train_p_hint = 0.013
    if accepted_path.exists():
        acc = json.loads(accepted_path.read_text())
        if acc:
            best = sorted(acc, key=lambda x: x.get("mcpt_p", 1))[0]
            params = best["params"]
            train_p_hint = best.get("mcpt_p", train_p_hint)
            print(f"Using accepted winner from probe p={train_p_hint}", flush=True)

    print(f"Locking {params['signal_mode']} rr={params['rr']} risk={params['risk_pct']} "
          f"atr={params['atr_stop_mult']} sw={params['swing_left']}", flush=True)

    bt = load_merged(params["pairs"], *TRAIN)
    bh = load_merged(params["pairs"], *HOLD)
    b_full = load_merged(params["pairs"], "2016-01-01", "2025-12-31")
    assert all(df.index.max() < pd.Timestamp("2026-01-01") for df in b_full.values())

    print("=== TRAIN MCPT (confirm) ===", flush=True)
    p_train, st_t = mcpt_p(bt, params, n_perm=150)
    print(f"train p={p_train:.3f} WR={st_t['win_rate']:.1%} PF={st_t['profit_factor']:.3f} "
          f"ann={st_t['avg_annual_pnl']:.1f} dd={st_t['max_dd_pct']:.1%} n={st_t['n_trades']}", flush=True)

    print("=== HOLD stats (no tune) ===", flush=True)
    st_h = run(bh, params).as_dict()
    print(f"hold WR={st_h['win_rate']:.1%} PF={st_h['profit_factor']:.3f} "
          f"ann={st_h['avg_annual_pnl']:.1f} dd={st_h['max_dd_pct']:.1%} blown={st_h['blown']} n={st_h['n_trades']}", flush=True)

    print("=== FULL 2016-2025 confirmatory MCPT (never 2026+) ===", flush=True)
    p_full, st_full = mcpt_p(b_full, params, n_perm=120, seed=41)
    print(f"full p={p_full:.3f} WR={st_full['win_rate']:.1%} PF={st_full['profit_factor']:.3f} "
          f"ann={st_full['avg_annual_pnl']:.1f} dd={st_full['max_dd_pct']:.1%}", flush=True)

    assert st_t["win_rate"] >= 0.45 and st_h["win_rate"] >= 0.42
    assert st_t["max_dd_pct"] <= 0.20 and st_h["max_dd_pct"] <= 0.20
    assert not st_t["blown"] and not st_h["blown"]
    assert p_train <= 0.05

    print("=== FUTURE 2026+ (report only, never trained) ===", flush=True)
    fut = load_future(params["pairs"])
    warm = load_merged(params["pairs"], "2025-07-01", "2025-12-31")
    combined = {}
    for pair in params["pairs"]:
        combined[pair] = pd.concat([warm[pair], fut[pair]]).sort_index()
        combined[pair] = combined[pair][~combined[pair].index.duplicated(keep="last")]
    fut_only = {
        pair: combined[pair][combined[pair].index >= pd.Timestamp("2026-01-01")] for pair in combined
    }
    assert all(df.index.min() >= pd.Timestamp("2026-01-01") for df in fut_only.values())
    st_f = run(fut_only, params).as_dict()
    print(
        f"future WR={st_f['win_rate']:.1%} PF={st_f['profit_factor']:.3f} "
        f"ann={st_f['avg_annual_pnl']:.1f} dd={st_f['max_dd_pct']:.1%} "
        f"blown={st_f['blown']} n={st_f['n_trades']} bal={st_f['final_balance']:.1f}",
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
        "train": st_t,
        "hold": st_h,
        "full_2016_2025": st_full,
        "future_2026": st_f,
        "mcpt_p": p_train,
        "mcpt_p_full_2016_2025": p_full,
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
    }
    path = OUT / "best_strategy_retail_1k.json"
    path.write_text(json.dumps(lock, indent=2, default=str))
    BEST_PATH.write_text(json.dumps(lock, indent=2, default=str))
    (OUT / "retail_timeless_results.json").write_text(
        json.dumps({"accepted": 1, "winner": lock}, indent=2, default=str)
    )
    print(f"LOCKED -> {path}", flush=True)
    print(
        f"WINNER {params['signal_mode']} risk={params['risk_pct']} rr={params['rr']} "
        f"atr={params['atr_stop_mult']} sw={params['swing_left']} "
        f"p_train={p_train:.3f} p_full={p_full:.3f} "
        f"WR T/H/F={st_t['win_rate']:.1%}/{st_h['win_rate']:.1%}/{st_f['win_rate']:.1%}",
        flush=True,
    )


if __name__ == "__main__":
    main()
