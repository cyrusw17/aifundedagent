"""Scale-in portfolio: start one $100k challenge per month; trade all that pass & survive.

Each month a new evaluation account is opened. While in eval there is no weekly
withdraw. Once +10% is hit (consistency OK, not blown), the account switches to
funded mode with weekly withdrawals. Failed evals and blown funded accounts
stop trading. Portfolio payouts = sum of withdrawals across active funded books.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import pandas as pd

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import prepare_market_book, run_backtest


@dataclass
class AccountRun:
    account_id: str
    start: pd.Timestamp
    status: str  # eval_failed | funded_active | funded_blown | funded_ended
    eval_passed: bool
    eval_pass_time: str | None
    eval_days: int | None
    eval_blown: bool
    funded_blown: bool
    funded_blow_time: str | None
    blow_reason: str
    total_withdrawn: float
    n_withdrawals: int
    funded_final_balance: float
    funded_n_trades: int
    withdrawals: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "account_id": self.account_id,
            "start": str(self.start.date()),
            "status": self.status,
            "eval_passed": self.eval_passed,
            "eval_pass_time": self.eval_pass_time,
            "eval_days": self.eval_days,
            "eval_blown": self.eval_blown,
            "funded_blown": self.funded_blown,
            "funded_blow_time": self.funded_blow_time,
            "blow_reason": self.blow_reason,
            "total_withdrawn": round(self.total_withdrawn, 2),
            "n_withdrawals": self.n_withdrawals,
            "funded_final_balance": round(self.funded_final_balance, 2),
            "funded_n_trades": self.funded_n_trades,
            "withdrawals": self.withdrawals,
        }


@dataclass
class PortfolioScaleReport:
    window: list[str]
    params: dict[str, Any]
    pairs: list[str]
    eval_max_days: int
    accounts: list[AccountRun]
    monthly: list[dict[str, Any]]
    summary: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "window": self.window,
            "params": self.params,
            "pairs": self.pairs,
            "eval_max_days": self.eval_max_days,
            "summary": self.summary,
            "monthly": self.monthly,
            "accounts": [a.to_dict() for a in self.accounts],
        }


def _month_starts(start: pd.Timestamp, end: pd.Timestamp) -> list[pd.Timestamp]:
    """First calendar day of each month in [start, end]."""
    periods = pd.period_range(start.to_period("M"), end.to_period("M"), freq="M")
    out = []
    for per in periods:
        ts = per.to_timestamp()
        if ts < start:
            ts = start
        if ts <= end:
            out.append(pd.Timestamp(ts))
    return out


def _slice_prepared(
    frames: dict,
    feats: dict,
    signals: dict,
    all_times: list,
    start: pd.Timestamp,
    end: pd.Timestamp,
) -> tuple:
    times = [t for t in all_times if start <= t <= end]
    if not times:
        return {}, {}, {}, []
    fr = {p: df[(df.index >= start) & (df.index <= end)].copy() for p, df in frames.items()}
    fr = {p: df for p, df in fr.items() if len(df)}
    fe = {p: feats[p].loc[fr[p].index] for p in fr}
    sg = {p: signals[p].loc[fr[p].index] for p in fr}
    return fr, fe, sg, times


def _find_eval_pass(
    eq: pd.Series,
    rules: FundedRules,
    start: pd.Timestamp,
    max_days: int,
) -> pd.Timestamp | None:
    if eq is None or len(eq) == 0:
        return None
    deadline = start + pd.Timedelta(days=max_days)
    target = rules.evaluation_target
    for t, v in eq.items():
        if t > deadline:
            break
        if v >= target:
            return pd.Timestamp(t)
    return None


def run_account_lifecycle(
    frames: dict,
    feats: dict,
    signals: dict,
    all_times: list,
    start: pd.Timestamp,
    end: pd.Timestamp,
    account_id: str,
    params: dict[str, Any],
    rules: FundedRules,
    eval_max_days: int,
) -> AccountRun:
    """Eval from start; if pass, fund until end or blow. Withdrawals only in funded."""
    base_kw = dict(
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
        rules=rules,
    )

    eval_end = min(end, start + pd.Timedelta(days=eval_max_days))
    fr, fe, sg, times = _slice_prepared(frames, feats, signals, all_times, start, eval_end)
    empty = dict(
        funded_blow_time=None,
        total_withdrawn=0.0,
        n_withdrawals=0,
        funded_final_balance=rules.initial_balance,
        funded_n_trades=0,
        withdrawals=[],
    )

    if not times:
        return AccountRun(
            account_id=account_id,
            start=start,
            status="eval_failed",
            eval_passed=False,
            eval_pass_time=None,
            eval_days=None,
            eval_blown=False,
            funded_blown=False,
            blow_reason="no_data",
            **empty,
        )

    eval_bt = run_backtest(
        fr,
        _prepared=(fr, fe, sg, times),
        weekly_withdraw=False,
        **base_kw,
    )
    pass_t = _find_eval_pass(eval_bt.equity_curve, rules, start, eval_max_days)
    if pass_t is not None:
        pre = eval_bt.equity_curve[eval_bt.equity_curve.index <= pass_t]
        if len(pre) and float(pre.min()) <= rules.floor_balance + 1e-6:
            pass_t = None

    if pass_t is None:
        blown = bool(eval_bt.account.blown)
        return AccountRun(
            account_id=account_id,
            start=start,
            status="eval_failed",
            eval_passed=False,
            eval_pass_time=None,
            eval_days=None,
            eval_blown=blown,
            funded_blown=False,
            blow_reason=eval_bt.account.blow_reason or ("timeout" if not blown else ""),
            **empty,
        )

    # Consistency using only closed-trade days on/before pass
    pass_day = pass_t.date() if hasattr(pass_t, "date") else pass_t
    daily = {
        d: v
        for d, v in eval_bt.account.daily_pnl.items()
        if d <= pass_day
    }
    profits = [v for v in daily.values() if v > 0]
    total_pos = sum(profits)
    consistency_ok = True if total_pos <= 0 else max(profits) <= total_pos * rules.consistency_pct + 1e-9
    if not consistency_ok:
        return AccountRun(
            account_id=account_id,
            start=start,
            status="eval_failed",
            eval_passed=False,
            eval_pass_time=None,
            eval_days=int((pass_t - start).days),
            eval_blown=False,
            funded_blown=False,
            blow_reason="consistency",
            **empty,
        )

    eval_days = int((pass_t - start).days)
    funded_start = pass_t + pd.Timedelta(hours=1)
    fr_f, fe_f, sg_f, times_f = _slice_prepared(
        frames, feats, signals, all_times, funded_start, end
    )
    if not times_f:
        return AccountRun(
            account_id=account_id,
            start=start,
            status="funded_ended",
            eval_passed=True,
            eval_pass_time=str(pass_t),
            eval_days=eval_days,
            eval_blown=False,
            funded_blown=False,
            blow_reason="",
            **empty,
        )

    funded_bt = run_backtest(
        fr_f,
        _prepared=(fr_f, fe_f, sg_f, times_f),
        weekly_withdraw=True,
        **base_kw,
    )
    wds = [
        {"date": str(w["date"]), "amount": round(float(w["amount"]), 2)}
        for w in funded_bt.account.withdrawals
    ]
    blow_t = None
    if funded_bt.account.blown and len(funded_bt.equity_curve):
        eq = funded_bt.equity_curve
        # first bar at/under floor, else last trade marked blown
        under = eq[eq <= rules.floor_balance + 1e-6]
        if len(under):
            blow_t = str(under.index[0])
        else:
            blown_tr = [tr for tr in funded_bt.trades if tr.reason == "blown"]
            if blown_tr:
                blow_t = str(blown_tr[0].exit_time)
            elif funded_bt.trades:
                blow_t = str(funded_bt.trades[-1].exit_time)

    if funded_bt.account.blown:
        status = "funded_blown"
    else:
        status = "funded_active"

    return AccountRun(
        account_id=account_id,
        start=start,
        status=status,
        eval_passed=True,
        eval_pass_time=str(pass_t),
        eval_days=eval_days,
        eval_blown=False,
        funded_blown=bool(funded_bt.account.blown),
        funded_blow_time=blow_t,
        blow_reason=funded_bt.account.blow_reason or "",
        total_withdrawn=float(funded_bt.account.total_withdrawn),
        n_withdrawals=len(wds),
        funded_final_balance=float(funded_bt.account.balance),
        funded_n_trades=len(funded_bt.trades),
        withdrawals=wds,
    )


def simulate_monthly_scale(
    book: dict[str, pd.DataFrame],
    params: dict[str, Any],
    *,
    start: str,
    end: str,
    pairs: list[str] | None = None,
    eval_max_days: int = 90,
    rules: FundedRules | None = None,
    warmup_start: str | None = None,
) -> PortfolioScaleReport:
    """Start one new $100k eval on the 1st of each month; aggregate funded payouts."""
    rules = rules or FundedRules()
    start_ts = pd.Timestamp(start)
    end_ts = pd.Timestamp(end)
    pairs = pairs or list(book.keys())
    book = {p: book[p] for p in pairs if p in book}

    warm = pd.Timestamp(warmup_start) if warmup_start else start_ts - pd.Timedelta(days=90)
    warm_book = {
        p: df[(df.index >= warm) & (df.index <= end_ts)].copy() for p, df in book.items()
    }
    frames, feats, signals, all_times = prepare_market_book(
        warm_book,
        signal_mode=params["signal_mode"],
        swing_left=int(params.get("swing_left", 3)),
        swing_right=int(params.get("swing_right", 3)),
        min_confluence=int(params.get("min_confluence", 2)),
        require_killzone=bool(params.get("require_killzone", False)),
    )

    starts = _month_starts(start_ts, end_ts)
    accounts: list[AccountRun] = []
    for i, ms in enumerate(starts):
        # snap start to first available bar on/after month start
        later = [t for t in all_times if t >= ms]
        if not later:
            continue
        acct_start = pd.Timestamp(later[0])
        if acct_start > end_ts:
            continue
        run = run_account_lifecycle(
            frames,
            feats,
            signals,
            all_times,
            acct_start,
            end_ts,
            account_id=f"A{i+1:02d}_{acct_start.strftime('%Y%m')}",
            params=params,
            rules=rules,
            eval_max_days=eval_max_days,
        )
        accounts.append(run)

    def _is_funded_active(a: AccountRun, m_start: pd.Timestamp, m_end: pd.Timestamp) -> bool:
        if not a.eval_passed or not a.eval_pass_time:
            return False
        pass_t = pd.Timestamp(a.eval_pass_time)
        if pass_t > m_end:
            return False
        if a.funded_blown and a.funded_blow_time:
            blow_t = pd.Timestamp(a.funded_blow_time)
            # active during month if blow on/after month start
            return blow_t >= m_start
        return True

    months = pd.period_range(start_ts.to_period("M"), end_ts.to_period("M"), freq="M")
    monthly = []
    cum_payout = 0.0
    for per in months:
        m_start = per.to_timestamp()
        m_end = (per + 1).to_timestamp() - pd.Timedelta(seconds=1)
        started = sum(1 for a in accounts if pd.Timestamp(a.start).to_period("M") == per)
        passed_this = sum(
            1
            for a in accounts
            if a.eval_pass_time and pd.Timestamp(a.eval_pass_time).to_period("M") == per
        )
        active = sum(1 for a in accounts if _is_funded_active(a, m_start, m_end))
        payout = 0.0
        for a in accounts:
            for w in a.withdrawals:
                wd = pd.Timestamp(w["date"])
                if m_start <= wd <= m_end:
                    payout += float(w["amount"])

        cum_payout += payout
        n_eval_failed = sum(
            1
            for a in accounts
            if (not a.eval_passed) and pd.Timestamp(a.start).to_period("M") <= per
        )
        n_funded_blown = sum(
            1
            for a in accounts
            if a.funded_blown
            and a.funded_blow_time
            and pd.Timestamp(a.funded_blow_time).to_period("M") <= per
        )
        monthly.append(
            {
                "month": str(per),
                "accounts_started": started,
                "evals_passed": passed_this,
                "funded_active": active,
                "payout_usd": round(payout, 2),
                "cumulative_payout_usd": round(cum_payout, 2),
                "eval_failed_to_date": n_eval_failed,
                "funded_blown_to_date": n_funded_blown,
            }
        )

    n_started = len(accounts)
    n_passed = sum(1 for a in accounts if a.eval_passed)
    n_eval_fail = sum(1 for a in accounts if not a.eval_passed)
    n_funded_blown = sum(1 for a in accounts if a.funded_blown)
    n_survived = sum(1 for a in accounts if a.eval_passed and not a.funded_blown)
    total_payouts = sum(a.total_withdrawn for a in accounts)
    pay_series = [m["payout_usd"] for m in monthly]
    avg_mo = float(sum(pay_series) / len(pay_series)) if pay_series else 0.0
    med_mo = float(pd.Series(pay_series).median()) if pay_series else 0.0
    peak_active = max((m["funded_active"] for m in monthly), default=0)
    eval_days = [a.eval_days for a in accounts if a.eval_days is not None]
    summary = {
        "accounts_started": n_started,
        "evals_passed": n_passed,
        "eval_pass_rate": (n_passed / n_started) if n_started else 0.0,
        "eval_failed": n_eval_fail,
        "funded_blown": n_funded_blown,
        "funded_survived_to_end": n_survived,
        "total_payouts_usd": round(total_payouts, 2),
        "avg_monthly_portfolio_payout_usd": round(avg_mo, 2),
        "median_monthly_portfolio_payout_usd": round(med_mo, 2),
        "peak_funded_active": peak_active,
        "median_eval_days": float(pd.Series(eval_days).median()) if eval_days else None,
        "mean_eval_days": float(pd.Series(eval_days).mean()) if eval_days else None,
        "notional_peak_usd": peak_active * rules.initial_balance,
        "recommended_personal_buffer_usd": round(
            max(6_000.0, 3.0 * avg_mo, peak_active * 2_000.0),
            0,
        ),
        "recommended_keep_per_account_above_initial_usd": 4_000.0,
        "note": (
            "One new $100k eval on the 1st of each month. Funded books use weekly "
            f"withdraw (min ${rules.withdraw_min:.0f}, cap ${rules.withdraw_cap:.0f}). "
            f"Eval must hit +10% within {eval_max_days} days without blowing. "
            "Challenge fees not deducted."
        ),
    }

    return PortfolioScaleReport(
        window=[str(start_ts.date()), str(end_ts.date())],
        params=dict(params),
        pairs=list(book.keys()),
        eval_max_days=eval_max_days,
        accounts=accounts,
        monthly=monthly,
        summary=summary,
    )
