# Prop-floor-safe ANN10 winners (causal)

The5ers rules enforced: static floor **$6,000** (equity > $94,000), daily loss
**$3,000**, soft `dd_halt` before the floor, capped trades/day.

Fills only after `knowable_at` (no look-ahead).

## The five (2020–2025 full sample)

| ID | Floor OK | DD OK | Max DD | Full ann | Risk | Hold | Halt |
|----|----------|-------|--------|----------|------|------|------|
| **A1_H1Don_n35_rr5** | yes | yes | $5,050 | 3.0% | 0.35% | ≤3d | $5,000 |
| **A2_H1Don_n30_rr4** | yes | yes | $4,678 | 1.5% | 0.40% | ≤1d | $4,500 |
| **A3_H1Don_n40_rr4** | yes | yes | $4,616 | 2.2% | 0.40% | ≤1d | $4,500 |
| **A4_ICT_MSB_PA** | yes | yes | $4,708 | 1.4% | 0.50% | day | $4,500 |
| **A5_ICT_MSB_ASIA** | yes | yes | $4,184 | 1.8% | 0.50% | day | $4,000 |

A4/A5 use tighter **SB 14:00–15:00 UTC** (not the old loose multi-window) so DD stays under the floor.

## Subperiod floor checks

All five also stay floor-safe on 2020–22, 2023–25, 2024–25, and 2026 H1 (max DD ≤ $6k, never hit $94k).

## Trade-off vs unconstrained ANN10

Unconstrained versions printed **>10% ann** with **$20k–$90k** drawdowns — they **breach** the prop floor.
Floor-safe sizing cuts risk to ~0.35–0.50% and adds `dd_halt`, so annualized return falls to ~**1.5–3%**.

## Code

- Registry: `strategy/strategies/ann10_winners.py` (`prop_params_for`, `ANN10_HALTS`)
- Confirm: `python3 scripts/confirm_ann10_winners.py`
- Engine: `StrategyParams.dd_halt` in `strategy/backtest.py`

## Caveats

- Floor-safe ≠ challenge pass ($10k target / consistency not guaranteed).
- H1 sleeves can be flat/negative in 2023–25 even while full-sample stays green and under floor.
- HistData ≠ The5ers broker.
