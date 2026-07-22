#!/usr/bin/env python3
"""Search for 20 distinct prop-floor-safe causal winners.

Same rules as ANN10 floor-safe:
- The5ers PROP: static floor $6k, daily $3k
- soft dd_halt, trade caps
- fills only after knowable_at
- full 2020–2025: floor_ok, max_dd<=$6k, profit>0, PF>=1.05
- early + late also floor_ok / dd_ok
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict, replace
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period
from strategy.config import PARAMS, PROP, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import FULL_2020_2025, TEST_LATE, TRAIN_EARLY, pd_years, pf
from strategy.strategies.ann10_winners import ANN10_H1, ANN10_ICT, ANN10_HALTS
from strategy.strategies.eq_liquidity_fade import generate_signals as gen_eq
from strategy.strategies.h1_models import H1Cfg, make_fn as make_h1
from strategy.strategies.judas_reversal import generate_signals as gen_judas
from strategy.strategies.kb_models import Cfg, make_fn as make_ict
from strategy.strategies.retail_models import RetailCfg, make_fn as make_retail
from strategy.strategies.swing_retail import SwingCfg, make_swing_fn
from strategy.strategies.turtle_soup import generate_signals as gen_turtle

RISKS = (0.0025, 0.0035, 0.0045, 0.0050)
HALTS = (4000.0, 4500.0, 5000.0)
MIN_PF = 1.05
MIN_TRADES = 40


def prop_params(risk_pct: float, max_hold_days: int, dd_halt: float, flatten_hour: int = 22, move_to_be: bool = False):
    return replace(
        PARAMS,
        risk_pct=risk_pct,
        max_hold_days=max_hold_days,
        dd_halt=dd_halt,
        flatten_hour_utc=flatten_hour,
        move_to_be=move_to_be,
        daily_profit_cap=2_500.0,
        max_trades_per_day=3,
        max_trades_per_pair_day=1,
        max_open_positions=1,
        cooldown_bars_after_trade=1,
    )


def run_prop(universe, fn, period, params):
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
        "floor_ok": bool(min_eq > floor and r.fail_reason != "max_loss"),
        "dd_ok": bool(r.max_dd <= PROP.max_loss + 1e-6),
        "fail_reason": r.fail_reason,
        "simple_ann_pct": round((profit / PROP.initial_balance) / years * 100, 2) if years else 0.0,
        "cagr_pct": round(((1 + profit / PROP.initial_balance) ** (1 / years) - 1) * 100, 2)
        if years and profit > -PROP.initial_balance
        else float("nan"),
    }


def is_winner(row: dict) -> bool:
    return (
        row["floor_ok"]
        and row["dd_ok"]
        and row["profit"] > 0
        and row["pf"] >= MIN_PF
        and row["trades"] >= MIN_TRADES
    )


def score(row: dict) -> tuple:
    return (int(row["floor_ok"]), int(row["dd_ok"]), row["profit"], row["pf"], -row["max_dd"])


def build_candidates() -> List[Dict[str, Any]]:
    """Diverse candidate list across families (logic fingerprints differ)."""
    cands: List[Dict[str, Any]] = []

    # --- Seed known floor-safe ANN10 ---
    for name, cfg in ANN10_H1.items():
        cands.append(
            {
                "id": name,
                "family": "h1_don",
                "kind": "h1",
                "cfg": cfg,
                "fn": make_h1(cfg),
                "hold": cfg.max_hold_days,
                "seed_risk": cfg.risk_pct,
                "seed_halt": ANN10_HALTS[name],
            }
        )
    for name, cfg in ANN10_ICT.items():
        cands.append(
            {
                "id": name,
                "family": "ict_sb",
                "kind": "ict",
                "cfg": cfg,
                "fn": make_ict(cfg),
                "hold": 0,
                "seed_risk": cfg.risk_pct,
                "seed_halt": ANN10_HALTS[name],
            }
        )

    # --- H1 Donchian neighbors (distinct lengths / RR) ---
    for don, rr, hold in (
        (20, 3.0, 1),
        (20, 4.0, 1),
        (25, 4.0, 1),
        (25, 5.0, 3),
        (45, 4.0, 1),
        (50, 3.0, 1),
        (55, 4.0, 3),
        (15, 3.0, 0),
        (30, 3.0, 1),
        (35, 4.0, 1),
        (40, 5.0, 1),
    ):
        tag = f"H1Don_n{don}_rr{int(rr)}_h{hold}"
        cfg = H1Cfg(
            tag=tag,
            model="don_h1",
            rr=rr,
            don_len=don,
            max_hold_days=hold,
            stop_atr=2.0,
            session_only=True,
            risk_pct=0.004,
        )
        cands.append({"id": tag, "family": "h1_don", "kind": "h1", "cfg": cfg, "fn": make_h1(cfg), "hold": hold})

    # --- H1 EMA ---
    for ef, es, rr, hold in (
        (8, 21, 3.0, 1),
        (12, 48, 3.0, 1),
        (12, 48, 4.0, 3),
        (20, 50, 3.0, 1),
        (9, 34, 4.0, 1),
    ):
        tag = f"H1EMA_{ef}_{es}_rr{int(rr)}_h{hold}"
        cfg = H1Cfg(
            tag=tag,
            model="ema_h1",
            rr=rr,
            ema_fast=ef,
            ema_slow=es,
            max_hold_days=hold,
            stop_atr=2.0,
            session_only=True,
            risk_pct=0.004,
        )
        cands.append({"id": tag, "family": "h1_ema", "kind": "h1", "cfg": cfg, "fn": make_h1(cfg), "hold": hold})

    # --- ICT SB / reject / orb / bos / sweep ---
    ict_specs = [
        ("ict_sb", "sb_fvg", dict(rr=3.0, min_body_atr=0.35, min_fvg_atr=0.15, use_pdh=True, use_asia=False, sb_start=14.0, sb_end=15.0)),
        ("ict_sb", "sb_fvg", dict(rr=3.0, min_body_atr=0.35, min_fvg_atr=0.10, use_pdh=False, use_asia=True, sb_start=14.0, sb_end=15.0)),
        ("ict_sb", "sb_fvg", dict(rr=3.5, min_body_atr=0.30, min_fvg_atr=0.12, use_pdh=True, use_asia=True, sb_start=14.0, sb_end=15.0)),
        ("ict_sb", "sb_fvg", dict(rr=2.5, min_body_atr=0.40, min_fvg_atr=0.15, use_pdh=True, use_asia=False, sb_start=14.0, sb_end=15.0)),
        ("ict_sb", "sb_fvg", dict(rr=3.0, min_body_atr=0.35, min_fvg_atr=0.15, use_pdh=True, use_asia=False, sb_start=7.0, sb_end=8.0)),
        ("ict_sb", "sb_fvg", dict(rr=3.0, min_body_atr=0.35, min_fvg_atr=0.12, use_pdh=False, use_asia=True, sb_start=15.0, sb_end=16.0)),
        ("ict_reject", "reject_mkt", dict(rr=2.0, min_body_atr=0.35, use_pdh=True, use_asia=True, strict_bias=False)),
        ("ict_reject", "reject_mkt", dict(rr=2.5, min_body_atr=0.45, use_pdh=True, use_asia=False, strict_bias=True)),
        ("ict_reject", "reject_mkt", dict(rr=2.0, min_body_atr=0.30, use_pdh=False, use_asia=True, strict_bias=False)),
        ("ict_orb", "orb", dict(rr=2.0, min_body_atr=0.30, orb_end="07:45", strict_bias=False)),
        ("ict_orb", "orb", dict(rr=2.5, min_body_atr=0.40, orb_end="07:30", strict_bias=False)),
        ("ict_bos", "bos_pullback", dict(rr=2.0, min_body_atr=0.35, strict_bias=False, use_pdh=True, use_asia=True)),
        ("ict_bos", "bos_pullback", dict(rr=2.5, min_body_atr=0.45, strict_bias=True, use_pdh=True, use_asia=False)),
        ("ict_sfvg", "sweep_fvg", dict(rr=2.0, min_body_atr=0.35, min_fvg_atr=0.12, strict_bias=False)),
        ("ict_sfvg", "sweep_fvg", dict(rr=2.5, min_body_atr=0.40, min_fvg_atr=0.15, strict_bias=False, use_pdh=True)),
        ("ict_msb", "multi_sb", dict(rr=3.0, min_body_atr=0.30, min_fvg_atr=0.12, use_pdh=True, use_asia=True, sb_windows=((7.0, 8.0), (14.0, 15.0)))),
        ("ict_msb", "multi_sb", dict(rr=3.5, min_body_atr=0.35, min_fvg_atr=0.15, use_pdh=True, use_asia=False, sb_windows=((14.0, 15.0), (15.0, 16.0)))),
    ]
    for fam, model, kw in ict_specs:
        tag = f"{model}_" + "_".join(f"{k}{v}" for k, v in list(kw.items())[:4])
        tag = tag.replace(".", "").replace(" ", "")[:48]
        cfg = Cfg(tag=tag, model=model, move_to_be=False, flatten_hour_utc=22, risk_pct=0.004, **kw)
        cands.append({"id": tag, "family": fam, "kind": "ict", "cfg": cfg, "fn": make_ict(cfg), "hold": 0})

    # --- Retail M15 ---
    retail_specs = [
        ("retail_ema", dict(model="ema_cross", rr=2.5, ema_fast=9, ema_slow=21, stop_atr=1.2, killzone_only=True)),
        ("retail_ema", dict(model="ema_cross", rr=3.0, ema_fast=9, ema_slow=20, stop_atr=1.5, killzone_only=True)),
        ("retail_ema", dict(model="ema_rsi", rr=2.5, ema_trend=50, rsi_lo=35, rsi_hi=65, stop_atr=1.2, killzone_only=True)),
        ("retail_ema", dict(model="ema_rsi", rr=2.0, ema_trend=100, rsi_lo=30, rsi_hi=70, stop_atr=1.2, killzone_only=True)),
        ("retail_don", dict(model="donchian", rr=2.5, don_len=16, stop_atr=1.5, killzone_only=True)),
        ("retail_don", dict(model="donchian", rr=3.0, don_len=24, stop_atr=1.5, killzone_only=True)),
        ("retail_don", dict(model="donchian", rr=2.0, don_len=20, stop_atr=1.2, killzone_only=True)),
        ("retail_macd", dict(model="macd", rr=2.5, stop_atr=1.2, killzone_only=True)),
        ("retail_macd", dict(model="macd", rr=3.0, stop_atr=1.5, killzone_only=True)),
        ("retail_st", dict(model="supertrend", rr=2.5, st_mult=3.0, stop_atr=1.5, killzone_only=True)),
        ("retail_st", dict(model="supertrend", rr=3.0, st_mult=2.5, stop_atr=1.5, killzone_only=True)),
        ("retail_bb", dict(model="bb_rsi", rr=2.0, bb_std=2.0, rsi_lo=30, rsi_hi=70, stop_atr=1.2, killzone_only=True)),
        ("retail_bb", dict(model="bb_rsi", rr=2.5, bb_std=2.5, rsi_lo=30, rsi_hi=70, stop_atr=1.2, killzone_only=True)),
        ("retail_stoch", dict(model="stoch_rsi", rr=2.0, stop_atr=1.2, killzone_only=True)),
        ("retail_vwap", dict(model="vwap_reversion", rr=2.0, vwap_z=1.5, stop_atr=1.0, killzone_only=True)),
    ]
    for fam, kw in retail_specs:
        model = kw["model"]
        tag = f"R_{model}_rr{kw['rr']}_" + "_".join(str(v) for k, v in kw.items() if k not in ("model", "rr", "killzone_only"))[:20]
        tag = tag.replace(".", "")[:40]
        cfg = RetailCfg(tag=tag, flatten_hour_utc=22, move_to_be=False, risk_pct=0.004, **kw)
        cands.append({"id": tag, "family": fam, "kind": "retail", "cfg": cfg, "fn": make_retail(cfg), "hold": 0})

    # --- Daily swing ---
    for don, rr, hold in ((10, 3.0, 5), (20, 3.0, 5), (20, 4.0, 8), (55, 3.0, 10)):
        tag = f"DonD_n{don}_rr{int(rr)}_h{hold}"
        cfg = SwingCfg(tag=tag, model="don_daily", rr=rr, don_len=don, max_hold_days=hold, flatten_hour_utc=23)
        cands.append({"id": tag, "family": "swing_don", "kind": "swing", "cfg": cfg, "fn": make_swing_fn(cfg), "hold": hold})
    for ef, es, rr, hold in ((10, 30, 3.0, 5), (20, 50, 3.0, 8)):
        tag = f"EmaD_{ef}_{es}_rr{int(rr)}_h{hold}"
        cfg = SwingCfg(tag=tag, model="ema_daily", rr=rr, ema_fast=ef, ema_slow=es, max_hold_days=hold, flatten_hour_utc=23)
        cands.append({"id": tag, "family": "swing_ema", "kind": "swing", "cfg": cfg, "fn": make_swing_fn(cfg), "hold": hold})
    for rr, hold in ((3.0, 5), (4.0, 8)):
        tag = f"RsiD_rr{int(rr)}_h{hold}"
        cfg = SwingCfg(tag=tag, model="rsi_daily", rr=rr, max_hold_days=hold, flatten_hour_utc=23)
        cands.append({"id": tag, "family": "swing_rsi", "kind": "swing", "cfg": cfg, "fn": make_swing_fn(cfg), "hold": hold})

    # --- Classic ICT fades (fixed generators) ---
    for name, fn in (
        ("EQ_fade", gen_eq),
        ("TurtleSoup", gen_turtle),
        ("JudasLondon", gen_judas),
    ):
        cands.append({"id": name, "family": "classic_fade", "kind": "classic", "cfg": None, "fn": fn, "hold": 0})

    # Dedupe by id
    seen = set()
    uniq = []
    for c in cands:
        if c["id"] in seen:
            continue
        seen.add(c["id"])
        uniq.append(c)
    return uniq


def tune_candidate(universe, cand: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Try risk/halt grid; return best floor-safe winner or None."""
    hold = int(cand.get("hold", 0))
    screen_risk = float(cand.get("seed_risk", 0.004))
    screen_halt = float(cand.get("seed_halt", 4500.0))
    params = prop_params(screen_risk, hold, screen_halt)
    full = run_prop(universe, cand["fn"], FULL_2020_2025, params)

    # Hopeless: skip grid
    if full["max_dd"] > 10_000 or full["profit"] < -4_000:
        return None

    trials = [(screen_risk, screen_halt, full)]
    promising = (
        full["profit"] > -500
        and full["pf"] >= 0.95
        and full["max_dd"] <= 8_000
    )
    if promising or cand.get("seed_risk"):
        risks = sorted(set([screen_risk, *RISKS]))
        halts = sorted(set([screen_halt, *HALTS]))
        for risk in risks:
            for halt in halts:
                if abs(risk - screen_risk) < 1e-9 and abs(halt - screen_halt) < 1e-9:
                    continue
                # Prefer lower risk when screen DD is high
                if full["max_dd"] > 6000 and risk > screen_risk:
                    continue
                p = prop_params(risk, hold, halt)
                row = run_prop(universe, cand["fn"], FULL_2020_2025, p)
                trials.append((risk, halt, row))
    elif full["max_dd"] > 6000 and full["profit"] > 0:
        # One shot at lower risk
        for risk in (0.0025, 0.0035):
            if risk >= screen_risk:
                continue
            p = prop_params(risk, hold, 4000.0)
            trials.append((risk, 4000.0, run_prop(universe, cand["fn"], FULL_2020_2025, p)))

    best = None
    for risk, halt, row in trials:
        if not is_winner(row):
            continue
        p = prop_params(risk, hold, halt)
        early = run_prop(universe, cand["fn"], TRAIN_EARLY, p)
        late = run_prop(universe, cand["fn"], TEST_LATE, p)
        if not (early["floor_ok"] and early["dd_ok"] and late["floor_ok"] and late["dd_ok"]):
            continue
        packed = {
            "id": cand["id"],
            "family": cand["family"],
            "kind": cand["kind"],
            "risk_pct": risk,
            "dd_halt": halt,
            "max_hold_days": hold,
            "cfg": asdict(cand["cfg"]) if cand["cfg"] is not None else None,
            "full": row,
            "early": {k: early[k] for k in ("floor_ok", "dd_ok", "max_dd", "profit", "pf", "trades", "simple_ann_pct")},
            "late": {k: late[k] for k in ("floor_ok", "dd_ok", "max_dd", "profit", "pf", "trades", "simple_ann_pct")},
        }
        if best is None or score(row) > score(best["full"]):
            best = packed
    return best


