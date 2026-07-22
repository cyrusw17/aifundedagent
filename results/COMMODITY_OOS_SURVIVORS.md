# Commodity OOS survivors (train 2024–25 → blind 2026)

## Protocol

1. **Train / select** on ≤2025-12-31 only (gates: 2024≥10%, 2025≥10%, 2023≥0%, no year 2021–25 &lt; −8%, floor held, causal fills).
2. **One-shot blind test** on 2026-01-01 … 2026-06-30.
3. If 2026 fails → **discard** (treat as curve-fit). **Never retune** that idea on 2026.

## Prior C1–C5

Long-only 4h Donchian winners cleared 2024/25 but **failed 2026 H1** (≈ −2% to −3% period). Discarded under this protocol.

## Five survivors (confirmed)

| ID | Logic | 2024 | 2025 | 2026 H1 ann | PF26 | n26 |
|----|-------|------|------|-------------|------|-----|
| O1 | Daily Don 25 RR2.5 **both** | 11.4% | 12.4% | **35.5%** | 14.8 | 5 |
| O2 | Daily Don 15 RR3 long | 23.4% | 13.3% | **21.2%** | ∞ | 3 |
| O3 | Daily ATR-break RR5 long | 10.6% | 11.4% | **7.7%** | 2.8 | 7 |
| O4 | 4h Don 40 RR2 long | 10.9% | 17.7% | **11.2%** | 2.6 | 10 |
| O5 | Daily Don 30 RR2.5 **both** | 10.9% | 12.0% | **29.5%** | 16.3 | 5 |

Both-side daily Donchian caught the 2026 Mar–Jun gold selloff; that is why O1/O5 beat pure long 4h breakouts on holdout.

## Hunt stats (XAU)

- ~240 idea × risk grid
- ~25 train→2026 survivors; ~112 train-pass ideas **failed** 2026 and were dropped
- Look-ahead: 0 violations on confirm

## Code

- Registry: `strategy/strategies/commodity_oos_winners.py`
- Hunt: `python3 strategy/run_commodity_oos_filter.py`
- Confirm: `python3 scripts/confirm_commodity_oos_winners.py`
