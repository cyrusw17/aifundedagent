"""Market data loading and synthetic sample generation."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

DATA_DIR = Path(__file__).resolve().parent.parent / "data"


def _normalize_ohlc(df: pd.DataFrame) -> pd.DataFrame:
    cols = {c.lower(): c for c in df.columns}
    mapping = {}
    for need in ("open", "high", "low", "close"):
        if need in cols:
            mapping[cols[need]] = need
        elif need.capitalize() in df.columns:
            mapping[need.capitalize()] = need
        else:
            raise ValueError(f"Missing required column: {need}")
    out = df.rename(columns=mapping)[["open", "high", "low", "close"]].astype(float)
    out = out.replace([np.inf, -np.inf], np.nan).dropna()
    out = out[(out > 0).all(axis=1)]
    if not isinstance(out.index, pd.DatetimeIndex):
        out.index = pd.to_datetime(out.index, utc=True, errors="coerce")
        out = out[out.index.notna()]
    out = out.sort_index()
    out = out[~out.index.duplicated(keep="first")]
    return out


def generate_synthetic_ohlc(
    n_bars: int = 24 * 365 * 5,
    start: str = "2016-01-01",
    freq: str = "h",
    seed: int = 42,
    start_price: float = 500.0,
) -> pd.DataFrame:
    """Geometric Brownian-ish OHLC with mild trends for offline demos."""
    rng = np.random.default_rng(seed)
    index = pd.date_range(start=start, periods=n_bars, freq=freq)
    # Regime-switching drift + clustered vol
    regime = rng.choice([-1, 0, 1], size=n_bars, p=[0.25, 0.5, 0.25])
    drift = regime * 0.00015
    vol = 0.008 + 0.004 * (regime != 0).astype(float)
    rets = drift + vol * rng.standard_normal(n_bars)
    close = start_price * np.exp(np.cumsum(rets))
    open_ = np.roll(close, 1)
    open_[0] = start_price
    wick = np.abs(rng.normal(0, 0.002, n_bars))
    high = np.maximum(open_, close) * (1 + wick)
    low = np.minimum(open_, close) * (1 - wick)
    return pd.DataFrame(
        {"open": open_, "high": high, "low": low, "close": close}, index=index
    )


def load_csv(path: str | Path) -> pd.DataFrame:
    path = Path(path)
    df = pd.read_csv(path, index_col=0, parse_dates=True)
    return _normalize_ohlc(df)


def load_parquet(path: str | Path) -> pd.DataFrame:
    path = Path(path)
    df = pd.read_parquet(path)
    if not isinstance(df.index, pd.DatetimeIndex):
        df.index = pd.to_datetime(df.index)
    return _normalize_ohlc(df)


def fetch_yfinance(
    symbol: str = "BTC-USD",
    interval: str = "1h",
    start: str = "2018-01-01",
    end: str | None = None,
) -> pd.DataFrame:
    """Download OHLCV via yfinance and normalize columns."""
    import yfinance as yf

    ticker = yf.Ticker(symbol)
    df = ticker.history(start=start, end=end, interval=interval, auto_adjust=True)
    if df.empty:
        raise ValueError(f"No data returned for {symbol}")
    df = df.rename(
        columns={"Open": "open", "High": "high", "Low": "low", "Close": "close"}
    )
    return _normalize_ohlc(df)


def get_default_dataset(
    source: str = "synthetic",
    symbol: str = "BTC-USD",
    start: str = "2018-01-01",
    end: str | None = None,
    interval: str = "1h",
) -> tuple[pd.DataFrame, str]:
    """Load market data. Falls back to synthetic if download fails."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    cached = DATA_DIR / f"{symbol.replace('/', '_')}_{interval}.parquet"

    if source == "cache" and cached.exists():
        return load_parquet(cached), f"cache:{cached.name}"

    if source == "synthetic":
        df = generate_synthetic_ohlc()
        return df, "synthetic"

    if source == "yfinance":
        try:
            df = fetch_yfinance(symbol=symbol, interval=interval, start=start, end=end)
            df.to_parquet(cached)
            return df, f"yfinance:{symbol}"
        except Exception:
            if cached.exists():
                return load_parquet(cached), f"cache:{cached.name}"
            df = generate_synthetic_ohlc()
            return df, "synthetic(fallback)"

    if Path(source).exists():
        path = Path(source)
        if path.suffix == ".parquet":
            return load_parquet(path), str(path)
        return load_csv(path), str(path)

    raise ValueError(f"Unknown data source: {source}")


def slice_years(df: pd.DataFrame, start_year: int, end_year: int) -> pd.DataFrame:
    """Inclusive start year, exclusive end year (matches original notebooks)."""
    return df[(df.index.year >= start_year) & (df.index.year < end_year)].copy()
