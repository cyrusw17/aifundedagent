# Risk & Funded-Account Operating Rules

## Risk geometry (SMC-native)
- Invalidation = structural, not arbitrary pips
- Size = `(account_risk_$) / (entry - stop)` in position units
- Prefer ideas where stop is tight **because sweep already defined extreme**, not because you squeezed a bad stop

## Suggested baseline (adapt to firm)
- Risk **0.25–0.5%** per A+ idea while evaluating
- Max **1–2** attempts per narrative per session
- Daily circuit breaker: stop trading at −1R to −2R (firm-dependent)
- No trading news blind unless your model *is* the volatility raid (advanced)

## Management templates
1. **Scale**: partial at IRL (internal liquidity), runner to ERL (external)
2. **BE logic**: only after meaningful displacement in your favor or TP1 — not on random noise
3. **Trail**: under/above LTF structure once expansion is underway

## Psychology rules that save funded accounts
- One loss does not change bias; **structure** does
- Missed trade ≠ lost money
- Overtrading after a win is as deadly as revenge after a loss
- Protect consistency metrics firms care about (profit factor, drawdown, rule adherence)

## What this knowledge base is for
Use it to:
- Train decision quality
- Standardize journaling language
- Power an AI agent checklist before suggesting entries

Not for:
- Guaranteed signals
- Ignoring broker/firm rules
- Martingale / grid / “recovery” nonsense
