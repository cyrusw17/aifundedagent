//+------------------------------------------------------------------+
//| FuturesThe5ersH1SweepBOS.mq5                                     |
//| MT5 EA — locked futures The5ers strategy (h1_sweep_bos).         |
//|                                                                  |
//| Research lock: data/research/best_strategy_futures_the5ers.json  |
//|   Symbols: ES, NQ, YM, CL, GC (map to broker CFD names)          |
//|   TF: H1 | risk 0.75% | RR 2.0 | ATR stop 1.25 | swing 2        |
//|   Skip Mondays | 1 entry/day | cooldown after 2 losses           |
//|   Daily halt ±3% / +5% of InitialBalance (The5ers-style)         |
//|                                                                  |
//| Causal: signal on closed H1 → market entry on new H1 open.       |
//+------------------------------------------------------------------+
#property copyright "aifundedagent"
#property version   "1.00"
#property description "The5ers futures H1 sweep→BOS (research lock)"

#include <Trade/Trade.mqh>
#include <FuturesThe5ers/SMCFeatures.mqh>
#include <FuturesThe5ers/RiskManager.mqh>

//--- Inputs (defaults = research lock)
input group "=== Symbols ==="
input string InpSymbols           = "US500,NAS100,US30,USOIL,XAUUSD"; // broker aliases for ES,NQ,YM,CL,GC
input bool   InpTradeChartOnly    = false;   // if true, ignore list and trade chart symbol only

input group "=== Signal (h1_sweep_bos) ==="
input ENUM_TIMEFRAMES InpTF       = PERIOD_H1;
input int    InpSwingLeft         = 2;
input int    InpSwingRight        = 2;
input int    InpAtrPeriod         = 14;
input double InpAtrStopMult       = 1.25;
input double InpRR                = 2.0;

input group "=== Risk / The5ers ==="
input double InpRiskPct           = 0.0075;  // 0.75% equity risk per trade
input double InpInitialBalance    = 100000.0;// used for daily halt $ and max-loss floor
input double InpMaxLoss           = 6000.0;  // absolute floor = Initial - MaxLoss
input double InpDailyHaltLossPct  = 0.03;    // halt new entries if day PnL <= -3% of Initial
input double InpDailyHaltProfitPct= 0.05;    // halt new entries if day PnL >= +5% of Initial
input double InpDailyLossKillPct  = 0.03;    // soft kill flag (no new trades) at -3% day vs Initial
input int    InpMaxPositions      = 1;       // portfolio-wide
input bool   InpSkipMondays       = true;
input bool   InpOneEntryPerDay    = true;
input int    InpCooldownLosses    = 2;       // consecutive losses → cooldown
input int    InpCooldownBars      = 2;       // H1 bars to skip after cooldown trigger

input group "=== Execution ==="
input long   InpMagic             = 20260721;
input int    InpSlippagePoints    = 30;
input int    InpMaxSpreadPoints   = 0;       // 0 = disabled
input bool   InpCloseOnFriday     = false;
input int    InpFridayHour        = 20;      // server hour

//--- State
CTrade         g_trade;
string         g_symbols[];
datetime       g_last_bar_time = 0;
datetime       g_day_stamp     = 0;
double         g_day_start_equity = 0.0;
bool           g_day_halted    = false;
bool           g_blown         = false;
int            g_consec_loss   = 0;
int            g_cooldown      = 0;
int            g_entries_today = 0;
datetime       g_last_deal_time_seen = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(InpTradeChartOnly)
   {
      ArrayResize(g_symbols, 1);
      g_symbols[0] = _Symbol;
   }
   else
   {
      string parts[];
      const int n = StringSplit(InpSymbols, ',', parts);
      ArrayResize(g_symbols, 0);
      for(int i = 0; i < n; i++)
      {
         string s = parts[i];
         StringTrimLeft(s);
         StringTrimRight(s);
         if(StringLen(s) == 0)
            continue;
         const int m = ArraySize(g_symbols);
         ArrayResize(g_symbols, m + 1);
         g_symbols[m] = s;
      }
      if(ArraySize(g_symbols) == 0)
      {
         ArrayResize(g_symbols, 1);
         g_symbols[0] = _Symbol;
      }
   }

   for(int i = 0; i < ArraySize(g_symbols); i++)
   {
      if(!SymbolSelect(g_symbols[i], true))
         Print("WARN: SymbolSelect failed for ", g_symbols[i], " — map names to your broker");
   }

   g_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_day_stamp = DayStamp(TimeCurrent());
   g_last_deal_time_seen = TimeCurrent();

   Print("FuturesThe5ersH1SweepBOS init | symbols=", ArraySize(g_symbols),
         " risk=", InpRiskPct, " RR=", InpRR, " ATR*=", InpAtrStopMult);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
datetime DayStamp(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
void ResetDayIfNeeded()
{
   const datetime today = DayStamp(TimeCurrent());
   if(today != g_day_stamp)
   {
      g_day_stamp = today;
      g_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_day_halted = false;
      g_entries_today = 0;
      // do not reset consec_loss / cooldown across days (matches continuous sim better)
   }
}

//+------------------------------------------------------------------+
void UpdateDealOutcomes()
{
   // Detect newly closed deals for this magic to update loss streak / cooldown.
   if(!HistorySelect(g_last_deal_time_seen - 86400, TimeCurrent() + 60))
      return;

   const int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT &&
         HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT_BY)
         continue;

      const datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(t <= g_last_deal_time_seen)
         continue;

      const double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                          + HistoryDealGetDouble(ticket, DEAL_SWAP)
                          + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      if(profit < 0.0)
      {
         g_consec_loss++;
         if(InpCooldownLosses > 0 && g_consec_loss >= InpCooldownLosses)
         {
            g_cooldown = InpCooldownBars;
            g_consec_loss = 0;
            Print("Cooldown armed for ", g_cooldown, " H1 bars after consecutive losses");
         }
      }
      else if(profit > 0.0)
      {
         g_consec_loss = 0;
      }
      g_last_deal_time_seen = t;
   }
}

