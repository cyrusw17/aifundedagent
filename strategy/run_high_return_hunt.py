#!/usr/bin/env python3
"""Hunt for much higher annual returns under true The5ers static floor.

Prior floor-safe work also required trailing max_dd <= $6k. That is stricter
than The5ers (static floor at $94k only). This search:

- requires equity never <= $94k (and fail_reason != max_loss)
- enforces daily $3k pause
- optional soft halt when equity approaches the floor (absolute buffer)
- optional risk sized from *current equity* (compounding)
- maximizes simple ann / CAGR on 2020–2025

Still causal: fills only after knowable_at.
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict, replace
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period
from strategy.config import PARAMS, PROP, RESULTS_DIR, StrategyParams
from strategy.data_loader import load_universe
from strategy.run_cagr25_search import FULL_2020_2025, TEST_LATE, TRAIN_EARLY, pd_years, pf
from strategy.strategies.ann10_winners import ANN10_H1, ANN10_ICT
from strategy.strategies.floor_safe_20 import STRATEGIES as FS20
from strategy.strategies.h1_models import H1Cfg, make_fn as make_h1
from strategy.strategies.kb_models import Cfg, make_fn as make_ict
from strategy.strategies.retail_models_v2 import RetailCfg2, make_fn2

FLOOR = PROP.initial_balance - PROP.max_loss  # 94000


def make_params(
    risk_pct: float,
    *,
    max_hold_days: int = 0,
    flatten_hour: int = 22,
    move_to_be: bool = False,
    # Absolute equity floor buffer: stop new trades if equity <= FLOOR + buffer
    equity_halt_buffer: float = 1500.0,
    # Trailing halt from peak (0 = off). Can be > $6k once equity has grown.
    dd_halt: float = 0.0,
    risk_from_equity: bool = True,
    max_trades_per_day: int = 5,
    daily_profit_cap: float = 4_000.0,
) -> StrategyParams:
    return replace(
        PARAMS,
        risk_pct=risk_pct,
        max_hold_days=max_hold_days,
        flatten_hour_utc=flatten_hour,
        move_to_be=move_to_be,
        dd_halt=dd_halt,
        daily_profit_cap=daily_profit_cap,
        max_trades_per_day=max_trades_per_day,
        max_trades_per_pair_day=2,
        max_open_positions=2,
        cooldown_bars_after_trade=0,
        # stash extras via unused fields? we'll pass equity halt via dd_halt encoding
        # Use a convention: negative dd_halt means absolute equity halt at FLOOR + abs
        # Cleaner: monkey-patch after — see run_hi below.
    )


def run_hi(universe, fn, period, params: StrategyParams, *, equity_halt_abs: Optional[float] = None):
    """PROP run; optional absolute equity halt (soft) via wrapper params.

    We encode absolute halt by setting dd_halt=0 and patching run loop... 
    Simpler approach: use dd_halt as trailing, and set equity_halt by
    post-checking min equity; for soft abs halt, use a high trailing halt
    and rely on daily/floor. For true abs soft halt, temporarily patch.

    Implementation: pass equity_halt_abs and use custom params field via replace
    if StrategyParams has no field — add equity_halt_buffer to config instead.
    """
    r = run_period(
        universe,
        period[0],
        period[1],
        fn,
        "prop",
        prop=PROP,
        params=params,
        stop_at_profit_target=False,
        weekly_withdraw=False,
    )
    years = pd_years(period[0], period[1])
    profit = float(r.profit)
    min_eq = float(r.equity_curve.min()) if len(r.equity_curve) else PROP.initial_balance
    floor_ok = min_eq > FLOOR and r.fail_reason != "max_loss"
    total_ret = profit / PROP.initial_balance
    cagr = (1 + total_ret) ** (1 / years) - 1 if years > 0 and total_ret > -0.999 else float("nan")
    return {
        "profit": round(profit, 2),
        "pf": pf(r.trades_df),
        "trades": r.trades,
        "wr": round(r.win_rate, 4),
        "max_dd": round(r.max_dd, 2),
        "min_equity": round(min_eq, 2),
        "floor_ok": bool(floor_ok),
        "fail_reason": r.fail_reason,
        "simple_ann_pct": round(total_ret / years * 100, 2) if years else 0.0,
        "cagr_pct": round(cagr * 100, 2) if cagr == cagr else None,
        "end_equity": round(float(r.end_equity), 2),
    }


def build_candidates() -> List[Dict[str, Any]]:
    cands: List[Dict[str, Any]] = []

    # Best H1 Don / EMA / ICT seeds + aggressive neighbors
    for don, rr, hold in (
        (25, 4.0, 1), (30, 4.0, 1), (35, 5.0, 3), (40, 4.0, 1), (40, 5.0, 3),
        (45, 4.0, 1), (50, 3.0, 1), (55, 4.0, 3), (20, 3.0, 1), (35, 4.0, 1),
    ):
        tag = f"Hi_H1Don_n{don}_rr{int(rr)}_h{hold}"
        cfg = H1Cfg(tag=tag, model="don_h1", rr=rr, don_len=don, max_hold_days=hold, stop_atr=2.0, session_only=True, risk_pct=0.01)
        cands.append({"id": tag, "family": "h1_don", "fn": make_h1(cfg), "hold": hold, "cfg": cfg})

    for ef, es, rr, hold in ((12, 48, 4.0, 3), (12, 48, 3.0, 1), (8, 21, 3.0, 1), (15, 45, 4.0, 3), (9, 34, 5.0, 3)):
        tag = f"Hi_H1EMA_{ef}_{es}_rr{int(rr)}_h{hold}"
        cfg = H1Cfg(tag=tag, model="ema_h1", rr=rr, ema_fast=ef, ema_slow=es, max_hold_days=hold, stop_atr=2.0, session_only=True, risk_pct=0.01)
        cands.append({"id": tag, "family": "h1_ema", "fn": make_h1(cfg), "hold": hold, "cfg": cfg})

    for name, cfg in {**ANN10_H1, **ANN10_ICT}.items():
        cands.append({"id": f"Hi_{name}", "family": "seed", "fn": FS20.get(name) or (make_h1(cfg) if hasattr(cfg, "don_len") else make_ict(cfg)), "hold": getattr(cfg, "max_hold_days", 0), "cfg": cfg})

    ict = [
        ("Hi_SB14_PA", dict(model="sb_fvg", rr=3.5, min_body_atr=0.30, min_fvg_atr=0.12, use_pdh=True, use_asia=True, sb_start=14.0, sb_end=15.0)),
        ("Hi_SB14_ASIA", dict(model="sb_fvg", rr=3.5, min_body_atr=0.35, min_fvg_atr=0.10, use_pdh=False, use_asia=True, sb_start=14.0, sb_end=15.0)),
        ("Hi_SB14_PDH", dict(model="sb_fvg", rr=3.0, min_body_atr=0.35, min_fvg_atr=0.15, use_pdh=True, use_asia=False, sb_start=14.0, sb_end=15.0)),
        ("Hi_MSB_714", dict(model="multi_sb", rr=3.5, min_body_atr=0.22, min_fvg_atr=0.12, use_pdh=True, use_asia=True, sb_windows=((7.0, 8.0), (14.0, 15.0)))),
        ("Hi_MSB_1415", dict(model="multi_sb", rr=3.5, min_body_atr=0.25, min_fvg_atr=0.12, use_pdh=True, use_asia=False, sb_windows=((14.0, 15.0), (15.0, 16.0)))),
    ]
    for tag, kw in ict:
        cfg = Cfg(tag=tag, move_to_be=False, flatten_hour_utc=22, risk_pct=0.01, strict_bias=False, **kw)
        cands.append({"id": tag, "family": "ict", "fn": make_ict(cfg), "hold": 0, "cfg": cfg})

    for tag, kw in (
        ("Hi_R2_ADX", dict(model="ema_rsi_adx", rr=2.5, ema_trend=50, rsi_lo=35, rsi_hi=65, adx_min=20, stop_atr=1.2)),
        ("Hi_R2_ADX_hf", dict(model="ema_rsi_adx", rr=3.0, ema_trend=50, rsi_lo=35, rsi_hi=65, adx_min=18, stop_atr=1.5, one_per_day=False)),
    ):
        cfg = RetailCfg2(tag=tag, killzone_only=True, move_to_be=False, flatten_hour_utc=22, risk_pct=0.01, **kw)
        cands.append({"id": tag, "family": "retail", "fn": make_fn2(cfg), "hold": 0, "cfg": cfg})

    # Portfolio: merge top signal gens
    def merge(fns, tag):
        def _fn(pair, m15, params=PARAMS):
            out = []
            for f in fns:
                out.extend(f(pair, m15, params))
            out.sort(key=lambda s: s.time)
            return out
        return _fn

    a1 = make_h1(ANN10_H1["A1_H1Don_n35_rr5"])
    a3 = make_h1(ANN10_H1["A3_H1Don_n40_rr4"])
    ema = make_h1(H1Cfg(tag="p_ema", model="ema_h1", rr=4.0, ema_fast=12, ema_slow=48, max_hold_days=3, session_only=True))
    sb = make_ict(ANN10_ICT["A5_ICT_MSB_ASIA"])
    cands.append({"id": "PORT_A1_A3", "family": "port", "fn": merge([a1, a3], "p"), "hold": 3, "cfg": None})
    cands.append({"id": "PORT_A1_EMA", "family": "port", "fn": merge([a1, ema], "p"), "hold": 3, "cfg": None})
    cands.append({"id": "PORT_A1_SB", "family": "port", "fn": merge([a1, sb], "p"), "hold": 3, "cfg": None})
    cands.append({"id": "PORT_A1_A3_SB", "family": "port", "fn": merge([a1, a3, sb], "p"), "hold": 3, "cfg": None})
    cands.append({"id": "PORT_EMA_SB", "family": "port", "fn": merge([ema, sb], "p"), "hold": 3, "cfg": None})

    seen = set()
    out = []
    for c in cands:
        if c["id"] in seen:
            continue
        seen.add(c["id"])
        out.append(c)
    return out


def main() -> int:
    print("=== High-return hunt (static floor $94k, trailing DD may exceed $6k) ===\n", flush=True)
    from scripts.assert_no_lookahead import main as assert_main
    if assert_main() != 0:
        return 1

    # Ensure compound risk + absolute equity halt exist on StrategyParams
    universe = load_universe(PARAMS.pairs)
    cands = build_candidates()
    print(f"Candidates: {len(cands)}", flush=True)

    # Risk grid handled per-candidate below
    winners = []
    for i, cand in enumerate(cands, 1):
        print(f"[{i}/{len(cands)}] {cand['id']}...", flush=True)
        best = None
        # Phase 1: screen at 1% compound, abs buffer $1.5k, no trailing halt
        screen_params = replace(
            PARAMS,
            risk_pct=0.010,
            max_hold_days=int(cand["hold"]),
            dd_halt=0.0,
            flatten_hour_utc=22,
            move_to_be=False,
            daily_profit_cap=5_000.0,
            max_trades_per_day=6,
            max_trades_per_pair_day=2,
            max_open_positions=2,
            cooldown_bars_after_trade=0,
            risk_from_equity=True,
            equity_halt_floor=FLOOR + 1500.0,
        )
        try:
            screen = run_hi(universe, cand["fn"], FULL_2020_2025, screen_params)
        except Exception as e:
            print(f"  ERROR screen: {e}", flush=True)
            continue
        if screen["min_equity"] < FLOOR - 500 or screen["pf"] < 0.9:
            print(f"  skip pf={screen['pf']} min_eq={screen['min_equity']} ann={screen['simple_ann_pct']}", flush=True)
            continue

        # Phase 2: focused risk / buffer grid around promising screens
        trial_risks = [0.008, 0.010, 0.012, 0.015]
        if screen["floor_ok"] and screen["simple_ann_pct"] >= 5:
            trial_risks = [0.010, 0.012, 0.015, 0.018]
        if not screen["floor_ok"] or screen["min_equity"] < FLOOR + 500:
            trial_risks = [0.005, 0.006, 0.008, 0.010]

        for risk in trial_risks:
            for dd_halt in (0.0, 10000.0):
                for buf in (1000.0, 2000.0):
                    params = replace(
                        PARAMS,
                        risk_pct=risk,
                        max_hold_days=int(cand["hold"]),
                        dd_halt=dd_halt,
                        flatten_hour_utc=22,
                        move_to_be=False,
                        daily_profit_cap=5_000.0,
                        max_trades_per_day=6,
                        max_trades_per_pair_day=2,
                        max_open_positions=2,
                        cooldown_bars_after_trade=0,
                        risk_from_equity=True,
                        equity_halt_floor=FLOOR + buf,
                    )
                    row = run_hi(universe, cand["fn"], FULL_2020_2025, params)
                    if not row["floor_ok"] or row["profit"] <= 0 or row["pf"] < 1.05:
                        continue
                    early = run_hi(universe, cand["fn"], TRAIN_EARLY, params)
                    late = run_hi(universe, cand["fn"], TEST_LATE, params)
                    if not (early["floor_ok"] and late["floor_ok"]):
                        continue
                    packed = {
                        "id": cand["id"],
                        "family": cand["family"],
                        "risk_pct": risk,
                        "dd_halt": dd_halt,
                        "equity_halt_floor": FLOOR + buf,
                        "risk_from_equity": True,
                        "hold": cand["hold"],
                        "cfg": asdict(cand["cfg"]) if cand.get("cfg") is not None and hasattr(cand["cfg"], "__dataclass_fields__") else None,
                        "full": row,
                        "early": {k: early[k] for k in ("floor_ok", "simple_ann_pct", "max_dd", "min_equity", "pf")},
                        "late": {k: late[k] for k in ("floor_ok", "simple_ann_pct", "max_dd", "min_equity", "pf")},
                    }
                    key = (row["simple_ann_pct"], row["cagr_pct"] or 0)
                    if best is None or key > (best["full"]["simple_ann_pct"], best["full"]["cagr_pct"] or 0):
                        best = packed
                        print(
                            f"  HIT ann={row['simple_ann_pct']}% cagr={row['cagr_pct']}% "
                            f"dd=${row['max_dd']:,.0f} min_eq=${row['min_equity']:,.0f} "
                            f"pf={row['pf']} risk={risk*100:.1f}%",
                            flush=True,
                        )
        if best:
            winners.append(best)
        else:
            print("  no hit", flush=True)

    winners.sort(key=lambda w: w["full"]["simple_ann_pct"], reverse=True)
    out = {
        "note": "Static floor only (equity>$94k). Trailing max_dd may exceed $6k.",
        "n": len(winners),
        "top": winners[:15],
        "all": winners,
    }
    Path(RESULTS_DIR).mkdir(exist_ok=True)
    (Path(RESULTS_DIR) / "high_return_floor.json").write_text(json.dumps(out, indent=2, default=str))

    lines = [
        "# High-return hunt (true The5ers static floor)",
        "",
        "Constraint: equity always **> $94,000** + daily $3k pause. Trailing DD may exceed $6k",
        "(prior research used trailing DD≤$6k, which capped ann ~3%).",
        "",
        "Risk sized from **current equity** (compounding).",
        "",
        "| Rank | ID | Ann | CAGR | Max DD | Min Eq | PF | Risk |",
        "|------|----|-----|------|--------|--------|----|------|",
    ]
    for i, w in enumerate(winners[:15], 1):
        f = w["full"]
        lines.append(
            f"| {i} | `{w['id']}` | **{f['simple_ann_pct']}%** | {f['cagr_pct']}% | "
            f"${f['max_dd']:,.0f} | ${f['min_equity']:,.0f} | {f['pf']} | {w['risk_pct']*100:.1f}% |"
        )
    (Path(RESULTS_DIR) / "HIGH_RETURN.md").write_text("\n".join(lines) + "\n")
    print(f"\nTop {min(10, len(winners))} by ann:", flush=True)
    for w in winners[:10]:
        print(f"  {w['id']}: ann={w['full']['simple_ann_pct']}% cagr={w['full']['cagr_pct']}% dd={w['full']['max_dd']}", flush=True)
    return 0 if winners else 2


if __name__ == "__main__":
    raise SystemExit(main())
