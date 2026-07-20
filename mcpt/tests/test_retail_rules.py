"""Retail $1k rules + peak DD kill."""

from mcpt.forex.account import retail_rules, PropAccount


def test_retail_rules_floor_and_dd():
    rules = retail_rules(initial_balance=1000, leverage=50, max_dd_pct=0.20)
    assert rules.initial_balance == 1000
    assert rules.leverage == 50
    assert rules.floor_balance == 800
    assert rules.max_dd_pct == 0.20

    acct = PropAccount(rules=rules)
    acct.mark_equity(1200)  # new peak
    assert not acct.blown
    acct.mark_equity(960)  # 20% off peak exactly
    assert acct.blown
    assert acct.blow_reason == "max_dd"


def test_retail_floor_from_initial():
    rules = retail_rules()
    acct = PropAccount(rules=rules)
    acct.realize_pnl(-200, "2024-01-01")
    assert acct.blown
    assert acct.blow_reason == "max_loss"
