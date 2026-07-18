"""Unit tests for MCPT core."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from mcpt.data import generate_synthetic_ohlc
from mcpt.metrics import profit_factor, strategy_returns
from mcpt.permute import get_permutation
from mcpt.pipeline import run_insample_mcpt, run_full_pipeline
from mcpt.strategies.donchian import donchian_breakout, optimize_donchian


@pytest.fixture
def ohlc() -> pd.DataFrame:
    return generate_synthetic_ohlc(n_bars=24 * 200, seed=7)


def test_permutation_preserves_endpoints(ohlc):
    perm = get_permutation(ohlc, seed=1)
    assert perm.index.equals(ohlc.index)
    np.testing.assert_allclose(perm["open"].iloc[0], ohlc["open"].iloc[0], rtol=1e-10)
    np.testing.assert_allclose(perm["close"].iloc[-1], ohlc["close"].iloc[-1], rtol=1e-10)


def test_permutation_changes_path(ohlc):
    perm = get_permutation(ohlc, seed=2)
    # Path should differ while stats stay close
    assert not np.allclose(perm["close"].to_numpy(), ohlc["close"].to_numpy())
    real_r = np.log(ohlc["close"]).diff().dropna()
    perm_r = np.log(perm["close"]).diff().dropna()
    assert abs(real_r.std() - perm_r.std()) / real_r.std() < 0.15


def test_permutation_start_index_keeps_prefix(ohlc):
    start = 100
    perm = get_permutation(ohlc, start_index=start, seed=3)
    pd.testing.assert_frame_equal(
        perm.iloc[:start][["open", "high", "low", "close"]],
        ohlc.iloc[:start][["open", "high", "low", "close"]],
    )


def test_donchian_signal_values(ohlc):
    sig = donchian_breakout(ohlc, 20)
    assert set(sig.dropna().unique()).issubset({-1.0, 1.0})


def test_optimize_donchian_returns_pf(ohlc):
    lookback, pf = optimize_donchian(ohlc, lookback_min=12, lookback_max=30)
    assert lookback >= 12
    assert pf > 0


def test_profit_factor_basic():
    r = pd.Series([0.1, -0.05, 0.2, -0.1])
    assert profit_factor(r) == pytest.approx(0.3 / 0.15)


def test_insample_mcpt_runs(ohlc):
    def opt(df):
        return optimize_donchian(df, lookback_min=12, lookback_max=24)

    result = run_insample_mcpt(ohlc, opt, n_permutations=12, seed=1)
    assert 0 <= result.p_value <= 1
    assert len(result.perm_scores) == 11


def test_full_pipeline_donchian():
    df = generate_synthetic_ohlc(n_bars=24 * 365 * 2, seed=11)
    result = run_full_pipeline(
        df,
        strategy="donchian",
        data_source="test",
        n_insample_perms=12,
        n_walkforward_perms=8,
        train_years=1,
        lookback_min=12,
        lookback_max=24,
        run_walkforward=True,
        seed=3,
    )
    d = result.to_dict()
    assert d["insample"]["profit_factor"] > 0
    assert d["insample_mcpt"]["p_value"] is not None
    assert "verdict" in d


def test_strategy_returns_alignment(ohlc):
    sig = donchian_breakout(ohlc, 16)
    rets = strategy_returns(sig, ohlc["close"])
    assert len(rets) == len(ohlc)
