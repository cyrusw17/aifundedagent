# Look-ahead audit

| Component | Rule | Status |
| --- | --- | --- |
| M15 OHLC | Signal on bar `i` uses only bars `≤ i` | OK |
| Swing points | Confirmed at `p+right`; used only when `p < i` | OK |
| H1 bias | `shift(1)` then ffill to M15 | OK |
| Asia range | 00:00–06:59; signals only `hour ≥ 7` | OK |
| London range | 07:00–11:59; signals only `hour ≥ 12` | OK |
| PDH/PDL | Prior completed day only | OK |
| Equal H/L | Built from confirmed swings with `p < i` | OK |
| Entry fill | First M1 **at/after signal bar close** (`time+15m`) | **FIXED 2026-07** |
| SL/TP same bar | Stop processed before take | OK |
| Parameters | Fixed a priori; no grid search | OK |

## Fill look-ahead (critical)

Older builds searched M1 from the signal bar **open**, so equal-fade limits filled **during the sweep wick** before the close confirmed the signal. That inflated S6 and related books to large green PnL.

Correct rule: fills only after the M15 bar closes. See `LOOKAHEAD_FILL_BUG.md`. Under causal fills, prior “winners” largely disappear; S6 EURUSD 2024 is red (~−$6k with prop floor).

HistData timestamps treated as EST without DST, converted to UTC (+5h) for killzones.
