# Critical: fill look-ahead in prior research

## What you saw in MT5 (−$7k) was right

The S6 EA trading **after** the M15 signal bar closes is **causal**.  
On EURUSD 2024 that produces about **−$6k to −$14k** (hits The5ers floor around −$6k).

Prior Python reports of **+$18k / +$161k** were **wrong**.

## The bug

Signals are decided on the **closed** M15 bar (`high` swept equal, `close` back inside).

Old fill engine started searching M1 from the bar **open**:

```text
signal known at close ──► but fill allowed during the same bar’s sweep
```

That fills the fade **during** the inducement wick — information you do not have until the bar completes. That is look-ahead.

| Fill rule | EURUSD 2024 S6 (0 spread, no floor) |
| --- | ---: |
| From bar open (old, biased) | ~+$35k |
| After bar close (causal) | ~−$14k |

With the $6k max-loss floor, causal S6 stops near **−$6k**—matching the EA.

## Causal 2024 (no floor) — all strategies

| Strategy | EURUSD | 8-pair |
| --- | ---: | ---: |
| S1 session break-retest | −$13k | −$22k |
| S2 NY–London turtle | **+$1k** | **+$5k** |
| S3 turtle soup | −$13k | −$46k |
| S4 asia break-go | −$5k | −$12k |
| S5 dual book | −$17k | −$54k |
| S6 equal fade | −$14k | −$44k |

Under causal fills, the old “five winners” list **does not hold**. Only S2 is slightly green in this window (not a funded edge by itself).

## Fix in code

`strategy/backtest.py` — fills start at `signal.time + 15 minutes` (bar close).  
EA v1.60 — M1 retest only **after** arm time (never the sweep bar).

## What this means

1. Stop trying to make the EA match the old green Python numbers — those numbers were invalid.  
2. The EA losing ~$7k on S6 2024 is consistent with corrected research.  
3. Strategies must be **redesigned and re-validated** with causal fills before any The5ers use.
