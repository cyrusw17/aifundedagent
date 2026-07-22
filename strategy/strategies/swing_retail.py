"""Causal swing/retail daily strategies built from M15 (no look-ahead).

Daily bar closes at 21:00 UTC (approx FX day); signal knowable then.
Entries are marketable on next M1 after daily close (= knowable_at).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, List

import numpy as np
import pandas as pd

from ..common import pack_signal
from ..config import PARAMS, StrategyParams
from .retail_models import _ema, _rsi


@dataclass(frozen=True)
class SwingCfg:
    tag: str
    model: str  # don_daily | ema_daily | rsi_daily
    rr: float = 2.5
    risk_pct: float = 0.010
    flatten_hour_utc: int = 22
    move_to_be: bool = False
    max_hold_days: int = 10
    don_len: int = 20
    ema_fast: int = 20
    ema_slow: int = 50
    rsi_len: int = 14
    rsi_lo: float = 30.0
    rsi_hi: float = 70.0
    stop_atr_mult: float = 2.0
    atr_len: int = 14


def _to_daily(m15: pd.DataFrame) -> pd.DataFrame:
    # FX day approx 22:00-21:59 UTC; use calendar day resample on M15
    d = m15.resample("1D", label="left", closed="left").agg(
        {"open": "first", "high": "max", "low": "min", "close": "last", "volume": "sum"}
    ).dropna(subset=["open", "high", "low", "close"])
    return d


def _atr_daily(d: pd.DataFrame, n: int) -> np.ndarray:
    prev = d["close"].shift(1)
    tr = pd.concat(
        [
            d["high"] - d["low"],
            (d["high"] - prev).abs(),
            (d["low"] - prev).abs(),
        ],
        axis=1,
    ).max(axis=1)
    return tr.rolling(n).mean().to_numpy()


def _emit_daily_signal(pair, day_ts, side, entry, stop, rr, tag):
    # Daily bar index is midnight; treat bar as 24h — knowable at next day open-ish.
    # Use signal_tf_minutes=1440 so knowable_at = day + 1D.
    return pack_signal(
        day_ts,
        pair,
        side,
        entry,
        stop,
        rr,
        tag,
        marketable=True,
        signal_tf_minutes=1440,
    )


def gen_don_daily(pair, m15, params, cfg: SwingCfg) -> List:
    d = _to_daily(m15)
    if len(d) < cfg.don_len + 5:
        return []
    h, l, c = d["high"].to_numpy(), d["low"].to_numpy(), d["close"].to_numpy()
    idx = d.index
    atr_v = _atr_daily(d, cfg.atr_len)
    hh = pd.Series(h).rolling(cfg.don_len).max().shift(1).to_numpy()
    ll = pd.Series(l).rolling(cfg.don_len).min().shift(1).to_numpy()
    out = []
    for i in range(cfg.don_len + 1, len(d)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or np.isnan(hh[i]):
            continue
        if c[i] > hh[i]:
            entry = float(c[i])
            stop = entry - cfg.stop_atr_mult * atr_v[i]
            s = _emit_daily_signal(pair, idx[i], 1, entry, stop, cfg.rr, cfg.tag)
            if s:
                out.append(s)
        elif c[i] < ll[i]:
            entry = float(c[i])
            stop = entry + cfg.stop_atr_mult * atr_v[i]
            s = _emit_daily_signal(pair, idx[i], -1, entry, stop, cfg.rr, cfg.tag)
            if s:
                out.append(s)
    return out


def gen_ema_daily(pair, m15, params, cfg: SwingCfg) -> List:
    d = _to_daily(m15)
    c = d["close"].to_numpy()
    idx = d.index
    atr_v = _atr_daily(d, cfg.atr_len)
    ef, es = _ema(c, cfg.ema_fast), _ema(c, cfg.ema_slow)
    out = []
    for i in range(1, len(d)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        if ef[i - 1] <= es[i - 1] and ef[i] > es[i]:
            entry = float(c[i])
            stop = entry - cfg.stop_atr_mult * atr_v[i]
            s = _emit_daily_signal(pair, idx[i], 1, entry, stop, cfg.rr, cfg.tag)
            if s:
                out.append(s)
        elif ef[i - 1] >= es[i - 1] and ef[i] < es[i]:
            entry = float(c[i])
            stop = entry + cfg.stop_atr_mult * atr_v[i]
            s = _emit_daily_signal(pair, idx[i], -1, entry, stop, cfg.rr, cfg.tag)
            if s:
                out.append(s)
    return out


def gen_rsi_daily(pair, m15, params, cfg: SwingCfg) -> List:
    d = _to_daily(m15)
    c = d["close"].to_numpy()
    idx = d.index
    atr_v = _atr_daily(d, cfg.atr_len)
    r = _rsi(c, cfg.rsi_len)
    et = _ema(c, cfg.ema_slow)
    out = []
    for i in range(1, len(d)):
        if np.isnan(atr_v[i]) or np.isnan(r[i]):
            continue
        if r[i - 1] < cfg.rsi_lo <= r[i] and c[i] > et[i]:
            entry = float(c[i])
            stop = entry - cfg.stop_atr_mult * atr_v[i]
            s = _emit_daily_signal(pair, idx[i], 1, entry, stop, cfg.rr, cfg.tag)
            if s:
                out.append(s)
        elif r[i - 1] > cfg.rsi_hi >= r[i] and c[i] < et[i]:
            entry = float(c[i])
            stop = entry + cfg.stop_atr_mult * atr_v[i]
            s = _emit_daily_signal(pair, idx[i], -1, entry, stop, cfg.rr, cfg.tag)
            if s:
                out.append(s)
    return out


GEN_SWING = {
    "don_daily": gen_don_daily,
    "ema_daily": gen_ema_daily,
    "rsi_daily": gen_rsi_daily,
}


def make_swing_fn(cfg: SwingCfg) -> Callable:
    gen = GEN_SWING[cfg.model]

    def _fn(pair, m15, params=PARAMS):
        return gen(pair, m15, params, cfg)

    return _fn


def build_swing_space() -> List[SwingCfg]:
    out = []
    for rr in (2.0, 3.0, 4.0):
        for don in (10, 20, 55):
            out.append(
                SwingCfg(
                    tag=f"DOND_rr{rr}_n{don}",
                    model="don_daily",
                    rr=rr,
                    don_len=don,
                    stop_atr_mult=2.0,
                    # Disable same-day flatten for swing: use late flatten
                    flatten_hour_utc=23,
                )
            )
        for ef, es in ((10, 30), (20, 50)):
            out.append(
                SwingCfg(
                    tag=f"EMAD_rr{rr}_{ef}_{es}",
                    model="ema_daily",
                    rr=rr,
                    ema_fast=ef,
                    ema_slow=es,
                    stop_atr_mult=2.5,
                    flatten_hour_utc=23,
                )
            )
        out.append(
            SwingCfg(
                tag=f"RSID_rr{rr}",
                model="rsi_daily",
                rr=rr,
                stop_atr_mult=2.0,
                flatten_hour_utc=23,
            )
        )
    return out