//+------------------------------------------------------------------+
bool RiskAllowsEntry(const double equity)
{
   if(g_blown || g_day_halted)
      return false;
   if(g_cooldown > 0)
      return false;
   if(RM_CountPositions(InpMagic) >= InpMaxPositions)
      return false;
   if(InpOneEntryPerDay && g_entries_today >= 1)
      return false;
   if(InpSkipMondays && RM_IsMonday(TimeCurrent()))
      return false;

   const double floor_bal = InpInitialBalance - InpMaxLoss;
   if(equity <= floor_bal)
   {
      g_blown = true;
      Print("BLOWN: equity ", equity, " <= floor ", floor_bal);
      return false;
   }

   const double day_pnl = equity - g_day_start_equity;
   if(day_pnl <= -InpInitialBalance * InpDailyHaltLossPct)
   {
      g_day_halted = true;
      return false;
   }
   if(day_pnl >= InpInitialBalance * InpDailyHaltProfitPct)
   {
      g_day_halted = true;
      return false;
   }
   if(day_pnl <= -InpInitialBalance * InpDailyLossKillPct)
   {
      g_day_halted = true;
      return false;
   }

   if(InpCloseOnFriday)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5 && dt.hour >= InpFridayHour)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool SpreadOk(const string symbol)
{
   if(InpMaxSpreadPoints <= 0)
      return true;
   const long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   return (spread <= InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
bool OpenTrade(const string symbol, const int direction, const double atr)
{
   if(direction == 0 || atr <= 0.0)
      return false;
   if(!SpreadOk(symbol))
      return false;

   const double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return false;

   const double entry = (direction > 0) ? ask : bid;
   const double dist  = InpAtrStopMult * atr;
   const double stop  = (direction > 0) ? (entry - dist) : (entry + dist);
   const double take  = (direction > 0) ? (entry + InpRR * dist) : (entry - InpRR * dist);

   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double floor_bal = InpInitialBalance - InpMaxLoss;
   const double room = MathMax(equity - floor_bal, 0.0);
   double risk = equity * InpRiskPct;
   risk = MathMin(risk, room * 0.45);

   const double day_pnl = equity - g_day_start_equity;
   const double daily_lim = InpInitialBalance * InpDailyHaltLossPct;
   const double daily_room = MathMax(daily_lim - MathMax(0.0, -day_pnl), 0.0);
   risk = MathMin(risk, daily_room * 0.5);

   if(risk < equity * 0.001)
      return false;

   const double lots = RM_LotsForRisk(symbol, entry, stop, risk);
   if(lots <= 0.0)
   {
      Print("Lot size 0 for ", symbol, " risk=", risk, " dist=", dist);
      return false;
   }

   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   const double sl = NormalizeDouble(stop, digits);
   const double tp = NormalizeDouble(take, digits);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(symbol);

   bool ok = false;
   if(direction > 0)
      ok = g_trade.Buy(lots, symbol, 0.0, sl, tp, "H1SweepBOS L");
   else
      ok = g_trade.Sell(lots, symbol, 0.0, sl, tp, "H1SweepBOS S");

   if(ok)
   {
      g_entries_today++;
      Print("OPEN ", (direction > 0 ? "BUY" : "SELL"), " ", symbol,
            " lots=", lots, " sl=", sl, " tp=", tp, " atr=", atr, " risk$=", risk);
   }
   else
   {
      Print("Order failed ", symbol, " retcode=", g_trade.ResultRetcode(),
            " ", g_trade.ResultRetcodeDescription());
   }
   return ok;
}

//+------------------------------------------------------------------+
void OnNewBar()
{
   ResetDayIfNeeded();
   UpdateDealOutcomes();

   if(g_cooldown > 0)
      g_cooldown--;

   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!RiskAllowsEntry(equity))
      return;

   // Scan symbols in order; take first valid signal (max 1 position).
   for(int i = 0; i < ArraySize(g_symbols); i++)
   {
      const string sym = g_symbols[i];
      if(!SymbolSelect(sym, true))
         continue;
      if(RM_CountPositions(InpMagic, sym) > 0)
         continue;

      double atr = 0.0;
      const int sig = H1SweepBosSignal(sym, InpTF, InpSwingLeft, InpSwingRight, InpAtrPeriod, atr);
      if(sig == 0)
         continue;

      if(OpenTrade(sym, sig, atr))
         break; // one entry
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   ResetDayIfNeeded();

   // Soft blow / halt checks every tick
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double floor_bal = InpInitialBalance - InpMaxLoss;
   if(equity <= floor_bal)
      g_blown = true;

   const double day_pnl = equity - g_day_start_equity;
   if(day_pnl <= -InpInitialBalance * InpDailyHaltLossPct ||
      day_pnl >=  InpInitialBalance * InpDailyHaltProfitPct)
      g_day_halted = true;

   datetime t[];
   if(CopyTime(_Symbol, InpTF, 0, 1, t) < 1)
      return;
   if(t[0] == g_last_bar_time)
      return;
   g_last_bar_time = t[0];
   OnNewBar();
}

//+------------------------------------------------------------------+
