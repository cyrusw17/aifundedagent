#!/usr/bin/env python3
"""Curated commodity winners — fast path to ≥5 (no 2026+)."""
from __future__ import annotations

import json
import sys
from dataclasses import asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.config import PARAMS, RESULTS_DIR
from strategy.data_loader import RESEARCH_MAX_END, load_universe
from strategy.run_commodity_search import YEARS, eval_years, is_winner, make_params
from strategy.strategies.commodity_models import CmdCfg, make_cmd_fn


CURATED = [
    CmdCfg(tag="DON_4h_n20_rr5_L", model="don", tf="4h", don_len=20, rr=5.0, long_only=True, max_hold_days=5, session_only=True, stop_atr=2.0),
    CmdCfg(tag="DON_4h_n20_rr4_L", model="don", tf="4h", don_len=20, rr=4.0, long_only=True, max_hold_days=5, session_only=True, stop_atr=2.0),
    CmdCfg(tag="DON_4h_n30_rr5_L", model="don", tf="4h", don_len=30, rr=5.0, long_only=True, max_hold_days=5, session_only=True, stop_atr=2.0),
    CmdCfg(tag="DON_4h_n12_rr5_L", model="don", tf="4h", don_len=12, rr=5.0, long_only=True, max_hold_days=5, session_only=True, stop_atr=2.0),
    CmdCfg(tag="DON_1h_n20_rr5_L", model="don", tf="1h", don_len=20, rr=5.0, long_only=True, max_hold_days=3, session_only=True, stop_atr=2.0),
    CmdCfg(tag="DON_1h_n35_rr5_L", model="don", tf="1h", don_len=35, rr=5.0, long_only=True, max_hold_days=3, session_only=True, stop_atr=2.0),
    CmdCfg(tag="DON_1D_n20_rr4_L", model="don", tf="1D", don_len=20, rr=4.0, long_only=True, max_hold_days=10, session_only=False, stop_atr=2.0),
    CmdCfg(tag="EMA_4h_12_48_rr5_L", model="ema", tf="4h", ema_fast=12, ema_slow=48, rr=5.0, long_only=True, max_hold_days=5, session_only=True, stop_atr=2.0),
    CmdCfg(tag="EMA_4h_8_21_rr4_L", model="ema", tf="4h", ema_fast=8, ema_slow=21, rr=4.0, long_only=True, max_hold_days=5, session_only=True, stop_atr=2.0),
    CmdCfg(tag="EMA_1h_12_48_rr5_L", model="ema", tf="1h", ema_fast=12, ema_slow=48, rr=5.0, long_only=True, max_hold_days=3, session_only=True, stop_atr=2.0),
    CmdCfg(tag="PB_4h_rr4_L", model="ema_pb", tf="4h", ema_slow=50, rr=4.0, long_only=True, max_hold_days=5, session_only=True, stop_atr=1.8, rsi_lo=35, rsi_hi=65),
    CmdCfg(tag="ATRB_4h_rr4_L", model="atr_brk", tf="4h", rr=4.0, long_only=True, max_hold_days=5, session_only=True, stop_atr=2.0, pullback_atr=0.3),
    CmdCfg(tag="DON_4h_n20_rr5_B", model="don", tf="4h", don_len=20, rr=5.0, long_only=False, max_hold_days=5, session_only=True, stop_atr=2.0),
    CmdCfg(tag="DON_1h_n20_rr4_B", model="don", tf="1h", don_len=20, rr=4.0, long_only=False, max_hold_days=3, session_only=True, stop_atr=2.0),
]


def main() -> int:
    print("=== Curated commodity winners ===\n", flush=True)
    universe = load_universe(PARAMS.commodity_pairs, max_end=RESEARCH_MAX_END)
    scopes = {
        "XAU": {k: universe[k] for k in ("XAUUSD",)},
        "XAG": {k: universe[k] for k in ("XAGUSD",)},
        "XAUXAG": {k: universe[k] for k in ("XAUUSD", "XAGUSD")},
        "CMD3": universe,
    }
    winners = []
    for scope_name, uni in scopes.items():
        print(f"--- {scope_name} ---", flush=True)
        for cfg in CURATED:
            fn = make_cmd_fn(cfg)
            best = None
            for risk in (0.008, 0.01, 0.0125, 0.015, 0.02):
                ev = eval_years(uni, fn, make_params(risk, cfg.max_hold_days))
                if not is_winner(ev):
                    continue
                packed = {
                    "id": f"{scope_name}__{cfg.tag}",
                    "scope": scope_name,
                    "name": cfg.tag,
                    "risk_pct": risk,
                    "hold": cfg.max_hold_days,
                    "cfg": asdict(cfg),
                    "years": {yy: ev["years"][yy] for yy in YEARS},
                    "w2425": ev["w2425"],
                    "min_year_ann": min(ev["years"][yy]["ann"] for yy in YEARS),
                }
                if best is None or packed["years"]["2024"]["ann"] + packed["years"]["2025"]["ann"] > best["years"]["2024"]["ann"] + best["years"]["2025"]["ann"]:
                    best = packed
            if best:
                y = best["years"]
                print(
                    f"  WIN {best['id']} r={best['risk_pct']*100:.1f}% "
                    f"21={y['2021']['ann']} 22={y['2022']['ann']} 23={y['2023']['ann']} "
                    f"24={y['2024']['ann']} 25={y['2025']['ann']}",
                    flush=True,
                )
                winners.append(best)

    # diversify by (scope, model, tf, don_len/ema)
    selected = []
    fps = set()
    winners.sort(key=lambda w: w["years"]["2024"]["ann"] + w["years"]["2025"]["ann"], reverse=True)
    for w in winners:
        c = w["cfg"]
        fp = (w["scope"], c["model"], c["tf"], c.get("don_len"), c.get("ema_fast"), c.get("long_only"))
        if fp in fps:
            continue
        fps.add(fp)
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

    Path(RESULTS_DIR).mkdir(exist_ok=True)
    payload = {
        "research_max_end": RESEARCH_MAX_END,
        "n_winners": len(winners),
        "n_selected": len(selected),
        "selected": selected,
        "all_winners": winners,
    }
    (Path(RESULTS_DIR) / "commodity_winners.json").write_text(json.dumps(payload, indent=2, default=str))
    lines = [
        "# Commodity winners (no 2026+ data)",
        "",
        "Universe: gold / silver / Brent. **No bars after 2025-12-31.**",
        "",
        "Gates: **2024≥10%**, **2025≥10%**, 2023≥0%, no year 2021–25 < −8%, PF≥1.05, static floor, causal.",
        "",
        f"Selected **{len(selected)}**.",
        "",
        "| # | ID | 2021 | 2022 | 2023 | 2024 | 2025 | Risk |",
        "|---|----|------|------|------|------|------|------|",
    ]
    for i, w in enumerate(selected, 1):
        y = w["years"]
        lines.append(
            f"| {i} | `{w['id']}` | {y['2021']['ann']}% | {y['2022']['ann']}% | {y['2023']['ann']}% | "
            f"**{y['2024']['ann']}%** | **{y['2025']['ann']}%** | {w['risk_pct']*100:.1f}% |"
        )
    (Path(RESULTS_DIR) / "COMMODITY_WINNERS.md").write_text("\n".join(lines) + "\n")
    print(f"\nSelected {len(selected)}", flush=True)
    return 0 if len(selected) >= 5 else 2


if __name__ == "__main__":
    raise SystemExit(main())
