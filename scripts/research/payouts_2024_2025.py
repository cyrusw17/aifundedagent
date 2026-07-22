#!/usr/bin/env python3
"""Monthly payout report for locked strategy on 2024-2025 Yahoo H1 only.

Runs funded-style weekly withdrawals ($250 min / $2k cap) and also
compounding (no withdraw) for comparison. Warmup bars from late 2023
are used for SMC features but the account clock starts 2024-01-01.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import run_backtest
from mcpt.forex.strategy_funded import load_best

DATA = ROOT / "data" / "forex"
OUT = ROOT / "data" / "research"
OUT.mkdir(parents=True, exist_ok=True)

TEST_START = "2024-01-01"
TEST_END = "2025-12-31"
WARMUP_START = "2023-10-02"


def load_yahoo_h1(pairs: list[str], start: str, end: str) -> dict[str, pd.DataFrame]:
    book = {}
    s, e = pd.Timestamp(start), pd.Timestamp(end)
    for p in pairs:
        path = DATA / f"{p}_1h.parquet"
        if not path.exists():
            continue
        df = pd.read_parquet(path)
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        df = df[(df.index >= s) & (df.index <= e)]
        df = df[~df.index.duplicated(keep="last")].sort_index()
        if len(df) >= 200:
            book[p] = df
    return book


def bt_kwargs(params: dict, weekly_withdraw: bool) -> dict:
    return dict(
        signal_mode=params["signal_mode"],
        risk_pct=float(params["risk_pct"]),
        rr=float(params["rr"]),
        atr_stop_mult=float(params["atr_stop_mult"]),
        max_positions=int(params.get("max_positions", 1)),
        min_confluence=int(params.get("min_confluence", 2)),
        swing_left=int(params.get("swing_left", 3)),
        swing_right=int(params.get("swing_right", 3)),
        require_killzone=bool(params.get("require_killzone", False)),
        move_be_at_r=float(params.get("move_be_at_r", 0.0)),
        skip_mondays=bool(params.get("skip_mondays", False)),
        daily_halt_loss_pct=float(params.get("daily_halt_loss_pct", 0.025)),
        daily_halt_profit_pct=float(params.get("daily_halt_profit_pct", 0.04)),
        cooldown_losses=int(params.get("cooldown_losses", 2)),
        one_entry_per_day=bool(params.get("one_entry_per_day", False)),
        weekly_withdraw=weekly_withdraw,
        rules=FundedRules(),
    )


def monthly_from_withdrawals(withdrawals: list[dict], start: str, end: str) -> pd.Series:
    rows = []
    s, e = pd.Timestamp(start), pd.Timestamp(end)
    for w in withdrawals:
        d = pd.Timestamp(w["date"])
        if d < s or d > e:
            continue
        rows.append({"month": d.to_period("M"), "amount": float(w["amount"])})
    if not rows:
        # still return empty months over the window
        idx = pd.period_range(start, end, freq="M")
        return pd.Series(0.0, index=idx, name="payout")
    df = pd.DataFrame(rows)
    monthly = df.groupby("month")["amount"].sum()
    full = pd.period_range(start, end, freq="M")
    return monthly.reindex(full, fill_value=0.0).astype(float)


def recommend_buffer(monthly: pd.Series, rules: FundedRules, max_dd: float, blown: bool) -> dict:
    """Cash / account buffers grounded in prop rules + payout variance."""
    avg = float(monthly.mean()) if len(monthly) else 0.0
    med = float(monthly.median()) if len(monthly) else 0.0
    p25 = float(monthly.quantile(0.25)) if len(monthly) else 0.0
    worst = float(monthly.min()) if len(monthly) else 0.0
    nonzero = monthly[monthly > 0]
    avg_pay_month = float(nonzero.mean()) if len(nonzero) else 0.0

    # Personal runway: cover 3 months at average payout, or 2 months at avg of paying months
    personal_runway = max(3.0 * max(avg, 0.0), 2.0 * max(avg_pay_month, 0.0))
    # Stress: months can be $0 — keep enough to skip a bad quarter
    stress_quarter = float(monthly.rolling(3).sum().min()) if len(monthly) >= 3 else worst
    personal_stress = max(0.0, -stress_quarter) + 2.0 * max(avg_pay_month, 0.0)

    # On-account buffer: stay clear of $6k max-loss floor.
    # Cap is $2k/week — leaving ~$3k–$4k above initial before withdrawing
    # reduces blow risk vs draining every week to exactly $100k.
    account_keep_above_initial = 3_000.0
    # Also: don't treat max_dd as withdrawable — hold at least half of observed DD
    dd_buffer = 0.5 * float(max_dd) if max_dd and max_dd > 0 else 3_000.0

    recommended_personal = float(np.ceil(max(personal_runway, personal_stress) / 100.0) * 100.0)
    recommended_account = float(
        np.ceil(max(account_keep_above_initial, min(dd_buffer, 5_000.0)) / 100.0) * 100.0
    )

    return {
        "avg_monthly_payout": avg,
        "median_monthly_payout": med,
        "p25_monthly_payout": p25,
        "worst_month_payout": worst,
        "avg_nonzero_month": avg_pay_month,
        "prop_max_loss": rules.max_loss,
        "prop_weekly_cap": rules.withdraw_cap,
        "prop_weekly_min": rules.withdraw_min,
        "recommended_personal_cash_buffer_usd": recommended_personal,
        "recommended_keep_on_account_above_initial_usd": recommended_account,
        "rationale": (
            "Personal buffer ≈ 3× average monthly payout (or 2× avg paying month), "
            "stressed for zero-payout streaks. Account buffer keeps equity above "
            "initial so weekly drains do not sit on the $6k max-loss floor; "
            "also sized off ~half observed max drawdown, capped near $5k."
        ),
        "blown_in_test": blown,
        "max_dd_observed": float(max_dd),
    }


def main() -> None:
    best = load_best()
    pairs = best.get("pairs") or [
        "EURUSD",
        "GBPUSD",
        "USDJPY",
        "AUDUSD",
        "USDCHF",
        "USDCAD",
    ]
    params = best["params"]

    # Warmup for features, then restrict sim window to 2024-2025 only
    warmup_book = load_yahoo_h1(pairs, WARMUP_START, TEST_END)
    test_book = {
        p: df[(df.index >= pd.Timestamp(TEST_START)) & (df.index <= pd.Timestamp(TEST_END))].copy()
        for p, df in warmup_book.items()
    }
    # Prefer prepared signals on warmup+test so early-2024 OBs exist, then sim on test only
    # via run_backtest on test_book (cold-ish) OR full window with withdrawal filter.
    # Use full warmup+test for signal continuity, but reset account at TEST_START by
    # only simulating the test slice after preparing signals on the longer book.
    from mcpt.forex.backtest import prepare_market_book

    frames, feats, signals, all_times = prepare_market_book(
        warmup_book,
        signal_mode=params["signal_mode"],
        swing_left=int(params.get("swing_left", 3)),
        swing_right=int(params.get("swing_right", 3)),
        min_confluence=int(params.get("min_confluence", 2)),
        require_killzone=bool(params.get("require_killzone", False)),
    )
    # Restrict times + frames to test window (signals already causal from warmup)
    t0 = pd.Timestamp(TEST_START)
    t1 = pd.Timestamp(TEST_END)
    all_times_test = [t for t in all_times if t0 <= t <= t1]
    frames_test = {
        p: df[(df.index >= t0) & (df.index <= t1)].copy() for p, df in frames.items()
    }
    feats_test = {
        p: f.loc[frames_test[p].index] if p in frames_test else f for p, f in feats.items()
    }
    signals_test = {
        p: s.loc[frames_test[p].index] if p in frames_test else s for p, s in signals.items()
    }
    prepared = (frames_test, feats_test, signals_test, all_times_test)

    print(f"Pairs: {list(test_book.keys())}")
    print(f"Bars/pair (test): {[len(v) for v in test_book.values()]}")

    from collections import defaultdict

    # Funded payouts path
    kw_w = bt_kwargs(params, weekly_withdraw=True)
    bt_w = run_backtest(test_book, _prepared=prepared, **kw_w)
    monthly = monthly_from_withdrawals(bt_w.account.withdrawals, TEST_START, TEST_END)

    # Compounding path (no weekly withdraw)
    kw_g = bt_kwargs(params, weekly_withdraw=False)
    bt_g = run_backtest(test_book, _prepared=prepared, **kw_g)

    m_pnl: dict = defaultdict(float)
    m_n: dict = defaultdict(int)
    for tr in bt_g.trades:
        per = pd.Timestamp(tr.exit_time).to_period("M")
        m_pnl[per] += float(tr.pnl)
        m_n[per] += 1

    months_table = []
    for per, amt in monthly.items():
        months_table.append(
            {
                "month": str(per),
                "payout_usd": round(float(amt), 2),
                "closed_pnl_usd": round(float(m_pnl.get(per, 0.0)), 2),
                "n_trades": int(m_n.get(per, 0)),
            }
        )

    buf = recommend_buffer(
        monthly,
        FundedRules(),
        max_dd=float(bt_w.stats.get("max_dd", 0.0)),
        blown=bool(bt_w.account.blown),
    )
    buf["recommended_personal_cash_buffer_usd"] = max(
        float(buf["recommended_personal_cash_buffer_usd"]),
        6_000.0,
    )
    buf["recommended_keep_on_account_above_initial_usd"] = 4_000.0
    buf["note_2024_2025"] = (
        "On 2024-2025 Yahoo H1 the locked sweep_bos_ob edge did not hold: "
        "early profit + two weekly payouts in Jan 2024, then drawdown to the "
        "max-loss floor band (~$94k) froze new risk (room_to_floor too small). "
        "Most months show $0 payout. Treat this era as a failed OOS check for payout planning."
    )

    eq = bt_g.equity_curve
    hit = None
    for t, v in eq.items():
        if v >= 110_000:
            hit = t
            break
    days_to_eval = int((hit - eq.index[0]).days) if hit is not None and len(eq) else None
    peak_t = eq.idxmax() if len(eq) else None
    peak_v = float(eq.max()) if len(eq) else 0.0
    near = eq[eq <= 94_500.0] if len(eq) else eq
    freeze_t = str(near.index[0]) if len(near) else None

    report = {
        "window": [TEST_START, TEST_END],
        "data": "yahoo_h1_parquet",
        "warmup": [WARMUP_START, TEST_START],
        "strategy": {
            "name": best.get("name"),
            "pairs": pairs,
            "params": params,
        },
        "summary": {
            "total_payouts_usd": round(float(bt_w.account.total_withdrawn), 2),
            "avg_monthly_payout_usd": round(float(monthly.mean()), 2),
            "median_monthly_payout_usd": round(float(monthly.median()), 2),
            "months_with_payout": int((monthly > 0).sum()),
            "months_total": int(len(monthly)),
            "paying_months_avg_usd": round(
                float(monthly[monthly > 0].mean()) if (monthly > 0).any() else 0.0, 2
            ),
            "compounding_final_balance": round(float(bt_g.account.balance), 2),
            "compounding_peak_equity": round(peak_v, 2),
            "compounding_peak_time": str(peak_t),
            "days_to_plus_10pct": days_to_eval,
            "hit_eval_target": bool(bt_g.stats.get("hit_eval_target")),
            "trading_froze_near_floor_around": freeze_t,
            "n_trades_compounding": bt_g.stats["n_trades"],
            "n_trades_withdraw": bt_w.stats["n_trades"],
        },
        "monthly": months_table,
        "withdrawals": [
            {"date": str(w["date"]), "amount": round(float(w["amount"]), 2)}
            for w in bt_w.account.withdrawals
        ],
        "funded_stats": bt_w.stats,
        "compounding_stats": bt_g.stats,
        "buffer": buf,
        "prop_rules": {
            "initial": 100_000,
            "weekly_cap": 2_000,
            "weekly_min": 250,
            "max_loss": 6_000,
            "daily_loss": 3_000,
        },
        "note": (
            "Payouts use The5ers-style weekly withdraw: excess above $100k, "
            "min $250, cap $2000/week. 2024-2025 Yahoo H1 only; locked params "
            "unchanged (no retune)."
        ),
    }

    out_path = OUT / "payouts_2024_2025.json"
    out_path.write_text(json.dumps(report, indent=2, default=str))
    s = report["summary"]
    print("\n=== 2024-2025 payout summary (Yahoo H1, locked sweep_bos_ob) ===")
    print(
        f"Total payouts: ${s['total_payouts_usd']:,.2f} | "
        f"avg ${s['avg_monthly_payout_usd']:,.2f}/mo | median ${s['median_monthly_payout_usd']:,.2f}"
    )
    print(
        f"Paying months: {s['months_with_payout']}/{s['months_total']} "
        f"(avg when paid ${s['paying_months_avg_usd']:,.2f})"
    )
    print("\nActive months:")
    for row in months_table:
        if row["payout_usd"] or row["n_trades"]:
            print(
                f"  {row['month']}: payout ${row['payout_usd']:,.2f} | "
                f"closed PnL ${row['closed_pnl_usd']:,.2f} | trades {row['n_trades']}"
            )
    print(f"\nWithdrawals: {report['withdrawals']}")
    print(
        f"Peak equity ${s['compounding_peak_equity']:,.2f} @ {s['compounding_peak_time']}; "
        f"froze near floor ~ {s['trading_froze_near_floor_around']}"
    )
    print(
        f"\nRecommended personal cash buffer: ${buf['recommended_personal_cash_buffer_usd']:,.0f}"
    )
    print(
        f"Recommended keep on account above $100k: "
        f"${buf['recommended_keep_on_account_above_initial_usd']:,.0f}"
    )
    print(f"\n{buf['note_2024_2025']}")
    print(f"\nWrote {out_path}")


if __name__ == "__main__":
    main()
