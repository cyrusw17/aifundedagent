# Five winning strategies (causal / no look-ahead)

Screened with `strategy/run_kb_search_v2.py` against the ICT/SMC/TJR knowledge base.
**All fills start only after M15 bar close (`signal.knowable_at`).** Look-ahead fills raise `RuntimeError`.

## Selection rule

On each of **DEV (2024–2025)**, **VAL 2023**, and **VAL 2026 H1**:

- edge profit factor ≥ **1.05**
- edge net profit > **0**

(Challenge floor / $10k eval target is separate; 2026 H1 is only ~6 months.)

## The five

| ID | Model | Window (UTC) | Liquidity | Risk | RR | BE |
|----|-------|--------------|----------|------|----|----|
| **W1_SB14_PDH_r6** | Silver Bullet → FVG CE | 14:00–15:00 | PDH/PDL | 0.60% | 3.0 | off |
| **W2_SB14_PDH_r7** | same | 14:00–15:00 | PDH/PDL | 0.70% | 3.0 | off |
| **W3_SB14_PDH_r5** | same | 14:00–15:00 | PDH/PDL | 0.50% | 3.0 | off |
| **W4_SB14_ASIA_r6** | same | 14:00–15:00 | Asia H/L | 0.60% | 3.0 | off |
| **W5_SB14_ASIA_r5** | same | 14:00–15:00 | Asia H/L | 0.50% | 3.0 | off |

Family: **NY Silver Bullet** (`knowledge/07_killzones_sessions.md`, `08_silver_bullet.md`) —
sweep external liquidity → enter FVG CE → 3R, flatten 22:00 UTC, no early BE.

They are **five validated configs**, not five unrelated models. Diversification is
PDH vs Asia levels and risk sizing.

## Edge results (full `PARAMS.pairs`, HistData) — confirmed causal

| ID | DEV PF / PnL | 2023 PF / PnL | 2026H1 PF / PnL |
|----|--------------|---------------|-----------------|
| W1 | 1.39 / +$11.7k | 1.11 / +$1.7k | 1.75 / +$3.1k |
| W2 | 1.38 / +$12.6k | 1.11 / +$1.9k | 1.67 / +$3.0k |
| W3 | 1.37 / +$9.9k | 1.11 / +$1.4k | 1.93 / +$3.4k |
| W4 | 1.32 / +$13.6k | 1.36 / +$7.1k | 1.19 / +$1.6k |
| W5 | 1.32 / +$12.0k | 1.37 / +$6.1k | 1.21 / +$1.6k |

Confirmed by `python3 scripts/confirm_winners_causal.py` (zero fills before `knowable_at`).
Source: `results/kb_search_results.json`, narrative `results/KB_SEARCH.md`.

## No look-ahead confirmation

```bash
python scripts/assert_no_lookahead.py
python scripts/confirm_winners_causal.py
```

Engine rule (`strategy/backtest.py`): M1 search starts at `knowable_at`; any earlier
fill aborts with `RuntimeError`.

## Code

- Specs: `strategy/strategies/winners.py` (`W1_…` … `W5_…`)
- Signal logic: `strategy/strategies/kb_models.py` (`sb_fvg`)
- Registry: `strategy/strategies/__init__.py`

## Caveats

- HistData M1 ≠ The5ers broker tick / spreads.
- Same SB14 family — correlated; treat as one edge with size/liquidity variants.
- Not yet ported to MT5 EA (old `S6_EqLiquidityFade.mq5` is a different model).
- Past causal edge ≠ future challenge pass; re-validate on broker data before live.
