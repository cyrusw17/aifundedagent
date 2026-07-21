#!/usr/bin/env python3
"""Fast random H1 hunt with cached prepare_book (targets >=$10k/yr)."""

from __future__ import annotations

import json
import random
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.fast_sim import fast_backtest, prepare_book
from scripts.research.h1_hunt import (
    is_hard_winner,
    load_h1,
    maybe_write_best,
    rank_key,
    validate,
)

OUT = ROOT / "data" / "research"

PAIRSETS = {
    "h1_majors4": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"],
    "h1_core5": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF"],
    "h1_all6": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF", "USDCAD"],
}
MODES = ["kz_fvg", "kz_active", "h1_sweep_bos", "active_smc", "london_asia_sweep", "killzone_smc"]
SWING = 3


def sample_params(rng: random.Random) -> dict:
    return dict(
        signal_mode=rng.choice(MODES),
        risk_pct=rng.choice([0.0065, 0.0075, 0.009, 0.01, 0.012, 0.015]),
        rr=rng.choice([1.8, 2.0, 2.5, 3.0, 3.5]),
        atr_stop_mult=rng.choice([0.8, 1.0, 1.2, 1.4]),
        max_positions=rng.choice([1, 2, 3]),
        min_confluence=2,
        swing_left=SWING,
        swing_right=SWING,
        require_killzone=False,
        weekly_withdraw=True,
        move_be_at_r=rng.choice([0.0, 1.0]),
        skip_mondays=rng.choice([True, False]),
        daily_halt_loss_pct=rng.choice([0.015, 0.02, 0.025]),
        daily_halt_profit_pct=rng.choice([0.03, 0.04]),
        cooldown_losses=rng.choice([0, 2, 3]),
        one_entry_per_day=rng.choice([True, False]),
    )


