"""S4 — Asia break-and-go (momentum): enter at break close, no retest wait."""

from __future__ import annotations

from typing import List, Set, Tuple

import numpy as np
import pandas as pd

from ..common import (
    Signal,
    atr,
    h1_bias_series,
    in_killzone,
    pack_signal,
    session_ranges_complete,
)
from ..config import PARAMS, StrategyParams

RR = 1.5


def generate_signals(
    pair: str, m15: pd.DataFrame, params: StrategyParams = PARAMS
) -> List[Signal]:
    if len(m15) < params.atr_period + 40:
        return []
    atr_v = atr(m15, params.atr_period).to_numpy()
    o = m15["open"].to_numpy()
    h = m15["high"].to_numpy()
    l = m15["low"].to_numpy()
    c = m15["close"].to_numpy()
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sessions = session_ranges_complete(idx, h, l)

    signals: List[Signal] = []
    used: Set[Tuple] = set()

    for i in range(len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        if not in_killzone(idx[i], params):
            continue
        day = idx[i].normalize()
        if day not in sessions or "asia" not in sessions[day]:
            continue
        if idx[i].hour < 7:
            continue
        ah, al, ar = sessions[day]["asia"]
        if ar < 0.6 * atr_v[i] or ar > 3.5 * atr_v[i]:
            continue
        body = abs(c[i] - o[i])
        if body < 0.35 * atr_v[i]:
            continue

        key = (day, 1)
        if key not in used and bias[i] >= 0 and c[i] > ah and o[i] <= ah and c[i] > o[i]:
            entry = float(c[i])
            stop = float(max(al, entry - params.max_stop_atr * atr_v[i]))
            if entry - stop < params.min_stop_atr * atr_v[i] * 0.6:
                stop = entry - params.min_stop_atr * atr_v[i] * 0.6
            if entry > stop:
                sig = pack_signal(
                    idx[i], pair, 1, entry, stop, RR, "asia_break_go_long", marketable=True
                )
                if sig:
                    signals.append(sig)
                    used.add(key)

        key = (day, -1)
        if key not in used and bias[i] <= 0 and c[i] < al and o[i] >= al and c[i] < o[i]:
            entry = float(c[i])
            stop = float(min(ah, entry + params.max_stop_atr * atr_v[i]))
            if stop - entry < params.min_stop_atr * atr_v[i] * 0.6:
                stop = entry + params.min_stop_atr * atr_v[i] * 0.6
            if stop > entry:
                sig = pack_signal(
                    idx[i], pair, -1, entry, stop, RR, "asia_break_go_short", marketable=True
                )
                if sig:
                    signals.append(sig)
                    used.add(key)
    return signals
