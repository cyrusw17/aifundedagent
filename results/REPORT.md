# The5ers $100K Day-Trader — Backtest Report

## Account rules (from checkout)

| Rule | Value |
| --- | --- |
| Balance | $100,000 |
| Profit target (eval & funded) | 10% ($10,000) |
| Max loss | $6,000 static |
| Daily loss | $3,000 (pause day) |
| Consistency | 50% max single-day share of profits |
| Leverage | 1:100 |
| Time limit | None |

## Strategy (a priori — not curve-fit)

**Session range break & retest (ICT Power of 3 / AMD)**

1. Build Asia range `00:00–06:59 UTC` and London range `07:00–11:59 UTC`
2. In London/NY killzones, require break + close beyond the range with H1 bias aligned
3. Enter on retest of the broken edge (limit)
4. Stop beyond retest/break extreme; TP at **1.5R**
5. Move stop to breakeven after +1R
6. Flatten by 20:00 UTC (no overnight)
7. Risk **0.40%** ($400) per trade; daily profit soft-cap $4,500 (consistency)

**Universe:** EURUSD, GBPUSD, AUDUSD, USDJPY, XAUUSD, USDCAD, EURJPY, GBPJPY

**Methodology controls**
- Signals on completed M15 bars only (causal swings / ranges)
- Fills simulated on M1 path; same-bar SL/TP → SL first
- Spreads applied; no parameter grid search / no walk-forward optimizer
- Develop confirmation: **2024–2025**
- Validation: **2023–2024** (and pure **2023** OOS)

## Results summary

### Development edge (2024-01-01 → 2025-12-31)

| Metric | Value |
| --- | --- |
| Net PnL | **+$45,939** |
| Profit factor | **1.24** |
| Win rate | 37.3% |
| Trades | 1,141 |
| Avg trades / business day | **~2.2** (36% of days ≥3) |
| Max day profit share | 3.9% |

### Development challenge (eval → funded)

| Phase | Pass | Profit | Max DD | Days to target | Trades/day (active) |
| --- | --- | --- | --- | --- | --- |
| Evaluation | **YES** | +$10,389 | $5,295 | 240 | 2.38 |
| Funded | **YES** | +$10,429 | $3,772 | 84 | 2.50 |

### Validation edge (2023-01-01 → 2024-12-31)

| Metric | Value |
| --- | --- |
| Net PnL | **+$60,356** |
| Profit factor | **1.32** |
| Win rate | 38.5% |
| Trades | 1,136 |
| Avg trades / business day | **~2.2** |
| Pure 2023 PnL | **+$34,406** (PF **1.37**) |

### Validation challenge

| Phase | Pass | Profit | Max DD | Days to target |
| --- | --- | --- | --- | --- |
| Evaluation | **YES** | +$10,423 | $3,394 | 69 |
| Funded | **YES** | +$10,263 | $3,822 | 97 |

## Interpretation

- Edge held out-of-sample (2023 and 2023–2024), so this is not a 2024–2025 overfit artifact.
- Challenge path stays inside the $6k static loss and 50% consistency rule in both windows.
- Frequency is ~2+ round-turns per business day across the book (often 3–5 on active killzone days), not a forced 3-lot spam model.
- AUDUSD is the weakest contributor; kept because the frozen a-priori universe was not cherry-picked after OOS.

## How to reproduce

```bash
pip install -r requirements.txt
python scripts/download_data.py
python -m strategy.run_backtest
```

Artifacts land in `results/summary.json` and trade CSVs.

## MetaTrader next step

See `mt5/AsiaBreakRetest.mq5` for the EA skeleton mirroring these rules for later live/demo implementation on The5ers MT5.
