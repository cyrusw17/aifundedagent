"""Causal strategy registry — 5 KB search winners (no look-ahead fills)."""

from __future__ import annotations

from typing import Callable, Dict, List

import pandas as pd

from ..common import Signal
from ..config import StrategyParams
from .winners import STRATEGIES, STRATEGY_DESC, WINNER_CFGS

# Re-export
__all__ = ["STRATEGIES", "STRATEGY_DESC", "WINNER_CFGS", "SignalFn"]

SignalFn = Callable[[str, pd.DataFrame, StrategyParams], List[Signal]]
