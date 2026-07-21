# S6 Equal Liquidity Fade — MT5 EA

Port of the backtested **S6_eq_liquidity_fade** strategy for MetaTrader 5.
**Strategy Tester ready** (v1.30+).

## If Strategy Tester lost money / took zero trades

Python **EURUSD-only 2024-01→2025-01** ≈ **+$18k**. Multi-pair book is larger.

| Version | Issue |
| --- | --- |
| v1.20 | Nudged limits far off equals → bad fills / losses |
| v1.30 | Skipped every “too close” equal → **0 trades** |
| **v1.31** | Exact limit → tiny stops-pad → **market if already through** |

Re-download **v1.31**, F7, Journal must say `v1.31`. On stop, Journal prints `signals= / limits= / markets= / skipped=`.

## Strategy Tester (drop-in)

1. Copy `S6_EqLiquidityFade.mq5` → `MQL5/Experts/` → **F7**
2. Tester: **EURUSD · M15 · Every tick · Deposit 100000 · 1:100**
3. Defaults: `InpTesterServerIsUTC=true`, `InpMarketIfThrough=true`, `InpMaxEntrySlipAtr=0.25`

## Live install

1. Same copy + compile.
2. Drag onto chart; enable **Algo Trading**.
3. The5ers: `InpInitialBalance=100000`; unique `InpMagic` per symbol.

## What it does

1. Closed M15 killzone: confirmed swing equals → sweep fade → H1 bias
2. **Exact** Buy/Sell limit at the equal level (skip if broker stops-level blocks it)
3. BE after +1R; flatten 20:00 UTC; daily pause / hard floor (closes all)

## Disclaimer

Past backtests ≠ live results. Broker ticks ≠ HistData.
