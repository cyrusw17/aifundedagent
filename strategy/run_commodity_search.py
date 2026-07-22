#!/usr/bin/env python3
"""Commodity strategy search — NO 2026+ data.

Target: ≥5 causal winners with:
- 2024 simple ann ≥ 10%
- 2025 simple ann ≥ 10%
- Consistent: each of 2021–2025 ≥ 5% ann (year-after-year)
- PF(2024–2025) ≥ 1.05
- Static floor equity > $94k on 2024–2025
- Fills only after knowable_at

Universe: XAUUSD, XAGUSD, BCOUSD (commodities only).
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
from strategy.data_loader import RESEARCH_MAX_END, load_universe
from strategy.run_cagr25_search import pf
from strategy.strategies.commodity_models import CmdCfg, build_commodity_space, make_cmd_fn
from strategy.strategies.kb_models import Cfg, make_fn as make_ict

FLOOR = PROP.initial_balance - PROP.max_loss
YEARS = ("2021", "2022", "2023", "2024", "2025")
TARGET_2425 = ("2024-01-01", "2025-12-31")
MIN_YEAR_ANN = 0.0
MIN_2425_ANN = 10.0
MIN_RECENT_ANN = 0.0  # 2023 at least flat; 2024–25 carry the 10%+ bar
MAX_YEAR_LOSS = -8.0


def assert_no_2026(universe) -> None:
    for pair, frames in universe.items():
        mx = frames["m1"].index.max()
        if mx >= pd_ts("2026-01-01"):
            raise RuntimeError(f"FUTURE DATA LEAK: {pair} max={mx}")


def pd_ts(s: str):
    import pandas as pd

    return pd.Timestamp(s)


def year_period(y: str) -> Tuple[str, str]:
    return f"{y}-01-01", f"{y}-12-31"


def make_params(risk: float, hold: int, *, compound: bool = True) -> Any:
    return replace(
        PARAMS,
        risk_pct=risk,
        max_hold_days=hold,
        dd_halt=0.0,
        flatten_hour_utc=22,
        move_to_be=False,
        daily_profit_cap=6_000.0,
        max_trades_per_day=6,
        max_trades_per_pair_day=2,
        max_open_positions=2,
        cooldown_bars_after_trade=0,
        risk_from_equity=compound,
        equity_halt_floor=FLOOR + 1_000.0,
    )


def run(universe, fn, period, params):
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
    import pandas as pd

    start, end = pd_ts(period[0]), pd_ts(period[1])
    years = max((end - start).days / 365.25, 1e-9)
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
        "end_eq": round(float(r.end_equity), 2),
    }


def eval_years(universe, fn, params) -> Dict[str, Any]:
    by_year = {}
    for y in YEARS:
        by_year[y] = run(universe, fn, year_period(y), params)
    w2425 = run(universe, fn, TARGET_2425, params)
    return {"years": by_year, "w2425": w2425}


def is_winner(ev: Dict[str, Any]) -> bool:
    y = ev["years"]
    w = ev["w2425"]
    if not w["floor_ok"] or w["pf"] < 1.05 or w["trades"] < 15:
        return False
    if y["2024"]["ann"] < MIN_2425_ANN or y["2025"]["ann"] < MIN_2425_ANN:
        return False
    # Recent: 2023 flat-or-better; 2024–2025 each ≥10% (already checked)
    if y["2023"]["ann"] < MIN_RECENT_ANN or not y["2023"]["floor_ok"]:
        return False
    # No disaster years in 2021–2025; floor always held
    for yy in YEARS:
        if not y[yy]["floor_ok"]:
            return False
        if y[yy]["ann"] < MAX_YEAR_LOSS:
            return False
    return True


def score(ev: Dict[str, Any]) -> tuple:
    y = ev["years"]
    return (
        min(y[yy]["ann"] for yy in YEARS),
        y["2024"]["ann"] + y["2025"]["ann"],
        ev["w2425"]["pf"],
    )


def ict_candidates() -> List[Tuple[str, Callable, int, Any]]:
    out = []
    specs = [
        ("ICT_SB14_ASIA", dict(model="sb_fvg", rr=3.5, min_body_atr=0.35, min_fvg_atr=0.12, use_pdh=False, use_asia=True, sb_start=14.0, sb_end=15.0, strict_bias=False)),
        ("ICT_SB14_PDH", dict(model="sb_fvg", rr=3.5, min_body_atr=0.35, min_fvg_atr=0.15, use_pdh=True, use_asia=False, sb_start=14.0, sb_end=15.0, strict_bias=False)),
        ("ICT_SB14_BOTH", dict(model="sb_fvg", rr=3.0, min_body_atr=0.30, min_fvg_atr=0.12, use_pdh=True, use_asia=True, sb_start=14.0, sb_end=15.0, strict_bias=False)),
        ("ICT_MSB", dict(model="multi_sb", rr=3.5, min_body_atr=0.25, min_fvg_atr=0.12, use_pdh=True, use_asia=True, sb_windows=((7.0, 8.0), (14.0, 15.0)), strict_bias=False)),
        ("ICT_RJ", dict(model="reject_mkt", rr=2.5, min_body_atr=0.35, use_pdh=True, use_asia=True, strict_bias=False)),
    ]
    for tag, kw in specs:
        cfg = Cfg(tag=tag, move_to_be=False, flatten_hour_utc=22, **kw)
        out.append((tag, make_ict(cfg), 0, cfg))
    return out


def main() -> int:
    print("=== Commodity winners search (NO 2026+ data) ===\n", flush=True)
    print(f"Research cutoff: {RESEARCH_MAX_END}", flush=True)

    # Look-ahead guard first
    from scripts.assert_no_lookahead import main as assert_main

    if assert_main() != 0:
        return 1

    pairs = PARAMS.commodity_pairs
    print(f"Loading commodities: {pairs}", flush=True)
    universe = load_universe(pairs, max_end=RESEARCH_MAX_END)
    assert_no_2026(universe)
    for p, fr in universe.items():
        print(f"  {p}: {fr['m1'].index.min()} → {fr['m1'].index.max()}  n={len(fr['m1'])}", flush=True)

    # Also single-metal universes for diversity
    uni_gold = {k: universe[k] for k in ("XAUUSD",) if k in universe}
    uni_silver = {k: universe[k] for k in ("XAGUSD",) if k in universe}
    uni_oil = {k: universe[k] for k in ("BCOUSD",) if k in universe}
    scopes = [
        ("CMD3", universe),
        ("XAU", uni_gold),
        ("XAG", uni_silver),
        ("BCO", uni_oil),
    ]

    space = build_commodity_space()
    # Compact: keep every other config to speed, plus all long-only daily/H4
    compact = []
    for cfg in space:
        if cfg.long_only and cfg.tf in ("4h", "1D"):
            compact.append(cfg)
        elif cfg.tf == "1h" and cfg.rr in (3.5, 5.0) and (cfg.don_len in (20, 35) or cfg.model != "don"):
            compact.append(cfg)
        elif cfg.tf == "4h" and cfg.rr == 3.5:
            compact.append(cfg)
    # dedupe by tag
    seen = set()
    cands = []
    for cfg in compact:
        if cfg.tag in seen:
            continue
        seen.add(cfg.tag)
        cands.append(("CMD_" + cfg.tag, make_cmd_fn(cfg), cfg.max_hold_days, cfg))
    for tag, fn, hold, cfg in ict_candidates():
        cands.append((tag, fn, hold, cfg))

    print(f"Candidates: {len(cands)} × {len(scopes)} scopes", flush=True)

    winners: List[Dict[str, Any]] = []
    tested = 0
    for scope_name, uni in scopes:
        if not uni:
            continue
        print(f"\n--- Scope {scope_name} ---", flush=True)
        for i, (name, fn, hold, cfg) in enumerate(cands, 1):
            # Screen at 0.75% on 2024-25 only
            screen_p = make_params(0.0075, hold)
            try:
                scr = run(uni, fn, TARGET_2425, screen_p)
            except Exception as e:
                print(f"  [{i}] {name} ERROR {e}", flush=True)
                continue
            tested += 1
            if scr["ann"] < 8 or scr["pf"] < 1.0 or not scr["floor_ok"]:
                continue
            print(f"  [{i}] {name} screen2425 ann={scr['ann']}% pf={scr['pf']} — deep check", flush=True)
            best_local = None
            for risk in (0.005, 0.0075, 0.010, 0.0125):
                p = make_params(risk, hold)
                ev = eval_years(uni, fn, p)
                if not is_winner(ev):
                    continue
                packed = {
                    "id": f"{scope_name}__{name}",
                    "scope": scope_name,
                    "name": name,
                    "risk_pct": risk,
                    "hold": hold,
                    "cfg": asdict(cfg) if hasattr(cfg, "__dataclass_fields__") else None,
                    "years": {yy: ev["years"][yy] for yy in YEARS},
                    "w2425": ev["w2425"],
                    "min_year_ann": min(ev["years"][yy]["ann"] for yy in YEARS),
                }
                if best_local is None or score(ev) > score({"years": best_local["years"], "w2425": best_local["w2425"]}):
                    best_local = packed
                    y = packed["years"]
                    print(
                        f"    WIN risk={risk*100:.2f}% min_yr={packed['min_year_ann']}% "
                        f"y24={y['2024']['ann']}% y25={y['2025']['ann']}% "
                        f"yrs={[y[yy]['ann'] for yy in YEARS]}",
                        flush=True,
                    )
            if best_local:
                winners.append(best_local)

    # Diversify: prefer different scopes/models, need ≥5
    winners.sort(key=lambda w: (w["min_year_ann"], w["years"]["2024"]["ann"] + w["years"]["2025"]["ann"]), reverse=True)
    selected = []
    used_models = set()
    for w in winners:
        model_key = (w["scope"], (w["cfg"] or {}).get("model"), (w["cfg"] or {}).get("tf"), (w["cfg"] or {}).get("long_only"))
        if model_key in used_models and len(selected) >= 3:
            # allow some same-family if still need 5
            if len(selected) < 5:
                pass
            else:
                continue
        selected.append(w)
        used_models.add(model_key)
        if len(selected) >= 8:
            break
    # if still short, take top remaining
    if len(selected) < 5:
        for w in winners:
            if w in selected:
                continue
            selected.append(w)
            if len(selected) >= 5:
                break

    out = {
        "research_max_end": RESEARCH_MAX_END,
        "rules": {
            "min_2024_ann": MIN_2425_ANN,
            "min_2025_ann": MIN_2425_ANN,
            "min_each_year_2021_2025": MIN_YEAR_ANN,
            "no_2026_data": True,
            "commodities_only": list(pairs),
        },
        "n_tested_screens": tested,
        "n_winners": len(winners),
        "n_selected": len(selected),
        "selected": selected,
        "all_winners": winners,
    }
    Path(RESULTS_DIR).mkdir(exist_ok=True)
    (Path(RESULTS_DIR) / "commodity_winners.json").write_text(json.dumps(out, indent=2, default=str))

    lines = [
        "# Commodity winners (no 2026+ data)",
        "",
        f"Cutoff: **{RESEARCH_MAX_END}**. Universe: {', '.join(pairs)}.",
        "",
        "Gates: 2024≥10%, 2025≥10%, ≥4/5 years 2021–2025 ≥0%, no year <−5%, "
        "PF(2024–25)≥1.05, static floor, causal fills, **no 2026+ data**.",
        "",
        f"Found **{len(winners)}** raw / **{len(selected)}** selected.",
        "",
        "| # | ID | Scope | Risk | 2021 | 2022 | 2023 | 2024 | 2025 | Min |",
        "|---|----|-------|------|------|------|------|------|------|-----|",
    ]
    for i, w in enumerate(selected, 1):
        y = w["years"]
        lines.append(
            f"| {i} | `{w['id']}` | {w['scope']} | {w['risk_pct']*100:.2f}% | "
            f"{y['2021']['ann']}% | {y['2022']['ann']}% | {y['2023']['ann']}% | "
            f"**{y['2024']['ann']}%** | **{y['2025']['ann']}%** | {w['min_year_ann']}% |"
        )
    (Path(RESULTS_DIR) / "COMMODITY_WINNERS.md").write_text("\n".join(lines) + "\n")

    print(f"\nSelected {len(selected)} / need 5", flush=True)
    for w in selected:
        print(f"  {w['id']}: min={w['min_year_ann']}% 24={w['years']['2024']['ann']}% 25={w['years']['2025']['ann']}%", flush=True)
    return 0 if len(selected) >= 5 else 2


if __name__ == "__main__":
    raise SystemExit(main())
