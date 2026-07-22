"""C2 — Causal liquidity rejection (Turtle-style), marketable after close.

Failed break of PDH/PDL/Asia: prior bar breaks level, this bar closes back
through with a rejecting body. Enter marketable at knowable_at (not limit
during the failure bar — that was look-ahead).
"""

from __future__ import annotations

from typing import List, Set, Tuple

import numpy as np

from ..common import (
    atr,
    h1_bias_series,
    in_killzone,
    pack_signal,
    prior_day_hl,
    session_ranges_complete,
)
from ..config import PARAMS, StrategyParams

RR = 1.5


def generate_signals(pair: str, m15, params: StrategyParams = PARAMS) -> List:
    if len(m15) < params.atr_period + 50:
        return []
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sessions = session_ranges_complete(idx, h, l)
    pdhl = prior_day_hl(idx, h, l)
    signals, used = [], set()

    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or not in_killzone(idx[i], params):
            continue
        day = idx[i].normalize()
        highs, lows = [], []
        if day in pdhl:
            highs.append(("pdh", pdhl[day][0]))
            lows.append(("pdl", pdhl[day][1]))
        if day in sessions and "asia" in sessions[day] and idx[i].hour >= 7:
            highs.append(("asia_h", sessions[day]["asia"][0]))
            lows.append(("asia_l", sessions[day]["asia"][1]))

        for name, lvl in highs:
            key = (day, name, -1)
            if key in used or bias[i] > 0:
                continue
            # Sweep + reject fully known on this closed bar
            if not (h[i] > lvl and c[i] < lvl and c[i] < o[i]):
                continue
            if h[i] - lvl < 0.05 * atr_v[i]:
                continue
            entry = float(c[i])  # rejection close → next open
            stop = float(h[i] + 0.15 * atr_v[i])
            if stop - entry < params.min_stop_atr * atr_v[i]:
                stop = entry + params.min_stop_atr * atr_v[i]
            if stop - entry > params.max_stop_atr * atr_v[i]:
                continue
            sig = pack_signal(idx[i], pair, -1, entry, stop, RR, f"c2_reject_{name}", True)
            if sig:
                signals.append(sig)
                used.add(key)
            break

        for name, lvl in lows:
            key = (day, name, 1)
            if key in used or bias[i] < 0:
                continue
            if not (l[i] < lvl and c[i] > lvl and c[i] > o[i]):
                continue
            if lvl - l[i] < 0.05 * atr_v[i]:
                continue
            entry = float(c[i])
            stop = float(l[i] - 0.15 * atr_v[i])
            if entry - stop < params.min_stop_atr * atr_v[i]:
                stop = entry - params.min_stop_atr * atr_v[i]
            if entry - stop > params.max_stop_atr * atr_v[i]:
                continue
            sig = pack_signal(idx[i], pair, 1, entry, stop, RR, f"c2_reject_{name}", True)
            if sig:
                signals.append(sig)
                used.add(key)
            break
    return signals
