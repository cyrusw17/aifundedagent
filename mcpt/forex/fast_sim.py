"""Fast vector-friendly trade simulator for research (still no look-ahead)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd

from mcpt.forex.account import FundedRules
from mcpt.forex.signals import generate_signals


@dataclass
class FastStats:
    n_trades: int
    win_rate: float
    profit_factor: float
    avg_annual_pnl: float
    net_wealth_gain: float
    total_withdrawn: float
    max_dd: float
    blown: bool
    blow_reason: str
    consistency_ok: bool
    consistency_ratio: float
    hit_eval_target: bool
    years: float
    final_balance: float

    def as_dict(self) -> dict:
        d = self.__dict__.copy()
        d["consistency_ok"] = bool(self.consistency_ok)
        d["blown"] = bool(self.blown)
        d["hit_eval_target"] = bool(self.hit_eval_target)
        return d


def prepare_pair(ohlc: pd.DataFrame, mode: str, swing: int, min_conf: int):
    ohlc = ohlc.copy()
    ohlc.index = pd.to_datetime(ohlc.index)
    if ohlc.index.tz is not None:
        ohlc.index = ohlc.index.tz_localize(None)
    sig, feats = generate_signals(
        ohlc, mode=mode, swing_left=swing, swing_right=swing, min_confluence=min_conf
    )
    return {
        "open": ohlc["open"].to_numpy(dtype=float),
        "high": ohlc["high"].to_numpy(dtype=float),
        "low": ohlc["low"].to_numpy(dtype=float),
        "close": ohlc["close"].to_numpy(dtype=float),
        "atr": feats["atr"].to_numpy(dtype=float),
        "sig": sig.to_numpy(dtype=int),
        "times": ohlc.index.to_numpy(),
        "index": ohlc.index,
    }


def prepare_book(book: dict[str, pd.DataFrame], mode: str, swing: int = 3, min_conf: int = 3):
    prepared = {p: prepare_pair(df, mode, swing, min_conf) for p, df in book.items()}
    # Cache shared timeline once — rebuilding it dominated H1 hunt runtime.
    pairs = list(prepared.keys())
    time_map: dict = {}
    entry_times = set()
    for pi, p in enumerate(pairs):
        times = prepared[p]["times"]
        sig = prepared[p]["sig"]
        for bi, t in enumerate(times):
            time_map.setdefault(t, []).append((pi, bi))
            if bi > 0 and sig[bi - 1] != 0:
                entry_times.add(t)
    timeline = sorted(time_map.keys())
    next_entry_from = {}
    nxt = None
    for t in reversed(timeline):
        if t in entry_times:
            nxt = t
        next_entry_from[t] = nxt
    prepared["__meta__"] = {
        "pairs": pairs,
        "time_map": time_map,
        "timeline": timeline,
        "next_entry_from": next_entry_from,
    }
    return prepared


def fast_backtest(
    prepared: dict,
    risk_pct: float = 0.0075,
    rr: float = 2.0,
    atr_stop_mult: float = 1.25,
    max_positions: int = 2,
    move_be_at_r: float = 0.0,
    skip_mondays: bool = True,
    daily_halt_loss_pct: float = 0.015,
    daily_halt_profit_pct: float = 0.025,
    cooldown_losses: int = 3,
    weekly_withdraw: bool = True,
    one_entry_per_day: bool = True,
    rules: FundedRules | None = None,
) -> FastStats:
    rules = rules or FundedRules()
    meta = prepared.get("__meta__")
    if meta is None:
        # backward compatible: rebuild timeline once for ad-hoc prepared dicts
        tmp = {k: v for k, v in prepared.items() if k != "__meta__"}
        pairs = list(tmp.keys())
        time_map: dict = {}
        entry_times = set()
        for pi, p in enumerate(pairs):
            times = tmp[p]["times"]
            sig = tmp[p]["sig"]
            for bi, t in enumerate(times):
                time_map.setdefault(t, []).append((pi, bi))
                if bi > 0 and sig[bi - 1] != 0:
                    entry_times.add(t)
        timeline = sorted(time_map.keys())
        next_entry_from = {}
        nxt = None
        for t in reversed(timeline):
            if t in entry_times:
                nxt = t
            next_entry_from[t] = nxt
        prepared = dict(tmp)
        prepared["__meta__"] = {
            "pairs": pairs,
            "time_map": time_map,
            "timeline": timeline,
            "next_entry_from": next_entry_from,
        }
        meta = prepared["__meta__"]

    pairs = meta["pairs"]
    time_map = meta["time_map"]
    timeline = meta["timeline"]
    next_entry_from = meta["next_entry_from"]
    # pair data lookups must ignore meta key
    prepared_pairs = {k: v for k, v in prepared.items() if k != "__meta__"}

    balance = rules.initial_balance
    equity = balance
    day_start = balance
    floor = rules.floor_balance
    daily_lim = rules.daily_loss_limit
    blown = False
    blow_reason = ""
    total_withdrawn = 0.0
    daily_pnl: dict = {}
    # open trades: list of dicts
    opens = []
    pnls = []
    equity_series = []
    current_day = None
    current_week = None
    day_halted = False
    consec_loss = 0
    cooldown = 0
    peak_eq = balance
    ti = 0
    n_tl = len(timeline)

    while ti < n_tl:
        t = timeline[ti]
        # numpy datetime64
        ts = pd.Timestamp(t)
        day = ts.date()
        week = (ts.isocalendar().year, ts.isocalendar().week)

        if current_day is None or day != current_day:
            current_day = day
            day_start = equity
            day_halted = False
        if weekly_withdraw and current_week is not None and week != current_week:
            excess = balance - rules.initial_balance
            if excess >= rules.withdraw_min:
                amt = min(excess, rules.withdraw_cap)
                balance -= amt
                equity = balance
                total_withdrawn += amt
        current_week = week

        if blown:
            equity_series.append(equity)
            ti += 1
            continue

        # manage opens
        still = []
        for tr in opens:
            p = pairs[tr["pi"]]
            bi = time_map[t]
            # find bar index for this pair today
            bar_i = None
            for pi2, b2 in bi:
                if pi2 == tr["pi"]:
                    bar_i = b2
                    break
            if bar_i is None:
                still.append(tr)
                continue
            d = prepared[p]
            hi, lo = d["high"][bar_i], d["low"][bar_i]
            # BE
            if move_be_at_r and not tr["be"]:
                be_lvl = tr["entry"] + tr["dir"] * move_be_at_r * tr["dist"]
                if tr["dir"] == 1 and hi >= be_lvl:
                    tr["stop"] = max(tr["stop"], tr["entry"])
                    tr["be"] = True
                elif tr["dir"] == -1 and lo <= be_lvl:
                    tr["stop"] = min(tr["stop"], tr["entry"])
                    tr["be"] = True
            hit_stop = (lo <= tr["stop"]) if tr["dir"] == 1 else (hi >= tr["stop"])
            hit_tp = (hi >= tr["target"]) if tr["dir"] == 1 else (lo <= tr["target"])
            if hit_stop and hit_tp:
                exit_px, reason = tr["stop"], "stop"
            elif hit_stop:
                exit_px, reason = tr["stop"], "stop"
            elif hit_tp:
                exit_px, reason = tr["target"], "target"
            else:
                still.append(tr)
                continue
            r_mult = tr["dir"] * (exit_px - tr["entry"]) / tr["dist"]
            pnl = r_mult * tr["risk"]
            balance += pnl
            equity = balance
            pnls.append(pnl)
            daily_pnl[day] = daily_pnl.get(day, 0.0) + pnl
            if pnl < 0:
                consec_loss += 1
                if cooldown_losses and consec_loss >= cooldown_losses:
                    cooldown = 2
                    consec_loss = 0
            else:
                consec_loss = 0
            if equity <= floor:
                blown, blow_reason = True, "max_loss"
            day_loss = day_start - equity
            if day_loss >= daily_lim:
                blown, blow_reason = True, "daily_loss"
        opens = still

        # mtm
        floating = 0.0
        for tr in opens:
            p = pairs[tr["pi"]]
            bar_i = None
            for pi2, b2 in time_map[t]:
                if pi2 == tr["pi"]:
                    bar_i = b2
                    break
            if bar_i is None:
                continue
            px = prepared[p]["close"][bar_i]
            floating += tr["dir"] * (px - tr["entry"]) / tr["dist"] * tr["risk"]
        equity = balance + floating
        peak_eq = max(peak_eq, equity)
        if equity <= floor:
            blown, blow_reason = True, "max_loss"
        if day_start - equity >= daily_lim:
            blown, blow_reason = True, "daily_loss"

        day_pnl_now = equity - day_start
        if day_pnl_now <= -rules.initial_balance * daily_halt_loss_pct:
            day_halted = True
        if day_pnl_now >= rules.initial_balance * daily_halt_profit_pct:
            day_halted = True

        # entries from prior bar signal
        allow = (not blown) and (not day_halted) and cooldown <= 0 and len(opens) < max_positions
        if skip_mondays and ts.dayofweek == 0:
            allow = False
        if allow:
            room = equity - floor
            daily_room = daily_lim - max(0.0, day_start - equity)
            entries_today = 0
            for pi, bar_i in time_map[t]:
                if len(opens) >= max_positions:
                    break
                if one_entry_per_day and entries_today >= 1:
                    break
                if bar_i == 0:
                    continue
                if any(tr["pi"] == pi for tr in opens):
                    continue
                d = prepared[pairs[pi]]
                direction = int(d["sig"][bar_i - 1])
                if direction == 0:
                    continue
                atr = d["atr"][bar_i - 1]
                if not np.isfinite(atr) or atr <= 0:
                    continue
                entry = d["open"][bar_i]
                dist = atr_stop_mult * atr
                stop = entry - dist if direction == 1 else entry + dist
                target = entry + rr * dist if direction == 1 else entry - rr * dist
                risk = min(equity * risk_pct, max(room * 0.45, 0.0), max(daily_room * 0.5, 0.0))
                if risk < equity * 0.001:
                    continue
                opens.append(
                    {
                        "pi": pi,
                        "dir": direction,
                        "entry": entry,
                        "stop": stop,
                        "target": target,
                        "dist": dist,
                        "risk": risk,
                        "be": False,
                    }
                )
                room -= risk
                daily_room -= risk
                entries_today += 1

        if cooldown > 0:
            cooldown -= 1
        equity_series.append(equity)

        # skip idle bars while flat (no open risk / no pending entry)
        if not opens and not blown and cooldown <= 0:
            nxt = next_entry_from.get(t)
            if nxt is not None and nxt != t:
                lo_i, hi_i = ti + 1, n_tl - 1
                target_i = None
                while lo_i <= hi_i:
                    mid = (lo_i + hi_i) // 2
                    if timeline[mid] < nxt:
                        lo_i = mid + 1
                    elif timeline[mid] > nxt:
                        hi_i = mid - 1
                    else:
                        target_i = mid
                        break
                if target_i is not None and target_i > ti:
                    # apply weekly withdrawals for each ISO week crossed during jump
                    if weekly_withdraw and current_week is not None:
                        end_ts = pd.Timestamp(timeline[target_i])
                        end_week = (end_ts.isocalendar().year, end_ts.isocalendar().week)
                        # approximate week distance; apply at most one withdraw per crossed week
                        y0, w0 = current_week
                        y1, w1 = end_week
                        weeks = max(0, (y1 - y0) * 52 + (w1 - w0))
                        for _ in range(weeks):
                            excess = balance - rules.initial_balance
                            if excess >= rules.withdraw_min:
                                amt = min(excess, rules.withdraw_cap)
                                balance -= amt
                                equity = balance
                                total_withdrawn += amt
                        current_week = end_week
                    ti = target_i
                    continue
        ti += 1

    # flatten opens at end
    if opens and timeline:
        t = timeline[-1]
        day = pd.Timestamp(t).date()
        for tr in opens:
            p = pairs[tr["pi"]]
            px = prepared[p]["close"][-1]
            pnl = tr["dir"] * (px - tr["entry"]) / tr["dist"] * tr["risk"]
            balance += pnl
            equity = balance
            pnls.append(pnl)
            daily_pnl[day] = daily_pnl.get(day, 0.0) + pnl

    years = 1.0
    if len(timeline) > 1:
        years = max((pd.Timestamp(timeline[-1]) - pd.Timestamp(timeline[0])).days / 365.25, 1 / 365)

    wealth = (balance - rules.initial_balance) + total_withdrawn
    ann = wealth / years
    wins = [p for p in pnls if p > 0]
    losses = [p for p in pnls if p <= 0]
    gp, gl = sum(wins), abs(sum(losses))
    pf = gp / gl if gl > 0 else (10.0 if gp > 0 else 0.0)
    eq = np.array(equity_series, dtype=float) if equity_series else np.array([balance])
    peak = np.maximum.accumulate(eq)
    max_dd = float((peak - eq).max()) if len(eq) else 0.0
    pos = [v for v in daily_pnl.values() if v > 0]
    cons_ratio = (max(pos) / sum(pos)) if pos else 0.0
    hit = (float(eq.max()) >= rules.evaluation_target) and not blown

    return FastStats(
        n_trades=len(pnls),
        win_rate=(len(wins) / len(pnls)) if pnls else 0.0,
        profit_factor=float(pf),
        avg_annual_pnl=float(ann),
        net_wealth_gain=float(wealth),
        total_withdrawn=float(total_withdrawn),
        max_dd=max_dd,
        blown=blown,
        blow_reason=blow_reason,
        consistency_ok=cons_ratio <= rules.consistency_pct + 1e-9,
        consistency_ratio=float(cons_ratio),
        hit_eval_target=bool(hit),
        years=float(years),
        final_balance=float(balance),
    )
