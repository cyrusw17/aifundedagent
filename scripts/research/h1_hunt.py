#!/usr/bin/env python3
"""H1 killzone hunter aiming for >= $10k/yr under funded rules + MCPT.

Uses contiguous hist H1 (2018–early 2022). Recent yfinance H1 is validated
separately when available (Yahoo only keeps ~730d of 1h).
Never overwrites data/research/best_strategy.json unless the candidate is better.
"""

from __future__ import annotations

import json
import os
import random
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.challenge import rolling_eval_windows, simulate_challenge
from mcpt.forex.fast_sim import fast_backtest, prepare_book
from mcpt.forex.mcpt_forex import permute_forex_book

DATA = ROOT / "data" / "forex"
OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)
BEST_PATH = OUT / "best_strategy.json"
DAILY_BACKUP = OUT / "best_strategy_daily.json"

PAIRSETS = {
    "h1_majors4": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"],
    "h1_core5": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF"],
    "h1_all6": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF", "USDCAD"],
}
MODES = [
    "killzone_smc",
    "london_asia_sweep",
    "kz_fvg",
    "kz_active",
    "h1_sweep_bos",
    "smc_plus",
    "active_smc",
    "smc",
]


def load_h1(pairs, recent: bool = False):
    """Load H1 book. Default = contiguous hist 2018–2022. recent=True → yfinance window."""
    import pandas as pd

    book = {}
    for p in pairs:
        if recent:
            yf = DATA / f"{p}_1h.parquet"
            if not yf.exists():
                continue
            df = pd.read_parquet(yf)
            df.index = pd.to_datetime(df.index)
            if df.index.tz is not None:
                df.index = df.index.tz_localize(None)
        else:
            hist = DATA / f"{p}_1h_hist.parquet"
            if not hist.exists():
                continue
            df = pd.read_parquet(hist)
            df.index = pd.to_datetime(df.index)
            if df.index.tz is not None:
                df.index = df.index.tz_localize(None)
            # keep contiguous research window
            df = df[(df.index >= "2018-01-01") & (df.index <= "2022-03-04")]
        df = df[~df.index.duplicated(keep="last")].sort_index()
        if len(df) > 500:
            book[p] = df
    return book


def sample(rng):
    swing = rng.choice([2, 3, 4])
    mode = rng.choice(MODES)
    return dict(
        signal_mode=mode,
        risk_pct=rng.choice([0.005, 0.0065, 0.0075, 0.009, 0.01, 0.012]),
        rr=rng.choice([1.8, 2.0, 2.5, 3.0, 3.5]),
        atr_stop_mult=rng.choice([0.8, 1.0, 1.2, 1.4]),
        max_positions=rng.choice([1, 2, 3]),
        min_confluence=2,
        swing_left=swing,
        swing_right=swing,
        require_killzone=False,
        weekly_withdraw=True,
        move_be_at_r=rng.choice([0.0, 1.0]),
        skip_mondays=rng.choice([True, False]),
        daily_halt_loss_pct=rng.choice([0.015, 0.02, 0.025]),
        daily_halt_profit_pct=rng.choice([0.03, 0.04]),
        cooldown_losses=rng.choice([0, 2, 3]),
        one_entry_per_day=rng.choice([True, False]),
    )


def mutate(p, rng):
    q = dict(p)
    for k, vals in [
        ("risk_pct", [0.005, 0.0065, 0.0075, 0.009, 0.01, 0.012]),
        ("rr", [1.8, 2.0, 2.5, 3.0, 3.5]),
        ("atr_stop_mult", [0.8, 1.0, 1.2, 1.4]),
        ("max_positions", [1, 2, 3]),
        ("move_be_at_r", [0.0, 1.0]),
        ("one_entry_per_day", [True, False]),
        ("daily_halt_loss_pct", [0.015, 0.02, 0.025]),
        ("signal_mode", MODES),
        ("cooldown_losses", [0, 2, 3]),
        ("skip_mondays", [True, False]),
    ]:
        if rng.random() < 0.45:
            q[k] = rng.choice(vals)
    return q


def _work(args):
    pairs, params = args
    book = load_h1(pairs)
    if len(book) < 2:
        return params, {"blown": True, "avg_annual_pnl": -1e9, "consistency_ok": False, "n_trades": 0}
    prep = prepare_book(book, params["signal_mode"], params["swing_left"], 2)
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
        weekly_withdraw=True,
        one_entry_per_day=bool(params.get("one_entry_per_day", True)),
    )
    d = st.as_dict()
    d["n_pairs"] = len(book)
    return params, d


