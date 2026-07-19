"""Causal Smart Money / ICT feature engineering (no look-ahead).

Every feature at bar i uses only information available at bar i close.
Signals intended for execution on bar i+1 open.
"""

from __future__ import annotations

import numpy as np
import pandas as pd


def _swing_high(high: pd.Series, left: int = 3, right: int = 3) -> pd.Series:
    """Swing high confirmed only after `right` bars have closed (no future leak)."""
    n = len(high)
    out = np.full(n, np.nan)
    vals = high.to_numpy()
    for i in range(left + right, n):
        # Candidate peak at i - right (fully confirmed)
        c = i - right
        window = vals[c - left : c + right + 1]
        if vals[c] >= window.max():
            out[i] = vals[c]  # known at confirmation bar i
    return pd.Series(out, index=high.index)


def _swing_low(low: pd.Series, left: int = 3, right: int = 3) -> pd.Series:
    n = len(low)
    out = np.full(n, np.nan)
    vals = low.to_numpy()
    for i in range(left + right, n):
        c = i - right
        window = vals[c - left : c + right + 1]
        if vals[c] <= window.min():
            out[i] = vals[c]
    return pd.Series(out, index=low.index)


def build_smc_features(
    ohlc: pd.DataFrame,
    swing_left: int = 3,
    swing_right: int = 3,
    atr_period: int = 14,
    structure_lookback: int = 20,
) -> pd.DataFrame:
    """Return feature frame aligned to ohlc index. Safe for live: bar-close features."""
    df = ohlc.copy()
    o, h, l, c = df["open"], df["high"], df["low"], df["close"]

    # ATR for stops / displacement
    prev_c = c.shift(1)
    tr = pd.concat([(h - l), (h - prev_c).abs(), (l - prev_c).abs()], axis=1).max(axis=1)
    atr = tr.rolling(atr_period).mean()

    sh = _swing_high(h, swing_left, swing_right)
    sl = _swing_low(l, swing_left, swing_right)

    # Last confirmed swing levels (forward-filled)
    last_swing_high = sh.ffill()
    last_swing_low = sl.ffill()

    # Liquidity sweep on current completed bar
    # Sweep high: took buy-side liquidity then closed back below swing high
    sweep_high = (h > last_swing_high.shift(1)) & (c < last_swing_high.shift(1))
    sweep_low = (l < last_swing_low.shift(1)) & (c > last_swing_low.shift(1))

    # Fair value gaps (3-candle), detected at bar i using i, i-1, i-2
    bull_fvg = l > h.shift(2)
    bear_fvg = h < l.shift(2)
    bull_fvg_top = np.where(bull_fvg, l, np.nan)
    bull_fvg_bot = np.where(bull_fvg, h.shift(2), np.nan)
    bear_fvg_top = np.where(bear_fvg, l.shift(2), np.nan)
    bear_fvg_bot = np.where(bear_fvg, h, np.nan)

    # Active FVG: last unmitigated (simple: keep last gap until price closes through)
    active_bull_top = pd.Series(bull_fvg_top, index=df.index).ffill()
    active_bull_bot = pd.Series(bull_fvg_bot, index=df.index).ffill()
    active_bear_top = pd.Series(bear_fvg_top, index=df.index).ffill()
    active_bear_bot = pd.Series(bear_fvg_bot, index=df.index).ffill()

    # Mitigate: if close through gap, clear (set NaN via mask)
    mit_bull = c < active_bull_bot
    mit_bear = c > active_bear_top
    active_bull_top = active_bull_top.mask(mit_bull)
    active_bull_bot = active_bull_bot.mask(mit_bull)
    active_bear_top = active_bear_top.mask(mit_bear)
    active_bear_bot = active_bear_bot.mask(mit_bear)
    # re-ffill after mitigation clears — use last *new* gap only
    active_bull_top = pd.Series(bull_fvg_top, index=df.index)
    active_bull_bot = pd.Series(bull_fvg_bot, index=df.index)
    active_bear_top = pd.Series(bear_fvg_top, index=df.index)
    active_bear_bot = pd.Series(bear_fvg_bot, index=df.index)
    for i in range(1, len(df)):
        if np.isnan(active_bull_top.iloc[i]):
            # carry previous if not mitigated by this close
            prev_bot = active_bull_bot.iloc[i - 1]
            prev_top = active_bull_top.iloc[i - 1]
            if not np.isnan(prev_bot) and c.iloc[i] >= prev_bot:
                active_bull_top.iloc[i] = prev_top
                active_bull_bot.iloc[i] = prev_bot
        if np.isnan(active_bear_top.iloc[i]):
            prev_bot = active_bear_bot.iloc[i - 1]
            prev_top = active_bear_top.iloc[i - 1]
            if not np.isnan(prev_top) and c.iloc[i] <= prev_top:
                active_bear_top.iloc[i] = prev_top
                active_bear_bot.iloc[i] = prev_bot

    # Displacement: body > k * ATR
    body = (c - o).abs()
    displacement = body > (1.2 * atr)

    # Structure bias from recent confirmed swings
    # +1 if last swing high > prior swing high and last swing low > prior (up)
    sh_pts = sh.dropna()
    sl_pts = sl.dropna()
    bias = pd.Series(0, index=df.index, dtype=int)
    last_sh_vals = []
    last_sl_vals = []
    sh_arr = sh.to_numpy()
    sl_arr = sl.to_numpy()
    bias_arr = np.zeros(len(df), dtype=int)
    for i in range(len(df)):
        if not np.isnan(sh_arr[i]):
            last_sh_vals.append(sh_arr[i])
            if len(last_sh_vals) > 5:
                last_sh_vals.pop(0)
        if not np.isnan(sl_arr[i]):
            last_sl_vals.append(sl_arr[i])
            if len(last_sl_vals) > 5:
                last_sl_vals.pop(0)
        b = 0
        if len(last_sh_vals) >= 2 and len(last_sl_vals) >= 2:
            if last_sh_vals[-1] > last_sh_vals[-2] and last_sl_vals[-1] > last_sl_vals[-2]:
                b = 1
            elif last_sh_vals[-1] < last_sh_vals[-2] and last_sl_vals[-1] < last_sl_vals[-2]:
                b = -1
        bias_arr[i] = b
    bias = pd.Series(bias_arr, index=df.index)

    # Premium / discount vs last swing range
    rng_hi = last_swing_high
    rng_lo = last_swing_low
    eq = (rng_hi + rng_lo) / 2.0
    in_discount = c < eq
    in_premium = c > eq

    # BOS on close
    bos_up = c > last_swing_high.shift(1)
    bos_dn = c < last_swing_low.shift(1)

    # EMA trend filter (causal)
    ema_fast = c.ewm(span=21, adjust=False).mean()
    ema_slow = c.ewm(span=55, adjust=False).mean()
    trend_up = ema_fast > ema_slow
    trend_dn = ema_fast < ema_slow

    # RSI for mean-revert confluence after sweep
    delta = c.diff()
    gain = delta.clip(lower=0).rolling(14).mean()
    loss = (-delta.clip(upper=0)).rolling(14).mean()
    rs = gain / loss.replace(0, np.nan)
    rsi = 100 - (100 / (1 + rs))

    # Session / calendar (UTC). For daily bars hour is 0.
    idx = df.index
    if getattr(idx, "tz", None) is not None:
        idx_utc = idx.tz_convert("UTC")
    else:
        idx_utc = idx.tz_localize("UTC") if hasattr(idx, "tz_localize") else idx
    try:
        hours = pd.Series([ts.hour for ts in idx_utc], index=df.index)
        dow = pd.Series([ts.dayofweek for ts in idx_utc], index=df.index)
    except Exception:
        hours = pd.Series(0, index=df.index)
        dow = pd.Series(df.index.dayofweek, index=df.index)

    london_kz = (hours >= 7) & (hours <= 10)
    ny_kz = (hours >= 12) & (hours <= 15)
    killzone = london_kz | ny_kz
    # On daily data, prefer Tue–Thu
    good_day = dow.isin([1, 2, 3])

    # --- Order blocks (causal ICT-style) ---
    # Bullish OB: last down-close candle before a bullish impulse (displacement or BOS up).
    # Bearish OB: last up-close candle before a bearish impulse.
    # Active until mitigated by close through the zone; touch = range overlaps OB.
    o_arr = o.to_numpy(dtype=float)
    h_arr = h.to_numpy(dtype=float)
    l_arr = l.to_numpy(dtype=float)
    c_arr = c.to_numpy(dtype=float)
    disp_arr = displacement.fillna(False).to_numpy(dtype=bool)
    bos_up_arr = bos_up.fillna(False).to_numpy(dtype=bool)
    bos_dn_arr = bos_dn.fillna(False).to_numpy(dtype=bool)
    n = len(df)
    bull_ob_hi = np.full(n, np.nan)
    bull_ob_lo = np.full(n, np.nan)
    bear_ob_hi = np.full(n, np.nan)
    bear_ob_lo = np.full(n, np.nan)
    touch_bull_ob = np.zeros(n, dtype=bool)
    touch_bear_ob = np.zeros(n, dtype=bool)
    in_bull_ob = np.zeros(n, dtype=bool)
    in_bear_ob = np.zeros(n, dtype=bool)
    cur_b_hi = cur_b_lo = np.nan
    cur_s_hi = cur_s_lo = np.nan
    for i in range(n):
        # mitigate first on this close
        if not np.isnan(cur_b_lo) and c_arr[i] < cur_b_lo:
            cur_b_hi = cur_b_lo = np.nan
        if not np.isnan(cur_s_hi) and c_arr[i] > cur_s_hi:
            cur_s_hi = cur_s_lo = np.nan
        # form new OB from impulse at i (origin candle is prior opposite-body bar)
        if disp_arr[i] or bos_up_arr[i]:
            for j in range(i - 1, max(i - 8, -1), -1):
                if c_arr[j] < o_arr[j]:  # down-close
                    cur_b_hi, cur_b_lo = h_arr[j], l_arr[j]
                    break
        if disp_arr[i] or bos_dn_arr[i]:
            for j in range(i - 1, max(i - 8, -1), -1):
                if c_arr[j] > o_arr[j]:  # up-close
                    cur_s_hi, cur_s_lo = h_arr[j], l_arr[j]
                    break
        bull_ob_hi[i], bull_ob_lo[i] = cur_b_hi, cur_b_lo
        bear_ob_hi[i], bear_ob_lo[i] = cur_s_hi, cur_s_lo
        if not np.isnan(cur_b_lo):
            touch_bull_ob[i] = (l_arr[i] <= cur_b_hi) and (h_arr[i] >= cur_b_lo)
            in_bull_ob[i] = (c_arr[i] <= cur_b_hi) and (c_arr[i] >= cur_b_lo)
        if not np.isnan(cur_s_hi):
            touch_bear_ob[i] = (l_arr[i] <= cur_s_hi) and (h_arr[i] >= cur_s_lo)
            in_bear_ob[i] = (c_arr[i] <= cur_s_hi) and (c_arr[i] >= cur_s_lo)

    # Active FVG zone touch (use carried active_* levels)
    ab_top = active_bull_top.to_numpy(dtype=float)
    ab_bot = active_bull_bot.to_numpy(dtype=float)
    as_top = active_bear_top.to_numpy(dtype=float)
    as_bot = active_bear_bot.to_numpy(dtype=float)
    touch_bull_fvg = np.zeros(n, dtype=bool)
    touch_bear_fvg = np.zeros(n, dtype=bool)
    for i in range(n):
        if not np.isnan(ab_bot[i]) and not np.isnan(ab_top[i]):
            touch_bull_fvg[i] = (l_arr[i] <= ab_top[i]) and (h_arr[i] >= ab_bot[i])
        if not np.isnan(as_bot[i]) and not np.isnan(as_top[i]):
            touch_bear_fvg[i] = (l_arr[i] <= as_top[i]) and (h_arr[i] >= as_bot[i])

    out = pd.DataFrame(
        {
            "atr": atr,
            "last_swing_high": last_swing_high,
            "last_swing_low": last_swing_low,
            "sweep_high": sweep_high.astype(int),
            "sweep_low": sweep_low.astype(int),
            "bull_fvg": bull_fvg.astype(int),
            "bear_fvg": bear_fvg.astype(int),
            "active_bull_fvg": (~active_bull_bot.isna()).astype(int),
            "active_bear_fvg": (~active_bear_top.isna()).astype(int),
            "displacement": displacement.fillna(False).astype(int),
            "bias": bias,
            "in_discount": in_discount.fillna(False).astype(int),
            "in_premium": in_premium.fillna(False).astype(int),
            "bos_up": bos_up.fillna(False).astype(int),
            "bos_dn": bos_dn.fillna(False).astype(int),
            "trend_up": trend_up.astype(int),
            "trend_dn": trend_dn.astype(int),
            "rsi": rsi,
            "killzone": killzone.astype(int),
            "good_day": good_day.astype(int),
            "ema_fast": ema_fast,
            "ema_slow": ema_slow,
            "eq": eq,
            "bull_ob_high": bull_ob_hi,
            "bull_ob_low": bull_ob_lo,
            "bear_ob_high": bear_ob_hi,
            "bear_ob_low": bear_ob_lo,
            "active_bull_ob": (~np.isnan(bull_ob_lo)).astype(int),
            "active_bear_ob": (~np.isnan(bear_ob_hi)).astype(int),
            "touch_bull_ob": touch_bull_ob.astype(int),
            "touch_bear_ob": touch_bear_ob.astype(int),
            "in_bull_ob": in_bull_ob.astype(int),
            "in_bear_ob": in_bear_ob.astype(int),
            "touch_bull_fvg": touch_bull_fvg.astype(int),
            "touch_bear_fvg": touch_bear_fvg.astype(int),
        },
        index=df.index,
    )
    return out


