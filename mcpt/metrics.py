"""Objective functions computed from bar-level strategy returns."""

from __future__ import annotations

import numpy as np
import pandas as pd


def strategy_returns(signal: pd.Series, close: pd.Series) -> pd.Series:
    """Bar-level strategy returns: position × next-bar log return."""
    r = np.log(close).diff().shift(-1)
    return signal * r


def profit_factor(returns: pd.Series | np.ndarray) -> float:
    """Gross profits / gross losses. Returns NaN if no losses."""
    r = pd.Series(returns).dropna()
    gains = r[r > 0].sum()
    losses = r[r < 0].abs().sum()
    if losses == 0:
        return float("inf") if gains > 0 else float("nan")
    return float(gains / losses)


def sharpe_ratio(returns: pd.Series | np.ndarray) -> float:
    """Simple (non-annualized) Sharpe of bar returns."""
    r = pd.Series(returns).dropna()
    std = r.std()
    if std == 0 or np.isnan(std):
        return float("nan")
    return float(r.mean() / std)


def cumulative_log_returns(returns: pd.Series) -> pd.Series:
    return returns.fillna(0).cumsum()
