//+------------------------------------------------------------------+
//| S6_EqLiquidityFade.mq5                                           |
//| Equal highs/lows sweep fade (ICT) — port of Python S6            |
//| Causal: signals only on closed M15 bars.                         |
//|                                                                  |
//| Install: MetaEditor → File → Open Data Folder → MQL5/Experts/    |
//|          copy this file → Compile (F7) → attach to chart         |
//| Recommended: attach to M15 chart of EURUSD (or any symbol).      |
//| Works on any chart TF (internally uses M15 + H1).                |
//+------------------------------------------------------------------+
#property copyright "aifundedagent"
#property link      "https://github.com/cyrusw17/aifundedagent"
#property version   "1.10"
#property strict
#property description "S6 Equal H/L sweep fade — The5ers-oriented day EA"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//------------------------------ inputs --------------------------------
input group "=== Risk (The5ers-style) ==="
input double InpRiskPercent        = 0.40;    // Risk % of initial balance per trade
input double InpRewardRisk         = 1.5;     // Take profit R-multiple
input double InpDailyLossLimitPct  = 3.0;     // Pause trading for day at -X% of initial
input double InpMaxLossPct         = 6.0;     // Hard floor: stop EA at -X% of initial
input double InpDailyProfitCapPct  = 4.5;     // Soft daily profit cap (% of initial)
input double InpInitialBalance     = 0.0;     // 0 = capture balance on attach
input int    InpMagic              = 6062026; // Magic number
input int    InpMaxTradesPerDay    = 3;       // Max filled trades / symbol / day
input int    InpMaxOpenPositions   = 1;       // Max open positions for this EA
input int    InpSlippagePoints     = 30;      // Deviation for market mods

input group "=== Strategy (S6 defaults match backtest) ==="
input int    InpSwingLeft          = 3;
input int    InpSwingRight         = 3;
input int    InpAtrPeriod          = 14;
input double InpEqualTolAtr        = 0.15;    // Equal H/L tolerance in ATR
input double InpStopBufferAtr      = 0.15;    // SL buffer beyond sweep in ATR
input double InpMinStopAtr         = 0.80;
input double InpMaxStopAtr         = 2.20;
input int    InpH1SwingLeft        = 2;
input int    InpH1SwingRight       = 2;
input int    InpLimitExpiryBars    = 16;      // Cancel pending after N M15 bars (~4h)
input bool   InpRequireH1Bias      = true;    // Match backtest bias filter

input group "=== Sessions (UTC / GMT — matches backtest) ==="
input int    InpKZ1Start           = 7;       // Killzone 1 start hour UTC
input int    InpKZ1End             = 11;      // Killzone 1 end hour UTC (exclusive)
input int    InpKZ2Start           = 12;
input int    InpKZ2End             = 17;
input int    InpFlattenHourUTC     = 20;      // Flatten open positions from this UTC hour
input bool   InpUseGMT             = true;    // true=TimeGMT(); false=TimeCurrent()+offset
input int    InpServerToUtcOffset  = 0;       // If UseGMT=false: UTC = server + this (hours)

input group "=== Misc ==="
input bool   InpTradeLong          = true;
input bool   InpTradeShort         = true;
input bool   InpMoveToBE           = true;    // Move SL to BE after +1R
input double InpBEOffsetPoints     = 5;       // BE offset in points (cover commission)
input bool   InpLogSignals         = true;

//------------------------------ state ---------------------------------
CTrade         g_trade;
CPositionInfo  g_pos;
COrderInfo     g_order;

double   g_initialBalance = 0.0;
datetime g_lastM15Bar     = 0;
int      g_dayStamp       = 0;   // yyyymmdd UTC
int      g_tradesToday    = 0;
double   g_dayStartEquity = 0.0;
double   g_dayRealized    = 0.0;
bool     g_dayPaused      = false;
bool     g_hardStopped    = false;
bool     g_usedEqHighDay  = false; // one short setup / day
bool     g_usedEqLowDay   = false; // one long setup / day

#define M15_BARS  400
#define H1_BARS   200

//------------------------------ utils ---------------------------------
string TfName(ENUM_TIMEFRAMES tf) { return EnumToString(tf); }

datetime NowUtc()
{
   if(InpUseGMT)
      return TimeGMT();
   return TimeCurrent() + InpServerToUtcOffset * 3600;
}

void UtcParts(datetime t, MqlDateTime &dt)
{
   TimeToStruct(t, dt);
}

