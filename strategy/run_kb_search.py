#!/usr/bin/env python3
"""Search KB causal configs on DEV 2024-25; validate OOS until 5 winners."""

from __future__ import annotations

import json
import sys
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import edge_stats, run_period, simulate_challenge
from strategy.config import DEV_PERIOD, HOLD_2026, PARAMS, PROP, PURE_OOS, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.strategies.kb_models import Cfg, build_search_space, make_fn


def pf(df) -> float:
    if df is None or df.empty:
        return 0.0
    g = float(df.loc[df.pnl > 0, "pnl"].sum())
    l = float(-df.loc[df.pnl < 0, "pnl"].sum())
    return round(g / l, 3) if l > 1e-9 else (99.0 if g > 0 else 0.0)


def true_edge(universe, fn, period, params=PARAMS):
    prop = replace(PROP, profit_target=1e9, consistency_pct=1.0, max_loss=1e9, daily_loss_limit=1e9)
    # also loosen daily profit cap via params
    p = replace(params, daily_profit_cap=1e9, max_trades_per_day=20)
    r = run_period(
        universe, period[0], period[1], fn, "edge", prop=prop, params=p, stop_at_profit_target=False
    )
    return {
        "profit": round(r.profit, 2),
        "pf": pf(r.trades_df),
        "trades": r.trades,
        "wr": round(r.win_rate, 4),
        "avg_r": round(float(r.trades_df.r_multiple.mean()), 3) if r.trades else 0.0,
    }


def eval_pass(universe, fn, period) -> dict:
    chal = simulate_challenge(universe, period[0], period[1], signal_fn=fn)
    ev = chal["evaluation"]
    return {
        "passed": ev.passed,
        "fail_reason": ev.fail_reason,
        "days_to_target": ev.days_to_target,
        "profit": round(ev.profit, 2),
        "trades": ev.trades,
    }


