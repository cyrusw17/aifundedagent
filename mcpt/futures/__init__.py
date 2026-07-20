"""Futures research under The5ers-style funded account rules.

Reuses forex SMC signal engine on futures OHLC; PnL via R-multiples × $ risk
(point value cancels). Data: Yahoo continuous futures H1 (~2024+) and D1 (longer).
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "futures"

# Liquid set for The5ers-style multi-market book
INDEX4 = ["ES", "NQ", "YM", "RTY"]
INDEX_COMM = ["ES", "NQ", "YM", "CL", "GC"]
ALL6 = ["ES", "NQ", "YM", "RTY", "CL", "GC"]


def load_futures(
    symbols: list[str],
    start: str,
    end: str,
    timeframe: str = "1h",
) -> dict[str, pd.DataFrame]:
    """Load parquet futures OHLC clipped to [start, end]."""
    s, e = pd.Timestamp(start), pd.Timestamp(end)
    book: dict[str, pd.DataFrame] = {}
    for sym in symbols:
        path = DATA / f"{sym}_{timeframe}.parquet"
        if not path.exists():
            continue
        df = pd.read_parquet(path)
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        cols = [c for c in ["open", "high", "low", "close"] if c in df.columns]
        df = df[cols].astype(float)
        df = df[(df.index >= s) & (df.index <= e)]
        df = df[~df.index.duplicated(keep="last")].sort_index()
        if len(df) >= 200:
            book[sym] = df
    return book