int DayStampUtc(datetime t)
{
   MqlDateTime dt;
   UtcParts(t, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

bool InKillzoneUtc(datetime t)
{
   MqlDateTime dt;
   UtcParts(t, dt);
   int h = dt.hour;
   if(h >= InpKZ1Start && h < InpKZ1End) return true;
   if(h >= InpKZ2Start && h < InpKZ2End) return true;
   return false;
}

bool IsNewM15Bar()
{
   datetime t[];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, t) != 1)
      return false;
   if(t[0] != g_lastM15Bar)
   {
      g_lastM15Bar = t[0];
      return true;
   }
   return false;
}

void ResetDayIfNeeded()
{
   int stamp = DayStampUtc(NowUtc());
   if(stamp == g_dayStamp)
      return;
   g_dayStamp       = stamp;
   g_tradesToday    = 0;
   g_dayRealized    = 0.0;
   g_dayPaused      = false;
   g_usedEqHighDay  = false;
   g_usedEqLowDay   = false;
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
}

double Equity()
{
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

bool HardFloorBreached()
{
   double floor = g_initialBalance * (1.0 - InpMaxLossPct / 100.0);
   return Equity() <= floor;
}

bool DailyLossBreached()
{
   double limit = g_initialBalance * (InpDailyLossLimitPct / 100.0);
   return (g_dayStartEquity - Equity()) >= limit;
}

bool DailyProfitCapped()
{
   double cap = g_initialBalance * (InpDailyProfitCapPct / 100.0);
   return g_dayRealized >= cap;
}

int CountOurPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      if(g_pos.Magic() != InpMagic) continue;
      n++;
   }
   return n;
}

int CountOurPendings()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!g_order.SelectByIndex(i)) continue;
      if(g_order.Symbol() != _Symbol) continue;
      if(g_order.Magic() != InpMagic) continue;
      n++;
   }
   return n;
}

void CancelOurPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!g_order.SelectByIndex(i)) continue;
      if(g_order.Symbol() != _Symbol) continue;
      if(g_order.Magic() != InpMagic) continue;
      g_trade.OrderDelete(g_order.Ticket());
   }
}

double NormalizeVolume(double lots)
{
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0) vstep = 0.01;
   lots = MathFloor(lots / vstep) * vstep;
   if(lots < vmin) lots = 0;
   if(lots > vmax) lots = vmax;
   return NormalizeDouble(lots, 2);
}

double LotsForRisk(double entry, double sl)
{
   double riskMoney = g_initialBalance * (InpRiskPercent / 100.0);
   double slDist = MathAbs(entry - sl);
   if(slDist <= 0 || riskMoney <= 0)
      return 0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0)
      return 0;

   double ticks = slDist / tickSize;
   double lots  = riskMoney / (ticks * tickValue);
   return NormalizeVolume(lots);
}

double ATR_M15(int shift)
{
   // ATR of closed bars ending at `shift` (shift>=1 preferred)
   int need = InpAtrPeriod + shift + 2;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M15, 0, need, rates) < need)
      return 0;

   double sum = 0;
   for(int i = shift; i < shift + InpAtrPeriod; i++)
   {
      double prevClose = rates[i + 1].close;
      double tr = MathMax(rates[i].high - rates[i].low,
                   MathMax(MathAbs(rates[i].high - prevClose),
                           MathAbs(rates[i].low - prevClose)));
      sum += tr;
   }
   return sum / InpAtrPeriod;
}

//----------------------- swing / bias helpers -------------------------
bool IsSwingHigh(const MqlRates &rates[], int p, int left, int right)
{
   // rates[] series=true: index 0 newest. Pivot at p must have left newer? 
   // We store chronological arrays (series=false) for clarity in scanners.
   return false; // unused
}

// Chronological rates: index 0 = oldest
bool CopyRatesChrono(ENUM_TIMEFRAMES tf, int count, MqlRates &out[])
{
   MqlRates tmp[];
   ArraySetAsSeries(tmp, true);
   int n = CopyRates(_Symbol, tf, 0, count, tmp);
   if(n <= 0) return false;
   ArrayResize(out, n);
   // reverse to chronological (oldest first)
   for(int i = 0; i < n; i++)
      out[i] = tmp[n - 1 - i];
   return true;
}

struct Swing
{
   int    idx;
   double price;
};

