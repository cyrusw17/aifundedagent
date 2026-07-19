"""Scale-in portfolio: staggered $100k evals → funded books with capacity caps.

Cadence (default historically: monthly) can be biweekly. Concurrent caps limit
how many evaluations and funded accounts may run at once. Passed evals wait in
a queue if funded slots are full; funded starts only when a slot frees (blow)
or is immediately available at pass time.
"""

from __future__ import annotations

import heapq
from dataclasses import dataclass, field
from typing import Any

import pandas as pd

from mcpt.forex.account import FundedRules
from mcpt.forex.backtest import prepare_market_book, run_backtest


@dataclass
class AccountRun:
    account_id: str
    start: pd.Timestamp
    status: str
    # statuses: eval_failed | funded_active | funded_blown | funded_queued |
    #           queued_never_funded | skipped_no_eval_slot
    eval_passed: bool
    eval_pass_time: str | None
    eval_days: int | None
    eval_blown: bool
    funded_blown: bool
    funded_blow_time: str | None
    funded_start_time: str | None
    blow_reason: str
    total_withdrawn: float
    n_withdrawals: int
    funded_final_balance: float
    funded_n_trades: int
    queue_wait_days: float | None = None
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
            "funded_start_time": self.funded_start_time,
            "queue_wait_days": self.queue_wait_days,
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
    config: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "window": self.window,
            "config": self.config,
            "params": self.params,
            "pairs": self.pairs,
            "eval_max_days": self.eval_max_days,
            "summary": self.summary,
            "monthly": self.monthly,
            "accounts": [a.to_dict() for a in self.accounts],
        }


def _month_starts(start: pd.Timestamp, end: pd.Timestamp) -> list[pd.Timestamp]:
    periods = pd.period_range(start.to_period("M"), end.to_period("M"), freq="M")
    out = []
    for per in periods:
        ts = per.to_timestamp()
        if ts < start:
            ts = start
        if ts <= end:
            out.append(pd.Timestamp(ts))
    return out


def _cadence_starts(start: pd.Timestamp, end: pd.Timestamp, every_days: int) -> list[pd.Timestamp]:
    if every_days <= 0:
        raise ValueError("every_days must be positive")
    out = []
    t = start
    while t <= end:
        out.append(pd.Timestamp(t))
        t = t + pd.Timedelta(days=every_days)
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


def _bt_kwargs(params: dict[str, Any], rules: FundedRules) -> dict[str, Any]:
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
        rules=rules,
    )


def _run_eval(
    frames,
    feats,
    signals,
    all_times,
    start: pd.Timestamp,
    rules: FundedRules,
    params: dict[str, Any],
    eval_max_days: int,
) -> tuple[bool, pd.Timestamp | None, int | None, bool, str]:
    """Returns (passed, pass_t, eval_days, blown, reason)."""
    eval_end = start + pd.Timedelta(days=eval_max_days)
    fr, fe, sg, times = _slice_prepared(frames, feats, signals, all_times, start, eval_end)
    if not times:
        return False, None, None, False, "no_data"
    bt = run_backtest(
        fr,
        _prepared=(fr, fe, sg, times),
        weekly_withdraw=False,
        **_bt_kwargs(params, rules),
    )
    pass_t = _find_eval_pass(bt.equity_curve, rules, start, eval_max_days)
    if pass_t is not None:
        pre = bt.equity_curve[bt.equity_curve.index <= pass_t]
        if len(pre) and float(pre.min()) <= rules.floor_balance + 1e-6:
            pass_t = None
    if pass_t is None:
        blown = bool(bt.account.blown)
        return False, None, None, blown, bt.account.blow_reason or ("timeout" if not blown else "")

    pass_day = pass_t.date() if hasattr(pass_t, "date") else pass_t
    daily = {d: v for d, v in bt.account.daily_pnl.items() if d <= pass_day}
    profits = [v for v in daily.values() if v > 0]
    total_pos = sum(profits)
    consistency_ok = True if total_pos <= 0 else max(profits) <= total_pos * rules.consistency_pct + 1e-9
    if not consistency_ok:
        return False, None, int((pass_t - start).days), False, "consistency"
    return True, pass_t, int((pass_t - start).days), False, ""


