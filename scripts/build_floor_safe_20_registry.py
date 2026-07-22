#!/usr/bin/env python3
"""Build floor_safe_20 registry from results/floor_safe_20.json with diversity caps."""
from __future__ import annotations

import json
import textwrap
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / "results" / "floor_safe_20.json").read_text())

# Prefer distinct logic: raise caps just enough to reach 20 from verified pool
CAPS = {
    "h1_don": 5,   # different Donchian lengths
    "h1_ema": 2,
    "ict_sb": 5,   # PDH / Asia / body variants
    "retail": 5,   # ema_rsi / adx / don / roc
    "swing": 4,    # daily don / ema variants
    "ict_other": 3,
    "classic": 3,
}

# Prefer these ids when breaking ties inside a family (seed + model diversity)
PREFER = [
    "A1_H1Don_n35_rr5",
    "A2_H1Don_n30_rr4",
    "A3_H1Don_n40_rr4",
    "A4_ICT_MSB_PA",
    "A5_ICT_MSB_ASIA",
    "H1EMA_12_48_rr4_h3",
    "H1Don_n55_rr4_h3",  # longer channel + hold
    "R2_EMA_ADX_rr25",
    "R2_ROC_rr25",
    "R_ema_rsi_rr20_100_30_70_12",
    "R_donchian_rr20_20_12",
    "DonD_n40_rr30_h10",
    "DonD_n20_rr4_h8",
    "EmaD_20_50_rr25_h5",
    "FS_W4_SB14_ASIA_r6",
]


def fam(w):
    f = w["family"]
    if f.startswith("retail"):
        return "retail"
    if f.startswith("swing"):
        return "swing"
    return f


def score(w):
    pref = 0
    if w["id"] in PREFER:
        pref = 100 - PREFER.index(w["id"])
    f = w["full"]
    return (pref, f["profit"], f["pf"], -f["max_dd"])


def select(n=20):
    winners = sorted(DATA["all_winners"], key=score, reverse=True)
    selected = []
    counts = Counter()
    for w in winners:
        f = fam(w)
        if counts[f] >= CAPS.get(f, 3):
            continue
        # avoid near-identical ann/dd twins unless preferred seed
        twin = False
        for s in selected:
            if fam(s) != f:
                continue
            if abs(s["full"]["simple_ann_pct"] - w["full"]["simple_ann_pct"]) < 0.12:
                if abs(s["full"]["max_dd"] - w["full"]["max_dd"]) < 120 and w["id"] not in PREFER:
                    twin = True
                    break
        if twin:
            continue
        selected.append(w)
        counts[f] += 1
        if len(selected) >= n:
            break
    # fill remainder without twin filter if still short
    if len(selected) < n:
        have = {x["id"] for x in selected}
        for w in winners:
            if w["id"] in have:
                continue
            f = fam(w)
            if counts[f] >= CAPS.get(f, 3) + 1:
                continue
            selected.append(w)
            counts[f] += 1
            have.add(w["id"])
            if len(selected) >= n:
                break
    return selected


def clean_id(w):
    """Stable public id."""
    i = w["id"]
    if i.startswith("sb_fvg_rr30"):
        return "SB14_PDH_rr30_b35"
    if i.startswith("sb_fvg_rr25"):
        return "SB14_PDH_rr25_b40"
    if i.startswith("DonD_n40_rr30"):
        return "DonD_n40_rr3_h10"
    if i.startswith("EmaD_20_50_rr25"):
        return "EmaD_20_50_rr25_h5"
    return i


