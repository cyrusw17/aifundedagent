# MT5 EA — Futures The5ers `h1_sweep_bos`

Ports the locked research strategy in `data/research/best_strategy_futures_the5ers.json` to MetaTrader 5.

## Strategy (locked)

| Param | Value |
|---|---|
| Mode | `h1_sweep_bos` — liquidity sweep in discount/premium, then BOS within 1–8 H1 bars |
| Symbols (research) | ES, NQ, YM, CL, GC |
| Timeframe | H1 |
| Risk | 0.75% equity |
| RR | 2.0 |
| ATR stop | 1.25 × ATR(14) SMA |
| Swing | left/right = 2 |
| Filters | skip Mondays, 1 entry/day, cooldown 2 bars after 2 consecutive losses |
| Daily halt | −3% / +5% of `InitialBalance` (default $100k) |
| Floor | `InitialBalance − MaxLoss` ($100k − $6k) |

Causal rule: signal on **closed** H1 → enter on the **new** H1 bar (market).

## Install

1. Copy into your MT5 data folder (`File → Open Data Folder → MQL5`):
   - `mt5/Experts/FuturesThe5ersH1SweepBOS.mq5` → `MQL5/Experts/`
   - `mt5/Include/FuturesThe5ers/` → `MQL5/Include/FuturesThe5ers/`
2. In MetaEditor: compile `FuturesThe5ersH1SweepBOS.mq5`.
3. Attach the EA to any chart (H1 preferred). It scans the symbol list on each new H1 bar.

## Broker symbol names

Default input list (edit to match your broker):

```
US500,NAS100,US30,USOIL,XAUUSD
```

Common mappings:

| Research | Typical CFD |
|---|---|
| ES | US500, SPX500, SP500 |
| NQ | NAS100, USTEC, NDX100 |
| YM | US30, DJ30, WallStreet30 |
| CL | USOIL, WTI, XTIusd |
| GC | XAUUSD, GOLD |

Or set `InpTradeChartOnly=true` to trade only the chart symbol.

## Notes

- Max **1** open position across the book (research portfolio rule).
- Lot size uses tick value/size so it works on index/commodity CFDs — verify contract specs on your broker.
- This is a research port, not a guarantee of funded-pass results. Demo first.
- Weekly withdraw from the sim is **not** automated (manual / prop dashboard).