def diversify(winners: List[Dict[str, Any]], n: int = 20) -> List[Dict[str, Any]]:
    """Pick up to n winners with family caps for diversity."""
    winners = sorted(winners, key=lambda w: score(w["full"]), reverse=True)
    selected: List[Dict[str, Any]] = []
    family_count: Dict[str, int] = {}
    # Prefer keeping seeded ANN10 ids
    seeds = [w for w in winners if w["id"].startswith("A")]
    rest = [w for w in winners if not w["id"].startswith("A")]

    def try_add(w):
        fam = w["family"]
        if family_count.get(fam, 0) >= 4 and not w["id"].startswith("A"):
            return False
        # Avoid near-duplicates: same family + very similar ann/dd already taken
        for s in selected:
            if s["family"] == fam and abs(s["full"]["simple_ann_pct"] - w["full"]["simple_ann_pct"]) < 0.15:
                if abs(s["full"]["max_dd"] - w["full"]["max_dd"]) < 150:
                    return False
        selected.append(w)
        family_count[fam] = family_count.get(fam, 0) + 1
        return True

    for w in seeds:
        if len(selected) >= n:
            break
        try_add(w)
    for w in rest:
        if len(selected) >= n:
            break
        try_add(w)
    # If still short, relax family cap
    if len(selected) < n:
        for w in winners:
            if len(selected) >= n:
                break
            if any(s["id"] == w["id"] for s in selected):
                continue
            selected.append(w)
    return selected[:n]


