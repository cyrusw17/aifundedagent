"""Five prop-floor-safe causal strategies (The5ers $6k static floor).

Retuned from ANN10: lower risk, soft dd_halt, daily loss pause, trade caps.
Under PROP rules on 2020–2025: never hit equity floor; max_dd <= $6,000.

Fills only after knowable_at (no look-ahead).
"""

from __future__ import annotations

from dataclasses import replace
from typing import Callable, Dict

from ..config import PARAMS, StrategyParams
from .h1_models import H1Cfg, make_fn as make_h1
from .kb_models import Cfg, make_fn as make_ict

# Soft halt levels (peak−equity) — keep buffer above $6k static floor
ANN10_HALTS: Dict[str, float] = {
    "A1_H1Don_n35_rr5": 5000.0,
    "A2_H1Don_n30_rr4": 4500.0,
    "A3_H1Don_n40_rr4": 4500.0,
    "A4_ICT_MSB_PA": 4500.0,
    "A5_ICT_MSB_ASIA": 4000.0,
}

ANN10_H1 = {
    "A1_H1Don_n35_rr5": H1Cfg(
        tag="A1_H1Don_n35_rr5",
        model="don_h1",
        rr=5.0,
        don_len=35,
        max_hold_days=3,
        stop_atr=2.0,
        session_only=True,
        risk_pct=0.0035,
    ),
    "A2_H1Don_n30_rr4": H1Cfg(
        tag="A2_H1Don_n30_rr4",
        model="don_h1",
        rr=4.0,
        don_len=30,
        max_hold_days=1,
        stop_atr=2.0,
        session_only=True,
        risk_pct=0.0040,
    ),
    "A3_H1Don_n40_rr4": H1Cfg(
        tag="A3_H1Don_n40_rr4",
        model="don_h1",
        rr=4.0,
        don_len=40,
        max_hold_days=1,
        stop_atr=2.0,
        session_only=True,
        risk_pct=0.0040,
    ),
}

# Floor-safe ICT: tighter SB14 (not loose multi-window) at 0.5% risk
ANN10_ICT = {
    "A4_ICT_MSB_PA": Cfg(
        tag="A4_ICT_MSB_PA",
        model="sb_fvg",
        rr=3.5,
        min_body_atr=0.35,
        min_fvg_atr=0.15,
        use_pdh=True,
        use_asia=True,
        strict_bias=False,
        move_to_be=False,
        risk_pct=0.005,
        flatten_hour_utc=22,
        sb_start=14.0,
        sb_end=15.0,
        sb_windows=((14.0, 15.0),),
    ),
    "A5_ICT_MSB_ASIA": Cfg(
        tag="A5_ICT_MSB_ASIA",
        model="sb_fvg",
        rr=3.5,
        min_body_atr=0.45,
        min_fvg_atr=0.12,
        use_pdh=False,
        use_asia=True,
        strict_bias=False,
        move_to_be=False,
        risk_pct=0.005,
        flatten_hour_utc=22,
        sb_start=14.0,
        sb_end=15.0,
        sb_windows=((14.0, 15.0),),
    ),
}

STRATEGIES: Dict[str, Callable] = {
    **{k: make_h1(v) for k, v in ANN10_H1.items()},
    **{k: make_ict(v) for k, v in ANN10_ICT.items()},
}

STRATEGY_DESC = {
    "A1_H1Don_n35_rr5": "Floor-safe H1 Donchian 35, RR5, hold≤3d, risk 0.35%, halt $5k",
    "A2_H1Don_n30_rr4": "Floor-safe H1 Donchian 30, RR4, hold≤1d, risk 0.40%, halt $4.5k",
    "A3_H1Don_n40_rr4": "Floor-safe H1 Donchian 40, RR4, hold≤1d, risk 0.40%, halt $4.5k",
    "A4_ICT_MSB_PA": "Floor-safe SB14 PDH+Asia, RR3.5, risk 0.50%, halt $4.5k",
    "A5_ICT_MSB_ASIA": "Floor-safe SB14 Asia, RR3.5, risk 0.50%, halt $4.0k",
}


def prop_params_for(name: str) -> StrategyParams:
    """StrategyParams for prop-floor-safe simulation of a named winner."""
    halt = ANN10_HALTS[name]
    if name in ANN10_H1:
        cfg = ANN10_H1[name]
        return replace(
            PARAMS,
            risk_pct=cfg.risk_pct,
            max_hold_days=cfg.max_hold_days,
            dd_halt=halt,
            flatten_hour_utc=cfg.flatten_hour_utc,
            move_to_be=cfg.move_to_be,
            daily_profit_cap=2_500.0,
            max_trades_per_day=3,
            max_trades_per_pair_day=1,
            max_open_positions=1,
            cooldown_bars_after_trade=1,
        )
    cfg = ANN10_ICT[name]
    return replace(
        PARAMS,
        risk_pct=cfg.risk_pct,
        max_hold_days=0,
        dd_halt=halt,
        flatten_hour_utc=cfg.flatten_hour_utc,
        move_to_be=cfg.move_to_be,
        daily_profit_cap=2_500.0,
        max_trades_per_day=3,
        max_trades_per_pair_day=1,
        max_open_positions=1,
        cooldown_bars_after_trade=1,
    )
