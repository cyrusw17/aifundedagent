"""Fixed a-priori parameters for The5ers $100K day trader."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Tuple


@dataclass(frozen=True)
class PropRules:
    initial_balance: float = 100_000.0
    profit_target: float = 10_000.0  # 10%
    max_loss: float = 6_000.0  # static floor at 94_000
    daily_loss_limit: float = 3_000.0  # pause rest of day
    consistency_pct: float = 0.50
    leverage: int = 100
    # Funded: keep $101k on account; withdraw excess each week end
    funded_retain: float = 101_000.0
    min_weekly_withdraw: float = 250.0  # skip dust < firm min target
    withdraw_cap: float = 2_000.0  # per-week cap from checkout sheet


@dataclass(frozen=True)
class StrategyParams:
    swing_left: int = 3
    swing_right: int = 3
    atr_period: int = 14
    min_stop_atr: float = 0.8
    max_stop_atr: float = 2.2
    mss_confirm_bars: int = 8
    fvg_max_age_bars: int = 8
    min_fvg_atr_frac: float = 0.12

    killzones_utc: Tuple[Tuple[int, int], ...] = (
        (7, 11),
        (12, 17),
    )
    flatten_hour_utc: int = 20

    reward_risk: float = 1.5  # default; strategies may override per signal
    risk_pct: float = 0.0040
    max_trades_per_day: int = 10
    max_open_positions: int = 3
    max_trades_per_pair_day: int = 3
    daily_profit_cap: float = 4_500.0
    cooldown_bars_after_trade: int = 1
    move_to_be: bool = True  # False = let TP/SL/flatten manage (no early BE)
    # 0 = day-trader mode (flatten same/next session day). >0 = hold up to N calendar days.
    max_hold_days: int = 0

    spreads: Dict[str, float] = field(
        default_factory=lambda: {
            "EURUSD": 0.00012,
            "GBPUSD": 0.00015,
            "USDJPY": 0.015,
            "XAUUSD": 0.25,
            "AUDUSD": 0.00014,
            "USDCAD": 0.00016,
            "EURJPY": 0.018,
            "GBPJPY": 0.025,
        }
    )

    contract_sizes: Dict[str, float] = field(
        default_factory=lambda: {
            "EURUSD": 100_000.0,
            "GBPUSD": 100_000.0,
            "USDJPY": 100_000.0,
            "XAUUSD": 100.0,
            "AUDUSD": 100_000.0,
            "USDCAD": 100_000.0,
            "EURJPY": 100_000.0,
            "GBPJPY": 100_000.0,
        }
    )

    pairs: Tuple[str, ...] = (
        "EURUSD",
        "GBPUSD",
        "AUDUSD",
        "USDJPY",
        "XAUUSD",
        "USDCAD",
        "EURJPY",
        "GBPJPY",
    )


PROP = PropRules()
PARAMS = StrategyParams()

DEV_PERIOD = ("2024-01-01", "2025-12-31")
VAL_PERIOD = ("2023-01-01", "2024-12-31")
PURE_OOS = ("2023-01-01", "2023-12-31")
HOLD_2026 = ("2026-01-01", "2026-06-30")

DATA_DIR = "data/raw"
RESULTS_DIR = "results"