int CollectSwings(const MqlRates &r[], int left, int right, bool highs, Swing &out[], int maxOut)
{
   int n = ArraySize(r);
   int count = 0;
   ArrayResize(out, 0);
   for(int p = left; p < n - right; p++)
   {
      if(highs)
      {
         int firstMax = p - left;
         for(int k = p - left; k <= p + right; k++)
            if(r[k].high > r[firstMax].high)
               firstMax = k;
         if(firstMax != p)
            continue;
      }
      else
      {
         int firstMin = p - left;
         for(int k = p - left; k <= p + right; k++)
            if(r[k].low < r[firstMin].low)
               firstMin = k;
         if(firstMin != p)
            continue;
      }
      ArrayResize(out, count + 1);
      out[count].idx = p;
      out[count].price = highs ? r[p].high : r[p].low;
      count++;
      if(count >= maxOut)
         break;
   }
   return count;
}

int H1BiasAt(datetime m15BarTime)
{
   // Bias from last *closed* H1 before this M15 bar (shift 1 closed H1)
   MqlRates h1[];
   if(!CopyRatesChrono(PERIOD_H1, H1_BARS, h1))
      return 0;
   int n = ArraySize(h1);
   if(n < 30) return 0;

   // last fully closed H1 is the bar whose time + period <= m15BarTime
   int lastClosed = -1;
   for(int i = 0; i < n; i++)
   {
      datetime end = h1[i].time + PeriodSeconds(PERIOD_H1);
      if(end <= m15BarTime)
         lastClosed = i;
      else
         break;
   }
   // shift(1): use previous closed H1 for structure end index
   int use = lastClosed - 1;
   if(use < 20) return 0;

   Swing sh[], sl[];
   CollectSwings(h1, InpH1SwingLeft, InpH1SwingRight, true,  sh, 80);
   CollectSwings(h1, InpH1SwingLeft, InpH1SwingRight, false, sl, 80);

   // Keep only swings confirmed by use (confirm = idx + right <= use)
   Swing ksh[], ksl[];
   int nsh = 0, nsl = 0;
   for(int i = 0; i < ArraySize(sh); i++)
   {
      if(sh[i].idx + InpH1SwingRight <= use)
      {
         ArrayResize(ksh, nsh + 1);
         ksh[nsh++] = sh[i];
      }
   }
   for(int i = 0; i < ArraySize(sl); i++)
   {
      if(sl[i].idx + InpH1SwingRight <= use)
      {
         ArrayResize(ksl, nsl + 1);
         ksl[nsl++] = sl[i];
      }
   }
   if(nsh < 2 || nsl < 2) return 0;

   bool hh = ksh[nsh - 1].price > ksh[nsh - 2].price;
   bool hl = ksl[nsl - 1].price > ksl[nsl - 2].price;
   bool lh = ksh[nsh - 1].price < ksh[nsh - 2].price;
   bool ll = ksl[nsl - 1].price < ksl[nsl - 2].price;
   if(hh && hl) return 1;
   if(lh && ll) return -1;
   return 0;
}

//----------------------- order / manage -------------------------------
bool PlaceLimit(int side, double entry, double sl, double tp, string comment)
{
   double lots = LotsForRisk(entry, sl);
   if(lots <= 0)
   {
      Print("S6: lot size 0 — check stops / symbol tick value");
      return false;
   }

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl, _Digits);
   tp    = NormalizeDouble(tp, _Digits);

   // Stops level
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDist = stops * point;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   datetime expiry = TimeCurrent() + InpLimitExpiryBars * PeriodSeconds(PERIOD_M15);

   bool ok = false;
   if(side > 0)
   {
      // Buy limit below market
      if(entry >= ask - minDist)
         entry = NormalizeDouble(ask - MathMax(minDist, 10 * point), _Digits);
      if(sl >= entry)
         return false;
      ok = g_trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, comment);
   }
   else
   {
      if(entry <= bid + minDist)
         entry = NormalizeDouble(bid + MathMax(minDist, 10 * point), _Digits);
      if(sl <= entry)
         return false;
      ok = g_trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, comment);
   }

   if(!ok)
      Print("S6: order failed ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
   else if(InpLogSignals)
      PrintFormat("S6: %s limit %.5f SL %.5f TP %.5f lots %.2f", comment, entry, sl, tp, lots);
   return ok;
}

