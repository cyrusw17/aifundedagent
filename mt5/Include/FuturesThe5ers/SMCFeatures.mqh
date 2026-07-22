//+------------------------------------------------------------------+
//| SMCFeatures.mqh                                                  |
//| Causal SMC helpers matching mcpt/forex/smc.py + h1_sweep_bos.    |
//| Features at bar-close i → execute on bar i+1 open.               |
//|                                                                  |
//| CRITICAL: rates[] is AsSeries (0=forming). Signal uses bar>=1.   |
//| Swing windows must NEVER read rates[0] (lookahead).              |
//+------------------------------------------------------------------+
#property copyright "aifundedagent"

#ifndef FUTURES_THE5ERS_SMC_MQH
#define FUTURES_THE5ERS_SMC_MQH

//+------------------------------------------------------------------+
//| ATR as SMA of True Range (matches pandas rolling mean).          |
//| Uses only closed bars: bar, bar+1, ... (AsSeries).               |
//+------------------------------------------------------------------+
double SMC_ATR_SMA(const MqlRates &rates[], const int bar, const int period, const int copied)
{
   // Need bar .. bar+period-1 and prior closes at bar+1 .. bar+period
   if(bar < 1 || bar + period >= copied)
      return 0.0;
   double sum = 0.0;
   for(int k = 0; k < period; k++)
   {
      const int i = bar + k;
      const double tr = MathMax(rates[i].high - rates[i].low,
                        MathMax(MathAbs(rates[i].high - rates[i + 1].close),
                                MathAbs(rates[i].low  - rates[i + 1].close)));
      sum += tr;
   }
   return sum / period;
}

//+------------------------------------------------------------------+
//| Build forward-filled last confirmed swing high/low (AsSeries).   |
//|                                                                   |
//| Python (chrono, 0=oldest): at confirm i, pivot c=i-right,        |
//| window [c-left, c+right] = [i-left-right, i] — no future bars.   |
//|                                                                   |
//| AsSeries (0=newest): confirm series index j (>=1),               |
//| pivot = j+right (older), window w = j .. j+left+right.           |
//| j=0 (forming) never confirms a swing — only carries prior level. |
//+------------------------------------------------------------------+
void SMC_BuildSwingLevels(
   const MqlRates &rates[],
   const int      copied,
   const int      swing_left,
   const int      swing_right,
   double        &last_sh[],
   double        &last_sl[]
)
{
   ArrayResize(last_sh, copied);
   ArrayResize(last_sl, copied);
   double sh = EMPTY_VALUE;
   double sl = EMPTY_VALUE;

   // Oldest → newest so ffill matches Python
   for(int j = copied - 1; j >= 0; j--)
   {
      // Forming bar: never confirm (would use incomplete OHLC)
      if(j >= 1)
      {
         const int pivot = j + swing_right; // older than confirm
         const int oldest = j + swing_left + swing_right;
         if(pivot < copied && oldest < copied)
         {
            bool is_sh = true;
            bool is_sl = true;
            for(int w = j; w <= oldest; w++)
            {
               if(rates[w].high > rates[pivot].high)
                  is_sh = false;
               if(rates[w].low < rates[pivot].low)
                  is_sl = false;
            }
            if(is_sh)
               sh = rates[pivot].high;
            if(is_sl)
               sl = rates[pivot].low;
         }
      }
      last_sh[j] = sh;
      last_sl[j] = sl;
   }
}

//+------------------------------------------------------------------+
//| True if sweep-low + discount at closed bar idx (AsSeries).       |
//| Sweep level = last_sl[idx+1]  (== Python shift(1)).              |
//| EQ from last swings at idx (same-bar ffill, like Python).        |
//+------------------------------------------------------------------+
bool SMC_SweepLongAt(
   const MqlRates &rates[],
   const double   &last_sh[],
   const double   &last_sl[],
   const int       idx,
   const int       copied
)
{
   if(idx < 1 || idx + 1 >= copied)
      return false;
   const double lvl = last_sl[idx + 1];
   const double eq_hi = last_sh[idx];
   const double eq_lo = last_sl[idx];
   if(lvl == EMPTY_VALUE || eq_hi == EMPTY_VALUE || eq_lo == EMPTY_VALUE)
      return false;
   const double eq = 0.5 * (eq_hi + eq_lo);
   const bool sweep = (rates[idx].low < lvl && rates[idx].close > lvl);
   return (sweep && rates[idx].close < eq);
}

