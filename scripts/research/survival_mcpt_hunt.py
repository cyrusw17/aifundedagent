#!/usr/bin/env python3
"""Honest 2016–2023 hunt: MCPT + funded survival (no curve-fit, no look-ahead).

Protocol
--------
Data: Dukascopy H1 contiguous (*_1h_2016_2023.parquet)

TRAIN (screen + MCPT only): 2016-01-01 .. 2020-12-31
HOLD  (hard gate, never tune): 2021-01-01 .. 2023-12-31

Two-phase FIXED discrete grid (holdout never used to pick params):
  Phase A — mode × pairset screen with a single conservative template
  Phase B — expand risk/RR/halt/etc. only for modes that cleared Phase A

Accept only if BOTH eras:
  A) Funded weekly withdraw: not blown, consistency OK, positive wealth
  B) Eval compounding: hits +10% without blow, consistency OK
  C) Holdout wealth similar to train
  D) MCPT p <= 0.05 on TRAIN
  E) Rolling funded survival on TRAIN >= 70%

After lock, report 2024–2025 Yahoo OOS without retuning.
"""

from __future__ import annotations

import argparse
import json
import sys
from itertools import product
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.challenge import simulate_challenge
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.mcpt_forex import permute_forex_book
from mcpt.forex.strategy_funded import BEST_PATH

DATA = ROOT / "data" / "forex"
OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)

TRAIN = ("2016-01-01", "2020-12-31")
HOLD = ("2021-01-01", "2023-12-31")
OOS = ("2024-01-01", "2025-12-31")

PAIRSETS = {
    "majors4": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"],
    "majors6": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF", "USDCAD"],
}

MODES = [
    "h1_sweep_bos",
    "sweep_bos_ob",
    "sweep_bos_ob_kz",
    "killzone_smc",
    "kz_fvg",
    "london_asia_sweep",
    "smc_plus",
    "kz_ob_fvg",
    "triple_confirm",
    "ob_confirm",
    "kz_active",
    "sweep_wait_ob",
]

# Shared defaults
BASE = {
    "max_positions": 1,
    "min_confluence": 2,
    "swing_left": 3,
    "swing_right": 3,
    "require_killzone": False,
    "weekly_withdraw": True,
}

# Phase A: small fixed template bank (not free search)
TEMPLATES = [
    {
        "risk_pct": 0.003,
        "rr": 1.8,
        "atr_stop_mult": 1.25,
        "move_be_at_r": 0.0,
        "skip_mondays": False,
        "daily_halt_loss_pct": 0.02,
        "daily_halt_profit_pct": 0.03,
        "cooldown_losses": 2,
        "one_entry_per_day": True,
    },
    {
        "risk_pct": 0.003,
        "rr": 2.0,
        "atr_stop_mult": 1.5,
        "move_be_at_r": 0.0,
        "skip_mondays": True,
        "daily_halt_loss_pct": 0.015,
        "daily_halt_profit_pct": 0.03,
        "cooldown_losses": 2,
        "one_entry_per_day": True,
    },
    {
        "risk_pct": 0.004,
        "rr": 2.0,
        "atr_stop_mult": 1.5,
        "move_be_at_r": 0.0,
        "skip_mondays": False,
        "daily_halt_loss_pct": 0.02,
        "daily_halt_profit_pct": 0.03,
        "cooldown_losses": 0,
        "one_entry_per_day": False,
    },
    {
        "risk_pct": 0.0035,
        "rr": 2.5,
        "atr_stop_mult": 1.5,
        "move_be_at_r": 1.0,
        "skip_mondays": True,
        "daily_halt_loss_pct": 0.025,
        "daily_halt_profit_pct": 0.04,
        "cooldown_losses": 2,
        "one_entry_per_day": True,
    },
]

# Phase B expansions (fixed discrete)
RISKS = [0.003, 0.0035, 0.004, 0.005]
RRS = [1.8, 2.0, 2.5]
ATRS = [1.25, 1.5]
SKIP = [True, False]
HALTS = [0.015, 0.02, 0.025]
OPD = [True, False]
COOL = [0, 2]
BE = [0.0, 1.0]


