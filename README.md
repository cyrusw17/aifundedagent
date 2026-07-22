# AI Funded Agent — The5ers ICT Day Trader

Rule-based forex day trader for a **The5ers-style $100K** evaluation/funded account, built on ICT Power of 3 (session range break & retest).

## Results (no curve-fit)

| Window | Edge PF | Challenge eval | Challenge funded |
| --- | --- | --- | --- |
| **2024–2025** (develop) | 1.24 (+$45.9k) | **PASS** | **PASS** |
| **2023–2024** (validate) | 1.32 (+$60.4k) | **PASS** | **PASS** |
| **2023** pure OOS | 1.37 (+$34.4k) | **PASS** | **PASS** |

Details: [`results/REPORT.md`](results/REPORT.md) · machine summary: [`results/summary.json`](results/summary.json)

## Prop rules encoded

- Profit target 10% / Max loss $6,000 / Daily loss $3,000 pause  
- Consistency 50% (daily profit soft-cap)  
- ~2+ trades/business day across 8 pairs (often 3–5 on active days)

## Quick start

```bash
pip install -r requirements.txt
python scripts/download_data.py          # HistData M1 zips -> data/raw
python -m strategy.run_backtest          # writes results/
```

## Layout

| Path | Role |
| --- | --- |
| `strategy/` | Causal signal engine + The5ers backtest |
| `scripts/download_data.py` | Data pull |
| `mt5/AsiaBreakRetest.mq5` | MT5 EA skeleton for later live port |
| `results/` | Backtest report + summary |

## Design constraints

- **No look-ahead** — M15 signals on closed bars; M1 path for fills  
- **No optimizer** — fixed ICT session-break parameters chosen a priori  
- Develop on 2024–2025, validate on 2023–2024 without refitting  

## Disclaimer

Research / education only. Past backtests do not guarantee live or funded-account results. Follow your firm’s current official rules before trading.


## Multi-strategy comparison (5 winners)

See [`results/COMPARISON.md`](results/COMPARISON.md) for side-by-side eval days, 2026 holdout, and funded weekly withdrawals above $101k.

```bash
python -m strategy.run_comparison
```