def _run_funded(
    frames,
    feats,
    signals,
    all_times,
    funded_start: pd.Timestamp,
    end: pd.Timestamp,
    rules: FundedRules,
    params: dict[str, Any],
) -> tuple[bool, str | None, float, list[dict], float, int, str]:
    """Returns (blown, blow_t, total_withdrawn, withdrawals, final_bal, n_trades, reason)."""
    fr, fe, sg, times = _slice_prepared(
        frames, feats, signals, all_times, funded_start, end
    )
    if not times:
        return False, None, 0.0, [], rules.initial_balance, 0, "no_funded_data"
    bt = run_backtest(
        fr,
        _prepared=(fr, fe, sg, times),
        weekly_withdraw=True,
        **_bt_kwargs(params, rules),
    )
    wds = [
        {"date": str(w["date"]), "amount": round(float(w["amount"]), 2)}
        for w in bt.account.withdrawals
    ]
    blow_t = None
    if bt.account.blown and len(bt.equity_curve):
        eq = bt.equity_curve
        under = eq[eq <= rules.floor_balance + 1e-6]
        if len(under):
            blow_t = str(under.index[0])
        else:
            blown_tr = [tr for tr in bt.trades if tr.reason == "blown"]
            if blown_tr:
                blow_t = str(blown_tr[0].exit_time)
            elif bt.trades:
                blow_t = str(bt.trades[-1].exit_time)
            else:
                blow_t = str(eq.index[-1])
    return (
        bool(bt.account.blown),
        blow_t,
        float(bt.account.total_withdrawn),
        wds,
        float(bt.account.balance),
        len(bt.trades),
        bt.account.blow_reason or "",
    )


def _empty_account(
    account_id: str,
    start: pd.Timestamp,
    status: str,
    *,
    eval_passed: bool = False,
    eval_pass_time: str | None = None,
    eval_days: int | None = None,
    eval_blown: bool = False,
    blow_reason: str = "",
    rules: FundedRules | None = None,
) -> AccountRun:
    bal = rules.initial_balance if rules else 100_000.0
    return AccountRun(
        account_id=account_id,
        start=start,
        status=status,
        eval_passed=eval_passed,
        eval_pass_time=eval_pass_time,
        eval_days=eval_days,
        eval_blown=eval_blown,
        funded_blown=False,
        funded_blow_time=None,
        funded_start_time=None,
        blow_reason=blow_reason,
        total_withdrawn=0.0,
        n_withdrawals=0,
        funded_final_balance=bal,
        funded_n_trades=0,
    )


