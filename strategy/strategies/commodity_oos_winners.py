"""Commodity OOS survivors — trained on 2024–2025, one-shot blind-tested on 2026.

Method:
1. Select only if 2024≥10%, 2025≥10%, 2023≥0%, no year 2021–25 < −8%, floor held.
2. Blind-test 2026-01-01..2026-06-30 once. If fail → discard (curve-fit). Never retune on 2026.

Causality: pack_signal → knowable_at = bar close; engine rejects early fills.
"""

from __future__ import annotations

from dataclasses import replace
from typing import Callable, Dict, List, Tuple

from ..config import PARAMS, StrategyParams
from .commodity_models import CmdCfg, make_cmd_fn

# (id, pairs, cfg, risk_pct)
# Diversified across side / TF / model from OOS hunt (see results/commodity_oos_survivors.json)
_SPECS: List[Tuple[str, Tuple[str, ...], CmdCfg, float]] = [
    (
        "O1_XAU_DON1D_n25_rr2p5_B",
        ("XAUUSD",),
        CmdCfg(
            tag="O1_XAU_DON1D_n25_rr2p5_B",
            model="don",
            tf="1D",
            don_len=25,
            rr=2.5,
            long_only=False,
            short_only=False,
            max_hold_days=10,
            session_only=False,
            stop_atr=2.0,
        ),
        0.025,
    ),
    (
        "O2_XAU_DON1D_n15_rr3_L",
        ("XAUUSD",),
        CmdCfg(
            tag="O2_XAU_DON1D_n15_rr3_L",
            model="don",
            tf="1D",
            don_len=15,
            rr=3.0,
            long_only=True,
            short_only=False,
            max_hold_days=10,
            session_only=False,
            stop_atr=2.0,
        ),
        0.02,
    ),
    (
        "O3_XAU_ATRB1D_k035_rr5_L",
        ("XAUUSD",),
        CmdCfg(
            tag="O3_XAU_ATRB1D_k035_rr5_L",
            model="atr_brk",
            tf="1D",
            rr=5.0,
            pullback_atr=0.35,
            long_only=True,
            short_only=False,
            max_hold_days=10,
            session_only=False,
            stop_atr=2.0,
        ),
        0.01,
    ),
    (
        "O4_XAU_DON4h_n40_rr2_L",
        ("XAUUSD",),
        CmdCfg(
            tag="O4_XAU_DON4h_n40_rr2_L",
            model="don",
            tf="4h",
            don_len=40,
            rr=2.0,
            long_only=True,
            short_only=False,
            max_hold_days=5,
            session_only=True,
            stop_atr=2.0,
        ),
        0.01,
    ),
    (
        "O5_XAU_DON1D_n30_rr2p5_B",
        ("XAUUSD",),
        CmdCfg(
            tag="O5_XAU_DON1D_n30_rr2p5_B",
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
    "O1_XAU_DON1D_n25_rr2p5_B": "Gold daily Donchian25 RR2.5 both-side — OOS 2026 survivor",
    "O2_XAU_DON1D_n15_rr3_L": "Gold daily Donchian15 RR3 long — OOS 2026 survivor",
    "O3_XAU_ATRB1D_k035_rr5_L": "Gold daily ATR-break RR5 long — OOS 2026 survivor",
    "O4_XAU_DON4h_n40_rr2_L": "Gold 4h Donchian40 RR2 long — OOS 2026 survivor",
    "O5_XAU_DON1D_n30_rr2p5_B": "Gold daily Donchian30 RR2.5 both-side — OOS 2026 survivor",
}

# Approximate researched metrics (confirm script remeasures)
META = {
    "O1_XAU_DON1D_n25_rr2p5_B": {
        "2024": 11.37,
        "2025": 12.35,
        "2026H1_ann": 35.46,
    },
    "O2_XAU_DON1D_n15_rr3_L": {
        "2024": 23.44,
        "2025": 13.33,
        "2026H1_ann": 21.22,
    },
    "O3_XAU_ATRB1D_k035_rr5_L": {
        "2024": 10.55,
        "2025": 11.39,
        "2026H1_ann": 7.73,
    },
    "O4_XAU_DON4h_n40_rr2_L": {
        "2024": 10.94,
        "2025": 17.73,
        "2026H1_ann": 11.19,
    },
    "O5_XAU_DON1D_n30_rr2p5_B": {
        "2024": 10.9,
        "2025": 12.02,
        "2026H1_ann": 29.54,
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
