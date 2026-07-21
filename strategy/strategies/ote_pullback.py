"""S5 — Dual liquidity book: merge Turtle Soup + Equal H/L fade signals.

Confluence-style portfolio of the two strongest ICT liquidity fades.
Deduplicates same pair/side within 4 M15 bars.
"""

from __future__ import annotations

from typing import List

import pandas as pd

from ..common import Signal
from ..config import PARAMS, StrategyParams
from .eq_liquidity_fade import generate_signals as gen_eq
from .turtle_soup import generate_signals as gen_turtle


def generate_signals(
    pair: str, m15: pd.DataFrame, params: StrategyParams = PARAMS
) -> List[Signal]:
    a = gen_turtle(pair, m15, params)
    b = gen_eq(pair, m15, params)
    merged = sorted(a + b, key=lambda s: s.time)
    out: List[Signal] = []
    last_t = None
    last_side = 0
    for s in merged:
        s = Signal(
            time=s.time,
            pair=s.pair,
            side=s.side,
            entry=s.entry,
            stop=s.stop,
            take=s.take,
            sweep_extreme=s.sweep_extreme,
            reason="dual_" + s.reason,
            reward_risk=s.reward_risk,
        )
        if last_t is not None and s.side == last_side:
            if (s.time - last_t).total_seconds() < 4 * 15 * 60:
                continue
        out.append(s)
        last_t = s.time
        last_side = s.side
    return out
