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


def load_pair_m1(
    pair: str,
    data_dir: str | Path = DATA_DIR,
    *,
    max_end: Optional[str] = None,
) -> pd.DataFrame:
    """Load M1 bars. If max_end is set (e.g. '2025-12-31'), drop later bars and
    skip zip files whose names imply years after that cutoff (no 2026+ leakage).
    """
    pair_u = pair.upper()
    root = Path(data_dir)
    frames: List[pd.DataFrame] = []
    max_year = None
    if max_end:
        max_year = int(str(max_end)[:4])
    for zpath in sorted(root.glob(f"DAT_MT_{pair_u}_M1_*.zip")):
        # Skip future-year archives when a research cutoff is set
        if max_year is not None:
            name = zpath.name  # DAT_MT_XAUUSD_M1_202601.zip or ..._2025.zip
            # Extract year token after M1_
            try:
                token = name.split("_M1_")[1].split(".")[0]
                y = int(token[:4])
                if y > max_year:
                    continue
            except (IndexError, ValueError):
                pass
        with zipfile.ZipFile(zpath) as zf:
            members = [n for n in zf.namelist() if n.lower().endswith((".csv", ".txt"))]
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
    if max_end:
        df = df.loc[df.index < pd.Timestamp(max_end) + pd.Timedelta(days=1)]
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


# Hard research cutoff — never load 2026+ into strategy research / training.
RESEARCH_MAX_END = "2025-12-31"


def load_universe(
    pairs: Iterable[str] = PARAMS.pairs,
    data_dir: str | Path = DATA_DIR,
    *,
    max_end: Optional[str] = RESEARCH_MAX_END,
) -> Dict[str, Dict[str, pd.DataFrame]]:
    out: Dict[str, Dict[str, pd.DataFrame]] = {}
    for pair in pairs:
        m1 = load_pair_m1(pair, data_dir=data_dir, max_end=max_end)
        if max_end and len(m1) and m1.index.max() >= pd.Timestamp(max_end) + pd.Timedelta(days=1):
            raise RuntimeError(f"LOOKAHEAD/FUTURE DATA: {pair} has bars after {max_end}")
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
