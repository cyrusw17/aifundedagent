"""Causal order-block features and confirmation signals."""

from __future__ import annotations

import numpy as np
import pandas as pd

from mcpt.forex.signals import generate_signals
from mcpt.forex.smc import build_smc_features


def _synth(n: int = 80) -> pd.DataFrame:
    idx = pd.date_range("2020-01-01", periods=n, freq="h")
    # trending up with a pullback zone
    close = np.linspace(1.10, 1.14, n) + np.sin(np.linspace(0, 6, n)) * 0.002
    open_ = np.roll(close, 1)
    open_[0] = close[0]
    high = np.maximum(open_, close) + 0.0015
    low = np.minimum(open_, close) - 0.0015
    return pd.DataFrame(
        {"open": open_, "high": high, "low": low, "close": close, "volume": 100},
        index=idx,
    )


def test_order_block_columns_present() -> None:
    f = build_smc_features(_synth())
    for col in (
        "active_bull_ob",
        "active_bear_ob",
        "touch_bull_ob",
        "touch_bear_ob",
        "touch_bull_fvg",
        "touch_bear_fvg",
    ):
        assert col in f.columns


def test_confirmation_modes_emit_int_series() -> None:
    df = _synth(200)
    for mode in ("ob_confirm", "sweep_wait_ob", "triple_confirm", "kz_ob_fvg"):
        sig, _ = generate_signals(df, mode=mode, swing_left=2, swing_right=2)
        assert len(sig) == len(df)
        assert set(np.unique(sig)).issubset({-1, 0, 1})
