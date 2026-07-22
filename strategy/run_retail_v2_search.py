#!/usr/bin/env python3
"""Retail v2 search: ADX/H1/CCI/ROC/EMA-stack + optional single-pair focus."""
from __future__ import annotations

import json
import sys
from dataclasses import asdict, replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.config import HOLD_2026, PARAMS, PROP, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import DEV_2425, FULL_2020_2025, TEST_LATE, TRAIN_EARLY
from strategy.run_retail_search import edge, params_for
from strategy.strategies.retail_models_v2 import RetailCfg2, build_retail_v2_space, make_fn2


def main() -> int:
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    # Screen on majors+XAU for speed; deep-validate hits also on all8 / xau-only
    universes = {
        "majors": load_universe(("EURUSD", "GBPUSD", "USDJPY", "XAUUSD"), data_dir=ROOT / "data" / "raw"),
        "xau": load_universe(("XAUUSD",), data_dir=ROOT / "data" / "raw"),
        "all8": load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw"),
    }
    cfgs = build_retail_v2_space()
    screen_names = ("majors", "xau")
    print(f"Retail v2: {len(cfgs)} configs × screen {screen_names}", flush=True)

    early_hits = []
    scored = []
    for uname in screen_names:
        universe = universes[uname]
        print(f"\n=== Universe {uname} ===", flush=True)
        for i, cfg in enumerate(cfgs):
            fn = make_fn2(cfg)
            try:
                e = edge(universe, fn, TRAIN_EARLY, cfg)
            except Exception as ex:
                print("skip", cfg.tag, ex, flush=True)
                continue
            scored.append((uname, e["simple_ann_pct"], e["pf"], e, cfg))
            if (i + 1) % 15 == 0 or (e["pf"] >= 1.1 and e["simple_ann_pct"] >= 5):
                print(
                    f"[{uname} {i+1}/{len(cfgs)}] {cfg.tag} ann={e['simple_ann_pct']}% "
                    f"PF={e['pf']} n={e['trades']}",
                    flush=True,
                )
            if e["pf"] >= 1.05 and e["profit"] > 0 and e["trades"] >= 25:
                early_hits.append((uname, e["simple_ann_pct"], e, cfg))

    early_hits.sort(key=lambda x: x[1], reverse=True)
    print(f"\nEarly hits: {len(early_hits)}", flush=True)
    for uname, ann, e, cfg in early_hits[:25]:
        print(
            f"  [{uname}] {cfg.tag}: ann={ann}% PF={e['pf']} n={e['trades']}",
            flush=True,
        )

    # Validate top hits + top scored if few hits
    pool = list(early_hits[:20])
    if len(pool) < 12:
        scored.sort(key=lambda x: (x[2], x[1]), reverse=True)
        for uname, ann, pf_, e, cfg in scored:
            if any(cfg.tag == c.tag and uname == u for u, _, _, c in pool):
                continue
            if pf_ >= 1.0 and e["trades"] >= 25:
                pool.append((uname, ann, e, cfg))
            if len(pool) >= 18:
                break

    rows = []
    print("\nDeep validate...", flush=True)
    for uname, ann, e0, cfg in pool:
        universe = universes[uname]
        fn = make_fn2(cfg)
        late = edge(universe, fn, TEST_LATE, cfg)
        full = edge(universe, fn, FULL_2020_2025, cfg)
        hold = edge(universe, fn, HOLD_2026, cfg)
        dev = edge(universe, fn, DEV_2425, cfg)
        row = {
            "universe": uname,
            "tag": cfg.tag,
            "model": cfg.model,
            "cfg": asdict(cfg),
            "early": e0,
            "late": late,
            "full": full,
            "hold": hold,
            "dev2425": dev,
        }
        rows.append(row)
        print(
            f"  [{uname}] {cfg.tag}: full CAGR={full['cagr_pct']}% PF={full['pf']} "
            f"| late PF={late['pf']} ann={late['simple_ann_pct']}% "
            f"| DEV ann={dev['simple_ann_pct']}% | 2026 PF={hold['pf']}",
            flush=True,
        )

    stable = [
        r
        for r in rows
        if r["early"]["pf"] >= 1.05 and r["late"]["pf"] >= 1.05 and r["full"]["profit"] > 0
    ]
    stable.sort(key=lambda r: r["full"]["cagr_pct"], reverse=True)
    near25 = [
        r
        for r in stable
        if r["full"]["cagr_pct"] >= 20
    ]
    best = sorted(rows, key=lambda r: r["full"]["cagr_pct"], reverse=True)[:15]

    summary = {
        "causal": True,
        "family": "retail_v2",
        "screened_per_universe": len(cfgs),
        "early_hits": len(early_hits),
        "stable": len(stable),
        "near_25": near25,
        "stable_top": stable[:10],
        "best15": best,
    }
    (out_dir / "retail_v2_search.json").write_text(json.dumps(summary, indent=2, default=str))

    lines = [
        "# Retail v2 search (ADX / H1 / CCI / ROC / EMA stack)",
        "",
        "Causal fills only. Risk 1%. Universes: all8, majors, XAU-only.",
        "",
        f"Early hits: **{len(early_hits)}**. Stable early+late: **{len(stable)}**.",
        "",
        "## Near ≥20% CAGR stable",
        "",
    ]
    if not near25:
        lines.append("_None._")
    for r in near25[:8]:
        lines.append(
            f"- [{r['universe']}] **{r['tag']}**: CAGR {r['full']['cagr_pct']}%"
        )
    lines += ["", "## Best full CAGR", ""]
    for r in best[:12]:
        f, e, l = r["full"], r["early"], r["late"]
        flag = "STABLE" if e["pf"] >= 1.05 and l["pf"] >= 1.05 else "fragile"
        lines.append(
            f"- [{r['universe']}] `{r['tag']}` [{flag}]: CAGR **{f['cagr_pct']}%** "
            f"PF {f['pf']} n={f['trades']} | early PF {e['pf']} | late PF {l['pf']} | "
            f"2026 PF {r['hold']['pf']}"
        )
    lines += ["", "## Verdict", ""]
    if near25:
        lines.append("Retail v2 found near-25% stable config(s).")
    elif stable:
        lines.append(
            f"Best stable retail v2 CAGR **{stable[0]['full']['cagr_pct']}%** "
            f"(`{stable[0]['tag']}` / {stable[0]['universe']})."
        )
    else:
        lines.append("No stable retail v2 edge across early+late in this grid.")
    (out_dir / "RETAIL_V2_SEARCH.md").write_text("\n".join(lines) + "\n")
    print("Wrote RETAIL_V2_SEARCH.md", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
