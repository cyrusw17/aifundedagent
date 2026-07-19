"""Live-trading ready signal generation (causal, bar-close only).

Usage pattern for a broker bridge:
1. On each new closed bar, append OHLC to history.
2. Call `LiveSMCEngine.on_bar(pair, bar)` → optional Signal.
3. Ask `FundedRiskGuard.allow_entry(...)` before sending the order.
4. Execute at next bar open with stop/target from signal.

Never call with partial/forming bars if you want parity with backtests.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any

import pandas as pd

from mcpt.forex.account import FundedRules
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
class FundedRiskGuard:
    """Mirrors backtest risk overlays for live/paper trading."""

    rules: FundedRules = field(default_factory=FundedRules)
    risk_pct: float = 0.0075
    max_positions: int = 1
    one_entry_per_day: bool = True
    skip_mondays: bool = True
    daily_halt_loss_pct: float = 0.02
    daily_halt_profit_pct: float = 0.03
    cooldown_losses: int = 2
    open_positions: int = 0
    day_pnl: float = 0.0
    day_date: date | None = None
    entries_today: int = 0
    consecutive_losses: int = 0
    equity: float = 100_000.0
    peak_equity: float = 100_000.0
    halted_today: bool = False
    last_reject: str = ""

    def _roll_day(self, when: datetime | date | pd.Timestamp) -> None:
        d = pd.Timestamp(when).date()
        if self.day_date != d:
            self.day_date = d
            self.day_pnl = 0.0
            self.entries_today = 0
            self.halted_today = False

    def on_fill_pnl(self, pnl: float, when: datetime | date | pd.Timestamp) -> None:
        self._roll_day(when)
        self.day_pnl += pnl
        self.equity += pnl
        self.peak_equity = max(self.peak_equity, self.equity)
        if pnl < 0:
            self.consecutive_losses += 1
        elif pnl > 0:
            self.consecutive_losses = 0
        start_eq = self.equity - self.day_pnl
        if start_eq > 0:
            if self.day_pnl <= -self.daily_halt_loss_pct * start_eq:
                self.halted_today = True
            if self.day_pnl >= self.daily_halt_profit_pct * start_eq:
                self.halted_today = True

    def on_position_opened(self) -> None:
        self.open_positions += 1
        self.entries_today += 1

    def on_position_closed(self) -> None:
        self.open_positions = max(0, self.open_positions - 1)

    def allow_entry(self, when: datetime | date | pd.Timestamp, risk_usd: float | None = None) -> bool:
        self._roll_day(when)
        ts = pd.Timestamp(when)
        if self.skip_mondays and ts.weekday() == 0:
            self.last_reject = "skip_monday"
            return False
        if self.halted_today:
            self.last_reject = "daily_halt"
            return False
        if self.open_positions >= self.max_positions:
            self.last_reject = "max_positions"
            return False
        if self.one_entry_per_day and self.entries_today >= 1:
            self.last_reject = "one_entry_per_day"
            return False
        if self.cooldown_losses and self.consecutive_losses >= self.cooldown_losses:
            self.last_reject = "cooldown_losses"
            return False
        # max loss / daily loss headroom vs rules
        floor = self.rules.floor_balance
        if self.equity <= floor:
            self.last_reject = "max_loss_floor"
            return False
        risk = risk_usd if risk_usd is not None else self.equity * self.risk_pct
        # keep a buffer so a stop-out cannot pierce the hard floor
        if self.equity - risk < floor:
            self.last_reject = "risk_exceeds_floor_headroom"
            return False
        # daily loss is absolute vs initial (card: 3% of $100k)
        if -self.day_pnl + risk > self.rules.daily_loss_limit:
            self.last_reject = "risk_exceeds_daily_headroom"
            return False
        self.last_reject = ""
        return True

    def position_risk_usd(self) -> float:
        floor = self.rules.floor_balance
        nominal = self.equity * self.risk_pct
        headroom = max(0.0, self.equity - floor - 1.0)
        day_headroom = max(0.0, self.rules.daily_loss_limit + self.day_pnl - 1.0)
        return min(nominal, headroom, day_headroom)


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
    guard: FundedRiskGuard | None = None

    def ensure_guard(self) -> FundedRiskGuard:
        if self.guard is None:
            self.guard = FundedRiskGuard(risk_pct=self.risk_pct)
        return self.guard

    def seed_history(self, pair: str, ohlc: pd.DataFrame) -> None:
        df = ohlc[["open", "high", "low", "close"]].copy()
        df.index = pd.to_datetime(df.index)
        if df.index.tz is not None:
            df.index = df.index.tz_localize(None)
        self.history[pair] = df.sort_index()

    def on_bar(self, pair: str, bar: dict | pd.Series, *, check_risk: bool = False) -> Signal | None:
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
        signal = Signal(
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
        if check_risk:
            g = self.ensure_guard()
            if not g.allow_entry(hist.index[-1], g.position_risk_usd()):
                return None
        return signal
