"""Retail v2: ADX filter, H1 trend alignment, CCI, ROC momentum — all causal."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, List

import numpy as np
import pandas as pd

from ..common import atr, h1_bias_series, in_killzone, pack_signal
from ..config import PARAMS, StrategyParams
from .retail_models import RetailCfg, _ema, _rsi, _allow_time, _stop_long, _stop_short


@dataclass(frozen=True)
class RetailCfg2(RetailCfg):
    adx_len: int = 14
    adx_min: float = 20.0
    cci_len: int = 20
    cci_lo: float = -100.0
    cci_hi: float = 100.0
    roc_len: int = 10
    roc_th: float = 0.0015  # ~15 pips on FX majors as fraction
    use_h1_bias: bool = True


def _adx(h, l, c, n: int):
    df = pd.DataFrame({"high": h, "low": l, "close": c})
    up = df["high"].diff()
    dn = -df["low"].diff()
    plus_dm = np.where((up > dn) & (up > 0), up, 0.0)
    minus_dm = np.where((dn > up) & (dn > 0), dn, 0.0)
    tr = pd.concat(
        [
            df["high"] - df["low"],
            (df["high"] - df["close"].shift(1)).abs(),
            (df["low"] - df["close"].shift(1)).abs(),
        ],
        axis=1,
    ).max(axis=1)
    atr_ = tr.ewm(alpha=1 / n, adjust=False).mean()
    plus_di = 100 * pd.Series(plus_dm).ewm(alpha=1 / n, adjust=False).mean() / atr_
    minus_di = 100 * pd.Series(minus_dm).ewm(alpha=1 / n, adjust=False).mean() / atr_
    dx = (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan) * 100
    adx = dx.ewm(alpha=1 / n, adjust=False).mean()
    return adx.to_numpy(), plus_di.to_numpy(), minus_di.to_numpy()


def _cci(h, l, c, n: int):
    tp = (h + l + c) / 3.0
    s = pd.Series(tp)
    ma = s.rolling(n).mean()
    md = s.rolling(n).apply(lambda x: np.mean(np.abs(x - x.mean())), raw=True)
    return ((s - ma) / (0.015 * md.replace(0, np.nan))).to_numpy()


def _roc(c, n: int):
    s = pd.Series(c)
    return ((s - s.shift(n)) / s.shift(n)).to_numpy()


def gen_ema_rsi_adx(pair, m15, params, cfg: RetailCfg2) -> List:
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    et = _ema(c, cfg.ema_trend)
    r = _rsi(c, cfg.rsi_len)
    adx, pdi, mdi = _adx(h, l, c, cfg.adx_len)
    bias = h1_bias_series(m15).to_numpy() if cfg.use_h1_bias else np.zeros(len(m15))
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or np.isnan(r[i]) or np.isnan(adx[i]):
            continue
        if not _allow_time(idx[i], params, cfg):
            continue
        if adx[i] < cfg.adx_min:
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        long_ok = c[i] > et[i] and r[i - 1] < cfg.rsi_lo <= r[i] and pdi[i] > mdi[i]
        short_ok = c[i] < et[i] and r[i - 1] > cfg.rsi_hi >= r[i] and mdi[i] > pdi[i]
        if cfg.use_h1_bias:
            long_ok = long_ok and bias[i] > 0
            short_ok = short_ok and bias[i] < 0
        if long_ok:
            entry = float(c[i])
            s = pack_signal(
                idx[i], pair, 1, entry, _stop_long(entry, atr_v[i], cfg), cfg.rr, cfg.tag, cfg.marketable
            )
            if s:
                out.append(s)
                used.add(day)
        elif short_ok:
            entry = float(c[i])
            s = pack_signal(
                idx[i], pair, -1, entry, _stop_short(entry, atr_v[i], cfg), cfg.rr, cfg.tag, cfg.marketable
            )
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_cci_fade(pair, m15, params, cfg: RetailCfg2) -> List:
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    cci = _cci(h, l, c, cfg.cci_len)
    et = _ema(c, cfg.ema_trend)
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or np.isnan(cci[i]) or not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        # Re-cross from extreme toward zero
        if cci[i - 1] < cfg.cci_lo <= cci[i] and c[i] > et[i]:
            entry = float(c[i])
            s = pack_signal(
                idx[i], pair, 1, entry, _stop_long(entry, atr_v[i], cfg), cfg.rr, cfg.tag, cfg.marketable
            )
            if s:
                out.append(s)
                used.add(day)
        elif cci[i - 1] > cfg.cci_hi >= cci[i] and c[i] < et[i]:
            entry = float(c[i])
            s = pack_signal(
                idx[i], pair, -1, entry, _stop_short(entry, atr_v[i], cfg), cfg.rr, cfg.tag, cfg.marketable
            )
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_roc_break(pair, m15, params, cfg: RetailCfg2) -> List:
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    roc = _roc(c, cfg.roc_len)
    adx, pdi, mdi = _adx(h, l, c, cfg.adx_len)
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or np.isnan(roc[i]) or np.isnan(adx[i]):
            continue
        if not _allow_time(idx[i], params, cfg) or adx[i] < cfg.adx_min:
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        if roc[i - 1] <= cfg.roc_th < roc[i] and pdi[i] > mdi[i]:
            entry = float(c[i])
            s = pack_signal(
                idx[i], pair, 1, entry, _stop_long(entry, atr_v[i], cfg), cfg.rr, cfg.tag, cfg.marketable
            )
            if s:
                out.append(s)
                used.add(day)
        elif roc[i - 1] >= -cfg.roc_th > roc[i] and mdi[i] > pdi[i]:
            entry = float(c[i])
            s = pack_signal(
                idx[i], pair, -1, entry, _stop_short(entry, atr_v[i], cfg), cfg.rr, cfg.tag, cfg.marketable
            )
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_ema_stack(pair, m15, params, cfg: RetailCfg2) -> List:
    """Retail 'EMA ribbon': 9>21>50 aligned, pullback to fast EMA."""
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    atr_v = atr(m15, params.atr_period).to_numpy()
    e9, e21, e50 = _ema(c, 9), _ema(c, 21), _ema(c, 50)
    out, used = [], set()
    for i in range(1, len(m15)):
        if np.isnan(atr_v[i]) or not _allow_time(idx[i], params, cfg):
            continue
        day = idx[i].normalize()
        if cfg.one_per_day and day in used:
            continue
        bull = e9[i] > e21[i] > e50[i]
        bear = e9[i] < e21[i] < e50[i]
        # Touch/reject fast EMA
        if bull and l[i] <= e9[i] <= h[i] and c[i] > e9[i] and c[i] > o[i]:
            entry = float(c[i])
            s = pack_signal(
                idx[i], pair, 1, entry, _stop_long(entry, atr_v[i], cfg), cfg.rr, cfg.tag, cfg.marketable
            )
            if s:
                out.append(s)
                used.add(day)
        elif bear and l[i] <= e9[i] <= h[i] and c[i] < e9[i] and c[i] < o[i]:
            entry = float(c[i])
            s = pack_signal(
                idx[i], pair, -1, entry, _stop_short(entry, atr_v[i], cfg), cfg.rr, cfg.tag, cfg.marketable
            )
            if s:
                out.append(s)
                used.add(day)
    return out


GEN2 = {
    "ema_rsi_adx": gen_ema_rsi_adx,
    "cci_fade": gen_cci_fade,
    "roc_break": gen_roc_break,
    "ema_stack": gen_ema_stack,
}


def make_fn2(cfg: RetailCfg2) -> Callable:
    gen = GEN2[cfg.model]

    def _fn(pair, m15, params=PARAMS):
        return gen(pair, m15, params, cfg)

    return _fn


def build_retail_v2_space() -> List[RetailCfg2]:
    out: List[RetailCfg2] = []
    for rr in (2.0, 2.5, 3.0, 3.5):
        for adx_min in (18.0, 25.0):
            for stop in (1.0, 1.5):
                for h1 in (True, False):
                    out.append(
                        RetailCfg2(
                            tag=f"ARSI_rr{rr}_adx{adx_min}_s{stop}_{'H1' if h1 else 'no'}",
                            model="ema_rsi_adx",
                            rr=rr,
                            stop_atr=stop,
                            adx_min=adx_min,
                            use_h1_bias=h1,
                            rsi_lo=35,
                            rsi_hi=65,
                            ema_trend=50,
                            killzone_only=True,
                            one_per_day=True,
                        )
                    )
    for rr in (2.0, 2.5, 3.0):
        for stop in (1.0, 1.5):
            out.append(
                RetailCfg2(
                    tag=f"CCI_rr{rr}_s{stop}",
                    model="cci_fade",
                    rr=rr,
                    stop_atr=stop,
                    killzone_only=True,
                    one_per_day=True,
                    ema_trend=50,
                )
            )
            out.append(
                RetailCfg2(
                    tag=f"ROC_rr{rr}_s{stop}",
                    model="roc_break",
                    rr=rr,
                    stop_atr=stop,
                    adx_min=20,
                    killzone_only=True,
                    one_per_day=True,
                )
            )
            out.append(
                RetailCfg2(
                    tag=f"STACK_rr{rr}_s{stop}",
                    model="ema_stack",
                    rr=rr,
                    stop_atr=stop,
                    killzone_only=True,
                    one_per_day=True,
                )
            )
    # Gold-friendly: wider stops, HF stack/ADX
    for rr in (2.5, 3.0):
        out.append(
            RetailCfg2(
                tag=f"ARSI_HF_rr{rr}",
                model="ema_rsi_adx",
                rr=rr,
                stop_atr=1.5,
                adx_min=20,
                use_h1_bias=True,
                killzone_only=True,
                one_per_day=False,
            )
        )
        out.append(
            RetailCfg2(
                tag=f"STACK_HF_rr{rr}",
                model="ema_stack",
                rr=rr,
                stop_atr=1.2,
                killzone_only=True,
                one_per_day=False,
            )
        )
    return out