void ManageOpenPositions()
{
   datetime now = NowUtc();
   MqlDateTime dt;
   UtcParts(now, dt);
   bool flatten = (dt.hour >= InpFlattenHourUTC);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      if(g_pos.Magic() != InpMagic) continue;

      ulong ticket = g_pos.Ticket();
      double open  = g_pos.PriceOpen();
      double sl    = g_pos.StopLoss();
      double tp    = g_pos.TakeProfit();
      long   type  = g_pos.PositionType();

      if(flatten)
      {
         g_trade.PositionClose(ticket);
         if(InpLogSignals) Print("S6: flatten UTC hour ", dt.hour);
         continue;
      }

      if(!InpMoveToBE || tp == 0 || sl == 0)
         continue;

      double risk = MathAbs(open - sl);
      if(risk <= 0) continue;
      double be = open;
      double beOff = InpBEOffsetPoints * _Point;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         if(bid >= open + risk)
         {
            double newSL = NormalizeDouble(be + beOff, _Digits);
            if(sl < newSL)
               g_trade.PositionModify(ticket, newSL, tp);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(ask <= open - risk)
         {
            double newSL = NormalizeDouble(be - beOff, _Digits);
            if(sl > newSL || sl == 0)
               g_trade.PositionModify(ticket, newSL, tp);
         }
      }
   }
}

//----------------------- signal on closed M15 -------------------------
void EvaluateClosedBar()
{
   // Use chronological M15; last index = newest closed? We include bar 0 forming —
   // signal only on the last *closed* bar = n-2 when series chrono includes forming.
   MqlRates m15[];
   if(!CopyRatesChrono(PERIOD_M15, M15_BARS, m15))
      return;
   int n = ArraySize(m15);
   if(n < InpAtrPeriod + 80)
      return;

   // Drop forming bar (last) so i = n-1 is last closed
   // CopyRates includes bar 0 forming as newest when series=true; after reverse,
   // last element is forming. Confirm: Time of last vs current M15 open.
   datetime curOpen[];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, curOpen) == 1)
   {
      if(m15[n - 1].time == curOpen[0])
      {
         ArrayResize(m15, n - 1);
         n--;
      }
   }
   if(n < InpAtrPeriod + 80)
      return;

   int i = n - 1; // last closed
   datetime barTime = m15[i].time;

   // Killzone on bar close time in UTC: bar time is broker server time.
   // Convert server bar time → UTC roughly via NowUtc offset approach:
   // Prefer: interpret killzone using GMT clock at bar close moment.
   // Approximate: if UseGMT, shift bar time by (TimeGMT()-TimeCurrent()).
   datetime barUtc = barTime;
   if(InpUseGMT)
      barUtc = barTime + (TimeGMT() - TimeCurrent());
   else
      barUtc = barTime + InpServerToUtcOffset * 3600;

   if(!InKillzoneUtc(barUtc))
      return;

   // ATR at closed bar i
   double atr = 0;
   if(i < InpAtrPeriod) return;
   {
      double sum = 0;
      for(int k = i - InpAtrPeriod + 1; k <= i; k++)
      {
         double prev = m15[k - 1].close;
         double tr = MathMax(m15[k].high - m15[k].low,
                      MathMax(MathAbs(m15[k].high - prev), MathAbs(m15[k].low - prev)));
         sum += tr;
      }
      atr = sum / InpAtrPeriod;
   }
   if(atr <= 0) return;

   int bias = H1BiasAt(barTime + PeriodSeconds(PERIOD_M15)); // after bar close
   if(InpRequireH1Bias && bias == 0)
   {
      // allow 0 as neutral in python (>=0 / <=0). Neutral OK.
   }

   Swing sh[], sl[];
   CollectSwings(m15, InpSwingLeft, InpSwingRight, true,  sh, 120);
   CollectSwings(m15, InpSwingLeft, InpSwingRight, false, sl, 120);

   // Known swings confirmed before i: confirmIdx = pivot+right < i  (pivot < i for use)
   // Python: known after confirm at p+right; then highs with p < i
   Swing highs[], lows[];
   int nh = 0, nl = 0;
   for(int s = 0; s < ArraySize(sh); s++)
   {
      int conf = sh[s].idx + InpSwingRight;
      if(conf <= i && sh[s].idx < i)
      {
         ArrayResize(highs, nh + 1);
         highs[nh++] = sh[s];
      }
   }
   for(int s = 0; s < ArraySize(sl); s++)
   {
      int conf = sl[s].idx + InpSwingRight;
      if(conf <= i && sl[s].idx < i)
      {
         ArrayResize(lows, nl + 1);
         lows[nl++] = sl[s];
      }
   }

   // last 6
   int hStart = MathMax(0, nh - 6);
   int lStart = MathMax(0, nl - 6);
   double tol = InpEqualTolAtr * atr;

   double eqHigh = 0;
   bool haveEqH = false;
   for(int a = hStart; a < nh; a++)
      for(int b = a + 1; b < nh; b++)
         if(MathAbs(highs[a].price - highs[b].price) <= tol)
         {
            double v = MathMax(highs[a].price, highs[b].price);
            if(!haveEqH || v > eqHigh) { eqHigh = v; haveEqH = true; }
         }

   double eqLow = 0;
   bool haveEqL = false;
   for(int a = lStart; a < nl; a++)
      for(int b = a + 1; b < nl; b++)
         if(MathAbs(lows[a].price - lows[b].price) <= tol)
         {
            double v = MathMin(lows[a].price, lows[b].price);
            if(!haveEqL || v < eqLow) { eqLow = v; haveEqL = true; }
         }

   double o = m15[i].open, h = m15[i].high, l = m15[i].low, c = m15[i].close;

   // Short: sweep equal highs
   if(InpTradeShort && haveEqH && !g_usedEqHighDay && bias <= 0)
   {
      if(h > eqHigh && c < eqHigh && c < o)
      {
         double entry = eqHigh;
         double stop  = h + InpStopBufferAtr * atr;
         double dist  = MathAbs(entry - stop);
         if(dist < InpMinStopAtr * atr)
            stop = entry + InpMinStopAtr * atr;
         dist = MathAbs(entry - stop);
         if(dist <= InpMaxStopAtr * atr)
         {
            double tp = entry - InpRewardRisk * dist;
            if(PlaceLimit(-1, entry, stop, tp, "S6_eqh_fade"))
            {
               g_usedEqHighDay = true;
               return; // one new pending per bar
            }
         }
      }
   }

   // Long: sweep equal lows
   if(InpTradeLong && haveEqL && !g_usedEqLowDay && bias >= 0)
   {
      if(l < eqLow && c > eqLow && c > o)
      {
         double entry = eqLow;
         double stop  = l - InpStopBufferAtr * atr;
         double dist  = MathAbs(entry - stop);
         if(dist < InpMinStopAtr * atr)
            stop = entry - InpMinStopAtr * atr;
         dist = MathAbs(entry - stop);
         if(dist <= InpMaxStopAtr * atr)
         {
            double tp = entry + InpRewardRisk * dist;
            if(PlaceLimit(1, entry, stop, tp, "S6_eql_fade"))
               g_usedEqLowDay = true;
         }
      }
   }
}

