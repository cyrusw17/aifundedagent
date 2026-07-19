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
| Pairs | EURUSD, USDJPY, USDCHF, AUDUSD |
| Mode | `smc_plus` (ICT-style sweep/BOS confluence) |
| Risk / RR | 0.75% · 3R · ATR stop 1.4 · 1 position · 1 entry/day |
| MCPT | **p ≈ 0.007 (pass)** |
| 2018–2023 | ~**$5.0k/yr** avg · PF ≈ 1.96 · not blown · consistency OK |
| Challenge split | evaluation **passed** · funded survived · funded ~**$4.4k/yr** |

```bash
# Replay locked strategy
PYTHONPATH=. python scripts/run_funded_strategy.py

# Fast research hunters (optional)
PYTHONPATH=. python scripts/research/lightning_hunt.py
PYTHONPATH=. python scripts/research/recover_best.py
```

Live bridge stub: `mcpt.forex.strategy_funded.make_live_engine()` / `mcpt.forex.live.LiveSMCEngine`  
(causal: signal on closed bar → enter next open). Concepts: `knowledge/smc_ict_concepts.md`.

## Strategies included

| ID | Name | Notes |
|----|------|--------|
| `donchian` | Donchian breakout | Full 4-step pipeline including walk-forward MCPT |
| `ma_crossover` | Moving-average crossover | In-sample optimize + MCPT |
| `tree` | Decision tree | Intentionally overfit demo — usually fails in-sample MCPT |
| `smc_plus` (forex) | ICT/SMC confluence | Locked funded candidate above |

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
