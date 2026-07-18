"""Additional causal signal generators for research iteration."""

from __future__ import annotations

import numpy as np
import pandas as pd

from mcpt.forex.smc import build_smc_features, generate_smc_signals


def generate_signals(ohlc: pd.DataFrame, mode: str = "smc", **kwargs) -> tuple[pd.Series, pd.DataFrame]:
    feats = build_smc_features(
        ohlc,
        swing_left=kwargs.get("swing_left", 3),
        swing_right=kwargs.get("swing_right", 3),
    )
    if mode == "smc":
        sig = generate_smc_signals(
            ohlc,
            feats,
            require_killzone=kwargs.get("require_killzone", False),
            min_confluence=kwargs.get("min_confluence", 3),
        )
    elif mode == "smc_strict":
        sig = _smc_strict(feats)
    elif mode == "sweep_bos":
        sig = _sweep_then_bos(ohlc, feats)
    elif mode == "trend_pullback":
        sig = _trend_pullback(ohlc, feats)
    elif mode == "breakout_hold":
        sig = _breakout_hold(ohlc, feats)
    elif mode == "combo":
        sig = _combo(ohlc, feats)
    elif mode == "smc_plus":
        sig = _smc_plus(ohlc, feats)
    else:
        sig = generate_smc_signals(ohlc, feats, min_confluence=2)
    return sig.astype(int), feats


def _smc_strict(f: pd.DataFrame) -> pd.Series:
    """Sweep + discount/premium + active FVG + aligned bias/trend."""
    long_ok = (
        (f["sweep_low"] == 1)
        & (f["in_discount"] == 1)
        & (f["active_bull_fvg"] == 1)
        & ((f["bias"] >= 0) | (f["trend_up"] == 1))
        & (f["rsi"] < 50)
        & (f["good_day"] == 1)
    )
    short_ok = (
        (f["sweep_high"] == 1)
        & (f["in_premium"] == 1)
        & (f["active_bear_fvg"] == 1)
        & ((f["bias"] <= 0) | (f["trend_dn"] == 1))
        & (f["rsi"] > 50)
        & (f["good_day"] == 1)
    )
    sig = pd.Series(0, index=f.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)


def _sweep_then_bos(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """After liquidity sweep, take first aligned BOS within 5 bars (causal)."""
    n = len(f)
    sig = np.zeros(n, dtype=int)
    sweep_low = f["sweep_low"].to_numpy()
    sweep_high = f["sweep_high"].to_numpy()
    bos_up = f["bos_up"].to_numpy()
    bos_dn = f["bos_dn"].to_numpy()
    trend_up = f["trend_up"].to_numpy()
    trend_dn = f["trend_dn"].to_numpy()
    pending = 0  # +1 wait long bos, -1 wait short bos
    age = 0
    for i in range(n):
        if pending != 0:
            age += 1
            if age > 5:
                pending = 0
            elif pending == 1 and bos_up[i] == 1 and trend_up[i] == 1:
                sig[i] = 1
                pending = 0
            elif pending == -1 and bos_dn[i] == 1 and trend_dn[i] == 1:
                sig[i] = -1
                pending = 0
        if sweep_low[i] == 1 and f["in_discount"].iloc[i] == 1:
            pending, age = 1, 0
        elif sweep_high[i] == 1 and f["in_premium"].iloc[i] == 1:
            pending, age = -1, 0
    return pd.Series(sig, index=f.index)


def _trend_pullback(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """EMA trend with RSI pullback in discount/premium — higher trade count."""
    c = ohlc["close"]
    ema21 = f["ema_fast"]
    # Pullback touch: low pierces ema while trend up, close back above
    long_ok = (
        (f["trend_up"] == 1)
        & (ohlc["low"] <= ema21)
        & (c > ema21)
        & (f["rsi"] < 45)
        & (f["in_discount"] == 1)
        & (f["good_day"] == 1)
    )
    short_ok = (
        (f["trend_dn"] == 1)
        & (ohlc["high"] >= ema21)
        & (c < ema21)
        & (f["rsi"] > 55)
        & (f["in_premium"] == 1)
        & (f["good_day"] == 1)
    )
    sig = pd.Series(0, index=f.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)


def _breakout_hold(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """Close beyond prior 20-day high/low with displacement — Donchian×SMC hybrid."""
    hh = ohlc["high"].rolling(20).max().shift(1)
    ll = ohlc["low"].rolling(20).min().shift(1)
    long_ok = (
        (ohlc["close"] > hh)
        & (f["displacement"] == 1)
        & (f["trend_up"] == 1)
        & (f["good_day"] == 1)
    )
    short_ok = (
        (ohlc["close"] < ll)
        & (f["displacement"] == 1)
        & (f["trend_dn"] == 1)
        & (f["good_day"] == 1)
    )
    sig = pd.Series(0, index=f.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)


def _combo(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """Union of strict SMC and trend pullback; prefer SMC when both."""
    a = _smc_strict(f)
    b = _trend_pullback(ohlc, f)
    sig = b.copy()
    sig = sig.mask(a != 0, a)
    return sig


def _smc_plus(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """High-frequency confluence: sweep OR (BOS+discount) with trend alignment."""
    base = generate_smc_signals(ohlc, f, min_confluence=2)
    long_add = (
        (f["bos_up"] == 1)
        & (f["in_discount"] == 1)
        & (f["trend_up"] == 1)
        & (f["rsi"] < 50)
        & (f["good_day"] == 1)
        & (f["displacement"] == 1)
    )
    short_add = (
        (f["bos_dn"] == 1)
        & (f["in_premium"] == 1)
        & (f["trend_dn"] == 1)
        & (f["rsi"] > 50)
        & (f["good_day"] == 1)
        & (f["displacement"] == 1)
    )
    sig = base.copy()
    sig = sig.mask((sig == 0) & long_add, 1)
    sig = sig.mask((sig == 0) & short_add, -1)
    return sig
