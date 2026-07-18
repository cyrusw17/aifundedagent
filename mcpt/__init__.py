"""Monte Carlo Permutation Test (MCPT) trading strategy tester.

Based on neurotrader888/mcpt and the four-step strategy development
process: in-sample excellence → in-sample MCPT → walk-forward →
walk-forward MCPT.
"""

from mcpt.metrics import profit_factor, sharpe_ratio, strategy_returns
from mcpt.permute import get_permutation
from mcpt.pipeline import run_insample_mcpt, run_walkforward_mcpt, run_full_pipeline

__all__ = [
    "get_permutation",
    "profit_factor",
    "sharpe_ratio",
    "strategy_returns",
    "run_insample_mcpt",
    "run_walkforward_mcpt",
    "run_full_pipeline",
]

__version__ = "1.0.0"
