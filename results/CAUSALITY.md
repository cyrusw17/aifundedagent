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
| Entry fill | First M1 **strictly after** signal timestamp | OK |
| SL/TP same bar | Stop processed before take | OK |
| Parameters | Fixed a priori; no grid search | OK |

HistData timestamps treated as EST without DST, converted to UTC (+5h) for killzones.
