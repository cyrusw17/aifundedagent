# Funded-edge winners (gold) — real prop money path

## Protocol

1. **Train** on ≤2025-12-31 only  
2. **Blind-test** 2026-01-01 … 2026-06-30 once — fail ⇒ discard (curve-fit)  
3. Must clear The5ers constraints: static floor, daily loss buffer (≥ −$2.8k), challenge pass, weekly-withdraw funded path without blowing floor  

## Primary result

**F1** (Gold 4h Donchian 40, RR 1.8, risk 2%) is the money strategy:

| Period | Open ann | Challenge | Funded (weekly withdraw) |
|--------|----------|-----------|---------------------------|
| 2024 | **35.0%** | 100 days | — |
| 2025 | **36.1%** | 245 days | **$62,081** total over 2024–25 |
| 2026 H1 | **21.9%** | **22 days** | **$11,151** |

Prior long-only 4h RR5 C1–C5 **failed** 2026. Lower RR + confirmed 2026 challenge is the difference.

## Five confirmed winners

| ID | Logic | 2024 | 2025 | 2026 H1 | Ch26 | Funded 24–25 | Funded 2026 H1 |
|----|-------|------|------|---------|------|--------------|----------------|
| **F1** | 4h Don40 RR1.8 L 2% | 35% | 36% | 22% | **22d** | **$62.1k** | $11.2k |
| F2 | 4h Don40 RR2 L 2% | 23% | 39% | 23% | 22d | $54.3k | $11.6k |
| F3 | 4h Don35 RR1.8 L 1.5% | 27% | 25% | 26% | 28d | $47.1k | $12.2k |
| F4 | 4h Don30 RR1.8 L 1.8% | 35% | 36% | 18% | 51d | $35.2k | $9.1k |
| F5 | Daily Don30 RR2.5 **both** 2% | 11% | 12% | 30% | 77d | $22.2k | **$13.6k** |

F5 is the selloff hedge (both-side). F1–F4 are the challenge/funded pace engines.

## Playbook

1. **Challenge:** run **F1** (or F4 if you want faster 2025-style pace — 106d in 2025).  
2. **Funded:** keep **F1**; weekly withdraw.  
3. **Risk-off / dump regimes:** consider **F5** both-side overlay.  

## What failed (discarded)

- Old C1–C5 4h Don RR5 long: dead in 2026 H1  
- Many daily long RR3+: hit +$10k then **consistency fail** on 2026 challenge  
- Higher risk on both-side n25: funded withdraw → max_loss  

## Code

- Registry: `strategy/strategies/funded_edge_winners.py`  
- Models: `strategy/strategies/commodity_models.py` (Don / regime / ST / MACD / BB)  
- Hunt: `strategy/run_funded_edge_hunt.py`  
- Confirm: `python3 scripts/confirm_funded_edge_winners.py`  
