#!/usr/bin/env python3
"""Search causal retail indicator strategies for ~25% CAGR (2020–2025).

Early filter: 2020–22 PF>=1.05 & profit>0, then score full/late/2026.
No look-ahead fills (knowable_at = M15 close).
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
from strategy.run_cagr25_search import (
    DEV_2425,
    FULL_2020_2025,
    TEST_LATE,
    TRAIN_EARLY,
    pd_years,
    pf,
)
from strategy.strategies.retail_models import RetailCfg, build_retail_space, make_fn


def params_for(cfg: RetailCfg):
    return replace(
        PARAMS,
        risk_pct=cfg.risk_pct,
        flatten_hour_utc=cfg.flatten_hour_utc,
        move_to_be=cfg.move_to_be,
        daily_profit_cap=1e9,
        max_trades_per_day=20,
        max_trades_per_pair_day=5,
        max_open_positions=5,
        cooldown_bars_after_trade=0,
    )


def edge(universe, fn, period, cfg: RetailCfg):
    prop = replace(
        PROP,
        profit_target=1e9,
        consistency_pct=1.0,
        max_loss=1e9,
        daily_loss_limit=1e9,
    )
    r = run_period(
        universe,
        period[0],
        period[1],
        fn,
        "e",
        prop=prop,
        params=params_for(cfg),
        stop_at_profit_target=False,
    )
    years = pd_years(period[0], period[1])
    profit = round(r.profit, 2)
    total_ret = profit / PROP.initial_balance
    cagr = (1 + total_ret) ** (1 / years) - 1 if years > 0 and total_ret > -0.999 else float("nan")
    simple_ann = total_ret / years if years else 0.0
    return {
        "profit": profit,
        "pf": pf(r.trades_df),
        "trades": r.trades,
        "wr": round(r.win_rate, 4),
        "max_dd": round(r.max_dd, 2),
        "years": round(years, 3),
        "cagr_pct": round(cagr * 100, 2),
        "simple_ann_pct": round(simple_ann * 100, 2),
    }


def make_portfolio(cfgs: list[RetailCfg]):
    fns = [(c, make_fn(c)) for c in cfgs]

    def _fn(pair, m15, params=PARAMS):
        out, seen = [], set()
        for c, fn in fns:
            for s in fn(pair, m15, params):
                key = (s.time, s.pair, s.side, round(s.entry, 5))
                if key in seen:
                    continue
                seen.add(key)
                out.append(s)
        out.sort(key=lambda s: s.time)
        return out

    return _fn


def main() -> int:
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    print("Loading universe...", flush=True)
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    cfgs = build_retail_space()
    print(f"Retail early-first screen: {len(cfgs)} configs...", flush=True)

    early_ok = []
    scored_all = []
    for i, cfg in enumerate(cfgs):
        fn = make_fn(cfg)
        try:
            e = edge(universe, fn, TRAIN_EARLY, cfg)
        except Exception as ex:
            print("skip", cfg.tag, ex, flush=True)
            continue
        scored_all.append((e["simple_ann_pct"], e["pf"], e, cfg))
        if (i + 1) % 15 == 0 or (e["pf"] >= 1.1 and e["simple_ann_pct"] >= 5):
            print(
                f"[{i+1}/{len(cfgs)}] {cfg.tag} early ann={e['simple_ann_pct']}% "
                f"PF={e['pf']} n={e['trades']}",
                flush=True,
            )
        if e["pf"] >= 1.05 and e["profit"] > 0 and e["trades"] >= 40:
            early_ok.append((e["simple_ann_pct"], e["pf"], e, cfg))

    early_ok.sort(key=lambda x: (x[0], x[1]), reverse=True)
    scored_all.sort(key=lambda x: (x[0], x[1]), reverse=True)
    print(f"\n{len(early_ok)} early PF>=1.05. Top early:", flush=True)
    for ann, pf_, e, cfg in early_ok[:20]:
        print(
            f"  {cfg.tag}: ann={e['simple_ann_pct']}% PF={e['pf']} n={e['trades']} dd={e['max_dd']}",
            flush=True,
        )
    if not early_ok:
        print("\nNo early hits — top early by ann anyway:", flush=True)
        for ann, pf_, e, cfg in scored_all[:15]:
            print(
                f"  {cfg.tag}: ann={e['simple_ann_pct']}% PF={e['pf']} n={e['trades']}",
                flush=True,
            )

    print("\nValidate candidates on late/full/DEV/2026...", flush=True)
    # Prefer early_ok; if few, also take best early ann among PF>=1.0
    pool = list(early_ok[:30])
    if len(pool) < 15:
        for row in scored_all:
            if row[3].tag in {c.tag for _, _, _, c in pool}:
                continue
            if row[1] >= 1.0 and row[2]["trades"] >= 40:
                pool.append(row)
            if len(pool) >= 25:
                break

    rows = []
    for ann, pf_, e0, cfg in pool:
        fn = make_fn(cfg)
        late = edge(universe, fn, TEST_LATE, cfg)
        full = edge(universe, fn, FULL_2020_2025, cfg)
        hold = edge(universe, fn, HOLD_2026, cfg)
        dev = edge(universe, fn, DEV_2425, cfg)
        row = {
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
            f"  {cfg.tag}: full CAGR={full['cagr_pct']}% ann={full['simple_ann_pct']}% "
            f"PF={full['pf']} | late PF={late['pf']} ann={late['simple_ann_pct']}% "
            f"| DEV ann={dev['simple_ann_pct']}% | 2026 PF={hold['pf']}",
            flush=True,
        )

    stable = [
        r
        for r in rows
        if r["early"]["pf"] >= 1.05
        and r["late"]["pf"] >= 1.05
        and r["early"]["profit"] > 0
        and r["late"]["profit"] > 0
    ]
    stable.sort(key=lambda r: r["full"]["cagr_pct"], reverse=True)

    ports = []
    if len(stable) >= 2:
        print(f"\n{len(stable)} stable. Building retail portfolios...", flush=True)
        sleeves = []
        for r in stable[:5]:
            c = r["cfg"]
            sleeves.append(RetailCfg(**{k: v for k, v in c.items()}))
        for k in (2, 3, min(4, len(sleeves))):
            fn = make_portfolio(sleeves[:k])
            shell = replace(sleeves[0], tag=f"RPORT{k}", risk_pct=0.010)
            full = edge(universe, fn, FULL_2020_2025, shell)
            early = edge(universe, fn, TRAIN_EARLY, shell)
            late = edge(universe, fn, TEST_LATE, shell)
            hold = edge(universe, fn, HOLD_2026, shell)
            ports.append(
                {
                    "tag": shell.tag,
                    "sleeves": [s.tag for s in sleeves[:k]],
                    "early": early,
                    "late": late,
                    "full": full,
                    "hold": hold,
                }
            )
            print(
                f"  RPORT{k}: full CAGR={full['cagr_pct']}% PF={full['pf']} n={full['trades']} "
                f"| early PF={early['pf']} late PF={late['pf']} | 2026 PF={hold['pf']}",
                flush=True,
            )

    all_ranked = sorted(
        [{"kind": "single", **r} for r in rows] + [{"kind": "port", **r} for r in ports],
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
        "family": "retail_indicators",
        "screened": len(cfgs),
        "early_pass": len(early_ok),
        "stable": len(stable),
        "near_25": near25,
        "best15": all_ranked[:15],
        "stable_top": stable[:10],
        "ports": ports,
        "top_early_raw": [
            {"tag": c.tag, "model": c.model, **e} for _, _, e, c in scored_all[:20]
        ],
    }
    (out_dir / "retail_search.json").write_text(json.dumps(summary, indent=2, default=str))

    lines = [
        "# Retail indicator search (causal) — aiming ~25%/yr",
        "",
        "Models: EMA cross, EMA+RSI, Bollinger+RSI, Donchian, MACD, Supertrend, Stoch, VWAP fade.",
        "Risk **1%**. No look-ahead. Early filter **2020–22 PF≥1.05**.",
        "",
        f"Screened **{len(cfgs)}**; early-pass **{len(early_ok)}**; stable early+late **{len(stable)}**.",
        "",
        "## Near ≥20% full CAGR (stable)",
        "",
    ]
    if not near25:
        lines.append("_None._")
    for r in near25[:8]:
        f = r["full"]
        lines.append(
            f"- **{r['tag']}**: CAGR **{f['cagr_pct']}%**, PF={f['pf']}, n={f['trades']}"
        )
    lines += ["", "## Best by full 2020–25 CAGR", ""]
    for r in all_ranked[:12]:
        f, e, l = r["full"], r["early"], r["late"]
        flag = "STABLE" if e["pf"] >= 1.05 and l["pf"] >= 1.05 else "fragile"
        lines.append(
            f"- `{r['tag']}` ({r.get('model', r.get('kind'))}) [{flag}]: "
            f"CAGR **{f['cagr_pct']}%** (ann {f['simple_ann_pct']}%, PF {f['pf']}, "
            f"n={f['trades']}, dd=${f['max_dd']:,.0f}) | "
            f"early PF {e['pf']} ann {e['simple_ann_pct']}% | "
            f"late PF {l['pf']} ann {l['simple_ann_pct']}% | "
            f"2026 PF {r['hold']['pf']}"
        )
    lines += ["", "## Verdict", ""]
    if near25:
        lines.append(f"Found {len(near25)} retail config(s) near/above 20% with stable PF.")
    elif stable:
        f = stable[0]["full"]
        lines.append(
            f"Best stable retail CAGR **{f['cagr_pct']}%** (`{stable[0]['tag']}`). "
            f"Still short of ~25%/yr under causal fills."
        )
    else:
        lines.append(
            "No retail config kept PF≥1.05 in both 2020–22 and 2023–25 in this grid."
        )
    (out_dir / "RETAIL_SEARCH.md").write_text("\n".join(lines) + "\n")
    print("\nWrote results/retail_search.json and RETAIL_SEARCH.md", flush=True)
    if near25:
        print("NEAR 25% FOUND (retail)")
    elif stable:
        print(f"BEST STABLE RETAIL CAGR={stable[0]['full']['cagr_pct']}%")
    else:
        print("NO STABLE RETAIL EDGE IN GRID")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
