# S6 Equal Liquidity Fade — MT5 EA

Port of the backtested **S6_eq_liquidity_fade** strategy for MetaTrader 5.

## Install

1. Open **MetaEditor** (F4 from MT5).
2. Menu: **File → Open Data Folder**.
3. Go to `MQL5/Experts/`.
4. Copy `S6_EqLiquidityFade.mq5` into that folder.
5. In MetaEditor, open the file → press **F7** (Compile).
6. In MT5 Navigator → Expert Advisors → drag **S6_EqLiquidityFade** onto a chart.

## Chart setup

- Any symbol you want to trade (start with **EURUSD**).
- Chart timeframe can be anything; the EA reads **M15 + H1** internally.
- Enable **Algo Trading** (toolbar) and allow trading in EA properties.
- One chart = one symbol. For a multi-pair book, attach the EA to each symbol chart (unique magic optional).

## Critical settings (match backtest)

| Input | Recommended | Notes |
| --- | --- | --- |
| `InpUseGMT` | **true** | Killzones use UTC like the research backtest |
| `InpKZ1Start/End` | 7 / 11 | London window UTC |
| `InpKZ2Start/End` | 12 / 17 | NY window UTC |
| `InpFlattenHourUTC` | 20 | Flat before late session |
| `InpRiskPercent` | 0.40 | 0.4% of initial balance |
| `InpRewardRisk` | 1.5 | TP distance |
| `InpInitialBalance` | 100000 or 0 | 0 = capture on attach; for prop use **100000** |
| `InpDailyLossLimitPct` | 3.0 | Day pause |
| `InpMaxLossPct` | 6.0 | Hard floor vs initial |
| `InpMagic` | unique per chart | Avoid collisions |

If your broker server is not GMT and `InpUseGMT=false`, set `InpServerToUtcOffset` so that `server + offset = UTC`.

## What it does

1. On each **closed M15** bar in a killzone:
   - Finds confirmed swing equals (tolerance 0.15 ATR)
   - Looks for a sweep beyond equals that closes back inside
   - Filters with H1 structure bias
2. Places a **limit** at the equal level, SL beyond sweep, TP = 1.5R
3. Moves SL to breakeven after +1R
4. Flattens from 20:00 UTC
5. Pauses on daily loss / hard max-loss floor

## Demo checklist before The5ers eval

1. Run on demo 1–2 weeks.
2. Journal: signal time, limit, fill, slippage vs backtest.
3. Confirm killzone hours vs UTC (print logs).
4. Confirm lot sizing risk ≈ 0.4% of $100k.
5. Only then attach to evaluation.

## Disclaimer

Past backtests ≠ live results. You are responsible for prop-firm rules, news risk, and compliance.