def main() -> int:
    print("=== Floor-safe search for 20 distinct winners ===\n", flush=True)
    assert_mod = __import__("scripts.assert_no_lookahead", fromlist=["main"])
    if assert_mod.main() != 0:
        print("ABORT: look-ahead assert failed")
        return 1

    universe = load_universe(PARAMS.pairs)
    cands = build_candidates()
    print(f"Candidates: {len(cands)}", flush=True)

    winners: List[Dict[str, Any]] = []
    tested = []
    for i, cand in enumerate(cands, 1):
        print(f"[{i}/{len(cands)}] {cand['id']} ({cand['family']})...", flush=True)
        try:
            best = tune_candidate(universe, cand)
        except Exception as e:
            print(f"  ERROR: {e}", flush=True)
            continue
        if best is None:
            print("  no floor-safe winner", flush=True)
            tested.append({"id": cand["id"], "family": cand["family"], "ok": False})
            continue
        f = best["full"]
        print(
            f"  WIN ann={f['simple_ann_pct']}% dd=${f['max_dd']:,.0f} pf={f['pf']} "
            f"n={f['trades']} risk={best['risk_pct']*100:.2f}% halt=${best['dd_halt']:,.0f}",
            flush=True,
        )
        winners.append(best)
        tested.append({"id": cand["id"], "ok": True, **{k: best[k] for k in ("risk_pct", "dd_halt", "family")}})

    selected = diversify(winners, 20)
    out = {
        "n_candidates": len(cands),
        "n_winners_raw": len(winners),
        "n_selected": len(selected),
        "selected": selected,
        "all_winners": winners,
        "tested": tested,
        "rules": {
            "floor": PROP.initial_balance - PROP.max_loss,
            "max_loss": PROP.max_loss,
            "daily": PROP.daily_loss_limit,
            "min_pf": MIN_PF,
            "min_trades": MIN_TRADES,
        },
    }
    RESULTS_DIR_P = Path(RESULTS_DIR)
    RESULTS_DIR_P.mkdir(exist_ok=True)
    (RESULTS_DIR_P / "floor_safe_20.json").write_text(json.dumps(out, indent=2, default=str))

    lines = [
        "# Twenty prop-floor-safe causal winners",
        "",
        "Rules: The5ers static floor **$6k**, daily **$3k**, soft `dd_halt`, causal fills only after `knowable_at`.",
        "",
        f"Screened **{len(cands)}** configs → **{len(winners)}** raw winners → **{len(selected)}** diverse selected.",
        "",
        "| # | ID | Family | Max DD | Ann | PF | Trades | Risk | Halt |",
        "|---|----|--------|--------|-----|----|--------|------|------|",
    ]
    for i, w in enumerate(selected, 1):
        f = w["full"]
        lines.append(
            f"| {i} | `{w['id']}` | {w['family']} | ${f['max_dd']:,.0f} | {f['simple_ann_pct']}% | "
            f"{f['pf']} | {f['trades']} | {w['risk_pct']*100:.2f}% | ${w['dd_halt']:,.0f} |"
        )
    lines += [
        "",
        "## Confirm",
        "",
        "```bash",
        "python3 scripts/assert_no_lookahead.py",
        "python3 scripts/confirm_floor_safe_20.py",
        "```",
        "",
        "Registry: `strategy/strategies/floor_safe_20.py`",
    ]
    (RESULTS_DIR_P / "FLOOR_SAFE_20.md").write_text("\n".join(lines) + "\n")
    print(f"\nSelected {len(selected)} / need 20. Wrote results/floor_safe_20.json", flush=True)
    for w in selected:
        print(f"  {w['id']}: ann={w['full']['simple_ann_pct']}% dd={w['full']['max_dd']}", flush=True)
    return 0 if len(selected) >= 20 else 2


if __name__ == "__main__":
    raise SystemExit(main())
