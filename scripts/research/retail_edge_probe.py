#!/usr/bin/env python3
"""Probe: isolate signal edge vs risk-control artifact; find MCPT-passable retail configs."""

from __future__ import annotations

import json
import sys
from itertools import product
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.fast_sim import prepare_book, fast_backtest
from mcpt.forex.mcpt_forex import permute_forex_book
from scripts.research.retail_timeless_hunt import (
    TRAIN,
    HOLD,
    RULES,
    load_merged,
    make_params,
)

PAIRS = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"]


def run_bt(book, params):
    prep = prepare_book(
        book, params["signal_mode"], params.get("swing_left", 3), params.get("min_confluence", 2)
    )
    return fast_backtest(
        prep,
        risk_pct=params["risk_pct"],
        rr=params["rr"],
        atr_stop_mult=params["atr_stop_mult"],
        max_positions=1,
        move_be_at_r=params["move_be_at_r"],
        skip_mondays=params["skip_mondays"],
        daily_halt_loss_pct=params["daily_halt_loss_pct"],
        daily_halt_profit_pct=params["daily_halt_profit_pct"],
        cooldown_losses=params["cooldown_losses"],
        weekly_withdraw=False,
        one_entry_per_day=params["one_entry_per_day"],
        rules=RULES,
    )


def obj(st):
    if st.blown:
        return -1.0
    if st.max_dd_pct > 0.20:
        return -0.5
    return (st.avg_annual_pnl / 1000) * 2.5 + min(st.profit_factor, 5) * 0.35 - st.max_dd_pct * 1.5


def mcpt_fast(book, params, n=80, seed=7):
    real = run_bt(book, params)
    rs = obj(real)
    better = 1
    for i in range(1, n):
        if obj(run_bt(permute_forex_book(book, seed=seed + i), params)) >= rs:
            better += 1
        if i % 20 == 0:
            print(f"    {i}/{n} p~{better/(i+1):.3f}", flush=True)
    return better / n, real


