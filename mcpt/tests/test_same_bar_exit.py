"""Same-bar stop/TP realism after entry fill."""

from __future__ import annotations

import numpy as np
import pandas as pd

from mcpt.forex.fast_sim import fast_backtest


def test_fast_sim_same_bar_stop_reduces_equity() -> None:
    idx = pd.date_range("2020-01-01", periods=6, freq="h")
    # Signal on bar0 → enter bar1 open; bar1 low crashes through any ATR stop.
    df = pd.DataFrame(
        {
            "open": [1.1000, 1.1000, 1.0950, 1.0960, 1.0970, 1.0980],
            "high": [1.1010, 1.1005, 1.0960, 1.0970, 1.0980, 1.0990],
            "low": [1.0990, 1.0900, 1.0940, 1.0950, 1.0960, 1.0970],
            "close": [1.1005, 1.0910, 1.0955, 1.0965, 1.0975, 1.0985],
            "volume": [100] * 6,
        },
        index=idx,
    )
    prepared = {
        "EURUSD": {
            "open": df["open"].to_numpy(float),
            "high": df["high"].to_numpy(float),
            "low": df["low"].to_numpy(float),
            "close": df["close"].to_numpy(float),
            "atr": np.array([0.002, 0.002, 0.002, 0.002, 0.002, 0.002], dtype=float),
            "sig": np.array([1, 0, 0, 0, 0, 0], dtype=int),
            "times": df.index.to_numpy(),
            "index": df.index,
        }
    }
    # Build meta timeline manually (prepare_book path)
    from mcpt.forex.fast_sim import prepare_book

    # Use prepare_book with a mode that may not emit our signal — inject after
    book = {"EURUSD": df}
    prep = prepare_book(book, mode="smc", swing=2, min_conf=1)
    prep["EURUSD"]["sig"] = np.array([1, 0, 0, 0, 0, 0], dtype=int)
    prep["EURUSD"]["atr"] = np.array([0.002] * 6, dtype=float)
    # Rebuild entry_times meta for injected signal
    pairs = prep["__meta__"]["pairs"]
    time_map = prep["__meta__"]["time_map"]
    entry_times = set()
    for pi, p in enumerate(pairs):
        times = prep[p]["times"]
        sig = prep[p]["sig"]
        for bi, t in enumerate(times):
            if bi > 0 and sig[bi - 1] != 0:
                entry_times.add(t)
    timeline = prep["__meta__"]["timeline"]
    next_entry_from = {}
    nxt = None
    for t in reversed(timeline):
        if t in entry_times:
            nxt = t
        next_entry_from[t] = nxt
    prep["__meta__"]["next_entry_from"] = next_entry_from

    res = fast_backtest(
        prep,
        risk_pct=0.01,
        rr=2.0,
        atr_stop_mult=0.5,
        max_positions=1,
        one_entry_per_day=False,
        skip_mondays=False,
        cooldown_losses=0,
        weekly_withdraw=False,
    )
    assert res.n_trades >= 1
    # Stop-out on entry bar should reduce equity vs starting 100k
    assert res.final_balance < 100_000.0
