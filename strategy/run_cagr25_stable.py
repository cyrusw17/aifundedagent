#!/usr/bin/env python3
"""Find ~25% CAGR with STABLE causal edge: require 2020-22 PF>=1.05 first.

No look-ahead. Risk up to 1%. Report honest full 2020-25 CAGR.
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict, replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period
from strategy.config import HOLD_2026, PARAMS, PROP, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.strategies.kb_models import Cfg, make_fn
from strategy.run_cagr25_search import (
    FULL_2020_2025,
    TEST_LATE,
    TRAIN_EARLY,
    DEV_2425,
    edge,
    make_portfolio,
    params_for,
)


def space_stable() -> list[Cfg]:
    """~90 configs: quality SB + reject/sweep, 1% risk."""
    out: list[Cfg] = []
    for rr in (3.0, 3.5):
        for body in (0.35, 0.45):
            for fvg in (0.12, 0.18):
                for wins, wtag, model in (
                    (((14.0, 15.0),), "w14", "sb_fvg"),
                    (((7.0, 8.0),), "w7", "sb_fvg"),
                    (((7.0, 8.0), (14.0, 15.0)), "w714", "multi_sb"),
                ):
                    for use_pdh, use_asia, lt in (
                        (True, False, "P"),
                        (False, True, "A"),
                        (True, True, "PA"),
                    ):
                        out.append(
                            Cfg(
                                tag=f"Q_MSB_rr{rr}_b{body}_f{fvg}_{lt}_{wtag}",
                                model=model,
                                rr=rr,
                                min_body_atr=body,
                                min_fvg_atr=fvg,
                                sb_start=wins[0][0],
                                sb_end=wins[0][1],
                                sb_windows=wins,
                                strict_bias=False,
                                move_to_be=False,
                                risk_pct=0.010,
                                flatten_hour_utc=22,
                                use_pdh=use_pdh,
                                use_asia=use_asia,
                            )
                        )
    for rr in (2.5, 3.0):
        for body in (0.40, 0.55):
            out.append(
                Cfg(
                    tag=f"Q_RJ_rr{rr}_b{body}",
                    model="reject_mkt",
                    rr=rr,
                    min_body_atr=body,
                    strict_bias=False,
                    move_to_be=False,
                    risk_pct=0.010,
                    flatten_hour_utc=22,
                    use_pdh=True,
                    use_asia=True,
                )
            )
            out.append(
                Cfg(
                    tag=f"Q_SFVG_rr{rr}_b{body}",
                    model="sweep_fvg",
                    rr=rr,
                    min_body_atr=body,
                    min_fvg_atr=0.15,
                    strict_bias=False,
                    move_to_be=False,
                    risk_pct=0.010,
                    flatten_hour_utc=22,
                    use_pdh=True,
                    use_asia=True,
                )
            )
    for rr in (3.0, 3.5):
        for body in (0.35, 0.45):
            for strict in (True, False):
                out.append(
                    Cfg(
                        tag=f"Q_SB14_rr{rr}_b{body}_{'S' if strict else 'L'}",
                        model="sb_fvg",
                        rr=rr,
                        sb_start=14.0,
                        sb_end=15.0,
                        min_body_atr=body,
                        min_fvg_atr=0.15,
                        strict_bias=strict,
                        move_to_be=False,
                        risk_pct=0.010,
                        flatten_hour_utc=22,
                        use_pdh=True,
                        use_asia=True,
                    )
                )
    return out


def main() -> int:
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    print("Loading universe...", flush=True)
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    cfgs = space_stable()
    print(f"Early-first screen: {len(cfgs)} configs on 2020-22...", flush=True)

    early_ok = []
    for i, cfg in enumerate(cfgs):
        # Force multi_sb when multiple windows even if model said sb_fvg
        if len(cfg.sb_windows) > 1:
            cfg = replace(cfg, model="multi_sb")
        fn = make_fn(cfg)
        try:
            e = edge(universe, fn, TRAIN_EARLY, cfg)
        except Exception as ex:
            print("skip", cfg.tag, ex, flush=True)
            continue
        if (i + 1) % 25 == 0 or (e["pf"] >= 1.1 and e["simple_ann_pct"] >= 8):
            print(
                f"[{i+1}/{len(cfgs)}] {cfg.tag} early ann={e['simple_ann_pct']}% "
                f"PF={e['pf']} n={e['trades']}",
                flush=True,
            )
        if e["pf"] >= 1.05 and e["profit"] > 0 and e["trades"] >= 40:
            early_ok.append((e["simple_ann_pct"], e["pf"], e, cfg))

    early_ok.sort(key=lambda x: (x[0], x[1]), reverse=True)
    print(f"\n{len(early_ok)} passed early PF>=1.05. Top early:", flush=True)
    for ann, pf_, e, cfg in early_ok[:20]:
        print(
            f"  {cfg.tag}: ann={e['simple_ann_pct']}% PF={e['pf']} n={e['trades']} dd={e['max_dd']}",
            flush=True,
        )

    print("\nValidate early-passers on late/full/2026...", flush=True)
    rows = []
    for ann, pf_, e0, cfg in early_ok[:35]:
        if len(cfg.sb_windows) > 1:
            cfg = replace(cfg, model="multi_sb")
        fn = make_fn(cfg)
        late = edge(universe, fn, TEST_LATE, cfg)
        full = edge(universe, fn, FULL_2020_2025, cfg)
        hold = edge(universe, fn, HOLD_2026, cfg)
        dev = edge(universe, fn, DEV_2425, cfg)
        row = {
            "tag": cfg.tag,
            "cfg": {k: (list(v) if k == "sb_windows" else v) for k, v in asdict(cfg).items()},
            "early": e0,
            "late": late,
            "full": full,
            "hold": hold,
            "dev2425": dev,
        }
        rows.append(row)
        print(
            f"  {cfg.tag}: full CAGR={full['cagr_pct']}% ann={full['simple_ann_pct']}% "
            f"PF={full['pf']} | late PF={late['pf']} ann={late['simple_ann_pct']}% "
            f"| DEV24-25 ann={dev['simple_ann_pct']}% | 2026 PF={hold['pf']}",
            flush=True,
        )

    # Portfolios of top stable (early+late PF>=1.05)
    stable = [
        r
        for r in rows
        if r["late"]["pf"] >= 1.05 and r["late"]["profit"] > 0 and r["full"]["pf"] >= 1.05
    ]
    stable.sort(key=lambda r: r["full"]["cagr_pct"], reverse=True)
    print(f"\n{len(stable)} stable across early+late. Building portfolios...", flush=True)

    ports = []
    if len(stable) >= 2:
        sleeves_src = []
        for r in stable[:5]:
            c = r["cfg"]
            sleeves_src.append(
                Cfg(
                    tag=c["tag"],
                    model=c["model"] if len(c.get("sb_windows") or []) <= 1 else "multi_sb",
                    rr=c["rr"],
                    min_body_atr=c["min_body_atr"],
                    min_fvg_atr=c["min_fvg_atr"],
                    strict_bias=c["strict_bias"],
                    use_pdh=c["use_pdh"],
                    use_asia=c["use_asia"],
                    move_to_be=c["move_to_be"],
                    risk_pct=0.010,
                    flatten_hour_utc=c["flatten_hour_utc"],
                    sb_start=c.get("sb_start", 14.0),
                    sb_end=c.get("sb_end", 15.0),
                    sb_windows=tuple(tuple(x) for x in c["sb_windows"])
                    if c.get("sb_windows")
                    else ((14.0, 15.0),),
                )
            )
        for k in (2, 3, min(4, len(sleeves_src))):
            sleeves = sleeves_src[:k]
            # 1% per trade still (user OK); more trades from blend
            fn = make_portfolio(sleeves)
            shell = replace(sleeves[0], tag=f"PORT{k}", risk_pct=0.010)
            full = edge(universe, fn, FULL_2020_2025, shell)
            early = edge(universe, fn, TRAIN_EARLY, shell)
            late = edge(universe, fn, TEST_LATE, shell)
            hold = edge(universe, fn, HOLD_2026, shell)
            ports.append(
                {
                    "tag": shell.tag,
                    "sleeves": [s.tag for s in sleeves],
                    "early": early,
                    "late": late,
                    "full": full,
                    "hold": hold,
                }
            )
            print(
                f"  PORT{k}: full CAGR={full['cagr_pct']}% ann={full['simple_ann_pct']}% "
                f"PF={full['pf']} n={full['trades']} | early PF={early['pf']} "
                f"late PF={late['pf']} | 2026 PF={hold['pf']}",
                flush=True,
            )

    all_ranked = sorted(
        [{"kind": "single", **r} for r in rows]
        + [{"kind": "port", **r} for r in ports],
        key=lambda r: r["full"]["cagr_pct"],
        reverse=True,
    )
    near25 = [
        r
        for r in all_ranked
        if r["full"]["cagr_pct"] >= 20
        and r["early"]["pf"] >= 1.05
        and r["late"]["pf"] >= 1.05
    ]

    summary = {
        "target_cagr_pct": 25,
        "causal": True,
        "method": "early-first (2020-22 PF>=1.05), then late/full",
        "screened": len(cfgs),
        "early_pass": len(early_ok),
        "stable_early_late": len(stable),
        "near_25": near25,
        "best15": all_ranked[:15],
        "stable_top": stable[:10],
        "ports": ports,
    }
    (out_dir / "cagr25_stable.json").write_text(json.dumps(summary, indent=2, default=str))

    lines = [
        "# Stable CAGR search (causal) — aiming ~25%/yr",
        "",
        "Filter: **2020–22 PF ≥ 1.05** before trusting 2024–25 prints.",
        "Risk **1%** of initial. No look-ahead fills.",
        "",
        f"Screened {len(cfgs)}; early-pass {len(early_ok)}; stable early+late {len(stable)}.",
        "",
        "## Near ≥20% full CAGR with split-sample edge",
        "",
    ]
    if not near25:
        lines.append("_None._")
    for r in near25[:8]:
        f = r["full"]
        lines.append(
            f"- **{r['tag']}**: full CAGR **{f['cagr_pct']}%**, PF={f['pf']}, n={f['trades']}"
        )
    lines += ["", "## Best by full 2020–25 CAGR (stable or not)", ""]
    for r in all_ranked[:12]:
        f, e, l = r["full"], r["early"], r["late"]
        flag = "STABLE" if e["pf"] >= 1.05 and l["pf"] >= 1.05 else "fragile"
        lines.append(
            f"- `{r['tag']}` [{flag}]: CAGR **{f['cagr_pct']}%** (ann {f['simple_ann_pct']}%, "
            f"PF {f['pf']}, n={f['trades']}, dd=${f['max_dd']:,.0f}) | "
            f"early PF {e['pf']} ann {e['simple_ann_pct']}% | "
            f"late PF {l['pf']} ann {l['simple_ann_pct']}% | "
            f"2026 PF {r['hold']['pf']}"
        )
    best_stable = stable[0] if stable else None
    lines += ["", "## Verdict", ""]
    if near25:
        lines.append(f"Found {len(near25)} config(s) near/above 20% with stable PF.")
    elif best_stable:
        f = best_stable["full"]
        lines.append(
            f"Under causal fills + early/late stability, best realistic CAGR is about "
            f"**{f['cagr_pct']}%**/yr (`{best_stable['tag']}`, 1% risk). "
            f"Hitting a **stable ~25%** looks unlikely with these ICT/SMC session models "
            f"on HistData — 2024–25 alone can print ~25% but 2020–22 usually does not confirm."
        )
    else:
        lines.append(
            "No config kept PF≥1.05 in both 2020–22 and 2023–25 at 1% risk in this grid."
        )
    (out_dir / "CAGR25_STABLE.md").write_text("\n".join(lines) + "\n")
    print("\nWrote results/cagr25_stable.json and CAGR25_STABLE.md", flush=True)
    if near25:
        print("NEAR 25% FOUND")
    elif best_stable:
        print(f"BEST STABLE CAGR={best_stable['full']['cagr_pct']}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
