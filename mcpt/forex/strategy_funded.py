"""Locked funded-challenge strategy config + helpers for live trading.

Default parameters come from MCPT-validated research
(`data/research/best_strategy.json`). Signals are causal (bar close → next open).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from mcpt.forex.account import FundedRules
from mcpt.forex.live import LiveSMCEngine, Signal

ROOT = Path(__file__).resolve().parents[2]
BEST_PATH = ROOT / "data" / "research" / "best_strategy.json"

# Fallback if research artifact missing
DEFAULT_PARAMS: dict[str, Any] = {
    "signal_mode": "smc_plus",
    "risk_pct": 0.0075,
    "rr": 3.0,
    "atr_stop_mult": 1.4,
    "max_positions": 1,
    "min_confluence": 2,
    "swing_left": 3,
    "swing_right": 3,
    "require_killzone": False,
    "weekly_withdraw": True,
    "move_be_at_r": 0.0,
    "skip_mondays": True,
    "daily_halt_loss_pct": 0.02,
    "daily_halt_profit_pct": 0.03,
    "cooldown_losses": 2,
    "one_entry_per_day": True,
}

DEFAULT_PAIRS = ["EURUSD", "USDJPY", "USDCHF", "AUDUSD"]


def load_best() -> dict[str, Any]:
    if BEST_PATH.exists():
        return json.loads(BEST_PATH.read_text())
    return {
        "pairset": "majors4",
        "pairs": DEFAULT_PAIRS,
        "params": DEFAULT_PARAMS,
        "mcpt_pass": None,
    }


def make_live_engine(params: dict[str, Any] | None = None) -> LiveSMCEngine:
    p = dict(DEFAULT_PARAMS)
    if params:
        p.update(params)
    return LiveSMCEngine(
        risk_pct=float(p["risk_pct"]),
        rr=float(p["rr"]),
        atr_stop_mult=float(p["atr_stop_mult"]),
        min_confluence=int(p.get("min_confluence", 2)),
        require_killzone=bool(p.get("require_killzone", False)),
        swing_left=int(p.get("swing_left", 3)),
        swing_right=int(p.get("swing_right", 3)),
        signal_mode=str(p.get("signal_mode", "smc_plus")),
    )


def funded_rules() -> FundedRules:
    return FundedRules()


def position_risk_usd(equity: float, params: dict[str, Any] | None = None) -> float:
    p = params or load_best().get("params", DEFAULT_PARAMS)
    return equity * float(p["risk_pct"])


__all__ = [
    "DEFAULT_PARAMS",
    "DEFAULT_PAIRS",
    "load_best",
    "make_live_engine",
    "funded_rules",
    "position_risk_usd",
    "Signal",
]
