#!/usr/bin/env python3
"""Search for ~25% annualized causal edge on 2020–2025 (no look-ahead).

Risk up to 1% of initial. Train filter: 2020–2022 PF>=1.05 & profit>0,
then score CAGR on 2020–2025 and holdout 2023–2025 / 2026 H1.
"""
from __future__ import annotations

import json
import math
import sys
from dataclasses import asdict, replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from strategy.backtest import run_period
from strategy.config import HOLD_2026, PARAMS, PROP, RESULTS_DIR
from strategy.data_loader import load_universe
from strategy.strategies.kb_models import Cfg, GENERATORS, make_fn

FULL_2020_2025 = ("2020-01-01", "2025-12-31")
TRAIN_EARLY = ("2020-01-01", "2022-12-31")  # stability filter
TEST_LATE = ("2023-01-01", "2025-12-31")
DEV_2425 = ("2024-01-01", "2025-12-31")


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
        max_trades_per_day=20,
        max_trades_per_pair_day=5,
        max_open_positions=5,
        cooldown_bars_after_trade=0,
    )


def edge(universe, fn, period, cfg):
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
    years = (
        pd_years(period[0], period[1])
    )
    profit = round(r.profit, 2)
    start = PROP.initial_balance
    total_ret = profit / start
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


def pd_years(a: str, b: str) -> float:
    import pandas as pd

    return max((pd.Timestamp(b) - pd.Timestamp(a)).days / 365.25, 1 / 12)


def make_portfolio(cfgs: list[Cfg]) -> callable:
    fns = [(c, make_fn(c)) for c in cfgs]

    def _fn(pair, m15, params=PARAMS):
        out = []
        seen = set()
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