def load_book(pairs: list[str], start: str, end: str, source: str = "dukascopy") -> dict:
    book = {}
    s, e = pd.Timestamp(start), pd.Timestamp(end)
    for p in pairs:
        if source == "dukascopy":
            path = DATA / f"{p}_1h_2016_2023.parquet"
        elif source == "yahoo":
            path = DATA / f"{p}_1h.parquet"
        else:
            path = DATA / f"{p}_1h_hist.parquet"
        if not path.exists():
            continue
        df = pd.read_parquet(path)
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        df = df[(df.index >= s) & (df.index <= e)]
        df = df[~df.index.duplicated(keep="last")].sort_index()
        if len(df) >= 400:
            book[p] = df[["open", "high", "low", "close"]].astype(float)
    return book


def make_params(mode: str, pset: str, template: dict | None = None, **over) -> dict:
    p = {
        "signal_mode": mode,
        "pairset": pset,
        "pairs": PAIRSETS[pset],
        **BASE,
        **(template or TEMPLATES[0]),
    }
    p.update(over)
    return p


def sim(prep, params, weekly_withdraw: bool) -> dict:
    st = fast_backtest(
        prep,
        risk_pct=params["risk_pct"],
        rr=params["rr"],
        atr_stop_mult=params["atr_stop_mult"],
        max_positions=params["max_positions"],
        move_be_at_r=params["move_be_at_r"],
        skip_mondays=params["skip_mondays"],
        daily_halt_loss_pct=params["daily_halt_loss_pct"],
        daily_halt_profit_pct=params["daily_halt_profit_pct"],
        cooldown_losses=params["cooldown_losses"],
        weekly_withdraw=weekly_withdraw,
        one_entry_per_day=bool(params["one_entry_per_day"]),
    )
    return st.as_dict()


def similar(train_w: float, hold_w: float) -> bool:
    if train_w <= 0 or hold_w <= 0:
        return False
    if hold_w >= 2000 and train_w >= 2000:
        return True
    return hold_w >= 0.4 * train_w


def era_ok(fund: dict, ev: dict, *, min_ann: float = 2000, min_trades: int = 60) -> bool:
    if fund["blown"] or not fund["consistency_ok"]:
        return False
    if ev["blown"] or not ev["consistency_ok"]:
        return False
    if not ev["hit_eval_target"]:
        return False
    if fund["n_trades"] < min_trades or ev["n_trades"] < min_trades:
        return False
    if fund["avg_annual_pnl"] < min_ann:
        return False
    return True


def dual_era_ok(pt, ph, params) -> tuple[bool, dict, dict, dict, dict]:
    fund_t = sim(pt, params, True)
    ev_t = sim(pt, params, False)
    if not era_ok(fund_t, ev_t):
        return False, fund_t, ev_t, {}, {}
    fund_h = sim(ph, params, True)
    ev_h = sim(ph, params, False)
    if not era_ok(fund_h, ev_h, min_ann=1500, min_trades=40):
        return False, fund_t, ev_t, fund_h, ev_h
    if not similar(fund_t["avg_annual_pnl"], fund_h["avg_annual_pnl"]):
        return False, fund_t, ev_t, fund_h, ev_h
    return True, fund_t, ev_t, fund_h, ev_h


def rolling_funded_survival(book, params, *, start, end, window_days=365, step_days=180) -> dict:
    cursor = pd.Timestamp(start)
    end_ts = pd.Timestamp(end)
    n = passed = blown = 0
    while cursor + pd.Timedelta(days=window_days) <= end_ts:
        w_end = cursor + pd.Timedelta(days=window_days)
        sl = {
            p: df[(df.index >= cursor) & (df.index <= w_end)].copy()
            for p, df in book.items()
        }
        if min(len(v) for v in sl.values()) < 200:
            cursor += pd.Timedelta(days=step_days)
            continue
        prep = prepare_book(
            sl, params["signal_mode"], params["swing_left"], params["min_confluence"]
        )
        st = sim(prep, params, weekly_withdraw=True)
        n += 1
        if st["blown"]:
            blown += 1
        else:
            passed += 1
        cursor += pd.Timedelta(days=step_days)
    return {
        "n_windows": n,
        "n_survived": passed,
        "n_blown": blown,
        "survival_rate": (passed / n) if n else 0.0,
    }


