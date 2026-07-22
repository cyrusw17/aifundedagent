# Strategy Side-by-Side Comparison

## Causality / anti-overfit controls

- Signals only on **completed M15** bars
- Swing pivots usable only after `pivot + right` confirmation
- H1 bias mapped with a **1-hour shift** (last closed H1)
- London range used only at/after **12:00 UTC** (session complete)
- Fills on **M1 after** signal time; same-bar SL before TP
- **No parameter optimizer / no walk-forward search**
- Develop **2024–2025** → validate **2023–2024** → holdout **2026 H1**

## Funded payout rule (as requested)

Each week, **all equity above $101,000** is withdrawn (skip if excess &lt; $250).  
Account continues near $101k. **Funded total made** = weekly withdrawals + (ending equity − $100k).

Eval still requires +$10k on the challenge account (no weekly withdraw during eval).

## Five winning strategies (eval PASS on all three windows)

| ID | Model |
| --- | --- |
| **S6** | Equal highs/lows sweep fade |
| **S4** | Asia break-and-go (momentum) |
| **S5** | Dual liquidity book (Turtle + Equals) |
| **S3** | Turtle Soup (failed PDH/PDL/Asia break) |
| **S1** | Asia/London break + retest |

S2 (NY–London turtle) passed 2024–25 and 2023–24 but **failed 2026 eval** — excluded from the winning set.

---

## Eval: days to pass (+$10k)

| Strategy | 2024–2025 | 2023–2024 | 2026 H1 |
| --- | ---: | ---: | ---: |
| S6_eq_liquidity_fade | **43** | **20** | **29** |
| S4_asia_break_go | **30** | **27** | **61** |
| S5_dual_liquidity_book | **38** | **30** | **29** |
| S3_turtle_soup | **73** | **100** | **41** |
| S1_session_break_retest | **240** | **69** | **86** |

---

## Funded: cash withdrawn (weekly >$101k) + total made

| Strategy | Window | Withdrawn | Weeks paid | Total made | End equity | Survived |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| **S6** | 2024–2025 | $150,183 | 74 | **$151,133** | $100,950 | Yes |
| **S6** | 2023–2024 | $172,284 | 76 | **$173,284** | $101,000 | Yes |
| **S6** | 2026 H1 | $24,155 | 12 | **$25,155** | $101,000 | Yes |
| **S4** | 2024–2025 | $161,327 | 83 | **$162,286** | $100,958 | Yes |
| **S4** | 2023–2024 | $189,144 | 87 | **$190,204** | $101,060 | Yes |
| **S4** | 2026 H1 | $15,321 | 12 | **$16,443** | $101,122 | Yes |
| **S5** | 2024–2025 | $163,886 | 65 | **$164,886** | $101,000 | Yes |
| **S5** | 2023–2024 | $177,000 | 70 | **$178,000** | $101,000 | Yes |
| **S5** | 2026 H1 | $14,798 | 9 | **$15,798** | $101,000 | Yes |
| **S3** | 2024–2025 | $91,363 | 46 | **$92,363** | $101,000 | Yes |
| **S3** | 2023–2024 | $95,333 | 48 | **$93,805** | $98,472 | Yes* |
| **S3** | 2026 H1 | $10,776 | 7 | **$11,698** | $100,922 | Yes |
| **S1** | 2024–2025 | $41,949 | 35 | **$35,551** | $93,601 | No (hit floor after payouts) |
| **S1** | 2023–2024 | $48,932 | 42 | **$49,932** | $101,000 | Yes |
| **S1** | 2026 H1 | $0 | 0 | **−$1,824** | $98,176 | Yes (no week ≥$250 above 101k) |

\*S3 2023–2024 end equity &lt; 101k after a late drawdown; still above $94k floor.

---

## Edge quality (full window, no target stop)

| Strategy | 2024–25 PF / PnL | 2023–24 PF / PnL | 2026 H1 PF / PnL | Trades/day |
| --- | --- | --- | --- | ---: |
| S6 Equals fade | 1.92 / +$161k | 2.06 / +$183k | 1.80 / +$36k | ~2.6 |
| S4 Asia break-go | 3.42 / +$173k | 3.41 / +$200k | 2.41 / +$27k | ~1.9 |
| S5 Dual book | 1.67 / +$176k | 1.71 / +$189k | 1.36 / +$26k | ~3.6 |
| S3 Turtle Soup | 1.50 / +$104k | 1.49 / +$105k | 1.41 / +$22k | ~2.7 |
| S1 Break-retest | 1.24 / +$46k | 1.32 / +$60k | 1.17 / +$8k | ~2.3 |

---

## Ranking for live / MT5 port (practical)

1. **S6 Equal liquidity fade** — best 2026 holdout cash + fast eval  
2. **S4 Asia break-and-go** — strongest PF; verify live slippage on marketable entries  
3. **S5 Dual liquidity book** — highest trade frequency (~3.6/day)  
4. **S3 Turtle Soup** — simple, robust across all windows  
5. **S1 Session break-retest** — solid edge but slowest eval / weakest 2026 funded

Machine-readable: `comparison_summary.json`, `comparison_table.csv`.
