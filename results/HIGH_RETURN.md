# High-return champion (true The5ers static floor)

## Why this beats the ~3% floor-safe set

Earlier “floor-safe” research required **trailing max DD ≤ $6k**. That is stricter than
The5ers day-trader rules. The firm rule is a **static floor at $94,000** (never breach
$6k loss from the $100k start). After equity grows, trailing DD from peak can exceed
$6k while the account is still legal.

Unlocks used here:

1. **Static floor only** (equity always > $94k; daily $3k pause)
2. **Compound risk** — size from current equity (`risk_from_equity=True`)
3. Soft **absolute equity halt** at $94,500 (buffer above the hard floor)
4. No trailing `$6k` DD cap

## Champion

| Field | Value |
|-------|-------|
| ID | `HR_Don35_rr5_h3` |
| Logic | H1 Donchian 35, RR5, hold ≤3d, session hours |
| Risk | **0.9% of current equity** |
| Equity halt | $94,500 |
| **Simple ann (2020–25)** | **~11.9%** |
| **CAGR** | **~9.4%** |
| End equity | ~$171.6k |
| Min equity | ~$94.98k (above floor) |
| Trailing max DD | ~$118k (from peak after growth) |
| PF | ~1.07 |

Vs prior trailing-DD≤$6k best (~3% ann): **~4× higher annualized return**.

## Subperiods

| Window | Floor OK | Approx ann |
|--------|----------|------------|
| 2020–22 | yes | ~+35% (carries the edge) |
| 2023–25 | yes | flat / slightly negative |
| Full 2020–25 | yes | **~12%** |

Regime concentration is real — document it; do not hide it.

## Code

- Registry: `strategy/strategies/high_return.py`
- Confirm: `python3 scripts/confirm_high_return.py`
- Engine: `StrategyParams.risk_from_equity`, `equity_halt_floor`
- Look-ahead: unchanged (`knowable_at` required)

## Caveats

- Not the same as “max_dd ≤ $6k forever.”
- Late sample is weak; most profit is 2020–22.
- HistData ≠ The5ers broker; challenge consistency / $10k target not claimed here.
