#!/usr/bin/env python3
"""Causal H1 Donchian / EMA trend search (multi-day hold, 1% risk)."""
from __future__ import annotations

import json
import sys
from dataclasses import dataclass, replace, asdict
from pathlib import Path
from typing import Callable, List

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period
from strategy.config import HOLD_2026, PARAMS, PROP, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import FULL_2020_2025, TEST_LATE, TRAIN_EARLY, pd_years, pf
from strategy.strategies.h1_models import H1Cfg, make_fn


def space() -> List[H1Cfg]:
    out = []
    for rr in (2.0, 3.0, 4.0):
        for don in (10, 20, 40):
            for hold in (3, 5, 8):
                out.append(
                    H1Cfg(
                        tag=f"DONH1_rr{rr}_n{don}_h{hold}",
                        model="don_h1",
                        rr=rr,
                        don_len=don,
                        max_hold_days=hold,
                        stop_atr=2.0,
                        session_only=True,
                    )
                )
        for ef, es in ((8, 21), (12, 48)):
            out.append(
                H1Cfg(
                    tag=f"EMAH1_rr{rr}_{ef}_{es}",
                    model="ema_h1",
                    rr=rr,
                    ema_fast=ef,
                    ema_slow=es,
                    max_hold_days=5,
                    stop_atr=2.0,
                    session_only=True,
                )
            )
    return out


def params_for(cfg: H1Cfg):
    return replace(
        PARAMS,
        risk_pct=cfg.risk_pct,
        move_to_be=cfg.move_to_be,
        max_hold_days=cfg.max_hold_days,
        flatten_hour_utc=cfg.flatten_hour_utc,
        daily_profit_cap=1e9,
        max_trades_per_day=8,
        max_trades_per_pair_day=2,
        cooldown_bars_after_trade=0,
    )


def edge(universe, fn, period, cfg):
    prop = replace(PROP, profit_target=1e9, consistency_pct=1.0, max_loss=1e9, daily_loss_limit=1e9)
    r = run_period(universe, period[0], period[1], fn, "e", prop=prop, params=params_for(cfg), stop_at_profit_target=False)
    years = pd_years(period[0], period[1])
    profit = round(r.profit, 2)
    total_ret = profit / PROP.initial_balance
    cagr = (1 + total_ret) ** (1 / years) - 1 if years > 0 and total_ret > -0.999 else float("nan")
    return {
        "profit": profit,
        "pf": pf(r.trades_df),
        "trades": r.trades,
        "wr": round(r.win_rate, 4),
        "max_dd": round(r.max_dd, 2),
        "cagr_pct": round(cagr * 100, 2),
        "simple_ann_pct": round((total_ret / years) * 100, 2) if years else 0.0,
    }


def main() -> int:
    out_dir = ROOT / RESULTS_DIR
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    cfgs = space()
    print(f"H1 trend search {len(cfgs)}", flush=True)
    early_ok, scored = [], []
    for i, cfg in enumerate(cfgs):
        e = edge(universe, make_fn(cfg), TRAIN_EARLY, cfg)
        scored.append((e["simple_ann_pct"], e["pf"], e, cfg))
        if (i + 1) % 8 == 0 or e["pf"] >= 1.15:
            print(f"[{i+1}/{len(cfgs)}] {cfg.tag} ann={e['simple_ann_pct']}% PF={e['pf']} n={e['trades']}", flush=True)
        if e["pf"] >= 1.05 and e["profit"] > 0 and e["trades"] >= 30:
            early_ok.append((e["simple_ann_pct"], e, cfg))
    early_ok.sort(reverse=True, key=lambda x: x[0])
    print(f"Early OK {len(early_ok)}", flush=True)
    pool = early_ok[:12] or [(a, e, c) for a, _, e, c in sorted(scored, key=lambda x: (x[1], x[0]), reverse=True)[:10]]
    rows = []
    for ann, e0, cfg in pool:
        late = edge(universe, make_fn(cfg), TEST_LATE, cfg)
        full = edge(universe, make_fn(cfg), FULL_2020_2025, cfg)
        hold = edge(universe, make_fn(cfg), HOLD_2026, cfg)
        rows.append({"tag": cfg.tag, "cfg": asdict(cfg), "early": e0, "late": late, "full": full, "hold": hold})
        print(f"  {cfg.tag}: full CAGR={full['cagr_pct']}% PF={full['pf']} late PF={late['pf']} 2026 PF={hold['pf']}", flush=True)
    stable = [r for r in rows if r["early"]["pf"] >= 1.05 and r["late"]["pf"] >= 1.05]
    stable.sort(key=lambda r: r["full"]["cagr_pct"], reverse=True)
    best = sorted(rows, key=lambda r: r["full"]["cagr_pct"], reverse=True)
    summary = {"causal": True, "family": "h1_trend", "early_ok": len(early_ok), "stable": len(stable), "best": best[:12], "stable_top": stable[:8]}
    (out_dir / "h1_trend_search.json").write_text(json.dumps(summary, indent=2, default=str))
    lines = ["# H1 trend retail search (causal)", "", f"Early OK {len(early_ok)}; stable {len(stable)}.", "", "## Best", ""]
    for r in best[:10]:
        f, e, l = r["full"], r["early"], r["late"]
        flag = "STABLE" if e["pf"] >= 1.05 and l["pf"] >= 1.05 else "fragile"
        lines.append(f"- `{r['tag']}` [{flag}]: CAGR **{f['cagr_pct']}%** PF {f['pf']} | early {e['pf']} | late {l['pf']}")
    if stable:
        lines.append(f"\nBest stable **{stable[0]['full']['cagr_pct']}%** (`{stable[0]['tag']}`).")
    else:
        lines.append("\nNo stable H1 trend edge.")
    (out_dir / "H1_TREND_SEARCH.md").write_text("\n".join(lines) + "\n")
    print("Wrote H1_TREND_SEARCH.md", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
