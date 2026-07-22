//+------------------------------------------------------------------+
//| AsiaBreakRetest.mq5                                              |
//| The5ers-oriented ICT session break & retest day EA (skeleton)    |
//| Port of Python strategy in /strategy — wire fills/risk next.     |
//+------------------------------------------------------------------+
#property copyright "aifundedagent"
#property version   "1.00"
#property strict

input double RiskPercent        = 0.40;   // % of initial balance
input double RewardRisk         = 1.5;
input double DailyLossLimitPct  = 3.0;
input double MaxLossPct         = 6.0;
input double DailyProfitCapPct  = 4.5;    // consistency helper vs 10% target
input int    Magic              = 260718;
input int    AsiaStartHourUTC   = 0;
input int    AsiaEndHourUTC     = 7;
input int    LondonEndHourUTC   = 12;
input int    FlattenHourUTC     = 20;

double initialBalance = 0.0;

int OnInit()
{
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   return INIT_SUCCEEDED;
}

bool InKillzone()
{
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   int h = t.hour;
   return (h >= 7 && h < 11) || (h >= 12 && h < 17);
}

// Placeholder: compute Asia/London range on M15, detect break+retest,
// size from RiskPercent, SL beyond retest extreme, TP = RewardRisk * R,
// BE at +1R, flatten at FlattenHourUTC, pause if daily loss hit.
void OnTick()
{
   if(!InKillzone())
      return;

   // TODO: port logic from strategy/signals.py + strategy/backtest.py
   // 1) Build session ranges from iBarShift M15
   // 2) On new M15 close: break detection + retest signal
   // 3) Place limit at edge; manage SL/TP/BE
   // 4) Enforce The5ers daily pause & static floor from initialBalance
}
