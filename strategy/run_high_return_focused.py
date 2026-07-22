#!/usr/bin/env python3
"""Focused high-return hunt under true The5ers static floor (equity > $94k)."""
from __future__ import annotations

import json
import sys
from dataclasses import asdict, replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.config import PARAMS, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import FULL_2020_2025, TEST_LATE, TRAIN_EARLY
from strategy.run_high_return_hunt import FLOOR, run_hi
from strategy.strategies.ann10_winners import ANN10_H1, ANN10_ICT
from strategy.strategies.h1_models import H1Cfg, make_fn as make_h1
from strategy.strategies.kb_models import Cfg, make_fn as make_ict


def params(risk, hold, buf=1500.0, dd_halt=0.0):
    return replace(
        PARAMS,
        risk_pct=risk,
        max_hold_days=hold,
        dd_halt=dd_halt,
        move_to_be=False,
        flatten_hour_utc=22,
        daily_profit_cap=5_000.0,
        max_trades_per_day=6,
        max_trades_per_pair_day=2,
        max_open_positions=2,
        cooldown_bars_after_trade=0,
        risk_from_equity=True,
        equity_halt_floor=FLOOR + buf,
    )


def merge(fns):
    def _fn(pair, m15, p=PARAMS):
        out = []
        for f in fns:
            out.extend(f(pair, m15, p))
        out.sort(key=lambda s: s.time)
        return out

    return _fn


