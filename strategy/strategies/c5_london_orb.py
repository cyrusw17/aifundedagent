"""C5 — Causal London ORB (opening range break).

Opening range = 07:00–07:45 UTC (first 4 M15 bars). Known only at/after 08:00.
Break with close beyond OR → marketable. One trade per day per side.
"""

from __future__ import annotations

from typing import Dict, List, Set, Tuple

import numpy as np
import pandas as pd

from ..common import atr, h1_bias_series, pack_signal
from ..config import PARAMS, StrategyParams

RR = 1.5


def _opening_ranges(idx, h, l) -> Dict[pd.Timestamp, Tuple[float, float]]:
    df = pd.DataFrame({"high": h, "low": l}, index=idx)
    out = {}
    for day, chunk in df.groupby(df.index.normalize()):
        orb = chunk.between_time("07:00", "07:45")
        if len(orb) < 3:
            continue
        hi, lo = float(orb["high"].max()), float(orb["low"].min())
        if hi > lo:
            out[day] = (hi, lo)
    return out


def generate_signals(pair: str, m15, params: StrategyParams = PARAMS) -> List:
    if len(m15) < params.atr_period + 40:
        return []
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    orbs = _opening_ranges(idx, h, l)
    signals, used = [], set()

    for i in range(len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        hour = idx[i].hour
        # OR complete only from 08:00; trade until 16:00
        if hour < 8 or hour >= 16:
            continue
        day = idx[i].normalize()
        if day not in orbs:
            continue
        orh, orl = orbs[day]
        width = orh - orl
        if width < 0.35 * atr_v[i] or width > 3.0 * atr_v[i]:
            continue
        if abs(c[i] - o[i]) < 0.25 * atr_v[i]:
            continue

        key = (day, 1)
        if key not in used and bias[i] >= 0 and c[i] > orh and c[i] > o[i]:
            entry = float(c[i])
            stop = float(max(orl, entry - params.max_stop_atr * atr_v[i]))
            if entry - stop < params.min_stop_atr * atr_v[i] * 0.5:
                stop = entry - params.min_stop_atr * atr_v[i] * 0.5
            if entry - stop <= params.max_stop_atr * atr_v[i]:
                sig = pack_signal(idx[i], pair, 1, entry, stop, RR, "c5_orb_long", True)
                if sig:
                    signals.append(sig)
                    used.add(key)

        key = (day, -1)
        if key not in used and bias[i] <= 0 and c[i] < orl and c[i] < o[i]:
            entry = float(c[i])
            stop = float(min(orh, entry + params.max_stop_atr * atr_v[i]))
            if stop - entry < params.min_stop_atr * atr_v[i] * 0.5:
                stop = entry + params.min_stop_atr * atr_v[i] * 0.5
            if stop - entry <= params.max_stop_atr * atr_v[i]:
                sig = pack_signal(idx[i], pair, -1, entry, stop, RR, "c5_orb_short", True)
                if sig:
                    signals.append(sig)
                    used.add(key)
    return signals
