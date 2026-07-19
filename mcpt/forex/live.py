"""Live-trading ready signal generation (causal, bar-close only).

Usage pattern for a broker bridge later:
1. On each new closed bar, append OHLC to history.
2. Call `LiveSMCEngine.on_bar(pair, bar)` → optional Signal.
3. Execute at next bar open with stop/target from signal.
Never call with partial/forming bars if you want parity with backtests.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import pandas as pd

from mcpt.forex.signals import generate_signals


@dataclass
class Signal:
    pair: str
    direction: int  # +1 long / -1 short
    bar_time: Any
    entry_ref: float  # last close; live should enter next open
    atr: float
    stop_mult: float
    rr: float
    risk_pct: float
    confluence_note: str = ""

    def stop_price(self, entry: float) -> float:
        dist = self.stop_mult * self.atr
        return entry - dist if self.direction == 1 else entry + dist

    def target_price(self, entry: float) -> float:
        dist = self.stop_mult * self.atr
        return entry + self.rr * dist if self.direction == 1 else entry - self.rr * dist

    def to_dict(self) -> dict:
        return {
            "pair": self.pair,
            "direction": self.direction,
            "bar_time": str(self.bar_time),
            "entry_ref": self.entry_ref,
            "atr": self.atr,
            "stop_mult": self.stop_mult,
            "rr": self.rr,
            "risk_pct": self.risk_pct,
            "note": self.confluence_note,
        }


@dataclass
class LiveSMCEngine:
    """Stateful multi-pair engine for live/paper trading."""

    risk_pct: float = 0.0075
    rr: float = 3.0
    atr_stop_mult: float = 1.4
    min_confluence: int = 2
    require_killzone: bool = False
    swing_left: int = 3
    swing_right: int = 3
    signal_mode: str = "smc_plus"
    history: dict[str, pd.DataFrame] = field(default_factory=dict)
    warmup_bars: int = 80

    def seed_history(self, pair: str, ohlc: pd.DataFrame) -> None:
        df = ohlc[["open", "high", "low", "close"]].copy()
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        self.history[pair] = df.sort_index()

    def on_bar(self, pair: str, bar: dict | pd.Series) -> Signal | None:
        """Ingest a *closed* bar and return a signal decided at this close (enter next open)."""
        if pair not in self.history:
            self.history[pair] = pd.DataFrame(columns=["open", "high", "low", "close"])

        row = pd.Series(bar)
        ts = pd.Timestamp(row.get("time", row.name))
        if ts.tz is not None:
            ts = ts.tz_localize(None)
        new = pd.DataFrame(
            {
                "open": [float(row["open"])],
                "high": [float(row["high"])],
                "low": [float(row["low"])],
                "close": [float(row["close"])],
            },
            index=[ts],
        )
        hist = pd.concat([self.history[pair], new])
        hist = hist[~hist.index.duplicated(keep="last")].sort_index()
        self.history[pair] = hist

        if len(hist) < self.warmup_bars:
            return None

        sig, feats = generate_signals(
            hist,
            mode=self.signal_mode,
            swing_left=self.swing_left,
            swing_right=self.swing_right,
            require_killzone=self.require_killzone,
            min_confluence=self.min_confluence,
        )
        direction = int(sig.iloc[-1])
        if direction == 0:
            return None
        atr = float(feats["atr"].iloc[-1])
        if not pd.notna(atr) or atr <= 0:
            return None
        return Signal(
            pair=pair,
            direction=direction,
            bar_time=hist.index[-1],
            entry_ref=float(hist["close"].iloc[-1]),
            atr=atr,
            stop_mult=self.atr_stop_mult,
            rr=self.rr,
            risk_pct=self.risk_pct,
            confluence_note=f"{self.signal_mode}_confluence",
        )
