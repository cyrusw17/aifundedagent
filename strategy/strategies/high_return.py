"""High-return champion under true The5ers static floor (equity > $94k).

Uses compound risk (risk_from_equity) and a soft absolute equity halt.
Trailing max DD from peak may exceed $6k after equity grows — that is allowed
under static-floor rules (unlike the prior trailing-DD≤$6k research).

Champion: H1 Donchian 35 / RR5 / hold≤3d @ 0.9% of equity.
2020–2025: ~12% simple ann, ~9.4% CAGR, min equity still above $94k.
"""

from __future__ import annotations

from dataclasses import replace
from typing import Callable, Dict

from ..config import PARAMS, StrategyParams
from .h1_models import H1Cfg, make_fn as make_h1

CHAMPION_ID = "HR_Don35_rr5_h3"

CHAMPION_CFG = H1Cfg(
    tag=CHAMPION_ID,
    model="don_h1",
    rr=5.0,
    don_len=35,
    max_hold_days=3,
    stop_atr=2.0,
    session_only=True,
    risk_pct=0.009,
    flatten_hour_utc=22,
    move_to_be=False,
)

# Soft halt: pause new trades at $94,500 (buffer above $94k static floor)
EQUITY_HALT_FLOOR = 94_500.0
RISK_PCT = 0.009
DD_HALT = 0.0  # trailing halt off — static floor + abs equity halt only

STRATEGIES: Dict[str, Callable] = {
    CHAMPION_ID: make_h1(CHAMPION_CFG),
}

STRATEGY_DESC = {
    CHAMPION_ID: (
        "H1 Donchian 35 RR5 hold≤3d, 0.9% compound risk, equity halt $94.5k — "
        "~12% simple ann 2020-25 under static floor"
    ),
}

META = {
    CHAMPION_ID: {
        "simple_ann_pct": 11.94,
        "cagr_pct": 9.42,
        "max_dd": 118339.0,
        "min_equity": 94977.0,
        "end_equity": 171614.0,
        "pf": 1.069,
        "risk_pct": RISK_PCT,
        "equity_halt_floor": EQUITY_HALT_FLOOR,
        "note": "Late 2023-25 flat/slightly negative but floor-safe; early 2020-22 carries return.",
    }
}


def prop_params_for(name: str = CHAMPION_ID) -> StrategyParams:
    if name != CHAMPION_ID:
        raise KeyError(name)
    return replace(
        PARAMS,
        risk_pct=RISK_PCT,
        max_hold_days=CHAMPION_CFG.max_hold_days,
        dd_halt=DD_HALT,
        flatten_hour_utc=22,
        move_to_be=False,
        daily_profit_cap=5_000.0,
        max_trades_per_day=6,
        max_trades_per_pair_day=2,
        max_open_positions=2,
        cooldown_bars_after_trade=0,
        risk_from_equity=True,
        equity_halt_floor=EQUITY_HALT_FLOOR,
    )
