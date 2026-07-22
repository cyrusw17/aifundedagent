# Making look-ahead impossible

Look-ahead is not fixed by “being careful.” It has to be **illegal in the engine**.

## Rules that close the holes

### 1. Separate *decision time* from *bar open*
- `signal.time` = bar **open** (candle label)
- `signal.knowable_at` = bar **close** (`open + tf`)
- Features may use the closed bar’s OHLC
- **Orders may only use data at/after `knowable_at`**

### 2. Fill search starts at `knowable_at`, never at `signal.time`
The bug that inflated S6: limits searched M1 from bar open and filled on the sweep wick before the close confirmed the fade.

### 3. Hard assert (crash on regression)
```text
if entry_time < signal.knowable_at: raise RuntimeError
```
In `strategy/backtest.py`. A silent wrong fill is worse than a crash.

### 4. Automated guard
```bash
python scripts/assert_no_lookahead.py
```
Fails CI if any fill is before `knowable_at`.

### 5. Same rules for indicators
| Feature | Causal form |
| --- | --- |
| Swings | usable only after `pivot + right` |
| H1 bias | `shift(1)` then map to M15 |
| Session ranges | Asia after 07:00; London after 12:00 |
| ATR / closes | no future bars in the window |

### 6. Live EA = event on *new bar*
Evaluate the **previous** closed M15 only. Pending/retest only on ticks **after** that close (never M1 inside the signal bar).

### 7. What does *not* count as protection
- Comments / README
- “We only use closed bars” while fills still start at bar open
- Strategy Tester profit matching a biased Python book

## One-line law

**No trade may enter before the moment a human could have known the signal.**
