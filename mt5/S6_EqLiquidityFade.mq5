//+------------------------------------------------------------------+
//| S6_EqLiquidityFade.mq5                                           |
//| Equal highs/lows sweep fade — Python S6 parity port              |
//|                                                                  |
//| v1.40 — CRITICAL FIX                                             |
//|   Python fills a LIMIT at the equal on a RETEST after the sweep. |
//|   Earlier EA builds marketed/padded when price was still BELOW   |
//|   the equal (short) / ABOVE (long) → hole entries → ~−$7k tests. |
//|                                                                  |
//| Entry rules (match research):                                    |
//|   1) Arm setup on closed M15 sweep-fade signal                   |
//|   2) Place SellLimit/BuyLimit EXACTLY at equal when stops-level  |
//|      allows (price far enough from market)                       |
//|   3) If price revisits equal before pending is on → market fill  |
//|      at the equal (retest). NEVER market while still offside.    |
//|                                                                  |
//| Tester: EURUSD | M15 | Every tick | Deposit 100000 | 1:100       |
//+------------------------------------------------------------------+
#property copyright "aifundedagent"
#property link      "https://github.com/cyrusw17/aifundedagent"
#property version   "1.40"
#property description "S6 equal fade — Python retest-limit parity"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//------------------------------ inputs --------------------------------
input group "=== Risk (The5ers-style) ==="
input double InpRiskPercent        = 0.40;    // Risk % of INITIAL balance (0.40 = 0.4%)
input double InpRewardRisk         = 1.5;
input double InpDailyLossLimitPct  = 3.0;
input double InpMaxLossPct         = 6.0;
input double InpDailyProfitCapPct  = 4.5;
input double InpInitialBalance     = 100000.0;// Use 100000 for prop/tester parity
input int    InpMagic              = 6062026;
input int    InpMaxTradesPerDay    = 3;
input int    InpMaxOpenPositions   = 1;
input int    InpSlippagePoints     = 30;
input double InpMaxLots            = 20.0;    // Sanity cap (forex); raise for gold

input group "=== Strategy ==="
input int    InpSwingLeft          = 3;
input int    InpSwingRight         = 3;
input int    InpAtrPeriod          = 14;
input double InpEqualTolAtr        = 0.15;
input double InpStopBufferAtr      = 0.15;
input double InpMinStopAtr         = 0.80;
input double InpMaxStopAtr         = 2.20;
input int    InpH1SwingLeft        = 2;
input int    InpH1SwingRight       = 2;
input int    InpLimitExpiryBars    = 16;      // ~4h M15
input bool   InpRequireH1Bias      = true;

input group "=== Sessions UTC ==="
input int    InpKZ1Start           = 7;
input int    InpKZ1End             = 11;
input int    InpKZ2Start           = 12;
input int    InpKZ2End             = 17;
input int    InpFlattenHourUTC     = 20;
input bool   InpUseGMT             = true;
input int    InpServerToUtcOffset  = 0;
input bool   InpTesterServerIsUTC  = true;    // Tester: bar/server time = UTC

input group "=== Misc ==="
input bool   InpTradeLong          = true;
input bool   InpTradeShort         = true;
input bool   InpMoveToBE           = true;
input double InpBEOffsetPoints     = 5;
input bool   InpLogSignals         = true;

//------------------------------ state ---------------------------------
CTrade         g_trade;
CPositionInfo  g_pos;
COrderInfo     g_order;

double   g_initialBalance = 0.0;
datetime g_lastM15Bar     = 0;
int      g_dayStamp       = 0;
int      g_tradesToday    = 0;
double   g_dayStartEquity = 0.0;
double   g_dayRealized    = 0.0;
bool     g_dayPaused      = false;
bool     g_hardStopped    = false;
bool     g_usedEqHighDay  = false;
bool     g_usedEqLowDay   = false;
bool     g_isTester       = false;
bool     g_doLog          = true;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_FOK;
int      g_prevH1Bias     = 0;

