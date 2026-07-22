"""Causal Model A — Sweep → MSS → FVG retrace (knowledge core SMC).

All steps use closed M15 only. Limit entry into FVG only after the FVG
bar is closed (knowable_at). Never fills during the sweep wick.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Set, Tuple

import numpy as np
import pandas as pd

from ..common import (
    atr,
    bullish_fvg,
    bearish_fvg,
    confirmed_swings,
    h1_bias_series,
    in_killzone,
    pack_signal,
    prior_day_hl,
    session_ranges_complete,
)
from ..config import PARAMS, StrategyParams


@dataclass(frozen=True)
class ModelAConfig:
    name: str = "C_sweep_mss_fvg"
    rr: float = 2.0
    max_wait_mss: int = 8
    max_wait_fvg_fill: int = 12
    min_disp_atr: float = 0.35
    min_fvg_atr: float = 0.12
    require_killzone_entry: bool = True
    use_pdh: bool = True
    use_asia: bool = True
    strict_bias: bool = True  # long only if bias>0, short only if bias<0


def generate_signals(
    pair: str,
    m15: pd.DataFrame,
    params: StrategyParams = PARAMS,
    cfg: ModelAConfig = ModelAConfig(),
) -> List:
    if len(m15) < params.atr_period + 80:
        return []
    atr_v = atr(m15, params.atr_period).to_numpy()
    o, h, l, c = (m15[x].to_numpy() for x in ("open", "high", "low", "close"))
    idx = m15.index
    bias = h1_bias_series(m15).to_numpy()
    sessions = session_ranges_complete(idx, h, l)
    pdhl = prior_day_hl(idx, h, l)

    sh, sl = confirmed_swings(h, l, params.swing_left, params.swing_right)
    # map confirm bar -> swings
    sh_at: Dict[int, List[Tuple[int, float]]] = {}
    sl_at: Dict[int, List[Tuple[int, float]]] = {}
    for p, px in sh:
        sh_at.setdefault(p + params.swing_right, []).append((p, px))
    for p, px in sl:
        sl_at.setdefault(p + params.swing_right, []).append((p, px))

    known_sh: List[Tuple[int, float]] = []
    known_sl: List[Tuple[int, float]] = []
    signals = []
    used_days: Set[Tuple] = set()

    # active setups awaiting MSS then FVG
    # side, sweep_ext, sweep_i, level_name, day
    pending_mss: List[dict] = []
    pending_entry: List[dict] = []

    for i in range(2, len(m15)):
        if i in sh_at:
            known_sh.extend(sh_at[i])
        if i in sl_at:
            known_sl.extend(sl_at[i])
        if np.isnan(atr_v[i]) or atr_v[i] <= 0:
            continue

        day = idx[i].normalize()
        hour = idx[i].hour

        # expire old pending
        pending_mss = [p for p in pending_mss if i - p["sweep_i"] <= cfg.max_wait_mss]
        pending_entry = [p for p in pending_entry if i - p["fvg_i"] <= cfg.max_wait_fvg_fill]

        # --- detect sweep on this closed bar ---
        levels_hi, levels_lo = [], []
        if cfg.use_pdh and day in pdhl:
            levels_hi.append(("pdh", pdhl[day][0]))
            levels_lo.append(("pdl", pdhl[day][1]))
        if cfg.use_asia and day in sessions and "asia" in sessions[day] and hour >= 7:
            levels_hi.append(("asia_h", sessions[day]["asia"][0]))
            levels_lo.append(("asia_l", sessions[day]["asia"][1]))

        for name, lvl in levels_hi:
            key = (day, name, -1)
            if key in used_days:
                continue
            if h[i] > lvl and (h[i] - lvl) >= 0.05 * atr_v[i]:
                # sweep of buy-side liquidity — look for bearish MSS next
                if cfg.strict_bias and bias[i] > 0:
                    continue
                pending_mss.append(
                    {
                        "side": -1,
                        "sweep_ext": float(h[i]),
                        "sweep_i": i,
                        "lvl": float(lvl),
                        "name": name,
                        "day": day,
                        "key": key,
                    }
                )

        for name, lvl in levels_lo:
            key = (day, name, 1)
            if key in used_days:
                continue
            if l[i] < lvl and (lvl - l[i]) >= 0.05 * atr_v[i]:
                if cfg.strict_bias and bias[i] < 0:
                    continue
                pending_mss.append(
                    {
                        "side": 1,
                        "sweep_ext": float(l[i]),
                        "sweep_i": i,
                        "lvl": float(lvl),
                        "name": name,
                        "day": day,
                        "key": key,
                    }
                )

        # --- MSS after sweep: close beyond last confirmed swing against sweep ---
        still_mss = []
        for p in pending_mss:
            if i <= p["sweep_i"]:
                still_mss.append(p)
                continue
            # need displacement body
            if abs(c[i] - o[i]) < cfg.min_disp_atr * atr_v[i]:
                still_mss.append(p)
                continue
            if p["side"] < 0:
                # bearish MSS: close below last swing low before sweep
                swings = [(pi, px) for pi, px in known_sl if pi < p["sweep_i"]]
                if len(swings) < 1:
                    still_mss.append(p)
                    continue
                mss_lvl = swings[-1][1]
                if c[i] < mss_lvl and c[i] < o[i]:
                    fvg = bearish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                    if fvg:
                        pending_entry.append(
                            {
                                **p,
                                "fvg_i": i,
                                "fvg_lo": fvg[0],
                                "fvg_hi": fvg[1],
                                "mss_i": i,
                            }
                        )
                        used_days.add(p["key"])
                    # else drop or keep waiting — drop to avoid stale
                else:
                    still_mss.append(p)
            else:
                swings = [(pi, px) for pi, px in known_sh if pi < p["sweep_i"]]
                if len(swings) < 1:
                    still_mss.append(p)
                    continue
                mss_lvl = swings[-1][1]
                if c[i] > mss_lvl and c[i] > o[i]:
                    fvg = bullish_fvg(h, l, i, cfg.min_fvg_atr * atr_v[i])
                    if fvg:
                        pending_entry.append(
                            {
                                **p,
                                "fvg_i": i,
                                "fvg_lo": fvg[0],
                                "fvg_hi": fvg[1],
                                "mss_i": i,
                            }
                        )
                        used_days.add(p["key"])
                else:
                    still_mss.append(p)
        pending_mss = still_mss

        # --- emit limit at FVG CE on the MSS/FVG bar (fill only after this bar closes) ---
        remain_entry = []
        for p in pending_entry:
            if i < p["fvg_i"]:
                remain_entry.append(p)
                continue
            if i > p["fvg_i"]:
                # already emitted on fvg_i
                continue
            if cfg.require_killzone_entry and not in_killzone(idx[i], params):
                remain_entry.append(p)
                continue
            ce = 0.5 * (p["fvg_lo"] + p["fvg_hi"])
            if p["side"] < 0:
                entry = float(ce)
                stop = float(p["sweep_ext"] + 0.1 * atr_v[i])
                if stop - entry < params.min_stop_atr * atr_v[i]:
                    stop = entry + params.min_stop_atr * atr_v[i]
                if stop - entry > params.max_stop_atr * atr_v[i]:
                    continue
                sig = pack_signal(
                    idx[i], pair, -1, entry, stop, cfg.rr, f"{cfg.name}_{p['name']}", False
                )
            else:
                entry = float(ce)
                stop = float(p["sweep_ext"] - 0.1 * atr_v[i])
                if entry - stop < params.min_stop_atr * atr_v[i]:
                    stop = entry - params.min_stop_atr * atr_v[i]
                if entry - stop > params.max_stop_atr * atr_v[i]:
                    continue
                sig = pack_signal(
                    idx[i], pair, 1, entry, stop, cfg.rr, f"{cfg.name}_{p['name']}", False
                )
            if sig:
                signals.append(sig)
        pending_entry = [p for p in pending_entry if i < p["fvg_i"]]

    return signals