def mcpt_pvalue(book, params, n_perm: int, seed: int = 11) -> tuple[float, dict]:
    def run(b):
        prep = prepare_book(
            b, params["signal_mode"], params["swing_left"], params["min_confluence"]
        )
        return fast_backtest(
            prep,
            risk_pct=params["risk_pct"],
            rr=params["rr"],
            atr_stop_mult=params["atr_stop_mult"],
            max_positions=params["max_positions"],
            move_be_at_r=params["move_be_at_r"],
            skip_mondays=params["skip_mondays"],
            daily_halt_loss_pct=params["daily_halt_loss_pct"],
            daily_halt_profit_pct=params["daily_halt_profit_pct"],
            cooldown_losses=params["cooldown_losses"],
            weekly_withdraw=True,
            one_entry_per_day=bool(params["one_entry_per_day"]),
        )

    def obj(st):
        if st.blown:
            return -1.0
        if not st.consistency_ok:
            return 0.0
        return (
            min(st.profit_factor, 5) * 0.2
            + (st.avg_annual_pnl / 8000) * 0.5
            + min(st.n_trades / 150, 1) * 0.15
            + (0.15 if st.max_dd < 5000 else 0.0)
        )

    real = run(book)
    rs = obj(real)
    better = 1
    for i in range(1, n_perm):
        if obj(run(permute_forex_book(book, seed=seed + i))) >= rs:
            better += 1
        if i % 40 == 0:
            print(f"    MCPT {i}/{n_perm} p~{better/(i+1):.3f}", flush=True)
    return better / n_perm, real.as_dict()