// Armed setup waiting for retest (Python limit-fill model)
int      g_armSide        = 0;      // 0 flat, +1 buy fade, -1 sell fade
double   g_armEqual       = 0.0;
double   g_armSL          = 0.0;
datetime g_armExpire      = 0;
bool     g_armOrderOn     = false;
string   g_armComment     = "";

int      g_statSignals    = 0;
int      g_statLimits     = 0;
int      g_statRetests    = 0;
int      g_statExpired    = 0;

#define M15_BARS 400
#define H1_BARS  200

//------------------------------ time ----------------------------------
bool IsTesterEnv()
{
   return (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
}

datetime NowUtc()
{
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
      datetime serverNow = TimeTradeServer();
      if(serverNow <= 0) serverNow = TimeCurrent();
      return barServerTime + (TimeGMT() - serverNow);
   }
   return barServerTime + InpServerToUtcOffset * 3600;
}

void UtcParts(datetime t, MqlDateTime &dt) { TimeToStruct(t, dt); }

int DayStampUtc(datetime t)
{
   MqlDateTime dt; UtcParts(t, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

bool InKillzoneUtc(datetime t)
{
   MqlDateTime dt; UtcParts(t, dt);
   int h = dt.hour;
   if(h >= InpKZ1Start && h < InpKZ1End) return true;
   if(h >= InpKZ2Start && h < InpKZ2End) return true;
   return false;
}

void LogMsg(const string msg) { if(g_doLog) Print(msg); }

ENUM_ORDER_TYPE_FILLING ResolveFilling()
{
   long modes = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((modes & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
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
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, t) != 1) return false;
   if(t[0] != g_lastM15Bar) { g_lastM15Bar = t[0]; return true; }
   return false;
}

void ResetDayIfNeeded()
{
   int stamp = DayStampUtc(NowUtc());
   if(stamp == g_dayStamp) return;
   g_dayStamp       = stamp;
   g_tradesToday    = 0;
   g_dayRealized    = 0.0;
   g_dayPaused      = false;
   g_usedEqHighDay  = false;
   g_usedEqLowDay   = false;
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
}

double Equity() { return AccountInfoDouble(ACCOUNT_EQUITY); }

bool HardFloorBreached()
{
   return Equity() <= g_initialBalance * (1.0 - InpMaxLossPct / 100.0);
}

bool DailyLossBreached()
{
   return (g_dayStartEquity - Equity()) >= g_initialBalance * (InpDailyLossLimitPct / 100.0);
}

bool DailyProfitCapped()
{
   return g_dayRealized >= g_initialBalance * (InpDailyProfitCapPct / 100.0);
}

int CountOurPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol || g_pos.Magic() != InpMagic) continue;
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
      if(g_order.Symbol() != _Symbol || g_order.Magic() != InpMagic) continue;
      n++;
   }
   return n;
}

void CancelOurPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!g_order.SelectByIndex(i)) continue;
      if(g_order.Symbol() != _Symbol || g_order.Magic() != InpMagic) continue;
      g_trade.OrderDelete(g_order.Ticket());
   }
}

void CloseOurPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol || g_pos.Magic() != InpMagic) continue;
      g_trade.PositionClose(g_pos.Ticket());
   }
}

void ClearArm(const string why)
{
   if(g_armSide != 0)
      LogMsg("S6: clear arm — " + why);
   g_armSide = 0;
   g_armEqual = 0;
   g_armSL = 0;
   g_armExpire = 0;
   g_armOrderOn = false;
   g_armComment = "";
}

double NormalizeVolume(double lots)
{
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0) vstep = 0.01;
   int digits = 0;
   double s = vstep;
   while(digits < 8 && MathAbs(s - MathRound(s)) > 1e-12) { s *= 10.0; digits++; }
   lots = MathFloor(lots / vstep + 1e-12) * vstep;
   if(lots < vmin - 1e-12) lots = 0;
   if(lots > vmax) lots = vmax;
   if(InpMaxLots > 0 && lots > InpMaxLots) lots = InpMaxLots;
   return NormalizeDouble(lots, digits);
}

