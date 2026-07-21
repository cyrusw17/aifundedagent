//+------------------------------------------------------------------+
//| SMCFeatures.mqh                                                  |
//| Causal SMC helpers matching mcpt/forex/smc.py + h1_sweep_bos.    |
//| Features at bar-close i → execute on bar i+1 open.               |
//+------------------------------------------------------------------+
#property copyright "aifundedagent"

#ifndef FUTURES_THE5ERS_SMC_MQH
#define FUTURES_THE5ERS_SMC_MQH

//+------------------------------------------------------------------+
//| ATR as SMA of True Range (matches pandas rolling mean).          |
//+------------------------------------------------------------------+
double SMC_ATR_SMA(const MqlRates &rates[], const int bar, const int period, const int copied)
{
   if(bar + period >= copied)
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
//| Build forward-filled last confirmed swing high/low arrays.       |
//| Series rates: index 0 = newest. Confirmation uses left/right.    |
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

   for(int j = copied - 1; j >= 0; j--)
   {
      const int c = j - swing_right;
      if(c - swing_left >= 0 && j >= swing_left + swing_right)
      {
         bool is_sh = true;
         bool is_sl = true;
         for(int w = c - swing_left; w <= c + swing_right; w++)
         {
            if(rates[w].high > rates[c].high)
               is_sh = false;
            if(rates[w].low < rates[c].low)
               is_sl = false;
         }
         if(is_sh)
            sh = rates[c].high;
         if(is_sl)
            sl = rates[c].low;
      }
      last_sh[j] = sh;
      last_sl[j] = sl;
   }
}

//+------------------------------------------------------------------+
//| h1_sweep_bos on last closed bar (index 1).                       |
//| Returns +1 long, -1 short, 0 flat. out_atr = ATR at signal bar.  |
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
   const int bar = 1;
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

   bool recent_long  = false;
   bool recent_short = false;

   for(int k = 1; k <= 8; k++)
   {
      const int idx = bar + k;
      if(idx + 1 >= copied)
         continue;

      const double sl_prev = last_sl[idx + 1];
      const double sh_prev = last_sh[idx + 1];
      const double eq_hi   = last_sh[idx];
      const double eq_lo   = last_sl[idx];
      if(eq_hi == EMPTY_VALUE || eq_lo == EMPTY_VALUE)
         continue;

      const double eq = 0.5 * (eq_hi + eq_lo);

      if(sl_prev != EMPTY_VALUE)
      {
         const bool sweep_l = (rates[idx].low < sl_prev && rates[idx].close > sl_prev);
         if(sweep_l && rates[idx].close < eq)
            recent_long = true;
      }
      if(sh_prev != EMPTY_VALUE)
      {
         const bool sweep_h = (rates[idx].high > sh_prev && rates[idx].close < sh_prev);
         if(sweep_h && rates[idx].close > eq)
            recent_short = true;
      }
   }

   bool bos_up = false;
   bool bos_dn = false;
   if(bar + 1 < copied)
   {
      const double sh_prev = last_sh[bar + 1];
      const double sl_prev = last_sl[bar + 1];
      if(sh_prev != EMPTY_VALUE)
         bos_up = (rates[bar].close > sh_prev);
      if(sl_prev != EMPTY_VALUE)
         bos_dn = (rates[bar].close < sl_prev);
   }

   if(recent_long && bos_up)
      return 1;
   if(recent_short && bos_dn)
      return -1;
   return 0;
}

#endif // FUTURES_THE5ERS_SMC_MQH
