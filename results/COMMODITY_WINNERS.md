# Commodity winners — no 2026+ data

Universe: **XAUUSD** (gold), **XAGUSD** (silver), **BCOUSD** (Brent).  
**Hard cutoff: 2025-12-31** — zip files and bars from 2026+ are never loaded for research.

## Gates

| Gate | Rule |
|------|------|
| 2024 | simple ann ≥ **10%** |
| 2025 | simple ann ≥ **10%** |
| 2023 | ≥ 0% |
| 2021–2025 | no year < **−8%**, floor always held |
| PF 2024–25 | ≥ 1.05 |
| Causality | fills only after `knowable_at` |

## Five winners

| # | ID | Universe | Logic | 2021 | 2022 | 2023 | **2024** | **2025** | Risk |
|---|----|----------|-------|------|------|------|----------|----------|------|
| 1 | `C1_XAU_DON4h_n30_rr5` | Gold | 4h Donchian 30 RR5 long | −5.9% | 0.2% | 9.2% | **28.3%** | **35.1%** | 2.0% |
| 2 | `C2_XAU_DON4h_n20_rr5` | Gold | 4h Donchian 20 RR5 long | −5.9% | −2.8% | 2.2% | **15.9%** | **31.3%** | 1.5% |
| 3 | `C3_XAU_DON1D_n20_rr4` | Gold | Daily Donchian 20 RR4 long | 1.0% | −3.5% | 3.7% | **16.2%** | **13.3%** | 2.0% |
| 4 | `C4_XAUXAG_DON4h_n20_rr5` | Gold+Silver | 4h Donchian 20 RR5 long | −5.4% | 4.9% | 2.3% | **12.2%** | **12.9%** | 1.0% |
| 5 | `C5_XAU_DON4h_n20_rr4` | Gold | 4h Donchian 20 RR4 long | −5.9% | −1.6% | 2.0% | **14.3%** | **31.3%** | 1.5% |

All use compound equity risk + soft equity halt at $95k (static The5ers floor).

## Notes

- Long-only Donchian on gold/silver is the edge that cleared 2024–2025 ≥10% with year-level stability.
- EMA / ICT / H1 retail grids were searched; none cleared the same yearly gates as cleanly.
- **2026+ reserved for future test** — do not train or select on it.
- 2021 is the weak year for most (gold chop); C3 is the most balanced early-year profile.

## Code

- Registry: `strategy/strategies/commodity_winners.py`
- Models: `strategy/strategies/commodity_models.py`
- Loader cutoff: `strategy/data_loader.py` `RESEARCH_MAX_END`
- Confirm: `python3 scripts/confirm_commodity_winners.py`
- Look-ahead: `python3 scripts/assert_no_lookahead.py`
