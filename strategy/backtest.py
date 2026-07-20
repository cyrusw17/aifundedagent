"""Event-driven backtest with The5ers risk rules. No look-ahead fills."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from .config import PARAMS, PROP, PropRules, StrategyParams
from .signals import Signal, generate_signals


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


def _quote_to_usd_factor(pair: str, exit: float, usdjpy: Optional[float]) -> float:
    """Convert quote-currency PnL factor into USD."""
    if pair.endswith("USD") and not pair.startswith("USD"):
        return 1.0  # EURUSD, GBPUSD, AUDUSD, XAUUSD
    if pair.startswith("USD"):
        # USDJPY, USDCAD — PnL in quote ccy / quote_price
        return 1.0 / exit
    if pair.endswith("JPY"):
        # EURJPY, GBPJPY — PnL in JPY / USDJPY
        fx = usdjpy if usdjpy and usdjpy > 0 else 150.0
        return 1.0 / fx
    return 1.0


def _pip_pnl(
    pair: str,
    side: int,
    entry: float,
    exit: float,
    lots: float,
    params: StrategyParams,
    usdjpy: Optional[float] = None,
) -> float:
    cs = params.contract_sizes[pair]
    move = (exit - entry) * side
    return lots * cs * move * _quote_to_usd_factor(pair, exit, usdjpy)


def _lots_for_risk(
    pair: str,
    entry: float,
    stop: float,
    risk_amount: float,
    params: StrategyParams,
    usdjpy: Optional[float] = None,
) -> float:
    stop_dist = abs(entry - stop)
    if stop_dist <= 0:
        return 0.0
    cs = params.contract_sizes[pair]
    # risk_cash ≈ lots * cs * stop_dist * usd_factor
    usd_f = _quote_to_usd_factor(pair, entry, usdjpy)
    denom = cs * stop_dist * usd_f
    if denom <= 0:
        return 0.0
    lots = risk_amount / denom
    lots = max(0.01, np.floor(lots * 100) / 100.0)
    return float(lots)


def _simulate_limit_entry_and_exit(
    m1: pd.DataFrame,
    signal: Signal,
    params: StrategyParams,
) -> Optional[Tuple[pd.Timestamp, float, pd.Timestamp, float, str]]:
    """Enter after signal bar; prefer limit at signal.entry if touched, else skip.

    Conservative same-bar SL/TP: if both touched, SL wins.
    """
    # First M1 bar strictly after signal time (signal on M15 close)
    pos = m1.index.searchsorted(signal.time, side="right")
    if pos >= len(m1):
        return None

    side = signal.side
    limit = signal.entry
    spread = params.spreads[signal.pair]
    stop = signal.stop

    times = m1.index
    highs = m1["high"].to_numpy()
    lows = m1["low"].to_numpy()
    closes = m1["close"].to_numpy()
    opens = m1["open"].to_numpy()
    hours = times.hour

    # Limit at Asia edge — fill on touch within 240 minutes (retest window)
    end_fill = min(len(m1), pos + 240)
    entry_i = None
    entry_px = None
    if side == 1:
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
    if side == 1:
        risk = entry_px - stop
        if risk <= 0:
            return None
        take = entry_px + params.reward_risk * risk
    else:
        risk = stop - entry_px
        if risk <= 0:
            return None
        take = entry_px - params.reward_risk * risk

    day = entry_time.normalize()
    # A-priori management: move stop to breakeven after +1R favorable excursion
    be_level = entry_px
    be_armed = False
    one_r = abs(entry_px - stop)

    j = entry_i + 1
    while j < len(m1):
        ts = times[j]
        if ts.normalize() == day and hours[j] >= params.flatten_hour_utc:
            return entry_time, float(entry_px), ts, float(closes[j]), "flatten"
        if ts.normalize() > day:
            return entry_time, float(entry_px), ts, float(opens[j]), "flatten_next"

        if side == 1:
            if not be_armed and highs[j] >= entry_px + one_r:
                be_armed = True
                stop = be_level
            hit_sl = lows[j] <= stop
            hit_tp = highs[j] >= take
            if hit_sl and hit_tp:
                # conservative: SL first
                return entry_time, float(entry_px), ts, float(stop), "be" if be_armed else "sl"
            if hit_sl:
                return entry_time, float(entry_px), ts, float(stop), "be" if be_armed else "sl"
            if hit_tp:
                return entry_time, float(entry_px), ts, float(take), "tp"
        else:
            if not be_armed and lows[j] <= entry_px - one_r:
                be_armed = True
                stop = be_level
            hit_sl = highs[j] >= stop
            hit_tp = lows[j] <= take
            if hit_sl and hit_tp:
                return entry_time, float(entry_px), ts, float(stop), "be" if be_armed else "sl"
            if hit_sl:
                return entry_time, float(entry_px), ts, float(stop), "be" if be_armed else "sl"
            if hit_tp:
                return entry_time, float(entry_px), ts, float(take), "tp"
        j += 1

    last_i = len(m1) - 1
    return entry_time, float(entry_px), times[last_i], float(closes[last_i]), "eod_data"


def run_period(
    universe: Dict[str, Dict[str, pd.DataFrame]],
    start: str,
    end: str,
    phase_name: str = "eval",
    prop: PropRules = PROP,
    params: StrategyParams = PARAMS,
    starting_equity: Optional[float] = None,
) -> PhaseResult:
    from .data_loader import slice_period

    equity0 = prop.initial_balance if starting_equity is None else starting_equity
    equity = equity0
    peak = equity
    max_dd = 0.0

    # Precompute signals per pair on sliced M15
    all_signals: List[Signal] = []
    m1_map = {}
    for pair, frames in universe.items():
        m15 = slice_period(frames["m15"], start, end)
        m1 = slice_period(frames["m1"], start, end)
        m1_map[pair] = m1
        # Warmup: include lookback before start for swings
        m15_warm = frames["m15"]
        warm_start = pd.Timestamp(start) - pd.Timedelta(days=20)
        m15_sig = m15_warm.loc[
            (m15_warm.index >= warm_start)
            & (m15_warm.index < pd.Timestamp(end) + pd.Timedelta(days=1))
        ]
        sigs = generate_signals(pair, m15_sig, params)
        for s in sigs:
            if pd.Timestamp(start) <= s.time < pd.Timestamp(end) + pd.Timedelta(days=1):
                all_signals.append(s)

    all_signals.sort(key=lambda s: s.time)

    trades: List[Trade] = []
    day_pnl: Dict[pd.Timestamp, float] = {}
    day_trades: Dict[pd.Timestamp, int] = {}
    day_pair_trades: Dict[Tuple[pd.Timestamp, str], int] = {}
    paused_days = set()
    daily_pauses = 0
    open_positions = 0  # sequential sim — we don't overlap fills for simplicity
    last_trade_time: Optional[pd.Timestamp] = None
    fail_reason = ""
    passed = False
    days_to_target: Optional[int] = None
    equity_points = []

    floor = prop.initial_balance - prop.max_loss
    risk_amount = prop.initial_balance * params.risk_pct

    # Track day start equity for daily loss
    current_day = None
    day_start_equity = equity

    i = 0
    while i < len(all_signals):
        sig = all_signals[i]
        day = sig.time.normalize()

        if current_day is None or day != current_day:
            current_day = day
            day_start_equity = equity

        if day in paused_days:
            i += 1
            continue

        # Prop daily pause
        if day_start_equity - equity >= prop.daily_loss_limit:
            paused_days.add(day)
            daily_pauses += 1
            i += 1
            continue

        # Soft daily profit cap (consistency)
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

        # Static max loss floor
        if equity <= floor:
            fail_reason = "max_loss"
            break

        m1 = m1_map[sig.pair]
        fill = _simulate_limit_entry_and_exit(m1, sig, params)
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

        # Hard caps — prevent pathological sizing; still within 1:100 leverage
        if sig.pair == "XAUUSD":
            lots = min(lots, 3.0)
        else:
            lots = min(lots, 8.0)

        cs = params.contract_sizes[sig.pair]
        pnl = _pip_pnl(
            sig.pair, sig.side, entry_px, exit_px, lots, params, usdjpy=usdjpy_px
        )
        risk_dist = abs(entry_px - sig.stop)
        r_mult = 0.0
        if risk_dist > 0:
            risk_cash = (
                lots
                * cs
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
                take=sig.take if sig.side == 1 else sig.take,
                lots=lots,
                pnl=pnl,
                reason_entry=sig.reason,
                reason_exit=why,
                r_multiple=r_mult,
            )
        )
        equity_points.append((exit_time, equity))

        # Daily pause check after trade
        if day_start_equity - equity >= prop.daily_loss_limit:
            paused_days.add(day)
            daily_pauses += 1

        if equity <= floor:
            fail_reason = "max_loss"
            break

        # Profit target
        if equity - prop.initial_balance >= prop.profit_target:
            # consistency: max single day profit <= 50% of total profit
            total_profit = equity - prop.initial_balance
            max_day = max(day_pnl.values()) if day_pnl else 0.0
            share = max_day / total_profit if total_profit > 0 else 0.0
            if share <= prop.consistency_pct + 1e-9:
                passed = True
                days_to_target = (day - pd.Timestamp(start)).days + 1
                fail_reason = ""
                break
            # else keep trading until consistency satisfied or fail
        i += 1

    total_profit = equity - prop.initial_balance
    max_day = max(day_pnl.values()) if day_pnl else 0.0
    share = (max_day / total_profit) if total_profit > 0 else 0.0
    consistency_ok = total_profit <= 0 or share <= prop.consistency_pct + 1e-9

    if not passed and not fail_reason:
        if equity <= floor:
            fail_reason = "max_loss"
        elif total_profit >= prop.profit_target and not consistency_ok:
            fail_reason = "consistency"
        else:
            fail_reason = "target_not_reached"

    wins = sum(1 for t in trades if t.pnl > 0)
    trades_df = pd.DataFrame([t.__dict__ for t in trades])
    if equity_points:
        eq = pd.Series(
            {t: e for t, e in equity_points}, dtype=float
        ).sort_index()
    else:
        eq = pd.Series({pd.Timestamp(start): equity0})

    trading_days = len(day_trades)
    avg_tpd = (len(trades) / trading_days) if trading_days else 0.0

    return PhaseResult(
        phase=phase_name,
        passed=passed and consistency_ok and equity > floor,
        fail_reason=fail_reason if not (passed and consistency_ok) else "",
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
    )


def simulate_challenge(
    universe: Dict[str, Dict[str, pd.DataFrame]],
    start: str,
    end: str,
    prop: PropRules = PROP,
    params: StrategyParams = PARAMS,
) -> Dict[str, PhaseResult]:
    """Run evaluation then funded phase sequentially inside [start, end]."""
    eval_res = run_period(
        universe, start, end, phase_name="evaluation", prop=prop, params=params
    )
    results = {"evaluation": eval_res}
    if not eval_res.passed:
        return results

    # Funded phase starts after last eval trade day
    if eval_res.trades_df.empty:
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
        phase_name="funded",
        prop=prop,
        params=params,
        starting_equity=prop.initial_balance,  # reset to 100k funded account
    )
    results["funded"] = funded
    return results
