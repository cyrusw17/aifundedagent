//+------------------------------------------------------------------+
//| S6_EqLiquidityFade.mq5                                           |
//| Equal highs/lows sweep fade (ICT) — port of Python S6            |
//| Causal: signals only on closed M15 bars.                         |
//|                                                                  |
//| Strategy Tester ready:                                           |
//|   Symbol: EURUSD (or any) | Period: M15 | Model: Every tick      |
//|   Deposit: 100000 | Leverage: 1:100                              |
//|   Inputs: leave defaults; InpUseGMT=true                         |
//| Live: copy to MQL5/Experts → F7 → attach chart → Algo Trading    |
//+------------------------------------------------------------------+
#property copyright "aifundedagent"
#property link      "https://github.com/cyrusw17/aifundedagent"
#property version   "1.30"
#property description "S6 Equal H/L sweep fade — Strategy Tester + live"

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
input double InpInitialBalance     = 0.0;     // 0 = use account/tester deposit
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

input group "=== Sessions (UTC — matches Python research) ==="
input int    InpKZ1Start           = 7;       // Killzone 1 start hour UTC
input int    InpKZ1End             = 11;      // Killzone 1 end hour UTC (exclusive)
input int    InpKZ2Start           = 12;
input int    InpKZ2End             = 17;
input int    InpFlattenHourUTC     = 20;      // Flatten open positions from this UTC hour
input bool   InpUseGMT             = true;    // true=UTC via GMT offset; false=server+offset
input int    InpServerToUtcOffset  = 0;       // If UseGMT=false: UTC = server + this (hours)
input bool   InpTesterServerIsUTC  = true;    // In Strategy Tester: treat server time as UTC

input group "=== Misc ==="
input bool   InpTradeLong          = true;
input bool   InpTradeShort         = true;
input bool   InpMoveToBE           = true;    // Move SL to BE after +1R
input double InpBEOffsetPoints     = 5;       // BE offset in points (cover commission)
input bool   InpLogSignals         = true;    // Verbose prints (auto-off in optimization)

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
bool     g_usedEqHighDay  = false;
bool     g_usedEqLowDay   = false;
bool     g_isTester       = false;
bool     g_isOptimize     = false;
bool     g_doLog          = true;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_FOK;

#define M15_BARS  400
#define H1_BARS   200

//------------------------------ utils ---------------------------------
bool IsTesterEnv()
{
   return (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
}

datetime NowUtc()
{
   // Strategy Tester: TimeGMT() is unreliable vs historical bars.
   // Default: treat TimeCurrent() (tester server clock) as UTC.
   if(g_isTester && InpTesterServerIsUTC)
      return TimeCurrent();

   if(InpUseGMT)
   {
      if(g_isTester)
         return TimeCurrent() + (TimeGMT() - TimeTradeServer());
      return TimeGMT();
   }
   return TimeCurrent() + InpServerToUtcOffset * 3600;
}

datetime BarTimeToUtc(datetime barServerTime)
{
   if(g_isTester && InpTesterServerIsUTC)
      return barServerTime;

   if(InpUseGMT)
   {
      // Convert broker bar open time → UTC using live offset
      datetime serverNow = TimeTradeServer();
      if(serverNow <= 0)
         serverNow = TimeCurrent();
      return barServerTime + (TimeGMT() - serverNow);
   }
   return barServerTime + InpServerToUtcOffset * 3600;
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

void LogMsg(const string msg)
{
   if(g_doLog)
      Print(msg);
}

ENUM_ORDER_TYPE_FILLING ResolveFilling()
{
   // Strategy Tester + many brokers: FOK/IOC/RETURN vary. Pick first allowed.
   long modes = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((modes & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

void ConfigureTrade()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFilling(g_filling);
   g_trade.SetAsyncMode(false);
}

bool IsNewM15Bar()
{
   datetime t[];
   ArraySetAsSeries(t, true);
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

void CloseOurPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      if(g_pos.Magic() != InpMagic) continue;
      g_trade.PositionClose(g_pos.Ticket());
   }
}

// Tester-safe expiry: GTC orders + cancel when older than N M15 bars
void CancelExpiredPendings()
{
   datetime m15[];
   ArraySetAsSeries(m15, true);
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, m15) != 1)
      return;
   datetime cutoff = m15[0] - (datetime)InpLimitExpiryBars * PeriodSeconds(PERIOD_M15);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!g_order.SelectByIndex(i)) continue;
      if(g_order.Symbol() != _Symbol) continue;
      if(g_order.Magic() != InpMagic) continue;
      datetime setup = (datetime)g_order.TimeSetup();
      if(setup > 0 && setup < cutoff)
      {
         g_trade.OrderDelete(g_order.Ticket());
         LogMsg("S6: expired pending cancelled");
      }
   }
}

