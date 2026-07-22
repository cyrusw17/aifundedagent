# Twenty prop-floor-safe causal winners

Rules: The5ers **$6k** static floor, **$3k** daily, soft `dd_halt`, fills after `knowable_at`.

Pool **28** verified → **20** diverse selected.

| # | ID | Family | Max DD | Ann | PF | n | Risk | Halt |
|---|----|--------|--------|-----|----|---|------|------|
| 1 | `A1_H1Don_n35_rr5` | h1_don | $5,050 | 2.99% | 1.408 | 198 | 0.35% | $5,000 |
| 2 | `A2_H1Don_n30_rr4` | h1_don | $4,962 | 2.06% | 1.566 | 98 | 0.50% | $4,500 |
| 3 | `A3_H1Don_n40_rr4` | h1_don | $4,681 | 2.87% | 1.825 | 104 | 0.50% | $4,500 |
| 4 | `A4_ICT_MSB_PA` | ict_sb | $4,708 | 1.43% | 1.329 | 78 | 0.50% | $4,500 |
| 5 | `A5_ICT_MSB_ASIA` | ict_sb | $4,184 | 1.84% | 1.542 | 65 | 0.50% | $4,000 |
| 6 | `H1EMA_12_48_rr4_h3` | h1_ema | $4,847 | 2.97% | 1.316 | 189 | 0.50% | $4,500 |
| 7 | `H1Don_n55_rr4_h3` | h1_don | $4,893 | 2.03% | 1.695 | 63 | 0.50% | $4,500 |
| 8 | `R2_EMA_ADX_rr25` | retail | $4,597 | 1.12% | 1.388 | 60 | 0.50% | $4,500 |
| 9 | `R2_ROC_rr25` | retail | $4,848 | 0.16% | 1.053 | 70 | 0.40% | $4,500 |
| 10 | `R_ema_rsi_rr20_100_30_70_12` | retail | $4,882 | 0.52% | 1.124 | 84 | 0.50% | $4,500 |
| 11 | `R_donchian_rr20_20_12` | retail | $4,862 | 0.17% | 1.066 | 66 | 0.40% | $4,500 |
| 12 | `DonD_n40_rr3_h10` | swing | $4,104 | 0.86% | 1.204 | 153 | 0.50% | $4,500 |
| 13 | `DonD_n20_rr4_h8` | swing | $4,038 | 0.51% | 1.121 | 191 | 0.40% | $4,500 |
| 14 | `EmaD_20_50_rr25_h5` | swing | $3,006 | 0.56% | 1.175 | 131 | 0.50% | $4,500 |
| 15 | `FS_W4_SB14_ASIA_r6` | ict_sb | $4,621 | 0.98% | 1.247 | 74 | 0.50% | $4,500 |
| 16 | `H1Don_n35_rr4_h1` | h1_don | $4,910 | 2.77% | 1.789 | 102 | 0.50% | $4,500 |
| 17 | `H1EMA_15_45_rr4_h3` | h1_ema | $4,675 | 0.88% | 1.145 | 120 | 0.50% | $4,500 |
| 18 | `SB14_PDH_rr30_b35` | ict_sb | $3,012 | 0.83% | 1.289 | 56 | 0.50% | $4,500 |
| 19 | `SB14_PDH_rr25_b40` | ict_sb | $2,514 | 0.5% | 1.198 | 51 | 0.50% | $4,500 |
| 20 | `DonD_n55_rr3_h10` | swing | $4,154 | 0.21% | 1.059 | 144 | 0.40% | $4,500 |

## Families

```
{'h1_don': 5, 'ict_sb': 5, 'h1_ema': 2, 'retail': 4, 'swing': 4}
```

## Guards

```bash
python3 scripts/assert_no_lookahead.py
python3 scripts/confirm_floor_safe_20.py
```

Registry: `strategy/strategies/floor_safe_20.py`
