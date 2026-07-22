# Five causal winning strategies (KB Silver Bullet family)

**Look-ahead:** impossible by engine law (`knowable_at` = M15 close; fills only after).  
**Train / develop:** 2024-01-01 → 2025-12-31.  
**OOS:** 2023 full year + 2026 H1.  
**Search:** ICT/SMC Model C (Silver Bullet) + sweep → displacement FVG → limit at CE.

## Winner criteria (honest)

| Window | Requirement |
| --- | --- |
| DEV 2024–25 | Edge PF ≥ 1.05, profit > 0; eval +$10k preferred |
| 2023 | Edge PF ≥ 1.05, profit > 0 |
| 2026 H1 | Edge PF ≥ 1.05, profit > 0 (eval +$10k often unrealistic in 6 months) |

## The five

| ID | Levels | Risk | DEV PF / PnL | 2023 PF / PnL | 2026 PF / PnL | Eval DEV/23/26 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| **W1** | PDH only | 0.6% | 1.39 / +$11.7k | 1.11 / +$1.7k | 1.75 / +$3.1k | Y / N / N |
| **W2** | PDH only | 0.7% | 1.38 / +$12.6k | 1.11 / +$1.9k | 1.67 / +$3.0k | Y / N / N |
| **W3** | PDH only | 0.5% | 1.37 / +$9.9k | 1.11 / +$1.4k | 1.93 / +$3.4k | Y / N / N |
| **W4** | Asia only | 0.6% | 1.32 / +$13.6k | 1.36 / +$7.1k | 1.19 / +$1.6k | Y / N / N |
| **W5** | Asia only | 0.5% | 1.32 / +$12.0k | 1.37 / +$6.1k | 1.21 / +$1.6k | Y / N / N |

Shared rules: **14:00–15:00 UTC**, RR **3.0**, body ≥ 0.35 ATR, **no BE**, flatten 22:00 UTC, loose H1 bias.

## Model (knowledge)

1. In Silver Bullet hour, wait for raid of PDH or Asia extreme on a **closed** M15  
2. Bearish/bullish displacement body + **FVG** on that same closed bar  
3. Limit at FVG CE; SL beyond sweep; TP = 3R  
4. Engine fills only on M1 **after** bar close  

## No-lookahead confirmation

```bash
python scripts/assert_no_lookahead.py
python scripts/confirm_winners_causal.py
```

## Caveats

- Family is concentrated (all SB 14–15 UTC). W1–W3 differ mainly by risk; W4–W5 by Asia vs PDH.  
- 2026 H1 eval rarely hits +$10k (short window / few trades) even when edge PF > 1.  
- Not The5ers-ready until live/demo proves fills and costs.  
- Old S1–S6 green reports were invalidated by look-ahead fills (`LOOKAHEAD_FILL_BUG.md`).
