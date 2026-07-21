"""Shared causal helpers. No look-ahead: swings confirm at pivot+right; H1 bias shifted."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from .config import StrategyParams


@dataclass
class Signal:
    time: pd.Timestamp  # M15 bar *open* time where the setup completed
    pair: str
    side: int
    entry: float
    stop: float
    take: float
    sweep_extreme: float
    reason: str
    reward_risk: float = 1.5
    marketable: bool = False  # if True, fill at next M1 open after knowable_at
    # Earliest moment the signal is knowable (= bar close). Fills before this = look-ahead.
    knowable_at: Optional[pd.Timestamp] = None
    signal_tf_minutes: int = 15


def atr(df: pd.DataFrame, period: int) -> pd.Series:
    prev_close = df["close"].shift(1)
    tr = pd.concat(
        [
            df["high"] - df["low"],
            (df["high"] - prev_close).abs(),
            (df["low"] - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)
    return tr.rolling(period, min_periods=period).mean()


def in_killzone(ts: pd.Timestamp, params: StrategyParams) -> bool:
    h = ts.hour + ts.minute / 60.0
    for start, end in params.killzones_utc:
        if start <= h < end:
            return True
    return False


def in_window(ts: pd.Timestamp, start_h: float, end_h: float) -> bool:
    h = ts.hour + ts.minute / 60.0
    return start_h <= h < end_h


def confirmed_swings(
    high: np.ndarray, low: np.ndarray, left: int, right: int
) -> Tuple[List[Tuple[int, float]], List[Tuple[int, float]]]:
    """Pivot at p is only known at bar p+right (causal)."""
    n = len(high)
    sh: List[Tuple[int, float]] = []
    sl: List[Tuple[int, float]] = []
    for p in range(left, n - right):
        wh = high[p - left : p + right + 1]
        wl = low[p - left : p + right + 1]
        if high[p] >= wh.max() and int(np.argmax(wh)) == left:
            sh.append((p, float(high[p])))
        if low[p] <= wl.min() and int(np.argmin(wl)) == left:
            sl.append((p, float(low[p])))
    return sh, sl


def h1_bias_series(m15: pd.DataFrame, left: int = 2, right: int = 2) -> pd.Series:
    """Last *closed* H1 structure bias mapped onto M15 (shift 1h)."""
    h1 = (
        m15.resample("1h", label="left", closed="left")
        .agg({"open": "first", "high": "max", "low": "min", "close": "last"})
        .dropna()
    )
    sh, sl = confirmed_swings(h1["high"].values, h1["low"].values, left, right)
    bias = pd.Series(0, index=h1.index, dtype=int)
    known_sh: List[Tuple[int, float]] = []
    known_sl: List[Tuple[int, float]] = []
    sh_conf: Dict[int, List[Tuple[int, float]]] = {}
    sl_conf: Dict[int, List[Tuple[int, float]]] = {}
    for p, price in sh:
        sh_conf.setdefault(p + right, []).append((p, price))
    for p, price in sl:
        sl_conf.setdefault(p + right, []).append((p, price))
    for i in range(len(h1)):
        if i in sh_conf:
            known_sh.extend(sh_conf[i])
        if i in sl_conf:
            known_sl.extend(sl_conf[i])
        if len(known_sh) >= 2 and len(known_sl) >= 2:
            hh = known_sh[-1][1] > known_sh[-2][1]
            hl = known_sl[-1][1] > known_sl[-2][1]
            lh = known_sh[-1][1] < known_sh[-2][1]
            ll = known_sl[-1][1] < known_sl[-2][1]
            if hh and hl:
                bias.iloc[i] = 1
            elif lh and ll:
                bias.iloc[i] = -1
            else:
                bias.iloc[i] = bias.iloc[i - 1] if i else 0
        elif i:
            bias.iloc[i] = bias.iloc[i - 1]
    return bias.shift(1).reindex(m15.index, method="ffill").fillna(0).astype(int)


def session_ranges_complete(
    index: pd.DatetimeIndex, high: np.ndarray, low: np.ndarray
) -> Dict[pd.Timestamp, Dict[str, Tuple[float, float, float]]]:
    """Completed session ranges only.

    Asia (00-06:59) is known from 07:00 onward.
    London (07-11:59) is known from 12:00 onward.
    Callers must gate London usage with hour >= 12.
    """
    df = pd.DataFrame({"high": high, "low": low}, index=index)
    out: Dict[pd.Timestamp, Dict[str, Tuple[float, float, float]]] = {}
    for day, chunk in df.groupby(df.index.normalize()):
        levels: Dict[str, Tuple[float, float, float]] = {}
        asia = chunk.between_time("00:00", "06:59")
        if len(asia) >= 6:
            ah, al = float(asia["high"].max()), float(asia["low"].min())
            if ah > al:
                levels["asia"] = (ah, al, ah - al)
        london = chunk.between_time("07:00", "11:59")
        if len(london) >= 6:
            lh, ll = float(london["high"].max()), float(london["low"].min())
            if lh > ll:
                levels["london"] = (lh, ll, lh - ll)
        if levels:
            out[day] = levels
    return out


def prior_day_hl(
    index: pd.DatetimeIndex, high: np.ndarray, low: np.ndarray
) -> Dict[pd.Timestamp, Tuple[float, float]]:
    df = pd.DataFrame({"high": high, "low": low}, index=index)
    days = list(df.groupby(df.index.normalize()))
    out: Dict[pd.Timestamp, Tuple[float, float]] = {}
    for i, (day, _) in enumerate(days):
        if i == 0:
            continue
        prev = days[i - 1][1]
        out[day] = (float(prev["high"].max()), float(prev["low"].min()))
    return out


def bullish_fvg(h, l, i: int, min_gap: float) -> Optional[Tuple[float, float]]:
    if i < 2:
        return None
    gap_low, gap_high = h[i - 2], l[i]
    if gap_high - gap_low >= min_gap:
        return float(gap_low), float(gap_high)
    return None


def bearish_fvg(h, l, i: int, min_gap: float) -> Optional[Tuple[float, float]]:
    if i < 2:
        return None
    gap_high, gap_low = l[i - 2], h[i]
    if gap_high - gap_low >= min_gap:
        return float(gap_low), float(gap_high)
    return None


def pack_signal(
    time,
    pair,
    side,
    entry,
    stop,
    rr: float,
    reason: str,
    marketable: bool = False,
    signal_tf_minutes: int = 15,
) -> Optional[Signal]:
    risk = abs(entry - stop)
    if risk <= 0:
        return None
    take = entry + rr * risk if side == 1 else entry - rr * risk
    ts = pd.Timestamp(time)
    # Signal features use the closed bar; it is only knowable at bar close.
    knowable = ts + pd.Timedelta(minutes=signal_tf_minutes)
    return Signal(
        time=ts,
        pair=pair,
        side=side,
        entry=float(entry),
        stop=float(stop),
        take=float(take),
        sweep_extreme=float(stop),
        reason=reason,
        reward_risk=float(rr),
        marketable=marketable,
        knowable_at=knowable,
        signal_tf_minutes=signal_tf_minutes,
    )