def emit_registry(selected):
    # Rebuild callable configs
    lines = [
        '"""Twenty prop-floor-safe causal strategies (The5ers $6k floor).',
        "",
        "Fills only after knowable_at. PROP: never hit $94k; max_dd <= $6k.",
        'Generated from results/floor_safe_20.json — do not hand-edit params lightly.',
        '"""',
        "from __future__ import annotations",
        "",
        "from dataclasses import replace",
        "from typing import Callable, Dict, Optional",
        "",
        "from ..config import PARAMS, StrategyParams",
        "from .h1_models import H1Cfg, make_fn as make_h1",
        "from .kb_models import Cfg, make_fn as make_ict",
        "from .retail_models import RetailCfg, make_fn as make_retail",
        "from .retail_models_v2 import RetailCfg2, make_fn2",
        "from .swing_retail import SwingCfg, make_swing_fn",
        "",
        "HALTS: Dict[str, float] = {}",
        "HOLDS: Dict[str, int] = {}",
        "RISKS: Dict[str, float] = {}",
        "STRATEGIES: Dict[str, Callable] = {}",
        "STRATEGY_DESC: Dict[str, str] = {}",
        "META: Dict[str, dict] = {}",
        "",
    ]

    # We'll build registration via a data-driven block executed at import
    regs = []
    for w in selected:
        cid = clean_id(w)
        cfg = w.get("cfg")
        kind = w.get("kind") or ""
        family = fam(w)
        # Infer kind from cfg/model if missing
        if cfg is None:
            # shouldn't happen for selected
            continue
        model = cfg.get("model", "")
        regs.append(
            {
                "id": cid,
                "orig": w["id"],
                "family": family,
                "kind": kind,
                "model": model,
                "cfg": cfg,
                "risk": w["risk_pct"],
                "halt": w["dd_halt"],
                "hold": w["max_hold_days"],
                "ann": w["full"]["simple_ann_pct"],
                "dd": w["full"]["max_dd"],
                "pf": w["full"]["pf"],
            }
        )

    body = ["def _register():"]
    body.append("    global HALTS, HOLDS, RISKS, STRATEGIES, STRATEGY_DESC, META")
    for r in regs:
        cid = r["id"]
        cfg = r["cfg"]
        model = r["model"]
        body.append(f"    # --- {cid} ({r['family']}) ann={r['ann']}% dd=${r['dd']:.0f} ---")
        if model in ("don_h1", "ema_h1"):
            body.append(f"    cfg = H1Cfg(")
            body.append(f"        tag={cid!r}, model={model!r}, rr={cfg['rr']},")
            if model == "don_h1":
                body.append(f"        don_len={cfg['don_len']},")
            else:
                body.append(f"        ema_fast={cfg['ema_fast']}, ema_slow={cfg['ema_slow']},")
            body.append(
                f"        max_hold_days={r['hold']}, stop_atr={cfg.get('stop_atr', 2.0)}, "
                f"session_only={cfg.get('session_only', True)}, risk_pct={r['risk']},"
            )
            body.append(f"        flatten_hour_utc={cfg.get('flatten_hour_utc', 22)}, move_to_be={cfg.get('move_to_be', False)},")
            body.append(f"    )")
            body.append(f"    STRATEGIES[{cid!r}] = make_h1(cfg)")
        elif model in ("sb_fvg", "multi_sb", "reject_mkt", "orb", "bos_pullback", "sweep_fvg"):
            # Cfg fields
            keys = [
                "rr", "min_body_atr", "min_fvg_atr", "use_pdh", "use_asia", "strict_bias",
                "sb_start", "sb_end", "orb_end", "sb_windows", "flatten_hour_utc", "move_to_be",
            ]
            parts = [f"tag={cid!r}", f"model={model!r}", f"risk_pct={r['risk']}"]
            for k in keys:
                if k in cfg and cfg[k] is not None:
                    parts.append(f"{k}={cfg[k]!r}")
            body.append(f"    cfg = Cfg({', '.join(parts)})")
            body.append(f"    STRATEGIES[{cid!r}] = make_ict(cfg)")
        elif model in ("ema_rsi_adx", "cci_fade", "roc_break", "ema_stack"):
            parts = [f"tag={cid!r}", f"model={model!r}", f"risk_pct={r['risk']}"]
            for k in ("rr", "stop_atr", "ema_trend", "rsi_lo", "rsi_hi", "adx_min", "killzone_only", "use_h1_bias", "flatten_hour_utc", "move_to_be"):
                if k in cfg:
                    parts.append(f"{k}={cfg[k]!r}")
            body.append(f"    cfg = RetailCfg2({', '.join(parts)})")
            body.append(f"    STRATEGIES[{cid!r}] = make_fn2(cfg)")
        elif model in ("ema_cross", "ema_rsi", "donchian", "macd", "supertrend", "bb_rsi", "stoch_rsi", "vwap_reversion"):
            parts = [f"tag={cid!r}", f"model={model!r}", f"risk_pct={r['risk']}"]
            for k in ("rr", "stop_atr", "ema_fast", "ema_slow", "ema_trend", "rsi_lo", "rsi_hi", "don_len", "bb_std", "st_mult", "vwap_z", "killzone_only", "flatten_hour_utc", "move_to_be"):
                if k in cfg:
                    parts.append(f"{k}={cfg[k]!r}")
            body.append(f"    cfg = RetailCfg({', '.join(parts)})")
            body.append(f"    STRATEGIES[{cid!r}] = make_retail(cfg)")
        elif model in ("don_daily", "ema_daily", "rsi_daily"):
            parts = [f"tag={cid!r}", f"model={model!r}", f"rr={cfg['rr']}", f"max_hold_days={r['hold']}", f"flatten_hour_utc={cfg.get('flatten_hour_utc', 23)}"]
            for k in ("don_len", "ema_fast", "ema_slow", "stop_atr_mult"):
                if k in cfg:
                    parts.append(f"{k}={cfg[k]!r}")
            body.append(f"    cfg = SwingCfg({', '.join(parts)})")
            body.append(f"    STRATEGIES[{cid!r}] = make_swing_fn(cfg)")
        else:
            body.append(f"    raise RuntimeError('unknown model for {cid}: {model}')")

        body.append(f"    HALTS[{cid!r}] = {r['halt']}")
        body.append(f"    HOLDS[{cid!r}] = {r['hold']}")
        body.append(f"    RISKS[{cid!r}] = {r['risk']}")
        body.append(
            f"    STRATEGY_DESC[{cid!r}] = "
            f"'{r['family']} {model}, floor-safe risk {r['risk']*100:.2f}%, halt ${r['halt']:,.0f}, "
            f"ann~{r['ann']:.1f}%, dd~${r['dd']:.0f}'"
        )
        body.append(
            f"    META[{cid!r}] = {{'family': {r['family']!r}, 'ann': {r['ann']}, 'max_dd': {r['dd']}, 'pf': {r['pf']}}}"
        )
        body.append("")

    body.append("_register()")
    body.append("")
    body.append("def prop_params_for(name: str) -> StrategyParams:")
    body.append("    return replace(")
    body.append("        PARAMS,")
    body.append("        risk_pct=RISKS[name],")
    body.append("        max_hold_days=HOLDS[name],")
    body.append("        dd_halt=HALTS[name],")
    body.append("        flatten_hour_utc=22,")
    body.append("        move_to_be=False,")
    body.append("        daily_profit_cap=2_500.0,")
    body.append("        max_trades_per_day=3,")
    body.append("        max_trades_per_pair_day=1,")
    body.append("        max_open_positions=1,")
    body.append("        cooldown_bars_after_trade=1,")
    body.append("    )")
    body.append("")

    path = ROOT / "strategy" / "strategies" / "floor_safe_20.py"
    path.write_text("\n".join(lines + body) + "\n")
    return path, [clean_id(w) for w in selected], selected