double NormalizeVolume(double lots)
{
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int    digits = 2;
   if(vstep <= 0) vstep = 0.01;
   // Digits from step (0.01 → 2, 0.001 → 3)
   double s = vstep;
   digits = 0;
   while(digits < 8 && MathAbs(s - MathRound(s)) > 1e-12)
   {
      s *= 10.0;
      digits++;
   }
   lots = MathFloor(lots / vstep + 1e-12) * vstep;
   if(lots < vmin - 1e-12) lots = 0;
   if(lots > vmax) lots = vmax;
   return NormalizeDouble(lots, digits);
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

// Chronological rates: index 0 = oldest
bool CopyRatesChrono(ENUM_TIMEFRAMES tf, int count, MqlRates &out[])
{
   MqlRates tmp[];
   ArraySetAsSeries(tmp, true);
   int n = CopyRates(_Symbol, tf, 0, count, tmp);
   if(n <= 0) return false;
   ArrayResize(out, n);
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
   MqlRates h1[];
   if(!CopyRatesChrono(PERIOD_H1, H1_BARS, h1))
      return 0;
   int n = ArraySize(h1);
   if(n < 30) return 0;

   int lastClosed = -1;
   for(int i = 0; i < n; i++)
   {
      datetime end = h1[i].time + PeriodSeconds(PERIOD_H1);
      if(end <= m15BarTime)
         lastClosed = i;
      else
         break;
   }
   int use = lastClosed - 1; // shift(1)
   if(use < 20) return 0;

   Swing sh[], sl[];
   CollectSwings(h1, InpH1SwingLeft, InpH1SwingRight, true,  sh, 80);
   CollectSwings(h1, InpH1SwingLeft, InpH1SwingRight, false, sl, 80);

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
   // CRITICAL: never nudge entry away from the equal level.
   // v1.20 nudged limits toward/away from market when stops-level blocked
   // the exact price — that destroyed the fade-at-equals edge and caused
   // large Strategy Tester losses vs the Python research book.
   double lots = LotsForRisk(entry, sl);
   if(lots <= 0)
   {
      LogMsg("S6: lot size 0 — check stops / symbol tick value");
      return false;
   }

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl, _Digits);
   tp    = NormalizeDouble(tp, _Digits);

   long stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) point = _Point;
   double minDist = MathMax((double)stopsLvl, (double)freeze) * point;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Exact equal-level must be a valid limit vs market + stops level
   if(side > 0)
   {
      // BuyLimit: entry must be below Ask by at least stops level
      if(entry >= ask - minDist)
      {
         LogMsg(StringFormat("S6: skip buy limit — equal %.5f too close to Ask %.5f (minDist=%.5f)",
                             entry, ask, minDist));
         return false;
      }
      if(sl >= entry || tp <= entry)
         return false;
      if(minDist > 0 && MathAbs(entry - sl) < minDist)
         sl = NormalizeDouble(entry - minDist, _Digits);
      if(minDist > 0 && MathAbs(tp - entry) < minDist)
         tp = NormalizeDouble(entry + minDist, _Digits);
      if(sl >= entry || tp <= entry)
         return false;
   }
   else
   {
      // SellLimit: entry must be above Bid by at least stops level
      if(entry <= bid + minDist)
      {
         LogMsg(StringFormat("S6: skip sell limit — equal %.5f too close to Bid %.5f (minDist=%.5f)",
                             entry, bid, minDist));
         return false;
      }
      if(sl <= entry || tp >= entry)
         return false;
      if(minDist > 0 && MathAbs(entry - sl) < minDist)
         sl = NormalizeDouble(entry + minDist, _Digits);
      if(minDist > 0 && MathAbs(entry - tp) < minDist)
         tp = NormalizeDouble(entry - minDist, _Digits);
      if(sl <= entry || tp >= entry)
         return false;
   }

   // Recalc lots after any SL pad so risk stays ~InpRiskPercent
   lots = LotsForRisk(entry, sl);
   if(lots <= 0)
      return false;

   ConfigureTrade();

   bool ok = false;
   if(side > 0)
      ok = g_trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
   else
      ok = g_trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);

   if(!ok)
   {
      ENUM_ORDER_TYPE_FILLING alt = (g_filling == ORDER_FILLING_FOK ? ORDER_FILLING_IOC : ORDER_FILLING_FOK);
      g_trade.SetTypeFilling(alt);
      if(side > 0)
         ok = g_trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
      else
         ok = g_trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
      if(ok)
         g_filling = alt;
      else
         Print("S6: order failed ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
   }
   else if(g_doLog)
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
         LogMsg(StringFormat("S6: flatten UTC hour %d", dt.hour));
         continue;
      }

      if(!InpMoveToBE || tp == 0 || sl == 0)
         continue;

      // Initial risk from open→TP (1.5R) ⇒ 1R = |tp-open|/RR
      double oneR = MathAbs(tp - open) / MathMax(InpRewardRisk, 0.1);
      if(oneR <= 0) continue;
      double beOff = InpBEOffsetPoints * _Point;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         // Already at/above BE?
         if(sl >= open) continue;
         if(bid >= open + oneR)
         {
            double newSL = NormalizeDouble(open + beOff, _Digits);
            if(sl < newSL)
               g_trade.PositionModify(ticket, newSL, tp);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(sl <= open && sl != 0) continue;
         if(ask <= open - oneR)
         {
            double newSL = NormalizeDouble(open - beOff, _Digits);
            if(sl == 0 || sl > newSL)
               g_trade.PositionModify(ticket, newSL, tp);
         }
      }
   }
}