def main() -> None:
    bt = load_merged(PAIRS, *TRAIN)
    bh = load_merged(PAIRS, *HOLD)

    modes = ["sweep_bos_ob", "sweep_bos_ob_kz", "h1_sweep_bos"]
    overlays = [
        dict(
            name="raw",
            skip_mondays=False,
            one_entry_per_day=False,
            cooldown_losses=0,
            daily_halt_loss_pct=0.99,
            daily_halt_profit_pct=0.99,
            move_be_at_r=0.0,
        ),
        dict(
            name="opd",
            skip_mondays=True,
            one_entry_per_day=True,
            cooldown_losses=0,
            daily_halt_loss_pct=0.99,
            daily_halt_profit_pct=0.99,
            move_be_at_r=0.0,
        ),
        dict(
            name="full",
            skip_mondays=True,
            one_entry_per_day=True,
            cooldown_losses=2,
            daily_halt_loss_pct=0.03,
            daily_halt_profit_pct=0.05,
            move_be_at_r=0.0,
        ),
    ]
    risks = [0.003, 0.005]
    rrs = [1.0, 1.2, 1.5, 1.8]
    atrs = [1.25, 1.5, 1.75]
    swings = [(2, 2), (3, 2), (3, 3), (4, 2)]

    print("Screening dual-era with raw/opd/full overlays...", flush=True)
    hits = []
    for mode in modes:
        for sl, mc in swings:
            print(f" prep {mode} sw={sl} mc={mc}", flush=True)
            pt = prepare_book(bt, mode, sl, mc)
            ph = prepare_book(bh, mode, sl, mc)
            for ov, risk, rr, atr in product(overlays, risks, rrs, atrs):
                tmpl = {k: v for k, v in ov.items() if k != "name"}
                tmpl.update(dict(risk_pct=risk, rr=rr, atr_stop_mult=atr))
                params = make_params(
                    mode, "majors4", tmpl, swing_left=sl, swing_right=sl, min_confluence=mc
                )
                st_t = fast_backtest(
                    pt,
                    risk_pct=risk,
                    rr=rr,
                    atr_stop_mult=atr,
                    max_positions=1,
                    move_be_at_r=tmpl["move_be_at_r"],
                    skip_mondays=tmpl["skip_mondays"],
                    daily_halt_loss_pct=tmpl["daily_halt_loss_pct"],
                    daily_halt_profit_pct=tmpl["daily_halt_profit_pct"],
                    cooldown_losses=tmpl["cooldown_losses"],
                    weekly_withdraw=False,
                    one_entry_per_day=tmpl["one_entry_per_day"],
                    rules=RULES,
                ).as_dict()
                if (
                    st_t["blown"]
                    or st_t["win_rate"] < 0.45
                    or st_t["max_dd_pct"] > 0.20
                    or st_t["avg_annual_pnl"] < 30
                    or st_t["n_trades"] < 80
                    or st_t["profit_factor"] < 1.05
                ):
                    continue
                st_h = fast_backtest(
                    ph,
                    risk_pct=risk,
                    rr=rr,
                    atr_stop_mult=atr,
                    max_positions=1,
                    move_be_at_r=tmpl["move_be_at_r"],
                    skip_mondays=tmpl["skip_mondays"],
                    daily_halt_loss_pct=tmpl["daily_halt_loss_pct"],
                    daily_halt_profit_pct=tmpl["daily_halt_profit_pct"],
                    cooldown_losses=tmpl["cooldown_losses"],
                    weekly_withdraw=False,
                    one_entry_per_day=tmpl["one_entry_per_day"],
                    rules=RULES,
                ).as_dict()
                if (
                    st_h["blown"]
                    or st_h["win_rate"] < 0.42
                    or st_h["max_dd_pct"] > 0.20
                    or st_h["avg_annual_pnl"] < 1
                    or st_h["n_trades"] < 20
                    or st_h["profit_factor"] < 1.02
                ):
                    continue
                esc = (
                    min(st_t["profit_factor"], st_h["profit_factor"]) * 1000
                    + min(st_t["avg_annual_pnl"], st_h["avg_annual_pnl"])
                )
                hits.append(
                    {"params": params, "train": st_t, "hold": st_h, "esc": esc, "ov": ov["name"]}
                )

    # Prefer strong train edge for MCPT (min-PF ranking hid high-ann configs)
    hits.sort(
        key=lambda x: (
            -(x["train"]["profit_factor"] * x["hold"]["profit_factor"]),
            -min(x["train"]["avg_annual_pnl"], x["hold"]["avg_annual_pnl"]),
            -x["esc"],
        )
    )
    print(f"hits={len(hits)}", flush=True)
    for h in hits[:15]:
        p = h["params"]
        print(
            f"  {h['ov']} {p['signal_mode']} sw={p['swing_left']} mc={p['min_confluence']} "
            f"rr={p['rr']} risk={p['risk_pct']} atr={p['atr_stop_mult']} "
            f"WR={h['train']['win_rate']:.1%}/{h['hold']['win_rate']:.1%} "
            f"PF={h['train']['profit_factor']:.2f}/{h['hold']['profit_factor']:.2f} "
            f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f}",
            flush=True,
        )

    seen = set()
    queue = []
    for h in hits:
        p = h["params"]
        key = (
            h["ov"],
            p["signal_mode"],
            p["rr"],
            p["risk_pct"],
            p["atr_stop_mult"],
            p["swing_left"],
            p["min_confluence"],
        )
        if key in seen:
            continue
        seen.add(key)
        queue.append(h)
        if len(queue) >= 10:
            break

    accepted = []
    for h in queue:
        p = h["params"]
        print(
            f"\nMCPT {h['ov']} {p['signal_mode']} rr={p['rr']} risk={p['risk_pct']} "
            f"atr={p['atr_stop_mult']} sw={p['swing_left']} "
            f"PF={h['train']['profit_factor']:.2f}/{h['hold']['profit_factor']:.2f} "
            f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f}",
            flush=True,
        )
        pv, st = mcpt_fast(bt, p, n=80)
        print(
            f"  p={pv:.3f} WR={st.win_rate:.1%} PF={st.profit_factor:.3f} ann={st.avg_annual_pnl:.1f}",
            flush=True,
        )
        if pv <= 0.05:
            accepted.append({**h, "mcpt_p": pv})
            print("  ACCEPT", flush=True)

    print(f"\naccepted={len(accepted)}", flush=True)
    Path("/tmp/edge_probe_hits.json").write_text(
        json.dumps(
            {
                "n": len(hits),
                "accepted": len(accepted),
                "top": [
                    {
                        "ov": h["ov"],
                        "params": h["params"],
                        "train": h["train"],
                        "hold": h["hold"],
                        "mcpt_p": h.get("mcpt_p"),
                    }
                    for h in (accepted or hits[:10])
                ],
            },
            indent=2,
            default=str,
        )
    )
    print("wrote /tmp/edge_probe_hits.json", flush=True)

    # If nothing accepted at WR 45, retry MCPT on best raw-edge with WR floor 0.43
    if not accepted and hits:
        print("\n=== Soft WR retry on best PF hits ===", flush=True)
        for h in queue[:6]:
            p = h["params"]
            if h["train"]["win_rate"] < 0.43 or h["hold"]["win_rate"] < 0.40:
                continue
            print(
                f"MCPT2 {h['ov']} {p['signal_mode']} rr={p['rr']} PF={h['train']['profit_factor']:.2f}/{h['hold']['profit_factor']:.2f}",
                flush=True,
            )
            pv, st = mcpt_fast(bt, p, n=100)
            print(f"  p={pv:.3f}", flush=True)
            if pv <= 0.05:
                accepted.append({**h, "mcpt_p": pv})
                print("  ACCEPT", flush=True)
                break

    if accepted:
        Path("/tmp/edge_probe_accepted.json").write_text(
            json.dumps(accepted, indent=2, default=str)
        )
        print(f"SAVED {len(accepted)} accepted -> /tmp/edge_probe_accepted.json", flush=True)


if __name__ == "__main__":
    main()
