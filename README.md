# MCPT Lab — Trading Strategy Tester

Monte Carlo Permutation Test (MCPT) toolkit and web UI for validating trading strategies, based on [neurotrader’s workflow](https://youtu.be/NLBXgSmRBgU) and the [neurotrader888/mcpt](https://github.com/neurotrader888/mcpt) reference implementation.

## The four steps

1. **In-sample excellence** — optimize strategy parameters on training data
2. **In-sample MCPT** — re-optimize on many OHLC permutations; low p-value means the edge is unlikely pure data-mining bias
3. **Walk-forward** — rolling re-optimization on unseen folds
4. **Walk-forward MCPT** — permute only after the first training fold; ask whether OOS results could be luck

Null hypothesis: *the strategy is garbage*. Permutation tests try to reject that.

## Quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Web UI
PYTHONPATH=. uvicorn app.main:app --host 0.0.0.0 --port 8000
# open http://localhost:8000

# CLI (synthetic data, fast)
PYTHONPATH=. python scripts/run_cli.py --strategy donchian --source synthetic \
  --insample-perms 40 --walkforward-perms 20 --train-years 2
```

## Forex funded strategy (The5ers-style card)

Rules modeled from the challenge checkout card:
- $100k · 10% evaluation target · **$6k max loss** · **3% daily loss** · **50% consistency**
- Funded: weekly withdraw of equity above $100k (min $250, cap $2,000)

Locked research winner (`data/research/best_strategy.json`):

| Field | Value |
|-------|--------|
| Timeframe | **H1** (contiguous hist **2018-01 → 2022-03**; Yahoo gap after) |
| Pairs | EURUSD, GBPUSD, USDJPY, AUDUSD, USDCHF |
| Mode | `h1_sweep_bos` (liquidity sweep → BOS within 8 bars) |
| Risk / RR | 0.65% · 2R · ATR×0.8 · max 2 positions · BE at 1R |
| MCPT | **p ≈ 0.008 (pass)** |
| Research window | ~**$12.9k/yr** · PF ≈ 1.28 · 667 trades · not blown · consistency OK |
| OOS (after 2020-06) | ~**$6.9k/yr** · funded survived |
| Daily MCPT backup | `data/research/best_strategy_daily.json` (~$5.0k/yr `smc_plus`) |

```bash
# Replay locked strategy (auto-selects H1 vs daily from artifact)
PYTHONPATH=. python scripts/run_funded_strategy.py

# H1 research hunters
PYTHONPATH=. python scripts/research/h1_lean_grid.py
PYTHONPATH=. python scripts/research/h1_validate_hits.py
```

Live bridge: `mcpt.forex.strategy_funded.make_live_engine()` wires `LiveSMCEngine` + `FundedRiskGuard`  
(causal: signal on closed bar → enter next open). Concepts: `knowledge/smc_ict_concepts.md`.

## Strategies included

| ID | Name | Notes |
|----|------|--------|
| `donchian` | Donchian breakout | Full 4-step pipeline including walk-forward MCPT |
| `ma_crossover` | Moving-average crossover | In-sample optimize + MCPT |
| `tree` | Decision tree | Intentionally overfit demo — usually fails in-sample MCPT |
| `h1_sweep_bos` (forex H1) | Sweep → BOS | Locked funded candidate above |
| `smc_plus` (forex daily) | ICT/SMC confluence | Backup in `best_strategy_daily.json` |

## Data sources

- `synthetic` — generated OHLC for offline demos (default)
- `yfinance` — download e.g. `BTC-USD` (cached under `data/`)
- `cache` — reuse a previous download
- CSV upload via the API (`POST /api/upload`) — columns: open, high, low, close

## Python API

```python
from mcpt.data import generate_synthetic_ohlc
from mcpt.pipeline import run_full_pipeline

df = generate_synthetic_ohlc(n_bars=24 * 365 * 3)
result = run_full_pipeline(
    df,
    strategy="donchian",
    n_insample_perms=100,
    n_walkforward_perms=50,
    train_years=2,
)
print(result.verdict)
```

Core pieces:

- `mcpt.permute.get_permutation` — OHLC bar shuffle preserving return stats
- `mcpt.pipeline.run_insample_mcpt` / `run_walkforward_mcpt`
- `mcpt.strategies.donchian` — breakout + walk-forward optimizer

## Tests

```bash
PYTHONPATH=. pytest mcpt/tests -q
```

## Attribution

Permutation algorithm and strategy examples adapted from [neurotrader888/mcpt](https://github.com/neurotrader888/mcpt) (MIT License). Method explained in [How I Develop Trading Strategies](https://youtu.be/NLBXgSmRBgU).

**Not financial advice.** Past results are not indicative of future performance.
