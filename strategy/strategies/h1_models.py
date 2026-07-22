"""Causal H1 Donchian / EMA trend models (no look-ahead)."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, List

import numpy as np
import pandas as pd

from ..common import pack_signal
from ..config import PARAMS, StrategyParams
from .retail_models import _ema


@dataclass(frozen=True)
class H1Cfg:
    tag: str
    model: str  # don_h1 | ema_h1
    rr: float = 3.0
    risk_pct: float = 0.010
    flatten_hour_utc: int = 22
    move_to_be: bool = False
    max_hold_days: int = 5
    don_len: int = 20
    ema_fast: int = 12
    ema_slow: int = 48
    stop_atr: float = 2.0
    atr_len: int = 14
    session_only: bool = False  # if True, only signal in killzone hours on H1
    long_only: bool = False
    short_only: bool = False


def _to_h1(m15: pd.DataFrame) -> pd.DataFrame:
    return m15.resample("1h", label="left", closed="left").agg(
        {"open": "first", "high": "max", "low": "min", "close": "last", "volume": "sum"}
    ).dropna(subset=["open", "high", "low", "close"])


def _atr(df, n):
    prev = df["close"].shift(1)
    tr = pd.concat(
        [df["high"] - df["low"], (df["high"] - prev).abs(), (df["low"] - prev).abs()],
        axis=1,
    ).max(axis=1)
    return tr.rolling(n).mean().to_numpy()


def gen_don_h1(pair, m15, params, cfg: H1Cfg) -> List:
    h1 = _to_h1(m15)
    h, l, c = h1["high"].to_numpy(), h1["low"].to_numpy(), h1["close"].to_numpy()
    idx = h1.index
    atr_v = _atr(h1, cfg.atr_len)
    hh = pd.Series(h).rolling(cfg.don_len).max().shift(1).to_numpy()
    ll = pd.Series(l).rolling(cfg.don_len).min().shift(1).to_numpy()
    out, used = [], set()
    for i in range(cfg.don_len + 1, len(h1)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or np.isnan(hh[i]):
            continue
        if cfg.session_only and not (7 <= idx[i].hour < 17):
            continue
        day = idx[i].normalize()
        if day in used:
            continue
        if c[i] > hh[i]:
            if cfg.short_only:
                continue
            entry = float(c[i])
            stop = entry - cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=60)
            if s:
                out.append(s)
                used.add(day)
        elif c[i] < ll[i]:
            if cfg.long_only:
                continue
            entry = float(c[i])
            stop = entry + cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=60)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_ema_h1(pair, m15, params, cfg: H1Cfg) -> List:
    h1 = _to_h1(m15)
    c = h1["close"].to_numpy()
    idx = h1.index
    atr_v = _atr(h1, cfg.atr_len)
    ef, es = _ema(c, cfg.ema_fast), _ema(c, cfg.ema_slow)
    out, used = [], set()
    for i in range(1, len(h1)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        if cfg.session_only and not (7 <= idx[i].hour < 17):
            continue
        day = idx[i].normalize()
        if day in used:
            continue
        if ef[i - 1] <= es[i - 1] and ef[i] > es[i]:
            if cfg.short_only:
                continue
            entry = float(c[i])
            stop = entry - cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=60)
            if s:
                out.append(s)
                used.add(day)
        elif ef[i - 1] >= es[i - 1] and ef[i] < es[i]:
            if cfg.long_only:
                continue
            entry = float(c[i])
            stop = entry + cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=60)
            if s:
                out.append(s)
                used.add(day)
    return out


GEN = {"don_h1": gen_don_h1, "ema_h1": gen_ema_h1}


def make_fn(cfg: H1Cfg) -> Callable:
    g = GEN[cfg.model]

    def _fn(pair, m15, params=PARAMS):
        return g(pair, m15, params, cfg)

    return _fn

