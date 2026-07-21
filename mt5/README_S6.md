# S6 Equal Liquidity Fade — MT5 EA (v1.50)

## Zero-spread losses are logic/data parity — not “spread”

Python EURUSD 2024 with **0 spread** ≈ **+$27k–$35k** (engine/limit book).  
If the EA still loses with spread=0, it was **not** taking the same fills as research.

### Bugs fixed in v1.50
1. **H1 bias** now from **M15→H1 resample** (Python), not broker `PERIOD_H1`
2. **Retest fill** uses **M1 high/low wick** (Python), not only Bid/Ask
3. **Day flag** set only on **FILL** — expired pendings no longer burn the day
4. Structural SL/TP no longer mutated toward the market on retest

Journal must say: **`S6 v1.50 PARITY`**

## Strategy Tester

| Field | Value |
| --- | --- |
| Expert | S6_EqLiquidityFade |
| Symbol | EURUSD |
| Period | M15 |
| Model | **Every tick** |
| Deposit | 100000 |
| `InpInitialBalance` | 100000 |

End stats: `armed= / limits= / retestMkt= / expired=`

## Still not identical to Python

Broker M1/M15 history ≠ HistData used in research. Even with correct logic, PnL will differ. Direction should no longer be a steady multi-thousand loser if parity holds.
