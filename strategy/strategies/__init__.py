"""Strategy registry — each generator is causal (no look-ahead)."""

from __future__ import annotations

from typing import Callable, Dict, List

import pandas as pd

from ..common import Signal
from ..config import StrategyParams
from . import (
    eq_liquidity_fade,
    judas_reversal,
    ote_pullback,
    session_break_retest,
    silver_bullet_fvg,
    turtle_soup,
)

SignalFn = Callable[[str, pd.DataFrame, StrategyParams], List[Signal]]

STRATEGIES: Dict[str, SignalFn] = {
    "S1_session_break_retest": session_break_retest.generate_signals,
    "S2_ny_london_turtle": judas_reversal.generate_signals,
    "S3_turtle_soup": turtle_soup.generate_signals,
    "S4_asia_break_go": silver_bullet_fvg.generate_signals,
    "S5_dual_liquidity_book": ote_pullback.generate_signals,
    "S6_eq_liquidity_fade": eq_liquidity_fade.generate_signals,
}

STRATEGY_DESC = {
    "S1_session_break_retest": "Asia/London range break + retest (Power of 3)",
    "S2_ny_london_turtle": "NY fade of failed London high/low breaks",
    "S3_turtle_soup": "Failed PDH/PDL or Asia break fade",
    "S4_asia_break_go": "Asia range break-and-go (momentum, no retest)",
    "S5_dual_liquidity_book": "Combined Turtle Soup + Equal H/L fade book",
    "S6_eq_liquidity_fade": "Equal highs/lows sweep fade",
}