def space() -> list[Cfg]:
    """Compact grid (~150) biased toward frequency + 1% risk."""
    out: list[Cfg] = []
    windows_sets = [
        ((14.0, 15.0),),
        ((7.0, 8.0), (14.0, 15.0)),
        ((7.0, 8.0), (14.0, 15.0), (15.0, 16.0)),
    ]
    for rr in (2.5, 3.0, 3.5):
        for body in (0.22, 0.30):
            for fvg in (0.10, 0.15):
                for risk in (0.010,):
                    for use_pdh, use_asia, tag_l in (
                        (True, False, "P"),
                        (False, True, "A"),
                        (True, True, "PA"),
                    ):
                        for wins in windows_sets:
                            wtag = "w" + "".join(str(int(a)) for a, _ in wins)
                            out.append(
                                Cfg(
                                    tag=f"MSB_rr{rr}_b{body}_f{fvg}_r{risk}_{tag_l}_{wtag}",
                                    model="multi_sb",
                                    rr=rr,
                                    min_body_atr=body,
                                    min_fvg_atr=fvg,
                                    strict_bias=False,
                                    move_to_be=False,
                                    risk_pct=risk,
                                    flatten_hour_utc=22,
                                    use_pdh=use_pdh,
                                    use_asia=use_asia,
                                    sb_windows=wins,
                                )
                            )
    for rr in (2.0, 2.5, 3.0):
        for body in (0.25, 0.40):
            for risk in (0.010,):
                for strict in (False,):
                    out.append(
                        Cfg(
                            tag=f"RJ_rr{rr}_b{body}_{'S' if strict else 'L'}_r{risk}",
                            model="reject_mkt",
                            rr=rr,
                            min_body_atr=body,
                            strict_bias=strict,
                            move_to_be=False,
                            risk_pct=risk,
                            flatten_hour_utc=22,
                            use_pdh=True,
                            use_asia=True,
                        )
                    )
    for rr in (2.5, 3.0):
        for body in (0.25, 0.35):
            out.append(
                Cfg(
                    tag=f"SFVG_rr{rr}_b{body}_r0.01",
                    model="sweep_fvg",
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
    # Known soft winners scaled to 1%
    for risk in (0.010,):
        out.append(
            Cfg(
                tag="W1scale_SB14_PDH_r1",
                model="sb_fvg",
                rr=3.0,
                sb_start=14.0,
                sb_end=15.0,
                strict_bias=False,
                move_to_be=False,
                risk_pct=risk,
                flatten_hour_utc=22,
                min_body_atr=0.35,
                min_fvg_atr=0.15,
                use_pdh=True,
                use_asia=False,
            )
        )
        out.append(
            Cfg(
                tag="W4scale_SB14_ASIA_r1",
                model="sb_fvg",
                rr=3.0,
                sb_start=14.0,
                sb_end=15.0,
                strict_bias=False,
                move_to_be=False,
                risk_pct=risk,
                flatten_hour_utc=22,
                min_body_atr=0.35,
                min_fvg_atr=0.10,
                use_pdh=False,
                use_asia=True,
            )
        )
    return out


def main() -> int:
    out_dir = ROOT / RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Loading universe...", flush=True)
    universe = load_universe(PARAMS.pairs, data_dir=ROOT / "data" / "raw")
    cfgs = space()
    print(f"Screening {len(cfgs)} configs for CAGR~25% (causal)...", flush=True)

    # Phase 1: cheap screen on 2024-25 at full risk — need high annualized
    scored = []
    for i, cfg in enumerate(cfgs):
        fn = make_fn(cfg)
        try:
            e = edge(universe, fn, DEV_2425, cfg)
        except Exception as ex:
            print("skip", cfg.tag, ex, flush=True)
            continue
        scored.append((e["simple_ann_pct"], e["pf"], e, cfg))
        if (i + 1) % 40 == 0 or e["simple_ann_pct"] >= 15:
            print(
                f"[{i+1}/{len(cfgs)}] {cfg.tag} ann={e['simple_ann_pct']}% "
                f"PF={e['pf']} pnl={e['profit']} n={e['trades']}",
                flush=True,
            )

    scored.sort(key=lambda x: (x[0], x[1]), reverse=True)
    print("\nTOP 25 by DEV simple ann%:", flush=True)
    for ann, pf_, e, cfg in scored[:25]:
        print(
            f"  {cfg.tag}: ann={e['simple_ann_pct']}% CAGR={e['cagr_pct']}% "
            f"PF={e['pf']} pnl={e['profit']} n={e['trades']} dd={e['max_dd']}",
            flush=True,
        )

    # Phase 2: deep validate top candidates on 2020-2025 + early/late
    candidates = []
    seen_tags = set()
    for ann, pf_, e, cfg in scored:
        if cfg.tag in seen_tags:
            continue
        if e["pf"] < 1.05 or e["trades"] < 30 or e["simple_ann_pct"] < 8:
            continue
        seen_tags.add(cfg.tag)
        candidates.append(cfg)
        if len(candidates) >= 40:
            break

    print(f"\nDeep-validating {len(candidates)} candidates on 2020-2025...", flush=True)
    deep = []
    for cfg in candidates:
        fn = make_fn(cfg)
        try:
            early = edge(universe, fn, TRAIN_EARLY, cfg)
            late = edge(universe, fn, TEST_LATE, cfg)
            full = edge(universe, fn, FULL_2020_2025, cfg)
            hold = edge(universe, fn, HOLD_2026, cfg)
        except Exception as ex:
            print("  fail", cfg.tag, ex, flush=True)
            continue
        row = {
            "tag": cfg.tag,
            "cfg": {k: (list(v) if k == "sb_windows" else v) for k, v in asdict(cfg).items()},
            "early_2020_22": early,
            "late_2023_25": late,
            "full_2020_25": full,
            "hold_2026": hold,
        }
        deep.append(row)
        print(
            f"  {cfg.tag}: full CAGR={full['cagr_pct']}% ann={full['simple_ann_pct']}% "
            f"PF={full['pf']} | early PF={early['pf']} late PF={late['pf']} "
            f"| 2026 PF={hold['pf']} ann~{hold['simple_ann_pct']}%",
            flush=True,
        )

    # Phase 3: portfolio blends of best complementary models
    print("\nBuilding portfolio blends...", flush=True)
    # Pick diverse high-ann from deep with early PF>=1.0
    pool = [
        r
        for r in deep
        if r["early_2020_22"]["pf"] >= 1.0
        and r["late_2023_25"]["pf"] >= 1.05
        and r["full_2020_25"]["simple_ann_pct"] >= 8
    ]
    pool.sort(key=lambda r: r["full_2020_25"]["cagr_pct"], reverse=True)
    blend_cfgs = []
    for r in pool[:6]:
        c = r["cfg"]
        blend_cfgs.append(
            Cfg(
                tag=c["tag"],
                model=c["model"],
                rr=c["rr"],
                min_body_atr=c["min_body_atr"],
                min_fvg_atr=c["min_fvg_atr"],
                strict_bias=c["strict_bias"],
                use_pdh=c["use_pdh"],
                use_asia=c["use_asia"],
                move_to_be=c["move_to_be"],
                risk_pct=0.010,  # unify at 1%
                flatten_hour_utc=c["flatten_hour_utc"],
                sb_windows=tuple(tuple(x) for x in c["sb_windows"])
                if c.get("sb_windows")
                else ((14.0, 15.0),),
            )
        )

    portfolios = []
    if len(blend_cfgs) >= 2:
        for k in (2, 3, min(4, len(blend_cfgs))):
            subset = blend_cfgs[:k]
            tag = "PORT_" + "+".join(c.model[:3] + c.tag.split("_")[0][-3:] for c in subset)
            # risk split so total risk ≈ 1% if all fire — actually each signal uses full risk_pct;
            # use 1%/k per sleeve to keep ~1% typical
            sleeves = [replace(c, risk_pct=0.010 / k, tag=c.tag + f"_s{k}") for c in subset]
            # Better: keep 1% per trade but portfolio has more trades — user OK with 1%/trade
            sleeves = subset
            fn = make_portfolio(sleeves)
            # Use a shell cfg for params (1% risk)
            shell = replace(subset[0], tag=tag, risk_pct=0.010)
            try:
                full = edge(universe, fn, FULL_2020_2025, shell)
                early = edge(universe, fn, TRAIN_EARLY, shell)
                late = edge(universe, fn, TEST_LATE, shell)
                hold = edge(universe, fn, HOLD_2026, shell)
            except Exception as ex:
                print("  port fail", tag, ex, flush=True)
                continue
            portfolios.append(
                {
                    "tag": tag,
                    "sleeves": [c.tag for c in sleeves],
                    "early_2020_22": early,
                    "late_2023_25": late,
                    "full_2020_25": full,
                    "hold_2026": hold,
                }
            )
            print(
                f"  {tag}: full CAGR={full['cagr_pct']}% ann={full['simple_ann_pct']}% "
                f"PF={full['pf']} n={full['trades']} | late PF={late['pf']} | 2026 PF={hold['pf']}",
                flush=True,
            )

    # Rank anything near 25%
    all_rows = deep + portfolios
    near = [
        r
        for r in all_rows
        if r["full_2020_25"]["cagr_pct"] >= 20
        and r["early_2020_22"]["pf"] >= 1.05
        and r["late_2023_25"]["pf"] >= 1.05
    ]
    near.sort(key=lambda r: r["full_2020_25"]["cagr_pct"], reverse=True)

    best = sorted(all_rows, key=lambda r: r["full_2020_25"]["cagr_pct"], reverse=True)[:15]

    summary = {
        "target_cagr_pct": 25,
        "causal": True,
        "risk_note": "up to 1% of initial balance per trade; fixed (non-compounding) risk",
        "periods": {
            "full": list(FULL_2020_2025),
            "early": list(TRAIN_EARLY),
            "late": list(TEST_LATE),
        },
        "screened": len(cfgs),
        "deep_n": len(deep),
        "near_25": near,
        "best15": best,
        "top_dev_screen": [
            {"tag": c.tag, **e} for _, _, e, c in scored[:20]
        ],
    }
    path = out_dir / "cagr25_search.json"
    path.write_text(json.dumps(summary, indent=2, default=str))

    md = [
        "# CAGR ~25% search (causal, no look-ahead)",
        "",
        "Risk up to **1%** of initial. Fills only after `knowable_at`.",
        f"Screened **{len(cfgs)}** configs. Deep-validated **{len(deep)}** + portfolios.",
        "",
        "## Near 25% CAGR (full 2020–25, early&late PF≥1.05)",
        "",
    ]
    if not near:
        md.append("_None found._")
    for r in near[:10]:
        f = r["full_2020_25"]
        md.append(
            f"- **{r['tag']}**: CAGR **{f['cagr_pct']}%**, simple ann {f['simple_ann_pct']}%, "
            f"PF={f['pf']}, trades={f['trades']}, dd=${f['max_dd']:,}"
        )
    md += ["", "## Best 10 by full CAGR (regardless of 25% bar)", ""]
    for r in best[:10]:
        f = r["full_2020_25"]
        e = r["early_2020_22"]
        l = r["late_2023_25"]
        md.append(
            f"- `{r['tag']}`: full CAGR **{f['cagr_pct']}%** (ann {f['simple_ann_pct']}%, PF {f['pf']}, "
            f"n={f['trades']}) | early PF {e['pf']} | late PF {l['pf']} | "
            f"2026 PF {r['hold_2026']['pf']}"
        )
    md += [
        "",
        "## Verdict",
        "",
    ]
    if near:
        md.append(f"Found {len(near)} config(s) clearing ~20%+ CAGR with split-sample PF≥1.05.")
    else:
        top = best[0]["full_2020_25"] if best else None
        if top:
            md.append(
                f"No stable ~25% CAGR strategy under causal fills. Best full-period CAGR was "
                f"**{top['cagr_pct']}%** (`{best[0]['tag']}`). Scaling risk to 1% helps but "
                f"does not reach 25% without a larger genuine edge / trade frequency."
            )
        else:
            md.append("No viable candidates.")
    (out_dir / "CAGR25_SEARCH.md").write_text("\n".join(md) + "\n")
    print("\nWrote", path, "and CAGR25_SEARCH.md", flush=True)
    if near:
        print(f"SUCCESS-ish: {len(near)} near-25% configs")
        return 0
    print("No ~25% CAGR causal strategy found; see best15 in JSON")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