def main():
    t0 = time.time()
    rng = random.Random(42)
    n_screen = 4000
    books = {ps: load_h1(pairs) for ps, pairs in PAIRSETS.items()}
    for ps, b in books.items():
        print(f"loaded {ps}: {{{', '.join(f'{k}:{len(v)}' for k,v in b.items())}}}", flush=True)

    prep_cache = {}
    for ps, book in books.items():
        for mode in MODES:
            print(f"prepare {ps}|{mode}...", flush=True)
            prep_cache[(ps, mode)] = prepare_book(book, mode, SWING, 2)

    hits = []
    for i in range(n_screen):
        ps = rng.choice(list(PAIRSETS))
        pairs = PAIRSETS[ps]
        p = sample_params(rng)
        if p["risk_pct"] >= 0.012 and p["max_positions"] >= 3 and not p["one_entry_per_day"]:
            p["one_entry_per_day"] = True
        st = fast_backtest(
            prep_cache[(ps, p["signal_mode"])],
            risk_pct=p["risk_pct"],
            rr=p["rr"],
            atr_stop_mult=p["atr_stop_mult"],
            max_positions=p["max_positions"],
            move_be_at_r=p["move_be_at_r"],
            skip_mondays=p["skip_mondays"],
            daily_halt_loss_pct=p["daily_halt_loss_pct"],
            daily_halt_profit_pct=p["daily_halt_profit_pct"],
            cooldown_losses=p["cooldown_losses"],
            weekly_withdraw=True,
            one_entry_per_day=p["one_entry_per_day"],
        )
        s = st.as_dict()
        if (i + 1) % 200 == 0:
            top = max((h[0] for h in hits), default=0)
            print(
                f"  screened {i+1}/{n_screen} hits={len(hits)} top=${top:.0f} "
                f"elapsed={time.time()-t0:.0f}s",
                flush=True,
            )
        if s["blown"] or not s["consistency_ok"] or s["n_trades"] < 100:
            continue
        if s["avg_annual_pnl"] < 7000:
            continue
        hits.append((s["avg_annual_pnl"], ps, pairs, p, s))

    hits.sort(reverse=True)
    print(f"screened {n_screen} hits={len(hits)} in {time.time()-t0:.1f}s", flush=True)
    for h in hits[:30]:
        print(
            f"screen ${h[0]:.0f} tr={h[4]['n_trades']} pf={h[4]['profit_factor']:.2f} "
            f"{h[1]}|{h[3]['signal_mode']} risk={h[3]['risk_pct']} rr={h[3]['rr']} "
            f"mp={h[3]['max_positions']} one={h[3]['one_entry_per_day']} be={h[3]['move_be_at_r']}",
            flush=True,
        )
    (OUT / "h1_lean_hits.json").write_text(
        json.dumps(
            [{"ann": h[0], "pairset": h[1], "params": h[3], "stats": h[4]} for h in hits[:100]],
            indent=2,
            default=str,
        )
    )

    best = None
    hard = None
    seen = set()
    cands = []
    for h in hits:
        key = (
            h[1],
            h[3]["signal_mode"],
            h[3]["risk_pct"],
            h[3]["rr"],
            h[3]["max_positions"],
            h[3]["one_entry_per_day"],
        )
        if key in seen:
            continue
        seen.add(key)
        cands.append(h)
        if len(cands) >= 20:
            break

    if len(cands) < 8:
        templates = [
            dict(
                signal_mode="kz_fvg",
                risk_pct=0.012,
                rr=2.5,
                atr_stop_mult=1.0,
                max_positions=2,
                min_confluence=2,
                swing_left=SWING,
                swing_right=SWING,
                require_killzone=False,
                weekly_withdraw=True,
                move_be_at_r=1.0,
                skip_mondays=True,
                daily_halt_loss_pct=0.02,
                daily_halt_profit_pct=0.03,
                cooldown_losses=2,
                one_entry_per_day=False,
            ),
            dict(
                signal_mode="h1_sweep_bos",
                risk_pct=0.01,
                rr=3.0,
                atr_stop_mult=1.2,
                max_positions=2,
                min_confluence=2,
                swing_left=SWING,
                swing_right=SWING,
                require_killzone=False,
                weekly_withdraw=True,
                move_be_at_r=1.0,
                skip_mondays=False,
                daily_halt_loss_pct=0.02,
                daily_halt_profit_pct=0.03,
                cooldown_losses=0,
                one_entry_per_day=False,
            ),
            dict(
                signal_mode="kz_active",
                risk_pct=0.015,
                rr=2.0,
                atr_stop_mult=1.0,
                max_positions=1,
                min_confluence=2,
                swing_left=SWING,
                swing_right=SWING,
                require_killzone=False,
                weekly_withdraw=True,
                move_be_at_r=1.0,
                skip_mondays=True,
                daily_halt_loss_pct=0.02,
                daily_halt_profit_pct=0.03,
                cooldown_losses=2,
                one_entry_per_day=True,
            ),
        ]
        for ps, pairs in PAIRSETS.items():
            for p in templates:
                st = fast_backtest(
                    prep_cache[(ps, p["signal_mode"])],
                    risk_pct=p["risk_pct"],
                    rr=p["rr"],
                    atr_stop_mult=p["atr_stop_mult"],
                    max_positions=p["max_positions"],
                    move_be_at_r=p["move_be_at_r"],
                    skip_mondays=p["skip_mondays"],
                    daily_halt_loss_pct=p["daily_halt_loss_pct"],
                    daily_halt_profit_pct=p["daily_halt_profit_pct"],
                    cooldown_losses=p["cooldown_losses"],
                    weekly_withdraw=True,
                    one_entry_per_day=p["one_entry_per_day"],
                )
                s = st.as_dict()
                print(
                    f"template {ps}|{p['signal_mode']} ann=${s['avg_annual_pnl']:.0f} "
                    f"tr={s['n_trades']} blown={s['blown']} cons={s['consistency_ok']}",
                    flush=True,
                )
                if not s["blown"] and s["consistency_ok"] and s["n_trades"] >= 80:
                    cands.append((s["avg_annual_pnl"], ps, pairs, p, s))
        cands.sort(reverse=True)
        cands = cands[:20]

    for ann, ps, pairs, p, s in cands:
        print(f"validate {ps}|{p['signal_mode']} screen=${ann:.0f}", flush=True)
        rec = validate(ps, pairs, p)
        print(
            f"  p={rec['mcpt_p']:.3f} full=${rec['full_stats']['avg_annual_pnl']:.0f} "
            f"oos=${rec['oos_stats']['avg_annual_pnl']:.0f} "
            f"fund=${rec['challenge']['funded_annual_pnl']:.0f} "
            f"eval={rec['challenge']['evaluation_passed']} "
            f"survived={rec['challenge']['funded_survived']} pr={rec['pass_rate']:.2f}",
            flush=True,
        )
        if rec.get("recent_stats"):
            rs = rec["recent_stats"]
            print(
                f"  recent ann=${rs['avg_annual_pnl']:.0f} blown={rs['blown']} tr={rs['n_trades']}",
                flush=True,
            )
        (OUT / "h1_grid_latest.json").write_text(json.dumps(rec, indent=2, default=str))
        if best is None or rank_key(rec) > best[0]:
            best = (rank_key(rec), rec)
            (OUT / "h1_best.json").write_text(json.dumps(rec, indent=2, default=str))
        wrote, _ = maybe_write_best(rec)
        if wrote:
            print("  wrote best_strategy.json", flush=True)
        if is_hard_winner(rec):
            hard = rec
            break

    summary = {
        "hard": bool(hard),
        "hits": len(hits),
        "screened": n_screen,
        "elapsed_s": time.time() - t0,
        "best_ann": None if not best else best[1]["full_stats"]["avg_annual_pnl"],
        "best_mcpt": None if not best else best[1]["mcpt_p"],
        "best_pass": None if not best else best[1]["mcpt_pass"],
        "best_mode": None if not best else best[1]["params"]["signal_mode"],
        "best_pairset": None if not best else best[1]["pairset"],
        "best_fund": None if not best else best[1]["challenge"]["funded_annual_pnl"],
    }
    print("DONE", json.dumps(summary, indent=2), flush=True)
    (OUT / "h1_lean_summary.json").write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
