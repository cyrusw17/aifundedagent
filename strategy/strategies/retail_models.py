"""Causal retail indicator strategies (no look-ahead).

Signals fire on M15 bar close only (`pack_signal` → knowable_at = close).
Indicators use bars through index i inclusive (the just-closed bar).

Families (common retail day-trading toolkits):
- ema_cross: fast/slow EMA cross in session
- ema_rsi: trend EMA + RSI pullback continuation
- bb_rsi: Bollinger fade with RSI extreme
- donchian: Donchian/Turtle breakout
- macd: MACD line/signal cross with EMA filter
- supertrend: ATR trailing channel flip
- stoch_rsi: Stochastic oversold/overbought in EMA trend
- vwap_reversion: session VWAP deviation fade (typical-price VWAP)
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Dict, List, Optional

import numpy as np
import pandas as pd

from ..common import atr, in_killzone, pack_signal
from ..config import PARAMS, StrategyParams


@dataclass(frozen=True)
class RetailCfg:
    tag: str
    model: str
    rr: float = 2.0
    risk_pct: float = 0.010
    flatten_hour_utc: int = 22
    move_to_be: bool = False
    stop_atr: float = 1.2
    # EMA
    ema_fast: int = 9
    ema_slow: int = 21
    ema_trend: int = 50
    # RSI / Stoch
    rsi_len: int = 14
    rsi_lo: float = 35.0
    rsi_hi: float = 65.0
    stoch_k: int = 14
    stoch_d: int = 3
    stoch_lo: float = 20.0
    stoch_hi: float = 80.0
    # Bollinger
    bb_len: int = 20
    bb_std: float = 2.0
    # Donchian
    don_len: int = 20
    # MACD
    macd_fast: int = 12
    macd_slow: int = 26
    macd_sig: int = 9
    # Supertrend
    st_atr_len: int = 10
    st_mult: float = 3.0
    # VWAP
    vwap_z: float = 1.5
    # Session: killzone only vs all day until flatten
    killzone_only: bool = True
    one_per_day: bool = True
    marketable: bool = True


def _ema(x: np.ndarray, n: int) -> np.ndarray:
    s = pd.Series(x).ewm(span=n, adjust=False).mean()
    return s.to_numpy()


def _rsi(close: np.ndarray, n: int) -> np.ndarray:
    c = pd.Series(close)
    d = c.diff()
    up = d.clip(lower=0.0)
    dn = (-d).clip(lower=0.0)
    ma_up = up.ewm(alpha=1 / n, adjust=False).mean()
    ma_dn = dn.ewm(alpha=1 / n, adjust=False).mean()
    rs = ma_up / ma_dn.replace(0, np.nan)
    out = 100 - (100 / (1 + rs))
    return out.to_numpy()


def _bb(close: np.ndarray, n: int, k: float):
    s = pd.Series(close)
    mid = s.rolling(n).mean()
    sd = s.rolling(n).std(ddof=0)
    return mid.to_numpy(), (mid + k * sd).to_numpy(), (mid - k * sd).to_numpy()


def _stoch(h, l, c, k_len: int, d_len: int):
    hh = pd.Series(h).rolling(k_len).max()
    ll = pd.Series(l).rolling(k_len).min()
    k = 100 * (pd.Series(c) - ll) / (hh - ll).replace(0, np.nan)
    d = k.rolling(d_len).mean()
    return k.to_numpy(), d.to_numpy()


def _macd(close, fast, slow, sig):
    ef = _ema(close, fast)
    es = _ema(close, slow)
    line = ef - es
    signal = _ema(line, sig)
    hist = line - signal
    return line, signal, hist


def _session_vwap(idx, h, l, c, v):
    """Causal session VWAP from typical price; resets each UTC day."""
    tp = (h + l + c) / 3.0
    vol = np.where(v > 0, v, 1.0)
    out = np.full(len(c), np.nan)
    days = pd.DatetimeIndex(idx).normalize()
    i0 = 0
    while i0 < len(c):
        day = days[i0]
        i1 = i0
        while i1 < len(c) and days[i1] == day:
            i1 += 1
        pv = 0.0
        vv = 0.0
        for j in range(i0, i1):
            pv += tp[j] * vol[j]
            vv += vol[j]
            out[j] = pv / vv if vv > 0 else tp[j]
        i0 = i1
    return out


def _supertrend(h, l, c, atr_v, mult: float):
    """Causal supertrend: band updates use closed bar ATR/close."""
    n = len(c)
    upper = np.full(n, np.nan)
    lower = np.full(n, np.nan)
    st = np.full(n, np.nan)
    direction = np.ones(n)  # 1 bull, -1 bear
    hl2 = (h + l) / 2.0
    for i in range(n):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        bu = hl2[i] + mult * atr_v[i]
        bl = hl2[i] - mult * atr_v[i]
        if i == 0 or np.isnan(upper[i - 1]):
            upper[i], lower[i] = bu, bl
            st[i] = bl
            direction[i] = 1
            continue
        upper[i] = bu if (bu < upper[i - 1] or c[i - 1] > upper[i - 1]) else upper[i - 1]
        lower[i] = bl if (bl > lower[i - 1] or c[i - 1] < lower[i - 1]) else lower[i - 1]
        if direction[i - 1] >= 0:
            if c[i] < lower[i]:
                direction[i] = -1
                st[i] = upper[i]
            else:
                direction[i] = 1
                st[i] = lower[i]
        else:
            if c[i] > upper[i]:
                direction[i] = 1
                st[i] = lower[i]
            else:
                direction[i] = -1
                st[i] = upper[i]
    return st, direction


def _allow_time(ts, params, cfg: RetailCfg) -> bool:
    if cfg.killzone_only:
        return in_killzone(ts, params)
    h = ts.hour + ts.minute / 60.0
    return 7.0 <= h < cfg.flatten_hour_utc


def _stop_long(entry, atr_i, cfg: RetailCfg) -> float:
    return entry - cfg.stop_atr * atr_i


def _stop_short(entry, atr_i, cfg: RetailCfg) -> float:
    return entry + cfg.stop_atr * atr_i


def gen_ema_cross(pair, m15, params, cfg: RetailCfg) -> List:
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    ef, es = _ema(c, cfg.ema_fast), _ema(c, cfg.ema_slow)
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        # Cross on closed bar i
        bull = ef[i - 1] <= es[i - 1] and ef[i] > es[i]
        bear = ef[i - 1] >= es[i - 1] and ef[i] < es[i]
        if bull:
            entry = float(c[i])
            stop = _stop_long(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
        elif bear:
            entry = float(c[i])
            stop = _stop_short(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_ema_rsi(pair, m15, params, cfg: RetailCfg) -> List:
    """Long: price > trend EMA, RSI crosses up through rsi_lo; short mirror."""
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    et = _ema(c, cfg.ema_trend)
    r = _rsi(c, cfg.rsi_len)
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or np.isnan(r[i]) or not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        if c[i] > et[i] and r[i - 1] < cfg.rsi_lo <= r[i]:
            entry = float(c[i])
            stop = _stop_long(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
        elif c[i] < et[i] and r[i - 1] > cfg.rsi_hi >= r[i]:
            entry = float(c[i])
            stop = _stop_short(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_bb_rsi(pair, m15, params, cfg: RetailCfg) -> List:
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    mid, up, lo = _bb(c, cfg.bb_len, cfg.bb_std)
    r = _rsi(c, cfg.rsi_len)
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or np.isnan(up[i]) or not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        # Fade: close back inside after piercing band + RSI extreme
        if l[i] < lo[i] and c[i] > lo[i] and r[i] <= cfg.rsi_lo:
            entry = float(c[i])
            stop = min(float(l[i]), _stop_long(entry, atr_v[i], cfg))
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
        elif h[i] > up[i] and c[i] < up[i] and r[i] >= cfg.rsi_hi:
            entry = float(c[i])
            stop = max(float(h[i]), _stop_short(entry, atr_v[i], cfg))
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_donchian(pair, m15, params, cfg: RetailCfg) -> List:
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    # Prior N bars only (exclude current) for causal breakout
    hh = pd.Series(h).rolling(cfg.don_len).max().shift(1).to_numpy()
    ll = pd.Series(l).rolling(cfg.don_len).min().shift(1).to_numpy()
    out, used = [], set()
    for i in range(cfg.don_len + 1, len(m15)):
        if np.isnan(atr_v[i]) or np.isnan(hh[i]) or not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        if c[i] > hh[i]:
            entry = float(c[i])
            stop = _stop_long(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
        elif c[i] < ll[i]:
            entry = float(c[i])
            stop = _stop_short(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_macd(pair, m15, params, cfg: RetailCfg) -> List:
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    line, sig, _ = _macd(c, cfg.macd_fast, cfg.macd_slow, cfg.macd_sig)
    et = _ema(c, cfg.ema_trend)
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or np.isnan(line[i]) or not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        bull = line[i - 1] <= sig[i - 1] and line[i] > sig[i] and c[i] > et[i]
        bear = line[i - 1] >= sig[i - 1] and line[i] < sig[i] and c[i] < et[i]
        if bull:
            entry = float(c[i])
            stop = _stop_long(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
        elif bear:
            entry = float(c[i])
            stop = _stop_short(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_supertrend(pair, m15, params, cfg: RetailCfg) -> List:
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, cfg.st_atr_len).to_numpy()
    st, direction = _supertrend(h, l, c, atr_v, cfg.st_mult)
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(st[i]) or np.isnan(atr_v[i]) or not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        if direction[i - 1] <= 0 < direction[i]:
            entry = float(c[i])
            stop = float(min(st[i], _stop_long(entry, atr_v[i], cfg)))
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
        elif direction[i - 1] >= 0 > direction[i]:
            entry = float(c[i])
            stop = float(max(st[i], _stop_short(entry, atr_v[i], cfg)))
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_stoch_rsi(pair, m15, params, cfg: RetailCfg) -> List:
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    k, d = _stoch(h, l, c, cfg.stoch_k, cfg.stoch_d)
    et = _ema(c, cfg.ema_trend)
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or np.isnan(k[i]) or not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        if c[i] > et[i] and k[i - 1] < cfg.stoch_lo and k[i] > d[i] and k[i] > cfg.stoch_lo:
            entry = float(c[i])
            stop = _stop_long(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
        elif c[i] < et[i] and k[i - 1] > cfg.stoch_hi and k[i] < d[i] and k[i] < cfg.stoch_hi:
            entry = float(c[i])
            stop = _stop_short(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_vwap_reversion(pair, m15, params, cfg: RetailCfg) -> List:
    o, h, l, c, v = (m15[x].to_numpy() for x in ("open", "high", "low", "close", "volume"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    vwap = _session_vwap(idx, h, l, c, v)
    # rolling std of (c - vwap) for z-ish threshold
    dev = pd.Series(c - vwap)
    sd = dev.rolling(20).std(ddof=0).to_numpy()
    out, used = [], set()
    for i in range(20, len(m15)):
        if np.isnan(atr_v[i]) or np.isnan(vwap[i]) or np.isnan(sd[i]) or sd[i] <= 0:
            continue
        if not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        z = (c[i] - vwap[i]) / sd[i]
        if z <= -cfg.vwap_z and c[i] > o[i]:
            entry = float(c[i])
            stop = _stop_long(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
        elif z >= cfg.vwap_z and c[i] < o[i]:
            entry = float(c[i])
            stop = _stop_short(entry, atr_v[i], cfg)
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, cfg.marketable)
            if s:
                out.append(s)
                used.add(day)
    return out


GENERATORS: Dict[str, Callable] = {
    "ema_cross": gen_ema_cross,
    "ema_rsi": gen_ema_rsi,
    "bb_rsi": gen_bb_rsi,
    "donchian": gen_donchian,
    "macd": gen_macd,
    "supertrend": gen_supertrend,
    "stoch_rsi": gen_stoch_rsi,
    "vwap_reversion": gen_vwap_reversion,
}


def make_fn(cfg: RetailCfg) -> Callable:
    gen = GENERATORS[cfg.model]

    def _fn(pair, m15, params=PARAMS):
        return gen(pair, m15, params, cfg)

    return _fn


def build_retail_space() -> List[RetailCfg]:
    """Compact retail grid (~100) at 1% risk."""
    out: List[RetailCfg] = []
    for rr in (1.5, 2.0, 2.5, 3.0):
        for stop in (1.0, 1.5):
            for kz in (True, False):
                out.append(
                    RetailCfg(
                        tag=f"EMA_rr{rr}_s{stop}_{'kz' if kz else 'all'}",
                        model="ema_cross",
                        rr=rr,
                        stop_atr=stop,
                        killzone_only=kz,
                        ema_fast=9,
                        ema_slow=21,
                    )
                )
                out.append(
                    RetailCfg(
                        tag=f"EMARSI_rr{rr}_s{stop}_{'kz' if kz else 'all'}",
                        model="ema_rsi",
                        rr=rr,
                        stop_atr=stop,
                        killzone_only=kz,
                        ema_trend=50,
                        rsi_lo=35,
                        rsi_hi=65,
                    )
                )
    for rr in (1.5, 2.0, 2.5):
        for bb_std in (2.0, 2.5):
            out.append(
                RetailCfg(
                    tag=f"BB_rr{rr}_std{bb_std}",
                    model="bb_rsi",
                    rr=rr,
                    bb_std=bb_std,
                    rsi_lo=30,
                    rsi_hi=70,
                    stop_atr=1.2,
                    killzone_only=True,
                )
            )
    for rr in (2.0, 2.5, 3.0):
        for don in (16, 24):
            for kz in (True, False):
                out.append(
                    RetailCfg(
                        tag=f"DON_rr{rr}_n{don}_{'kz' if kz else 'all'}",
                        model="donchian",
                        rr=rr,
                        don_len=don,
                        stop_atr=1.5,
                        killzone_only=kz,
                    )
                )
    for rr in (2.0, 2.5, 3.0):
        out.append(
            RetailCfg(
                tag=f"MACD_rr{rr}",
                model="macd",
                rr=rr,
                stop_atr=1.2,
                killzone_only=True,
            )
        )
    for rr in (2.0, 2.5, 3.0):
        for mult in (2.5, 3.5):
            out.append(
                RetailCfg(
                    tag=f"ST_rr{rr}_m{mult}",
                    model="supertrend",
                    rr=rr,
                    st_mult=mult,
                    stop_atr=1.5,
                    killzone_only=True,
                )
            )
    for rr in (1.5, 2.0, 2.5):
        out.append(
            RetailCfg(
                tag=f"STOCH_rr{rr}",
                model="stoch_rsi",
                rr=rr,
                stop_atr=1.2,
                killzone_only=True,
            )
        )
        out.append(
            RetailCfg(
                tag=f"VWAP_rr{rr}",
                model="vwap_reversion",
                rr=rr,
                vwap_z=1.5,
                stop_atr=1.0,
                killzone_only=True,
            )
        )
    # Extra EMA 9/20 (retail favorite) and RSI extremes
    for rr in (2.0, 2.5):
        out.append(
            RetailCfg(
                tag=f"EMA920_rr{rr}",
                model="ema_cross",
                rr=rr,
                ema_fast=9,
                ema_slow=20,
                stop_atr=1.2,
                killzone_only=True,
            )
        )
        out.append(
            RetailCfg(
                tag=f"EMARSI30_rr{rr}",
                model="ema_rsi",
                rr=rr,
                rsi_lo=30,
                rsi_hi=70,
                ema_trend=100,
                stop_atr=1.2,
                killzone_only=True,
            )
        )
    # Higher frequency (multiple signals/day) for CAGR hunt
    for model, kwargs in (
        ("ema_cross", {"ema_fast": 9, "ema_slow": 21}),
        ("donchian", {"don_len": 16}),
        ("supertrend", {"st_mult": 3.0}),
        ("macd", {}),
        ("bb_rsi", {"bb_std": 2.0, "rsi_lo": 30, "rsi_hi": 70}),
    ):
        for rr in (2.0, 2.5, 3.0):
            out.append(
                RetailCfg(
                    tag=f"HF_{model}_rr{rr}",
                    model=model,
                    rr=rr,
                    stop_atr=1.2,
                    killzone_only=True,
                    one_per_day=False,
                    **kwargs,
                )
            )
    return out
