"""Prop / funded account rules from The5ers challenge card + retail helper."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class FundedRules:
    """Rules matching the challenge checkout card (100K) — also usable for retail."""

    initial_balance: float = 100_000.0
    profit_target_pct: float = 0.10  # evaluation 10%
    max_loss: float = 6_000.0  # absolute from initial
    daily_loss_pct: float = 0.03  # 3% of initial ($3,000)
    consistency_pct: float = 0.50  # best day <= 50% of profits
    leverage: int = 100
    withdraw_min: float = 250.0
    withdraw_cap: float = 2_000.0  # per weekly withdraw
    # User operating rule: withdraw equity above initial at week end
    weekly_withdraw_above_initial: bool = True
    # Optional peak-to-trough drawdown kill (e.g. 0.20 = 20%). None = disabled.
    max_dd_pct: float | None = None

    @property
    def daily_loss_limit(self) -> float:
        return self.initial_balance * self.daily_loss_pct

    @property
    def floor_balance(self) -> float:
        return self.initial_balance - self.max_loss

    @property
    def evaluation_target(self) -> float:
        return self.initial_balance * (1.0 + self.profit_target_pct)


def retail_rules(
    *,
    initial_balance: float = 1_000.0,
    leverage: int = 50,
    max_dd_pct: float = 0.20,
    daily_loss_pct: float = 0.10,
) -> FundedRules:
    """$1k-style retail book: 50:1 leverage, hard 20% DD floor from initial + peak DD kill."""
    max_loss = initial_balance * max_dd_pct
    return FundedRules(
        initial_balance=initial_balance,
        profit_target_pct=0.20,  # soft growth target for reporting only
        max_loss=max_loss,
        daily_loss_pct=daily_loss_pct,
        consistency_pct=1.0,  # not a prop consistency gate
        leverage=leverage,
        withdraw_min=1e12,  # effectively disable weekly withdraw
        withdraw_cap=0.0,
        weekly_withdraw_above_initial=False,
        max_dd_pct=max_dd_pct,
    )


@dataclass
class PropAccount:
    """Tracks balance/equity under funded rules. No look-ahead — bar-close updates only."""

    rules: FundedRules = field(default_factory=FundedRules)
    balance: float = 100_000.0
    equity: float = 100_000.0
    day_start_equity: float = 100_000.0
    peak_equity: float = 100_000.0
    blown: bool = False
    blow_reason: str = ""
    daily_pnl: dict = field(default_factory=dict)  # date -> closed pnl
    withdrawals: list = field(default_factory=list)
    total_withdrawn: float = 0.0

    def __post_init__(self) -> None:
        self.balance = self.rules.initial_balance
        self.equity = self.rules.initial_balance
        self.day_start_equity = self.rules.initial_balance
        self.peak_equity = self.rules.initial_balance

    def new_day(self, date) -> None:
        self.day_start_equity = self.equity

    def mark_equity(self, equity: float) -> None:
        self.equity = equity
        self.peak_equity = max(self.peak_equity, equity)
        self._check_limits()

    def realize_pnl(self, pnl: float, date) -> None:
        self.balance += pnl
        self.equity = self.balance
        self.daily_pnl[date] = self.daily_pnl.get(date, 0.0) + pnl
        self.peak_equity = max(self.peak_equity, self.equity)
        self._check_limits()

    def _check_limits(self) -> None:
        if self.blown:
            return
        if self.equity <= self.rules.floor_balance:
            self.blown = True
            self.blow_reason = "max_loss"
            return
        if self.rules.max_dd_pct is not None and self.peak_equity > 0:
            dd = (self.peak_equity - self.equity) / self.peak_equity
            if dd >= self.rules.max_dd_pct - 1e-12:
                self.blown = True
                self.blow_reason = "max_dd"
                return
        day_loss = self.day_start_equity - self.equity
        if day_loss >= self.rules.daily_loss_limit:
            self.blown = True
            self.blow_reason = "daily_loss"

    def weekly_withdraw(self, week_end_date) -> float:
        """Withdraw equity above initial, capped per rules."""
        if not self.rules.weekly_withdraw_above_initial:
            return 0.0
        excess = self.balance - self.rules.initial_balance
        if excess < self.rules.withdraw_min:
            return 0.0
        amount = min(excess, self.rules.withdraw_cap)
        self.balance -= amount
        self.equity = self.balance
        self.total_withdrawn += amount
        self.withdrawals.append({"date": week_end_date, "amount": amount})
        return amount

    def consistency_ok(self) -> bool:
        profits = [v for v in self.daily_pnl.values() if v > 0]
        total = sum(profits)
        if total <= 0:
            return True
        return max(profits) <= total * self.rules.consistency_pct

    def hit_profit_target(self) -> bool:
        # Include withdrawn profits for funded performance; evaluation uses balance/equity
        return self.equity >= self.rules.evaluation_target or (
            self.balance + self.total_withdrawn >= self.rules.evaluation_target
        )