//----------------------- signal on closed M15 -------------------------
void EvaluateClosedBar()
{
   MqlRates m15[];
   if(!CopyRatesChrono(PERIOD_M15, M15_BARS, m15))
      return;
   int n = ArraySize(m15);
   if(n < InpAtrPeriod + 80)
      return;

   // Drop forming bar so i = n-1 is last closed
   datetime curOpen[];
   ArraySetAsSeries(curOpen, true);
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

   int i = n - 1;
   datetime barTime = m15[i].time;
   datetime barUtc  = BarTimeToUtc(barTime);

   if(!InKillzoneUtc(barUtc))
      return;

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

   int bias = H1BiasAt(barTime + PeriodSeconds(PERIOD_M15));
   // Python: long if bias >= 0, short if bias <= 0 (neutral allowed)
   bool allowShort = InpRequireH1Bias ? (bias <= 0) : true;
   bool allowLong  = InpRequireH1Bias ? (bias >= 0) : true;

   Swing sh[], sl[];
   CollectSwings(m15, InpSwingLeft, InpSwingRight, true,  sh, 120);
   CollectSwings(m15, InpSwingLeft, InpSwingRight, false, sl, 120);

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

   if(InpTradeShort && haveEqH && !g_usedEqHighDay && allowShort)
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
               return;
            }
         }
      }
   }

   if(InpTradeLong && haveEqL && !g_usedEqLowDay && allowLong)
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
   g_isTester   = IsTesterEnv();
   g_isOptimize = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_doLog      = InpLogSignals && !g_isOptimize;

   g_initialBalance = (InpInitialBalance > 0.0 ? InpInitialBalance : AccountInfoDouble(ACCOUNT_BALANCE));
   if(g_initialBalance <= 0)
      g_initialBalance = 100000.0; // safe default for prop-style tests

   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStamp       = DayStampUtc(NowUtc());
   g_lastM15Bar     = 0;
   g_tradesToday    = 0;
   g_dayRealized    = 0.0;
   g_dayPaused      = false;
   g_hardStopped    = false;
   g_usedEqHighDay  = false;
   g_usedEqLowDay   = false;

   g_filling = ResolveFilling();
   ConfigureTrade();

   // Ensure symbol selected (needed for multi-TF CopyRates in some builds)
   SymbolSelect(_Symbol, true);

   // Warmup check — in tester history is usually present; warn if thin
   MqlRates warm[];
   ArraySetAsSeries(warm, true);
   int got = CopyRates(_Symbol, PERIOD_M15, 0, 50, warm);
   if(got < 50 && !g_isTester)
   {
      Print("S6: waiting for M15 history (", got, " bars)");
      // still allow init; OnTick will no-op until enough bars
   }

   PrintFormat("S6 EqLiquidityFade v1.30 | bal=%.2f | %s | magic=%d | tester=%s | fill=%d | UTC-mode=%s",
               g_initialBalance, _Symbol, InpMagic,
               g_isTester ? "YES" : "no",
               (int)g_filling,
               (g_isTester && InpTesterServerIsUTC) ? "tester-as-UTC" : (InpUseGMT ? "GMT" : "offset"));

   if(g_isTester)
   {
      Print("S6 Tester tips: Period=M15 | Model=Every tick | Deposit=100000 | Leverage=1:100");
      Print("S6: InpTesterServerIsUTC=true assumes history timestamps are UTC.");
      Print("S6: v1.30 skips trades if equal-level limit is invalid (no entry nudging).");
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   ResetDayIfNeeded();

   // Always manage / expire first (flatten, BE) unless already hard-stopped flat
   if(!g_hardStopped)
   {
      ManageOpenPositions();
      CancelExpiredPendings();
   }

   if(g_hardStopped)
      return;

   if(HardFloorBreached())
   {
      g_hardStopped = true;
      CancelOurPendings();
      CloseOurPositions();
      PrintFormat("S6: HARD STOP — equity %.2f <= floor %.2f. Closed all.",
                  Equity(), g_initialBalance * (1.0 - InpMaxLossPct / 100.0));
      return;
   }

   if(DailyLossBreached())
   {
      if(!g_dayPaused)
      {
         g_dayPaused = true;
         CancelOurPendings();
         Print("S6: daily loss pause active (new entries blocked)");
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
      return;

   if(!IsNewM15Bar())
      return;

   EvaluateClosedBar();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.deal == 0)
      return;

   // Tester-safe: select history window then deal
   HistorySelect(TimeCurrent() - 86400 * 7, TimeCurrent() + 60);
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
      g_tradesToday++;
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
      g_dayRealized += HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                     + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                     + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
}

// Custom optimization score: net profit with soft drawdown penalty
double OnTester()
{
   double profit = TesterStatistics(STAT_PROFIT);
   double dd     = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < 1)
      return 0;
   // Prefer profit; penalize relative DD above 6% (prop max-loss zone)
   double penalty = (dd > 6.0 ? (dd - 6.0) * 500.0 : 0.0);
   return profit - penalty;
}
//+------------------------------------------------------------------+
