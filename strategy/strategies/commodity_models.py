"""Causal commodity strategies (gold / silver / oil) — no look-ahead.

All signals via pack_signal (knowable_at = bar close).
Research must never use 2026+ bars (enforced by data_loader.RESEARCH_MAX_END).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, List

import numpy as np
import pandas as pd

from ..common import atr, pack_signal
from ..config import PARAMS, StrategyParams
from .retail_models import _ema, _rsi


@dataclass(frozen=True)
class CmdCfg:
    tag: str
    model: str
    rr: float = 3.0
    risk_pct: float = 0.01
    flatten_hour_utc: int = 22
    move_to_be: bool = False
    max_hold_days: int = 5
    don_len: int = 20
    ema_fast: int = 12
    ema_slow: int = 48
    stop_atr: float = 2.0
    atr_len: int = 14
    long_only: bool = False
    short_only: bool = False
    session_only: bool = True
    # H4 / daily helpers
    tf: str = "1h"  # 1h | 4h | 1D
    rsi_lo: float = 40.0
    rsi_hi: float = 60.0
    pullback_atr: float = 0.5


def _resample(m15: pd.DataFrame, tf: str) -> pd.DataFrame:
    rule = {"1h": "1h", "4h": "4h", "1D": "1D"}[tf]
    return m15.resample(rule, label="left", closed="left").agg(
        {"open": "first", "high": "max", "low": "min", "close": "last", "volume": "sum"}
    ).dropna(subset=["open", "high", "low", "close"])


def _atr_arr(df: pd.DataFrame, n: int) -> np.ndarray:
    prev = df["close"].shift(1)
    tr = pd.concat(
        [df["high"] - df["low"], (df["high"] - prev).abs(), (df["low"] - prev).abs()],
        axis=1,
    ).max(axis=1)
    return tr.rolling(n).mean().to_numpy()


def _tf_minutes(tf: str) -> int:
    return {"1h": 60, "4h": 240, "1D": 1440}[tf]


def _session_ok(ts, cfg: CmdCfg) -> bool:
    if not cfg.session_only:
        return True
    # Commodities: London+NY overlap bias (07-17 UTC), allow daily always
    if cfg.tf == "1D":
        return True
    return 7 <= ts.hour < 17


def gen_don(pair, m15, params, cfg: CmdCfg) -> List:
    df = _resample(m15, cfg.tf)
    h, l, c = df["high"].to_numpy(), df["low"].to_numpy(), df["close"].to_numpy()
    idx = df.index
    atr_v = _atr_arr(df, cfg.atr_len)
    hh = pd.Series(h).rolling(cfg.don_len).max().shift(1).to_numpy()
    ll = pd.Series(l).rolling(cfg.don_len).min().shift(1).to_numpy()
    tfm = _tf_minutes(cfg.tf)
    out, used = [], set()
    for i in range(cfg.don_len + 1, len(df)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or np.isnan(hh[i]):
            continue
        if not _session_ok(idx[i], cfg):
            continue
        day = idx[i].normalize()
        if day in used:
            continue
        if c[i] > hh[i] and not cfg.short_only:
            entry = float(c[i])
            stop = entry - cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=tfm)
            if s:
                out.append(s)
                used.add(day)
        elif c[i] < ll[i] and not cfg.long_only:
            entry = float(c[i])
            stop = entry + cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=tfm)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_ema(pair, m15, params, cfg: CmdCfg) -> List:
    df = _resample(m15, cfg.tf)
    c = df["close"].to_numpy()
    idx = df.index
    atr_v = _atr_arr(df, cfg.atr_len)
    ef, es = _ema(c, cfg.ema_fast), _ema(c, cfg.ema_slow)
    tfm = _tf_minutes(cfg.tf)
    out, used = [], set()
    for i in range(1, len(df)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        if not _session_ok(idx[i], cfg):
            continue
        day = idx[i].normalize()
        if day in used:
            continue
        if ef[i - 1] <= es[i - 1] and ef[i] > es[i] and not cfg.short_only:
            entry = float(c[i])
            stop = entry - cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=tfm)
            if s:
                out.append(s)
                used.add(day)
        elif ef[i - 1] >= es[i - 1] and ef[i] < es[i] and not cfg.long_only:
            entry = float(c[i])
            stop = entry + cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=tfm)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_ema_pullback(pair, m15, params, cfg: CmdCfg) -> List:
    """Trend EMA + RSI pullback continuation (causal on closed bar)."""
    df = _resample(m15, cfg.tf)
    c = df["close"].to_numpy()
    idx = df.index
    atr_v = _atr_arr(df, cfg.atr_len)
    et = _ema(c, cfg.ema_slow)
    r = _rsi(c, 14)
    tfm = _tf_minutes(cfg.tf)
    out, used = [], set()
    for i in range(2, len(df)):
        if np.isnan(atr_v[i]) or np.isnan(r[i]) or np.isnan(et[i]):
            continue
        if not _session_ok(idx[i], cfg):
            continue
        day = idx[i].normalize()
        if day in used:
            continue
        # long: price above slow EMA, RSI crosses up through rsi_lo
        if (not cfg.short_only) and c[i] > et[i] and r[i - 1] < cfg.rsi_lo <= r[i]:
            entry = float(c[i])
            stop = entry - cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=tfm)
            if s:
                out.append(s)
                used.add(day)
        elif (not cfg.long_only) and c[i] < et[i] and r[i - 1] > cfg.rsi_hi >= r[i]:
            entry = float(c[i])
            stop = entry + cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=tfm)
            if s:
                out.append(s)
                used.add(day)
    return out


def gen_atr_break(pair, m15, params, cfg: CmdCfg) -> List:
    """Break of prior bar high/low by k*ATR (causal)."""
    df = _resample(m15, cfg.tf)
    h, l, c = df["high"].to_numpy(), df["low"].to_numpy(), df["close"].to_numpy()
    idx = df.index
    atr_v = _atr_arr(df, cfg.atr_len)
    tfm = _tf_minutes(cfg.tf)
    out, used = [], set()
    for i in range(2, len(df)):
        if np.isnan(atr_v[i - 1]) or atr_v[i - 1] <= 0:
            continue
        if not _session_ok(idx[i], cfg):
            continue
        day = idx[i].normalize()
        if day in used:
            continue
        thr = cfg.pullback_atr * atr_v[i - 1]
        if (not cfg.short_only) and c[i] > h[i - 1] + thr:
            entry = float(c[i])
            stop = entry - cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=tfm)
            if s:
                out.append(s)
                used.add(day)
        elif (not cfg.long_only) and c[i] < l[i - 1] - thr:
            entry = float(c[i])
            stop = entry + cfg.stop_atr * atr_v[i]
            s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, cfg.tag, True, signal_tf_minutes=tfm)
            if s:
                out.append(s)
                used.add(day)
    return out


GEN = {
    "don": gen_don,
    "ema": gen_ema,
    "ema_pb": gen_ema_pullback,
    "atr_brk": gen_atr_break,
}


def make_cmd_fn(cfg: CmdCfg) -> Callable:
    g = GEN[cfg.model]

    def _fn(pair, m15, params=PARAMS):
        return g(pair, m15, params, cfg)

    return _fn


def build_commodity_space() -> List[CmdCfg]:
    """Broad idea grid across TFs / sides / RR."""
    out: List[CmdCfg] = []
    for tf in ("1h", "4h", "1D"):
        for side, lo, so in (("both", False, False), ("long", True, False)):
            for rr in (2.5, 3.5, 5.0):
                for don in (10, 20, 35, 55):
                    out.append(
                        CmdCfg(
                            tag=f"DON_{tf}_n{don}_rr{rr}_{side}",
                            model="don",
                            tf=tf,
                            don_len=don,
                            rr=rr,
                            long_only=lo,
                            short_only=so,
                            max_hold_days=10 if tf == "1D" else (5 if tf == "4h" else 3),
                            session_only=(tf != "1D"),
                            stop_atr=2.0,
                        )
                    )
                for ef, es in ((8, 21), (12, 48), (20, 50)):
                    out.append(
                        CmdCfg(
                            tag=f"EMA_{tf}_{ef}_{es}_rr{rr}_{side}",
                            model="ema",
                            tf=tf,
                            ema_fast=ef,
                            ema_slow=es,
                            rr=rr,
                            long_only=lo,
                            short_only=so,
                            max_hold_days=10 if tf == "1D" else (5 if tf == "4h" else 3),
                            session_only=(tf != "1D"),
                            stop_atr=2.0,
                        )
                    )
                out.append(
                    CmdCfg(
                        tag=f"PB_{tf}_rr{rr}_{side}",
                        model="ema_pb",
                        tf=tf,
                        ema_slow=50,
                        rr=rr,
                        long_only=lo,
                        short_only=so,
                        max_hold_days=5 if tf != "1D" else 10,
                        session_only=(tf != "1D"),
                        stop_atr=1.5,
                        rsi_lo=35,
                        rsi_hi=65,
                    )
                )
                out.append(
                    CmdCfg(
                        tag=f"ATRB_{tf}_rr{rr}_{side}",
                        model="atr_brk",
                        tf=tf,
                        rr=rr,
                        long_only=lo,
                        short_only=so,
                        max_hold_days=5 if tf != "1D" else 8,
                        session_only=(tf != "1D"),
                        stop_atr=2.0,
                        pullback_atr=0.35,
                    )
                )
    return out
