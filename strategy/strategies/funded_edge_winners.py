"""Funded-edge gold strategies — train 2024–25, blind 2026, The5ers-viable.

Protocol:
1. Select on ≤2025-12-31 (ann, floor, daily-loss buffer, challenge pass 2024&2025).
2. One-shot blind-test 2026 H1 (open ann + challenge). Failures discarded — no retune.

Primary edge: 4h Donchian long on XAUUSD with modest RR (~1.8–2.0) and 1.5–2% risk.
Both-side daily kept as regime hedge for selloffs.
"""

from __future__ import annotations

from dataclasses import replace
from typing import Callable, Dict, List, Tuple

from ..config import PARAMS, StrategyParams
from .commodity_models import CmdCfg, make_cmd_fn

# (id, pairs, cfg, risk_pct)
_SPECS: List[Tuple[str, Tuple[str, ...], CmdCfg, float]] = [
    (
        "F1_XAU_DON4h_n40_rr1p8_L",
        ("XAUUSD",),
        CmdCfg(
            tag="F1_XAU_DON4h_n40_rr1p8_L",
            model="don",
            tf="4h",
            don_len=40,
            rr=1.8,
            long_only=True,
            max_hold_days=5,
            session_only=True,
            stop_atr=2.0,
        ),
        0.02,
    ),
    (
        "F2_XAU_DON4h_n40_rr2_L",
        ("XAUUSD",),
        CmdCfg(
            tag="F2_XAU_DON4h_n40_rr2_L",
            model="don",
            tf="4h",
            don_len=40,
            rr=2.0,
            long_only=True,
            max_hold_days=5,
            session_only=True,
            stop_atr=2.0,
        ),
        0.02,
    ),
    (
        "F3_XAU_DON4h_n35_rr1p8_L",
        ("XAUUSD",),
        CmdCfg(
            tag="F3_XAU_DON4h_n35_rr1p8_L",
            model="don",
            tf="4h",
            don_len=35,
            rr=1.8,
            long_only=True,
            max_hold_days=5,
            session_only=True,
            stop_atr=2.0,
        ),
        0.015,
    ),
    (
        "F4_XAU_DON4h_n30_rr1p8_L",
        ("XAUUSD",),
        CmdCfg(
            tag="F4_XAU_DON4h_n30_rr1p8_L",
            model="don",
            tf="4h",
            don_len=30,
            rr=1.8,
            long_only=True,
            max_hold_days=5,
            session_only=True,
            stop_atr=2.0,
        ),
        0.018,
    ),
    (
        "F5_XAU_DON1D_n30_rr2p5_B",
        ("XAUUSD",),
        CmdCfg(
            tag="F5_XAU_DON1D_n30_rr2p5_B",
            model="don",
            tf="1D",
            don_len=30,
            rr=2.5,
            long_only=False,
            short_only=False,
            max_hold_days=10,
            session_only=False,
            stop_atr=2.0,
        ),
        0.02,
    ),
]

PAIRS: Dict[str, Tuple[str, ...]] = {i: p for i, p, _, _ in _SPECS}
CFGS: Dict[str, CmdCfg] = {i: c for i, _, c, _ in _SPECS}
RISKS: Dict[str, float] = {i: r for i, _, _, r in _SPECS}
HOLDS: Dict[str, int] = {i: c.max_hold_days for i, _, c, _ in _SPECS}

STRATEGIES: Dict[str, Callable] = {i: make_cmd_fn(c) for i, _, c, _ in _SPECS}

STRATEGY_DESC = {
    "F1_XAU_DON4h_n40_rr1p8_L": "PRIMARY: Gold 4h Don40 RR1.8 long 2% — ~$62k funded 24-25, ch26≈22d",
    "F2_XAU_DON4h_n40_rr2_L": "Gold 4h Don40 RR2 long 2% — strong funded + ch26≈22d",
    "F3_XAU_DON4h_n35_rr1p8_L": "Gold 4h Don35 RR1.8 long 1.5% — balanced money / 2026",
    "F4_XAU_DON4h_n30_rr1p8_L": "Gold 4h Don30 RR1.8 long 1.8% — fastest train challenges",
    "F5_XAU_DON1D_n30_rr2p5_B": "Gold daily Don30 RR2.5 both-side — selloff hedge, ch26≈77d",
}

# Approximate researched metrics
META = {
    "F1_XAU_DON4h_n40_rr1p8_L": {
        "2024": 34.97,
        "2025": 36.06,
        "2026H1_ann": 21.93,
        "ch_days": {"2024": 100, "2025": 245, "2026": 22},
        "funded_total": {"2024_2025": 62081, "2026H1": 11151},
    },
    "F2_XAU_DON4h_n40_rr2_L": {
        "2024": 22.78,
        "2025": 38.64,
        "2026H1_ann": 23.18,
        "ch_days": {"2024": 130, "2025": 245, "2026": 22},
        "funded_total": {"2024_2025": 54318, "2026H1": 11584},
    },
    "F3_XAU_DON4h_n35_rr1p8_L": {
        "2024": 26.74,
        "2025": 25.27,
        "2026H1_ann": 26.15,
        "ch_days": {"2024": 100, "2025": 272, "2026": 28},
        "funded_total": {"2024_2025": 47119, "2026H1": 12242},
    },
    "F4_XAU_DON4h_n30_rr1p8_L": {
        "2024": 34.86,
        "2025": 36.41,
        "2026H1_ann": 18.4,
        "ch_days": {"2024": 100, "2025": 106, "2026": 51},
        "funded_total": {"2024_2025": 35155, "2026H1": 9051},
    },
    "F5_XAU_DON1D_n30_rr2p5_B": {
        "2024": 10.9,
        "2025": 12.02,
        "2026H1_ann": 29.54,
        "ch_days": {"2024": 256, "2025": 278, "2026": 77},
        "funded_total": {"2024_2025": 22158, "2026H1": 13552},
    },
}


def prop_params_for(name: str) -> StrategyParams:
    return replace(
        PARAMS,
        risk_pct=RISKS[name],
        max_hold_days=HOLDS[name],
        dd_halt=0.0,
        flatten_hour_utc=22,
        move_to_be=False,
        daily_profit_cap=6_000.0,
        max_trades_per_day=6,
        max_trades_per_pair_day=2,
        max_open_positions=2,
        cooldown_bars_after_trade=0,
        risk_from_equity=True,
        equity_halt_floor=94_000.0 + 1_000.0,
    )