//----------------------- events ---------------------------------------
int OnInit()
{
   g_initialBalance = (InpInitialBalance > 0.0 ? InpInitialBalance : AccountInfoDouble(ACCOUNT_BALANCE));
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStamp = DayStampUtc(NowUtc());
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   PrintFormat("S6 EqLiquidityFade init | balance=%.2f | symbol=%s | magic=%d | GMT=%s",
               g_initialBalance, _Symbol, InpMagic, InpUseGMT ? "yes" : "no");
   Print("Tip: set InpUseGMT=true to match backtest killzones (07-11 & 12-17 UTC).");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   ResetDayIfNeeded();

   if(g_hardStopped)
      return;

   if(HardFloorBreached())
   {
      g_hardStopped = true;
      CancelOurPendings();
      Print("S6: HARD STOP — max loss floor reached. EA paused.");
      return;
   }

   ManageOpenPositions();

   if(DailyLossBreached())
   {
      if(!g_dayPaused)
      {
         g_dayPaused = true;
         CancelOurPendings();
         Print("S6: daily loss pause active");
      }
      return;
   }

   if(g_dayPaused || DailyProfitCapped())
      return;

   if(CountOurPositions() >= InpMaxOpenPositions)
      return;
   if(g_tradesToday >= InpMaxTradesPerDay)
      return;
   if(CountOurPendings() > 0)
      return; // wait — one pending at a time

   // New M15 bar (forming just started ⇒ previous closed)
   if(!IsNewM15Bar())
      return;

   EvaluateClosedBar();
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Count fills for daily trade cap / realized
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
         if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
         long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
            g_tradesToday++;
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
            g_dayRealized += HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                           + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                           + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      }
   }
}
//+------------------------------------------------------------------+