double LotsForRisk(double entry, double sl)
{
   double riskMoney = g_initialBalance * (InpRiskPercent / 100.0);
   double slDist = MathAbs(entry - sl);
   if(slDist <= 0 || riskMoney <= 0) return 0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double contract  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(tickSize <= 0) return 0;

   double lossPerLot = 0.0;
   if(tickValue > 0)
      lossPerLot = (slDist / tickSize) * tickValue;
   else if(contract > 0)
      lossPerLot = slDist * contract; // fallback (USD-quoted pairs)

   if(lossPerLot <= 0) return 0;
   double lots = riskMoney / lossPerLot;
   lots = NormalizeVolume(lots);

   // Sanity: intended risk should be near riskMoney
   if(lots > 0 && g_doLog)
   {
      double actualRisk = lots * lossPerLot;
      if(actualRisk > riskMoney * 2.0)
         PrintFormat("S6 WARN: risk $%.0f lots=%.2f (check tick value) entry=%.5f sl=%.5f",
                     actualRisk, lots, entry, sl);
   }
   return lots;
}

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

struct Swing { int idx; double price; };

int CollectSwings(const MqlRates &r[], int left, int right, bool highs, Swing &out[], int maxOut)
{
   // Match Python: pivot must be unique extreme (first occurrence of max/min at offset left)
   int n = ArraySize(r);
   int count = 0;
   ArrayResize(out, 0);
   for(int p = left; p < n - right; p++)
   {
      if(highs)
      {
         int argmax = p - left;
         for(int k = p - left; k <= p + right; k++)
            if(r[k].high > r[argmax].high) argmax = k;
         if(argmax != p) continue;
         ArrayResize(out, count + 1);
         out[count].idx = p; out[count].price = r[p].high; count++;
      }
      else
      {
         int argmin = p - left;
         for(int k = p - left; k <= p + right; k++)
            if(r[k].low < r[argmin].low) argmin = k;
         if(argmin != p) continue;
         ArrayResize(out, count + 1);
         out[count].idx = p; out[count].price = r[p].low; count++;
      }
      if(count >= maxOut) break;
   }
   return count;
}

int H1BiasAt(datetime m15BarTime)
{
   // Python: compute bias on each closed H1, shift(1), ffill to M15; carry mixed.
   MqlRates h1[];
   if(!CopyRatesChrono(PERIOD_H1, H1_BARS, h1)) return g_prevH1Bias;
   int n = ArraySize(h1);
   if(n < 30) return g_prevH1Bias;

   int lastClosed = -1;
   for(int i = 0; i < n; i++)
   {
      if(h1[i].time + PeriodSeconds(PERIOD_H1) <= m15BarTime)
         lastClosed = i;
      else break;
   }
   // shift(1): use prior closed H1 as end of known structure
   int use = lastClosed - 1;
   if(use < 20) return g_prevH1Bias;

   Swing sh[], sl[];
   CollectSwings(h1, InpH1SwingLeft, InpH1SwingRight, true,  sh, 80);
   CollectSwings(h1, InpH1SwingLeft, InpH1SwingRight, false, sl, 80);

   Swing ksh[], ksl[];
   int nsh = 0, nsl = 0;
   for(int i = 0; i < ArraySize(sh); i++)
      if(sh[i].idx + InpH1SwingRight <= use)
      { ArrayResize(ksh, nsh + 1); ksh[nsh++] = sh[i]; }
   for(int i = 0; i < ArraySize(sl); i++)
      if(sl[i].idx + InpH1SwingRight <= use)
      { ArrayResize(ksl, nsl + 1); ksl[nsl++] = sl[i]; }

   if(nsh < 2 || nsl < 2) return g_prevH1Bias;

   bool hh = ksh[nsh - 1].price > ksh[nsh - 2].price;
   bool hl = ksl[nsl - 1].price > ksl[nsl - 2].price;
   bool lh = ksh[nsh - 1].price < ksh[nsh - 2].price;
   bool ll = ksl[nsl - 1].price < ksl[nsl - 2].price;
   int b = g_prevH1Bias;
   if(hh && hl) b = 1;
   else if(lh && ll) b = -1;
   // else carry forward (Python mixed keeps prior)
   g_prevH1Bias = b;
   return b;
}

