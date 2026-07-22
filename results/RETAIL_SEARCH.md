# Retail indicator search (causal) — aiming ~25%/yr

Models: EMA cross, EMA+RSI, Bollinger+RSI, Donchian, MACD, Supertrend, Stoch, VWAP fade.
Risk **1%**. No look-ahead. Early filter **2020–22 PF≥1.05**.

Screened **84**; early-pass **0**; stable early+late **0**.

## Near ≥20% full CAGR (stable)

_None._

## Best by full 2020–25 CAGR

- `EMARSI_rr3.0_s1.5_kz` (ema_rsi) [fragile]: CAGR **-0.8%** (ann -0.78%, PF 0.98, n=390, dd=$27,459) | early PF 1.03 ann 1.04% | late PF 0.939 ann -2.61% | 2026 PF 1.894
- `EMARSI_rr3.0_s1.0_all` (ema_rsi) [fragile]: CAGR **-1.38%** (ann -1.34%, PF 0.966, n=431, dd=$42,018) | early PF 1.016 ann 0.57% | late PF 0.923 ann -3.24% | 2026 PF 1.033
- `EMARSI_rr3.0_s1.5_all` (ema_rsi) [fragile]: CAGR **-1.39%** (ann -1.35%, PF 0.968, n=428, dd=$29,967) | early PF 1.035 ann 1.28% | late PF 0.915 ann -3.98% | 2026 PF 1.274
- `EMARSI_rr3.0_s1.0_kz` (ema_rsi) [fragile]: CAGR **-2.18%** (ann -2.07%, PF 0.942, n=392, dd=$47,284) | early PF 1.016 ann 0.53% | late PF 0.881 ann -4.66% | 2026 PF 1.509
- `EMARSI_rr2.0_s1.5_kz` (ema_rsi) [fragile]: CAGR **-3.2%** (ann -2.96%, PF 0.92, n=392, dd=$41,299) | early PF 1.005 ann 0.17% | late PF 0.853 ann -6.08% | 2026 PF 1.705
- `EMARSI_rr2.0_s1.5_all` (ema_rsi) [fragile]: CAGR **-3.21%** (ann -2.96%, PF 0.926, n=431, dd=$41,137) | early PF 1.003 ann 0.12% | late PF 0.865 ann -6.04% | 2026 PF 1.156
- `EMARSI_rr1.5_s1.0_kz` (ema_rsi) [fragile]: CAGR **-5.65%** (ann -4.91%, PF 0.844, n=394, dd=$50,867) | early PF 1.001 ann 0.02% | late PF 0.725 ann -9.84% | 2026 PF 0.882

## Verdict

No retail config kept PF≥1.05 in both 2020–22 and 2023–25 in this grid.
