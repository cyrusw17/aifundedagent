"""Built-in strategies for MCPT testing."""

from mcpt.strategies.donchian import (
    donchian_breakout,
    optimize_donchian,
    walkforward_donchian,
)
from mcpt.strategies.moving_average import ma_crossover, optimize_ma_crossover
from mcpt.strategies.tree import train_tree, tree_strategy

STRATEGY_REGISTRY = {
    "donchian": {
        "name": "Donchian Breakout",
        "description": "Long on close breakout above lookback high; short below lookback low.",
        "optimize": optimize_donchian,
        "signal": donchian_breakout,
        "walkforward": walkforward_donchian,
        "param_name": "lookback",
    },
    "ma_crossover": {
        "name": "Moving Average Crossover",
        "description": "Long when fast MA > slow MA; flat otherwise.",
        "optimize": optimize_ma_crossover,
        "signal": None,
        "walkforward": None,
        "param_name": "fast/slow",
    },
    "tree": {
        "name": "Decision Tree (overfit demo)",
        "description": "Intentionally overfit classifier — fails in-sample MCPT.",
        "optimize": None,
        "signal": None,
        "walkforward": None,
        "param_name": None,
    },
}

__all__ = [
    "STRATEGY_REGISTRY",
    "donchian_breakout",
    "optimize_donchian",
    "walkforward_donchian",
    "ma_crossover",
    "optimize_ma_crossover",
    "train_tree",
    "tree_strategy",
]
