"""S2 — NY fade of London session extremes (nested Power of 3).

After 12:00 UTC, London range is complete. Fade a failed break of London high/low
(Turtle Soup on London liquidity) aligned with H1 bias.
"""

from __future__ import annotations

from typing import List, Set, Tuple

import numpy as np
import pandas as pd

from ..common import (
    Signal,
    atr,
    h1_bias_series,
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

    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        # London complete only from 12:00; trade NY window
        if idx[i].hour < 12 or idx[i].hour >= 17:
            continue
        day = idx[i].normalize()
        if day not in sessions or "london" not in sessions[day]:
            continue
        lh, ll, lr = sessions[day]["london"]
        if lr < 0.5 * atr_v[i] or lr > 4 * atr_v[i]:
            continue

        # Failed break above London high
        key = (day, -1)
        if key not in used and bias[i] <= 0:
            broke = h[i - 1] > lh and c[i - 1] > lh
            failed = c[i] < lh and c[i] < o[i]
            # also allow same-bar sweep & fail
            same = h[i] > lh and c[i] < lh and c[i] < o[i]
            if (broke and failed) or same:
                entry = float(lh)
                stop = float(max(h[i - 1], h[i]) + 0.15 * atr_v[i])
                if params.min_stop_atr * atr_v[i] <= abs(entry - stop) <= params.max_stop_atr * atr_v[i]:
                    sig = pack_signal(idx[i], pair, -1, entry, stop, RR, "ny_london_turtle_short")
                    if sig:
                        signals.append(sig)
                        used.add(key)

        key = (day, 1)
        if key not in used and bias[i] >= 0:
            broke = l[i - 1] < ll and c[i - 1] < ll
            failed = c[i] > ll and c[i] > o[i]
            same = l[i] < ll and c[i] > ll and c[i] > o[i]
            if (broke and failed) or same:
                entry = float(ll)
                stop = float(min(l[i - 1], l[i]) - 0.15 * atr_v[i])
                if params.min_stop_atr * atr_v[i] <= abs(entry - stop) <= params.max_stop_atr * atr_v[i]:
                    sig = pack_signal(idx[i], pair, 1, entry, stop, RR, "ny_london_turtle_long")
                    if sig:
                        signals.append(sig)
                        used.add(key)
    return signals
