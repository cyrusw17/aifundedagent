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
    elif mode == "weekly_smc":
        sig = _weekly_smc(ohlc, feats)
    elif mode == "asia_sweep":
        sig = _asia_style_daily(ohlc, feats)
    elif mode == "active_smc":
        sig = _active_smc(ohlc, feats)
    elif mode == "donchian_smc":
        sig = _donchian_smc(ohlc, feats)
    elif mode == "killzone_smc":
        sig = _killzone_smc(ohlc, feats)
    elif mode == "london_asia_sweep":
        sig = _london_asia_sweep(ohlc, feats)
    elif mode == "kz_fvg":
        sig = _kz_fvg(ohlc, feats)
    elif mode == "h1_sweep_bos":
        sig = _h1_sweep_bos(ohlc, feats)
    elif mode == "kz_active":
        sig = _kz_active(ohlc, feats)
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
    """EMA trend with RSI pullback — higher trade count (light filters)."""
    c = ohlc["close"]
    ema21 = f["ema_fast"]
    long_ok = (
        (f["trend_up"] == 1)
        & (ohlc["low"] <= ema21)
        & (c > ema21)
        & (f["rsi"] < 48)
        & (f["good_day"] == 1)
    )
    short_ok = (
        (f["trend_dn"] == 1)
        & (ohlc["high"] >= ema21)
        & (c < ema21)
        & (f["rsi"] > 52)
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


def _weekly_smc(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """Daily SMC entries filtered by completed prior-week trend (causal)."""
    weekly_close = ohlc["close"].resample("W-FRI").last()
    w_ema = weekly_close.ewm(span=10, adjust=False).mean()
    # Prior completed week bias only
    w_bias = (weekly_close > w_ema).astype(int) - (weekly_close < w_ema).astype(int)
    w_bias = w_bias.shift(1)  # use last completed week
    daily_bias = w_bias.reindex(ohlc.index, method="ffill").fillna(0)

    base = generate_smc_signals(ohlc, f, min_confluence=2)
    sig = pd.Series(0, index=ohlc.index, dtype=int)
    long_ok = (base == 1) & (daily_bias >= 0) & (f["trend_up"] == 1)
    short_ok = (base == -1) & (daily_bias <= 0) & (f["trend_dn"] == 1)
    return sig.mask(long_ok, 1).mask(short_ok, -1)


def _active_smc(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """High-frequency SMC: sweep OR BOS with light trend filter."""
    long_ok = (
        ((f["sweep_low"] == 1) | ((f["bos_up"] == 1) & (f["in_discount"] == 1)))
        & (f["trend_up"] == 1)
        & (f["rsi"] < 55)
        & (f["good_day"] == 1)
    )
    short_ok = (
        ((f["sweep_high"] == 1) | ((f["bos_dn"] == 1) & (f["in_premium"] == 1)))
        & (f["trend_dn"] == 1)
        & (f["rsi"] > 45)
        & (f["good_day"] == 1)
    )
    sig = pd.Series(0, index=ohlc.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)


def _donchian_smc(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """20-day breakout confirmed by trend + not extreme RSI."""
    hh = ohlc["high"].rolling(20).max().shift(1)
    ll = ohlc["low"].rolling(20).min().shift(1)
    long_ok = (ohlc["close"] > hh) & (f["trend_up"] == 1) & (f["rsi"] < 70) & (f["good_day"] == 1)
    short_ok = (ohlc["close"] < ll) & (f["trend_dn"] == 1) & (f["rsi"] > 30) & (f["good_day"] == 1)
    sig = pd.Series(0, index=ohlc.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)


def _asia_style_daily(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """Proxy for Asia range sweep → continuation: prior 3-day range break with sweep."""
    hh = ohlc["high"].rolling(3).max().shift(1)
    ll = ohlc["low"].rolling(3).min().shift(1)
    long_ok = (
        (f["sweep_low"] == 1)
        & (ohlc["close"] > hh)
        & (f["trend_up"] == 1)
        & (f["in_discount"] == 1)
        & (f["good_day"] == 1)
    )
    short_ok = (
        (f["sweep_high"] == 1)
        & (ohlc["close"] < ll)
        & (f["trend_dn"] == 1)
        & (f["in_premium"] == 1)
        & (f["good_day"] == 1)
    )
    sig = pd.Series(0, index=ohlc.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)


def _session_masks(index: pd.DatetimeIndex) -> tuple[pd.Series, pd.Series, pd.Series]:
    """UTC session masks: Asia 00-06, London 07-10, NY 12-15."""
    hours = pd.Series([ts.hour for ts in index], index=index)
    asia = (hours >= 0) & (hours <= 6)
    london = (hours >= 7) & (hours <= 10)
    ny = (hours >= 12) & (hours <= 15)
    return asia, london, ny


def _killzone_smc(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """SMC sweep confluence restricted to London/NY killzones (H1)."""
    _, london, ny = _session_masks(ohlc.index)
    kz = london | ny
    long_ok = (
        kz
        & (f["sweep_low"] == 1)
        & (f["in_discount"] == 1)
        & ((f["trend_up"] == 1) | (f["bias"] >= 0))
        & (f["rsi"] < 50)
        & ((f["bull_fvg"] == 1) | (f["displacement"] == 1) | (f["active_bull_fvg"] == 1))
    )
    short_ok = (
        kz
        & (f["sweep_high"] == 1)
        & (f["in_premium"] == 1)
        & ((f["trend_dn"] == 1) | (f["bias"] <= 0))
        & (f["rsi"] > 50)
        & ((f["bear_fvg"] == 1) | (f["displacement"] == 1) | (f["active_bear_fvg"] == 1))
    )
    sig = pd.Series(0, index=ohlc.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)


def _london_asia_sweep(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """Classic ICT: sweep Asia high/low during London, trade reversal/continuation.

    Asia range uses prior completed Asia session only (causal).
    """
    asia, london, _ = _session_masks(ohlc.index)
    daily_ah = ohlc["high"].where(asia).groupby(ohlc.index.floor("D")).max()
    daily_al = ohlc["low"].where(asia).groupby(ohlc.index.floor("D")).min()
    prev_ah = daily_ah.shift(1).reindex(ohlc.index.floor("D")).to_numpy()
    prev_al = daily_al.shift(1).reindex(ohlc.index.floor("D")).to_numpy()
    prev_ah = pd.Series(prev_ah, index=ohlc.index)
    prev_al = pd.Series(prev_al, index=ohlc.index)

    sweep_asia_low = london & (ohlc["low"] < prev_al) & (ohlc["close"] > prev_al)
    sweep_asia_high = london & (ohlc["high"] > prev_ah) & (ohlc["close"] < prev_ah)

    long_ok = sweep_asia_low & (f["trend_up"] == 1) & (f["rsi"] < 55)
    short_ok = sweep_asia_high & (f["trend_dn"] == 1) & (f["rsi"] > 45)
    # also allow displacement confirmation
    long_ok = long_ok | (sweep_asia_low & (f["displacement"] == 1) & (f["in_discount"] == 1))
    short_ok = short_ok | (sweep_asia_high & (f["displacement"] == 1) & (f["in_premium"] == 1))

    sig = pd.Series(0, index=ohlc.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)


def _kz_fvg(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """Killzone + FVG/displacement with light trend filter (higher trade rate)."""
    _, london, ny = _session_masks(ohlc.index)
    kz = london | ny
    long_ok = (
        kz
        & ((f["bull_fvg"] == 1) | (f["active_bull_fvg"] == 1) | (f["displacement"] == 1))
        & (f["in_discount"] == 1)
        & ((f["trend_up"] == 1) | (f["bias"] >= 0))
        & (f["rsi"] < 58)
    )
    short_ok = (
        kz
        & ((f["bear_fvg"] == 1) | (f["active_bear_fvg"] == 1) | (f["displacement"] == 1))
        & (f["in_premium"] == 1)
        & ((f["trend_dn"] == 1) | (f["bias"] <= 0))
        & (f["rsi"] > 42)
    )
    sig = pd.Series(0, index=ohlc.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)


def _h1_sweep_bos(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """H1: liquidity sweep then BOS within a few bars (no weekday filter).

    Vectorized approximation: BOS within 1..8 bars after a discount/premium sweep.
    """
    sweep_long = ((f["sweep_low"] == 1) & (f["in_discount"] == 1)).to_numpy()
    sweep_short = ((f["sweep_high"] == 1) & (f["in_premium"] == 1)).to_numpy()
    bos_up = (f["bos_up"] == 1).to_numpy()
    bos_dn = (f["bos_dn"] == 1).to_numpy()
    recent_long = np.zeros(len(f), dtype=bool)
    recent_short = np.zeros(len(f), dtype=bool)
    for k in range(1, 9):
        recent_long |= np.roll(sweep_long, k)
        recent_short |= np.roll(sweep_short, k)
    recent_long[:9] = False
    recent_short[:9] = False
    long_ok = recent_long & bos_up
    short_ok = recent_short & bos_dn & ~long_ok
    sig = np.zeros(len(f), dtype=int)
    sig[long_ok] = 1
    sig[short_ok] = -1
    return pd.Series(sig, index=ohlc.index)


def _kz_active(ohlc: pd.DataFrame, f: pd.DataFrame) -> pd.Series:
    """Killzone-only active SMC: sweep or discount/premium BOS."""
    _, london, ny = _session_masks(ohlc.index)
    kz = london | ny
    long_ok = (
        kz
        & ((f["sweep_low"] == 1) | ((f["bos_up"] == 1) & (f["in_discount"] == 1)))
        & ((f["trend_up"] == 1) | (f["bias"] >= 0))
        & (f["rsi"] < 60)
    )
    short_ok = (
        kz
        & ((f["sweep_high"] == 1) | ((f["bos_dn"] == 1) & (f["in_premium"] == 1)))
        & ((f["trend_dn"] == 1) | (f["bias"] <= 0))
        & (f["rsi"] > 40)
    )
    sig = pd.Series(0, index=ohlc.index, dtype=int)
    return sig.mask(long_ok, 1).mask(short_ok & ~long_ok, -1)
