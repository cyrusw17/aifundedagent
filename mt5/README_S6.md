# S6 Equal Liquidity Fade — MT5 EA (v1.40)

## Why earlier tester runs lost ~$7k

Python **EURUSD 2024** ≈ **+$18k** with **limit fills on a retest of the equal**.

| Build | Bug |
| --- | --- |
| v1.20–1.31 | Entered **offside** (short while still below equal / long above) via nudge or “market if near” |
| **v1.40** | Arms a setup → **SellLimit/BuyLimit at the equal** → market **only** when price **revisits** the equal |

If Journal does not say **`S6 v1.40 PYTHON-RETEST`**, you are still on an old compile.

## Strategy Tester

1. Copy `S6_EqLiquidityFade.mq5` → `MQL5/Experts/` → **F7** (0 errors)
2. Ctrl+R:

| Field | Value |
| --- | --- |
| Expert | S6_EqLiquidityFade |
| Symbol | EURUSD |
| Period | **M15** |
| Model | **Every tick** (not “Open prices only”) |
| Dates | 2024.01.01 – 2025.01.01 |
| Deposit | **100000** |
| Leverage | 1:100 |

3. Inputs: `InpInitialBalance=100000`, `InpTesterServerIsUTC=true`, `InpRiskPercent=0.40` (that is **0.4%**, not 40)
4. Start → Journal: `S6 v1.40 PYTHON-RETEST`
5. End → stats: `armed= / limits= / retestMkt= / expired=`

Expect **many** `LIMIT` and some `RETEST-MKT` lines. If you only see hole-style markets, wrong file.

## Live

Same compile; attach chart; Algo Trading on; `InpInitialBalance=100000`.

## Research baseline

- EURUSD-only Python 2024 ≈ +$18k  
- 8-pair Python book is much larger — do not compare one-symbol tester to that
