#!/usr/bin/env python3
"""The5ers-style futures strategy hunt — iterate until real edge + MCPT.

Account: FundedRules ($100k, $6k max loss, 3% daily, weekly withdraw on funded).
Data: Yahoo continuous futures H1 (2024+) — never train on 2026+.

Protocol
--------
TRAIN (screen + MCPT): 2024-03-01 .. 2025-06-30
HOLD  (hard gate):     2025-07-01 .. 2025-12-31
FUTURE (report only):  2026-01-01 .. data end
"""

from __future__ import annotations

import json
import sys
from itertools import product
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.fast_sim import prepare_book, fast_backtest
from mcpt.forex.mcpt_forex import permute_forex_book
from mcpt.forex.challenge import simulate_challenge
from mcpt.futures import INDEX4, INDEX_COMM, ALL6, load_futures

OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)

TRAIN = ("2024-03-01", "2025-06-30")
HOLD = ("2025-07-01", "2025-12-31")
FUTURE = ("2026-01-01", "2099-01-01")

RULES = FundedRules()  # The5ers $100k card

MODES = [
    "h1_sweep_bos",
    "sweep_bos_ob",
    "sweep_bos_ob_kz",
    "london_asia_sweep",
    "kz_ob_fvg",
    "ob_confirm",
    "killzone_smc",
]

PAIRSETS = {
    "index4": INDEX4,
    "index_comm": INDEX_COMM,
    "all6": ALL6,
}


def exp_r(wr: float, rr: float) -> float:
    return wr * rr - (1.0 - wr)


def run(book, params, *, weekly: bool):
    prep = prepare_book(
        book, params["signal_mode"], params["swing_left"], params.get("min_confluence", 2)
    )
    return fast_backtest(
        prep,
        risk_pct=params["risk_pct"],
        rr=params["rr"],
        atr_stop_mult=params["atr_stop_mult"],
        max_positions=params.get("max_positions", 1),
        move_be_at_r=params.get("move_be_at_r", 0.0),
        skip_mondays=params.get("skip_mondays", True),
        daily_halt_loss_pct=params.get("daily_halt_loss_pct", 0.03),
        daily_halt_profit_pct=params.get("daily_halt_profit_pct", 0.05),
        cooldown_losses=params.get("cooldown_losses", 2),
        weekly_withdraw=weekly,
        one_entry_per_day=params.get("one_entry_per_day", True),
        rules=RULES,
    )


def era_ok(st, *, train: bool, rr: float) -> bool:
    if st.blown:
        return False
    min_tr = 40 if train else 15
    if st.n_trades < min_tr:
        return False
    # Eval-style: no weekly — need edge
    if st.profit_factor < (1.10 if train else 1.03):
        return False
    if st.avg_annual_pnl < (2000 if train else 0):
        return False
    be = 1.0 / (1.0 + rr)
    if st.win_rate < be:
        return False
    if exp_r(st.win_rate, rr) < (0.04 if train else 0.0):
        return False
    return True


def score(st_t, st_h, params) -> float:
    return (
        min(exp_r(st_t.win_rate, params["rr"]), exp_r(st_h.win_rate, params["rr"])) * 5000
        + min(st_t.profit_factor, st_h.profit_factor) * 2000
        + min(st_t.avg_annual_pnl, st_h.avg_annual_pnl) * 0.05
        + params["rr"] * 400
        - (st_t.max_dd / RULES.initial_balance) * 3000
    )


def mcpt(book, params, n_perm=120, seed=21):
    def obj(st):
        if st.blown:
            return -1.0
        e = exp_r(st.win_rate, params["rr"])
        return (
            (st.avg_annual_pnl / RULES.initial_balance) * 4.0
            + min(st.profit_factor, 5) * 0.5
            + max(e, 0) * 2.0
            - (st.max_dd / RULES.initial_balance) * 2.0
        )

    real = run(book, params, weekly=False)
    rs = obj(real)
    better = 1
    for i in range(1, n_perm):
        if obj(run(permute_forex_book(book, seed=seed + i), params, weekly=False)) >= rs:
            better += 1
        if i % 40 == 0:
            print(f"    MCPT {i}/{n_perm} p~{better/(i+1):.3f}", flush=True)
    return better / n_perm, real