bool SMC_SweepShortAt(
   const MqlRates &rates[],
   const double   &last_sh[],
   const double   &last_sl[],
   const int       idx,
   const int       copied
)
{
   if(idx < 1 || idx + 1 >= copied)
      return false;
   const double lvl = last_sh[idx + 1];
   const double eq_hi = last_sh[idx];
   const double eq_lo = last_sl[idx];
   if(lvl == EMPTY_VALUE || eq_hi == EMPTY_VALUE || eq_lo == EMPTY_VALUE)
      return false;
   const double eq = 0.5 * (eq_hi + eq_lo);
   const bool sweep = (rates[idx].high > lvl && rates[idx].close < lvl);
   return (sweep && rates[idx].close > eq);
}

bool SMC_BosUpAt(
   const MqlRates &rates[],
   const double   &last_sh[],
   const int       idx,
   const int       copied
)
{
   if(idx < 1 || idx + 1 >= copied)
      return false;
   const double lvl = last_sh[idx + 1];
   if(lvl == EMPTY_VALUE)
      return false;
   return (rates[idx].close > lvl);
}

bool SMC_BosDnAt(
   const MqlRates &rates[],
   const double   &last_sl[],
   const int       idx,
   const int       copied
)
{
   if(idx < 1 || idx + 1 >= copied)
      return false;
   const double lvl = last_sl[idx + 1];
   if(lvl == EMPTY_VALUE)
      return false;
   return (rates[idx].close < lvl);
}

//+------------------------------------------------------------------+
//| h1_sweep_bos on last closed bar (index 1).                       |
//| Returns +1 long, -1 short, 0 flat. out_atr = ATR at signal bar.  |
//|                                                                   |
//| Lookback: sweeps on bars 2..9 only (prior 1..8), BOS on bar 1.   |
//| Never reads rates[0] OHLC for the signal decision.               |
//+------------------------------------------------------------------+
int H1SweepBosSignal(
   const string          symbol,
   const ENUM_TIMEFRAMES tf,
   const int             swing_left,
   const int             swing_right,
   const int             atr_period,
   double               &out_atr
)
{
   out_atr = 0.0;
   const int bar = 1; // last fully closed H1
   const int need = 150;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   const int copied = CopyRates(symbol, tf, 0, need, rates);
   if(copied < 80)
      return 0;

   out_atr = SMC_ATR_SMA(rates, bar, atr_period, copied);
   if(out_atr <= 0.0)
      return 0;

   double last_sh[], last_sl[];
   SMC_BuildSwingLevels(rates, copied, swing_left, swing_right, last_sh, last_sl);

   // recent sweep on prior bars only (k=1..8 → series idx = bar+k = 2..9)
   bool recent_long  = false;
   bool recent_short = false;
   for(int k = 1; k <= 8; k++)
   {
      const int idx = bar + k;
      if(SMC_SweepLongAt(rates, last_sh, last_sl, idx, copied))
         recent_long = true;
      if(SMC_SweepShortAt(rates, last_sh, last_sl, idx, copied))
         recent_short = true;
   }

   const bool bos_up = SMC_BosUpAt(rates, last_sh, bar, copied);
   const bool bos_dn = SMC_BosDnAt(rates, last_sl, bar, copied);

   if(recent_long && bos_up)
      return 1;
   if(recent_short && bos_dn)
      return -1;
   return 0;
}

#endif // FUTURES_THE5ERS_SMC_MQH
