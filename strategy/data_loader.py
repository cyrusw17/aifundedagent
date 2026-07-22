"""Load HistData MetaTrader M1 zips and build causal M15 bars."""

from __future__ import annotations

import io
import zipfile
from pathlib import Path
from typing import Dict, Iterable, List, Optional

import pandas as pd

from .config import DATA_DIR, PARAMS


def _parse_mt_csv(text: str) -> pd.DataFrame:
    # DATE,TIME,OPEN,HIGH,LOW,CLOSE,VOLUME
    df = pd.read_csv(
        io.StringIO(text),
        header=None,
        names=["date", "time", "open", "high", "low", "close", "volume"],
    )
    ts = pd.to_datetime(df["date"] + " " + df["time"], format="%Y.%m.%d %H:%M")
    # HistData timestamps are Eastern Standard Time without DST (UTC-5 fixed)
    ts = ts + pd.Timedelta(hours=5)  # -> UTC
    out = pd.DataFrame(
        {
            "open": df["open"].astype(float).values,
            "high": df["high"].astype(float).values,
            "low": df["low"].astype(float).values,
            "close": df["close"].astype(float).values,
            "volume": df["volume"].astype(float).values,
        },
        index=pd.DatetimeIndex(ts, name="time"),
    )
    out = out[~out.index.duplicated(keep="last")].sort_index()
    return out


def load_pair_m1(pair: str, data_dir: str | Path = DATA_DIR) -> pd.DataFrame:
    pair_u = pair.upper()
    root = Path(data_dir)
    frames: List[pd.DataFrame] = []
    for zpath in sorted(root.glob(f"DAT_MT_{pair_u}_M1_*.zip")):
        with zipfile.ZipFile(zpath) as zf:
            members = [n for n in zf.namelist() if n.lower().endswith((".csv", ".txt"))]
            # Prefer csv
            members.sort(key=lambda n: (0 if n.lower().endswith(".csv") else 1, n))
            if not members:
                continue
            raw = zf.read(members[0]).decode("utf-8", errors="ignore")
            if not raw.strip():
                continue
            frames.append(_parse_mt_csv(raw))
    if not frames:
        raise FileNotFoundError(f"No M1 data for {pair_u} in {root}")
    df = pd.concat(frames).sort_index()
    df = df[~df.index.duplicated(keep="last")]
    return df


def to_m15(m1: pd.DataFrame) -> pd.DataFrame:
    ohlc = m1.resample("15min", label="left", closed="left").agg(
        {
            "open": "first",
            "high": "max",
            "low": "min",
            "close": "last",
            "volume": "sum",
        }
    )
    return ohlc.dropna(subset=["open", "high", "low", "close"])


def load_universe(
    pairs: Iterable[str] = PARAMS.pairs,
    data_dir: str | Path = DATA_DIR,
) -> Dict[str, Dict[str, pd.DataFrame]]:
    out: Dict[str, Dict[str, pd.DataFrame]] = {}
    for pair in pairs:
        m1 = load_pair_m1(pair, data_dir=data_dir)
        out[pair.upper()] = {"m1": m1, "m15": to_m15(m1)}
    return out


def slice_period(
    df: pd.DataFrame, start: Optional[str], end: Optional[str]
) -> pd.DataFrame:
    s = df
    if start:
        s = s.loc[s.index >= pd.Timestamp(start, tz=None)]
    if end:
        # inclusive end day
        s = s.loc[s.index < pd.Timestamp(end, tz=None) + pd.Timedelta(days=1)]
    return s