//----------------------- send helpers ---------------------------------
bool SendOrder(int side, double entry, double sl, double tp, string comment, bool asMarket)
{
   double lots = LotsForRisk(asMarket ? entry : entry, sl);
   // Size off equal/SL geometry (entry for market may be ask/bid; use arm equal risk)
   if(!asMarket)
      lots = LotsForRisk(entry, sl);
   else
      lots = LotsForRisk(g_armEqual, g_armSL); // risk from structure
   if(lots <= 0) { LogMsg("S6: lots=0"); return false; }

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl, _Digits);
   tp    = NormalizeDouble(tp, _Digits);

   if(side > 0 && (sl >= entry || tp <= entry)) return false;
   if(side < 0 && (sl <= entry || tp >= entry)) return false;

   ConfigureTrade();
   bool ok = false;
   if(asMarket)
   {
      if(side > 0) ok = g_trade.Buy(lots, _Symbol, 0, sl, tp, comment);
      else         ok = g_trade.Sell(lots, _Symbol, 0, sl, tp, comment);
   }
   else
   {
      if(side > 0) ok = g_trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
      else         ok = g_trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
   }

   if(!ok)
   {
      ENUM_ORDER_TYPE_FILLING alt = (g_filling == ORDER_FILLING_FOK ? ORDER_FILLING_IOC : ORDER_FILLING_FOK);
      g_trade.SetTypeFilling(alt);
      if(asMarket)
      {
         if(side > 0) ok = g_trade.Buy(lots, _Symbol, 0, sl, tp, comment);
         else         ok = g_trade.Sell(lots, _Symbol, 0, sl, tp, comment);
      }
      else
      {
         if(side > 0) ok = g_trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
         else         ok = g_trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
      }
      if(ok) g_filling = alt;
      else Print("S6: order fail ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
   }
   else
      LogMsg(StringFormat("S6: %s %s @%.5f SL=%.5f TP=%.5f lots=%.2f",
                          comment, asMarket ? "RETEST-MKT" : "LIMIT", entry, sl, tp, lots));
   return ok;
}

double TpFrom(int side, double entry, double sl)
{
   double risk = MathAbs(entry - sl);
   if(side > 0) return entry + InpRewardRisk * risk;
   return entry - InpRewardRisk * risk;
}

double BrokerMinDist()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) point = _Point;
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax((double)stops, (double)freeze) * point;
}

