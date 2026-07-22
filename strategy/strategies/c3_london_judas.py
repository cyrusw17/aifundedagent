"""C3 — Causal London Judas: fade early London sweep of Asia after close.

London hours only. Sweep Asia extreme and close back inside → marketable fade.
"""

from __future__ import annotations

from typing import List, Set, Tuple

import numpy as np

from ..common import atr, h1_bias_series, pack_signal, session_ranges_complete
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
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        hour = idx[i].hour
        if hour < 7 or hour >= 12:  # London window only
            continue
        day = idx[i].normalize()
        if day not in sessions or "asia" not in sessions[day]:
            continue
        ah, al, ar = sessions[day]["asia"]
        if ar < 0.4 * atr_v[i]:
            continue

        key = (day, -1)
        if key not in used and bias[i] <= 0 and h[i] > ah and c[i] < ah and c[i] < o[i]:
            entry = float(c[i])
            stop = float(h[i] + 0.12 * atr_v[i])
            if stop - entry < params.min_stop_atr * atr_v[i]:
                stop = entry + params.min_stop_atr * atr_v[i]
            if stop - entry <= params.max_stop_atr * atr_v[i]:
                sig = pack_signal(idx[i], pair, -1, entry, stop, RR, "c3_judas_short", True)
                if sig:
                    signals.append(sig)
                    used.add(key)

        key = (day, 1)
        if key not in used and bias[i] >= 0 and l[i] < al and c[i] > al and c[i] > o[i]:
            entry = float(c[i])
            stop = float(l[i] - 0.12 * atr_v[i])
            if entry - stop < params.min_stop_atr * atr_v[i]:
                stop = entry - params.min_stop_atr * atr_v[i]
            if entry - stop <= params.max_stop_atr * atr_v[i]:
                sig = pack_signal(idx[i], pair, 1, entry, stop, RR, "c3_judas_long", True)
                if sig:
                    signals.append(sig)
                    used.add(key)
    return signals
