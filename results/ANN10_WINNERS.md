# Five strategies — prop-floor-safe edition

**Prop rules:** static max loss $6,000 · daily loss $3,000 · soft `dd_halt`  
**Fills:** no look-ahead (`knowable_at` = bar close)  
**Window:** 2020–2025 (and checked on early/late/2026 H1)

| # | Strategy | Max DD | Full ann | Risk | Halt |
|---|----------|--------|----------|------|------|
| 1 | **A1** H1 Donchian 35 RR5 | **$5.1k** | 3.0% | 0.35% | $5.0k |
| 2 | **A2** H1 Donchian 30 RR4 | **$4.7k** | 1.5% | 0.40% | $4.5k |
| 3 | **A3** H1 Donchian 40 RR4 | **$4.6k** | 2.2% | 0.40% | $4.5k |
| 4 | **A4** SB14 PDH+Asia | **$4.7k** | 1.4% | 0.50% | $4.5k |
| 5 | **A5** SB14 Asia | **$4.2k** | 1.8% | 0.50% | $4.0k |

All five: **never hit $94k floor**, **max_dd ≤ $6k**.

See `FLOOR_SAFE.md` for the unconstrained → floor-safe trade-off (was >10% ann with $20k–$90k DD).

Registry: `strategy/strategies/ann10_winners.py`  
Confirm: `python3 scripts/confirm_ann10_winners.py`