//----------------------- retest arm manager ---------------------------
void ManageArm()
{
   if(g_armSide == 0)
      return;

   if(TimeCurrent() >= g_armExpire)
   {
      CancelOurPendings();
      g_statExpired++;
      ClearArm("expired");
      return;
   }

   // Already have our pending
   if(CountOurPendings() > 0)
   {
      g_armOrderOn = true;
      return;
   }
   // Pending gone but we thought it was on → filled or cancelled
   if(g_armOrderOn)
   {
      if(CountOurPositions() > 0)
         ClearArm("filled");
      else
         ClearArm("pending gone");
      return;
   }

   if(CountOurPositions() >= InpMaxOpenPositions)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minDist = BrokerMinDist();
   double equal = g_armEqual;
   double sl = g_armSL;
   int side = g_armSide;

   // Stop hunted before entry → abort
   if(side < 0 && bid >= sl) { ClearArm("price hit SL before entry"); return; }
   if(side > 0 && ask <= sl) { ClearArm("price hit SL before entry"); return; }

   // --- SHORT fade: wait for retest UP to equal ---
   if(side < 0)
   {
      // Retest happening now: price back at/above equal → fill like Python limit
      if(bid >= equal)
      {
         double entry = equal; // geometry at equal (Python)
         double tp = TpFrom(side, entry, sl);
         // Actual market sell at bid; keep SL/TP from equal geometry
         // Adjust if broker requires distance from current price
         if(minDist > 0)
         {
            if(sl < bid + minDist) sl = NormalizeDouble(bid + minDist, _Digits);
            if(tp > bid - minDist) tp = NormalizeDouble(bid - minDist, _Digits);
         }
         if(SendOrder(side, bid, sl, tp, g_armComment, true))
         {
            g_statRetests++;
            if(StringFind(g_armComment, "eqh") >= 0) g_usedEqHighDay = true;
            ClearArm("retest market");
         }
         return;
      }

      // Still below equal: place SellLimit at EXACT equal when far enough
      if(equal >= bid + minDist + _Point)
      {
         double tp = TpFrom(side, equal, sl);
         if(minDist > 0 && MathAbs(equal - sl) < minDist)
            sl = NormalizeDouble(equal + minDist, _Digits);
         tp = TpFrom(side, equal, sl);
         if(SendOrder(side, equal, sl, tp, g_armComment, false))
         {
            g_statLimits++;
            g_armOrderOn = true;
            if(StringFind(g_armComment, "eqh") >= 0) g_usedEqHighDay = true;
         }
      }
      // else: too close — WAIT (do not market below equal)
      return;
   }

   // --- LONG fade: wait for retest DOWN to equal ---
   if(ask <= equal)
   {
      double entry = equal;
      double tp = TpFrom(side, entry, sl);
      if(minDist > 0)
      {
         if(sl > ask - minDist) sl = NormalizeDouble(ask - minDist, _Digits);
         if(tp < ask + minDist) tp = NormalizeDouble(ask + minDist, _Digits);
      }
      if(SendOrder(side, ask, sl, tp, g_armComment, true))
      {
         g_statRetests++;
         if(StringFind(g_armComment, "eql") >= 0) g_usedEqLowDay = true;
         ClearArm("retest market");
      }
      return;
   }

   if(equal <= ask - minDist - _Point)
   {
      double tp = TpFrom(side, equal, sl);
      if(minDist > 0 && MathAbs(equal - sl) < minDist)
         sl = NormalizeDouble(equal - minDist, _Digits);
      tp = TpFrom(side, equal, sl);
      if(SendOrder(side, equal, sl, tp, g_armComment, false))
      {
         g_statLimits++;
         g_armOrderOn = true;
         if(StringFind(g_armComment, "eql") >= 0) g_usedEqLowDay = true;
      }
   }
}

void ArmSetup(int side, double equal, double sl, string comment)
{
   if(g_armSide != 0) return; // one arm at a time
   g_armSide    = side;
   g_armEqual   = NormalizeDouble(equal, _Digits);
   g_armSL      = NormalizeDouble(sl, _Digits);
   g_armExpire  = TimeCurrent() + InpLimitExpiryBars * PeriodSeconds(PERIOD_M15);
   g_armOrderOn = false;
   g_armComment = comment;
   g_statSignals++;
   LogMsg(StringFormat("S6: ARM %s equal=%.5f SL=%.5f (wait retest)",
                       comment, g_armEqual, g_armSL));
}