def generate_smc_signals(
    ohlc: pd.DataFrame,
    feats: pd.DataFrame,
    require_killzone: bool = False,
    min_confluence: int = 3,
    rsi_long_max: float = 45.0,
    rsi_short_min: float = 55.0,
) -> pd.Series:
    """Discrete signal in {-1, 0, +1} decided at bar close → trade next open.

    Long setup (ICT-style):
      sweep lows (sell-side liquidity taken) + discount + (FVG or displacement)
      + bullish bias/trend + RSI not overbought + optional killzone/weekday

    Short is mirrored.
    """
    f = feats
    long_score = (
        f["sweep_low"]
        + f["in_discount"]
        + ((f["bull_fvg"] | f["active_bull_fvg"] | f["displacement"]).astype(int))
        + ((f["bias"] > 0) | (f["trend_up"] > 0)).astype(int)
        + (f["rsi"] < rsi_long_max).astype(int)
        + f["good_day"]
    )
    short_score = (
        f["sweep_high"]
        + f["in_premium"]
        + ((f["bear_fvg"] | f["active_bear_fvg"] | f["displacement"]).astype(int))
        + ((f["bias"] < 0) | (f["trend_dn"] > 0)).astype(int)
        + (f["rsi"] > rsi_short_min).astype(int)
        + f["good_day"]
    )

    if require_killzone:
        long_score = long_score + f["killzone"]
        short_score = short_score + f["killzone"]
        # bump threshold if killzone required
        need = min_confluence + 1
    else:
        need = min_confluence

    # Must include the liquidity sweep as mandatory trigger
    long_ok = (f["sweep_low"] == 1) & (long_score >= need)
    short_ok = (f["sweep_high"] == 1) & (short_score >= need)

    sig = pd.Series(0, index=ohlc.index, dtype=int)
    sig = sig.mask(long_ok, 1)
    sig = sig.mask(short_ok & ~long_ok, -1)
    # If both, prefer higher score
    both = long_ok & short_ok
    sig = sig.mask(both & (short_score > long_score), -1)
    sig = sig.mask(both & (long_score >= short_score), 1)
    return sig.astype(int)
