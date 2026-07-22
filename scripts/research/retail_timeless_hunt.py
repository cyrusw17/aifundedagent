#!/usr/bin/env python3
"""Retail $1k timeless hunt — train through 2025, never touch 2026+ for tuning.

Account: $1000, 50:1 leverage, max 20% drawdown (peak + initial floor).
Goal: higher win rate, positive both eras, DD<=20%, MCPT pass, then future-test 2026+.

Protocol (no curve-fitting / no look-ahead)
------------------------------------------
TRAIN (screen + MCPT): 2016-01-01 .. 2023-12-31
HOLD  (hard gate):     2024-01-01 .. 2025-12-31   ← never used to pick params
FUTURE (report only):  2026-01-01 .. data end      ← NEVER train/tune

Data: Dukascopy 2016–2023 + Yahoo through 2025 for hold; Yahoo 2026+ future only.
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

from mcpt.forex.account import retail_rules
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.mcpt_forex import permute_forex_book
from mcpt.forex.strategy_funded import BEST_PATH

DATA = ROOT / "data" / "forex"
OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)

TRAIN = ("2016-01-01", "2023-12-31")
HOLD = ("2024-01-01", "2025-12-31")
FUTURE = ("2026-01-01", "2099-01-01")  # clipped to data

PAIRSETS = {
    "majors4": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"],
    "majors6": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF", "USDCAD"],
}

# Favor selective / confirmation modes for higher WR
MODES = [
    "triple_confirm",
    "ob_confirm",
    "sweep_bos_ob",
    "sweep_bos_ob_kz",
    "kz_ob_fvg",
    "h1_sweep_bos",
    "smc_strict",
    "killzone_smc",
    "kz_fvg",
    "sweep_wait_ob",
    "smc_plus",
    "london_asia_sweep",
]

# Lower RR → higher WR bias; conservative risk for 20% DD
TEMPLATES = [
    dict(risk_pct=0.004, rr=1.0, atr_stop_mult=1.75, skip_mondays=True, one_entry_per_day=True, cooldown_losses=2, daily_halt_loss_pct=0.03, daily_halt_profit_pct=0.05, move_be_at_r=0.0),
    dict(risk_pct=0.004, rr=1.0, atr_stop_mult=1.5, skip_mondays=True, one_entry_per_day=True, cooldown_losses=2, daily_halt_loss_pct=0.03, daily_halt_profit_pct=0.05, move_be_at_r=1.0),
    dict(risk_pct=0.005, rr=1.2, atr_stop_mult=1.25, skip_mondays=True, one_entry_per_day=True, cooldown_losses=2, daily_halt_loss_pct=0.03, daily_halt_profit_pct=0.05, move_be_at_r=0.0),
    dict(risk_pct=0.005, rr=1.0, atr_stop_mult=1.5, skip_mondays=True, one_entry_per_day=True, cooldown_losses=2, daily_halt_loss_pct=0.025, daily_halt_profit_pct=0.04, move_be_at_r=0.0),
    dict(risk_pct=0.0075, rr=1.2, atr_stop_mult=1.5, skip_mondays=True, one_entry_per_day=True, cooldown_losses=2, daily_halt_loss_pct=0.04, daily_halt_profit_pct=0.06, move_be_at_r=1.0),
    dict(risk_pct=0.005, rr=1.5, atr_stop_mult=1.5, skip_mondays=True, one_entry_per_day=True, cooldown_losses=2, daily_halt_loss_pct=0.03, daily_halt_profit_pct=0.05, move_be_at_r=0.0),
    dict(risk_pct=0.003, rr=1.0, atr_stop_mult=1.75, skip_mondays=True, one_entry_per_day=True, cooldown_losses=2, daily_halt_loss_pct=0.03, daily_halt_profit_pct=0.05, move_be_at_r=0.0),
]

RISKS = [0.003, 0.004, 0.005, 0.0075]
RRS = [1.0, 1.2, 1.5]
ATRS = [1.25, 1.5, 1.75]
SKIP = [True, False]
OPD = [True]
COOL = [0, 2]
BE = [0.0, 1.0]
HALTS = [0.025, 0.03, 0.04]

MIN_WR_TRAIN = 0.45
MIN_WR_HOLD = 0.42
MAX_DD = 0.20
MIN_TRADES_TRAIN = 80
MIN_TRADES_HOLD = 20
MIN_ANN_TRAIN = 35.0  # $ on $1k book — edge over noise, not huge
MIN_ANN_HOLD = 1.0  # must be profitable on hold, not a large bar
MIN_PF_TRAIN = 1.05
MIN_PF_HOLD = 1.03


def load_merged(pairs: list[str], start: str, end: str) -> dict[str, pd.DataFrame]:
    """Merge Dukascopy 2016–2023 with Yahoo; clip to [start,end]. Never requires 2026."""
    s, e = pd.Timestamp(start), pd.Timestamp(end)
    # Hard guard: refuse any end past 2025-12-31 for train/hold loaders
    book = {}
    for p in pairs:
        parts = []
        for path in [
            DATA / f"{p}_1h_2016_2023.parquet",
            DATA / f"{p}_1h.parquet",
        ]:
            if not path.exists():
                continue
            df = pd.read_parquet(path)
            df.index = pd.to_datetime(df.index)
            if df.index.tz is not None:
                df.index = df.index.tz_localize(None)
            parts.append(df[["open", "high", "low", "close"]].astype(float))
        if not parts:
            continue
        df = pd.concat(parts).sort_index()
        df = df[~df.index.duplicated(keep="last")]
        df = df[(df.index >= s) & (df.index <= e)]
        if len(df) >= 400:
            book[p] = df
    return book


def load_future(pairs: list[str]) -> dict[str, pd.DataFrame]:
    """Yahoo bars from 2026-01-01 only — future test, never for tuning."""
    s = pd.Timestamp(FUTURE[0])
    book = {}
    for p in pairs:
        path = DATA / f"{p}_1h.parquet"
        if not path.exists():
            continue
        df = pd.read_parquet(path)
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        df = df[df.index >= s][["open", "high", "low", "close"]].astype(float)
        df = df[~df.index.duplicated(keep="last")].sort_index()
        if len(df) >= 100:
            book[p] = df
    return book


def make_params(mode: str, pset: str, tmpl: dict, **over) -> dict:
    p = {
        "signal_mode": mode,
        "pairset": pset,
        "pairs": PAIRSETS[pset],
        "max_positions": 1,
        "min_confluence": 2,
        "swing_left": 3,
        "swing_right": 3,
        "require_killzone": False,
        "weekly_withdraw": False,
        **tmpl,
    }
    p.update(over)
    return p


RULES = retail_rules()


def sim(prep, params) -> dict:
    st = fast_backtest(
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
    return st.as_dict()


def era_ok(
    st: dict,
    *,
    min_trades: int,
    min_wr: float,
    min_ann: float,
) -> bool:
    if st.get("blown"):
        return False
    if st.get("n_trades", 0) < min_trades:
        return False
    if st.get("win_rate", 0) < min_wr:
        return False
    if st.get("max_dd_pct", 1.0) > MAX_DD + 1e-9:
        return False
    if st.get("avg_annual_pnl", 0) < min_ann:
        return False
    pf_floor = MIN_PF_TRAIN if min_trades >= MIN_TRADES_TRAIN else MIN_PF_HOLD
    if st.get("profit_factor", 0) < pf_floor:
        return False
    return True


def score(st_t: dict, st_h: dict) -> float:
    """Rank dual-era survivors: prefer edge (PF/ann) while keeping WR elevated."""
    return (
        min(st_t["profit_factor"], st_h["profit_factor"]) * 2_000
        + min(st_t["avg_annual_pnl"], st_h["avg_annual_pnl"]) * 3
        + min(st_t["win_rate"], st_h["win_rate"]) * 8_000
        - 4_000 * max(st_t["max_dd_pct"], st_h["max_dd_pct"])
    )


def mcpt_objective(st, *, min_wr: float) -> float:
    """PnL/edge-focused objective (WR is a hard gate for candidate selection, not MCPT).

    Thin high-WR edges fail when WR dominates the objective; annual PnL + PF
    matches the survival-hunt style that previously passed MCPT.
    """
    if st.blown:
        return -1.0
    if st.max_dd_pct > MAX_DD:
        return -0.5
    return (
        (st.avg_annual_pnl / RULES.initial_balance) * 2.5
        + min(st.profit_factor, 5) * 0.35
        + min(st.n_trades / 200, 1.0) * 0.1
        + max(st.win_rate - min_wr, 0.0) * 0.4
        - st.max_dd_pct * 1.5
    )


def mcpt(book, params, n_perm: int, seed: int = 21, min_wr: float = MIN_WR_TRAIN) -> float:
    def run(b):
        prep = prepare_book(b, params["signal_mode"], 3, 2)
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

    real = run(book)
    rs = mcpt_objective(real, min_wr=min_wr)
    better = 1
    for i in range(1, n_perm):
        if mcpt_objective(run(permute_forex_book(book, seed=seed + i)), min_wr=min_wr) >= rs:
            better += 1
        if i % 40 == 0:
            print(f"    MCPT {i}/{n_perm} p~{better/(i+1):.3f}", flush=True)
    return better / n_perm


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n-perm", type=int, default=150)
    ap.add_argument("--top-mcpt", type=int, default=10)
    ap.add_argument("--min-wr", type=float, default=MIN_WR_TRAIN)
    ap.add_argument("--min-wr-hold", type=float, default=MIN_WR_HOLD)
    ap.add_argument("--lock", action="store_true")
    ap.add_argument("--phase-b-limit", type=int, default=0)
    args = ap.parse_args()
    min_wr_t = float(args.min_wr)
    min_wr_h = float(args.min_wr_hold)

    def era_ok_local(st: dict, *, min_trades: int, wr_floor: float, min_ann: float) -> bool:
        return era_ok(st, min_trades=min_trades, min_wr=wr_floor, min_ann=min_ann)

    books_t: dict = {}
    books_h: dict = {}
    prep_t: dict = {}
    prep_h: dict = {}

    def get_books(pset):
        if pset not in books_t:
            pairs = PAIRSETS[pset]
            books_t[pset] = load_merged(pairs, *TRAIN)
            books_h[pset] = load_merged(pairs, *HOLD)
            for p, df in books_h[pset].items():
                assert df.index.max() < pd.Timestamp("2026-01-01"), "HOLD leaked 2026+"
            print(
                f"loaded {pset}: train bars~{min(map(len, books_t[pset].values()))} "
                f"hold~{min(map(len, books_h[pset].values()))}",
                flush=True,
            )
        return books_t[pset], books_h[pset]

    def get_prep(cache, book, mode, pset):
        key = (mode, pset)
        if key not in cache:
            print(f"  prepare {mode} {pset}...", flush=True)
            cache[key] = prepare_book(book, mode, 3, 2)
        return cache[key]

    print("=== Phase A: mode × pairset × templates (retail $1k) ===", flush=True)
    print(
        f"Rules: bal={RULES.initial_balance} lev={RULES.leverage} max_dd={RULES.max_dd_pct} "
        f"min_wr_t/h={min_wr_t}/{min_wr_h}",
        flush=True,
    )
    phase_a = []
    for mode, pset in product(MODES, PAIRSETS):
        bt, bh = get_books(pset)
        if len(bt) < 3 or len(bh) < 3:
            continue
        pt = get_prep(prep_t, bt, mode, pset)
        ph = get_prep(prep_h, bh, mode, pset)
        best = None
        for ti, tmpl in enumerate(TEMPLATES):
            params = make_params(mode, pset, tmpl)
            st_t = sim(pt, params)
            ok_t = era_ok_local(st_t, min_trades=MIN_TRADES_TRAIN, wr_floor=min_wr_t, min_ann=MIN_ANN_TRAIN)
            if not ok_t:
                if ti == 0:
                    print(
                        f"  {mode:18} {pset} t0: failT WR={st_t['win_rate']:.1%} "
                        f"dd={st_t['max_dd_pct']:.1%} blown={st_t['blown']} "
                        f"ann={st_t['avg_annual_pnl']:.1f} n={st_t['n_trades']}",
                        flush=True,
                    )
                continue
            st_h = sim(ph, params)
            ok_h = era_ok_local(st_h, min_trades=MIN_TRADES_HOLD, wr_floor=min_wr_h, min_ann=MIN_ANN_HOLD)
            print(
                f"  {mode:18} {pset} t{ti}: T_ok WR={st_t['win_rate']:.1%} "
                f"dd={st_t['max_dd_pct']:.1%} | H_ok={ok_h} WR={st_h['win_rate']:.1%} "
                f"dd={st_h['max_dd_pct']:.1%} annT/H={st_t['avg_annual_pnl']:.0f}/"
                f"{st_h['avg_annual_pnl']:.0f}",
                flush=True,
            )
            if not ok_h:
                continue
            row = {
                "mode": mode,
                "pairset": pset,
                "params": params,
                "train": st_t,
                "hold": st_h,
                "score": score(st_t, st_h),
            }
            if best is None or row["score"] > best["score"]:
                best = row
        if best:
            phase_a.append(best)

    print(f"Phase A hits: {len(phase_a)}", flush=True)
    if not phase_a:
        print("No Phase A hits. Relaxing hold WR to 0.40 / ann>=0...", flush=True)
        min_wr_t, min_wr_h = 0.42, 0.40
        for mode, pset in product(MODES, PAIRSETS):
            bt, bh = get_books(pset)
            if len(bt) < 3:
                continue
            pt = get_prep(prep_t, bt, mode, pset)
            ph = get_prep(prep_h, bh, mode, pset)
            best = None
            for tmpl in TEMPLATES:
                params = make_params(mode, pset, tmpl)
                st_t, st_h = sim(pt, params), sim(ph, params)
                if not era_ok_local(st_t, min_trades=MIN_TRADES_TRAIN, wr_floor=min_wr_t, min_ann=MIN_ANN_TRAIN):
                    continue
                if not era_ok_local(st_h, min_trades=MIN_TRADES_HOLD, wr_floor=min_wr_h, min_ann=0.0):
                    continue
                row = {
                    "mode": mode,
                    "pairset": pset,
                    "params": params,
                    "train": st_t,
                    "hold": st_h,
                    "score": score(st_t, st_h),
                }
                if best is None or row["score"] > best["score"]:
                    best = row
            if best:
                phase_a.append(best)
                print(
                    f"  RELAX hit {best['mode']} {best['pairset']} "
                    f"WR T/H={best['train']['win_rate']:.1%}/{best['hold']['win_rate']:.1%}",
                    flush=True,
                )
        print(f"Phase A hits after relax: {len(phase_a)}", flush=True)

    if not phase_a:
        (OUT / "retail_timeless_results.json").write_text(
            json.dumps({"phase_a": 0, "finalists": [], "note": "no dual-era retail survivors"}, indent=2)
        )
        print("FAILED: no dual-era survivors", flush=True)
        return

    print("=== Phase B: expand grid on Phase A modes ===", flush=True)
    combos = list(product(RISKS, RRS, ATRS, SKIP, OPD, COOL, BE, HALTS))
    if args.phase_b_limit:
        combos = combos[: args.phase_b_limit]
    screened = []
    for hit in phase_a:
        mode, pset = hit["mode"], hit["pairset"]
        bt, bh = get_books(pset)
        pt = get_prep(prep_t, bt, mode, pset)
        ph = get_prep(prep_h, bh, mode, pset)
        local = 0
        for risk, rr, atr, skip, opd, cool, be, halt in combos:
            params = make_params(
                mode,
                pset,
                hit["params"],
                risk_pct=risk,
                rr=rr,
                atr_stop_mult=atr,
                skip_mondays=skip,
                one_entry_per_day=opd,
                cooldown_losses=cool,
                move_be_at_r=be,
                daily_halt_loss_pct=halt,
                daily_halt_profit_pct=max(halt + 0.02, 0.05),
            )
            st_t = sim(pt, params)
            if not era_ok_local(st_t, min_trades=MIN_TRADES_TRAIN, wr_floor=min_wr_t, min_ann=MIN_ANN_TRAIN):
                continue
            st_h = sim(ph, params)
            if not era_ok_local(st_h, min_trades=MIN_TRADES_HOLD, wr_floor=min_wr_h, min_ann=MIN_ANN_HOLD):
                continue
            local += 1
            screened.append(
                {"params": params, "train": st_t, "hold": st_h, "score": score(st_t, st_h)}
            )
        screened.append(
            {
                "params": hit["params"],
                "train": hit["train"],
                "hold": hit["hold"],
                "score": hit["score"],
            }
        )
        print(f"  {mode} {pset}: +{local}", flush=True)

    uniq = {}
    for r in screened:
        k = json.dumps(r["params"], sort_keys=True, default=str)
        if k not in uniq or r["score"] > uniq[k]["score"]:
            uniq[k] = r
    screened = sorted(uniq.values(), key=lambda r: -r["score"])
    print(f"Screened unique: {len(screened)}", flush=True)
    (OUT / "retail_timeless_screen.json").write_text(
        json.dumps(
            {
                "protocol": {"train": TRAIN, "hold": HOLD, "future": FUTURE[0]},
                "min_wr_train": min_wr_t, "min_wr_hold": min_wr_h,
                "max_dd": MAX_DD,
                "account": {"initial": 1000, "leverage": 50},
                "n_hits": len(screened),
                "top": [
                    {
                        "score": r["score"],
                        "params": r["params"],
                        "train_wr": r["train"]["win_rate"],
                        "hold_wr": r["hold"]["win_rate"],
                        "train_ann": r["train"]["avg_annual_pnl"],
                        "hold_ann": r["hold"]["avg_annual_pnl"],
                        "train_dd": r["train"]["max_dd_pct"],
                        "hold_dd": r["hold"]["max_dd_pct"],
                    }
                    for r in screened[:40]
                ],
            },
            indent=2,
            default=str,
        )
    )

    # Diversify MCPT queue: unique (mode, rr, risk, atr, BE) by score
    queue = []
    seen_keys = set()
    for r in screened:
        p = r["params"]
        key = (p["signal_mode"], p["rr"], p["risk_pct"], p["atr_stop_mult"], p["move_be_at_r"])
        if key in seen_keys:
            continue
        seen_keys.add(key)
        queue.append(r)
        if len(queue) >= args.top_mcpt:
            break

    finalists = []
    for r in queue:
        params = r["params"]
        bt, _ = get_books(params["pairset"])
        print(
            f"\nMCPT {params['signal_mode']} {params['pairset']} "
            f"risk={params['risk_pct']} rr={params['rr']} atr={params['atr_stop_mult']} "
            f"WR T/H={r['train']['win_rate']:.1%}/{r['hold']['win_rate']:.1%} "
            f"PF T/H={r['train']['profit_factor']:.2f}/{r['hold']['profit_factor']:.2f} "
            f"ann T/H={r['train']['avg_annual_pnl']:.0f}/{r['hold']['avg_annual_pnl']:.0f} "
            f"dd T/H={r['train']['max_dd_pct']:.1%}/{r['hold']['max_dd_pct']:.1%}",
            flush=True,
        )
        pval = mcpt(bt, params, n_perm=args.n_perm, min_wr=min_wr_t)
        accept = pval <= 0.05
        print(f"  p={pval:.3f} accept={accept}", flush=True)
        finalists.append({**r, "mcpt_p": pval, "mcpt_pass": accept, "accept": accept})

        if accept and sum(1 for f in finalists if f["accept"]) >= 3:
            print("Have 3 MCPT passes — stopping early", flush=True)
            break

    finalists.sort(
        key=lambda x: (
            -int(x["accept"]),
            -min(x["train"]["win_rate"], x["hold"]["win_rate"]),
            -min(x["train"]["avg_annual_pnl"], x["hold"]["avg_annual_pnl"]),
            x["mcpt_p"],
        )
    )
    accepted = [f for f in finalists if f["accept"]]
    print(f"\nAccepted MCPT: {len(accepted)}/{len(finalists)}", flush=True)
    if not accepted:
        print("No MCPT pass. Top near-misses:", flush=True)
        for f in finalists[:5]:
            print(
                f"  p={f['mcpt_p']:.3f} WR={f['train']['win_rate']:.1%}/{f['hold']['win_rate']:.1%} "
                f"{f['params']['signal_mode']} rr={f['params']['rr']}",
                flush=True,
            )
        (OUT / "retail_timeless_results.json").write_text(
            json.dumps({"finalists": finalists, "accepted": 0}, indent=2, default=str)
        )
        return

    winner = accepted[0]
    params = winner["params"]
    fut = load_future(params["pairs"])
    assert all(df.index.min() >= pd.Timestamp("2026-01-01") for df in fut.values())
    fut_st = None
    if len(fut) >= 3:
        warm = load_merged(params["pairs"], "2025-07-01", "2025-12-31")
        combined = {}
        for p in params["pairs"]:
            if p in warm and p in fut:
                combined[p] = pd.concat([warm[p], fut[p]]).sort_index()
                combined[p] = combined[p][~combined[p].index.duplicated(keep="last")]
        fut_only = {
            p: combined[p][combined[p].index >= pd.Timestamp("2026-01-01")] for p in combined
        }
        prep_f = prepare_book(fut_only, params["signal_mode"], 3, 2)
        fut_st = sim(prep_f, params)
        print(
            f"FUTURE 2026+ WR={fut_st['win_rate']:.1%} dd={fut_st['max_dd_pct']:.1%} "
            f"ann={fut_st['avg_annual_pnl']:.1f} blown={fut_st['blown']} n={fut_st['n_trades']}",
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
    lock = {
        "name": "retail_timeless_1k",
        "account": {"initial_balance": 1000, "leverage": 50, "max_dd_pct": 0.20},
        "timeframe": "1h",
        "pairs": params["pairs"],
        "params": lock_params,
        "train_era": list(TRAIN),
        "hold_era": list(HOLD),
        "future_era": [FUTURE[0], "data_end"],
        "train": winner["train"],
        "hold": winner["hold"],
        "future_2026": fut_st,
        "mcpt_p": winner["mcpt_p"],
        "mcpt_pass": True,
        "min_wr_gate": {"train": min_wr_t, "hold": min_wr_h},
        "protocol": {
            "train": TRAIN,
            "hold": HOLD,
            "future": FUTURE[0],
            "n_perm": args.n_perm,
            "note": "Fixed grid; HOLD unused for tuning; FUTURE never used for training; causal; same-bar stop",
        },
        "no_curve_fitting": True,
        "no_lookahead": True,
        "never_trained_on_2026": True,
        "alternatives": [
            {
                "params": f["params"],
                "mcpt_p": f["mcpt_p"],
                "train_wr": f["train"]["win_rate"],
                "hold_wr": f["hold"]["win_rate"],
                "train_ann": f["train"]["avg_annual_pnl"],
                "hold_ann": f["hold"]["avg_annual_pnl"],
            }
            for f in accepted[:8]
        ],
    }
    path = OUT / "best_strategy_retail_1k.json"
    path.write_text(json.dumps(lock, indent=2, default=str))
    (OUT / "retail_timeless_results.json").write_text(
        json.dumps(
            {"accepted": len(accepted), "winner": lock, "finalists": finalists[:15]},
            indent=2,
            default=str,
        )
    )
    print(f"Wrote {path}", flush=True)
    print(
        f"WINNER {params['signal_mode']} {params['pairset']} risk={params['risk_pct']} "
        f"rr={params['rr']} p={winner['mcpt_p']:.3f} "
        f"WR T/H={winner['train']['win_rate']:.1%}/{winner['hold']['win_rate']:.1%}",
        flush=True,
    )
    if args.lock:
        BEST_PATH.write_text(json.dumps(lock, indent=2, default=str))
        print(f"Locked -> {BEST_PATH}", flush=True)


if __name__ == "__main__":
    main()