//----------------------- manage open ----------------------------------
void ManageOpenPositions()
{
   datetime now = NowUtc();
   MqlDateTime dt; UtcParts(now, dt);
   bool flatten = (dt.hour >= InpFlattenHourUTC);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol || g_pos.Magic() != InpMagic) continue;

      ulong ticket = g_pos.Ticket();
      double open = g_pos.PriceOpen();
      double sl = g_pos.StopLoss();
      double tp = g_pos.TakeProfit();
      long type = g_pos.PositionType();

      if(flatten)
      {
         g_trade.PositionClose(ticket);
         LogMsg(StringFormat("S6: flatten hour %d", dt.hour));
         continue;
      }

      if(!InpMoveToBE || tp == 0 || sl == 0) continue;

      double oneR = MathAbs(tp - open) / MathMax(InpRewardRisk, 0.1);
      double beOff = InpBEOffsetPoints * _Point;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         if(sl >= open) continue;
         if(bid >= open + oneR)
         {
            double newSL = NormalizeDouble(open + beOff, _Digits);
            if(sl < newSL) g_trade.PositionModify(ticket, newSL, tp);
         }
      }
      else
      {
         if(sl <= open && sl != 0) continue;
         if(ask <= open - oneR)
         {
            double newSL = NormalizeDouble(open - beOff, _Digits);
            if(sl == 0 || sl > newSL) g_trade.PositionModify(ticket, newSL, tp);
         }
      }
   }
}

