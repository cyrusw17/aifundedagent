# S6 Equal Liquidity Fade — MT5 EA

Port of the backtested **S6_eq_liquidity_fade** strategy for MetaTrader 5.
**Strategy Tester ready** (v1.30+).

## If Strategy Tester lost money (important)

Python research for **EURUSD only, 2024-01 → 2025-01** is about **+$18k** (PF ~1.9, max DD ~$4k).  
The big multi-pair Python number (~+$161k / 2024–25) is **8 pairs**, not one chart.

If your tester showed ~**−$7k**, that was **not** matching research. Common causes fixed in **v1.30**:

1. **Entry nudging** (v1.20) moved limit prices off the equal level when stops-level blocked them → wrong trades. **v1.30 skips** those setups instead.
2. Hard floor cancelled pendings but **left positions open** past −6%. Now it **closes all**.
3. Wrong model/timezone: use **Every tick**, `InpTesterServerIsUTC=true`.

Re-download **v1.30**, recompile (F7), re-run the same dates. Journal must say `v1.30`.

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
| Dates | e.g. 2024.01.01 – 2025.01.01 |
| Deposit | **100000** |
| Leverage | **1:100** |
| Model | **Every tick** (avoid “Open prices only”) |
| Optimization | Off |

5. Inputs: leave defaults (`InpTesterServerIsUTC=true`, `InpInitialBalance=0` or `100000`)
6. Start — Journal: `S6 EqLiquidityFade v1.30 | tester=YES`

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
