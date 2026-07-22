"""S3 — Turtle Soup: fade failed break of PDH/PDL or Asia extremes."""

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
    prior_day_hl,
    session_ranges_complete,
)
from ..config import PARAMS, StrategyParams

RR = 1.5


def generate_signals(
    pair: str, m15: pd.DataFrame, params: StrategyParams = PARAMS
) -> List[Signal]:
    if len(m15) < params.atr_period + 50:
        return []
    atr_v = atr(m15, params.atr_period).to_numpy()
    o = m15["open"].to_numpy()
    h = m15["high"].to_numpy()
    l = m15["low"].to_numpy()
    c = m15["close"].to_numpy()
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sessions = session_ranges_complete(idx, h, l)
    pdhl = prior_day_hl(idx, h, l)

    signals: List[Signal] = []
    used: Set[Tuple] = set()

    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        if not in_killzone(idx[i], params):
            continue
        day = idx[i].normalize()
        levels_hi = []
        levels_lo = []
        if day in pdhl:
            levels_hi.append(("pdh", pdhl[day][0]))
            levels_lo.append(("pdl", pdhl[day][1]))
        if day in sessions and "asia" in sessions[day] and idx[i].hour >= 7:
            levels_hi.append(("asia_high", sessions[day]["asia"][0]))
            levels_lo.append(("asia_low", sessions[day]["asia"][1]))

        # Failed upside break: prior bar broke above, this bar closes back below
        for name, lvl in levels_hi:
            key = (day, name, -1)
            if key in used or bias[i] > 0:
                continue
            broke = h[i - 1] > lvl and c[i - 1] > lvl
            failed = c[i] < lvl and c[i] < o[i]
            if not (broke and failed):
                continue
            entry = float(lvl)
            stop = float(max(h[i - 1], h[i]) + 0.15 * atr_v[i])
            if abs(entry - stop) < params.min_stop_atr * atr_v[i]:
                stop = entry + params.min_stop_atr * atr_v[i]
            if abs(entry - stop) > params.max_stop_atr * atr_v[i]:
                continue
            sig = pack_signal(idx[i], pair, -1, entry, stop, RR, f"turtle_soup_{name}")
            if sig:
                signals.append(sig)
                used.add(key)
            break

        for name, lvl in levels_lo:
            key = (day, name, 1)
            if key in used or bias[i] < 0:
                continue
            broke = l[i - 1] < lvl and c[i - 1] < lvl
            failed = c[i] > lvl and c[i] > o[i]
            if not (broke and failed):
                continue
            entry = float(lvl)
            stop = float(min(l[i - 1], l[i]) - 0.15 * atr_v[i])
            if abs(entry - stop) < params.min_stop_atr * atr_v[i]:
                stop = entry - params.min_stop_atr * atr_v[i]
            if abs(entry - stop) > params.max_stop_atr * atr_v[i]:
                continue
            sig = pack_signal(idx[i], pair, 1, entry, stop, RR, f"turtle_soup_{name}")
            if sig:
                signals.append(sig)
                used.add(key)
            break
    return signals
