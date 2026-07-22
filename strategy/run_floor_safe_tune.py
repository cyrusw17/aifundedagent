#!/usr/bin/env python3
"""Retune ANN10 strategies to be The5ers prop-floor safe (causal).

Rules enforced:
- static max loss $6,000 (equity never <= $94,000)
- daily loss pause $3,000
- soft dd_halt before floor
- prefer max_dd <= $6,000

Searches risk / hold / dd_halt / trade caps for each ANN10 family.
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict, replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period
from strategy.config import DEV_PERIOD, HOLD_2026, PARAMS, PROP, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import FULL_2020_2025, TEST_LATE, TRAIN_EARLY, pd_years, pf
from strategy.strategies.ann10_winners import ANN10_H1, ANN10_ICT
from strategy.strategies.h1_models import H1Cfg, make_fn as make_h1
from strategy.strategies.kb_models import Cfg, make_fn as make_ict


def run_prop(universe, fn, period, *, risk_pct, max_hold_days, dd_halt, flatten_hour=22, move_to_be=False):
    params = replace(
        PARAMS,
        risk_pct=risk_pct,
        max_hold_days=max_hold_days,
        dd_halt=dd_halt,
        flatten_hour_utc=flatten_hour,
        move_to_be=move_to_be,
        daily_profit_cap=2_500.0,  # stay under consistency / daily blow-up
        max_trades_per_day=3,
        max_trades_per_pair_day=1,
        max_open_positions=1,
        cooldown_bars_after_trade=1,
    )
    # Real The5ers prop rules (floor + daily)
    r = run_period(
        universe,
        period[0],
        period[1],
        fn,
        "prop",
        prop=PROP,
        params=params,
        stop_at_profit_target=False,
        weekly_withdraw=False,
    )
    years = pd_years(period[0], period[1])
    profit = round(r.profit, 2)
    min_eq = float(r.equity_curve.min()) if len(r.equity_curve) else PROP.initial_balance
    floor = PROP.initial_balance - PROP.max_loss
    return {
        "profit": profit,
        "pf": pf(r.trades_df),
        "trades": r.trades,
        "wr": round(r.win_rate, 4),
        "max_dd": round(r.max_dd, 2),
        "min_equity": round(min_eq, 2),
        "floor_ok": min_eq > floor and r.fail_reason != "max_loss",
        "dd_ok": r.max_dd <= PROP.max_loss + 1e-6,
        "fail_reason": r.fail_reason,
        "simple_ann_pct": round((profit / PROP.initial_balance) / years * 100, 2) if years else 0.0,
        "cagr_pct": round(((1 + profit / PROP.initial_balance) ** (1 / years) - 1) * 100, 2)
        if years and profit > -PROP.initial_balance
        else float("nan"),
        "risk_pct": risk_pct,
        "max_hold_days": max_hold_days,
        "dd_halt": dd_halt,
    }


def score(row) -> tuple:
    # Prefer floor-safe, then dd-safe, then profit, then PF
    return (
        int(row["floor_ok"]),
        int(row["dd_ok"]),
        row["profit"],
        row["pf"],
    )


def tune_h1(universe, base: H1Cfg, name: str):
    print(f"\n=== Tune {name} ===", flush=True)
    best = None
    tested = []
    for risk in (0.0020, 0.0025, 0.0030, 0.0035, 0.0040):
        for hold in (0, 1, 3):  # 0 = day-trader flatten
            for halt in (4500.0, 5000.0):
                cfg = replace(base, risk_pct=risk, max_hold_days=hold, tag=f"{name}_r{risk}_h{hold}")
                fn = make_h1(cfg)
                # Screen on full period first (hardest for floor)
                full = run_prop(
                    universe, fn, FULL_2020_2025, risk_pct=risk, max_hold_days=hold, dd_halt=halt
                )
                tested.append({"name": name, "cfg": asdict(cfg), **full})
                if full["floor_ok"] and full["dd_ok"] and full["profit"] > 0:
                    print(
                        f"  CAND {name} risk={risk} hold={hold} halt={halt} "
                        f"ann={full['simple_ann_pct']}% dd={full['max_dd']} pf={full['pf']}",
                        flush=True,
                    )
                    if best is None or score(full) > score(best["full"]):
                        best = {"name": name, "cfg": cfg, "halt": halt, "full": full}
    # If none fully dd_ok, take best floor_ok with lowest max_dd
    if best is None:
        floor_ok = [t for t in tested if t["floor_ok"] and t["profit"] > 0]
        floor_ok.sort(key=lambda t: (t["max_dd"], -t["profit"]))
        if floor_ok:
            t = floor_ok[0]
            print(f"  FALLBACK floor_ok dd={t['max_dd']} ann={t['simple_ann_pct']}%", flush=True)
            cfg = H1Cfg(**{k: v for k, v in t["cfg"].items()})
            best = {
                "name": name,
                "cfg": cfg,
                "halt": t["dd_halt"],
                "full": {k: t[k] for k in (
                    "profit", "pf", "trades", "wr", "max_dd", "min_equity", "floor_ok",
                    "dd_ok", "fail_reason", "simple_ann_pct", "cagr_pct", "risk_pct",
                    "max_hold_days", "dd_halt",
                )},
            }
    return best, tested


def tune_ict(universe, base: Cfg, name: str):
    print(f"\n=== Tune {name} ===", flush=True)
    best = None
    tested = []
    for risk in (0.0025, 0.0030, 0.0035, 0.0040, 0.0050):
        for body in (0.22, 0.35):
            for halt in (4500.0, 5000.0):
                cfg = replace(base, risk_pct=risk, min_body_atr=body, tag=f"{name}_r{risk}_b{body}")
                fn = make_ict(cfg)
                full = run_prop(
                    universe, fn, FULL_2020_2025, risk_pct=risk, max_hold_days=0, dd_halt=halt,
                    flatten_hour=22, move_to_be=False,
                )
                tested.append({"name": name, "cfg": {k: (list(v) if k == "sb_windows" else v) for k, v in asdict(cfg).items()}, **full})
                if full["floor_ok"] and full["dd_ok"] and full["profit"] > 0:
                    print(
                        f"  CAND {name} risk={risk} body={body} halt={halt} "
                        f"ann={full['simple_ann_pct']}% dd={full['max_dd']} pf={full['pf']}",
                        flush=True,
                    )
                    if best is None or score(full) > score(best["full"]):
                        best = {"name": name, "cfg": cfg, "halt": halt, "full": full}
    if best is None:
        floor_ok = [t for t in tested if t["floor_ok"] and t["profit"] > 0]
        floor_ok.sort(key=lambda t: (t["max_dd"], -t["profit"]))
        if floor_ok:
            t = floor_ok[0]
            print(f"  FALLBACK floor_ok dd={t['max_dd']} ann={t['simple_ann_pct']}%", flush=True)
            raw = t["cfg"]
            cfg = Cfg(
                tag=raw["tag"], model=raw["model"], rr=raw["rr"], min_body_atr=raw["min_body_atr"],
                min_fvg_atr=raw["min_fvg_atr"], strict_bias=raw["strict_bias"], use_pdh=raw["use_pdh"],
                use_asia=raw["use_asia"], move_to_be=raw["move_to_be"], risk_pct=raw["risk_pct"],
                flatten_hour_utc=raw["flatten_hour_utc"],
                sb_windows=tuple(tuple(x) for x in raw["sb_windows"]),
            )
            best = {
                "name": name,
                "cfg": cfg,
                "halt": t["dd_halt"],
                "full": {k: t[k] for k in (
                    "profit", "pf", "trades", "wr", "max_dd", "min_equity", "floor_ok",
                    "dd_ok", "fail_reason", "simple_ann_pct", "cagr_pct", "risk_pct",
                    "max_hold_days", "dd_halt",
                )},
            }
    return best, tested


def validate(universe, best, kind: str):
    cfg, halt = best["cfg"], best["halt"]
    if kind == "h1":
        fn = make_h1(cfg)
        hold = cfg.max_hold_days
        risk = cfg.risk_pct
    else:
        fn = make_ict(cfg)
        hold = 0
        risk = cfg.risk_pct
    out = {}
    for label, period in [
        ("full", FULL_2020_2025),
        ("early", TRAIN_EARLY),
        ("late", TEST_LATE),
        ("dev", DEV_PERIOD),
        ("hold2026", HOLD_2026),
    ]:
        out[label] = run_prop(
            universe, fn, period, risk_pct=risk, max_hold_days=hold, dd_halt=halt,
            flatten_hour=getattr(cfg, "flatten_hour_utc", 22), move_to_be=False,
        )
        print(
            f"  {best['name']} {label}: floor_ok={out[label]['floor_ok']} dd_ok={out[label]['dd_ok']} "
            f"dd={out[label]['max_dd']} ann={out[label]['simple_ann_pct']}% pf={out[label]['pf']} "
            f"fail={out[label]['fail_reason']}",
            flush=True,
        )
    return out


def main() -> int:
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    print("Loading universe...", flush=True)
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")

    winners = []
    # Keep identity of A1-A5 bases
    h1_bases = [
        ("A1_H1Don_n35_rr5", ANN10_H1["A1_H1Don_n35_rr5"]),
        ("A2_H1Don_n30_rr4", ANN10_H1["A2_H1Don_n30_rr4"]),
        ("A3_H1Don_n40_rr4", ANN10_H1["A3_H1Don_n40_rr4"]),
    ]
    ict_bases = [
        ("A4_ICT_MSB_PA", ANN10_ICT["A4_ICT_MSB_PA"]),
        ("A5_ICT_MSB_ASIA", ANN10_ICT["A5_ICT_MSB_ASIA"]),
    ]

    for name, base in h1_bases:
        best, _ = tune_h1(universe, base, name)
        if not best:
            print(f"FAILED to find floor-safe {name}", flush=True)
            continue
        print(f"Validate {name}...", flush=True)
        periods = validate(universe, best, "h1")
        winners.append({"name": name, "kind": "h1", "cfg": asdict(best["cfg"]), "halt": best["halt"], "periods": periods})

    for name, base in ict_bases:
        best, _ = tune_ict(universe, base, name)
        if not best:
            print(f"FAILED to find floor-safe {name}", flush=True)
            continue
        print(f"Validate {name}...", flush=True)
        periods = validate(universe, best, "ict")
        cfg_d = {k: (list(v) if k == "sb_windows" else v) for k, v in asdict(best["cfg"]).items()}
        winners.append({"name": name, "kind": "ict", "cfg": cfg_d, "halt": best["halt"], "periods": periods})

    (out_dir / "floor_safe_tune.json").write_text(json.dumps({"winners": winners}, indent=2, default=str))

    lines = [
        "# Prop-floor-safe ANN10 retune (causal)",
        "",
        "The5ers rules: static floor **$6,000**, daily loss **$3,000**, soft `dd_halt`.",
        "Fills still only after `knowable_at`.",
        "",
        "| ID | Floor OK (full) | DD OK | Max DD | Full ann | Risk | Hold | Halt |",
        "|----|-----------------|-------|--------|----------|------|------|------|",
    ]
    all_floor = True
    for w in winners:
        f = w["periods"]["full"]
        all_floor = all_floor and f["floor_ok"]
        lines.append(
            f"| **{w['name']}** | {f['floor_ok']} | {f['dd_ok']} | ${f['max_dd']:,.0f} | "
            f"{f['simple_ann_pct']}% | {w['cfg']['risk_pct']*100:.2f}% | "
            f"{w['cfg'].get('max_hold_days', 0)} | ${w['halt']:,.0f} |"
        )
    lines += [
        "",
        "## Period checks",
        "",
    ]
    for w in winners:
        lines.append(f"### {w['name']}")
        for label in ("full", "early", "late", "dev", "hold2026"):
            p = w["periods"][label]
            lines.append(
                f"- {label}: floor_ok={p['floor_ok']} dd_ok={p['dd_ok']} dd=${p['max_dd']:,.0f} "
                f"ann={p['simple_ann_pct']}% pf={p['pf']} trades={p['trades']}"
            )
        lines.append("")
    lines += [
        "## Verdict",
        "",
        "All five floor-safe on full sample." if all_floor and len(winners) == 5
        else f"Floor-safe set size: {len(winners)}; all_floor={all_floor}.",
        "Annual returns drop vs unconstrained ANN10 because risk is cut to respect the $6k floor.",
        "",
    ]
    (out_dir / "FLOOR_SAFE.md").write_text("\n".join(lines) + "\n")
    print("\nWrote FLOOR_SAFE.md", flush=True)
    print("ALL FLOOR SAFE" if all_floor and len(winners) == 5 else "PARTIAL", flush=True)
    return 0 if all_floor and len(winners) == 5 else 1


if __name__ == "__main__":
    raise SystemExit(main())
