"""C4 — Causal displacement continuation.

Closed M15 closes beyond the prior 4-bar extreme by ≥0.25 ATR (displacement)
in H1 bias direction during killzone → marketable continuation.
"""

from __future__ import annotations

from typing import List, Set, Tuple

import numpy as np

from ..common import atr, confirmed_swings, h1_bias_series, in_killzone, pack_signal
from ..config import PARAMS, StrategyParams

RR = 1.6


def generate_signals(pair: str, m15, params: StrategyParams = PARAMS) -> List:
    if len(m15) < params.atr_period + 40:
        return []
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    signals, used = [], set()

    for i in range(5, len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or not in_killzone(idx[i], params):
            continue
        day = idx[i].normalize()
        prior_hi = float(np.max(h[i - 4 : i]))
        prior_lo = float(np.min(l[i - 4 : i]))
        body = abs(c[i] - o[i])
        if body < 0.35 * atr_v[i]:
            continue

        key = (day, 1)
        if (
            key not in used
            and bias[i] > 0
            and c[i] > prior_hi + 0.25 * atr_v[i]
            and c[i] > o[i]
        ):
            entry = float(c[i])
            stop = float(min(l[i], entry - params.min_stop_atr * atr_v[i]))
            if entry - stop < params.min_stop_atr * atr_v[i] * 0.5:
                stop = entry - params.min_stop_atr * atr_v[i] * 0.5
            if entry - stop <= params.max_stop_atr * atr_v[i]:
                sig = pack_signal(idx[i], pair, 1, entry, stop, RR, "c4_disp_long", True)
                if sig:
                    signals.append(sig)
                    used.add(key)

        key = (day, -1)
        if (
            key not in used
            and bias[i] < 0
            and c[i] < prior_lo - 0.25 * atr_v[i]
            and c[i] < o[i]
        ):
            entry = float(c[i])
            stop = float(max(h[i], entry + params.min_stop_atr * atr_v[i]))
            if stop - entry < params.min_stop_atr * atr_v[i] * 0.5:
                stop = entry + params.min_stop_atr * atr_v[i] * 0.5
            if stop - entry <= params.max_stop_atr * atr_v[i]:
                sig = pack_signal(idx[i], pair, -1, entry, stop, RR, "c4_disp_short", True)
                if sig:
                    signals.append(sig)
                    used.add(key)
    return signals
