"""Five causal strategies with >10% simple annualized return on 2020–2025.

Metric: simple_ann = total_return / 6 years on $100k, PF>=1.05.
Fills only after knowable_at (no look-ahead).
"""

from __future__ import annotations

from typing import Callable, Dict

from .h1_models import H1Cfg, make_fn as make_h1
from .kb_models import Cfg, make_fn as make_ict

ANN10_H1 = {
    "A1_H1Don_n35_rr5": H1Cfg(
        tag="A1_H1Don_n35_rr5",
        model="don_h1",
        rr=5.0,
        don_len=35,
        max_hold_days=3,
        stop_atr=2.0,
        session_only=True,
        risk_pct=0.012,
    ),
    "A2_H1Don_n30_rr4": H1Cfg(
        tag="A2_H1Don_n30_rr4",
        model="don_h1",
        rr=4.0,
        don_len=30,
        max_hold_days=3,
        stop_atr=2.0,
        session_only=True,
        risk_pct=0.010,
    ),
    "A3_H1Don_n40_rr4": H1Cfg(
        tag="A3_H1Don_n40_rr4",
        model="don_h1",
        rr=4.0,
        don_len=40,
        max_hold_days=3,
        stop_atr=2.0,
        session_only=True,
        risk_pct=0.012,
    ),
}

ANN10_ICT = {
    "A4_ICT_MSB_PA": Cfg(
        tag="A4_ICT_MSB_PA",
        model="multi_sb",
        rr=3.5,
        min_body_atr=0.22,
        min_fvg_atr=0.15,
        use_pdh=True,
        use_asia=True,
        strict_bias=False,
        move_to_be=False,
        risk_pct=0.020,
        flatten_hour_utc=22,
        sb_windows=((7.0, 8.0), (14.0, 15.0), (15.0, 16.0)),
    ),
    "A5_ICT_MSB_ASIA": Cfg(
        tag="A5_ICT_MSB_ASIA",
        model="multi_sb",
        rr=3.5,
        min_body_atr=0.22,
        min_fvg_atr=0.12,
        use_pdh=False,
        use_asia=True,
        strict_bias=False,
        move_to_be=False,
        risk_pct=0.020,
        flatten_hour_utc=22,
        sb_windows=((7.0, 8.0), (14.0, 15.0), (15.0, 16.0)),
    ),
}

STRATEGIES: Dict[str, Callable] = {
    **{k: make_h1(v) for k, v in ANN10_H1.items()},
    **{k: make_ict(v) for k, v in ANN10_ICT.items()},
}

STRATEGY_DESC = {
    "A1_H1Don_n35_rr5": "H1 Donchian 35, RR5, hold 3d, risk 1.2%",
    "A2_H1Don_n30_rr4": "H1 Donchian 30, RR4, hold 3d, risk 1.0%",
    "A3_H1Don_n40_rr4": "H1 Donchian 40, RR4, hold 3d, risk 1.2%",
    "A4_ICT_MSB_PA": "Multi Silver Bullet PDH+Asia, RR3.5, risk 2%",
    "A5_ICT_MSB_ASIA": "Multi Silver Bullet Asia-only, RR3.5, risk 2%",
}