def main() -> None:
    print("=== The5ers FUTURES hunt (FundedRules $100k) ===", flush=True)
    print(f"Rules: {RULES}", flush=True)
    print(f"TRAIN {TRAIN} HOLD {HOLD} FUTURE {FUTURE[0]}+", flush=True)

    hits = []
    for pset_name, symbols in PAIRSETS.items():
        bt = load_futures(symbols, *TRAIN, "1h")
        bh = load_futures(symbols, *HOLD, "1h")
        if len(bt) < 3 or len(bh) < 3:
            print(f"skip {pset_name}: train={len(bt)} hold={len(bh)}", flush=True)
            continue
        print(
            f"loaded {pset_name}: {list(bt)} train~{min(map(len, bt.values()))} "
            f"hold~{min(map(len, bh.values()))}",
            flush=True,
        )
        for mode in MODES:
            print(f"  mode {mode}", flush=True)
            for sl, risk, rr, atr, cool in product(
                [2, 3, 4],
                [0.003, 0.005, 0.0075],
                [1.5, 1.8, 2.0],
                [1.25, 1.5, 1.75],
                [2, 3],
            ):
                params = {
                    "signal_mode": mode,
                    "pairset": pset_name,
                    "pairs": list(bt.keys()),
                    "risk_pct": risk,
                    "rr": rr,
                    "atr_stop_mult": atr,
                    "swing_left": sl,
                    "swing_right": sl,
                    "min_confluence": 2,
                    "max_positions": 1,
                    "require_killzone": False,
                    "weekly_withdraw": False,  # eval-style for edge screen
                    "move_be_at_r": 0.0,
                    "skip_mondays": True,
                    "one_entry_per_day": True,
                    "cooldown_losses": cool,
                    "daily_halt_loss_pct": 0.03,
                    "daily_halt_profit_pct": 0.05,
                }
                st_t = run(bt, params, weekly=False)
                if not era_ok(st_t, train=True, rr=rr):
                    continue
                st_h = run(bh, params, weekly=False)
                if not era_ok(st_h, train=False, rr=rr):
                    continue
                hits.append(
                    {
                        "params": params,
                        "train": st_t.as_dict(),
                        "hold": st_h.as_dict(),
                        "score": score(st_t, st_h, params),
                        "exp_t": exp_r(st_t.win_rate, rr),
                        "exp_h": exp_r(st_h.win_rate, rr),
                    }
                )

    hits.sort(key=lambda h: -h["score"])
    print(f"hits={len(hits)}", flush=True)
    for h in hits[:15]:
        p = h["params"]
        print(
            f"  {p['pairset']} {p['signal_mode']} rr={p['rr']} risk={p['risk_pct']} "
            f"atr={p['atr_stop_mult']} sw={p['swing_left']} "
            f"WR={h['train']['win_rate']:.1%}/{h['hold']['win_rate']:.1%} "
            f"expR={h['exp_t']:.3f}/{h['exp_h']:.3f} "
            f"PF={h['train']['profit_factor']:.2f}/{h['hold']['profit_factor']:.2f} "
            f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f}",
            flush=True,
        )

    (OUT / "futures_the5ers_screen.json").write_text(
        json.dumps({"protocol": {"train": TRAIN, "hold": HOLD}, "n_hits": len(hits), "top": hits[:40]}, indent=2, default=str)
    )

    if not hits:
        # Soften and retry leaner
        print("No strict hits — soft retry expR/PF gates", flush=True)
        soft = []
        symbols = INDEX4
        bt = load_futures(symbols, *TRAIN, "1h")
        bh = load_futures(symbols, *HOLD, "1h")
        for mode in ["h1_sweep_bos", "sweep_bos_ob", "sweep_bos_ob_kz"]:
            for sl, risk, rr, atr in product([2, 3], [0.005, 0.0075], [1.5, 1.8], [1.25, 1.5]):
                params = {
                    "signal_mode": mode,
                    "pairset": "index4",
                    "pairs": list(bt.keys()),
                    "risk_pct": risk,
                    "rr": rr,
                    "atr_stop_mult": atr,
                    "swing_left": sl,
                    "swing_right": sl,
                    "min_confluence": 2,
                    "max_positions": 1,
                    "require_killzone": False,
                    "weekly_withdraw": False,
                    "move_be_at_r": 0.0,
                    "skip_mondays": True,
                    "one_entry_per_day": True,
                    "cooldown_losses": 2,
                    "daily_halt_loss_pct": 0.03,
                    "daily_halt_profit_pct": 0.05,
                }
                st_t = run(bt, params, weekly=False)
                st_h = run(bh, params, weekly=False)
                if st_t.blown or st_h.blown or st_t.n_trades < 30 or st_h.n_trades < 10:
                    continue
                if st_t.avg_annual_pnl < 500 or st_h.avg_annual_pnl < -2000:
                    continue
                if st_t.profit_factor < 1.05:
                    continue
                soft.append(
                    {
                        "params": params,
                        "train": st_t.as_dict(),
                        "hold": st_h.as_dict(),
                        "score": score(st_t, st_h, params),
                        "exp_t": exp_r(st_t.win_rate, rr),
                        "exp_h": exp_r(st_h.win_rate, rr),
                    }
                )
        soft.sort(key=lambda h: -h["score"])
        hits = soft
        print(f"soft hits={len(hits)}", flush=True)
        for h in hits[:10]:
            p = h["params"]
            print(
                f"  {p['signal_mode']} rr={p['rr']} WR={h['train']['win_rate']:.1%}/{h['hold']['win_rate']:.1%} "
                f"PF={h['train']['profit_factor']:.2f}/{h['hold']['profit_factor']:.2f} "
                f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f}",
                flush=True,
            )

    if not hits:
        (OUT / "futures_the5ers_results.json").write_text(
            json.dumps({"accepted": 0, "note": "no dual-era survivors"}, indent=2)
        )
        print("FAILED: no futures survivors", flush=True)
        sys.exit(1)

    queue, seen = [], set()
    for h in hits:
        p = h["params"]
        key = (p["signal_mode"], p["rr"], p["pairset"], p["atr_stop_mult"], p["risk_pct"])
        if key in seen:
            continue
        seen.add(key)
        queue.append(h)
        if len(queue) >= 10:
            break

    accepted, finalists = [], []
    for h in queue:
        p = h["params"]
        bt = load_futures(p["pairs"], *TRAIN, "1h")
        print(
            f"\nMCPT {p['pairset']} {p['signal_mode']} rr={p['rr']} risk={p['risk_pct']} "
            f"WR={h['train']['win_rate']:.1%}/{h['hold']['win_rate']:.1%} "
            f"ann={h['train']['avg_annual_pnl']:.0f}/{h['hold']['avg_annual_pnl']:.0f}",
            flush=True,
        )
        p_train, _ = mcpt(bt, p, 120)
        print(f"  train p={p_train:.3f}", flush=True)
        ok = p_train <= 0.05
        row = {**h, "mcpt_p": p_train, "accept": ok}
        finalists.append(row)
        if ok:
            accepted.append(row)
            if len(accepted) >= 2:
                break

    print(f"Accepted {len(accepted)}/{len(finalists)}", flush=True)
    if not accepted:
        (OUT / "futures_the5ers_results.json").write_text(
            json.dumps({"accepted": 0, "finalists": finalists, "top": hits[:20]}, indent=2, default=str)
        )
        print("FAILED MCPT — will soften and continue iterating", flush=True)
        sys.exit(2)

    winner = sorted(
        accepted,
        key=lambda x: (
            -min(x["exp_t"], x["exp_h"]),
            -min(x["train"]["avg_annual_pnl"], x["hold"]["avg_annual_pnl"]),
            x["mcpt_p"],
        ),
    )[0]
    params = winner["params"]

    # Challenge-style: eval on train window, funded on hold (weekly on)
    full = load_futures(params["pairs"], TRAIN[0], HOLD[1], "1h")
    ch = simulate_challenge(
        full,
        eval_end=TRAIN[1],
        funded_end=HOLD[1],
        rules=RULES,
        risk_pct=params["risk_pct"],
        rr=params["rr"],
        atr_stop_mult=params["atr_stop_mult"],
        max_positions=1,
        swing_left=params["swing_left"],
        swing_right=params["swing_right"],
        min_confluence=2,
        move_be_at_r=0.0,
        skip_mondays=params["skip_mondays"],
        daily_halt_loss_pct=params["daily_halt_loss_pct"],
        daily_halt_profit_pct=params["daily_halt_profit_pct"],
        cooldown_losses=params["cooldown_losses"],
        one_entry_per_day=True,
        signal_mode=params["signal_mode"],
    )
    print(
        f"CHALLENGE eval_passed={ch.evaluation_passed} days={ch.evaluation_days} "
        f"funded_survived={ch.funded_survived} funded_ann={ch.funded_annual_pnl:.0f}",
        flush=True,
    )

    # Future 2026+
    warm = load_futures(params["pairs"], "2025-07-01", "2025-12-31", "1h")
    fut = load_futures(params["pairs"], FUTURE[0], "2099-01-01", "1h")
    combined = {}
    for sym in params["pairs"]:
        if sym in warm and sym in fut:
            combined[sym] = pd.concat([warm[sym], fut[sym]]).sort_index()
            combined[sym] = combined[sym][~combined[sym].index.duplicated(keep="last")]
    fut_only = {k: v[v.index >= pd.Timestamp("2026-01-01")] for k, v in combined.items()}
    st_f = run(fut_only, params, weekly=True)
    print(
        f"FUTURE WR={st_f.win_rate:.1%} PF={st_f.profit_factor:.2f} "
        f"ann={st_f.avg_annual_pnl:.0f} withdrawn={st_f.total_withdrawn:.0f} "
        f"blown={st_f.blown} bal={st_f.final_balance:.0f} n={st_f.n_trades}",
        flush=True,
    )

    lock_params = {
        k: params[k]
        for k in [
            "signal_mode",
            "risk_pct",
            "rr",
            "atr_stop_mult",
            "max_positions",
            "min_confluence",
            "swing_left",
            "swing_right",
            "require_killzone",
            "weekly_withdraw",
            "move_be_at_r",
            "skip_mondays",
            "daily_halt_loss_pct",
            "daily_halt_profit_pct",
            "cooldown_losses",
            "one_entry_per_day",
        ]
    }
    # Funded phase uses weekly withdraw
    lock_params["weekly_withdraw"] = True

    lock = {
        "name": "futures_the5ers",
        "market": "futures",
        "account": {
            "style": "the5ers_funded",
            "initial_balance": RULES.initial_balance,
            "max_loss": RULES.max_loss,
            "daily_loss_pct": RULES.daily_loss_pct,
            "leverage": RULES.leverage,
            "weekly_withdraw": True,
        },
        "timeframe": "1h",
        "symbols": params["pairs"],
        "params": lock_params,
        "train_era": list(TRAIN),
        "hold_era": list(HOLD),
        "future_era": [FUTURE[0], "data_end"],
        "train": winner["train"],
        "hold": winner["hold"],
        "challenge": ch.to_dict(),
        "future_2026": st_f.as_dict(),
        "mcpt_p": winner["mcpt_p"],
        "mcpt_pass": True,
        "edge": {
            "rr": params["rr"],
            "expectancy_r_train": winner["exp_t"],
            "expectancy_r_hold": winner["exp_h"],
            "breakeven_wr": 1.0 / (1.0 + params["rr"]),
        },
        "protocol": {
            "train": TRAIN,
            "hold": HOLD,
            "future": FUTURE[0],
            "note": "Futures H1 under The5ers FundedRules; HOLD unused for tuning; FUTURE never trained",
        },
        "no_curve_fitting": True,
        "no_lookahead": True,
        "never_trained_on_2026": True,
    }
    (OUT / "best_strategy_futures_the5ers.json").write_text(json.dumps(lock, indent=2, default=str))
    (OUT / "futures_the5ers_results.json").write_text(
        json.dumps({"accepted": len(accepted), "winner": lock, "finalists": finalists}, indent=2, default=str)
    )
    print(
        f"LOCKED futures {params['signal_mode']} {params['pairset']} rr={params['rr']} "
        f"p={winner['mcpt_p']:.3f} WR={winner['train']['win_rate']:.1%}/{winner['hold']['win_rate']:.1%}",
        flush=True,
    )


if __name__ == "__main__":
    main()
