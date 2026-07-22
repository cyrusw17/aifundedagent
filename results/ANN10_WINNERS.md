# Five strategies above 10% annual return (causal)

**Window:** 2020-01-01 → 2025-12-31 (6 years).
**Metric:** simple annualized return = total PnL / $100k / 6.
**Fills:** no look-ahead (`knowable_at` = bar close).

| # | Strategy | Full ann | CAGR | PF | Trades | Max DD | 2020-22 ann | 2023-25 ann |
|---|----------|----------|------|----|--------|--------|-------------|-------------|
| 1 | **A1_H1Don_n35_rr5** | **14.3%** | 10.9% | 1.094 | 1172 | $97,642 | 35.0% | -6.5% |
| 2 | **A2_H1Don_n30_rr4** | **13.1%** | 10.1% | 1.1 | 1219 | $62,636 | 22.0% | 3.9% |
| 3 | **A3_H1Don_n40_rr4** | **10.9%** | 8.8% | 1.073 | 1177 | $87,282 | 19.3% | 2.4% |
| 4 | **A4_ICT_MSB_PA** | **11.2%** | 8.9% | 1.138 | 996 | $32,810 | -2.3% | 24.6% |
| 5 | **A5_ICT_MSB_ASIA** | **10.2%** | 8.2% | 1.174 | 666 | $23,387 | 6.1% | 14.2% |

## What they are

1. **A1–A3** — H1 Donchian breakouts (session 07–17 UTC), multi-day hold ≤3, ATR stop.
2. **A4–A5** — ICT multi Silver Bullet (07–08 + 14–15 + 15–16 UTC) → FVG CE, risk 2%.

Registry: `strategy/strategies/ann10_winners.py`

## Caveats

- Full-sample average >10%; **subperiods diverge** (H1 strong 2020–22 / weak 2023–25; ICT often the reverse).
- Drawdowns can exceed **$60k–$90k** on $100k — not The5ers floor-safe.
- Causal fills only; HistData ≠ live broker.

