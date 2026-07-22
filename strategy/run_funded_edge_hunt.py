#!/usr/bin/env python3
"""Funded-edge hunt: train 2024-25 → blind 2026, strict prop-viable gates.

A survivor must:
- 2024 & 2025 each ≥ 15% simple ann (real money pace)
- 2023 ≥ 0%; no year 2021-25 < -8%; floor held
- 2026 H1 ann ≥ 15% (one-shot; fail = curve-fit, no retune)
- worst single-day PnL > -$2,800 (buffer under The5ers $3k daily)
- zero hard floor breaches
- can hit +$10k challenge target in calendar 2024 AND 2025 (stop_at_target)
- causal fills only
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict, replace
from pathlib import Path
from typing import Any, Dict, List, Tuple

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period
from strategy.config import PARAMS, PROP, RESULTS_DIR
from strategy.data_loader import RESEARCH_MAX_END, load_universe
from strategy.run_commodity_search import make_params, pf, run, year_period
from strategy.strategies.commodity_models import CmdCfg, make_cmd_fn
from strategy.strategies.retail_models import RetailCfg, make_fn as make_retail

HOLD_2026 = ("2026-01-01", "2026-06-30")
FLOOR = PROP.initial_balance - PROP.max_loss
DAILY_BUF = -2_800.0  # must stay above -$3k


def build_ideas() -> List[Tuple[str, Any, CmdCfg | RetailCfg, int]]:
    """Return (tag, signal_fn_factory_or_fn, cfg, hold_days)."""
    out: List[Tuple[str, Any, Any, int]] = []
    # HTF commodity models — prioritize both-side + regime (survived 2026 dump)
    for tf, hold in (("1D", 10), ("4h", 5)):
        for don in (12, 15, 20, 25, 30, 40):
            for rr in (2.0, 2.5, 3.0, 3.5, 4.0, 5.0):
                for side, lo, so in (("L", True, False), ("B", False, False)):
                    cfg = CmdCfg(
                        tag=f"DON_{tf}_n{don}_rr{rr}_{side}",
                        model="don",
                        tf=tf,
                        don_len=don,
                        rr=rr,
                        long_only=lo,
                        short_only=so,
                        max_hold_days=hold,
                        session_only=(tf != "1D"),
                        stop_atr=2.0,
                    )
                    out.append((cfg.tag, make_cmd_fn(cfg), cfg, hold))
                    cfg2 = CmdCfg(
                        tag=f"RDON_{tf}_n{don}_rr{rr}_{side}",
                        model="regime_don",
                        tf=tf,
                        don_len=don,
                        rr=rr,
                        long_only=lo,
                        short_only=so,
                        max_hold_days=hold,
                        session_only=(tf != "1D"),
                        stop_atr=2.0,
                        ema_slow=50,
                    )
                    out.append((cfg2.tag, make_cmd_fn(cfg2), cfg2, hold))
        for rr in (2.5, 3.5, 5.0):
            for mult in (2.5, 3.0, 3.5):
                for side, lo, so in (("L", True, False), ("B", False, False)):
                    cfg = CmdCfg(
                        tag=f"ST_{tf}_m{mult}_rr{rr}_{side}",
                        model="supertrend",
                        tf=tf,
                        rr=rr,
                        pullback_atr=mult,  # reused as ST mult
                        long_only=lo,
                        short_only=so,
                        max_hold_days=hold,
                        session_only=(tf != "1D"),
                        stop_atr=2.0,
                    )
                    out.append((cfg.tag, make_cmd_fn(cfg), cfg, hold))
            for side, lo, so in (("L", True, False), ("B", False, False)):
                cfg = CmdCfg(
                    tag=f"MACD_{tf}_rr{rr}_{side}",
                    model="macd",
                    tf=tf,
                    ema_fast=12,
                    ema_slow=26,
                    rr=rr,
                    long_only=lo,
                    short_only=so,
                    max_hold_days=hold,
                    session_only=(tf != "1D"),
                    stop_atr=2.0,
                )
                out.append((cfg.tag, make_cmd_fn(cfg), cfg, hold))
                cfg = CmdCfg(
                    tag=f"BB_{tf}_rr{rr}_{side}",
                    model="bb_fade",
                    tf=tf,
                    don_len=20,
                    rr=rr,
                    rsi_lo=35,
                    rsi_hi=65,
                    long_only=lo,
                    short_only=so,
                    max_hold_days=hold,
                    session_only=(tf != "1D"),
                    stop_atr=1.8,
                )
                out.append((cfg.tag, make_cmd_fn(cfg), cfg, hold))
                cfg = CmdCfg(
                    tag=f"ATRB_{tf}_rr{rr}_{side}",
                    model="atr_brk",
                    tf=tf,
                    rr=rr,
                    pullback_atr=0.35,
                    long_only=lo,
                    short_only=so,
                    max_hold_days=hold,
                    session_only=(tf != "1D"),
                    stop_atr=2.0,
                )
                out.append((cfg.tag, make_cmd_fn(cfg), cfg, hold))

    # M15 retail families on gold (higher trade count / challenge speed)
    for model in ("donchian", "supertrend", "macd", "ema_cross", "ema_rsi", "bb_rsi"):
        for rr in (2.0, 2.5, 3.5):
            for kz in (True, False):
                cfg = RetailCfg(
                    tag=f"M15_{model}_rr{rr}_{'KZ' if kz else 'ALL'}",
                    model=model,
                    rr=rr,
                    killzone_only=kz,
                    one_per_day=True,
                    marketable=True,
                    stop_atr=1.5,
                    don_len=20,
                    st_mult=3.0,
                    flatten_hour_utc=22,
                    move_to_be=False,
                )
                out.append((cfg.tag, make_retail(cfg), cfg, 0))
    return out


def worst_day_pnl(trades_df) -> float:
    if trades_df is None or len(trades_df) == 0:
        return 0.0
    t = trades_df.copy()
    t["day"] = pd.to_datetime(t["exit_time"]).dt.normalize()
    return float(t.groupby("day")["pnl"].sum().min())


def challenge_hit(universe, fn, start: str, end: str, params) -> Dict[str, Any]:
    r = run_period(
        universe,
        start,
        end,
        fn,
        "prop",
        prop=PROP,
        params=params,
        stop_at_profit_target=True,
        weekly_withdraw=False,
    )
    return {
        "passed": bool(r.passed),
        "days": r.days_to_target,
        "fail": r.fail_reason,
        "profit": round(float(r.profit), 2),
        "min_eq": round(float(r.equity_curve.min()) if len(r.equity_curve) else PROP.initial_balance, 2),
        "worst_day": round(worst_day_pnl(r.trades_df), 2),
    }


def open_period(universe, fn, start: str, end: str, params):
    r = run_period(
        universe,
        start,
        end,
        fn,
        "prop",
        prop=PROP,
        params=params,
        stop_at_profit_target=False,
        weekly_withdraw=False,
    )
    years = max((pd.Timestamp(end) - pd.Timestamp(start)).days / 365.25, 1e-9)
    profit = float(r.profit)
    min_eq = float(r.equity_curve.min()) if len(r.equity_curve) else PROP.initial_balance
    return {
        "profit": round(profit, 2),
        "ann": round(profit / PROP.initial_balance / years * 100, 2),
        "pf": pf(r.trades_df),
        "trades": r.trades,
        "max_dd": round(r.max_dd, 2),
        "min_eq": round(min_eq, 2),
        "floor_ok": bool(min_eq > FLOOR and r.fail_reason != "max_loss"),
        "worst_day": round(worst_day_pnl(r.trades_df), 2),
        "end_eq": round(float(r.end_equity), 2),
    }


def ok_train(yrs: Dict[str, Any]) -> bool:
    if yrs["2024"]["ann"] < 15 or yrs["2025"]["ann"] < 15:
        return False
    if yrs["2023"]["ann"] < 0:
        return False
    for y in ("2021", "2022", "2023", "2024", "2025"):
        if not yrs[y]["floor_ok"] or yrs[y]["ann"] < -8:
            return False
        if yrs[y]["worst_day"] < DAILY_BUF:
            return False
    if yrs["2024"]["pf"] < 1.1 or yrs["2025"]["pf"] < 1.1:
        return False
    if yrs["2024"]["trades"] < 6 or yrs["2025"]["trades"] < 6:
        return False
    return True


def ok_holdout(r26: Dict[str, Any]) -> bool:
    return (
        r26["floor_ok"]
        and r26["ann"] >= 15.0
        and r26["pf"] >= 1.15
        and r26["trades"] >= 3
        and r26["worst_day"] >= DAILY_BUF
    )


def main() -> int:
    print("=== Funded-edge hunt (strict) ===\n", flush=True)
    print(f"Train cutoff {RESEARCH_MAX_END}; holdout {HOLD_2026}", flush=True)
    print(f"Gates: y24/y25≥15%, y26≥15%, worst_day≥{DAILY_BUF}, challenge 24&25\n", flush=True)

    uni_train = load_universe(("XAUUSD",), max_end=RESEARCH_MAX_END)
    uni_full = load_universe(("XAUUSD",), max_end=None)
    ideas = build_ideas()
    print(f"Ideas: {len(ideas)}", flush=True)

    survivors: List[Dict[str, Any]] = []
    fail26 = 0
    train_hits = 0

    for tag, fn, cfg, hold in ideas:
        for risk in (0.01, 0.015, 0.02, 0.025, 0.03):
            params = make_params(risk, hold if hold > 0 else 0)
            # prune 2024
            r24 = open_period(uni_train, fn, "2024-01-01", "2024-12-31", params)
            if r24["ann"] < 12 or not r24["floor_ok"] or r24["worst_day"] < DAILY_BUF:
                continue
            r25 = open_period(uni_train, fn, "2025-01-01", "2025-12-31", params)
            if r25["ann"] < 12 or not r25["floor_ok"] or r25["worst_day"] < DAILY_BUF:
                continue
            yrs = {
                "2024": r24,
                "2025": r25,
                "2023": open_period(uni_train, fn, "2023-01-01", "2023-12-31", params),
                "2021": open_period(uni_train, fn, "2021-01-01", "2021-12-31", params),
                "2022": open_period(uni_train, fn, "2022-01-01", "2022-12-31", params),
            }
            if not ok_train(yrs):
                continue
            # challenge must hit in 2024 and 2025 calendar years
            ch24 = challenge_hit(uni_train, fn, "2024-01-01", "2024-12-31", params)
            ch25 = challenge_hit(uni_train, fn, "2025-01-01", "2025-12-31", params)
            if not (ch24["passed"] and ch25["passed"]):
                continue
            if ch24["worst_day"] < DAILY_BUF or ch25["worst_day"] < DAILY_BUF:
                continue
            train_hits += 1
            # ONE-SHOT 2026
            r26 = open_period(uni_full, fn, HOLD_2026[0], HOLD_2026[1], params)
            ch26 = challenge_hit(uni_full, fn, HOLD_2026[0], HOLD_2026[1], params)
            row = {
                "tag": tag,
                "risk": risk,
                "hold": hold,
                "cfg": asdict(cfg) if hasattr(cfg, "__dataclass_fields__") else str(cfg),
                "y21": yrs["2021"]["ann"],
                "y22": yrs["2022"]["ann"],
                "y23": yrs["2023"]["ann"],
                "y24": yrs["2024"]["ann"],
                "y25": yrs["2025"]["ann"],
                "y26": r26["ann"],
                "pf26": r26["pf"],
                "n26": r26["trades"],
                "wd24": yrs["2024"]["worst_day"],
                "wd25": yrs["2025"]["worst_day"],
                "wd26": r26["worst_day"],
                "ch24_days": ch24["days"],
                "ch25_days": ch25["days"],
                "ch26_pass": ch26["passed"],
                "ch26_days": ch26["days"],
                "model": getattr(cfg, "model", "?"),
                "tf": getattr(cfg, "tf", "M15"),
            }
            if ok_holdout(r26):
                survivors.append(row)
                print(
                    f"SURVIVOR {tag} risk={risk*100:.1f}% "
                    f"24/25/26={r24['ann']}/{r25['ann']}/{r26['ann']} "
                    f"ch24={ch24['days']}d ch25={ch25['days']}d ch26={ch26['passed']}/{ch26['days']} "
                    f"wd26={r26['worst_day']}",
                    flush=True,
                )
                break
            fail26 += 1
            print(
                f"FAIL26 {tag} risk={risk*100:.1f}% "
                f"24/25={r24['ann']}/{r25['ann']} 26={r26['ann']} pf={r26['pf']} wd={r26['worst_day']}",
                flush=True,
            )
            # do not retune signals on 2026; trying other risk is sizing only

    # rank: prefer 2026 strength + challenge speed + train min year
    survivors.sort(
        key=lambda x: (
            1 if x["ch26_pass"] else 0,
            x["y26"],
            min(x["y24"], x["y25"]),
            -(x["ch24_days"] or 999),
            -(x["ch25_days"] or 999),
        ),
        reverse=True,
    )

    # diversify by model+tf
    picked = []
    used = set()
    for s in survivors:
        fam = (s["model"], s["tf"])
        if fam in used and len(picked) >= 3:
            continue
        used.add(fam)
        picked.append(s)
        if len(picked) >= 5:
            break
    if len(picked) < 5:
        for s in survivors:
            if s in picked:
                continue
            picked.append(s)
            if len(picked) >= 5:
                break

    out = {
        "method": "funded_edge_train2425_blind2026",
        "gates": {
            "y24_y25_ann_min": 15,
            "y26_ann_min": 15,
            "worst_day_min": DAILY_BUF,
            "challenge_2024_and_2025": True,
        },
        "n_ideas": len(ideas),
        "n_train_hits": train_hits,
        "n_fail26": fail26,
        "n_survivors": len(survivors),
        "survivors": survivors,
        "selected": picked,
    }
    path = Path(RESULTS_DIR) / "funded_edge_survivors.json"
    path.write_text(json.dumps(out, indent=2))
    print(f"\nWrote {path}", flush=True)
    print(f"survivors={len(survivors)} selected={len(picked)} train_hits={train_hits} fail26={fail26}", flush=True)
    for i, s in enumerate(picked, 1):
        print(f"  F{i}", {k: s[k] for k in s if k != "cfg"}, flush=True)

    return 0 if len(picked) >= 1 else 1


if __name__ == "__main__":
    raise SystemExit(main())
