"""S1 — Asia/London session break & retest (proven baseline)."""

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

    signals: List[Signal] = []
    state = None
    signaled: Set[Tuple] = set()

    for i in range(len(m15)):
        day = idx[i].normalize()
        if day not in sessions or np.isnan(atr_v[i]) or atr_v[i] <= 0:
            state = None
            continue
        if not in_killzone(idx[i], params):
            continue
        if state is not None and (state["day"] != day or i - state["break_i"] > 12):
            state = None

        hour = idx[i].hour
        candidates = []
        if "asia" in sessions[day] and hour >= 7:
            candidates.append(("asia", sessions[day]["asia"]))
        # London range only after London session completes (no look-ahead)
        if hour >= 12 and "london" in sessions[day]:
            candidates.append(("london", sessions[day]["london"]))

        if state is None:
            for name, (rh, rl, rrng) in candidates:
                if rrng < 0.6 * atr_v[i] or rrng > 4.0 * atr_v[i]:
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
                            "range": rrng,
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
                            "range": rrng,
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
            stop = float(min(l[i], state["extreme"], edge) - 0.15 * atr_v[i])
            risk = entry - stop
            if risk < params.min_stop_atr * atr_v[i]:
                stop = entry - params.min_stop_atr * atr_v[i]
            if abs(entry - stop) > params.max_stop_atr * atr_v[i]:
                state = None
                continue
            sig = pack_signal(
                idx[i], pair, 1, entry, stop, RR, f"{state['sess']}_break_retest_long"
            )
            if sig:
                signals.append(sig)
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
            stop = float(max(h[i], state["extreme"], edge) + 0.15 * atr_v[i])
            if abs(entry - stop) < params.min_stop_atr * atr_v[i]:
                stop = entry + params.min_stop_atr * atr_v[i]
            if abs(entry - stop) > params.max_stop_atr * atr_v[i]:
                state = None
                continue
            sig = pack_signal(
                idx[i], pair, -1, entry, stop, RR, f"{state['sess']}_break_retest_short"
            )
            if sig:
                signals.append(sig)
                signaled.add((day, state["sess"], -1))
            state = None
    return signals