def main() -> int:
    print("=== Focused high-return (static floor, compound risk) ===\n", flush=True)
    uni = load_universe(PARAMS.pairs)
    cands = []

    for don, rr, hold in (
        (35, 5.0, 3),
        (40, 4.0, 1),
        (40, 5.0, 3),
        (30, 4.0, 1),
        (45, 4.0, 1),
        (55, 4.0, 3),
        (25, 4.0, 1),
        (50, 3.0, 1),
    ):
        cfg = H1Cfg(
            tag=f"HR_Don{don}_rr{int(rr)}_h{hold}",
            model="don_h1",
            rr=rr,
            don_len=don,
            max_hold_days=hold,
            session_only=True,
            stop_atr=2.0,
        )
        cands.append((cfg.tag, "h1_don", make_h1(cfg), hold, cfg))

    for ef, es, rr, hold in ((12, 48, 4.0, 3), (12, 48, 5.0, 3), (15, 45, 4.0, 3), (8, 21, 3.0, 1)):
        cfg = H1Cfg(
            tag=f"HR_EMA{ef}_{es}_rr{int(rr)}_h{hold}",
            model="ema_h1",
            rr=rr,
            ema_fast=ef,
            ema_slow=es,
            max_hold_days=hold,
            session_only=True,
            stop_atr=2.0,
        )
        cands.append((cfg.tag, "h1_ema", make_h1(cfg), hold, cfg))

    for tag, kw in (
        (
            "HR_MSB_714",
            dict(
                model="multi_sb",
                rr=3.5,
                min_body_atr=0.22,
                min_fvg_atr=0.15,
                use_pdh=True,
                use_asia=True,
                sb_windows=((7.0, 8.0), (14.0, 15.0)),
            ),
        ),
        (
            "HR_SB14_ASIA",
            dict(
                model="sb_fvg",
                rr=3.5,
                min_body_atr=0.45,
                min_fvg_atr=0.12,
                use_pdh=False,
                use_asia=True,
                sb_start=14.0,
                sb_end=15.0,
            ),
        ),
        (
            "HR_SB14_PA",
            dict(
                model="sb_fvg",
                rr=3.5,
                min_body_atr=0.35,
                min_fvg_atr=0.15,
                use_pdh=True,
                use_asia=True,
                sb_start=14.0,
                sb_end=15.0,
            ),
        ),
    ):
        cfg = Cfg(tag=tag, move_to_be=False, flatten_hour_utc=22, strict_bias=False, **kw)
        cands.append((tag, "ict", make_ict(cfg), 0, cfg))

    a1 = make_h1(ANN10_H1["A1_H1Don_n35_rr5"])
    a3 = make_h1(ANN10_H1["A3_H1Don_n40_rr4"])
    ema = make_h1(
        H1Cfg(tag="e", model="ema_h1", rr=4.0, ema_fast=12, ema_slow=48, max_hold_days=3, session_only=True, stop_atr=2.0)
    )
    sb = make_ict(ANN10_ICT["A5_ICT_MSB_ASIA"])
    for name, fns, hold in (
        ("HR_PORT_A1_EMA", [a1, ema], 3),
        ("HR_PORT_A1_A3", [a1, a3], 3),
        ("HR_PORT_A1_SB", [a1, sb], 3),
        ("HR_PORT_A1_EMA_SB", [a1, ema, sb], 3),
        ("HR_PORT_EMA_A3", [ema, a3], 3),
    ):
        cands.append((name, "port", merge(fns), hold, None))

    print(f"Candidates: {len(cands)}", flush=True)
    hits = []

    for i, (name, fam, fn, hold, cfg) in enumerate(cands, 1):
        print(f"[{i}/{len(cands)}] {name}", flush=True)
        best = None
        # screen risks
        for risk in (0.004, 0.005, 0.006, 0.007, 0.008):
            row = run_hi(uni, fn, FULL_2020_2025, params(risk, hold))
            print(
                f"  screen r={risk*100:.1f}% ann={row['simple_ann_pct']}% "
                f"min={row['min_equity']:.0f} pf={row['pf']} floor={row['floor_ok']}",
                flush=True,
            )
            if not (row["floor_ok"] and row["profit"] > 0 and row["pf"] >= 1.05):
                continue
            early = run_hi(uni, fn, TRAIN_EARLY, params(risk, hold))
            late = run_hi(uni, fn, TEST_LATE, params(risk, hold))
            if not (early["floor_ok"] and late["floor_ok"]):
                print("    fail early/late floor", flush=True)
                continue
            # try slightly higher risk if headroom
            for risk2, buf in ((risk, 1500.0), (risk + 0.001, 1000.0), (risk + 0.002, 1000.0)):
                if risk2 > 0.012:
                    continue
                row2 = run_hi(uni, fn, FULL_2020_2025, params(risk2, hold, buf=buf))
                if not (row2["floor_ok"] and row2["pf"] >= 1.05 and row2["profit"] > 0):
                    continue
                e2 = run_hi(uni, fn, TRAIN_EARLY, params(risk2, hold, buf=buf))
                l2 = run_hi(uni, fn, TEST_LATE, params(risk2, hold, buf=buf))
                if not (e2["floor_ok"] and l2["floor_ok"]):
                    continue
                packed = {
                    "id": name,
                    "family": fam,
                    "risk_pct": risk2,
                    "equity_halt_floor": FLOOR + buf,
                    "hold": hold,
                    "cfg": asdict(cfg) if cfg is not None else None,
                    "full": row2,
                    "early_ann": e2["simple_ann_pct"],
                    "late_ann": l2["simple_ann_pct"],
                }
                if best is None or row2["simple_ann_pct"] > best["full"]["simple_ann_pct"]:
                    best = packed
                    print(
                        f"  HIT ann={row2['simple_ann_pct']}% cagr={row2['cagr_pct']}% "
                        f"dd={row2['max_dd']:.0f} end={row2['end_equity']:.0f} risk={risk2*100:.1f}%",
                        flush=True,
                    )
        if best:
            hits.append(best)

    hits.sort(key=lambda h: h["full"]["simple_ann_pct"], reverse=True)
    Path(RESULTS_DIR).mkdir(exist_ok=True)
    (Path(RESULTS_DIR) / "high_return_floor.json").write_text(json.dumps({"hits": hits}, indent=2, default=str))

    lines = [
        "# High-return strategy (true The5ers static floor)",
        "",
        "Prior ~3% ann caps came from requiring **trailing max DD ≤ $6k**.",
        "The5ers day-trader rule is a **static floor at $94k** (equity must stay above).",
        "Once equity grows, trailing DD from peak can exceed $6k while still floor-safe.",
        "",
        "This hunt: compound risk (`risk_from_equity`), soft absolute equity halt,",
        "floor_ok on full / early / late, PF≥1.05, causal fills.",
        "",
        "| Rank | ID | Ann | CAGR | End Eq | Max DD | Min Eq | Risk | PF |",
        "|------|----|-----|------|--------|--------|--------|------|----|",
    ]
    for i, h in enumerate(hits[:12], 1):
        f = h["full"]
        lines.append(
            f"| {i} | `{h['id']}` | **{f['simple_ann_pct']}%** | {f['cagr_pct']}% | "
            f"${f['end_equity']:,.0f} | ${f['max_dd']:,.0f} | ${f['min_equity']:,.0f} | "
            f"{h['risk_pct']*100:.1f}% | {f['pf']} |"
        )
    if hits:
        best = hits[0]
        lines += [
            "",
            f"## Champion: `{best['id']}`",
            "",
            f"- Simple ann **{best['full']['simple_ann_pct']}%** / CAGR **{best['full']['cagr_pct']}%**",
            f"- End equity ${best['full']['end_equity']:,.0f} on $100k over 2020–2025",
            f"- Min equity ${best['full']['min_equity']:,.0f} (above $94k floor)",
            f"- Trailing max DD ${best['full']['max_dd']:,.0f} (allowed under static-floor rules)",
            f"- Risk {best['risk_pct']*100:.1f}% of current equity",
            "",
            "Registry: `strategy/strategies/high_return.py`",
        ]
    (Path(RESULTS_DIR) / "HIGH_RETURN.md").write_text("\n".join(lines) + "\n")
    print("\n=== TOP ===", flush=True)
    for h in hits[:10]:
        print(
            f"  {h['full']['simple_ann_pct']:6.2f}%  {h['id']}  risk={h['risk_pct']*100:.1f}%  "
            f"cagr={h['full']['cagr_pct']}% end={h['full']['end_equity']:.0f}",
            flush=True,
        )
    return 0 if hits else 2


if __name__ == "__main__":
    raise SystemExit(main())
