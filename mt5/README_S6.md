# S6 Equal Liquidity Fade — MT5 EA

Port of the backtested **S6_eq_liquidity_fade** strategy for MetaTrader 5.
**Strategy Tester ready** (v1.20+).

## Strategy Tester (drop-in)

1. Open **MetaEditor** (F4) → `File → Open Data Folder` → `MQL5/Experts/`
2. Copy `S6_EqLiquidityFade.mq5` there → open it → **F7** (0 errors)
3. In MT5: **View → Strategy Tester** (Ctrl+R)
4. Settings:

| Field | Value |
| --- | --- |
| Expert | `S6_EqLiquidityFade` |
| Symbol | `EURUSD` (start here) |
| Period | **M15** |
| Dates | e.g. 2024.01.01 – 2025.12.31 |
| Forward | No (or optional) |
| Deposit | **100000** |
| Leverage | **1:100** |
| Model | **Every tick** (best) or **1 minute OHLC** |
| Optimization | Disabled for first run |

5. Inputs: **leave defaults**. Confirm:
   - `InpUseGMT` = true
   - `InpTesterServerIsUTC` = **true** (MetaQuotes / most demo history)
   - `InpInitialBalance` = **0** (uses tester deposit) or **100000**
6. Click **Start**. Journal should show: `S6 EqLiquidityFade v1.20 | tester=YES`

If killzones look wrong (no trades in London/NY windows), set `InpTesterServerIsUTC=false` and set `InpServerToUtcOffset` so server+offset = UTC.

## Live install

1. Same copy + compile as above.
2. Drag EA onto a chart (any TF; EA reads M15+H1 internally).
3. Enable **Algo Trading**.
4. For The5ers: `InpInitialBalance=100000`, unique `InpMagic` per symbol chart.

## Critical settings

| Input | Recommended | Notes |
| --- | --- | --- |
| `InpUseGMT` | true | Killzones match research UTC |
| `InpTesterServerIsUTC` | true | Tester: treat bar times as UTC |
| `InpKZ1Start/End` | 7 / 11 | London UTC |
| `InpKZ2Start/End` | 12 / 17 | NY UTC |
| `InpFlattenHourUTC` | 20 | Flat late session |
| `InpRiskPercent` | 0.40 | 0.4% of initial |
| `InpRewardRisk` | 1.5 | TP distance |
| `InpDailyLossLimitPct` | 3.0 | Day pause |
| `InpMaxLossPct` | 6.0 | Hard floor |

## What it does

1. On each **closed M15** bar in a killzone:
   - Confirmed swing equals (0.15 ATR)
   - Sweep beyond equals that closes back inside
   - H1 structure bias filter
2. Places a **Buy/Sell limit** at the equal level (GTC; auto-cancel after ~16 M15 bars)
3. Moves SL to breakeven after +1R
4. Flattens from 20:00 UTC
5. Pauses on daily loss / hard max-loss floor

## Tester vs Python research

Same *rules*, not identical PnL: broker ticks ≠ HistData, spreads/slippage differ, one symbol vs multi-pair book.

## Demo checklist before The5ers eval

1. Strategy Tester sanity check (trades fire, no order errors).
2. Demo 1–2 weeks; journal fills vs research.
3. Confirm killzone hours in Journal prints.
4. Confirm lot risk ≈ 0.4% of $100k.

## Disclaimer

Past backtests ≠ live results. You are responsible for prop-firm rules, news risk, and compliance.
