#!/usr/bin/env python3
"""Second-pass diversity hunt: fill underrepresented families to reach 20 distinct winners.

Same PROP floor rules. Hard family caps. Reuses pass-1 winners from floor_safe_20.json.
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict, replace
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.config import PARAMS, PROP, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.run_floor_safe_20 import (
    MIN_PF,
    MIN_TRADES,
    is_winner,
    prop_params,
    run_prop,
    score,
)
from strategy.run_cagr25_search import FULL_2020_2025, TEST_LATE, TRAIN_EARLY
from strategy.strategies.c1_asia_break_go import generate_signals as gen_c1
from strategy.strategies.c2_liquidity_reject import generate_signals as gen_c2
from strategy.strategies.c3_london_judas import generate_signals as gen_c3
from strategy.strategies.c4_displacement import generate_signals as gen_c4
from strategy.strategies.c5_london_orb import generate_signals as gen_c5
from strategy.strategies.c6_equal_retest import generate_signals as gen_c6
from strategy.strategies.h1_models import H1Cfg, make_fn as make_h1
from strategy.strategies.kb_models import Cfg, make_fn as make_ict
from strategy.strategies.retail_models import RetailCfg, make_fn as make_retail
from strategy.strategies.retail_models_v2 import RetailCfg2, make_fn2
from strategy.strategies.session_break_retest import generate_signals as gen_sbr
from strategy.strategies.silver_bullet_fvg import generate_signals as gen_sb
from strategy.strategies.swing_retail import SwingCfg, make_swing_fn
from strategy.strategies.winners import WINNER_CFGS

FAMILY_CAP = {
    "h1_don": 3,
    "h1_ema": 2,
    "ict_sb": 4,
    "ict_other": 3,
    "retail": 4,
    "swing": 3,
    "classic": 4,
}


def validate(universe, fn, hold, risk, halt, depth: int = 0) -> Optional[Dict[str, Any]]:
    p = prop_params(risk, hold, halt)
    row = run_prop(universe, fn, FULL_2020_2025, p)
    if not is_winner(row):
        if depth == 0 and row["profit"] > 0 and (row["max_dd"] > 6000 or not row["dd_ok"]) and risk > 0.003:
            return validate(universe, fn, hold, 0.0025, 4000.0, depth=1)
        return None
    early = run_prop(universe, fn, TRAIN_EARLY, p)
    late = run_prop(universe, fn, TEST_LATE, p)
    if not (early["floor_ok"] and early["dd_ok"] and late["floor_ok"] and late["dd_ok"]):
        if depth == 0 and risk > 0.003:
            return validate(universe, fn, hold, 0.0025, 4000.0, depth=1)
        return None
    return {
        "risk_pct": risk,
        "dd_halt": halt,
        "max_hold_days": hold,
        "full": row,
        "early": {k: early[k] for k in ("floor_ok", "dd_ok", "max_dd", "profit", "pf", "trades", "simple_ann_pct")},
        "late": {k: late[k] for k in ("floor_ok", "dd_ok", "max_dd", "profit", "pf", "trades", "simple_ann_pct")},
    }


def build_diverse_candidates() -> List[Dict[str, Any]]:
    cands = []

    # Soft KB winners W1-W5 at floor risk
    for name, cfg in WINNER_CFGS.items():
        cfg2 = replace(cfg, risk_pct=0.004, move_to_be=False, flatten_hour_utc=22)
        cands.append({"id": f"FS_{name}", "family": "ict_sb", "kind": "ict", "cfg": cfg2, "fn": make_ict(cfg2), "hold": 0})

    # More SB / ICT variants with clean IDs
    ict_list = [
        ("SB14_PDH_rr35_b40", "sb_fvg", dict(rr=3.5, min_body_atr=0.40, min_fvg_atr=0.12, use_pdh=True, use_asia=False, sb_start=14.0, sb_end=15.0)),
        ("SB14_ASIA_rr30_b40", "sb_fvg", dict(rr=3.0, min_body_atr=0.40, min_fvg_atr=0.10, use_pdh=False, use_asia=True, sb_start=14.0, sb_end=15.0)),
        ("SB14_BOTH_rr30_b30", "sb_fvg", dict(rr=3.0, min_body_atr=0.30, min_fvg_atr=0.10, use_pdh=True, use_asia=True, sb_start=14.0, sb_end=15.0)),
        ("SB7_PDH_rr30", "sb_fvg", dict(rr=3.0, min_body_atr=0.35, min_fvg_atr=0.15, use_pdh=True, use_asia=False, sb_start=7.0, sb_end=8.0)),
        ("SB15_ASIA_rr30", "sb_fvg", dict(rr=3.0, min_body_atr=0.35, min_fvg_atr=0.12, use_pdh=False, use_asia=True, sb_start=15.0, sb_end=16.0)),
        ("RJ_BOTH_rr20_b35", "reject_mkt", dict(rr=2.0, min_body_atr=0.35, use_pdh=True, use_asia=True, strict_bias=False)),
        ("RJ_PDH_rr25_b40_S", "reject_mkt", dict(rr=2.5, min_body_atr=0.40, use_pdh=True, use_asia=False, strict_bias=True)),
        ("RJ_ASIA_rr20_b25", "reject_mkt", dict(rr=2.0, min_body_atr=0.25, use_pdh=False, use_asia=True, strict_bias=False)),
        ("ORB745_rr20", "orb", dict(rr=2.0, min_body_atr=0.25, orb_end="07:45", strict_bias=False)),
        ("ORB730_rr25", "orb", dict(rr=2.5, min_body_atr=0.30, orb_end="07:30", strict_bias=False)),
        ("BOS_rr20_b30", "bos_pullback", dict(rr=2.0, min_body_atr=0.30, strict_bias=False, use_pdh=True, use_asia=True)),
        ("BOS_rr25_b35_S", "bos_pullback", dict(rr=2.5, min_body_atr=0.35, strict_bias=True, use_pdh=True, use_asia=False)),
        ("SFVG_rr20_b30", "sweep_fvg", dict(rr=2.0, min_body_atr=0.30, min_fvg_atr=0.10, strict_bias=False)),
        ("SFVG_rr25_b35", "sweep_fvg", dict(rr=2.5, min_body_atr=0.35, min_fvg_atr=0.12, strict_bias=False)),
        ("MSB_714_rr30", "multi_sb", dict(rr=3.0, min_body_atr=0.30, min_fvg_atr=0.12, use_pdh=True, use_asia=True, sb_windows=((7.0, 8.0), (14.0, 15.0)))),
        ("MSB_1415_rr35", "multi_sb", dict(rr=3.5, min_body_atr=0.30, min_fvg_atr=0.12, use_pdh=True, use_asia=False, sb_windows=((14.0, 15.0), (15.0, 16.0)))),
    ]
    for tag, model, kw in ict_list:
        fam = "ict_sb" if model in ("sb_fvg", "multi_sb") else "ict_other"
        cfg = Cfg(tag=tag, model=model, move_to_be=False, flatten_hour_utc=22, risk_pct=0.004, **kw)
        cands.append({"id": tag, "family": fam, "kind": "ict", "cfg": cfg, "fn": make_ict(cfg), "hold": 0})

    # H1 EMA more variants
    for ef, es, rr, hold in ((5, 20, 3.0, 1), (8, 34, 4.0, 1), (12, 26, 3.0, 1), (15, 45, 4.0, 3), (10, 40, 3.0, 1)):
        tag = f"H1EMA_{ef}_{es}_rr{int(rr)}_h{hold}"
        cfg = H1Cfg(tag=tag, model="ema_h1", rr=rr, ema_fast=ef, ema_slow=es, max_hold_days=hold, stop_atr=2.0, session_only=True, risk_pct=0.004)
        cands.append({"id": tag, "family": "h1_ema", "kind": "h1", "cfg": cfg, "fn": make_h1(cfg), "hold": hold})

    # Retail + v2
    retail = [
        ("R_EMA9_21_rr20", dict(model="ema_cross", rr=2.0, ema_fast=9, ema_slow=21, stop_atr=1.0, killzone_only=True)),
        ("R_EMA8_21_rr25", dict(model="ema_cross", rr=2.5, ema_fast=8, ema_slow=21, stop_atr=1.2, killzone_only=True)),
        ("R_EMARSI_t50_rr30", dict(model="ema_rsi", rr=3.0, ema_trend=50, rsi_lo=40, rsi_hi=60, stop_atr=1.2, killzone_only=True)),
        ("R_DON16_rr25", dict(model="donchian", rr=2.5, don_len=16, stop_atr=1.2, killzone_only=True)),
        ("R_DON32_rr20", dict(model="donchian", rr=2.0, don_len=32, stop_atr=1.5, killzone_only=True)),
        ("R_MACD_rr20", dict(model="macd", rr=2.0, stop_atr=1.0, killzone_only=True)),
        ("R_ST_m30_rr20", dict(model="supertrend", rr=2.0, st_mult=3.0, stop_atr=1.2, killzone_only=True)),
        ("R_BB_rr15", dict(model="bb_rsi", rr=1.5, bb_std=2.0, rsi_lo=25, rsi_hi=75, stop_atr=1.0, killzone_only=True)),
        ("R_STOCH_rr25", dict(model="stoch_rsi", rr=2.5, stop_atr=1.0, killzone_only=True)),
        ("R_VWAP_z20_rr20", dict(model="vwap_reversion", rr=2.0, vwap_z=2.0, stop_atr=1.0, killzone_only=True)),
    ]
    for tag, kw in retail:
        cfg = RetailCfg(tag=tag, flatten_hour_utc=22, move_to_be=False, risk_pct=0.004, **kw)
        cands.append({"id": tag, "family": "retail", "kind": "retail", "cfg": cfg, "fn": make_retail(cfg), "hold": 0})

    for tag, kw in (
        ("R2_EMA_ADX_rr25", dict(model="ema_rsi_adx", rr=2.5, ema_trend=50, rsi_lo=35, rsi_hi=65, adx_min=20, stop_atr=1.2, killzone_only=True)),
        ("R2_EMA_ADX_rr20", dict(model="ema_rsi_adx", rr=2.0, ema_trend=100, rsi_lo=30, rsi_hi=70, adx_min=18, stop_atr=1.2, killzone_only=True)),
        ("R2_CCI_rr20", dict(model="cci_fade", rr=2.0, stop_atr=1.2, killzone_only=True)),
        ("R2_ROC_rr25", dict(model="roc_break", rr=2.5, stop_atr=1.2, killzone_only=True)),
        ("R2_STACK_rr20", dict(model="ema_stack", rr=2.0, stop_atr=1.2, killzone_only=True)),
    ):
        cfg = RetailCfg2(tag=tag, flatten_hour_utc=22, move_to_be=False, risk_pct=0.004, **kw)
        cands.append({"id": tag, "family": "retail", "kind": "retail2", "cfg": cfg, "fn": make_fn2(cfg), "hold": 0})

    # Swing more
    for don, rr, hold in ((15, 3.0, 5), (30, 4.0, 8), (40, 3.0, 10), (20, 2.5, 5)):
        tag = f"DonD_n{don}_rr{rr}_h{hold}".replace(".", "")
        cfg = SwingCfg(tag=tag, model="don_daily", rr=rr, don_len=don, max_hold_days=hold, flatten_hour_utc=23)
        cands.append({"id": tag, "family": "swing", "kind": "swing", "cfg": cfg, "fn": make_swing_fn(cfg), "hold": hold})
    for ef, es, rr, hold in ((8, 21, 3.0, 5), (12, 48, 4.0, 8), (20, 50, 2.5, 5)):
        tag = f"EmaD_{ef}_{es}_rr{rr}_h{hold}".replace(".", "")
        cfg = SwingCfg(tag=tag, model="ema_daily", rr=rr, ema_fast=ef, ema_slow=es, max_hold_days=hold, flatten_hour_utc=23)
        cands.append({"id": tag, "family": "swing", "kind": "swing", "cfg": cfg, "fn": make_swing_fn(cfg), "hold": hold})
    for rr, hold in ((2.5, 5), (3.5, 8)):
        tag = f"RsiD_rr{rr}_h{hold}".replace(".", "")
        cfg = SwingCfg(tag=tag, model="rsi_daily", rr=rr, max_hold_days=hold, flatten_hour_utc=23)
        cands.append({"id": tag, "family": "swing", "kind": "swing", "cfg": cfg, "fn": make_swing_fn(cfg), "hold": hold})

    # Classic causal modules
    for name, fn in (
        ("C1_AsiaBreakGo", gen_c1),
        ("C2_LiqReject", gen_c2),
        ("C3_LondonJudas", gen_c3),
        ("C4_Displacement", gen_c4),
        ("C5_LondonORB", gen_c5),
        ("C6_EqualRetest", gen_c6),
        ("SBR_SessionBreak", gen_sbr),
        ("SB_Module", gen_sb),
    ):
        cands.append({"id": name, "family": "classic", "kind": "classic", "cfg": None, "fn": fn, "hold": 0})

    seen = set()
    out = []
    for c in cands:
        if c["id"] in seen:
            continue
        seen.add(c["id"])
        out.append(c)
    return out


def diversify_hard(winners: List[Dict[str, Any]], n: int = 20) -> List[Dict[str, Any]]:
    winners = sorted(winners, key=lambda w: score(w["full"]), reverse=True)
    selected = []
    fam_n: Dict[str, int] = {}

    def fam_of(w):
        f = w["family"]
        if f.startswith("retail"):
            return "retail"
        if f.startswith("swing"):
            return "swing"
        if f in ("ict_reject", "ict_orb", "ict_bos", "ict_sfvg", "ict_msb"):
            return "ict_other" if f != "ict_msb" else "ict_sb"
        if f == "ict_msb":
            return "ict_sb"
        return f

    for w in winners:
        fam = fam_of(w)
        cap = FAMILY_CAP.get(fam, 3)
        if fam_n.get(fam, 0) >= cap:
            continue
        # skip near-dupes inside family
        skip = False
        for s in selected:
            if fam_of(s) == fam and abs(s["full"]["simple_ann_pct"] - w["full"]["simple_ann_pct"]) < 0.2:
                if abs(s["full"]["max_dd"] - w["full"]["max_dd"]) < 200:
                    skip = True
                    break
        if skip:
            continue
        selected.append(w)
        fam_n[fam] = fam_n.get(fam, 0) + 1
        if len(selected) >= n:
            break
    return selected


def main() -> int:
    print("=== Diversity pass for floor-safe 20 ===\n", flush=True)
    prev_path = Path(RESULTS_DIR) / "floor_safe_20.json"
    prev = json.loads(prev_path.read_text()) if prev_path.exists() else {"all_winners": []}
    # Remap old families
    existing = []
    for w in prev.get("all_winners", []):
        fam = w["family"]
        if fam.startswith("retail"):
            w = dict(w, family="retail")
        elif fam.startswith("swing"):
            w = dict(w, family="swing")
        elif fam in ("ict_reject", "ict_orb", "ict_bos", "ict_sfvg"):
            w = dict(w, family="ict_other")
        elif fam == "ict_msb":
            w = dict(w, family="ict_sb")
        existing.append(w)

    universe = load_universe(PARAMS.pairs)
    screen_uni = {k: universe[k] for k in ("EURUSD", "GBPUSD", "USDJPY", "XAUUSD") if k in universe}
    cands = build_diverse_candidates()
    print(f"Pass-2 candidates: {len(cands)}; prior winners: {len(existing)}", flush=True)

    new_wins = []
    for i, cand in enumerate(cands, 1):
        print(f"[{i}/{len(cands)}] {cand['id']} ({cand['family']})...", flush=True)
        try:
            # cheap screen
            scr = run_prop(screen_uni, cand["fn"], FULL_2020_2025, prop_params(0.004, cand["hold"], 4500.0))
            if scr["profit"] < -2000 or scr["max_dd"] > 12000 or scr["pf"] < 0.9:
                print(f"  skip screen pf={scr['pf']} dd={scr['max_dd']} pnl={scr['profit']}", flush=True)
                continue
            risks = [0.004]
            if scr["max_dd"] > 5500:
                risks = [0.0025, 0.0035]
            elif scr["profit"] > 0 and scr["pf"] >= 1.0:
                risks = [0.004, 0.005]
            best = None
            for risk in risks:
                halt = 4000.0 if scr["max_dd"] > 5000 else 4500.0
                packed = validate(universe, cand["fn"], cand["hold"], risk, halt)
                if packed is None:
                    continue
                row = {
                    "id": cand["id"],
                    "family": cand["family"],
                    "kind": cand["kind"],
                    "cfg": asdict(cand["cfg"]) if cand["cfg"] is not None else None,
                    **packed,
                }
                if best is None or score(row["full"]) > score(best["full"]):
                    best = row
            if best is None:
                print("  no floor-safe winner", flush=True)
            else:
                f = best["full"]
                print(
                    f"  WIN ann={f['simple_ann_pct']}% dd=${f['max_dd']:,.0f} pf={f['pf']} n={f['trades']} "
                    f"risk={best['risk_pct']*100:.2f}%",
                    flush=True,
                )
                new_wins.append(best)
        except Exception as e:
            print(f"  ERROR: {e}", flush=True)

    # Merge by id (prefer higher score)
    by_id = {w["id"]: w for w in existing}
    for w in new_wins:
        if w["id"] not in by_id or score(w["full"]) > score(by_id[w["id"]]["full"]):
            by_id[w["id"]] = w
    all_w = list(by_id.values())
    selected = diversify_hard(all_w, 20)

    out = {
        "n_pass2_candidates": len(cands),
        "n_winners_raw": len(all_w),
        "n_selected": len(selected),
        "selected": selected,
        "all_winners": all_w,
        "rules": {
            "floor": PROP.initial_balance - PROP.max_loss,
            "max_loss": PROP.max_loss,
            "daily": PROP.daily_loss_limit,
            "min_pf": MIN_PF,
            "min_trades": MIN_TRADES,
            "family_cap": FAMILY_CAP,
        },
    }
    Path(RESULTS_DIR).mkdir(exist_ok=True)
    (Path(RESULTS_DIR) / "floor_safe_20.json").write_text(json.dumps(out, indent=2, default=str))

    lines = [
        "# Twenty prop-floor-safe causal winners (diverse)",
        "",
        "Rules: The5ers static floor **$6k**, daily **$3k**, soft `dd_halt`, causal fills after `knowable_at`.",
        "",
        f"Merged pool **{len(all_w)}** → selected **{len(selected)}** with family caps.",
        "",
        "| # | ID | Family | Max DD | Ann | PF | n | Risk | Halt |",
        "|---|----|--------|--------|-----|----|---|------|------|",
    ]
    for i, w in enumerate(selected, 1):
        f = w["full"]
        lines.append(
            f"| {i} | `{w['id']}` | {w['family']} | ${f['max_dd']:,.0f} | {f['simple_ann_pct']}% | "
            f"{f['pf']} | {f['trades']} | {w['risk_pct']*100:.2f}% | ${w['dd_halt']:,.0f} |"
        )
    lines += ["", "Registry: `strategy/strategies/floor_safe_20.py`", "", "Confirm: `python3 scripts/confirm_floor_safe_20.py`"]
    (Path(RESULTS_DIR) / "FLOOR_SAFE_20.md").write_text("\n".join(lines) + "\n")

    print(f"\nSelected {len(selected)}/20", flush=True)
    for w in selected:
        print(f"  {w['id']}: {w['family']} ann={w['full']['simple_ann_pct']}%", flush=True)
    from collections import Counter
    print("families:", dict(Counter(w["family"] for w in selected)), flush=True)
    return 0 if len(selected) >= 20 else 2


if __name__ == "__main__":
    raise SystemExit(main())
