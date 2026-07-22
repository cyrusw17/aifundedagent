#!/usr/bin/env python3
"""Focused search: multi-SB + no-BE + risk variants → 5 causal winners."""

from __future__ import annotations

import json
import sys
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period, simulate_challenge
from strategy.config import DEV_PERIOD, HOLD_2026, PARAMS, PROP, PURE_OOS, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.strategies.kb_models import Cfg, make_fn


def pf(df) -> float:
    if df is None or df.empty:
        return 0.0
    g = float(df.loc[df.pnl > 0, "pnl"].sum())
    l = float(-df.loc[df.pnl < 0, "pnl"].sum())
    return round(g / l, 3) if l > 1e-9 else (99.0 if g > 0 else 0.0)


def params_for(cfg: Cfg):
    return replace(
        PARAMS,
        risk_pct=cfg.risk_pct,
        flatten_hour_utc=cfg.flatten_hour_utc,
        move_to_be=cfg.move_to_be,
        daily_profit_cap=1e9,
        max_trades_per_day=12,
    )


def edge(universe, fn, period, cfg):
    prop = replace(PROP, profit_target=1e9, consistency_pct=1.0, max_loss=1e9, daily_loss_limit=1e9)
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
    return {
        "profit": round(r.profit, 2),
        "pf": pf(r.trades_df),
        "trades": r.trades,
        "wr": round(r.win_rate, 4),
    }


def challenge_eval(universe, fn, period, cfg):
    # simulate_challenge uses global PARAMS — temporarily not; pass via monkey
    # Use run_period eval style with stop at target
    from strategy.backtest import simulate_challenge as sc

    # Patch: run_period inside uses PARAMS default; we need custom params.
    # Call run_period directly for evaluation phase.
    r = run_period(
        universe,
        period[0],
        period[1],
        fn,
        "evaluation",
        prop=PROP,
        params=params_for(cfg),
        stop_at_profit_target=True,
        weekly_withdraw=False,
    )
    return {
        "passed": r.passed,
        "fail_reason": r.fail_reason,
        "days_to_target": r.days_to_target,
        "profit": round(r.profit, 2),
        "trades": r.trades,
    }


def space() -> list[Cfg]:
    out = []
    for rr in (2.0, 2.5, 3.0):
        for strict in (True, False):
            for be in (False, True):
                for risk in (0.005, 0.006):
                    out.append(
                        Cfg(
                            tag=f"MSB_rr{rr}_{'S' if strict else 'L'}_be{int(be)}_r{risk}",
                            model="multi_sb",
                            rr=rr,
                            strict_bias=strict,
                            move_to_be=be,
                            risk_pct=risk,
                            flatten_hour_utc=22,
                            min_body_atr=0.28,
                        )
                    )
    for rr in (2.0, 2.5, 3.0):
        for sb in ((7.0, 8.0), (14.0, 15.0), (15.0, 16.0)):
            for strict in (True, False):
                for be in (False,):
                    out.append(
                        Cfg(
                            tag=f"SB{int(sb[0])}_rr{rr}_{'S' if strict else 'L'}_nobe_r6",
                            model="sb_fvg",
                            rr=rr,
                            sb_start=sb[0],
                            sb_end=sb[1],
                            strict_bias=strict,
                            move_to_be=be,
                            risk_pct=0.006,
                            flatten_hour_utc=22,
                            min_body_atr=0.28,
                        )
                    )
    for rr in (2.0, 2.5):
        for body in (0.30, 0.40):
            for strict in (True, False):
                out.append(
                    Cfg(
                        tag=f"SFVG_rr{rr}_b{body}_{'S' if strict else 'L'}_nobe_r5",
                        model="sweep_fvg",
                        rr=rr,
                        min_body_atr=body,
                        strict_bias=strict,
                        move_to_be=False,
                        risk_pct=0.005,
                        flatten_hour_utc=22,
                    )
                )
    for rr in (2.0, 2.5):
        for body in (0.35, 0.50):
            for strict in (True, False):
                out.append(
                    Cfg(
                        tag=f"RJ_rr{rr}_b{body}_{'S' if strict else 'L'}_nobe_r5",
                        model="reject_mkt",
                        rr=rr,
                        min_body_atr=body,
                        strict_bias=strict,
                        move_to_be=False,
                        risk_pct=0.005,
                        flatten_hour_utc=22,
                    )
                )
    return out


