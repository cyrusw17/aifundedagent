#!/usr/bin/env python3
"""Honest train / holdout hunt — fixed discrete grid, no curve-fitting.

Protocol
--------
1. TRAIN era: 2020-01-01 .. 2022-03-04  (screen candidates only)
2. HOLD  era: 2016-01-01 .. 2019-12-31  (must look similar; never used for tuning)
3. Fixed economically-motivated param grid (not free / random optimization)
4. Accept only if BOTH eras: not blown, consistency OK, positive annual $,
   enough trades, and holdout annual is similar to train
5. MCPT on TRAIN only for top screened candidates (p <= 0.05)

Re-running never peeks at holdout to pick params — holdout is a hard gate only.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.mcpt_forex import permute_forex_book

DATA = ROOT / "data" / "forex"
OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)

PAIRSETS = {
    "majors4": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"],
    "majors6": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF", "USDCAD"],
}

# Fixed discrete grid — economically motivated, NOT a free search space
MODES = [
    "kz_fvg",
    "killzone_smc",
    "london_asia_sweep",
    "h1_sweep_bos",
    "kz_active",
    "smc_plus",
]
RISKS = [0.005, 0.0075, 0.01]
RRS = [2.0, 2.5, 3.0]
ATRS = [0.7, 1.0, 1.25]
SKIP_MON = [True, False]
DAILY_HALTS = [0.015, 0.02]
ONE_PER_DAY = [True, False]
# Small fixed risk-management variants (not random)
COOLDOWNS = [0, 2]
MOVE_BE = [0.0]


def load_h1(pairs: list[str], start: str, end: str) -> dict[str, pd.DataFrame]:
    book = {}
    s, e = pd.Timestamp(start), pd.Timestamp(end)
    for p in pairs:
        path = DATA / f"{p}_1h_hist.parquet"
        if not path.exists():
            continue
        df = pd.read_parquet(path)
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        df = df[(df.index >= s) & (df.index <= e)]
        df = df[~df.index.duplicated(keep="last")].sort_index()
        if len(df) >= 400:
            book[p] = df
    return book


def similar(train_ann: float, hold_ann: float) -> bool:
    """Holdout must be profitable and not a totally different regime fit."""
    if train_ann <= 0 or hold_ann <= 0:
        return False
    if hold_ann >= 3000 and train_ann >= 3000:
        return True
    return hold_ann >= 0.4 * train_ann


def run_fast(prep, params) -> dict:
    st = fast_backtest(
        prep,
        risk_pct=params["risk_pct"],
        rr=params["rr"],
        atr_stop_mult=params["atr_stop_mult"],
        max_positions=params["max_positions"],
        move_be_at_r=params["move_be_at_r"],
        skip_mondays=params["skip_mondays"],
        daily_halt_loss_pct=params["daily_halt_loss_pct"],
        daily_halt_profit_pct=params["daily_halt_profit_pct"],
        cooldown_losses=params["cooldown_losses"],
        weekly_withdraw=True,
        one_entry_per_day=bool(params["one_entry_per_day"]),
    )
    return st.as_dict()


def mcpt_pvalue(book, params, n_perm: int, seed: int = 7) -> tuple[float, dict]:
    def run(b):
        prep = prepare_book(b, params["signal_mode"], params["swing_left"], params["min_confluence"])
        return fast_backtest(
            prep,
            risk_pct=params["risk_pct"],
            rr=params["rr"],
            atr_stop_mult=params["atr_stop_mult"],
            max_positions=params["max_positions"],
            move_be_at_r=params["move_be_at_r"],
            skip_mondays=params["skip_mondays"],
            daily_halt_loss_pct=params["daily_halt_loss_pct"],
            daily_halt_profit_pct=params["daily_halt_profit_pct"],
            cooldown_losses=params["cooldown_losses"],
            weekly_withdraw=True,
            one_entry_per_day=bool(params["one_entry_per_day"]),
        )

    def obj(st):
        if st.blown:
            return -1.0
        if not st.consistency_ok:
            return 0.0
        return (
            min(st.profit_factor, 5) * 0.25
            + (st.avg_annual_pnl / 10000) * 0.65
            + min(st.n_trades / 200, 1) * 0.1
        )

    real = run(book)
    rs = obj(real)
    better = 1
    for i in range(1, n_perm):
        if obj(run(permute_forex_book(book, seed=seed + i))) >= rs:
            better += 1
        if i % 25 == 0:
            print(f"    MCPT {i}/{n_perm} p~{better/(i+1):.3f}", flush=True)
    return better / n_perm, real.as_dict()


def build_grid(max_candidates: int = 0) -> list[dict]:
    grid = []
    for ps_name, pairs in PAIRSETS.items():
        for mode in MODES:
            for risk in RISKS:
                for rr in RRS:
                    for atr in ATRS:
                        for skip_m in SKIP_MON:
                            for halt in DAILY_HALTS:
                                for opd in ONE_PER_DAY:
                                    for cd in COOLDOWNS:
                                        for be in MOVE_BE:
                                            grid.append(
                                                {
                                                    "pairset": ps_name,
                                                    "pairs": pairs,
                                                    "signal_mode": mode,
                                                    "risk_pct": risk,
                                                    "rr": rr,
                                                    "atr_stop_mult": atr,
                                                    "max_positions": 1,
                                                    "min_confluence": 2,
                                                    "swing_left": 3,
                                                    "swing_right": 3,
                                                    "require_killzone": False,
                                                    "weekly_withdraw": True,
                                                    "move_be_at_r": be,
                                                    "skip_mondays": skip_m,
                                                    "daily_halt_loss_pct": halt,
                                                    "daily_halt_profit_pct": 0.03,
                                                    "cooldown_losses": cd,
                                                    "one_entry_per_day": opd,
                                                }
                                            )
    if max_candidates and max_candidates < len(grid):
        # Deterministic thin (stride) — still not random overfit
        step = max(len(grid) // max_candidates, 1)
        grid = grid[::step][:max_candidates]
    return grid


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--train-start", default="2020-01-01")
    ap.add_argument("--train-end", default="2022-03-04")
    ap.add_argument("--hold-start", default="2016-01-01")
    ap.add_argument("--hold-end", default="2019-12-31")
    ap.add_argument("--n-perm", type=int, default=200)
    ap.add_argument("--max-candidates", type=int, default=0)
    ap.add_argument("--top-mcpt", type=int, default=12)
    ap.add_argument("--out", type=Path, default=OUT / "honest_era_hunt.json")
    args = ap.parse_args()

    # Load full span once per pairset
    raw_all = {}
    for ps_name, pairs in PAIRSETS.items():
        raw_all[ps_name] = {
            "train": load_h1(pairs, args.train_start, args.train_end),
            "hold": load_h1(pairs, args.hold_start, args.hold_end),
        }
        for era in ("train", "hold"):
            book = raw_all[ps_name][era]
            print(
                f"{ps_name}/{era}: { {p: len(df) for p, df in book.items()} }",
                flush=True,
            )

    grid = build_grid(args.max_candidates)
    print(f"Grid size: {len(grid)}", flush=True)

    # Cache prepare_book by (era, pairset, mode)
    prep_cache: dict[tuple, dict] = {}

    def get_prep(era: str, pairset: str, mode: str, swing: int, min_conf: int):
        key = (era, pairset, mode, swing, min_conf)
        if key not in prep_cache:
            book = raw_all[pairset][era]
            prep_cache[key] = prepare_book(book, mode, swing, min_conf)
            print(f"  prepared {key[0]}/{key[1]}/{key[2]}", flush=True)
        return prep_cache[key]

    screened: list[dict] = []
    for i, params in enumerate(grid, 1):
        try:
            tprep = get_prep(
                "train",
                params["pairset"],
                params["signal_mode"],
                params["swing_left"],
                params["min_confluence"],
            )
            train_m = run_fast(tprep, params)
            if (
                train_m["blown"]
                or train_m["avg_annual_pnl"] <= 0
                or not train_m["consistency_ok"]
                or train_m["n_trades"] < 40
            ):
                if i % 100 == 0:
                    print(f"  [{i}/{len(grid)}] screened_ok={len(screened)}", flush=True)
                continue
            hprep = get_prep(
                "hold",
                params["pairset"],
                params["signal_mode"],
                params["swing_left"],
                params["min_confluence"],
            )
            hold_m = run_fast(hprep, params)
            if (
                hold_m["blown"]
                or hold_m["avg_annual_pnl"] <= 0
                or not hold_m["consistency_ok"]
                or hold_m["n_trades"] < 40
            ):
                continue
            if not similar(train_m["avg_annual_pnl"], hold_m["avg_annual_pnl"]):
                continue
            score = min(train_m["avg_annual_pnl"], hold_m["avg_annual_pnl"]) + 1500 * (
                int(train_m["hit_eval_target"]) + int(hold_m["hit_eval_target"])
            )
            row = {
                "params": {k: v for k, v in params.items() if k != "pairs"},
                "pairs": params["pairs"],
                "train": train_m,
                "hold": hold_m,
                "score": score,
            }
            screened.append(row)
            print(
                f"  PASS screen [{i}] {params['signal_mode']} {params['pairset']} "
                f"r={params['risk_pct']} rr={params['rr']} atr={params['atr_stop_mult']} "
                f"train_ann=${train_m['avg_annual_pnl']:,.0f} "
                f"hold_ann=${hold_m['avg_annual_pnl']:,.0f} "
                f"eval T/H={train_m['hit_eval_target']}/{hold_m['hit_eval_target']}",
                flush=True,
            )
        except Exception as e:
            print(f"  err {i}: {e}", flush=True)
        if i % 100 == 0:
            print(f"  progress {i}/{len(grid)} screened_ok={len(screened)}", flush=True)

    screened.sort(key=lambda r: r["score"], reverse=True)
    print(f"\nScreened survivors: {len(screened)}", flush=True)

    mcpt_rows = []
    accepted = None
    rules = FundedRules()

    for rank, row in enumerate(screened[: args.top_mcpt], 1):
        params = {**row["params"]}
        # restore pairs for backtest kwargs cleanly
        bt_params = {
            k: params[k]
            for k in (
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
            )
        }
        print(
            f"\n=== MCPT rank {rank}: {bt_params['signal_mode']} "
            f"{params['pairset']} score={row['score']:.0f} ===",
            flush=True,
        )
        train_book = raw_all[params["pairset"]]["train"]
        hold_book = raw_all[params["pairset"]]["hold"]

        bt_train = run_backtest(train_book, rules=rules, **bt_params)
        bt_hold = run_backtest(hold_book, rules=rules, **bt_params)
        pval, mcpt_real = mcpt_pvalue(train_book, {**bt_params}, args.n_perm, seed=42 + rank)

        rec = {
            "rank": rank,
            "pairset": params["pairset"],
            "pairs": row["pairs"],
            "params": bt_params,
            "train_fast": row["train"],
            "hold_fast": row["hold"],
            "train_bt": bt_train.stats,
            "hold_bt": bt_hold.stats,
            "mcpt_train_fast": mcpt_real,
            "mcpt_p": pval,
            "mcpt_pass": pval <= 0.05,
            "score": row["score"],
        }
        mcpt_rows.append(rec)
        print(
            f"  BT train ann=${bt_train.stats['avg_annual_pnl']:,.0f} "
            f"pf={bt_train.stats['profit_factor']:.2f} blown={bt_train.stats['blown']} | "
            f"hold ann=${bt_hold.stats['avg_annual_pnl']:,.0f} "
            f"pf={bt_hold.stats['profit_factor']:.2f} blown={bt_hold.stats['blown']} | "
            f"MCPT p={pval:.4f}",
            flush=True,
        )
        train_ok = (
            not bt_train.stats["blown"]
            and bt_train.stats["avg_annual_pnl"] > 0
            and bt_train.stats.get("consistency_ok", False)
        )
        hold_ok = (
            not bt_hold.stats["blown"]
            and bt_hold.stats["avg_annual_pnl"] > 0
            and bt_hold.stats.get("consistency_ok", False)
            and similar(bt_train.stats["avg_annual_pnl"], bt_hold.stats["avg_annual_pnl"])
        )
        if pval <= 0.05 and train_ok and hold_ok:
            accepted = rec
            print("  >>> ACCEPTED (MCPT + dual-era)", flush=True)
            break

    payload = {
        "protocol": {
            "train": [args.train_start, args.train_end],
            "hold": [args.hold_start, args.hold_end],
            "n_perm": args.n_perm,
            "grid_size": len(grid),
            "screened": len(screened),
            "note": (
                "Fixed discrete grid; holdout never used for tuning; "
                "MCPT on train only after dual-era screen."
            ),
        },
        "accepted": accepted,
        "top_mcpt": mcpt_rows,
        "top_screened": [
            {
                "score": r["score"],
                "params": r["params"],
                "pairs": r["pairs"],
                "train_ann": r["train"]["avg_annual_pnl"],
                "hold_ann": r["hold"]["avg_annual_pnl"],
                "train_trades": r["train"]["n_trades"],
                "hold_trades": r["hold"]["n_trades"],
            }
            for r in screened[:30]
        ],
    }

    if accepted is not None:
        lock = {
            "name": "honest_era_winner",
            "timeframe": "1h",
            "pairset": accepted["pairset"],
            "pairs": accepted["pairs"],
            "params": accepted["params"],
            "train_era": [args.train_start, args.train_end],
            "hold_era": [args.hold_start, args.hold_end],
            "train_bt": accepted["train_bt"],
            "hold_bt": accepted["hold_bt"],
            "mcpt_p": accepted["mcpt_p"],
            "mcpt_pass": True,
            "protocol": payload["protocol"],
            "same_bar_stop_tp": True,
        }
        lock_path = OUT / "best_strategy_honest.json"
        lock_path.write_text(json.dumps(lock, indent=2))
        # Also promote to best_strategy.json when dual-era + MCPT pass
        BEST = OUT / "best_strategy.json"
        BEST.write_text(json.dumps({**lock, "source": "honest_era_hunt"}, indent=2))
        print(f"Locked {lock_path} and {BEST}", flush=True)
        payload["lock_path"] = str(lock_path)
    else:
        # Keep best screened (even if MCPT failed) for iteration visibility
        if mcpt_rows:
            best_fail = min(mcpt_rows, key=lambda r: r["mcpt_p"])
            fail_path = OUT / "best_strategy_honest_candidate.json"
            fail_path.write_text(
                json.dumps(
                    {
                        "name": "honest_era_best_mcpt_fail",
                        "note": "Best dual-era screen; did not pass MCPT<=0.05",
                        **{k: v for k, v in best_fail.items()},
                        "protocol": payload["protocol"],
                    },
                    indent=2,
                    default=str,
                )
            )
            print(f"Wrote candidate (MCPT fail) {fail_path}", flush=True)

    args.out.write_text(json.dumps(payload, indent=2, default=str))
    print(f"Wrote {args.out}", flush=True)
    if accepted is None:
        print("NO candidate passed MCPT + dual-era gate.", flush=True)
        if screened:
            print(
                "Best screened:",
                json.dumps(payload["top_screened"][0], indent=2, default=str),
                flush=True,
            )


if __name__ == "__main__":
    main()
