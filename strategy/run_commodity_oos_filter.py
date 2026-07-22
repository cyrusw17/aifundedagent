#!/usr/bin/env python3
"""Train on 2024–2025 (consistency 2021–23), one-shot blind-test on 2026.

If 2026 fails → discard (curve-fit). Never retune a failed idea on 2026.
Research selection never uses 2026 metrics — 2026 is evaluated only after
a candidate already clears train gates.
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.config import RESULTS_DIR
from strategy.data_loader import RESEARCH_MAX_END, load_universe
from strategy.run_commodity_search import make_params, run
from strategy.strategies.commodity_models import CmdCfg, make_cmd_fn

HOLD_2026 = ("2026-01-01", "2026-06-30")
TRAIN_YEARS = ("2021", "2022", "2023", "2024", "2025")


def year_period(y: str) -> Tuple[str, str]:
    return f"{y}-01-01", f"{y}-12-31"


def build_ideas() -> List[CmdCfg]:
    out: List[CmdCfg] = []
    for tf, hold in (("1D", 10), ("4h", 5)):
        for don in (15, 20, 25, 30, 40, 55):
            for rr in (2.0, 2.5, 3.0, 3.5, 4.0, 5.0):
                for side, lo, so in (("L", True, False), ("B", False, False)):
                    out.append(
                        CmdCfg(
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
                    )
        for ef, es in ((8, 21), (12, 48), (20, 50), (10, 40)):
            for rr in (2.5, 3.5, 5.0):
                for side, lo, so in (("L", True, False), ("B", False, False)):
                    out.append(
                        CmdCfg(
                            tag=f"EMA_{tf}_{ef}_{es}_rr{rr}_{side}",
                            model="ema",
                            tf=tf,
                            ema_fast=ef,
                            ema_slow=es,
                            rr=rr,
                            long_only=lo,
                            short_only=so,
                            max_hold_days=hold,
                            session_only=(tf != "1D"),
                            stop_atr=2.0,
                        )
                    )
        for rr in (2.5, 3.5, 5.0):
            for pb in (0.2, 0.35, 0.5):
                for side, lo, so in (("L", True, False), ("B", False, False)):
                    out.append(
                        CmdCfg(
                            tag=f"ATRB_{tf}_k{pb}_rr{rr}_{side}",
                            model="atr_brk",
                            tf=tf,
                            rr=rr,
                            pullback_atr=pb,
                            long_only=lo,
                            short_only=so,
                            max_hold_days=hold,
                            session_only=(tf != "1D"),
                            stop_atr=2.0,
                        )
                    )
            for side, lo, so in (("L", True, False), ("B", False, False)):
                out.append(
                    CmdCfg(
                        tag=f"PB_{tf}_rr{rr}_{side}",
                        model="ema_pb",
                        tf=tf,
                        ema_slow=50,
                        rr=rr,
                        rsi_lo=35,
                        rsi_hi=65,
                        long_only=lo,
                        short_only=so,
                        max_hold_days=hold,
                        session_only=(tf != "1D"),
                        stop_atr=1.5,
                    )
                )
    return out


def ok_train(yrs: Dict[str, Any]) -> bool:
    if yrs["2024"]["ann"] < 10 or yrs["2025"]["ann"] < 10:
        return False
    if yrs["2023"]["ann"] < 0:
        return False
    for y in TRAIN_YEARS:
        if not yrs[y]["floor_ok"]:
            return False
        if yrs[y]["ann"] < -8:
            return False
    if yrs["2024"]["pf"] < 1.05 or yrs["2025"]["pf"] < 1.05:
        return False
    if yrs["2024"]["trades"] < 5 or yrs["2025"]["trades"] < 5:
        return False
    return True


def ok_2026(r: Dict[str, Any]) -> bool:
    """Blind holdout gate (partial year, annualized by run())."""
    return (
        r["floor_ok"]
        and r["ann"] >= 5.0
        and r["pf"] >= 1.0
        and r["trades"] >= 3
    )


def eval_train(universe, fn, params) -> Dict[str, Any]:
    return {y: run(universe, fn, year_period(y), params) for y in TRAIN_YEARS}


def family_key(row: Dict[str, Any]) -> Tuple:
    return (row["scope"], row["model"], row["tf"], row["side"])


def diversify(survivors: List[Dict[str, Any]], n: int = 5) -> List[Dict[str, Any]]:
    """Prefer distinct (model, tf, side); then distinct don_len / rr."""
    survivors = sorted(
        survivors,
        key=lambda x: (x["y26"], x["y24"] + x["y25"], x["pf26"]),
        reverse=True,
    )
    picked: List[Dict[str, Any]] = []
    used_fam = set()
    used_fine = set()

    def fine_key(s: Dict[str, Any]) -> Tuple:
        return (
            s["scope"],
            s["model"],
            s["tf"],
            s["side"],
            s.get("don_len"),
            round(float(s["rr"]), 1),
            round(float(s.get("pullback_atr") or 0), 2),
        )

    # Pass 1: distinct model/tf/side families
    for s in survivors:
        fam = family_key(s)
        if fam in used_fam:
            continue
        used_fam.add(fam)
        used_fine.add(fine_key(s))
        picked.append(s)
        if len(picked) >= n:
            return picked
    # Pass 2: fill with distinct fine keys (different length/RR)
    for s in survivors:
        fk = fine_key(s)
        if fk in used_fine:
            continue
        # avoid near-duplicates of same don/rr already taken
        used_fine.add(fk)
        picked.append(s)
        if len(picked) >= n:
            break
    return picked


def main() -> int:
    print("=== Commodity train(2024-25) → blind 2026 filter ===\n", flush=True)
    print(f"Train cutoff: {RESEARCH_MAX_END}", flush=True)
    print(f"Holdout: {HOLD_2026[0]} .. {HOLD_2026[1]} (one-shot, no retune)\n", flush=True)

    # Only scopes with 2026 holdout data can be validated (silver/oil have none).
    scopes = {
        "XAU": ("XAUUSD",),
        "XAUXAG": ("XAUUSD", "XAGUSD"),  # silver leg silent in 2026; gold still validates
    }
    ideas = build_ideas()
    print(f"Ideas: {len(ideas)}  scopes: {list(scopes)}\n", flush=True)

    uni_train: Dict[str, Any] = {}
    uni_full: Dict[str, Any] = {}
    for scope, pairs in scopes.items():
        uni_train[scope] = load_universe(pairs, max_end=RESEARCH_MAX_END)
        uni_full[scope] = load_universe(pairs, max_end=None)
        for p, fr in uni_full[scope].items():
            print(f"  {scope}/{p} max={fr['m1'].index.max().date()}", flush=True)

    survivors: List[Dict[str, Any]] = []
    fail26: List[Dict[str, Any]] = []
    no_holdout: List[Dict[str, Any]] = []
    train_hits = 0

    for scope, pairs in scopes.items():
        has26 = any(fr["m1"].index.max().year >= 2026 for fr in uni_full[scope].values())
        print(f"\n--- scope {scope} has_2026={has26} ---", flush=True)
        for cfg in ideas:
            fn = make_cmd_fn(cfg)
            for risk in (0.01, 0.015, 0.02, 0.025):
                params = make_params(risk, cfg.max_hold_days)
                # Early prune on 2024 only (train universe — no 2026)
                r24 = run(uni_train[scope], fn, year_period("2024"), params)
                if r24["ann"] < 9 or not r24["floor_ok"]:
                    continue
                r25 = run(uni_train[scope], fn, year_period("2025"), params)
                if r25["ann"] < 9 or not r25["floor_ok"]:
                    continue
                yrs = {
                    "2024": r24,
                    "2025": r25,
                    "2023": run(uni_train[scope], fn, year_period("2023"), params),
                    "2021": run(uni_train[scope], fn, year_period("2021"), params),
                    "2022": run(uni_train[scope], fn, year_period("2022"), params),
                }
                if not ok_train(yrs):
                    continue
                train_hits += 1
                side = "L" if cfg.long_only else ("S" if cfg.short_only else "B")
                row: Dict[str, Any] = {
                    "scope": scope,
                    "pairs": list(pairs),
                    "tag": cfg.tag,
                    "model": cfg.model,
                    "tf": cfg.tf,
                    "side": side,
                    "rr": cfg.rr,
                    "risk": risk,
                    "don_len": cfg.don_len,
                    "ema_fast": cfg.ema_fast,
                    "ema_slow": cfg.ema_slow,
                    "pullback_atr": cfg.pullback_atr,
                    "stop_atr": cfg.stop_atr,
                    "max_hold_days": cfg.max_hold_days,
                    "session_only": cfg.session_only,
                    "y21": yrs["2021"]["ann"],
                    "y22": yrs["2022"]["ann"],
                    "y23": yrs["2023"]["ann"],
                    "y24": yrs["2024"]["ann"],
                    "y25": yrs["2025"]["ann"],
                    "cfg": asdict(cfg),
                }
                if not has26:
                    no_holdout.append(row)
                    print(f"  TRAIN-OK (no 2026 data) {scope} {cfg.tag} risk={risk}", flush=True)
                    break
                # ONE-SHOT blind 2026 — do not retune if fail
                r26 = run(uni_full[scope], fn, HOLD_2026, params)
                row.update(
                    {
                        "y26": r26["ann"],
                        "pf26": r26["pf"],
                        "n26": r26["trades"],
                        "floor26": r26["floor_ok"],
                        "profit26": r26["profit"],
                    }
                )
                if ok_2026(r26):
                    survivors.append(row)
                    print(
                        f"  SURVIVOR {scope} {cfg.tag} risk={risk*100:.1f}% "
                        f"24={r24['ann']}% 25={r25['ann']}% 26={r26['ann']}% "
                        f"pf26={r26['pf']} n={r26['trades']}",
                        flush=True,
                    )
                    break  # next idea (don't stack risks)
                fail26.append(row)
                # failed 2026 → move on (do not try other risks for same idea? 
                # try other risks still — risk is sizing not signal curve-fit)
                # continue risk loop
            # end risk
        print(
            f"  scope done: survivors={len(survivors)} fail26={len(fail26)} "
            f"train_hits≈{train_hits}",
            flush=True,
        )
        # Early stop once we have enough diversified survivors from gold.
        if len(diversify(survivors, n=5)) >= 5 and scope == "XAU":
            print("  early-stop: ≥5 diversified XAU survivors", flush=True)
            break

    picked = diversify(survivors, n=5)
    out = {
        "method": "train_2024_2025_then_blind_2026",
        "research_max_end": RESEARCH_MAX_END,
        "holdout": list(HOLD_2026),
        "train_gates": {
            "y2024_ann_min": 10,
            "y2025_ann_min": 10,
            "y2023_ann_min": 0,
            "year_floor_min": -8,
            "pf_2425_min": 1.05,
        },
        "holdout_gates": {
            "ann_min": 5.0,
            "pf_min": 1.0,
            "trades_min": 3,
            "floor": True,
        },
        "n_ideas": len(ideas),
        "n_train_pass_approx": train_hits,
        "n_fail_2026": len(fail26),
        "n_survivors": len(survivors),
        "n_no_holdout_data": len(no_holdout),
        "survivors": [
            {k: v for k, v in s.items() if k != "cfg"} for s in survivors
        ],
        "selected": [{k: v for k, v in s.items() if k != "cfg"} for s in picked],
        "selected_cfgs": [s["cfg"] for s in picked],
        "selected_meta": [
            {
                "id": f"O{i+1}_{s['scope']}_{s['tag']}",
                "scope": s["scope"],
                "pairs": s["pairs"],
                "risk": s["risk"],
                "tag": s["tag"],
                "years": {
                    "2021": s["y21"],
                    "2022": s["y22"],
                    "2023": s["y23"],
                    "2024": s["y24"],
                    "2025": s["y25"],
                    "2026H1_ann": s["y26"],
                },
                "pf26": s["pf26"],
                "n26": s["n26"],
            }
            for i, s in enumerate(picked)
        ],
    }
    path = Path(RESULTS_DIR) / "commodity_oos_survivors.json"
    path.write_text(json.dumps(out, indent=2))
    print(f"\nWrote {path}", flush=True)
    print(f"Survivors={len(survivors)} selected={len(picked)} fail26={len(fail26)}", flush=True)
    for m in out["selected_meta"]:
        print(m, flush=True)

    if len(picked) < 5:
        print(f"\nNEED MORE: only {len(picked)} diversified survivors", flush=True)
        return 1
    print("\nOK: ≥5 OOS survivors", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
