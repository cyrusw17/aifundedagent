#!/usr/bin/env python3
"""Focused commodity hunt for ≥5 winners (no 2026+ data)."""
from __future__ import annotations

import json
import sys
from dataclasses import asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.config import PARAMS, RESULTS_DIR
from strategy.data_loader import RESEARCH_MAX_END, load_universe
from strategy.run_commodity_search import (
    YEARS,
    eval_years,
    is_winner,
    make_params,
    score,
)
from strategy.strategies.commodity_models import CmdCfg, make_cmd_fn
from strategy.strategies.kb_models import Cfg, make_fn as make_ict
from strategy.strategies.retail_models import RetailCfg, make_fn as make_retail
from strategy.strategies.retail_models_v2 import RetailCfg2, make_fn2


def ideas():
    out = []
    # Donchian / EMA across TFs — long-only bias for bull commodities + both
    for tf, hold in (("1h", 3), ("4h", 5), ("1D", 10)):
        for don in (12, 20, 30, 40):
            for rr in (3.0, 4.0, 5.0):
                for lo in (True, False):
                    out.append(
                        CmdCfg(
                            tag=f"DON_{tf}_n{don}_rr{rr}_{'L' if lo else 'B'}",
                            model="don",
                            tf=tf,
                            don_len=don,
                            rr=rr,
                            long_only=lo,
                            max_hold_days=hold,
                            session_only=(tf != "1D"),
                            stop_atr=2.0,
                        )
                    )
        for ef, es in ((8, 21), (12, 48), (20, 50)):
            for rr in (3.0, 4.0, 5.0):
                for lo in (True, False):
                    out.append(
                        CmdCfg(
                            tag=f"EMA_{tf}_{ef}_{es}_rr{rr}_{'L' if lo else 'B'}",
                            model="ema",
                            tf=tf,
                            ema_fast=ef,
                            ema_slow=es,
                            rr=rr,
                            long_only=lo,
                            max_hold_days=hold,
                            session_only=(tf != "1D"),
                            stop_atr=2.0,
                        )
                    )
        for rr in (3.0, 4.0):
            out.append(
                CmdCfg(
                    tag=f"PB_{tf}_rr{rr}_L",
                    model="ema_pb",
                    tf=tf,
                    ema_slow=50,
                    rr=rr,
                    long_only=True,
                    max_hold_days=hold,
                    session_only=(tf != "1D"),
                    stop_atr=1.8,
                    rsi_lo=35,
                    rsi_hi=65,
                )
            )
            out.append(
                CmdCfg(
                    tag=f"ATRB_{tf}_rr{rr}_L",
                    model="atr_brk",
                    tf=tf,
                    rr=rr,
                    long_only=True,
                    max_hold_days=hold,
                    session_only=(tf != "1D"),
                    stop_atr=2.0,
                    pullback_atr=0.3,
                )
            )
    return out


