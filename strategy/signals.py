"""Asia Range Break & Retest (ICT Power of 3 / AMD day model).

A priori rules (not optimized):
1. Build Asia range 00:00-06:59 UTC
2. In London (07-11) or NY (12-17) killzone, require a break + close beyond Asia
3. Enter on retest of the broken Asia edge (limit at boundary)
4. Stop beyond Asia opposite extreme (or break wick extreme)
5. Take profit at 1.5R (fixed)
6. Optional H1 bias filter aligned with break direction

Causal / no look-ahead.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from .config import PARAMS, StrategyParams


@dataclass
class Signal:
    time: pd.Timestamp
    pair: str
    side: int
    entry: float
    stop: float
    take: float
    sweep_extreme: float
    reason: str


def _atr(df: pd.DataFrame, period: int) -> pd.Series:
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


def _in_killzone(ts: pd.Timestamp, params: StrategyParams) -> bool:
    h = ts.hour + ts.minute / 60.0
    for start, end in params.killzones_utc:
        if start <= h < end:
            return True
    return False


def _session_ranges(
    index: pd.DatetimeIndex, high: np.ndarray, low: np.ndarray
) -> Dict[pd.Timestamp, Dict[str, Tuple[float, float, float]]]:
    """day -> {asia:(h,l,r), london:(h,l,r)}."""
    df = pd.DataFrame({"high": high, "low": low}, index=index)
    out: Dict[pd.Timestamp, Dict[str, Tuple[float, float, float]]] = {}
    for day, chunk in df.groupby(df.index.normalize()):
        levels = {}
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


def _confirmed_swings(high, low, left, right):
    n = len(high)
    sh, sl = [], []
    for p in range(left, n - right):
        wh = high[p - left : p + right + 1]
        wl = low[p - left : p + right + 1]
        if high[p] >= wh.max() and int(np.argmax(wh)) == left:
            sh.append((p, float(high[p])))
        if low[p] <= wl.min() and int(np.argmin(wl)) == left:
            sl.append((p, float(low[p])))
    return sh, sl


def _h1_bias_series(m15: pd.DataFrame) -> pd.Series:
    h1 = (
        m15.resample("1h", label="left", closed="left")
        .agg({"open": "first", "high": "max", "low": "min", "close": "last"})
        .dropna()
    )
    sh, sl = _confirmed_swings(h1["high"].values, h1["low"].values, 2, 2)
    bias = pd.Series(0, index=h1.index, dtype=int)
    known_sh, known_sl = [], []
    sh_conf, sl_conf = {}, {}
    for p, price in sh:
        sh_conf.setdefault(p + 2, []).append((p, price))
    for p, price in sl:
        sl_conf.setdefault(p + 2, []).append((p, price))
    for i in range(len(h1)):
        if i in sh_conf:
            known_sh.extend(sh_conf[i])
        if i in sl_conf:
            known_sl.extend(sl_conf[i])
        if len(known_sh) >= 2 and len(known_sl) >= 2:
            if known_sh[-1][1] > known_sh[-2][1] and known_sl[-1][1] > known_sl[-2][1]:
                bias.iloc[i] = 1
            elif known_sh[-1][1] < known_sh[-2][1] and known_sl[-1][1] < known_sl[-2][1]:
                bias.iloc[i] = -1
            else:
                bias.iloc[i] = bias.iloc[i - 1] if i else 0
        elif i:
            bias.iloc[i] = bias.iloc[i - 1]
    return bias.shift(1).reindex(m15.index, method="ffill").fillna(0).astype(int)


def generate_signals(
    pair: str,
    m15: pd.DataFrame,
    params: StrategyParams = PARAMS,
) -> List[Signal]:
    if len(m15) < params.atr_period + 50:
        return []

    atr = _atr(m15, params.atr_period).to_numpy()
    o = m15["open"].to_numpy()
    h = m15["high"].to_numpy()
    l = m15["low"].to_numpy()
    c = m15["close"].to_numpy()
    idx = m15.index
    bias = _h1_bias_series(m15).to_numpy()
    sessions = _session_ranges(idx, h, l)

    signals: List[Signal] = []
    state = None
    signaled = set()  # (day, session_name, side)

    for i in range(len(m15)):
        day = idx[i].normalize()
        if day not in sessions:
            state = None
            continue
        if np.isnan(atr[i]) or atr[i] <= 0:
            continue
        if not _in_killzone(idx[i], params):
            continue

        if state is not None and (state["day"] != day or i - state["break_i"] > 12):
            state = None

        # Choose active range: Asia for London+NY; London range only in NY
        hour = idx[i].hour
        candidates = []
        if "asia" in sessions[day]:
            candidates.append(("asia", sessions[day]["asia"]))
        if hour >= 12 and "london" in sessions[day]:
            candidates.append(("london", sessions[day]["london"]))

        if state is None:
            for name, (rh, rl, rr) in candidates:
                if rr < 0.6 * atr[i] or rr > 4.0 * atr[i]:
                    continue
                if c[i] > rh and o[i] <= rh and bias[i] >= 0:
                    key = (day, name, 1)
                    if key not in signaled:
                        state = {
                            "side": 1,
                            "day": day,
                            "sess": name,
                            "break_i": i,
                            "edge": rh,
                            "extreme": float(max(h[i], rh)),
                            "range": rr,
                            "invalid": rl,
                        }
                        break
                elif c[i] < rl and o[i] >= rl and bias[i] <= 0:
                    key = (day, name, -1)
                    if key not in signaled:
                        state = {
                            "side": -1,
                            "day": day,
                            "sess": name,
                            "break_i": i,
                            "edge": rl,
                            "extreme": float(min(l[i], rl)),
                            "range": rr,
                            "invalid": rh,
                        }
                        break
            continue

        side = state["side"]
        edge = state["edge"]
        zone = 0.15 * state["range"]
        if side == 1:
            touched = l[i] <= edge + zone and h[i] >= edge - zone
            held = c[i] > edge - zone and c[i] >= o[i]
            if not (touched and held):
                if c[i] < state["invalid"]:
                    state = None
                continue
            entry = edge
            stop = float(min(l[i], state["extreme"], edge) - 0.15 * atr[i])
            risk = entry - stop
            if risk < params.min_stop_atr * atr[i]:
                stop = entry - params.min_stop_atr * atr[i]
                risk = entry - stop
            if risk > params.max_stop_atr * atr[i]:
                state = None
                continue
            take = entry + params.reward_risk * risk
            reason = f"{state['sess']}_break_retest_long"
            signals.append(
                Signal(
                    time=idx[i],
                    pair=pair,
                    side=1,
                    entry=float(entry),
                    stop=float(stop),
                    take=float(take),
                    sweep_extreme=float(stop),
                    reason=reason,
                )
            )
            signaled.add((day, state["sess"], 1))
            state = None
        else:
            touched = h[i] >= edge - zone and l[i] <= edge + zone
            held = c[i] < edge + zone and c[i] <= o[i]
            if not (touched and held):
                if c[i] > state["invalid"]:
                    state = None
                continue
            entry = edge
            stop = float(max(h[i], state["extreme"], edge) + 0.15 * atr[i])
            risk = stop - entry
            if risk < params.min_stop_atr * atr[i]:
                stop = entry + params.min_stop_atr * atr[i]
                risk = stop - entry
            if risk > params.max_stop_atr * atr[i]:
                state = None
                continue
            take = entry - params.reward_risk * risk
            reason = f"{state['sess']}_break_retest_short"
            signals.append(
                Signal(
                    time=idx[i],
                    pair=pair,
                    side=-1,
                    entry=float(entry),
                    stop=float(stop),
                    take=float(take),
                    sweep_extreme=float(stop),
                    reason=reason,
                )
            )
            signaled.add((day, state["sess"], -1))
            state = None

    return signals
