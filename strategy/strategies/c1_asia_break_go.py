"""C1 — Causal Asia break-and-go (momentum).

Signal on closed M15 that closes through Asia high/low with body.
Fill: marketable at next M1 open after bar close (knowable_at).
"""

from __future__ import annotations

from typing import List, Set, Tuple

import numpy as np

from ..common import atr, h1_bias_series, in_killzone, pack_signal, session_ranges_complete
from ..config import PARAMS, StrategyParams

RR = 1.5


def generate_signals(pair: str, m15, params: StrategyParams = PARAMS) -> List:
    if len(m15) < params.atr_period + 40:
        return []
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sessions = session_ranges_complete(idx, h, l)
    signals, used = [], set()

    for i in range(len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or not in_killzone(idx[i], params):
            continue
        day = idx[i].normalize()
        if day not in sessions or "asia" not in sessions[day] or idx[i].hour < 7:
            continue
        ah, al, ar = sessions[day]["asia"]
        if ar < 0.5 * atr_v[i] or ar > 4.0 * atr_v[i]:
            continue
        if abs(c[i] - o[i]) < 0.30 * atr_v[i]:
            continue

        if (day, 1) not in used and bias[i] >= 0 and c[i] > ah and c[i] > o[i]:
            entry = float(c[i])
            stop = float(min(entry - params.min_stop_atr * atr_v[i], max(al, l[i] - 0.1 * atr_v[i])))
            if entry - stop < params.min_stop_atr * atr_v[i] * 0.5:
                stop = entry - params.min_stop_atr * atr_v[i] * 0.5
            if entry - stop <= params.max_stop_atr * atr_v[i]:
                sig = pack_signal(idx[i], pair, 1, entry, stop, RR, "c1_asia_go_long", True)
                if sig:
                    signals.append(sig)
                    used.add((day, 1))

        if (day, -1) not in used and bias[i] <= 0 and c[i] < al and c[i] < o[i]:
            entry = float(c[i])
            stop = float(max(entry + params.min_stop_atr * atr_v[i], min(ah, h[i] + 0.1 * atr_v[i])))
            if stop - entry < params.min_stop_atr * atr_v[i] * 0.5:
                stop = entry + params.min_stop_atr * atr_v[i] * 0.5
            if stop - entry <= params.max_stop_atr * atr_v[i]:
                sig = pack_signal(idx[i], pair, -1, entry, stop, RR, "c1_asia_go_short", True)
                if sig:
                    signals.append(sig)
                    used.add((day, -1))
    return signals
