"""Causal knowledge-base models + discrete config search on DEV 2024-25."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Set, Tuple

import numpy as np
import pandas as pd

from ..common import (
    atr,
    bearish_fvg,
    bullish_fvg,
    confirmed_swings,
    h1_bias_series,
    in_killzone,
    in_window,
    pack_signal,
    prior_day_hl,
    session_ranges_complete,
)
from ..config import PARAMS, StrategyParams


def _levels(day, hour, pdhl, sessions, use_pdh=True, use_asia=True):
    hi, lo = [], []
    if use_pdh and day in pdhl:
        hi.append(("pdh", pdhl[day][0]))
        lo.append(("pdl", pdhl[day][1]))
    if use_asia and day in sessions and "asia" in sessions[day] and hour >= 7:
        hi.append(("asia_h", sessions[day]["asia"][0]))
        lo.append(("asia_l", sessions[day]["asia"][1]))
    return hi, lo


@dataclass(frozen=True)
class Cfg:
    tag: str
    model: str  # a_mss_fvg | reject_mkt | orb | sb_fvg | bos_pullback | multi_sb
    rr: float = 2.0
    min_body_atr: float = 0.30
    min_fvg_atr: float = 0.12
    strict_bias: bool = True
    use_pdh: bool = True
    use_asia: bool = True
    max_mss_wait: int = 10
    orb_end: str = "07:45"
    sb_start: float = 14.0  # UTC hour
    sb_end: float = 15.0
    marketable: bool = False
    min_stop_mult: float = 1.0  # vs params.min_stop_atr
    move_to_be: bool = True
    risk_pct: float = 0.004
    flatten_hour_utc: int = 20
    sb_windows: tuple = ((7.0, 8.0), (14.0, 15.0), (15.0, 16.0))


def gen_reject_mkt(pair, m15, params, cfg: Cfg) -> List:
    """Model D variant: sweep+reject on same closed bar → marketable after close."""
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sessions = session_ranges_complete(idx, h, l)
    pdhl = prior_day_hl(idx, h, l)
    out, used = [], set()
    for i in range(len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or not in_killzone(idx[i], params):
            continue
        if abs(c[i] - o[i]) < cfg.min_body_atr * atr_v[i]:
            continue
        day, hour = idx[i].normalize(), idx[i].hour
        highs, lows = _levels(day, hour, pdhl, sessions, cfg.use_pdh, cfg.use_asia)
        for name, lvl in highs:
            key = (day, name, -1)
            if key in used:
                continue
            if cfg.strict_bias and bias[i] >= 0:
                continue
            if h[i] > lvl and c[i] < lvl and c[i] < o[i]:
                entry, stop = float(c[i]), float(h[i] + 0.12 * atr_v[i])
                if stop - entry < params.min_stop_atr * cfg.min_stop_mult * atr_v[i]:
                    stop = entry + params.min_stop_atr * cfg.min_stop_mult * atr_v[i]
                if stop - entry <= params.max_stop_atr * atr_v[i]:
                    s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, f"{cfg.tag}_{name}", True)
                    if s:
                        out.append(s)
                        used.add(key)
        for name, lvl in lows:
            key = (day, name, 1)
            if key in used:
                continue
            if cfg.strict_bias and bias[i] <= 0:
                continue
            if l[i] < lvl and c[i] > lvl and c[i] > o[i]:
                entry, stop = float(c[i]), float(l[i] - 0.12 * atr_v[i])
                if entry - stop < params.min_stop_atr * cfg.min_stop_mult * atr_v[i]:
                    stop = entry - params.min_stop_atr * cfg.min_stop_mult * atr_v[i]
                if entry - stop <= params.max_stop_atr * atr_v[i]:
                    s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, f"{cfg.tag}_{name}", True)
                    if s:
                        out.append(s)
                        used.add(key)
    return out


def gen_orb(pair, m15, params, cfg: Cfg) -> List:
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    df = pd.DataFrame({"high": h, "low": l}, index=idx)
    orbs = {}
    for day, chunk in df.groupby(df.index.normalize()):
        orb = chunk.between_time("07:00", cfg.orb_end)
        if len(orb) >= 3:
            hi, lo = float(orb.high.max()), float(orb.low.min())
            if hi > lo:
                orbs[day] = (hi, lo)
    out, used = [], set()
    for i in range(len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        hour = idx[i].hour
        if hour < 8 or hour >= 16:
            continue
        day = idx[i].normalize()
        if day not in orbs:
            continue
        orh, orl = orbs[day]
        w = orh - orl
        if w < 0.3 * atr_v[i] or w > 3.5 * atr_v[i]:
            continue
        if abs(c[i] - o[i]) < cfg.min_body_atr * atr_v[i]:
            continue
        if (day, 1) not in used and (not cfg.strict_bias or bias[i] > 0) and c[i] > orh and c[i] > o[i]:
            entry = float(c[i])
            stop = float(max(orl, entry - params.max_stop_atr * atr_v[i]))
            if entry - stop < params.min_stop_atr * cfg.min_stop_mult * atr_v[i] * 0.5:
                stop = entry - params.min_stop_atr * cfg.min_stop_mult * atr_v[i] * 0.5
            if 0 < entry - stop <= params.max_stop_atr * atr_v[i]:
                s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, f"{cfg.tag}_long", True)
                if s:
                    out.append(s)
                    used.add((day, 1))
        if (day, -1) not in used and (not cfg.strict_bias or bias[i] < 0) and c[i] < orl and c[i] < o[i]:
            entry = float(c[i])
            stop = float(min(orh, entry + params.max_stop_atr * atr_v[i]))
            if stop - entry < params.min_stop_atr * cfg.min_stop_mult * atr_v[i] * 0.5:
                stop = entry + params.min_stop_atr * cfg.min_stop_mult * atr_v[i] * 0.5
            if 0 < stop - entry <= params.max_stop_atr * atr_v[i]:
                s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, f"{cfg.tag}_short", True)
                if s:
                    out.append(s)
                    used.add((day, -1))
    return out


def gen_sb_fvg(pair, m15, params, cfg: Cfg) -> List:
    """Silver Bullet: sweep + displacement FVG inside SB hour → limit at CE."""
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sessions = session_ranges_complete(idx, h, l)
    pdhl = prior_day_hl(idx, h, l)
    out, used = [], set()
    for i in range(2, len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        if not in_window(idx[i], cfg.sb_start, cfg.sb_end):
            continue
        if abs(c[i] - o[i]) < cfg.min_body_atr * atr_v[i]:
            continue
        day, hour = idx[i].normalize(), idx[i].hour
        highs, lows = _levels(day, hour, pdhl, sessions, cfg.use_pdh, cfg.use_asia)
        # bearish SB: raid high then bearish FVG on this bar
        for name, lvl in highs:
            key = (day, "sb", -1)
            if key in used or (cfg.strict_bias and bias[i] >= 0):
                continue
            if h[i] > lvl and c[i] < o[i]:
                fvg = bearish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                if not fvg:
                    continue
                entry = 0.5 * (fvg[0] + fvg[1])
                stop = float(h[i] + 0.1 * atr_v[i])
                if stop - entry < params.min_stop_atr * atr_v[i]:
                    stop = entry + params.min_stop_atr * atr_v[i]
                if stop - entry <= params.max_stop_atr * atr_v[i]:
                    s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, f"{cfg.tag}_{name}", False)
                    if s:
                        out.append(s)
                        used.add(key)
        for name, lvl in lows:
            key = (day, "sb", 1)
            if key in used or (cfg.strict_bias and bias[i] <= 0):
                continue
            if l[i] < lvl and c[i] > o[i]:
                fvg = bullish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                if not fvg:
                    continue
                entry = 0.5 * (fvg[0] + fvg[1])
                stop = float(l[i] - 0.1 * atr_v[i])
                if entry - stop < params.min_stop_atr * atr_v[i]:
                    stop = entry - params.min_stop_atr * atr_v[i]
                if entry - stop <= params.max_stop_atr * atr_v[i]:
                    s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, f"{cfg.tag}_{name}", False)
                    if s:
                        out.append(s)
                        used.add(key)
    return out


def gen_bos_pullback(pair, m15, params, cfg: Cfg) -> List:
    """Model E: after bullish BOS (close > prior swing high), limit to bullish FVG."""
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sh, sl = confirmed_swings(h, l, params.swing_left, params.swing_right)
    known_sh, known_sl = [], []
    sh_c, sl_c = {}, {}
    for p, px in sh:
        sh_c.setdefault(p + params.swing_right, []).append((p, px))
    for p, px in sl:
        sl_c.setdefault(p + params.swing_right, []).append((p, px))
    out, used = [], set()
    for i in range(2, len(m15)):
        if i in sh_c:
            known_sh.extend(sh_c[i])
        if i in sl_c:
            known_sl.extend(sl_c[i])
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or not in_killzone(idx[i], params):
            continue
        day = idx[i].normalize()
        if abs(c[i] - o[i]) < cfg.min_body_atr * atr_v[i]:
            continue
        if (not cfg.strict_bias or bias[i] > 0) and (day, 1) not in used and len(known_sh) >= 1:
            last = known_sh[-1][1]
            if c[i] > last and c[i] > o[i]:
                fvg = bullish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                if fvg:
                    entry = 0.5 * (fvg[0] + fvg[1])
                    stop = float(min(l[i], entry - params.min_stop_atr * atr_v[i]))
                    if entry - stop < params.min_stop_atr * atr_v[i]:
                        stop = entry - params.min_stop_atr * atr_v[i]
                    if entry - stop <= params.max_stop_atr * atr_v[i]:
                        s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, f"{cfg.tag}_bos_long", False)
                        if s:
                            out.append(s)
                            used.add((day, 1))
        if (not cfg.strict_bias or bias[i] < 0) and (day, -1) not in used and len(known_sl) >= 1:
            last = known_sl[-1][1]
            if c[i] < last and c[i] < o[i]:
                fvg = bearish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                if fvg:
                    entry = 0.5 * (fvg[0] + fvg[1])
                    stop = float(max(h[i], entry + params.min_stop_atr * atr_v[i]))
                    if stop - entry < params.min_stop_atr * atr_v[i]:
                        stop = entry + params.min_stop_atr * atr_v[i]
                    if stop - entry <= params.max_stop_atr * atr_v[i]:
                        s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, f"{cfg.tag}_bos_short", False)
                        if s:
                            out.append(s)
                            used.add((day, -1))
    return out


def gen_sweep_mss_fvg(pair, m15, params, cfg: Cfg) -> List:
    """Model A simplified: same-bar or next-bar sweep+close reject with FVG."""
    # Use reject that also has FVG on the rejection bar
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sessions = session_ranges_complete(idx, h, l)
    pdhl = prior_day_hl(idx, h, l)
    out, used = [], set()
    for i in range(2, len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0 or not in_killzone(idx[i], params):
            continue
        if abs(c[i] - o[i]) < cfg.min_body_atr * atr_v[i]:
            continue
        day, hour = idx[i].normalize(), idx[i].hour
        highs, lows = _levels(day, hour, pdhl, sessions, cfg.use_pdh, cfg.use_asia)
        for name, lvl in highs:
            key = (day, name, -1)
            if key in used or (cfg.strict_bias and bias[i] >= 0):
                continue
            if h[i] > lvl and c[i] < lvl and c[i] < o[i]:
                fvg = bearish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                if not fvg:
                    continue
                entry = 0.5 * (fvg[0] + fvg[1])
                stop = float(h[i] + 0.1 * atr_v[i])
                if stop - entry < params.min_stop_atr * atr_v[i]:
                    stop = entry + params.min_stop_atr * atr_v[i]
                if stop - entry <= params.max_stop_atr * atr_v[i] and entry < stop:
                    s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, f"{cfg.tag}_{name}", False)
                    if s:
                        out.append(s)
                        used.add(key)
        for name, lvl in lows:
            key = (day, name, 1)
            if key in used or (cfg.strict_bias and bias[i] <= 0):
                continue
            if l[i] < lvl and c[i] > lvl and c[i] > o[i]:
                fvg = bullish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                if not fvg:
                    continue
                entry = 0.5 * (fvg[0] + fvg[1])
                stop = float(l[i] - 0.1 * atr_v[i])
                if entry - stop < params.min_stop_atr * atr_v[i]:
                    stop = entry - params.min_stop_atr * atr_v[i]
                if entry - stop <= params.max_stop_atr * atr_v[i] and entry > stop:
                    s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, f"{cfg.tag}_{name}", False)
                    if s:
                        out.append(s)
                        used.add(key)
    return out


def gen_multi_sb(pair, m15, params, cfg: Cfg) -> List:
    """Silver Bullet across several UTC windows (merged)."""
    windows = getattr(cfg, "sb_windows", None) or (
        (7.0, 8.0),
        (14.0, 15.0),
        (15.0, 16.0),
    )
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sessions = session_ranges_complete(idx, h, l)
    pdhl = prior_day_hl(idx, h, l)
    out, used = [], set()
    for i in range(2, len(m15)):
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue
        in_sb = any(in_window(idx[i], a, b) for a, b in windows)
        if not in_sb:
            continue
        if abs(c[i] - o[i]) < cfg.min_body_atr * atr_v[i]:
            continue
        day, hour = idx[i].normalize(), idx[i].hour
        highs, lows = _levels(day, hour, pdhl, sessions, cfg.use_pdh, cfg.use_asia)
        for name, lvl in highs:
            key = (day, hour, -1)  # allow one short per hour window
            if key in used or (cfg.strict_bias and bias[i] >= 0):
                continue
            if h[i] > lvl and c[i] < o[i]:
                fvg = bearish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                if not fvg:
                    continue
                entry = 0.5 * (fvg[0] + fvg[1])
                stop = float(h[i] + 0.1 * atr_v[i])
                if stop - entry < params.min_stop_atr * atr_v[i]:
                    stop = entry + params.min_stop_atr * atr_v[i]
                if stop - entry <= params.max_stop_atr * atr_v[i]:
                    s = pack_signal(idx[i], pair, -1, entry, stop, cfg.rr, f"{cfg.tag}_{name}", False)
                    if s:
                        out.append(s)
                        used.add(key)
        for name, lvl in lows:
            key = (day, hour, 1)
            if key in used or (cfg.strict_bias and bias[i] <= 0):
                continue
            if l[i] < lvl and c[i] > o[i]:
                fvg = bullish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                if not fvg:
                    continue
                entry = 0.5 * (fvg[0] + fvg[1])
                stop = float(l[i] - 0.1 * atr_v[i])
                if entry - stop < params.min_stop_atr * atr_v[i]:
                    stop = entry - params.min_stop_atr * atr_v[i]
                if entry - stop <= params.max_stop_atr * atr_v[i]:
                    s = pack_signal(idx[i], pair, 1, entry, stop, cfg.rr, f"{cfg.tag}_{name}", False)
                    if s:
                        out.append(s)
                        used.add(key)
    return out


GENERATORS = {
    "reject_mkt": gen_reject_mkt,
    "orb": gen_orb,
    "sb_fvg": gen_sb_fvg,
    "bos_pullback": gen_bos_pullback,
    "sweep_fvg": gen_sweep_mss_fvg,
    "multi_sb": gen_multi_sb,
}


def make_fn(cfg: Cfg) -> Callable:
    gen = GENERATORS[cfg.model]

    def _fn(pair, m15, params=PARAMS):
        return gen(pair, m15, params, cfg)

    return _fn


def build_search_space() -> List[Cfg]:
    cfgs: List[Cfg] = []
    for rr in (1.5, 2.0, 2.5):
        for body in (0.25, 0.45):
            for strict in (True, False):
                cfgs.append(
                    Cfg(
                        tag=f"RJ_rr{rr}_b{body}_{'S' if strict else 'L'}",
                        model="reject_mkt",
                        rr=rr,
                        min_body_atr=body,
                        strict_bias=strict,
                    )
                )
    for rr in (1.5, 2.0, 2.5):
        for body in (0.25, 0.40):
            for strict in (True, False):
                for orb_end in ("07:30", "07:45"):
                    cfgs.append(
                        Cfg(
                            tag=f"ORB_rr{rr}_b{body}_{orb_end}_{'S' if strict else 'L'}",
                            model="orb",
                            rr=rr,
                            min_body_atr=body,
                            strict_bias=strict,
                            orb_end=orb_end,
                        )
                    )
    for rr in (2.0, 2.5, 3.0):
        for sb in ((7.0, 8.0), (14.0, 15.0), (15.0, 16.0)):
            for strict in (True, False):
                cfgs.append(
                    Cfg(
                        tag=f"SB_{int(sb[0])}-{int(sb[1])}_rr{rr}_{'S' if strict else 'L'}",
                        model="sb_fvg",
                        rr=rr,
                        sb_start=sb[0],
                        sb_end=sb[1],
                        strict_bias=strict,
                        min_body_atr=0.30,
                    )
                )
    for rr in (1.5, 2.0, 2.5):
        for body in (0.30, 0.45):
            for strict in (True, False):
                cfgs.append(
                    Cfg(
                        tag=f"BOS_rr{rr}_b{body}_{'S' if strict else 'L'}",
                        model="bos_pullback",
                        rr=rr,
                        min_body_atr=body,
                        strict_bias=strict,
                    )
                )
                cfgs.append(
                    Cfg(
                        tag=f"SFVG_rr{rr}_b{body}_{'S' if strict else 'L'}",
                        model="sweep_fvg",
                        rr=rr,
                        min_body_atr=body,
                        strict_bias=strict,
                    )
                )
    return cfgs