//----------------------- signals on closed M15 ------------------------
void EvaluateClosedBar()
{
   if(g_armSide != 0) return; // finish current arm first
   if(CountOurPendings() > 0 || CountOurPositions() >= InpMaxOpenPositions) return;
   if(g_tradesToday >= InpMaxTradesPerDay) return;

   MqlRates m15[];
   if(!CopyRatesChrono(PERIOD_M15, M15_BARS, m15)) return;
   int n = ArraySize(m15);
   if(n < InpAtrPeriod + 80) return;

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
   if(n < InpAtrPeriod + 80) return;

   int i = n - 1;
   datetime barUtc = BarTimeToUtc(m15[i].time);
   if(!InKillzoneUtc(barUtc)) return;

   double atr = 0;
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

   int bias = H1BiasAt(m15[i].time + PeriodSeconds(PERIOD_M15));
   bool allowShort = InpRequireH1Bias ? (bias <= 0) : true;
   bool allowLong  = InpRequireH1Bias ? (bias >= 0) : true;

   Swing sh[], sl[];
   CollectSwings(m15, InpSwingLeft, InpSwingRight, true,  sh, 120);
   CollectSwings(m15, InpSwingLeft, InpSwingRight, false, sl, 120);

   // Python: known swings with confirm<=i and pivot<i; last 6; last matching pair wins
   Swing highs[], lows[];
   int nh = 0, nl = 0;
   for(int s = 0; s < ArraySize(sh); s++)
   {
      if(sh[s].idx + InpSwingRight <= i && sh[s].idx < i)
      { ArrayResize(highs, nh + 1); highs[nh++] = sh[s]; }
   }
   for(int s = 0; s < ArraySize(sl); s++)
   {
      if(sl[s].idx + InpSwingRight <= i && sl[s].idx < i)
      { ArrayResize(lows, nl + 1); lows[nl++] = sl[s]; }
   }

   int hStart = MathMax(0, nh - 6);
   int lStart = MathMax(0, nl - 6);
   double tol = InpEqualTolAtr * atr;

   double eqHigh = 0; bool haveEqH = false;
   for(int a = hStart; a < nh; a++)
      for(int b = a + 1; b < nh; b++)
         if(MathAbs(highs[a].price - highs[b].price) <= tol)
         {
            // Python: last assignment wins (not max-of-all)
            eqHigh = MathMax(highs[a].price, highs[b].price);
            haveEqH = true;
         }

   double eqLow = 0; bool haveEqL = false;
   for(int a = lStart; a < nl; a++)
      for(int b = a + 1; b < nl; b++)
         if(MathAbs(lows[a].price - lows[b].price) <= tol)
         {
            eqLow = MathMin(lows[a].price, lows[b].price);
            haveEqL = true;
         }

   double o = m15[i].open, h = m15[i].high, l = m15[i].low, c = m15[i].close;

   if(InpTradeShort && haveEqH && !g_usedEqHighDay && allowShort)
   {
      if(h > eqHigh && c < eqHigh && c < o)
      {
         double entry = eqHigh;
         double stop  = h + InpStopBufferAtr * atr;
         double dist  = MathAbs(entry - stop);
         if(dist < InpMinStopAtr * atr) stop = entry + InpMinStopAtr * atr;
         dist = MathAbs(entry - stop);
         if(dist <= InpMaxStopAtr * atr)
         {
            ArmSetup(-1, entry, stop, "S6_eqh_fade");
            return;
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
         if(dist < InpMinStopAtr * atr) stop = entry - InpMinStopAtr * atr;
         dist = MathAbs(entry - stop);
         if(dist <= InpMaxStopAtr * atr)
            ArmSetup(1, entry, stop, "S6_eql_fade");
      }
   }
}

//----------------------- events ---------------------------------------
int OnInit()
{
   g_isTester = IsTesterEnv();
   g_doLog = InpLogSignals && !(bool)MQLInfoInteger(MQL_OPTIMIZATION);

   g_initialBalance = (InpInitialBalance > 0.0 ? InpInitialBalance : AccountInfoDouble(ACCOUNT_BALANCE));
   if(g_initialBalance <= 0) g_initialBalance = 100000.0;

   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStamp = DayStampUtc(NowUtc());
   g_lastM15Bar = 0;
   g_tradesToday = 0;
   g_dayRealized = 0;
   g_dayPaused = false;
   g_hardStopped = false;
   g_usedEqHighDay = false;
   g_usedEqLowDay = false;
   g_prevH1Bias = 0;
   ClearArm("init");
   g_statSignals = g_statLimits = g_statRetests = g_statExpired = 0;

   g_filling = ResolveFilling();
   ConfigureTrade();
   SymbolSelect(_Symbol, true);

   PrintFormat("S6 v1.40 PYTHON-RETEST | bal=%.2f | %s | tester=%s | UTC=%s",
               g_initialBalance, _Symbol,
               g_isTester ? "YES" : "no",
               (g_isTester && InpTesterServerIsUTC) ? "tester-as-UTC" : "gmt/offset");
   Print("S6: Arms limit at equal; markets ONLY on retest touch. Never hole-entries.");
   Print("S6 Tester: M15 | Every tick | Deposit=100000 | set InpInitialBalance=100000");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFormat("S6 stats: armed=%d limits=%d retestMkt=%d expired=%d tradesTodayGate=%d",
               g_statSignals, g_statLimits, g_statRetests, g_statExpired, g_tradesToday);
}

void OnTick()
{
   ResetDayIfNeeded();

   if(!g_hardStopped)
   {
      ManageOpenPositions();
      ManageArm();
   }

   if(g_hardStopped) return;

   if(HardFloorBreached())
   {
      g_hardStopped = true;
      CancelOurPendings();
      ClearArm("hard floor");
      CloseOurPositions();
      PrintFormat("S6: HARD STOP equity=%.2f", Equity());
      return;
   }

   if(DailyLossBreached())
   {
      if(!g_dayPaused)
      {
         g_dayPaused = true;
         CancelOurPendings();
         ClearArm("daily loss");
         Print("S6: daily loss pause");
      }
      return;
   }

   if(g_dayPaused || DailyProfitCapped()) return;
   if(CountOurPositions() >= InpMaxOpenPositions) return;
   if(g_tradesToday >= InpMaxTradesPerDay) return;
   if(g_armSide != 0 || CountOurPendings() > 0) return;

   if(!IsNewM15Bar()) return;
   EvaluateClosedBar();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   HistorySelect(TimeCurrent() - 86400 * 7, TimeCurrent() + 60);
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN) g_tradesToday++;
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
      g_dayRealized += HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                     + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                     + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
}

double OnTester()
{
   double profit = TesterStatistics(STAT_PROFIT);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < 1) return 0;
   double penalty = (dd > 6.0 ? (dd - 6.0) * 500.0 : 0.0);
   return profit - penalty;
}
//+------------------------------------------------------------------+