def mcpt(book, params, n=100, seed=5):
    def run(b):
        prep = prepare_book(b, params["signal_mode"], params["swing_left"], 2)
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
            one_entry_per_day=bool(params.get("one_entry_per_day", True)),
        )

    def obj(st):
        if st.blown:
            return -1
        if not st.consistency_ok:
            return 0
        return (
            min(st.profit_factor, 5) * 0.25
            + (st.avg_annual_pnl / 10000) * 0.65
            + min(st.n_trades / 200, 1) * 0.1
        )

    import pandas as pd

    cut = pd.Timestamp("2020-06-30")
    train = {k: v[v.index <= cut] for k, v in book.items()}
    if min(len(v) for v in train.values()) < 2000:
        train = {k: v.iloc[: int(len(v) * 0.6)] for k, v in book.items()}
    real = run(train)
    rs = obj(real)
    better = 1
    for i in range(1, n):
        if obj(run(permute_forex_book(train, seed=seed + i))) >= rs:
            better += 1
    return better / n, real.as_dict()


def validate(ps, pairs, params):
    import pandas as pd

    book = load_h1(pairs)
    rules = FundedRules()
    full = run_backtest(book, rules=rules, **params)
    eval_end = "2020-06-30"
    funded_end = str(min(v.index.max() for v in book.values()).date())
    ch = simulate_challenge(
        book, eval_end=eval_end, funded_end=funded_end, rules=rules, **params
    )
    rolls = rolling_eval_windows(
        book,
        start="2018-01-01",
        end=funded_end,
        window_days=300,
        step_days=90,
        rules=rules,
        **{k: v for k, v in params.items() if k != "weekly_withdraw"},
    )
    pr = sum(1 for r in rolls if r["passed"]) / max(len(rolls), 1)
    p_val, _ = mcpt(book, params, n=80)
    if p_val <= 0.08:
        p_val, _ = mcpt(book, params, n=150)
    oos = {k: v[v.index > pd.Timestamp(eval_end)] for k, v in book.items()}
    oos_bt = (
        run_backtest(oos, rules=rules, **params)
        if all(len(v) > 200 for v in oos.values())
        else full
    )
    recent = load_h1(pairs, recent=True)
    recent_stats = None
    if recent and all(len(v) > 200 for v in recent.values()):
        recent_stats = run_backtest(recent, rules=rules, **params).stats
    return dict(
        pairset=ps,
        pairs=list(book.keys()),
        timeframe="1h",
        data_window="2018-01-01..2022-03-04",
        params=params,
        mcpt_p=p_val,
        mcpt_pass=p_val <= 0.05,
        full_stats=full.stats,
        oos_stats=oos_bt.stats,
        recent_stats=recent_stats,
        challenge=ch.to_dict(),
        pass_rate=pr,
        data_end=funded_end,
    )


def rank_key(rec):
    fs, oos, ch = rec["full_stats"], rec["oos_stats"], rec["challenge"]
    recent = rec.get("recent_stats") or {}
    recent_ok = 1
    if recent:
        recent_ok = int(not recent.get("blown", True) and recent.get("avg_annual_pnl", -1) > -2000)
    return (
        int(rec["mcpt_pass"]),
        int(ch.get("funded_survived", False)),
        int(not fs["blown"]),
        int(fs.get("consistency_ok", False)),
        int(not oos.get("blown", True)),
        recent_ok,
        fs["avg_annual_pnl"],
        ch.get("funded_annual_pnl", 0),
        oos.get("avg_annual_pnl", 0),
    )


def is_hard_winner(rec):
    fs, oos, ch = rec["full_stats"], rec["oos_stats"], rec["challenge"]
    if not rec["mcpt_pass"] or fs["blown"] or oos.get("blown") or not fs["consistency_ok"]:
        return False
    if not ch["funded_survived"]:
        return False
    return fs["avg_annual_pnl"] >= 10000 or (
        ch["funded_annual_pnl"] >= 10000 and oos["avg_annual_pnl"] >= 5000
    )


def maybe_write_best(rec, current_best_key=None):
    """Write best_strategy.json only if strictly better than existing artifact."""
    existing = None
    if BEST_PATH.exists():
        try:
            existing = json.loads(BEST_PATH.read_text())
        except Exception:
            existing = None
    # keep daily backup once
    if existing and existing.get("timeframe") != "1h" and not DAILY_BACKUP.exists():
        DAILY_BACKUP.write_text(json.dumps(existing, indent=2, default=str))

    new_key = rank_key(rec)
    if existing:
        # synthesize comparable key for existing
        ex = deepcopy(existing)
        ex.setdefault("oos_stats", ex.get("full_stats", {}))
        ex.setdefault("challenge", {})
        old_key = rank_key(ex)
        if new_key <= old_key:
            (OUT / "h1_latest.json").write_text(json.dumps(rec, indent=2, default=str))
            return False, old_key
    BEST_PATH.write_text(json.dumps(rec, indent=2, default=str))
    (OUT / "h1_best.json").write_text(json.dumps(rec, indent=2, default=str))
    (OUT / "h1_latest.json").write_text(json.dumps(rec, indent=2, default=str))
    return True, new_key