def main():
    selected = select(20)
    path, ids, sel = emit_registry(selected)
    # update json selected + md
    DATA["selected"] = sel
    DATA["n_selected"] = len(sel)
    DATA["public_ids"] = ids
    (ROOT / "results" / "floor_safe_20.json").write_text(json.dumps(DATA, indent=2, default=str))
    md = [
        "# Twenty prop-floor-safe causal winners",
        "",
        "Rules: The5ers **$6k** static floor, **$3k** daily, soft `dd_halt`, fills after `knowable_at`.",
        "",
        f"Pool **{DATA['n_winners_raw']}** verified → **{len(sel)}** diverse selected.",
        "",
        "| # | ID | Family | Max DD | Ann | PF | n | Risk | Halt |",
        "|---|----|--------|--------|-----|----|---|------|------|",
    ]
    for i, w in enumerate(sel, 1):
        f = w["full"]
        md.append(
            f"| {i} | `{clean_id(w)}` | {fam(w)} | ${f['max_dd']:,.0f} | {f['simple_ann_pct']}% | "
            f"{f['pf']} | {f['trades']} | {w['risk_pct']*100:.2f}% | ${w['dd_halt']:,.0f} |"
        )
    md += [
        "",
        "## Families",
        "",
        "```",
        str(dict(Counter(fam(w) for w in sel))),
        "```",
        "",
        "## Guards",
        "",
        "```bash",
        "python3 scripts/assert_no_lookahead.py",
        "python3 scripts/confirm_floor_safe_20.py",
        "```",
        "",
        "Registry: `strategy/strategies/floor_safe_20.py`",
        "",
    ]
    (ROOT / "results" / "FLOOR_SAFE_20.md").write_text("\n".join(md))
    print(f"Wrote {path} with {len(ids)} strategies")
    print("families", dict(Counter(fam(w) for w in sel)))
    for i, w in enumerate(sel, 1):
        print(f"{i:2d} {clean_id(w)}")


if __name__ == "__main__":
    main()
