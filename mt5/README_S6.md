# S6 MT5 EA (v1.60) — read this first

## Your −$7k tester result is expected

Corrected Python (causal fills, after signal bar close):

- S6 EURUSD 2024 ≈ **−$6k to −$14k**
- Old “+$18k / +$161k” reports used **look-ahead fills** (filled during the sweep before the signal was knowable)

Details: [`../results/LOOKAHEAD_FILL_BUG.md`](../results/LOOKAHEAD_FILL_BUG.md)

**Do not use this EA on The5ers** until strategies are rebuilt under causal fills.

## What v1.60 does

Causal equal-fade: arm after M15 close → limit at equal → retest only on M1 **after** the signal (never the sweep wick).

Journal: `S6 v1.60 CAUSAL`

## Tester

EURUSD · M15 · Every tick · Deposit 100000 · `InpInitialBalance=100000`
