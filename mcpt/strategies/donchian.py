"""Donchian channel breakout strategy."""

from __future__ import annotations

import numpy as np
import pandas as pd

from mcpt.metrics import profit_factor


def donchian_breakout(ohlc: pd.DataFrame, lookback: int) -> pd.Series:
    """Position signal: +1 long breakout, -1 short breakout, ffilled."""
    upper = ohlc["close"].rolling(lookback - 1).max().shift(1)
    lower = ohlc["close"].rolling(lookback - 1).min().shift(1)
    signal = pd.Series(np.full(len(ohlc), np.nan), index=ohlc.index)
    signal.loc[ohlc["close"] > upper] = 1
    signal.loc[ohlc["close"] < lower] = -1
    return signal.ffill()


def optimize_donchian(
    ohlc: pd.DataFrame,
    lookback_min: int = 12,
    lookback_max: int = 169,
) -> tuple[int, float]:
    """Grid-search lookback maximizing profit factor."""
    best_pf = 0.0
    best_lookback = -1
    r = np.log(ohlc["close"]).diff().shift(-1)

    for lookback in range(lookback_min, lookback_max):
        signal = donchian_breakout(ohlc, lookback)
        sig_rets = signal * r
        sig_pf = profit_factor(sig_rets)
        if np.isnan(sig_pf):
            continue
        if sig_pf > best_pf:
            best_pf = sig_pf
            best_lookback = lookback

    return best_lookback, float(best_pf)


def walkforward_donchian(
    ohlc: pd.DataFrame,
    train_lookback: int = 24 * 365 * 4,
    train_step: int = 24 * 30,
    lookback_min: int = 12,
    lookback_max: int = 169,
) -> pd.Series:
    """Rolling optimization: re-fit lookback every ``train_step`` bars."""
    n = len(ohlc)
    wf_signal = np.full(n, np.nan)
    tmp_signal: pd.Series | None = None
    next_train = train_lookback

    for i in range(next_train, n):
        if i == next_train:
            best_lookback, _ = optimize_donchian(
                ohlc.iloc[i - train_lookback : i],
                lookback_min=lookback_min,
                lookback_max=lookback_max,
            )
            tmp_signal = donchian_breakout(ohlc, best_lookback)
            next_train += train_step
        if tmp_signal is not None:
            wf_signal[i] = tmp_signal.iloc[i]

    return pd.Series(wf_signal, index=ohlc.index)

