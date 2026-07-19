"""Bar-by-bar forex backtest with prop risk rules. No look-ahead execution.

Signal at bar i close → enter at bar i+1 open.
PnL is computed in R-multiples × dollar risk so all pairs (incl. JPY) are correct.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import numpy as np
import pandas as pd

from mcpt.forex.account import FundedRules, PropAccount
from mcpt.forex.signals import generate_signals


@dataclass
class Trade:
    pair: str
    direction: int
    entry_time: Any
    entry: float
    stop: float
    target: float
    risk_amount: float
    stop_dist: float
    exit_time: Any = None
    exit: float = None
    pnl: float = 0.0
    reason: str = ""
    moved_be: bool = False


@dataclass
class BacktestResult:
    equity_curve: pd.Series
    trades: list[Trade]
    account: PropAccount
    stats: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "stats": self.stats,
            "n_trades": len(self.trades),
            "total_withdrawn": self.account.total_withdrawn,
            "final_balance": self.account.balance,
            "blown": self.account.blown,
            "blow_reason": self.account.blow_reason,
            "consistency_ok": self.account.consistency_ok(),
        }


def _pnl_usd(direction: int, entry: float, exit_px: float, stop_dist: float, risk_amount: float) -> float:
    """Pair-agnostic dollar PnL via R-multiple."""
    if stop_dist <= 0:
        return 0.0
    r_mult = direction * (exit_px - entry) / stop_dist
    return r_mult * risk_amount


def _risk_budget(
    equity: float,
    risk_pct: float,
    room_to_floor: float,
    daily_room: float,
) -> float:
    risk_amount = equity * risk_pct
    risk_amount = min(risk_amount, max(room_to_floor * 0.35, 0.0), max(daily_room * 0.45, 0.0))
    if risk_amount < equity * 0.001:
        return 0.0
    return risk_amount


def prepare_market_book(
    data: dict[str, pd.DataFrame],
    signal_mode: str = "smc",
    swing_left: int = 3,
    swing_right: int = 3,
    min_confluence: int = 3,
    require_killzone: bool = False,
) -> tuple[dict[str, pd.DataFrame], dict[str, pd.DataFrame], dict[str, pd.Series], list]:
    """Precompute frames/features/signals once; reuse across risk-parameter trials."""
    frames: dict[str, pd.DataFrame] = {}
    feats: dict[str, pd.DataFrame] = {}
    signals: dict[str, pd.Series] = {}
    for pair, ohlc in data.items():
        ohlc = ohlc.copy()
        ohlc.index = pd.to_datetime(ohlc.index)
        if ohlc.index.tz is not None:
            ohlc.index = ohlc.index.tz_localize(None)
        sig, f = generate_signals(
            ohlc,
            mode=signal_mode,
            swing_left=swing_left,
            swing_right=swing_right,
            require_killzone=require_killzone,
            min_confluence=min_confluence,
        )
        frames[pair] = ohlc
        feats[pair] = f
        signals[pair] = sig
    all_times = sorted(set().union(*[set(df.index) for df in frames.values()]))
    return frames, feats, signals, all_times


def run_backtest(
    data: dict[str, pd.DataFrame],
    risk_pct: float = 0.005,
    rr: float = 2.0,
    atr_stop_mult: float = 1.25,
    min_confluence: int = 3,
    require_killzone: bool = False,
    max_positions: int = 2,
    swing_left: int = 3,
    swing_right: int = 3,
    rules: FundedRules | None = None,
    weekly_withdraw: bool = True,
    signal_mode: str = "smc",
    move_be_at_r: float = 1.0,
    skip_mondays: bool = True,
    daily_halt_loss_pct: float = 0.015,
    daily_halt_profit_pct: float = 0.025,
    cooldown_losses: int = 3,
    one_entry_per_day: bool = True,
    _prepared: tuple | None = None,
) -> BacktestResult:
    rules = rules or FundedRules()
    account = PropAccount(rules=rules)

    if _prepared is None:
        frames, feats, signals, all_times = prepare_market_book(
            data,
            signal_mode=signal_mode,
            swing_left=swing_left,
            swing_right=swing_right,
            min_confluence=min_confluence,
            require_killzone=require_killzone,
        )
    else:
        frames, feats, signals, all_times = _prepared
    open_trades: list[Trade] = []
    closed: list[Trade] = []
    equity_pts = []
    current_day = None
    current_week = None
    day_halted = False
    consec_losses = 0
    cooldown_left = 0

    for t in all_times:
        day = t.date() if hasattr(t, "date") else t
        week = (t.isocalendar()[0], t.isocalendar()[1]) if hasattr(t, "isocalendar") else None

        if current_day is None or day != current_day:
            current_day = day
            account.new_day(day)
            day_halted = False

        if weekly_withdraw and current_week is not None and week != current_week:
            account.weekly_withdraw(day)
        current_week = week

        if account.blown:
            equity_pts.append((t, account.equity))
            continue

        still_open: list[Trade] = []
        for tr in open_trades:
            ohlc = frames.get(tr.pair)
            if ohlc is None or t not in ohlc.index:
                still_open.append(tr)
                continue
            bar = ohlc.loc[t]

            if move_be_at_r and not tr.moved_be:
                be_level = tr.entry + tr.direction * move_be_at_r * tr.stop_dist
                if tr.direction == 1 and bar["high"] >= be_level:
                    tr.stop = max(tr.stop, tr.entry)
                    tr.moved_be = True
                elif tr.direction == -1 and bar["low"] <= be_level:
                    tr.stop = min(tr.stop, tr.entry)
                    tr.moved_be = True

            if tr.direction == 1:
                hit_stop = bar["low"] <= tr.stop
                hit_tp = bar["high"] >= tr.target
            else:
                hit_stop = bar["high"] >= tr.stop
                hit_tp = bar["low"] <= tr.target

            if hit_stop and hit_tp:
                exit_px, reason = tr.stop, "stop_conflict"
            elif hit_stop:
                exit_px, reason = tr.stop, "stop"
            elif hit_tp:
                exit_px, reason = tr.target, "target"
            else:
                still_open.append(tr)
                continue

            pnl = _pnl_usd(tr.direction, tr.entry, exit_px, tr.stop_dist, tr.risk_amount)
            tr.exit, tr.exit_time, tr.pnl, tr.reason = exit_px, t, pnl, reason
            account.realize_pnl(pnl, day)
            closed.append(tr)
            if pnl < 0:
                consec_losses += 1
                if cooldown_losses and consec_losses >= cooldown_losses:
                    cooldown_left = 2
                    consec_losses = 0
            else:
                consec_losses = 0
            if account.blown:
                break

        open_trades = still_open
        if account.blown:
            equity_pts.append((t, account.equity))
            continue

        floating = 0.0
        for tr in open_trades:
            ohlc = frames[tr.pair]
            if t in ohlc.index:
                px = float(ohlc.loc[t, "close"])
                floating += _pnl_usd(tr.direction, tr.entry, px, tr.stop_dist, tr.risk_amount)
        account.mark_equity(account.balance + floating)

        day_pnl = account.equity - account.day_start_equity
        if day_pnl <= -account.rules.initial_balance * daily_halt_loss_pct:
            day_halted = True
        if day_pnl >= account.rules.initial_balance * daily_halt_profit_pct:
            day_halted = True

        if account.blown:
            for tr in open_trades:
                ohlc = frames[tr.pair]
                px = float(ohlc.loc[t, "close"]) if t in ohlc.index else tr.entry
                pnl = _pnl_usd(tr.direction, tr.entry, px, tr.stop_dist, tr.risk_amount)
                tr.exit, tr.exit_time, tr.pnl, tr.reason = px, t, pnl, "blown"
                account.realize_pnl(pnl, day)
                closed.append(tr)
            open_trades = []
            equity_pts.append((t, account.equity))
            continue

        allow_entries = (
            not day_halted and cooldown_left <= 0 and len(open_trades) < max_positions
        )
        if skip_mondays and hasattr(t, "dayofweek") and t.dayofweek == 0:
            allow_entries = False

        if allow_entries:
            room_to_floor = account.equity - rules.floor_balance
            daily_room = rules.daily_loss_limit - max(
                0.0, account.day_start_equity - account.equity
            )
            entries_today = 0
            for pair, sig in signals.items():
                if len(open_trades) >= max_positions:
                    break
                if one_entry_per_day and entries_today >= 1:
                    break
                ohlc = frames[pair]
                if t not in ohlc.index:
                    continue
                loc = ohlc.index.get_loc(t)
                if not isinstance(loc, (int, np.integer)) or loc == 0:
                    continue
                prev_t = ohlc.index[int(loc) - 1]
                direction = int(sig.loc[prev_t])
                if direction == 0:
                    continue
                if any(tr.pair == pair for tr in open_trades):
                    continue

                entry = float(ohlc.loc[t, "open"])
                atr = float(feats[pair].loc[prev_t, "atr"])
                if not np.isfinite(atr) or atr <= 0:
                    continue
                stop_dist = atr_stop_mult * atr
                if direction == 1:
                    stop = entry - stop_dist
                    target = entry + rr * stop_dist
                else:
                    stop = entry + stop_dist
                    target = entry - rr * stop_dist

                risk_amt = _risk_budget(account.equity, risk_pct, room_to_floor, daily_room)
                if risk_amt <= 0:
                    continue

                open_trades.append(
                    Trade(
                        pair=pair,
                        direction=direction,
                        entry_time=t,
                        entry=entry,
                        stop=stop,
                        target=target,
                        risk_amount=risk_amt,
                        stop_dist=stop_dist,
                    )
                )
                room_to_floor -= risk_amt
                daily_room -= risk_amt
                entries_today += 1

        if cooldown_left > 0:
            cooldown_left -= 1

        equity_pts.append((t, account.equity))

    if open_trades and all_times:
        t = all_times[-1]
        day = t.date() if hasattr(t, "date") else t
        for tr in open_trades:
            px = float(frames[tr.pair].iloc[-1]["close"])
            pnl = _pnl_usd(tr.direction, tr.entry, px, tr.stop_dist, tr.risk_amount)
            tr.exit, tr.exit_time, tr.pnl, tr.reason = px, t, pnl, "eod"
            account.realize_pnl(pnl, day)
            closed.append(tr)

    eq = pd.Series({t: e for t, e in equity_pts}).sort_index()
    stats = _compute_stats(closed, account, eq, rules)
    return BacktestResult(equity_curve=eq, trades=closed, account=account, stats=stats)


def _compute_stats(
    trades: list[Trade], account: PropAccount, eq: pd.Series, rules: FundedRules
) -> dict:
    pnls = [t.pnl for t in trades]
    n = len(pnls)
    wins = [p for p in pnls if p > 0]
    losses = [p for p in pnls if p <= 0]
    years = 1.0
    if len(eq) > 1:
        days = (eq.index[-1] - eq.index[0]).days
        years = max(days / 365.25, 1 / 365.25)

    wealth = (account.balance - rules.initial_balance) + account.total_withdrawn
    ann = wealth / years
    gp = sum(wins) if wins else 0.0
    gl = abs(sum(losses)) if losses else 0.0
    pf = gp / gl if gl > 0 else (float("inf") if gp > 0 else 0.0)
    peak = eq.cummax() if len(eq) else eq
    dd = float((peak - eq).max()) if len(eq) else 0.0
    best_day = max(account.daily_pnl.values()) if account.daily_pnl else 0.0
    pos_days = sum(v for v in account.daily_pnl.values() if v > 0)
    consistency = (best_day / pos_days) if pos_days > 0 else 0.0

    return {
        "n_trades": n,
        "win_rate": (len(wins) / n) if n else 0.0,
        "profit_factor": float(pf) if np.isfinite(pf) else 10.0,
        "total_pnl": float(sum(pnls)) if pnls else 0.0,
        "total_withdrawn": account.total_withdrawn,
        "net_wealth_gain": wealth,
        "avg_annual_pnl": ann,
        "max_dd": dd,
        "blown": account.blown,
        "blow_reason": account.blow_reason,
        "consistency_ratio": consistency,
        "consistency_ok": consistency <= rules.consistency_pct + 1e-9,
        "years": years,
        "final_balance": account.balance,
        "hit_eval_target": bool((eq.max() >= rules.evaluation_target) if len(eq) else False)
        and not account.blown,
    }
