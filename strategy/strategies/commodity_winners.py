"""Five commodity winners (gold/silver) — no 2026+ data used in research.

Gates (calendar years, simple ann on $100k, static floor, causal fills):
- 2024 >= 10%, 2025 >= 10%
- 2023 >= 0%
- no year 2021-2025 < -8%
- PF(2024-2025) >= 1.05

All long-biased Donchian breakouts on commodity CFDs (distinct TF / length / universe).
"""

from __future__ import annotations

from dataclasses import replace
from typing import Callable, Dict, List, Tuple

from ..config import PARAMS, StrategyParams
from .commodity_models import CmdCfg, make_cmd_fn

# (id, pairs, cfg, risk_pct)
_SPECS: List[Tuple[str, Tuple[str, ...], CmdCfg, float]] = [
    (
        "C1_XAU_DON4h_n30_rr5",
        ("XAUUSD",),
        CmdCfg(
            tag="C1_XAU_DON4h_n30_rr5",
            model="don",
            tf="4h",
            don_len=30,
            rr=5.0,
            long_only=True,
            max_hold_days=5,
            session_only=True,
            stop_atr=2.0,
        ),
        0.02,
    ),
    (
        "C2_XAU_DON4h_n20_rr5",
        ("XAUUSD",),
        CmdCfg(
            tag="C2_XAU_DON4h_n20_rr5",
            model="don",
            tf="4h",
            don_len=20,
            rr=5.0,
            long_only=True,
            max_hold_days=5,
            session_only=True,
            stop_atr=2.0,
        ),
        0.015,
    ),
    (
        "C3_XAU_DON1D_n20_rr4",
        ("XAUUSD",),
        CmdCfg(
            tag="C3_XAU_DON1D_n20_rr4",
            model="don",
            tf="1D",
            don_len=20,
            rr=4.0,
            long_only=True,
            max_hold_days=10,
            session_only=False,
            stop_atr=2.0,
        ),
        0.02,
    ),
    (
        "C4_XAUXAG_DON4h_n20_rr5",
        ("XAUUSD", "XAGUSD"),
        CmdCfg(
            tag="C4_XAUXAG_DON4h_n20_rr5",
            model="don",
            tf="4h",
            don_len=20,
            rr=5.0,
            long_only=True,
            max_hold_days=5,
            session_only=True,
            stop_atr=2.0,
        ),
        0.01,
    ),
    (
        "C5_XAU_DON4h_n20_rr4",
        ("XAUUSD",),
        CmdCfg(
            tag="C5_XAU_DON4h_n20_rr4",
            model="don",
            tf="4h",
            don_len=20,
            rr=4.0,
            long_only=True,
            max_hold_days=5,
            session_only=True,
            stop_atr=2.0,
        ),
        0.015,
    ),
]

PAIRS: Dict[str, Tuple[str, ...]] = {i: p for i, p, _, _ in _SPECS}
CFGS: Dict[str, CmdCfg] = {i: c for i, _, c, _ in _SPECS}
RISKS: Dict[str, float] = {i: r for i, _, _, r in _SPECS}
HOLDS: Dict[str, int] = {i: c.max_hold_days for i, _, c, _ in _SPECS}

STRATEGIES: Dict[str, Callable] = {i: make_cmd_fn(c) for i, _, c, _ in _SPECS}

STRATEGY_DESC = {
    "C1_XAU_DON4h_n30_rr5": "Gold 4h Donchian30 RR5 long-only, risk 2% equity — ~28%/35% in 2024/25",
    "C2_XAU_DON4h_n20_rr5": "Gold 4h Donchian20 RR5 long-only, risk 1.5% — ~16%/31% in 2024/25",
    "C3_XAU_DON1D_n20_rr4": "Gold daily Donchian20 RR4 long-only, risk 2% — ~16%/13% in 2024/25",
    "C4_XAUXAG_DON4h_n20_rr5": "Gold+Silver 4h Donchian20 RR5 long-only, risk 1% — ~12%/13% in 2024/25",
    "C5_XAU_DON4h_n20_rr4": "Gold 4h Donchian20 RR4 long-only, risk 1.5% — ~14%/31% in 2024/25",
}

# Approximate researched yearly anns (confirm script remeasures)
META = {
    "C1_XAU_DON4h_n30_rr5": {"2021": -5.86, "2022": 0.2, "2023": 9.17, "2024": 28.29, "2025": 35.11},
    "C2_XAU_DON4h_n20_rr5": {"2021": -5.85, "2022": -2.81, "2023": 2.2, "2024": 15.89, "2025": 31.27},
    "C3_XAU_DON1D_n20_rr4": {"2021": 0.96, "2022": -3.53, "2023": 3.71, "2024": 16.15, "2025": 13.29},
    "C4_XAUXAG_DON4h_n20_rr5": {"2021": -5.38, "2022": 4.86, "2023": 2.31, "2024": 12.24, "2025": 12.88},
    "C5_XAU_DON4h_n20_rr4": {"2021": -5.85, "2022": -1.57, "2023": 2.03, "2024": 14.26, "2025": 31.27},
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
