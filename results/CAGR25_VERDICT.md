# Can we get ~25% per year? (causal / no look-ahead)

**Short answer: not stably — not with these ICT/SMC session models on HistData at ≤1% risk.**

## What we tried

- Risk up to **1% of initial** per trade  
- Fills only after `knowable_at` (M15 close)  
- Multi-SB windows, Asia/PDH levels, reject, ORB, BOS, sweep-FVG  
- Portfolios of top sleeves  
- Screen on 2024–25, then **early-first** filter on **2020–22**

Scripts: `strategy/run_cagr25_search.py`, `strategy/run_cagr25_stable.py`.

## Fragile “25%” (do not trust)

On **DEV 2024–25 only**, aggressive multi-SB at 1% risk printed up to:

| Config | DEV simple ann | DEV PF | Notes |
|--------|---------------:|-------:|-------|
| `MSB_rr3.5_b0.22_f0.15_PA_w71415` | **25.5%** | 1.34 | 3 SB windows, loose body |

Same config on **full 2020–25**: CAGR **~7.9%**, early **2020–22 PF 0.97** (edge dies), **2026 red**.

So the 25% number is a **2-year regime fit**, not a durable annual return.

## Stable best (early + late PF ≥ 1.05)

| Config | Full 2020–25 CAGR | Early ann | Late ann | 2026 PF |
|--------|------------------:|----------:|---------:|--------:|
| `Q_MSB_rr3.5_b0.45_f0.12_A_w714` (Asia SB) | **5.4%** | 5.2% | 7.1% | 1.82 |

Reject / ORB / BOS grids: **0** configs with early PF ≥ 1.05 and enough trades.

W1/W4 at 1% risk: green late, **red early**; full CAGR only **~2–3%**.

## Why 25% is out of reach here

1. **Trade capacity** — even busy multi-SB is ~50–200 fills/year across 8 pairs after causal filters.  
2. **Realized EV** is closer to ~0.2R/trade after flatten/spreads, not full RR.  
3. At 1% risk: \(0.2R × 100 trades/yr × $1k ≈ $20k\) is an upper sketch; live PF in hard years (2020–22) is often **&lt; 1**.  
4. Scaling risk to hit 25% would need **~4–5% risk/trade** on the stable sleeve (or huge DD), which breaks a 1% risk budget and The5ers $6k floor (stable best already shows ~$15–20k DD on $100k).

## Retail / indicator follow-up

Also tested EMA/RSI/BB/MACD/Donchian/Supertrend/VWAP, ADX filters, daily swing, and H1 turtle-style Donchian (see `RETAIL_EXPANSION.md`).

- M15 retail: no early PF≥1.05 grid hit worth keeping  
- H1 Donchian can print **~25%+ in 2020–22** then **dies in 2023–25** (same regime trap)  
- Soft best retail full CAGR ~**7%** with ~$75k DD — not stable, not 25%

## Verdict

I do **not** believe a **stable ~25%/year** strategy is available from ICT/SMC **or** common retail indicator families under **no look-ahead** on 2020–2025 HistData at **1% risk**.  

Best honest durable number remains **~5% CAGR** (Asia Silver Bullet). Fragile windows can print 25% but do not survive the other half of the sample.
