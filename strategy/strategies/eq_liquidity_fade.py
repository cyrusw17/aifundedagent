"""S6 — Equal highs/lows liquidity engineering fade (ICT inducement).

If two swing highs (or lows) print within 0.15 ATR (equals), wait for a sweep
beyond them that closes back inside during a killzone, then enter fade.
"""

from __future__ import annotations

from typing import Dict, List, Set, Tuple

import numpy as np
import pandas as pd

from ..common import (
    Signal,
    atr,
    confirmed_swings,
    h1_bias_series,
    in_killzone,
    pack_signal,
)
from ..config import PARAMS, StrategyParams

RR = 1.5


def generate_signals(
    pair: str, m15: pd.DataFrame, params: StrategyParams = PARAMS
) -> List[Signal]:
    if len(m15) < params.atr_period + 80:
        return []
    atr_v = atr(m15, params.atr_period).to_numpy()
    o = m15["open"].to_numpy()
    h = m15["high"].to_numpy()
    l = m15["low"].to_numpy()
    c = m15["close"].to_numpy()
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()

    sh, sl = confirmed_swings(h, l, params.swing_left, params.swing_right)
    sh_conf: Dict[int, list] = {}
    sl_conf: Dict[int, list] = {}
    for p, price in sh:
        sh_conf.setdefault(p + params.swing_right, []).append((p, price))
    for p, price in sl:
        sl_conf.setdefault(p + params.swing_right, []).append((p, price))
    known_sh, known_sl = [], []
    signals: List[Signal] = []
    used: Set[Tuple] = set()

    for i in range(len(m15)):
        if i in sh_conf:
            known_sh.extend(sh_conf[i])
        if i in sl_conf:
            known_sl.extend(sl_conf[i])
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        if not in_killzone(idx[i], params):
            continue
        day = idx[i].normalize()
        tol = 0.15 * atr_v[i]

        # Equal highs among last 6 confirmed swings before i
        highs = [(p, px) for p, px in known_sh if p < i][-6:]
        lows = [(p, px) for p, px in known_sl if p < i][-6:]

        eq_high = None
        for a in range(len(highs)):
            for b in range(a + 1, len(highs)):
                if abs(highs[a][1] - highs[b][1]) <= tol:
                    eq_high = max(highs[a][1], highs[b][1])
        eq_low = None
        for a in range(len(lows)):
            for b in range(a + 1, len(lows)):
                if abs(lows[a][1] - lows[b][1]) <= tol:
                    eq_low = min(lows[a][1], lows[b][1])

        if eq_high is not None and bias[i] <= 0:
            key = (day, "eqh", -1)
            if key not in used and h[i] > eq_high and c[i] < eq_high and c[i] < o[i]:
                entry = float(eq_high)
                stop = float(h[i] + 0.15 * atr_v[i])
                if abs(entry - stop) < params.min_stop_atr * atr_v[i]:
                    stop = entry + params.min_stop_atr * atr_v[i]
                if abs(entry - stop) <= params.max_stop_atr * atr_v[i]:
                    sig = pack_signal(idx[i], pair, -1, entry, stop, RR, "eqh_sweep_fade")
                    if sig:
                        signals.append(sig)
                        used.add(key)

        if eq_low is not None and bias[i] >= 0:
            key = (day, "eql", 1)
            if key not in used and l[i] < eq_low and c[i] > eq_low and c[i] > o[i]:
                entry = float(eq_low)
                stop = float(l[i] - 0.15 * atr_v[i])
                if abs(entry - stop) < params.min_stop_atr * atr_v[i]:
                    stop = entry - params.min_stop_atr * atr_v[i]
                if abs(entry - stop) <= params.max_stop_atr * atr_v[i]:
                    sig = pack_signal(idx[i], pair, 1, entry, stop, RR, "eql_sweep_fade")
                    if sig:
                        signals.append(sig)
                        used.add(key)
    return signals