def simulate_scale(
    book: dict[str, pd.DataFrame],
    params: dict[str, Any],
    *,
    start: str,
    end: str,
    pairs: list[str] | None = None,
    eval_max_days: int = 90,
    start_every_days: int = 14,
    max_concurrent_evals: int = 5,
    max_concurrent_funded: int = 5,
    rules: FundedRules | None = None,
    warmup_start: str | None = None,
) -> PortfolioScaleReport:
    """Biweekly (or custom) scale-in with concurrent eval/funded caps."""
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

    # Event queue: (time, priority, seq, kind, payload)
    # priority: 0=eval_done/funded_blow, 1=try_start — free slots before new starts
    pq: list[tuple] = []
    seq = 0

    def push(t: pd.Timestamp, priority: int, kind: str, payload: Any) -> None:
        nonlocal seq
        heapq.heappush(pq, (pd.Timestamp(t), priority, seq, kind, payload))
        seq += 1

    for t in _cadence_starts(start_ts, end_ts, start_every_days):
        push(t, 1, "try_start", None)

    accounts: dict[str, AccountRun] = {}
    active_evals: set[str] = set()
    active_funded: set[str] = set()
    funded_queue: list[str] = []  # account ids waiting for funded slot
    pending: dict[str, dict[str, Any]] = {}  # eval results awaiting conversion
    state = {
        "skipped_starts": 0,
        "attempted_starts": 0,
        "acct_counter": 0,
        "peak_evals": 0,
        "peak_funded": 0,
        "peak_queue": 0,
    }

    def snap_start(t: pd.Timestamp) -> pd.Timestamp | None:
        later = [x for x in all_times if x >= t]
        if not later:
            return None
        s = pd.Timestamp(later[0])
        return s if s <= end_ts else None

    def activate_funded(aid: str, when: pd.Timestamp) -> None:
        meta = pending[aid]
        pass_t = meta["pass_t"]
        wait_days = float((when - pass_t).total_seconds() / 86400.0)
        funded_start = when + pd.Timedelta(hours=1)
        blown, blow_t, tw, wds, bal, ntr, reason = _run_funded(
            frames, feats, signals, all_times, funded_start, end_ts, rules, params
        )
        a = accounts[aid]
        a.funded_start_time = str(funded_start)
        a.queue_wait_days = round(wait_days, 2)
        a.total_withdrawn = tw
        a.n_withdrawals = len(wds)
        a.withdrawals = wds
        a.funded_final_balance = bal
        a.funded_n_trades = ntr
        a.funded_blown = blown
        a.funded_blow_time = blow_t
        a.blow_reason = reason
        a.status = "funded_blown" if blown else "funded_active"
        active_funded.add(aid)
        state["peak_funded"] = max(state["peak_funded"], len(active_funded))
        if blown and blow_t:
            push(pd.Timestamp(blow_t), 0, "funded_blow", aid)

    while pq:
        t, _prio, _s, kind, payload = heapq.heappop(pq)
        if t > end_ts and kind != "funded_blow":
            continue

        if kind == "try_start":
            state["attempted_starts"] += 1
            if len(active_evals) >= max_concurrent_evals:
                state["skipped_starts"] += 1
                aid = f"SKIP_{t.strftime('%Y%m%d')}_{state['skipped_starts']}"
                accounts[aid] = _empty_account(
                    aid, t, "skipped_no_eval_slot", blow_reason="eval_cap", rules=rules
                )
                continue
            acct_start = snap_start(t)
            if acct_start is None:
                continue
            state["acct_counter"] += 1
            aid = f"A{state['acct_counter']:02d}_{acct_start.strftime('%Y%m%d')}"
            passed, pass_t, eval_days, blown, reason = _run_eval(
                frames,
                feats,
                signals,
                all_times,
                acct_start,
                rules,
                params,
                eval_max_days,
            )
            if not passed:
                accounts[aid] = _empty_account(
                    aid,
                    acct_start,
                    "eval_failed",
                    eval_passed=False,
                    eval_days=eval_days,
                    eval_blown=blown,
                    blow_reason=reason,
                    rules=rules,
                )
                # occupies eval slot until fail/timeout end
                fail_t = min(acct_start + pd.Timedelta(days=eval_max_days), end_ts)
                active_evals.add(aid)
                state["peak_evals"] = max(state["peak_evals"], len(active_evals))
                push(fail_t, 0, "eval_fail", aid)
                continue

            accounts[aid] = _empty_account(
                aid,
                acct_start,
                "eval_passed_pending",
                eval_passed=True,
                eval_pass_time=str(pass_t),
                eval_days=eval_days,
                rules=rules,
            )
            pending[aid] = {"pass_t": pass_t}
            active_evals.add(aid)
            state["peak_evals"] = max(state["peak_evals"], len(active_evals))
            push(pass_t, 0, "eval_pass", aid)

        elif kind == "eval_fail":
            aid = payload
            active_evals.discard(aid)

        elif kind == "eval_pass":
            aid = payload
            active_evals.discard(aid)
            a = accounts[aid]
            if len(active_funded) < max_concurrent_funded:
                activate_funded(aid, pd.Timestamp(a.eval_pass_time))
            else:
                a.status = "funded_queued"
                funded_queue.append(aid)
                state["peak_queue"] = max(state["peak_queue"], len(funded_queue))

        elif kind == "funded_blow":
            aid = payload
            active_funded.discard(aid)
            while funded_queue and len(active_funded) < max_concurrent_funded:
                nxt = funded_queue.pop(0)
                if nxt in accounts and accounts[nxt].status == "funded_queued":
                    activate_funded(nxt, t)

    # Anyone still queued at end never funded
    for aid in funded_queue:
        a = accounts[aid]
        if a.status == "funded_queued":
            a.status = "queued_never_funded"
            a.blow_reason = "funded_cap_no_slot"

    # Clear transient status
    for a in accounts.values():
        if a.status == "eval_passed_pending":
            a.status = "queued_never_funded"

    account_list = sorted(accounts.values(), key=lambda x: (x.start, x.account_id))

    def _is_funded_active(a: AccountRun, m_start: pd.Timestamp, m_end: pd.Timestamp) -> bool:
        if not a.funded_start_time:
            return False
        fs = pd.Timestamp(a.funded_start_time)
        if fs > m_end:
            return False
        if a.funded_blown and a.funded_blow_time:
            return pd.Timestamp(a.funded_blow_time) >= m_start
        return True

    def _is_eval_active(a: AccountRun, m_start: pd.Timestamp, m_end: pd.Timestamp) -> bool:
        if a.status == "skipped_no_eval_slot":
            return False
        st = pd.Timestamp(a.start)
        if st > m_end:
            return False
        if a.eval_passed and a.eval_pass_time:
            return st <= m_end and pd.Timestamp(a.eval_pass_time) >= m_start
        # failed eval occupies until timeout
        end_eval = st + pd.Timedelta(days=eval_max_days)
        return st <= m_end and end_eval >= m_start and not a.eval_passed

    months = pd.period_range(start_ts.to_period("M"), end_ts.to_period("M"), freq="M")
    monthly = []
    cum_payout = 0.0
    for per in months:
        m_start = per.to_timestamp()
        m_end = (per + 1).to_timestamp() - pd.Timedelta(seconds=1)
        started = sum(
            1
            for a in account_list
            if a.status != "skipped_no_eval_slot"
            and pd.Timestamp(a.start).to_period("M") == per
        )
        skipped = sum(
            1
            for a in account_list
            if a.status == "skipped_no_eval_slot"
            and pd.Timestamp(a.start).to_period("M") == per
        )
        passed_this = sum(
            1
            for a in account_list
            if a.eval_pass_time and pd.Timestamp(a.eval_pass_time).to_period("M") == per
        )
        active_f = sum(1 for a in account_list if _is_funded_active(a, m_start, m_end))
        active_e = sum(1 for a in account_list if _is_eval_active(a, m_start, m_end))
        payout = 0.0
        for a in account_list:
            for w in a.withdrawals:
                wd = pd.Timestamp(w["date"])
                if m_start <= wd <= m_end:
                    payout += float(w["amount"])
        cum_payout += payout
        monthly.append(
            {
                "month": str(per),
                "accounts_started": started,
                "starts_skipped_eval_cap": skipped,
                "evals_passed": passed_this,
                "evals_active": active_e,
                "funded_active": active_f,
                "payout_usd": round(payout, 2),
                "cumulative_payout_usd": round(cum_payout, 2),
            }
        )

    started_real = [a for a in account_list if a.status != "skipped_no_eval_slot"]
    n_started = len(started_real)
    n_passed = sum(1 for a in started_real if a.eval_passed)
    n_eval_fail = sum(1 for a in started_real if not a.eval_passed)
    n_funded_blown = sum(1 for a in started_real if a.funded_blown)
    n_funded_started = sum(1 for a in started_real if a.funded_start_time)
    n_queued_never = sum(1 for a in started_real if a.status == "queued_never_funded")
    n_survived = sum(
        1 for a in started_real if a.funded_start_time and not a.funded_blown
    )
    total_payouts = sum(a.total_withdrawn for a in started_real)
    pay_series = [m["payout_usd"] for m in monthly]
    avg_mo = float(sum(pay_series) / len(pay_series)) if pay_series else 0.0
    med_mo = float(pd.Series(pay_series).median()) if pay_series else 0.0
    peak_active = max((m["funded_active"] for m in monthly), default=0)
    eval_days = [a.eval_days for a in started_real if a.eval_days is not None]
    config = {
        "start_every_days": start_every_days,
        "max_concurrent_evals": max_concurrent_evals,
        "max_concurrent_funded": max_concurrent_funded,
        "eval_max_days": eval_max_days,
    }
    summary = {
        "accounts_started": n_started,
        "start_attempts": state["attempted_starts"],
        "starts_skipped_eval_cap": state["skipped_starts"],
        "evals_passed": n_passed,
        "eval_pass_rate": (n_passed / n_started) if n_started else 0.0,
        "eval_failed": n_eval_fail,
        "funded_started": n_funded_started,
        "funded_blown": n_funded_blown,
        "funded_survived_to_end": n_survived,
        "queued_never_funded": n_queued_never,
        "total_payouts_usd": round(total_payouts, 2),
        "avg_monthly_portfolio_payout_usd": round(avg_mo, 2),
        "median_monthly_portfolio_payout_usd": round(med_mo, 2),
        "peak_funded_active": peak_active,
        "peak_evals_concurrent": state["peak_evals"],
        "peak_funded_concurrent": state["peak_funded"],
        "peak_funded_queue": state["peak_queue"],
        "median_eval_days": float(pd.Series(eval_days).median()) if eval_days else None,
        "mean_eval_days": float(pd.Series(eval_days).mean()) if eval_days else None,
        "notional_peak_usd": peak_active * rules.initial_balance,
        "recommended_personal_buffer_usd": round(
            max(6_000.0, 3.0 * avg_mo, peak_active * 2_000.0),
            0,
        ),
        "recommended_keep_per_account_above_initial_usd": 4_000.0,
        "note": (
            f"New $100k eval every {start_every_days}d when eval slots < "
            f"{max_concurrent_evals}; max {max_concurrent_funded} funded at once. "
            f"Passed evals queue if funded full. Weekly withdraw min "
            f"${rules.withdraw_min:.0f} / cap ${rules.withdraw_cap:.0f}. "
            "Challenge fees not deducted."
        ),
    }

    return PortfolioScaleReport(
        window=[str(start_ts.date()), str(end_ts.date())],
        params=dict(params),
        pairs=list(book.keys()),
        eval_max_days=eval_max_days,
        accounts=account_list,
        monthly=monthly,
        summary=summary,
        config=config,
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
    """Backward-compatible: one new eval on the 1st of each month, no concurrency caps."""
    # Emulate uncapped monthly by using month starts via large caps + 30-ish day cadence
    # Prefer exact month-start schedule:
    rules = rules or FundedRules()
    start_ts = pd.Timestamp(start)
    end_ts = pd.Timestamp(end)
    # Use scale with huge caps but inject month starts by calling simulate_scale
    # with start_every_days=32 approx — better: custom path using month starts.
    # Implement via simulate_scale after monkey-patching cadence — cleanest: pass
    # start_every_days from month gaps is uneven. Keep dedicated month path:

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

    accounts: list[AccountRun] = []
    for i, ms in enumerate(_month_starts(start_ts, end_ts)):
        later = [t for t in all_times if t >= ms]
        if not later:
            continue
        acct_start = pd.Timestamp(later[0])
        if acct_start > end_ts:
            continue
        aid = f"A{i+1:02d}_{acct_start.strftime('%Y%m')}"
        passed, pass_t, eval_days, blown, reason = _run_eval(
            frames, feats, signals, all_times, acct_start, rules, params, eval_max_days
        )
        if not passed:
            accounts.append(
                _empty_account(
                    aid,
                    acct_start,
                    "eval_failed",
                    eval_days=eval_days,
                    eval_blown=blown,
                    blow_reason=reason,
                    rules=rules,
                )
            )
            continue
        funded_start = pass_t + pd.Timedelta(hours=1)
        blown_f, blow_t, tw, wds, bal, ntr, freason = _run_funded(
            frames, feats, signals, all_times, funded_start, end_ts, rules, params
        )
        accounts.append(
            AccountRun(
                account_id=aid,
                start=acct_start,
                status="funded_blown" if blown_f else "funded_active",
                eval_passed=True,
                eval_pass_time=str(pass_t),
                eval_days=eval_days,
                eval_blown=False,
                funded_blown=blown_f,
                funded_blow_time=blow_t,
                funded_start_time=str(funded_start),
                blow_reason=freason,
                total_withdrawn=tw,
                n_withdrawals=len(wds),
                funded_final_balance=bal,
                funded_n_trades=ntr,
                queue_wait_days=0.0,
                withdrawals=wds,
            )
        )

    # Reuse reporting by wrapping through a tiny shim report builder
    return _report_from_accounts(
        accounts,
        params=params,
        pairs=list(book.keys()),
        start_ts=start_ts,
        end_ts=end_ts,
        eval_max_days=eval_max_days,
        rules=rules,
        config={
            "start_every_days": "monthly",
            "max_concurrent_evals": None,
            "max_concurrent_funded": None,
            "eval_max_days": eval_max_days,
        },
    )


def _report_from_accounts(
    accounts: list[AccountRun],
    *,
    params: dict,
    pairs: list[str],
    start_ts: pd.Timestamp,
    end_ts: pd.Timestamp,
    eval_max_days: int,
    rules: FundedRules,
    config: dict,
) -> PortfolioScaleReport:
    def _is_funded_active(a: AccountRun, m_start: pd.Timestamp, m_end: pd.Timestamp) -> bool:
        if not a.funded_start_time:
            return False
        fs = pd.Timestamp(a.funded_start_time)
        if fs > m_end:
            return False
        if a.funded_blown and a.funded_blow_time:
            return pd.Timestamp(a.funded_blow_time) >= m_start
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
        payout = sum(
            float(w["amount"])
            for a in accounts
            for w in a.withdrawals
            if m_start <= pd.Timestamp(w["date"]) <= m_end
        )
        cum_payout += payout
        monthly.append(
            {
                "month": str(per),
                "accounts_started": started,
                "evals_passed": passed_this,
                "funded_active": active,
                "payout_usd": round(payout, 2),
                "cumulative_payout_usd": round(cum_payout, 2),
            }
        )

    n_started = len(accounts)
    n_passed = sum(1 for a in accounts if a.eval_passed)
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
        "eval_failed": sum(1 for a in accounts if not a.eval_passed),
        "funded_blown": sum(1 for a in accounts if a.funded_blown),
        "funded_survived_to_end": sum(
            1 for a in accounts if a.eval_passed and not a.funded_blown
        ),
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
        "note": "Monthly uncapped scale-in (legacy).",
    }
    return PortfolioScaleReport(
        window=[str(start_ts.date()), str(end_ts.date())],
        params=dict(params),
        pairs=pairs,
        eval_max_days=eval_max_days,
        accounts=accounts,
        monthly=monthly,
        summary=summary,
        config=config,
    )
