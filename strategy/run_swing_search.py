#!/usr/bin/env python3
"""Search causal daily swing retail strategies (multi-day hold, 1% risk)."""
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
from strategy.strategies.swing_retail import SwingCfg, build_swing_space, make_swing_fn


def params_for(cfg: SwingCfg):
    return replace(
        PARAMS,
        risk_pct=cfg.risk_pct,
        flatten_hour_utc=cfg.flatten_hour_utc,
        move_to_be=cfg.move_to_be,
        max_hold_days=cfg.max_hold_days,
        daily_profit_cap=1e9,
        max_trades_per_day=5,
        max_trades_per_pair_day=2,
        cooldown_bars_after_trade=0,
    )


def edge(universe, fn, period, cfg: SwingCfg):
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
    out_dir.mkdir(parents=True, exist_ok=True)
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    cfgs = build_swing_space()
    print(f"Swing search {len(cfgs)} configs (max_hold_days enabled)...", flush=True)

    early_ok = []
    scored = []
    for i, cfg in enumerate(cfgs):
        fn = make_swing_fn(cfg)
        e = edge(universe, fn, TRAIN_EARLY, cfg)
        scored.append((e["simple_ann_pct"], e["pf"], e, cfg))
        if (i + 1) % 5 == 0 or e["pf"] >= 1.1:
            print(
                f"[{i+1}/{len(cfgs)}] {cfg.tag} early ann={e['simple_ann_pct']}% "
                f"PF={e['pf']} n={e['trades']}",
                flush=True,
            )
        if e["pf"] >= 1.05 and e["profit"] > 0 and e["trades"] >= 20:
            early_ok.append((e["simple_ann_pct"], e, cfg))

    early_ok.sort(key=lambda x: x[0], reverse=True)
    scored.sort(key=lambda x: (x[1], x[0]), reverse=True)
    print(f"Early OK: {len(early_ok)}", flush=True)

    pool = early_ok[:15] or [(e["simple_ann_pct"], e, c) for _, _, e, c in scored[:10]]
    rows = []
    for ann, e0, cfg in pool:
        fn = make_swing_fn(cfg)
        late = edge(universe, fn, TEST_LATE, cfg)
        full = edge(universe, fn, FULL_2020_2025, cfg)
        hold = edge(universe, fn, HOLD_2026, cfg)
        row = {
            "tag": cfg.tag,
            "model": cfg.model,
            "cfg": asdict(cfg),
            "early": e0,
            "late": late,
            "full": full,
            "hold": hold,
        }
        rows.append(row)
        print(
            f"  {cfg.tag}: full CAGR={full['cagr_pct']}% PF={full['pf']} "
            f"| late PF={late['pf']} | 2026 PF={hold['pf']}",
            flush=True,
        )

    stable = [r for r in rows if r["early"]["pf"] >= 1.05 and r["late"]["pf"] >= 1.05]
    stable.sort(key=lambda r: r["full"]["cagr_pct"], reverse=True)
    near = [r for r in stable if r["full"]["cagr_pct"] >= 20]
    best = sorted(rows, key=lambda r: r["full"]["cagr_pct"], reverse=True)

    summary = {
        "causal": True,
        "family": "swing_daily_retail",
        "screened": len(cfgs),
        "early_ok": len(early_ok),
        "stable": len(stable),
        "near_25": near,
        "best": best[:12],
        "stable_top": stable[:8],
    }
    (out_dir / "swing_search.json").write_text(json.dumps(summary, indent=2, default=str))
    lines = [
        "# Swing daily retail search (causal, multi-day hold)",
        "",
        "Donchian / EMA / RSI on daily bars from M15. `max_hold_days` holds (no same-day flatten).",
        f"Screened {len(cfgs)}; early OK {len(early_ok)}; stable {len(stable)}.",
        "",
        "## Near 20%+",
        "_None_" if not near else "",
    ]
    for r in near[:5]:
        lines.append(f"- **{r['tag']}**: CAGR {r['full']['cagr_pct']}%")
    lines += ["", "## Best", ""]
    for r in best[:10]:
        f, e, l = r["full"], r["early"], r["late"]
        flag = "STABLE" if e["pf"] >= 1.05 and l["pf"] >= 1.05 else "fragile"
        lines.append(
            f"- `{r['tag']}` [{flag}]: CAGR **{f['cagr_pct']}%** PF {f['pf']} "
            f"| early {e['pf']} | late {l['pf']} | 2026 {r['hold']['pf']}"
        )
    if stable:
        lines.append(
            f"\nBest stable swing CAGR **{stable[0]['full']['cagr_pct']}%** (`{stable[0]['tag']}`)."
        )
    else:
        lines.append("\nNo stable swing edge in this grid.")
    (out_dir / "SWING_SEARCH.md").write_text("\n".join(lines) + "\n")
    print("Wrote SWING_SEARCH.md", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