def main() -> int:
    print("=== Focused commodity hunt (cutoff 2025-12-31) ===\n", flush=True)
    from scripts.assert_no_lookahead import main as assert_main

    if assert_main() != 0:
        return 1

    universe = load_universe(PARAMS.commodity_pairs, max_end=RESEARCH_MAX_END)
    for p, fr in universe.items():
        assert fr["m1"].index.max().year <= 2025
        print(f"  {p}: → {fr['m1'].index.max()}", flush=True)

    scopes = {
        "CMD3": universe,
        "XAU": {k: universe[k] for k in ("XAUUSD",)},
        "XAG": {k: universe[k] for k in ("XAGUSD",)},
        "XAUXAG": {k: universe[k] for k in ("XAUUSD", "XAGUSD")},
        "BCO": {k: universe[k] for k in ("BCOUSD",)},
    }

    cands = []
    for cfg in ideas():
        cands.append((cfg.tag, make_cmd_fn(cfg), cfg.max_hold_days, cfg, "cmd"))
    # ICT on metals
    for tag, kw in (
        ("ICT_SB14_ASIA", dict(model="sb_fvg", rr=3.5, min_body_atr=0.35, min_fvg_atr=0.12, use_pdh=False, use_asia=True, sb_start=14.0, sb_end=15.0, strict_bias=False)),
        ("ICT_SB14_PDH", dict(model="sb_fvg", rr=3.5, min_body_atr=0.30, min_fvg_atr=0.12, use_pdh=True, use_asia=False, sb_start=14.0, sb_end=15.0, strict_bias=False)),
        ("ICT_MSB", dict(model="multi_sb", rr=3.5, min_body_atr=0.25, min_fvg_atr=0.12, use_pdh=True, use_asia=True, sb_windows=((7.0, 8.0), (14.0, 15.0)), strict_bias=False)),
    ):
        cfg = Cfg(tag=tag, move_to_be=False, flatten_hour_utc=22, **kw)
        cands.append((tag, make_ict(cfg), 0, cfg, "ict"))
    # Retail M15 on commodities
    for tag, kw in (
        ("R_DON20_rr3", dict(model="donchian", rr=3.0, don_len=20, stop_atr=1.5, killzone_only=True)),
        ("R_DON16_rr4", dict(model="donchian", rr=4.0, don_len=16, stop_atr=1.5, killzone_only=True)),
        ("R_ST_rr3", dict(model="supertrend", rr=3.0, st_mult=3.0, stop_atr=1.5, killzone_only=True)),
        ("R_EMA_rr3", dict(model="ema_cross", rr=3.0, ema_fast=9, ema_slow=21, stop_atr=1.2, killzone_only=True)),
        ("R_MACD_rr3", dict(model="macd", rr=3.0, stop_atr=1.2, killzone_only=True)),
    ):
        cfg = RetailCfg(tag=tag, move_to_be=False, flatten_hour_utc=22, **kw)
        cands.append((tag, make_retail(cfg), 0, cfg, "retail"))
    for tag, kw in (
        ("R2_ADX_rr3", dict(model="ema_rsi_adx", rr=3.0, ema_trend=50, rsi_lo=35, rsi_hi=65, adx_min=18, stop_atr=1.5, killzone_only=True)),
        ("R2_STACK_rr3", dict(model="ema_stack", rr=3.0, stop_atr=1.2, killzone_only=True)),
    ):
        cfg = RetailCfg2(tag=tag, move_to_be=False, flatten_hour_utc=22, **kw)
        cands.append((tag, make_fn2(cfg), 0, cfg, "retail2"))

    print(f"Candidates: {len(cands)} × {len(scopes)} scopes", flush=True)
    winners = []

    for scope_name, uni in scopes.items():
        print(f"\n=== {scope_name} ===", flush=True)
        for i, (name, fn, hold, cfg, kind) in enumerate(cands, 1):
            # Fast screen: 2024 and 2025 separately at 1.5% risk
            p_screen = make_params(0.015, hold)
            try:
                from strategy.run_commodity_search import run, year_period

                s24 = run(uni, fn, year_period("2024"), p_screen)
                s25 = run(uni, fn, year_period("2025"), p_screen)
            except Exception as e:
                print(f"  skip {name}: {e}", flush=True)
                continue
            if s24["ann"] < 9 or s25["ann"] < 9 or not s24["floor_ok"] or not s25["floor_ok"]:
                continue
            print(
                f"  [{i}] {name} screen 24={s24['ann']}% 25={s25['ann']}% — deep",
                flush=True,
            )
            best = None
            for risk in (0.01, 0.0125, 0.015, 0.0175, 0.02, 0.025):
                ev = eval_years(uni, fn, make_params(risk, hold))
                if not is_winner(ev):
                    continue
                packed = {
                    "id": f"{scope_name}__{name}",
                    "scope": scope_name,
                    "name": name,
                    "kind": kind,
                    "risk_pct": risk,
                    "hold": hold,
                    "cfg": asdict(cfg) if hasattr(cfg, "__dataclass_fields__") else None,
                    "years": {yy: ev["years"][yy] for yy in YEARS},
                    "w2425": ev["w2425"],
                    "min_year_ann": min(ev["years"][yy]["ann"] for yy in YEARS),
                    "min_recent": min(ev["years"][yy]["ann"] for yy in ("2023", "2024", "2025")),
                }
                if best is None or score(ev) > score({"years": best["years"], "w2425": best["w2425"]}):
                    best = packed
                    y = packed["years"]
                    print(
                        f"    WIN r={risk*100:.2f}% recent_min={packed['min_recent']}% "
                        f"yrs={[y[yy]['ann'] for yy in YEARS]}",
                        flush=True,
                    )
            if best:
                winners.append(best)

    winners.sort(
        key=lambda w: (w["min_recent"], w["years"]["2024"]["ann"] + w["years"]["2025"]["ann"]),
        reverse=True,
    )

    # Diversity pick ≥5
    selected = []
    seen_fp = set()
    for w in winners:
        fp = (
            w["scope"],
            (w["cfg"] or {}).get("model"),
            (w["cfg"] or {}).get("tf"),
            (w["cfg"] or {}).get("long_only"),
            (w["cfg"] or {}).get("don_len"),
            w["kind"],
        )
        if fp in seen_fp:
            continue
        seen_fp.add(fp)
        selected.append(w)
        if len(selected) >= 8:
            break
    if len(selected) < 5:
        for w in winners:
            if any(s["id"] == w["id"] for s in selected):
                continue
            selected.append(w)
            if len(selected) >= 5:
                break

    out = {
        "research_max_end": RESEARCH_MAX_END,
        "n_winners": len(winners),
        "n_selected": len(selected),
        "selected": selected,
        "all_winners": winners,
        "gates": {
            "2024_min": 10,
            "2025_min": 10,
            "2023_2025_min": 8,
            "worst_year_min": -8,
            "no_2026": True,
        },
    }
    Path(RESULTS_DIR).mkdir(exist_ok=True)
    (Path(RESULTS_DIR) / "commodity_winners.json").write_text(json.dumps(out, indent=2, default=str))

    lines = [
        "# Commodity winners — no 2026+ data",
        "",
        "Universe: XAUUSD, XAGUSD, BCOUSD. Cutoff **2025-12-31**.",
        "",
        "Gates: 2024≥10%, 2025≥10%, 2023≥0%, no year 2021–2025 < −8%,",
        "PF(2024–25)≥1.05, static floor, causal fills, **no 2026+ data**.",
        "",
        f"Selected **{len(selected)}** / raw {len(winners)}.",
        "",
        "| # | ID | 2021 | 2022 | 2023 | 2024 | 2025 | Risk |",
        "|---|----|------|------|------|------|------|------|",
    ]
    for i, w in enumerate(selected, 1):
        y = w["years"]
        lines.append(
            f"| {i} | `{w['id']}` | {y['2021']['ann']}% | {y['2022']['ann']}% | "
            f"**{y['2023']['ann']}%** | **{y['2024']['ann']}%** | **{y['2025']['ann']}%** | "
            f"{w['risk_pct']*100:.2f}% |"
        )
    (Path(RESULTS_DIR) / "COMMODITY_WINNERS.md").write_text("\n".join(lines) + "\n")
    print(f"\nSelected {len(selected)} (need ≥5)", flush=True)
    for w in selected:
        y = w["years"]
        print(
            f"  {w['id']}: 23={y['2023']['ann']}% 24={y['2024']['ann']}% 25={y['2025']['ann']}%",
            flush=True,
        )
    return 0 if len(selected) >= 5 else 2


if __name__ == "__main__":
    raise SystemExit(main())