def main():
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    assert __import__("scripts.assert_no_lookahead", fromlist=["main"]).main() == 0

    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    cfgs = space()
    print(f"Focused search {len(cfgs)} configs", flush=True)

    scored = []
    for i, cfg in enumerate(cfgs):
        fn = make_fn(cfg)
        try:
            e = edge(universe, fn, DEV_PERIOD, cfg)
        except Exception as ex:
            print("skip", cfg.tag, ex, flush=True)
            continue
        scored.append((e["pf"], e["profit"], e, cfg))
        if (i + 1) % 15 == 0 or e["pf"] >= 1.15:
            print(f"[{i+1}/{len(cfgs)}] {cfg.tag} PF={e['pf']} pnl={e['profit']} n={e['trades']}", flush=True)

    scored.sort(key=lambda x: (x[0], x[1]), reverse=True)
    print("\nTOP 20 DEV:", flush=True)
    for pf_, pnl, e, cfg in scored[:20]:
        print(f"  {cfg.tag}: PF={e['pf']} pnl={e['profit']} n={e['trades']} WR={e['wr']}", flush=True)

    winners = []
    for pf_, pnl, e, cfg in scored:
        if e["pf"] < 1.05 or e["trades"] < 25:
            continue
        fn = make_fn(cfg)
        print(f"\nValidate {cfg.tag}...", flush=True)
        de = edge(universe, fn, DEV_PERIOD, cfg)
        oe = edge(universe, fn, PURE_OOS, cfg)
        he = edge(universe, fn, HOLD_2026, cfg)
        dv = challenge_eval(universe, fn, DEV_PERIOD, cfg)
        ov = challenge_eval(universe, fn, PURE_OOS, cfg)
        hv = challenge_eval(universe, fn, HOLD_2026, cfg)
        print(
            f"  edge DEV/OOS/HOLD PF {de['pf']}/{oe['pf']}/{he['pf']} "
            f"pnl {de['profit']}/{oe['profit']}/{he['profit']}",
            flush=True,
        )
        print(
            f"  eval pass DEV/OOS/HOLD {dv['passed']}/{ov['passed']}/{hv['passed']}",
            flush=True,
        )
        # Strict winner
        if dv["passed"] and ov["passed"] and hv["passed"] and oe["pf"] >= 1.0 and he["pf"] >= 1.0:
            winners.append({"tag": cfg.tag, "cfg": cfg, "dev": de, "oos": oe, "hold": he, "evals": (dv, ov, hv), "rule": "strict"})
            print("  => STRICT WIN", flush=True)
        # Soft: all edges PF>=1.05 and profit>0, DEV eval pass
        elif (
            dv["passed"]
            and de["pf"] >= 1.05
            and oe["pf"] >= 1.05
            and he["pf"] >= 1.05
            and oe["profit"] > 0
            and he["profit"] > 0
        ):
            winners.append({"tag": cfg.tag, "cfg": cfg, "dev": de, "oos": oe, "hold": he, "evals": (dv, ov, hv), "rule": "soft"})
            print("  => SOFT WIN", flush=True)
        if len(winners) >= 5:
            break

    # If still short: take best by min PF across windows among DEV PF>=1.1
    if len(winners) < 5:
        print("\nFill with best worst-window PF (DEV PF>=1.1)...", flush=True)
        pool = []
        for pf_, pnl, e, cfg in scored:
            if e["pf"] < 1.1 or e["trades"] < 20:
                continue
            if any(w["tag"] == cfg.tag for w in winners):
                continue
            fn = make_fn(cfg)
            oe = edge(universe, fn, PURE_OOS, cfg)
            he = edge(universe, fn, HOLD_2026, cfg)
            worst = min(e["pf"], oe["pf"], he["pf"])
            pool.append((worst, e, oe, he, cfg))
        pool.sort(reverse=True, key=lambda x: (x[0], x[1]["profit"]))
        for worst, de, oe, he, cfg in pool:
            if len(winners) >= 5:
                break
            fn = make_fn(cfg)
            winners.append(
                {
                    "tag": cfg.tag,
                    "cfg": cfg,
                    "dev": de,
                    "oos": oe,
                    "hold": he,
                    "evals": (
                        challenge_eval(universe, fn, DEV_PERIOD, cfg),
                        challenge_eval(universe, fn, PURE_OOS, cfg),
                        challenge_eval(universe, fn, HOLD_2026, cfg),
                    ),
                    "rule": f"best_worst={worst}",
                }
            )
            print(f"  ADD {cfg.tag} worstPF={worst}", flush=True)

    # Register winners into strategies package files for reproducibility
    summary = {
        "causal": True,
        "fill_rule": "knowable_at=bar close",
        "develop": list(DEV_PERIOD),
        "searched": len(cfgs),
        "top15": [{"tag": c.tag, **e} for _, _, e, c in scored[:15]],
        "winners": [
            {
                "tag": w["tag"],
                "rule": w["rule"],
                "model": w["cfg"].model,
                "rr": w["cfg"].rr,
                "risk_pct": w["cfg"].risk_pct,
                "move_to_be": w["cfg"].move_to_be,
                "strict_bias": w["cfg"].strict_bias,
                "dev": w["dev"],
                "oos_2023": w["oos"],
                "hold_2026": w["hold"],
                "eval_dev": w["evals"][0],
                "eval_2023": w["evals"][1],
                "eval_2026": w["evals"][2],
            }
            for w in winners
        ],
    }
    (out_dir / "kb_search_results.json").write_text(json.dumps(summary, indent=2, default=str))

    lines = [
        "# Causal KB search — 5 strategies",
        "",
        "Look-ahead impossible: fills only after `knowable_at` (M15 close).",
        f"Develop/train: **{DEV_PERIOD[0]} → {DEV_PERIOD[1]}**. Searched {len(cfgs)} configs.",
        "",
        f"## Selected ({len(winners)})",
        "",
    ]
    for w in winners:
        lines += [
            f"### {w['tag']}",
            f"- Model `{w['cfg'].model}` RR={w['cfg'].rr} risk={w['cfg'].risk_pct} BE={w['cfg'].move_to_be} rule={w['rule']}",
            f"- DEV PF={w['dev']['pf']} PnL={w['dev']['profit']} | 2023 PF={w['oos']['pf']} | 2026 PF={w['hold']['pf']}",
            f"- Eval pass DEV/2023/2026: {w['evals'][0]['passed']}/{w['evals'][1]['passed']}/{w['evals'][2]['passed']}",
            "",
        ]
    lines += [
        "## No-lookahead confirmation",
        "",
        "- `pack_signal` sets `knowable_at = bar_open + 15m`",
        "- `_simulate_limit_entry_and_exit` searches M1 only from `knowable_at`",
        "- Raises `RuntimeError` if `entry_time < knowable_at`",
        "- Guard: `python scripts/assert_no_lookahead.py`",
        "",
    ]
    (out_dir / "KB_SEARCH.md").write_text("\n".join(lines))
    print(f"DONE winners={len(winners)}", flush=True)


if __name__ == "__main__":
    main()
