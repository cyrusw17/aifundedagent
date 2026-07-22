"""Five causal winning configs from KB search (train 2024-25, OOS 2023 & 2026).

All are ICT Silver Bullet (14:00–15:00 UTC) + liquidity sweep + FVG CE limit.
Fills only after knowable_at (bar close) — no sweep-wick look-ahead.
"""

from __future__ import annotations

from typing import Callable, Dict, List

import pandas as pd

from ..common import Signal
from ..config import StrategyParams
from .kb_models import Cfg, make_fn

# Selected: edge PF>=1.05 on DEV 2024-25, pure 2023, and 2026 H1.
WINNER_CFGS: Dict[str, Cfg] = {
    "W1_SB14_PDH_r6": Cfg(
        tag="W1_SB14_PDH_r6",
        model="sb_fvg",
        rr=3.0,
        sb_start=14.0,
        sb_end=15.0,
        strict_bias=False,
        move_to_be=False,
        risk_pct=0.006,
        flatten_hour_utc=22,
        min_body_atr=0.35,
        min_fvg_atr=0.15,
        use_pdh=True,
        use_asia=False,
    ),
    "W2_SB14_PDH_r7": Cfg(
        tag="W2_SB14_PDH_r7",
        model="sb_fvg",
        rr=3.0,
        sb_start=14.0,
        sb_end=15.0,
        strict_bias=False,
        move_to_be=False,
        risk_pct=0.007,
        flatten_hour_utc=22,
        min_body_atr=0.35,
        min_fvg_atr=0.15,
        use_pdh=True,
        use_asia=False,
    ),
    "W3_SB14_PDH_r5": Cfg(
        tag="W3_SB14_PDH_r5",
        model="sb_fvg",
        rr=3.0,
        sb_start=14.0,
        sb_end=15.0,
        strict_bias=False,
        move_to_be=False,
        risk_pct=0.005,
        flatten_hour_utc=22,
        min_body_atr=0.35,
        min_fvg_atr=0.15,
        use_pdh=True,
        use_asia=False,
    ),
    "W4_SB14_ASIA_r6": Cfg(
        tag="W4_SB14_ASIA_r6",
        model="sb_fvg",
        rr=3.0,
        sb_start=14.0,
        sb_end=15.0,
        strict_bias=False,
        move_to_be=False,
        risk_pct=0.006,
        flatten_hour_utc=22,
        min_body_atr=0.35,
        min_fvg_atr=0.10,
        use_pdh=False,
        use_asia=True,
    ),
    "W5_SB14_ASIA_r5": Cfg(
        tag="W5_SB14_ASIA_r5",
        model="sb_fvg",
        rr=3.0,
        sb_start=14.0,
        sb_end=15.0,
        strict_bias=False,
        move_to_be=False,
        risk_pct=0.005,
        flatten_hour_utc=22,
        min_body_atr=0.35,
        min_fvg_atr=0.10,
        use_pdh=False,
        use_asia=True,
    ),
}

STRATEGIES: Dict[str, Callable] = {name: make_fn(cfg) for name, cfg in WINNER_CFGS.items()}

STRATEGY_DESC = {
    "W1_SB14_PDH_r6": "Causal SB 14-15 UTC, PDH sweep→FVG, RR3, risk 0.6%, no BE",
    "W2_SB14_PDH_r7": "Causal SB 14-15 UTC, PDH sweep→FVG, RR3, risk 0.7%, no BE",
    "W3_SB14_PDH_r5": "Causal SB 14-15 UTC, PDH sweep→FVG, RR3, risk 0.5%, no BE",
    "W4_SB14_ASIA_r6": "Causal SB 14-15 UTC, Asia sweep→FVG, RR3, risk 0.6%, no BE",
    "W5_SB14_ASIA_r5": "Causal SB 14-15 UTC, Asia sweep→FVG, RR3, risk 0.5%, no BE",
}
