"""OHLC bar permutation that preserves return distribution statistics.

Adapted from neurotrader888/mcpt (MIT License).
Shuffles relative intrabar moves and gaps so legitimate temporal patterns
are destroyed while mean/std/skew/kurtosis stay nearly identical.
"""

from __future__ import annotations

from typing import List, Union

import numpy as np
import pandas as pd


def get_permutation(
    ohlc: Union[pd.DataFrame, List[pd.DataFrame]],
    start_index: int = 0,
    seed: int | None = None,
) -> Union[pd.DataFrame, List[pd.DataFrame]]:
    """Permute OHLC bars from ``start_index`` onward.

    Parameters
    ----------
    ohlc:
        Single OHLC DataFrame or list of aligned DataFrames (multi-market).
        Columns required: open, high, low, close.
    start_index:
        Bars before this index are left unchanged (used for walk-forward MCPT
        so the first training fold stays real).
    seed:
        Optional RNG seed for reproducibility.
    """
    if start_index < 0:
        raise ValueError("start_index must be >= 0")

    rng = np.random.default_rng(seed)

    if isinstance(ohlc, list):
        time_index = ohlc[0].index
        for mkt in ohlc:
            if not np.all(time_index == mkt.index):
                raise ValueError("Indexes do not match across markets")
        n_markets = len(ohlc)
        markets = ohlc
    else:
        n_markets = 1
        time_index = ohlc.index
        markets = [ohlc]

    n_bars = len(markets[0])
    perm_index = start_index + 1
    perm_n = n_bars - perm_index
    if perm_n <= 0:
        raise ValueError("Not enough bars after start_index to permute")

    start_bar = np.empty((n_markets, 4))
    relative_open = np.empty((n_markets, perm_n))
    relative_high = np.empty((n_markets, perm_n))
    relative_low = np.empty((n_markets, perm_n))
    relative_close = np.empty((n_markets, perm_n))

    for mkt_i, reg_bars in enumerate(markets):
        log_bars = np.log(reg_bars[["open", "high", "low", "close"]])
        start_bar[mkt_i] = log_bars.iloc[start_index].to_numpy()

        r_o = (log_bars["open"] - log_bars["close"].shift()).to_numpy()
        r_h = (log_bars["high"] - log_bars["open"]).to_numpy()
        r_l = (log_bars["low"] - log_bars["open"]).to_numpy()
        r_c = (log_bars["close"] - log_bars["open"]).to_numpy()

        relative_open[mkt_i] = r_o[perm_index:]
        relative_high[mkt_i] = r_h[perm_index:]
        relative_low[mkt_i] = r_l[perm_index:]
        relative_close[mkt_i] = r_c[perm_index:]

    idx = np.arange(perm_n)

    # Shuffle intrabar relative values (high/low/close) together
    perm1 = rng.permutation(idx)
    relative_high = relative_high[:, perm1]
    relative_low = relative_low[:, perm1]
    relative_close = relative_close[:, perm1]

    # Shuffle gaps (prior close → open) separately
    perm2 = rng.permutation(idx)
    relative_open = relative_open[:, perm2]

    perm_ohlc: list[pd.DataFrame] = []
    for mkt_i, reg_bars in enumerate(markets):
        perm_bars = np.zeros((n_bars, 4))
        log_bars = np.log(reg_bars[["open", "high", "low", "close"]]).to_numpy().copy()
        perm_bars[:start_index] = log_bars[:start_index]
        perm_bars[start_index] = start_bar[mkt_i]

        for i in range(perm_index, n_bars):
            k = i - perm_index
            perm_bars[i, 0] = perm_bars[i - 1, 3] + relative_open[mkt_i][k]
            perm_bars[i, 1] = perm_bars[i, 0] + relative_high[mkt_i][k]
            perm_bars[i, 2] = perm_bars[i, 0] + relative_low[mkt_i][k]
            perm_bars[i, 3] = perm_bars[i, 0] + relative_close[mkt_i][k]

        out = pd.DataFrame(
            np.exp(perm_bars),
            index=time_index,
            columns=["open", "high", "low", "close"],
        )
        perm_ohlc.append(out)

    return perm_ohlc if n_markets > 1 else perm_ohlc[0]
