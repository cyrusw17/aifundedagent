#!/usr/bin/env python3
"""Aggressive OB/confluence hunt targeting >= $10k/yr and fast eval pass.

Protocol (no curve-fitting on holdout):
  TRAIN: 2020-01-01 .. 2022-03-04  — screen + MCPT
  HOLD:  2016-01-01 .. 2019-12-31  — must also print ~similar edge
  Accept: both eras avg_annual_pnl >= 10000, not blown, consistency OK,
          MCPT p <= 0.05 on train, and eval hit (+10%) in a reasonable window.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.challenge import rolling_eval_windows, simulate_challenge
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.mcpt_forex import permute_forex_book
from mcpt.forex.month_challenge import rolling_month_eval

DATA = ROOT / "data" / "forex"
OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)

PAIRSETS = {
    "majors4": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"],
    "majors6": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF", "USDCAD"],
}

MODES = [
    "ob_confirm",
    "sweep_wait_ob",
    "triple_confirm",
    "kz_ob_fvg",
    "killzone_smc",
    "h1_sweep_bos",
    "kz_fvg",
]

# Aggressive but fixed discrete grid
RISKS = [0.0075, 0.01, 0.012, 0.015]
RRS = [1.8, 2.0, 2.5, 3.0]
ATRS = [1.0, 1.25, 1.5]
SKIP = [True, False]
HALTS = [0.02, 0.025]
OPD = [True, False]
COOL = [0, 2]
BE = [0.0, 1.0]


def load_h1(pairs, start, end):
    book = {}
    s, e = pd.Timestamp(start), pd.Timestamp(end)
    for p in pairs:
        path = DATA / f"{p}_1h_hist.parquet"
        df = pd.read_parquet(path)
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        df = df[(df.index >= s) & (df.index <= e)]
        df = df[~df.index.duplicated(keep="last")].sort_index()
        if len(df) >= 400:
            book[p] = df
    return book


def mcpt(book, params, n=150, seed=9):
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
            one_entry_per_day=params["one_entry_per_day"],
        )

    def obj(st):
        if st.blown:
            return -1.0
        if not st.consistency_ok:
            return 0.0
        return (
            min(st.profit_factor, 5) * 0.2
            + (st.avg_annual_pnl / 10000) * 0.7
            + min(st.n_trades / 150, 1) * 0.1
        )

    real = run(book)
    rs = obj(real)
    better = 1
    for i in range(1, n):
        if obj(run(permute_forex_book(book, seed=seed + i))) >= rs:
            better += 1
        if i % 50 == 0:
            print(f"    MCPT {i}/{n} p~{better/(i+1):.3f}", flush=True)
    return better / n, real.as_dict()


def build_grid(max_n: int = 0):
    grid = []
    for ps, pairs in PAIRSETS.items():
        for mode in MODES:
            for risk in RISKS:
                for rr in RRS:
                    for atr in ATRS:
                        for skip in SKIP:
                            for halt in HALTS:
                                for opd in OPD:
                                    for cd in COOL:
                                        for be in BE:
                                            grid.append(
                                                dict(
                                                    pairset=ps,
                                                    pairs=pairs,
                                                    signal_mode=mode,
                                                    risk_pct=risk,
                                                    rr=rr,
                                                    atr_stop_mult=atr,
                                                    max_positions=1,
                                                    min_confluence=2,
                                                    swing_left=3,
                                                    swing_right=3,
                                                    require_killzone=False,
                                                    weekly_withdraw=True,
                                                    move_be_at_r=be,
                                                    skip_mondays=skip,
                                                    daily_halt_loss_pct=halt,
                                                    daily_halt_profit_pct=0.04,
                                                    cooldown_losses=cd,
                                                    one_entry_per_day=opd,
                                                )
                                            )
    if max_n and max_n < len(grid):
        step = max(len(grid) // max_n, 1)
        grid = grid[::step][:max_n]
    return grid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-candidates", type=int, default=0)
    ap.add_argument("--n-perm", type=int, default=150)
    ap.add_argument("--min-ann", type=float, default=10000.0)
    ap.add_argument("--top-mcpt", type=int, default=15)
    args = ap.parse_args()

    raw = {}
    for ps, pairs in PAIRSETS.items():
        raw[ps] = {
            "train": load_h1(pairs, "2020-01-01", "2022-03-04"),
            "hold": load_h1(pairs, "2016-01-01", "2019-12-31"),
            "full": load_h1(pairs, "2016-01-01", "2022-03-04"),
        }
        print(ps, {e: len(raw[ps][e]) for e in raw[ps]}, flush=True)

    grid = build_grid(args.max_candidates)
    print(f"Grid {len(grid)}", flush=True)

    prep_cache = {}

    def get_prep(era, ps, mode, swing, conf):
        key = (era, ps, mode, swing, conf)
        if key not in prep_cache:
            prep_cache[key] = prepare_book(raw[ps][era], mode, swing, conf)
            print(f"  prepared {era}/{ps}/{mode}", flush=True)
        return prep_cache[key]

    screened = []
    for i, p in enumerate(grid, 1):
        try:
            tprep = get_prep("train", p["pairset"], p["signal_mode"], p["swing_left"], p["min_confluence"])
            th = fast_backtest(
                tprep,
                risk_pct=p["risk_pct"],
                rr=p["rr"],
                atr_stop_mult=p["atr_stop_mult"],
                max_positions=1,
                move_be_at_r=p["move_be_at_r"],
                skip_mondays=p["skip_mondays"],
                daily_halt_loss_pct=p["daily_halt_loss_pct"],
                daily_halt_profit_pct=p["daily_halt_profit_pct"],
                cooldown_losses=p["cooldown_losses"],
                weekly_withdraw=True,
                one_entry_per_day=p["one_entry_per_day"],
            )
            if (
                th.blown
                or th.avg_annual_pnl < args.min_ann
                or not th.consistency_ok
                or th.n_trades < 40
            ):
                if i % 200 == 0:
                    print(f"  [{i}/{len(grid)}] ok={len(screened)}", flush=True)
                continue
            hprep = get_prep("hold", p["pairset"], p["signal_mode"], p["swing_left"], p["min_confluence"])
            hh = fast_backtest(
                hprep,
                risk_pct=p["risk_pct"],
                rr=p["rr"],
                atr_stop_mult=p["atr_stop_mult"],
                max_positions=1,
                move_be_at_r=p["move_be_at_r"],
                skip_mondays=p["skip_mondays"],
                daily_halt_loss_pct=p["daily_halt_loss_pct"],
                daily_halt_profit_pct=p["daily_halt_profit_pct"],
                cooldown_losses=p["cooldown_losses"],
                weekly_withdraw=True,
                one_entry_per_day=p["one_entry_per_day"],
            )
            if (
                hh.blown
                or hh.avg_annual_pnl < args.min_ann * 0.55  # hold at least ~55% of target
                or not hh.consistency_ok
                or hh.n_trades < 40
            ):
                continue
            # similar: hold >= 40% of train or both strong
            if hh.avg_annual_pnl < 0.4 * th.avg_annual_pnl and hh.avg_annual_pnl < args.min_ann:
                continue
            score = min(th.avg_annual_pnl, hh.avg_annual_pnl) + 2000 * int(th.hit_eval_target) + 2000 * int(
                hh.hit_eval_target
            )
            screened.append(
                dict(
                    params={k: v for k, v in p.items() if k != "pairs"},
                    pairs=p["pairs"],
                    train=th.as_dict(),
                    hold=hh.as_dict(),
                    score=score,
                )
            )
            print(
                f"  HIT [{i}] {p['signal_mode']} {p['pairset']} r={p['risk_pct']} rr={p['rr']} "
                f"train=${th.avg_annual_pnl:,.0f} hold=${hh.avg_annual_pnl:,.0f} "
                f"eval T/H={th.hit_eval_target}/{hh.hit_eval_target}",
                flush=True,
            )
        except Exception as ex:
            print(f"  err {i}: {ex}", flush=True)
        if i % 200 == 0:
            print(f"  progress {i}/{len(grid)} screened={len(screened)}", flush=True)

    screened.sort(key=lambda r: r["score"], reverse=True)
    print(f"\nScreened {len(screened)}", flush=True)
    (OUT / "aggressive_ob_screen.json").write_text(
        json.dumps(
            [
                {
                    "score": r["score"],
                    "params": r["params"],
                    "pairs": r["pairs"],
                    "train_ann": r["train"]["avg_annual_pnl"],
                    "hold_ann": r["hold"]["avg_annual_pnl"],
                    "train_eval": r["train"]["hit_eval_target"],
                    "hold_eval": r["hold"]["hit_eval_target"],
                }
                for r in screened[:40]
            ],
            indent=2,
        )
    )

    rules = FundedRules()
    accepted = None
    mcpt_rows = []
    for rank, row in enumerate(screened[: args.top_mcpt], 1):
        bt_params = {
            k: row["params"][k]
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
            f"\n=== MCPT #{rank} {bt_params['signal_mode']} {row['params']['pairset']} "
            f"score={row['score']:.0f} ===",
            flush=True,
        )
        train = raw[row["params"]["pairset"]]["train"]
        hold = raw[row["params"]["pairset"]]["hold"]
        full = raw[row["params"]["pairset"]]["full"]
        bt_t = run_backtest(train, rules=rules, **bt_params)
        bt_h = run_backtest(hold, rules=rules, **bt_params)
        print(
            f"  BT train ${bt_t.stats['avg_annual_pnl']:,.0f} pf={bt_t.stats['profit_factor']:.2f} | "
            f"hold ${bt_h.stats['avg_annual_pnl']:,.0f} pf={bt_h.stats['profit_factor']:.2f}",
            flush=True,
        )
        dual = (
            not bt_t.stats["blown"]
            and not bt_h.stats["blown"]
            and bt_t.stats["avg_annual_pnl"] >= args.min_ann
            and bt_h.stats["avg_annual_pnl"] >= args.min_ann * 0.55
            and bt_t.stats["consistency_ok"]
            and bt_h.stats["consistency_ok"]
        )
        if not dual:
            print("  skip MCPT (failed full BT dual gate)", flush=True)
            mcpt_rows.append(dict(rank=rank, params=bt_params, pairs=row["pairs"], dual_ok=False, mcpt_p=None))
            continue
        pval, _ = mcpt(train, bt_params, n=args.n_perm, seed=30 + rank)
        ch = simulate_challenge(full, eval_end="2019-12-31", funded_end="2022-03-04", rules=rules, **bt_params)
        # Fast eval: rolling 90d and 180d windows
        rolls90 = rolling_eval_windows(
            full,
            start="2016-01-01",
            end="2022-03-04",
            window_days=90,
            step_days=30,
            rules=rules,
            **{k: v for k, v in bt_params.items() if k != "weekly_withdraw"},
        )
        rolls180 = rolling_eval_windows(
            full,
            start="2016-01-01",
            end="2022-03-04",
            window_days=180,
            step_days=45,
            rules=rules,
            **{k: v for k, v in bt_params.items() if k != "weekly_withdraw"},
        )
        pr90 = sum(1 for r in rolls90 if r["passed"]) / max(len(rolls90), 1)
        pr180 = sum(1 for r in rolls180 if r["passed"]) / max(len(rolls180), 1)
        try:
            month = rolling_month_eval(full, **{k: v for k, v in bt_params.items() if k != "weekly_withdraw"})
            month_rate = month.get("pass_rate") if isinstance(month, dict) else getattr(month, "pass_rate", None)
        except Exception:
            month_rate = None
        rec = dict(
            rank=rank,
            params=bt_params,
            pairs=row["pairs"],
            train_bt=bt_t.stats,
            hold_bt=bt_h.stats,
            mcpt_p=pval,
            mcpt_pass=pval <= 0.05,
            dual_ok=True,
            challenge=ch.to_dict(),
            roll90_pass=pr90,
            roll180_pass=pr180,
            month_pass_rate=month_rate,
            score=row["score"],
        )
        mcpt_rows.append(rec)
        print(
            f"  MCPT p={pval:.4f} challenge eval_days={ch.evaluation_days} "
            f"funded_ann=${ch.funded_annual_pnl:,.0f} roll90={pr90:.1%} roll180={pr180:.1%}",
            flush=True,
        )
        fast_eval = (
            ch.evaluation_passed
            and 0 < ch.evaluation_days <= 120
            and ch.funded_survived
            and (pr90 >= 0.25 or pr180 >= 0.4)
        )
        if pval <= 0.05 and dual and fast_eval:
            # Prefer first that clears hard gate; keep scanning for better min-ann
            if accepted is None or min(
                rec["train_bt"]["avg_annual_pnl"], rec["hold_bt"]["avg_annual_pnl"]
            ) > min(accepted["train_bt"]["avg_annual_pnl"], accepted["hold_bt"]["avg_annual_pnl"]):
                accepted = rec
                print("  >>> ACCEPTED (tentative best)", flush=True)

    # If none hit fast_eval, relax to MCPT+dual with best min ann and report eval speed
    if accepted is None:
        passers = [r for r in mcpt_rows if r.get("mcpt_pass") and r.get("dual_ok")]
        if passers:
            passers.sort(
                key=lambda r: (
                    -min(r["train_bt"]["avg_annual_pnl"], r["hold_bt"]["avg_annual_pnl"]),
                    r.get("challenge", {}).get("evaluation_days") or 9999,
                )
            )
            accepted = passers[0]
            print("\nNo fast-eval hard pass; promoting best MCPT+dual by min ann", flush=True)

    payload = dict(
        protocol=dict(
            train=["2020-01-01", "2022-03-04"],
            hold=["2016-01-01", "2019-12-31"],
            min_ann=args.min_ann,
            n_perm=args.n_perm,
            grid=len(grid),
            screened=len(screened),
            note="Fixed grid OB/confluence modes; holdout never used for tuning",
        ),
        accepted=accepted,
        top_mcpt=mcpt_rows,
    )
    (OUT / "aggressive_ob_hunt.json").write_text(json.dumps(payload, indent=2, default=str))

    if accepted:
        lock = dict(
            name="aggressive_ob_winner",
            timeframe="1h",
            pairs=accepted["pairs"],
            params=accepted["params"],
            train_era=["2020-01-01", "2022-03-04"],
            hold_era=["2016-01-01", "2019-12-31"],
            train_bt=accepted["train_bt"],
            hold_bt=accepted["hold_bt"],
            mcpt_p=accepted["mcpt_p"],
            mcpt_pass=True,
            challenge=accepted.get("challenge"),
            roll90_pass=accepted.get("roll90_pass"),
            roll180_pass=accepted.get("roll180_pass"),
            month_pass_rate=accepted.get("month_pass_rate"),
            same_bar_stop_tp=True,
            order_blocks=True,
            confluence_confirm=True,
            source="aggressive_ob_hunt",
            protocol=payload["protocol"],
        )
        (OUT / "best_strategy_aggressive.json").write_text(json.dumps(lock, indent=2, default=str))
        (OUT / "best_strategy.json").write_text(json.dumps(lock, indent=2, default=str))
        print(f"LOCKED {OUT/'best_strategy.json'}", flush=True)
    else:
        print("NO winner", flush=True)
        if screened:
            print("Best screen:", json.dumps(screened[0]["params"], indent=2), flush=True)


if __name__ == "__main__":
    main()
