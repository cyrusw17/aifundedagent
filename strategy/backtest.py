"""Event-driven backtest with The5ers rules + weekly funded withdrawals."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from .common import Signal
from .config import PARAMS, PROP, PropRules, StrategyParams


@dataclass
class Trade:
    pair: str
    side: int
    entry_time: pd.Timestamp
    exit_time: pd.Timestamp
    entry: float
    exit: float
    stop: float
    take: float
    lots: float
    pnl: float
    reason_entry: str
    reason_exit: str
    r_multiple: float


@dataclass
class PhaseResult:
    phase: str
    passed: bool
    fail_reason: str
    start_equity: float
    end_equity: float
    max_dd: float
    profit: float
    trades: int
    win_rate: float
    avg_trades_per_day: float
    trading_days: int
    days_to_target: Optional[int]
    consistency_ok: bool
    max_day_profit_share: float
    daily_pauses: int
    equity_curve: pd.Series
    trades_df: pd.DataFrame
    total_withdrawn: float = 0.0
    weekly_withdrawals: int = 0
    total_made: float = 0.0  # withdrawn + (end_equity - start) for funded


def _quote_to_usd_factor(pair: str, exit: float, usdjpy: Optional[float]) -> float:
    if pair.endswith("USD") and not pair.startswith("USD"):
        return 1.0
    if pair.startswith("USD"):
        return 1.0 / exit
    if pair.endswith("JPY"):
        fx = usdjpy if usdjpy and usdjpy > 0 else 150.0
        return 1.0 / fx
    return 1.0


def _pip_pnl(pair, side, entry, exit, lots, params, usdjpy=None) -> float:
    cs = params.contract_sizes[pair]
    move = (exit - entry) * side
    return lots * cs * move * _quote_to_usd_factor(pair, exit, usdjpy)


def _lots_for_risk(pair, entry, stop, risk_amount, params, usdjpy=None) -> float:
    stop_dist = abs(entry - stop)
    if stop_dist <= 0:
        return 0.0
    cs = params.contract_sizes[pair]
    denom = cs * stop_dist * _quote_to_usd_factor(pair, entry, usdjpy)
    if denom <= 0:
        return 0.0
    lots = risk_amount / denom
    return float(max(0.01, np.floor(lots * 100) / 100.0))


def _week_end_key(ts: pd.Timestamp) -> Tuple[int, int]:
    """ISO year/week for Friday week-end withdrawals."""
    iso = ts.isocalendar()
    return int(iso.year), int(iso.week)


def _simulate_limit_entry_and_exit(
    m1: pd.DataFrame,
    signal: Signal,
    params: StrategyParams,
) -> Optional[Tuple[pd.Timestamp, float, pd.Timestamp, float, str]]:
    # HARD RULE: no fill before the signal is knowable (bar close).
    # signal.time = bar open; knowable_at = bar close. Searching from bar open
    # filled during the sweep wick and was look-ahead (see LOOKAHEAD_FILL_BUG.md).
    not_before = signal.knowable_at
    if not_before is None:
        not_before = signal.time + pd.Timedelta(minutes=getattr(signal, "signal_tf_minutes", 15))

    pos = m1.index.searchsorted(not_before, side="left")
    if pos >= len(m1):
        return None

    side = signal.side
    limit = signal.entry
    spread = params.spreads[signal.pair]
    stop = signal.stop
    rr = signal.reward_risk if signal.reward_risk > 0 else params.reward_risk

    times = m1.index
    highs = m1["high"].to_numpy()
    lows = m1["low"].to_numpy()
    closes = m1["close"].to_numpy()
    opens = m1["open"].to_numpy()
    hours = times.hour

    end_fill = min(len(m1), pos + 240)
    entry_i = None
    entry_px = None
    if signal.marketable:
        if pos < len(m1):
            entry_i = pos
            entry_px = float(opens[pos] + spread if side == 1 else opens[pos] - spread)
    elif side == 1:
        hits = np.where(lows[pos:end_fill] <= limit)[0]
        if len(hits):
            entry_i = pos + int(hits[0])
            entry_px = limit + spread
    else:
        hits = np.where(highs[pos:end_fill] >= limit)[0]
        if len(hits):
            entry_i = pos + int(hits[0])
            entry_px = limit - spread
    if entry_i is None or entry_px is None:
        return None

    entry_time = times[entry_i]
    # Structural ban on look-ahead fills — raises if a future refactor regresses.
    if entry_time < not_before:
        raise RuntimeError(
            f"LOOK-AHEAD FILL BLOCKED: entry {entry_time} < knowable_at {not_before} "
            f"({signal.pair} {signal.reason})"
        )

    if side == 1:
        risk = entry_px - stop
        if risk <= 0:
            return None
        take = entry_px + rr * risk
    else:
        risk = stop - entry_px
        if risk <= 0:
            return None
        take = entry_px - rr * risk

    day = entry_time.normalize()
    be_level = entry_px
    be_armed = False
    one_r = abs(entry_px - stop)
    use_be = getattr(params, "move_to_be", True)

    j = entry_i + 1
    while j < len(m1):
        ts = times[j]
        if ts.normalize() == day and hours[j] >= params.flatten_hour_utc:
            return entry_time, float(entry_px), ts, float(closes[j]), "flatten"
        if ts.normalize() > day:
            return entry_time, float(entry_px), ts, float(opens[j]), "flatten_next"

        if side == 1:
            if use_be and not be_armed and highs[j] >= entry_px + one_r:
                be_armed = True
                stop = be_level
            if lows[j] <= stop:
                return entry_time, float(entry_px), ts, float(stop), "be" if be_armed else "sl"
            if highs[j] >= take:
                return entry_time, float(entry_px), ts, float(take), "tp"
        else:
            if use_be and not be_armed and lows[j] <= entry_px - one_r:
                be_armed = True
                stop = be_level
            if highs[j] >= stop:
                return entry_time, float(entry_px), ts, float(stop), "be" if be_armed else "sl"
            if lows[j] <= take:
                return entry_time, float(entry_px), ts, float(take), "tp"
        j += 1

    last_i = len(m1) - 1
    return entry_time, float(entry_px), times[last_i], float(closes[last_i]), "eod_data"


def _apply_weekly_withdrawal(
    equity: float,
    prop: PropRules,
) -> Tuple[float, float]:
    """Return (new_equity, withdrawn). All equity above funded_retain leaves weekly."""
    excess = equity - prop.funded_retain
    if excess < prop.min_weekly_withdraw:
        return equity, 0.0
    # User rule: everything above 101k withdrawn EOW (checkout cap ignored for this sim)
    return prop.funded_retain, excess


def run_period(
    universe: Dict[str, Dict[str, pd.DataFrame]],
    start: str,
    end: str,
    signal_fn: Callable,
    phase_name: str = "eval",
    prop: PropRules = PROP,
    params: StrategyParams = PARAMS,
    starting_equity: Optional[float] = None,
    weekly_withdraw: bool = False,
    stop_at_profit_target: bool = True,
) -> PhaseResult:
    from .data_loader import slice_period

    equity0 = prop.initial_balance if starting_equity is None else starting_equity
    equity = equity0
    peak = equity
    max_dd = 0.0
    total_withdrawn = 0.0
    weekly_withdrawals = 0

    all_signals: List[Signal] = []
    m1_map = {}
    for pair, frames in universe.items():
        m1 = slice_period(frames["m1"], start, end)
        m1_map[pair] = m1
        m15_warm = frames["m15"]
        warm_start = pd.Timestamp(start) - pd.Timedelta(days=20)
        m15_sig = m15_warm.loc[
            (m15_warm.index >= warm_start)
            & (m15_warm.index < pd.Timestamp(end) + pd.Timedelta(days=1))
        ]
        for s in signal_fn(pair, m15_sig, params):
            if pd.Timestamp(start) <= s.time < pd.Timestamp(end) + pd.Timedelta(days=1):
                all_signals.append(s)
    all_signals.sort(key=lambda s: s.time)

    trades: List[Trade] = []
    day_pnl: Dict[pd.Timestamp, float] = {}
    day_trades: Dict[pd.Timestamp, int] = {}
    day_pair_trades: Dict[Tuple[pd.Timestamp, str], int] = {}
    paused_days = set()
    daily_pauses = 0
    last_trade_time: Optional[pd.Timestamp] = None
    fail_reason = ""
    passed = False
    days_to_target: Optional[int] = None
    equity_points = []

    floor = prop.initial_balance - prop.max_loss
    risk_amount = prop.initial_balance * params.risk_pct
    current_day = None
    day_start_equity = equity
    last_week: Optional[Tuple[int, int]] = None

    i = 0
    while i < len(all_signals):
        sig = all_signals[i]
        day = sig.time.normalize()
        week = _week_end_key(sig.time)

        # Weekly withdrawal at week change (funded only)
        if weekly_withdraw and last_week is not None and week != last_week:
            equity, w = _apply_weekly_withdrawal(equity, prop)
            if w > 0:
                total_withdrawn += w
                weekly_withdrawals += 1
                equity_points.append((day, equity))
                peak = max(peak, equity)
        last_week = week

        if current_day is None or day != current_day:
            current_day = day
            day_start_equity = equity

        if day in paused_days:
            i += 1
            continue
        if day_start_equity - equity >= prop.daily_loss_limit:
            paused_days.add(day)
            daily_pauses += 1
            i += 1
            continue
        if day_pnl.get(day, 0.0) >= params.daily_profit_cap:
            i += 1
            continue
        if day_trades.get(day, 0) >= params.max_trades_per_day:
            i += 1
            continue
        if day_pair_trades.get((day, sig.pair), 0) >= params.max_trades_per_pair_day:
            i += 1
            continue
        if last_trade_time is not None and sig.time < last_trade_time + pd.Timedelta(
            minutes=15 * params.cooldown_bars_after_trade
        ):
            i += 1
            continue
        if equity <= floor:
            fail_reason = "max_loss"
            break

        fill = _simulate_limit_entry_and_exit(m1_map[sig.pair], sig, params)
        if fill is None:
            i += 1
            continue
        entry_time, entry_px, exit_time, exit_px, why = fill

        usdjpy_px = None
        if "USDJPY" in m1_map and len(m1_map["USDJPY"]):
            u = m1_map["USDJPY"]
            j = u.index.searchsorted(entry_time, side="right") - 1
            if j >= 0:
                usdjpy_px = float(u["close"].iloc[j])

        lots = _lots_for_risk(
            sig.pair, entry_px, sig.stop, risk_amount, params, usdjpy=usdjpy_px
        )
        if lots <= 0:
            i += 1
            continue
        lots = min(lots, 3.0 if sig.pair == "XAUUSD" else 8.0)

        pnl = _pip_pnl(
            sig.pair, sig.side, entry_px, exit_px, lots, params, usdjpy=usdjpy_px
        )
        risk_dist = abs(entry_px - sig.stop)
        r_mult = 0.0
        if risk_dist > 0:
            risk_cash = (
                lots
                * params.contract_sizes[sig.pair]
                * risk_dist
                * _quote_to_usd_factor(sig.pair, entry_px, usdjpy_px)
            )
            r_mult = pnl / risk_cash if risk_cash else 0.0

        equity += pnl
        peak = max(peak, equity)
        max_dd = max(max_dd, peak - equity)
        day_pnl[day] = day_pnl.get(day, 0.0) + pnl
        day_trades[day] = day_trades.get(day, 0) + 1
        day_pair_trades[(day, sig.pair)] = day_pair_trades.get((day, sig.pair), 0) + 1
        last_trade_time = exit_time

        trades.append(
            Trade(
                pair=sig.pair,
                side=sig.side,
                entry_time=entry_time,
                exit_time=exit_time,
                entry=entry_px,
                exit=exit_px,
                stop=sig.stop,
                take=sig.take,
                lots=lots,
                pnl=pnl,
                reason_entry=sig.reason,
                reason_exit=why,
                r_multiple=r_mult,
            )
        )
        equity_points.append((exit_time, equity))

        if day_start_equity - equity >= prop.daily_loss_limit:
            paused_days.add(day)
            daily_pauses += 1
        if equity <= floor:
            fail_reason = "max_loss"
            break

        if stop_at_profit_target and not weekly_withdraw:
            if equity - prop.initial_balance >= prop.profit_target:
                total_profit = equity - prop.initial_balance
                max_day = max(day_pnl.values()) if day_pnl else 0.0
                share = max_day / total_profit if total_profit > 0 else 0.0
                if share <= prop.consistency_pct + 1e-9:
                    passed = True
                    days_to_target = (day - pd.Timestamp(start)).days + 1
                    fail_reason = ""
                    break
        i += 1

    # Final week withdrawal flush
    if weekly_withdraw:
        equity, w = _apply_weekly_withdrawal(equity, prop)
        if w > 0:
            total_withdrawn += w
            weekly_withdrawals += 1

    total_profit = equity - equity0
    max_day = max(day_pnl.values()) if day_pnl else 0.0
    # For consistency on eval: vs profit toward target
    eval_profit = equity - prop.initial_balance
    share = (max_day / eval_profit) if eval_profit > 0 else 0.0
    consistency_ok = eval_profit <= 0 or share <= prop.consistency_pct + 1e-9

    if weekly_withdraw:
        # Funded "pass" = survived without max loss
        passed = equity > floor and fail_reason != "max_loss"
        if not passed and not fail_reason:
            fail_reason = "max_loss" if equity <= floor else ""
        total_made = total_withdrawn + (equity - equity0)
    else:
        if not passed and not fail_reason:
            if equity <= floor:
                fail_reason = "max_loss"
            elif eval_profit >= prop.profit_target and not consistency_ok:
                fail_reason = "consistency"
            else:
                fail_reason = "target_not_reached"
        total_made = eval_profit

    wins = sum(1 for t in trades if t.pnl > 0)
    trades_df = pd.DataFrame([t.__dict__ for t in trades])
    eq = (
        pd.Series({t: e for t, e in equity_points}, dtype=float).sort_index()
        if equity_points
        else pd.Series({pd.Timestamp(start): equity0})
    )
    trading_days = len(day_trades)
    avg_tpd = (len(trades) / trading_days) if trading_days else 0.0

    return PhaseResult(
        phase=phase_name,
        passed=bool(passed and (consistency_ok or weekly_withdraw) and equity > floor),
        fail_reason=fail_reason if not passed else "",
        start_equity=equity0,
        end_equity=equity,
        max_dd=max_dd,
        profit=total_profit,
        trades=len(trades),
        win_rate=(wins / len(trades) if trades else 0.0),
        avg_trades_per_day=avg_tpd,
        trading_days=trading_days,
        days_to_target=days_to_target,
        consistency_ok=consistency_ok,
        max_day_profit_share=share,
        daily_pauses=daily_pauses,
        equity_curve=eq,
        trades_df=trades_df,
        total_withdrawn=total_withdrawn,
        weekly_withdrawals=weekly_withdrawals,
        total_made=total_made,
    )


def simulate_challenge(
    universe: Dict[str, Dict[str, pd.DataFrame]],
    start: str,
    end: str,
    signal_fn: Callable,
    prop: PropRules = PROP,
    params: StrategyParams = PARAMS,
) -> Dict[str, PhaseResult]:
    """Eval (stop at +10k) then funded with weekly withdraw above $101k."""
    eval_res = run_period(
        universe,
        start,
        end,
        signal_fn=signal_fn,
        phase_name="evaluation",
        prop=prop,
        params=params,
        weekly_withdraw=False,
        stop_at_profit_target=True,
    )
    results = {"evaluation": eval_res}
    if not eval_res.passed or eval_res.trades_df.empty:
        return results

    funded_start = (
        pd.Timestamp(eval_res.trades_df["exit_time"].max()).normalize()
        + pd.Timedelta(days=1)
    ).strftime("%Y-%m-%d")
    if pd.Timestamp(funded_start) > pd.Timestamp(end):
        return results

    funded = run_period(
        universe,
        funded_start,
        end,
        signal_fn=signal_fn,
        phase_name="funded",
        prop=prop,
        params=params,
        starting_equity=prop.initial_balance,
        weekly_withdraw=True,
        stop_at_profit_target=False,
    )
    results["funded"] = funded
    return results


def edge_stats(
    universe,
    start,
    end,
    signal_fn,
    prop=PROP,
    params=PARAMS,
) -> PhaseResult:
    """Full-period edge without profit-target stop (no weekly withdraw)."""
    from dataclasses import replace

    loose = replace(prop, profit_target=10_000_000.0, consistency_pct=1.0)
    return run_period(
        universe,
        start,
        end,
        signal_fn=signal_fn,
        phase_name="edge",
        prop=loose,
        params=params,
        weekly_withdraw=False,
        stop_at_profit_target=False,
    )
