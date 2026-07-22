# Retail / indicator expansion (causal) — still no stable ~25%

After ICT/SMC stalled near ~5% stable CAGR, we encoded common **retail** toolkits
and searched 2020–2025 under **no look-ahead** fills (1% risk).

## Families tested

| Family | Models | Best stable note |
|--------|--------|------------------|
| M15 indicators | EMA cross, EMA+RSI, BB+RSI, Donchian, MACD, Supertrend, Stoch, VWAP | **0** early PF≥1.05 |
| M15 v2 | EMA+RSI+ADX+H1, CCI, ROC, EMA stack | Stable ~**1.5%** CAGR (majors) |
| Daily swing | Donchian / EMA / RSI daily, multi-day hold | **0** stable; best ~1.6% fragile |
| H1 trend | Donchian / EMA H1, hold 2–8 days | Soft ~**7.3%** full CAGR; **0** late PF≥1.05 |

## Headline numbers (causal, 1% risk)

| Result | Period | Ann / CAGR | Stable? |
|--------|--------|------------|---------|
| H1 Donchian `rr4 n35 h3` | **2020–22 only** | **~28%** ann | No — late PF 0.98 |
| Same family best soft | 2020–25 full | **~7.3%** CAGR | Late PF only 1.01; DD ~$75k |
| EMA+RSI+ADX H1 filter | 2020–25 stable | **~1.5%** CAGR | Yes, tiny |
| ICT Asia SB (prior) | 2020–25 stable | **~5.4%** CAGR | Still best durable |

## Pattern

Retail trend systems often **print 20–28% in 2020–22** (strong trends) then **lose in 2023–25**.
That is the same overfit trap as loose multi-SB on 2024–25 alone.

## Code

- `strategy/strategies/retail_models.py` (+ `retail_models_v2.py`, `swing_retail.py`)
- `strategy/run_retail_search.py`, `run_retail_v2_search.py`, `run_swing_search.py`, `run_h1_trend_search.py`
- Engine: `max_hold_days` for multi-day holds (`strategy/config.py` / `backtest.py`)

## Verdict

Expanding into retail indicators did **not** produce a **stable ~25%/yr** strategy.
Best durable edge remains ICT Asia Silver Bullet (~5% CAGR). Best “soft” retail is H1 Donchian (~7% full CAGR) with large DD and weak late PF.