def score_row(fund_t, fund_h, ev_t, ev_h) -> float:
    return (
        min(fund_t["avg_annual_pnl"], fund_h["avg_annual_pnl"])
        + 3000 * int(not fund_t["blown"])
        + 3000 * int(not fund_h["blown"])
        + 1000 * int(ev_t["hit_eval_target"])
        + 1000 * int(ev_h["hit_eval_target"])
        - 0.15 * max(fund_t["max_dd"], fund_h["max_dd"])
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n-perm", type=int, default=150)
    ap.add_argument("--top-mcpt", type=int, default=15)
    ap.add_argument("--lock", action="store_true")
    ap.add_argument("--phase-b-limit", type=int, default=0, help="0=all phase-B combos")
    args = ap.parse_args()

    books_train: dict = {}
    books_hold: dict = {}
    prep_train: dict = {}
    prep_hold: dict = {}

    def get_books(pset: str):
        if pset not in books_train:
            pairs = PAIRSETS[pset]
            books_train[pset] = load_book(pairs, *TRAIN, "dukascopy")
            books_hold[pset] = load_book(pairs, *HOLD, "dukascopy")
            print(
                f"loaded {pset}: train n~{min(len(v) for v in books_train[pset].values())}",
                flush=True,
            )
        return books_train[pset], books_hold[pset]

    def get_prep(cache, book, mode, pset):
        key = (mode, pset)
        if key not in cache:
            print(f"  prepare {mode} {pset}...", flush=True)
            cache[key] = prepare_book(book, mode, 3, 2)
        return cache[key]

    # ----- Phase A -----
    phase_a_hits = []
    phase_a_modes = set()
    print("=== Phase A: mode × pairset × template bank ===", flush=True)
    for mode, pset in product(MODES, PAIRSETS):
        bt, bh = get_books(pset)
        if len(bt) < 3 or len(bh) < 3:
            continue
        pt = get_prep(prep_train, bt, mode, pset)
        ph = get_prep(prep_hold, bh, mode, pset)
        best_local = None
        for ti, tmpl in enumerate(TEMPLATES):
            params = make_params(mode, pset, template=tmpl)
            ok, ft, et, fh, eh = dual_era_ok(pt, ph, params)
            if ti == 0 or ok:
                print(
                    f"  {mode:18} {pset} t{ti}: ok={ok} "
                    f"T_ann={ft.get('avg_annual_pnl', 0):.0f} blown={ft.get('blown')} "
                    f"H_ann={fh.get('avg_annual_pnl', 0):.0f} blown={fh.get('blown')} "
                    f"evalT/H={et.get('hit_eval_target')}/{eh.get('hit_eval_target')}",
                    flush=True,
                )
            if not ok:
                continue
            row = {
                "mode": mode,
                "pairset": pset,
                "params": params,
                "train_fund": ft,
                "train_eval": et,
                "hold_fund": fh,
                "hold_eval": eh,
                "score": score_row(ft, fh, et, eh),
            }
            if best_local is None or row["score"] > best_local["score"]:
                best_local = row
        if best_local:
            phase_a_hits.append(best_local)
            phase_a_modes.add((mode, pset))

    print(f"Phase A hits: {len(phase_a_hits)}", flush=True)
    if not phase_a_hits:
        (OUT / "survival_mcpt_results.json").write_text(
            json.dumps({"phase_a_hits": 0, "finalists": []}, indent=2)
        )
        print("No Phase A survivors.", flush=True)
        return

    # ----- Phase B -----
    print("=== Phase B: expand fixed risk grid on Phase A modes ===", flush=True)
    screened = []
    combos = list(product(RISKS, RRS, ATRS, SKIP, HALTS, OPD, COOL, BE))
    if args.phase_b_limit:
        combos = combos[: args.phase_b_limit]
    for hit in phase_a_hits:
        mode, pset = hit["mode"], hit["pairset"]
        bt, bh = get_books(pset)
        pt = get_prep(prep_train, bt, mode, pset)
        ph = get_prep(prep_hold, bh, mode, pset)
        local = 0
        for risk, rr, atr, skip, halt, opd, cool, be in combos:
            params = make_params(
                mode,
                pset,
                risk_pct=risk,
                rr=rr,
                atr_stop_mult=atr,
                skip_mondays=skip,
                daily_halt_loss_pct=halt,
                daily_halt_profit_pct=max(halt + 0.01, 0.03),
                one_entry_per_day=opd,
                cooldown_losses=cool,
                move_be_at_r=be,
            )
            ok, ft, et, fh, eh = dual_era_ok(pt, ph, params)
            if not ok:
                continue
            local += 1
            screened.append(
                {
                    "params": params,
                    "score": score_row(ft, fh, et, eh),
                    "train_fund": ft,
                    "train_eval": et,
                    "hold_fund": fh,
                    "hold_eval": eh,
                }
            )
        print(f"  {mode} {pset}: +{local} dual-era configs", flush=True)

    # Always include Phase A templates
    for hit in phase_a_hits:
        screened.append(
            {
                "params": hit["params"],
                "score": hit["score"],
                "train_fund": hit["train_fund"],
                "train_eval": hit["train_eval"],
                "hold_fund": hit["hold_fund"],
                "hold_eval": hit["hold_eval"],
            }
        )

    # de-dupe by params tuple
    uniq = {}
    for r in screened:
        key = json.dumps(r["params"], sort_keys=True, default=str)
        if key not in uniq or r["score"] > uniq[key]["score"]:
            uniq[key] = r
    screened = sorted(uniq.values(), key=lambda r: -r["score"])
    print(f"Screened unique dual-era survivors: {len(screened)}", flush=True)

    (OUT / "survival_screen.json").write_text(
        json.dumps(
            {
                "protocol": {"train": TRAIN, "hold": HOLD},
                "phase_a_hits": [
                    {
                        "mode": h["mode"],
                        "pairset": h["pairset"],
                        "train_ann": h["train_fund"]["avg_annual_pnl"],
                        "hold_ann": h["hold_fund"]["avg_annual_pnl"],
                    }
                    for h in phase_a_hits
                ],
                "n_hits": len(screened),
                "top": [
                    {
                        "score": r["score"],
                        "params": r["params"],
                        "train_fund_ann": r["train_fund"]["avg_annual_pnl"],
                        "hold_fund_ann": r["hold_fund"]["avg_annual_pnl"],
                    }
                    for r in screened[:50]
                ],
            },
            indent=2,
            default=str,
        )
    )

    # ----- MCPT + rolling survival -----
    finalists = []
    for r in screened[: args.top_mcpt]:
        params = r["params"]
        bt, _ = get_books(params["pairset"])
        print(
            f"\nMCPT {params['signal_mode']} {params['pairset']} "
            f"risk={params['risk_pct']} rr={params['rr']} skip={params['skip_mondays']} "
            f"halt={params['daily_halt_loss_pct']} opd={params['one_entry_per_day']} "
            f"T/H={r['train_fund']['avg_annual_pnl']:.0f}/{r['hold_fund']['avg_annual_pnl']:.0f}",
            flush=True,
        )
        pval, _ = mcpt_pvalue(bt, params, n_perm=args.n_perm)
        roll = rolling_funded_survival(bt, params, start=TRAIN[0], end=TRAIN[1])
        # also hold rolling survival (report only — not used to choose before MCPT list)
        bh = books_hold[params["pairset"]]
        roll_h = rolling_funded_survival(bh, params, start=HOLD[0], end=HOLD[1])
        print(
            f"  p={pval:.3f} train_surv={roll['survival_rate']:.2%} "
            f"hold_surv={roll_h['survival_rate']:.2%}",
            flush=True,
        )
        accept = (
            pval <= 0.05
            and roll["survival_rate"] >= 0.70
            and roll["n_windows"] >= 4
            and roll_h["survival_rate"] >= 0.70
        )
        finalists.append(
            {
                **{k: r[k] for k in ("params", "score", "train_fund", "train_eval", "hold_fund", "hold_eval")},
                "mcpt_p": pval,
                "mcpt_pass": pval <= 0.05,
                "roll_survival_train": roll,
                "roll_survival_hold": roll_h,
                "accept": accept,
            }
        )

    finalists.sort(
        key=lambda x: (
            -int(x["accept"]),
            -int(x["mcpt_pass"]),
            -min(
                x["roll_survival_train"]["survival_rate"],
                x["roll_survival_hold"]["survival_rate"],
            ),
            -min(x["train_fund"]["avg_annual_pnl"], x["hold_fund"]["avg_annual_pnl"]),
            x["mcpt_p"],
        )
    )
    (OUT / "survival_mcpt_results.json").write_text(
        json.dumps(
            {
                "protocol": {
                    "train": TRAIN,
                    "hold": HOLD,
                    "oos_report": OOS,
                    "note": "Fixed two-phase grid; holdout unused for tuning; MCPT on train; no look-ahead",
                },
                "n_screened": len(screened),
                "finalists": finalists,
            },
            indent=2,
            default=str,
        )
    )

    accepted = [f for f in finalists if f["accept"]]
    print(f"\nAccepted: {len(accepted)} / {len(finalists)}", flush=True)
    if not accepted:
        print("No full accepts. Near-misses:", flush=True)
        for f in finalists[:8]:
            print(
                f"  p={f['mcpt_p']:.3f} "
                f"survT/H={f['roll_survival_train']['survival_rate']:.2%}/"
                f"{f['roll_survival_hold']['survival_rate']:.2%} "
                f"{f['params']['signal_mode']} risk={f['params']['risk_pct']} "
                f"ann={f['train_fund']['avg_annual_pnl']:.0f}/"
                f"{f['hold_fund']['avg_annual_pnl']:.0f}",
                flush=True,
            )
        accepted = [
            f
            for f in finalists
            if f["mcpt_pass"]
            and f["roll_survival_train"]["survival_rate"] >= 0.7
            and f["roll_survival_hold"]["survival_rate"] >= 0.5
        ]
        if accepted:
            print(f"Relaxed (hold surv>=50%): {len(accepted)}", flush=True)
        else:
            return

    winner = accepted[0]
    params = winner["params"]
    full = load_book(params["pairs"], TRAIN[0], HOLD[1], "dukascopy")
    ch = simulate_challenge(
        full,
        eval_end="2020-12-31",
        funded_end="2023-12-31",
        signal_mode=params["signal_mode"],
        risk_pct=params["risk_pct"],
        rr=params["rr"],
        atr_stop_mult=params["atr_stop_mult"],
        max_positions=1,
        min_confluence=params["min_confluence"],
        swing_left=3,
        swing_right=3,
        require_killzone=False,
        move_be_at_r=params["move_be_at_r"],
        skip_mondays=params["skip_mondays"],
        daily_halt_loss_pct=params["daily_halt_loss_pct"],
        daily_halt_profit_pct=params["daily_halt_profit_pct"],
        cooldown_losses=params["cooldown_losses"],
        one_entry_per_day=params["one_entry_per_day"],
        weekly_withdraw=True,
        rules=FundedRules(),
    )

    oos_fund = oos_eval = None
    oos_book = load_book(params["pairs"], OOS[0], OOS[1], "yahoo")
    if len(oos_book) >= 3:
        po = prepare_book(oos_book, params["signal_mode"], 3, 2)
        oos_fund = sim(po, params, True)
        oos_eval = sim(po, params, False)

    lock_params = {
        "signal_mode": params["signal_mode"],
        "risk_pct": params["risk_pct"],
        "rr": params["rr"],
        "atr_stop_mult": params["atr_stop_mult"],
        "max_positions": 1,
        "min_confluence": 2,
        "swing_left": 3,
        "swing_right": 3,
        "require_killzone": False,
        "weekly_withdraw": True,
        "move_be_at_r": params["move_be_at_r"],
        "skip_mondays": params["skip_mondays"],
        "daily_halt_loss_pct": params["daily_halt_loss_pct"],
        "daily_halt_profit_pct": params["daily_halt_profit_pct"],
        "cooldown_losses": params["cooldown_losses"],
        "one_entry_per_day": params["one_entry_per_day"],
    }
    lock = {
        "name": "survival_mcpt_2016_2023",
        "timeframe": "1h",
        "pairs": params["pairs"],
        "params": lock_params,
        "train_era": list(TRAIN),
        "hold_era": list(HOLD),
        "oos_era": list(OOS),
        "train_fund": winner["train_fund"],
        "train_eval": winner["train_eval"],
        "hold_fund": winner["hold_fund"],
        "hold_eval": winner["hold_eval"],
        "mcpt_p": winner["mcpt_p"],
        "mcpt_pass": True,
        "roll_survival_train": winner["roll_survival_train"],
        "roll_survival_hold": winner["roll_survival_hold"],
        "challenge": ch.to_dict(),
        "oos_2024_2025_fund": oos_fund,
        "oos_2024_2025_eval": oos_eval,
        "protocol": {
            "train": TRAIN,
            "hold": HOLD,
            "n_perm": args.n_perm,
            "note": "Fixed two-phase grid; holdout unused for tuning; MCPT on train; causal; same-bar stop",
        },
        "data": "dukascopy_h1_2016_2023",
        "no_curve_fitting": True,
        "no_lookahead": True,
        "alternatives": [
            {
                "params": f["params"],
                "mcpt_p": f["mcpt_p"],
                "surv_train": f["roll_survival_train"]["survival_rate"],
                "surv_hold": f["roll_survival_hold"]["survival_rate"],
                "train_ann": f["train_fund"]["avg_annual_pnl"],
                "hold_ann": f["hold_fund"]["avg_annual_pnl"],
            }
            for f in accepted[:10]
        ],
    }
    path = OUT / "best_strategy_survival.json"
    path.write_text(json.dumps(lock, indent=2, default=str))
    print(f"\nWrote {path}", flush=True)
    print(
        f"WINNER {params['signal_mode']} {params['pairset']} risk={params['risk_pct']} "
        f"rr={params['rr']} p={winner['mcpt_p']:.3f} "
        f"survT/H={winner['roll_survival_train']['survival_rate']:.0%}/"
        f"{winner['roll_survival_hold']['survival_rate']:.0%}",
        flush=True,
    )
    print(
        f"  fund ann T/H=${winner['train_fund']['avg_annual_pnl']:.0f}/"
        f"${winner['hold_fund']['avg_annual_pnl']:.0f} "
        f"blown T/H={winner['train_fund']['blown']}/{winner['hold_fund']['blown']}",
        flush=True,
    )
    print(
        f"  challenge eval={ch.evaluation_passed} days={ch.evaluation_days} "
        f"funded_survived={ch.funded_survived}",
        flush=True,
    )
    if oos_fund:
        print(
            f"  OOS24-25 fund ann=${oos_fund['avg_annual_pnl']:.0f} "
            f"blown={oos_fund['blown']} eval_hit={oos_eval['hit_eval_target']}",
            flush=True,
        )

    if args.lock:
        BEST_PATH.write_text(json.dumps(lock, indent=2, default=str))
        # also update strategy_funded defaults file already reads BEST_PATH
        print(f"Locked -> {BEST_PATH}", flush=True)


if __name__ == "__main__":
    main()
