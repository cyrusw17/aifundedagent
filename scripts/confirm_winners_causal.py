#!/usr/bin/env python3
"""Confirm the five KB winners under strict no-lookahead fills.

1. RuntimeError if any fill before signal.knowable_at
2. Edge PF >= 1.05 and profit > 0 on DEV, 2023, and 2026 H1
"""
from __future__ import annotations

import sys
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period
from strategy.config import DEV_PERIOD, HOLD_2026, PARAMS, PROP, PURE_OOS
from strategy.data_loader import load_universe
from strategy.strategies.kb_models import Cfg
from strategy.strategies.winners import STRATEGIES, WINNER_CFGS


def pf(df) -> float:
    if df is None or df.empty:
        return 0.0
    g = float(df.loc[df.pnl > 0, "pnl"].sum())
    l = float(-df.loc[df.pnl < 0, "pnl"].sum())
    return round(g / l, 3) if l > 1e-9 else (99.0 if g > 0 else 0.0)


def params_for(cfg: Cfg):
    return replace(
        PARAMS,
        risk_pct=cfg.risk_pct,
        flatten_hour_utc=cfg.flatten_hour_utc,
        move_to_be=cfg.move_to_be,
        daily_profit_cap=1e9,
        max_trades_per_day=12,
    )


def edge(universe, fn, period, cfg):
    prop = replace(PROP, profit_target=1e9, consistency_pct=1.0, max_loss=1e9, daily_loss_limit=1e9)
    r = run_period(
        universe,
        period[0],
        period[1],
        fn,
        "e",
        prop=prop,
        params=params_for(cfg),
        stop_at_profit_target=False,
    )
    return {
        "profit": round(r.profit, 2),
        "pf": pf(r.trades_df),
        "trades": r.trades,
        "wr": round(r.win_rate, 4),
    }


def main() -> int:
    print("=== Confirm five winners (causal / no look-ahead) ===\n")
    # Same universe as KB search (PARAMS.pairs)
    universe = load_universe(PARAMS.pairs)
    periods = {
        "DEV": DEV_PERIOD,
        "VAL_2023": PURE_OOS,
        "VAL_2026H1": HOLD_2026,
    }
    failed: list[str] = []

    for name, cfg in WINNER_CFGS.items():
        fn = STRATEGIES[name]
        print(f"--- {name}: {cfg.model} rr={cfg.rr} risk={cfg.risk_pct} ---")
        p = params_for(cfg)
        n_sigs = 0
        bad_k = 0
        for pair, frames in universe.items():
            sigs = fn(pair, frames["m15"], p)
            n_sigs += len(sigs)
            bad_k += sum(1 for s in sigs if s.knowable_at is None)
        if bad_k:
            print(f"  FAIL: {bad_k} signals missing knowable_at")
            failed.append(name)
            continue
        print(f"  signals={n_sigs}  knowable_at=OK")

        ok = True
        for label, period in periods.items():
            try:
                e = edge(universe, fn, period, cfg)
            except RuntimeError as exc:
                print(f"  {label}: LOOKAHEAD RuntimeError: {exc}")
                failed.append(name)
                ok = False
                break
            pass_edge = e["pf"] >= 1.05 and e["profit"] > 0
            mark = "PASS" if pass_edge else "FAIL"
            print(
                f"  {label}: {mark}  trades={e['trades']}  PF={e['pf']:.3f}  "
                f"pnl=${e['profit']:,.0f}"
            )
            if not pass_edge:
                ok = False
                failed.append(name)
        if ok:
            print(f"  >>> {name} CONFIRMED WINNER (causal)\n")
        else:
            print(f"  >>> {name} did not confirm\n")

    # Spot-check: every filled trade for W1 starts at/after knowable_at
    print("--- Fill-time vs knowable_at spot-check (W1 DEV sample) ---")
    import pandas as pd

    from strategy.backtest import _simulate_limit_entry_and_exit

    w1_name = next(iter(WINNER_CFGS))
    w1_cfg = WINNER_CFGS[w1_name]
    w1_fn = STRATEGIES[w1_name]
    m15 = universe["EURUSD"]["m15"]
    m1 = universe["EURUSD"]["m1"]
    p = params_for(w1_cfg)
    sample = [s for s in w1_fn("EURUSD", m15, p) if "2024-01-01" <= str(s.time)[:10] <= "2024-06-30"]
    violations = 0
    checked = 0
    for s in sample:
        out = _simulate_limit_entry_and_exit(m1, s, p)
        if out is None:
            continue
        checked += 1
        if out[0] < s.knowable_at:
            print(f"  VIOLATION entry={out[0]} knowable={s.knowable_at}")
            violations += 1
    if violations:
        print(f"  FAIL: {violations} look-ahead fills")
        failed.append("FILL_CHECK")
    else:
        print(f"  OK: {checked} fills, zero before knowable_at")

    print()
    if failed:
        print(f"FAILED: {sorted(set(failed))}")
        return 1
    print("ALL FIVE WINNERS CONFIRMED UNDER NO-LOOKAHEAD FILLS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