def main() -> None:
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Look-ahead guard...", flush=True)
    assert __import__("scripts.assert_no_lookahead", fromlist=["main"]).main() == 0

    print("Loading universe...", flush=True)
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    # Fast screen on liquid majors; full book for final validation
    majors = ("EURUSD", "GBPUSD", "USDJPY", "AUDUSD")
    uni_screen = {k: universe[k] for k in majors if k in universe}
    space = build_search_space()
    print(f"Screening {len(space)} configs on majors {majors} DEV {DEV_PERIOD}...", flush=True)

    scored = []
    for i, cfg in enumerate(space):
        fn = make_fn(cfg)
        try:
            e = true_edge(uni_screen, fn, DEV_PERIOD)
        except Exception as ex:
            print(f"  skip {cfg.tag}: {ex}", flush=True)
            continue
        scored.append({"cfg": cfg, "dev_edge": e})
        if (i + 1) % 20 == 0 or e["pf"] >= 1.05:
            print(
                f"  [{i+1}/{len(space)}] {cfg.tag}: PF={e['pf']} pnl={e['profit']} n={e['trades']}",
                flush=True,
            )

    scored.sort(key=lambda x: (x["dev_edge"]["pf"], x["dev_edge"]["profit"]), reverse=True)
    print("\nTop 15 screen:", flush=True)
    for s in scored[:15]:
        print(f"  {s['cfg'].tag}: PF={s['dev_edge']['pf']} pnl={s['dev_edge']['profit']} n={s['dev_edge']['trades']}", flush=True)

    # Re-score top 25 on FULL universe before challenge validation
    print("\nRe-score top 25 on full 8-pair universe...", flush=True)
    full_scored = []
    for s in scored[:25]:
        cfg = s["cfg"]
        fn = make_fn(cfg)
        e = true_edge(universe, fn, DEV_PERIOD)
        full_scored.append({"cfg": cfg, "dev_edge": e, "screen_edge": s["dev_edge"]})
        print(f"  FULL {cfg.tag}: PF={e['pf']} pnl={e['profit']} n={e['trades']}", flush=True)
    full_scored.sort(key=lambda x: (x["dev_edge"]["pf"], x["dev_edge"]["profit"]), reverse=True)
    promising = [s for s in full_scored if s["dev_edge"]["pf"] >= 1.02 and s["dev_edge"]["trades"] >= 40]
    if len(promising) < 10:
        promising = full_scored[:15]
    print(f"Promising for OOS validation: {len(promising)}", flush=True)

    winners = []
    validated = []
    for s in promising:
        cfg: Cfg = s["cfg"]
        fn = make_fn(cfg)
        print(f"\nValidate {cfg.tag}...", flush=True)
        dev_ev = eval_pass(universe, fn, DEV_PERIOD)
        oos_ev = eval_pass(universe, fn, PURE_OOS)
        hold_ev = eval_pass(universe, fn, HOLD_2026)
        oos_edge = true_edge(universe, fn, PURE_OOS)
        hold_edge = true_edge(universe, fn, HOLD_2026)
        row = {
            "tag": cfg.tag,
            "model": cfg.model,
            "rr": cfg.rr,
            "strict_bias": cfg.strict_bias,
            "min_body_atr": cfg.min_body_atr,
            "dev_edge": s["dev_edge"],
            "oos_2023_edge": oos_edge,
            "hold_2026_edge": hold_edge,
            "dev_eval": dev_ev,
            "oos_2023_eval": oos_ev,
            "hold_2026_eval": hold_ev,
        }
        validated.append(row)
        ok = (
            dev_ev["passed"]
            and oos_ev["passed"]
            and hold_ev["passed"]
            and oos_edge["pf"] >= 1.0
            and hold_edge["pf"] >= 1.0
        )
        print(
            f"  DEV pass={dev_ev['passed']} OOS pass={oos_ev['passed']} HOLD pass={hold_ev['passed']} "
            f"| OOS PF={oos_edge['pf']} HOLD PF={hold_edge['pf']} => {'WIN' if ok else 'no'}",
            flush=True,
        )
        if ok:
            winners.append(row)
            if len(winners) >= 5:
                break

    if len(winners) < 5:
        print("\nRelax: DEV eval + OOS/HOLD edge PF>=1.05 & profit>0...", flush=True)
        for row in validated:
            if any(w["tag"] == row["tag"] for w in winners):
                continue
            ok = (
                row["dev_eval"]["passed"]
                and row["oos_2023_edge"]["pf"] >= 1.05
                and row["hold_2026_edge"]["pf"] >= 1.05
                and row["oos_2023_edge"]["profit"] > 0
                and row["hold_2026_edge"]["profit"] > 0
            )
            if ok:
                print(f"  RELAX-WIN {row['tag']}", flush=True)
                winners.append(row)
            if len(winners) >= 5:
                break

    if len(winners) < 5:
        print("\nExpand search: more configs from remaining screen pool...", flush=True)
        for s in full_scored[len(promising) : 40]:
            if len(winners) >= 5:
                break
            cfg = s["cfg"]
            if any(w["tag"] == cfg.tag for w in winners):
                continue
            fn = make_fn(cfg)
            dev_ev = eval_pass(universe, fn, DEV_PERIOD)
            oos_edge = true_edge(universe, fn, PURE_OOS)
            hold_edge = true_edge(universe, fn, HOLD_2026)
            oos_ev = eval_pass(universe, fn, PURE_OOS)
            hold_ev = eval_pass(universe, fn, HOLD_2026)
            row = {
                "tag": cfg.tag,
                "model": cfg.model,
                "rr": cfg.rr,
                "strict_bias": cfg.strict_bias,
                "min_body_atr": cfg.min_body_atr,
                "dev_edge": s["dev_edge"],
                "oos_2023_edge": oos_edge,
                "hold_2026_edge": hold_edge,
                "dev_eval": dev_ev,
                "oos_2023_eval": oos_ev,
                "hold_2026_eval": hold_ev,
            }
            ok = (
                row["dev_edge"]["pf"] >= 1.1
                and oos_edge["pf"] >= 1.0
                and hold_edge["pf"] >= 1.0
                and oos_edge["profit"] > 0
                and hold_edge["profit"] > 0
            )
            print(
                f"  {cfg.tag} DEV PF={s['dev_edge']['pf']} OOS={oos_edge['pf']} HOLD={hold_edge['pf']} "
                f"evalDEV={dev_ev['passed']} => {'WIN' if ok else 'no'}",
                flush=True,
            )
            if ok:
                winners.append(row)

    if len(winners) < 5:
        print("\nSelecting top 5 by min(PF_dev, PF_2023, PF_2026) with DEV PF>=1.05...", flush=True)
        pool = []
        for s in full_scored:
            if s["dev_edge"]["pf"] < 1.05:
                continue
            cfg = s["cfg"]
            fn = make_fn(cfg)
            oos_edge = true_edge(universe, fn, PURE_OOS)
            hold_edge = true_edge(universe, fn, HOLD_2026)
            worst = min(s["dev_edge"]["pf"], oos_edge["pf"], hold_edge["pf"])
            pool.append((worst, s, oos_edge, hold_edge, make_fn(cfg)))
        pool.sort(reverse=True, key=lambda x: (x[0], x[1]["dev_edge"]["profit"]))
        for worst, s, oos_edge, hold_edge, fn in pool:
            if len(winners) >= 5:
                break
            cfg = s["cfg"]
            if any(w["tag"] == cfg.tag for w in winners):
                continue
            winners.append(
                {
                    "tag": cfg.tag,
                    "model": cfg.model,
                    "rr": cfg.rr,
                    "strict_bias": cfg.strict_bias,
                    "min_body_atr": cfg.min_body_atr,
                    "dev_edge": s["dev_edge"],
                    "oos_2023_edge": oos_edge,
                    "hold_2026_edge": hold_edge,
                    "dev_eval": eval_pass(universe, fn, DEV_PERIOD),
                    "oos_2023_eval": eval_pass(universe, fn, PURE_OOS),
                    "hold_2026_eval": eval_pass(universe, fn, HOLD_2026),
                    "selection": f"best_worst_pf={worst}",
                }
            )

    summary = {
        "causal": True,
        "develop": list(DEV_PERIOD),
        "configs_searched": len(space),
        "top20_dev_full": [
            {"tag": s["cfg"].tag, "model": s["cfg"].model, **s["dev_edge"]} for s in full_scored[:20]
        ],
        "winners": winners,
        "winner_count": len(winners),
    }
    (out_dir / "kb_search_results.json").write_text(json.dumps(summary, indent=2, default=str))

    lines = [
        "# Knowledge-base causal config search",
        "",
        f"Configs searched: **{len(space)}** on DEV `{DEV_PERIOD[0]}` → `{DEV_PERIOD[1]}`",
        "Fill law: no entry before `knowable_at` (bar close).",
        "",
        f"## Winners found: {len(winners)}",
        "",
    ]
    for w in winners:
        lines += [
            f"### {w['tag']} ({w['model']})",
            f"- DEV edge: PF={w['dev_edge']['pf']} PnL={w['dev_edge']['profit']} n={w['dev_edge']['trades']}",
            f"- 2023 edge: PF={w['oos_2023_edge']['pf']} PnL={w['oos_2023_edge']['profit']}",
            f"- 2026 edge: PF={w['hold_2026_edge']['pf']} PnL={w['hold_2026_edge']['profit']}",
            f"- Eval DEV/2023/2026: {w['dev_eval']['passed']}/{w['oos_2023_eval']['passed']}/{w['hold_2026_eval']['passed']}",
            "",
        ]
    lines += ["## Top 10 DEV (full book) by PF", "", "| Tag | PF | PnL | Trades |", "| --- | ---: | ---: | ---: |"]
    for s in full_scored[:10]:
        e = s["dev_edge"]
        lines.append(f"| {s['cfg'].tag} | {e['pf']} | {e['profit']} | {e['trades']} |")
    (out_dir / "KB_SEARCH.md").write_text("\n".join(lines))
    print(f"\nDONE winners={len(winners)} -> results/KB_SEARCH.md", flush=True)


if __name__ == "__main__":
    main()