def main():
    t0 = time.time()
    rng = random.Random(17)
    workers = max(2, min(4, os.cpu_count() or 4))
    print(f"H1 hunt workers={workers}", flush=True)
    for ps, pairs in PAIRSETS.items():
        b = load_h1(pairs)
        print(f"  hist {ps}: {{{', '.join(f'{k}:{len(v)}' for k,v in b.items())}}}", flush=True)

    # preserve daily winner
    if BEST_PATH.exists() and not DAILY_BACKUP.exists():
        cur = json.loads(BEST_PATH.read_text())
        if cur.get("timeframe") != "1h":
            DAILY_BACKUP.write_text(json.dumps(cur, indent=2, default=str))
            print("Backed up daily best_strategy.json", flush=True)

    elites = []
    best = None
    hard = None

    for rnd in range(1, 16):
        batch = []
        for _ in range(160):
            ps = rng.choice(list(PAIRSETS))
            batch.append((PAIRSETS[ps], sample(rng), ps))
        for p, s, ps, _ in elites[:24]:
            for _ in range(6):
                batch.append((PAIRSETS[ps], mutate(p, rng), ps))

        print(f"\n=== Round {rnd} n={len(batch)} ===", flush=True)
        hits = []
        with ProcessPoolExecutor(max_workers=workers) as ex:
            futs = {ex.submit(_work, (pairs, params)): ps for pairs, params, ps in batch}
            done = 0
            for fut in as_completed(futs):
                ps = futs[fut]
                params, stats = fut.result()
                done += 1
                if stats.get("blown") or not stats.get("consistency_ok"):
                    continue
                if stats.get("n_trades", 0) < 80:
                    continue
                if stats.get("avg_annual_pnl", -1e9) < 3000:
                    continue
                sc = stats["avg_annual_pnl"] + min(stats.get("profit_factor", 0), 3) * 800
                hits.append((params, stats, ps, sc))
                if done % 40 == 0:
                    top = max((h[1]["avg_annual_pnl"] for h in hits), default=0)
                    print(f"  {done}/{len(batch)} hits={len(hits)} top=${top:.0f}", flush=True)

        hits.sort(key=lambda x: x[3], reverse=True)
        if hits:
            print(
                f"  top ${hits[0][1]['avg_annual_pnl']:.0f} tr={hits[0][1]['n_trades']} "
                f"pf={hits[0][1]['profit_factor']:.2f} {hits[0][2]}|{hits[0][0]['signal_mode']}",
                flush=True,
            )
        elites = (hits[:40] + elites)[:60]
        elites.sort(key=lambda x: x[3], reverse=True)

        cands = [h for h in hits if h[1]["avg_annual_pnl"] >= 8000][:6] or hits[:4]
        for params, stats, ps, sc in cands:
            print(
                f"  validate {ps}|{params['signal_mode']} screen=${stats['avg_annual_pnl']:.0f} "
                f"tr={stats['n_trades']} risk={params['risk_pct']}",
                flush=True,
            )
            rec = validate(ps, PAIRSETS[ps], params)
            print(
                f"    p={rec['mcpt_p']:.3f} full=${rec['full_stats']['avg_annual_pnl']:.0f} "
                f"oos=${rec['oos_stats']['avg_annual_pnl']:.0f} fund=${rec['challenge']['funded_annual_pnl']:.0f} "
                f"eval={rec['challenge']['evaluation_passed']} pr={rec['pass_rate']:.2f}",
                flush=True,
            )
            if rec.get("recent_stats"):
                rs = rec["recent_stats"]
                print(
                    f"    recent ann=${rs['avg_annual_pnl']:.0f} blown={rs['blown']} "
                    f"tr={rs['n_trades']} pf={rs.get('profit_factor', 0):.2f}",
                    flush=True,
                )
            wrote, key = maybe_write_best(rec)
            if wrote:
                print("    wrote best_strategy.json (improved)", flush=True)
            if best is None or rank_key(rec) > best[0]:
                best = (rank_key(rec), rec)
                (OUT / "h1_best.json").write_text(json.dumps(rec, indent=2, default=str))
            if is_hard_winner(rec):
                hard = rec
                maybe_write_best(rec)
                break
        if hard:
            break

    rec = hard or (best[1] if best else None)
    if rec is None:
        print("No H1 candidates", flush=True)
        return
    (OUT / "h1_best.json").write_text(json.dumps(rec, indent=2, default=str))
    print("\n=== H1 SELECTED ===", flush=True)
    print(
        json.dumps(
            {
                "hard_winner": bool(hard),
                "pairset": rec["pairset"],
                "pairs": rec["pairs"],
                "timeframe": rec.get("timeframe"),
                "params": rec["params"],
                "mcpt_p": rec["mcpt_p"],
                "mcpt_pass": rec["mcpt_pass"],
                "full_ann": rec["full_stats"]["avg_annual_pnl"],
                "oos_ann": rec["oos_stats"]["avg_annual_pnl"],
                "fund_ann": rec["challenge"]["funded_annual_pnl"],
                "eval": rec["challenge"]["evaluation_passed"],
                "survived": rec["challenge"]["funded_survived"],
                "pr": rec["pass_rate"],
                "trades": rec["full_stats"]["n_trades"],
                "pf": rec["full_stats"]["profit_factor"],
                "blown": rec["full_stats"]["blown"],
            },
            indent=2,
        ),
        flush=True,
    )
    print(f"Elapsed {time.time()-t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
