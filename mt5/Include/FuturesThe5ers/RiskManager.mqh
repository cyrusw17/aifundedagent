//+------------------------------------------------------------------+
//| RiskManager.mqh                                                  |
//| Position sizing + The5ers-style daily halt / cooldown helpers.   |
//+------------------------------------------------------------------+
#property copyright "aifundedagent"

#ifndef FUTURES_THE5ERS_RISK_MQH
#define FUTURES_THE5ERS_RISK_MQH

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Normalize volume to symbol limits.                               |
//+------------------------------------------------------------------+
double RM_NormalizeLots(const string symbol, double lots)
{
   const double vmin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   const double vmax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   const double vstep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0)
      return 0.0;
   lots = MathFloor(lots / vstep) * vstep;
   if(lots < vmin)
      return 0.0;
   if(lots > vmax)
      lots = vmax;
   const int digits = (int)MathMax(0, MathCeil(-MathLog10(vstep)));
   return NormalizeDouble(lots, digits);
}

//+------------------------------------------------------------------+
//| Lots so that stop distance ≈ risk_money.                         |
//+------------------------------------------------------------------+
double RM_LotsForRisk(
   const string symbol,
   const double entry,
   const double stop,
   const double risk_money
)
{
   if(risk_money <= 0.0 || entry <= 0.0)
      return 0.0;

   const double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return 0.0;

   const double dist = MathAbs(entry - stop);
   if(dist <= 0.0)
      return 0.0;

   const double ticks = dist / tick_size;
   if(ticks <= 0.0)
      return 0.0;

   const double lots = risk_money / (ticks * tick_value);
   return RM_NormalizeLots(symbol, lots);
}

//+------------------------------------------------------------------+
//| Count open positions for magic (optionally one symbol).          |
//+------------------------------------------------------------------+
int RM_CountPositions(const long magic, const string symbol = NULL)
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      if(symbol != NULL && symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| True if today is Monday on the chart/server time.                |
//+------------------------------------------------------------------+
bool RM_IsMonday(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   // MQL5: 0=Sunday, 1=Monday, ... 6=Saturday
   return (dt.day_of_week == 1);
}

#endif // FUTURES_THE5ERS_RISK_MQH
