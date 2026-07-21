"""Intentionally overfit decision-tree strategy (fails in-sample MCPT)."""

from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.tree import DecisionTreeClassifier

from mcpt.metrics import profit_factor


def train_tree(ohlc: pd.DataFrame, min_samples_leaf: int = 5) -> DecisionTreeClassifier:
    log_c = np.log(ohlc["close"])
    diff6 = log_c.diff(6)
    diff24 = log_c.diff(24)
    diff168 = log_c.diff(168)
    target = np.sign(log_c.diff(24).shift(-24))
    target = (target + 1) / 2

    dataset = pd.concat([diff6, diff24, diff168, target], axis=1)
    dataset.columns = ["diff6", "diff24", "diff168", "target"]
    train_data = dataset.dropna()
    train_x = train_data[["diff6", "diff24", "diff168"]].to_numpy()
    train_y = train_data["target"].astype(int).to_numpy()

    model = DecisionTreeClassifier(min_samples_leaf=min_samples_leaf, random_state=69)
    model.fit(train_x, train_y)
    return model


def tree_strategy(
    ohlc: pd.DataFrame, model: DecisionTreeClassifier
) -> tuple[pd.Series, float]:
    log_c = np.log(ohlc["close"])
    dataset = pd.concat(
        [log_c.diff(6), log_c.diff(24), log_c.diff(168)], axis=1
    )
    dataset.columns = ["diff6", "diff24", "diff168"]
    dataset = dataset.dropna()

    pred = pd.Series(model.predict(dataset.to_numpy()), index=dataset.index)
    pred = pred.reindex(ohlc.index)
    signal = pd.Series(np.where(pred > 0, 1, -1), index=ohlc.index, dtype=float)

    r = log_c.diff().shift(-1)
    rets = signal * r
    return signal, profit_factor(rets)
