# Smart Money / ICT / TJR Concepts Used in Strategy Design

Reference notes distilled into causal (no look-ahead) features for the forex MCPT stack.
These are *structural* ideas used as confluence filters — not guaranteed edges.

## Core concepts

### 1. Liquidity (stops)
- Buy-side liquidity sits above swing highs (stop-losses of shorts / breakout buys).
- Sell-side liquidity sits below swing lows.
- A **liquidity sweep** is a brief pierce beyond a swing then close back inside the range.
- We only detect sweeps on a *completed* bar (close known). Entry is deferred to the next bar open.

### 2. Fair Value Gap (FVG / imbalance)
- Bullish FVG: `low[i] > high[i-2]` after an impulsive up move (3-candle gap).
- Bearish FVG: `high[i] < low[i-2]`.
- Mitigated when price later trades through the gap zone.
- Features mark active (unmitigated) gaps only using past bars.

### 3. Order blocks (OB)
- Bullish OB: last bearish candle before a decisive bullish displacement that breaks structure.
- Bearish OB: last bullish candle before bearish displacement.
- Used as a zone confluence, not a standalone trigger.

### 4. Market structure
- Bullish BOS: close above prior swing high.
- Bearish BOS: close below prior swing low.
- CHoCH: first opposite BOS after an established trend bias.

### 5. Premium / discount
- From the active swing range, equilibrium = midpoint.
- Longs preferred in **discount** (below eq); shorts in **premium** (above eq).

### 6. Sessions / killzones (intraday)
- London: ~07:00–10:00 UTC
- New York: ~12:00–15:00 UTC
- Asia range often provides liquidity for later London sweeps.
- On daily bars we approximate with weekday seasonality instead.

### 7. TJR-style confluence stacking
- Bias (HTF structure) + liquidity event + displacement/FVG + session window + RR filter.
- Trade only when multiple independent conditions agree.

### 8. Risk for prop / funded rules (The5ers-style from challenge card)
- Account: $100,000
- Evaluation profit target: 10%
- Max loss: $6,000 (static)
- Daily loss: 3% / $3,000
- Consistency: best day ≤ 50% of total profit
- Funded: weekly withdraw of equity above $100k; min withdraw $250; cap $2,000/week modeled

Position size from stop distance so risk per trade stays well under daily loss (default 0.5%–0.75% equity).
