"""Simple moving-average crossover strategy."""

from __future__ import annotations

import numpy as np
import pandas as pd

from mcpt.metrics import profit_factor


def ma_crossover(ohlc: pd.DataFrame, fast: int, slow: int) -> pd.Series:
    """Long when fast MA > slow MA, else flat (0)."""
    if fast >= slow:
        raise ValueError("fast period must be < slow period")
    fast_ma = ohlc["close"].rolling(fast).mean()
    slow_ma = ohlc["close"].rolling(slow).mean()
    return pd.Series(np.where(fast_ma > slow_ma, 1, 0), index=ohlc.index, dtype=float)


def optimize_ma_crossover(
    ohlc: pd.DataFrame,
    fast_range: range | None = None,
    slow_range: range | None = None,
) -> tuple[tuple[int, int], float]:
    """Grid-search (fast, slow) maximizing profit factor."""
    if fast_range is None:
        fast_range = range(5, 31, 5)
    if slow_range is None:
        slow_range = range(20, 101, 10)

    best_pf = 0.0
    best_params = (-1, -1)
    r = np.log(ohlc["close"]).diff().shift(-1)

    for fast in fast_range:
        for slow in slow_range:
            if fast >= slow:
                continue
            signal = ma_crossover(ohlc, fast, slow)
            sig_pf = profit_factor(signal * r)
            if np.isnan(sig_pf):
                continue
            if sig_pf > best_pf:
                best_pf = sig_pf
                best_params = (fast, slow)

    return best_params, float(best_pf)
