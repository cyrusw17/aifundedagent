"""Fixed a-priori parameters for The5ers $100K day trader.

No grid search / walk-forward optimization. Values come from ICT/SMC doctrine
and prop-firm risk geometry, chosen before evaluating 2024-2025 results.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Tuple


@dataclass(frozen=True)
class PropRules:
    initial_balance: float = 100_000.0
    profit_target: float = 10_000.0  # 10%
    max_loss: float = 6_000.0  # static floor at 94_000
    daily_loss_limit: float = 3_000.0  # pause rest of day
    consistency_pct: float = 0.50  # no single day > 50% of total profit toward target
    leverage: int = 100
    # Funded payouts (informational)
    withdraw_target: float = 250.0
    withdraw_cap: float = 2_000.0


@dataclass(frozen=True)
class StrategyParams:
    """ICT Sweep -> MSS -> FVG day model. Frozen — do not tune on sample."""

    # Structure (M15)
    swing_left: int = 3
    swing_right: int = 3
    atr_period: int = 14
    min_stop_atr: float = 0.8
    max_stop_atr: float = 2.2
    mss_confirm_bars: int = 8  # bars after sweep to confirm MSS
    fvg_max_age_bars: int = 8
    min_fvg_atr_frac: float = 0.12  # ignore tiny gaps

    # Sessions in UTC (HistData EST/UTC-5 converted +5h)
    # London KZ ~07:00-11:00 UTC, NY AM ~12:00-17:00 UTC
    killzones_utc: Tuple[Tuple[int, int], ...] = (
        (7, 11),
        (12, 17),
    )
    flatten_hour_utc: int = 20  # no overnight holds

    # Trade management
    reward_risk: float = 1.5  # classic range-break day target
    risk_pct: float = 0.0040  # 0.40% = $400
    max_trades_per_day: int = 10
    max_open_positions: int = 3
    max_trades_per_pair_day: int = 3
    daily_profit_cap: float = 4_500.0  # soft cap for 50% consistency vs $10k target
    cooldown_bars_after_trade: int = 1  # M15 bars

    # Costs (round-turn approx in price units applied at entry)
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

    # Contract sizes for PnL
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

    # Liquid ICT day-trade universe
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

# Periods — development confirmation vs validation (no refit after OOS)
DEV_PERIOD = ("2024-01-01", "2025-12-31")
VAL_PERIOD = ("2023-01-01", "2024-12-31")
PURE_OOS = ("2023-01-01", "2023-12-31")

DATA_DIR = "data/raw"
RESULTS_DIR = "results"
