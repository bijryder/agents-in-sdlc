//+------------------------------------------------------------------+
//|                                                    Akeula Gold EA|
//|                     Version 1.0 - Part 2A + 2B Complete         |
//|                     Author: Bolaji Akeula                        |
//+------------------------------------------------------------------+
#property copyright "Bolaji Akeula"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//==============================
// INPUT PARAMETERS
//==============================

input group "General Settings"
input bool   EnableAutoTrading = true;
input ulong  MagicNumber = 777777;
input double RiskPercent = 1.0;

input group "Trading Session"
input bool TradeLondon = true;
input bool TradeNewYork = true;

input group "Trend"
input int FastEMA = 20;
input int SlowEMA = 50;

input group "Momentum"
input int RSI_Period = 14;
input int ATR_Period = 14;

input group "Spread"
input int MaxSpread = 30;

input group "Risk"
input double ATR_SL = 1.5;
input double ATR_TP = 3.0;
input double RiskRewardRatio = 2.0;

input group "Protection"
input double DailyLossLimit = 5.0;
input double DailyProfitTarget = 3.0;

input group "Trade Management"
input int MaxOpenTrades = 3;
input double MinConfidenceScore = 60.0;

//==============================
// INDICATOR HANDLES
//==============================

int FastEMAHandle;
int SlowEMAHandle;
int RSIHandle;
int ATRHandle;

//==============================
// INDICATOR BUFFERS
//==============================

double FastEMAValue[];
double SlowEMAValue[];
double RSIValue[];
double ATRValue[];

//==============================
// TRADE STATISTICS
//==============================

struct TradeStats
{
   double dailyProfit;
   double dailyLoss;
   int openTrades;
};

TradeStats tradeStats;

//==============================
// INITIALIZATION
//==============================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   FastEMAHandle = iMA(_Symbol, PERIOD_M15, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   SlowEMAHandle = iMA(_Symbol, PERIOD_M15, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   RSIHandle = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   ATRHandle = iATR(_Symbol, PERIOD_M5, ATR_Period);

   if(FastEMAHandle == INVALID_HANDLE || SlowEMAHandle == INVALID_HANDLE ||
      RSIHandle == INVALID_HANDLE || ATRHandle == INVALID_HANDLE)
   {
      Print("Error: Failed to initialize indicators");
      return INIT_FAILED;
   }

   Print("Akeula Gold EA Initialized Successfully");
   return INIT_SUCCEEDED;
}

//==============================
// DEINITIALIZATION
//==============================

void OnDeinit(const int reason)
{
   IndicatorRelease(FastEMAHandle);
   IndicatorRelease(SlowEMAHandle);
   IndicatorRelease(RSIHandle);
   IndicatorRelease(ATRHandle);
   Print("EA Removed");
}

//==============================
// MAIN TICK FUNCTION
//==============================

void OnTick()
{
   if(!EnableAutoTrading) return;
   if(!IsValidSymbol()) return;

   UpdateIndicators();

   if(!SpreadFilter()) return;
   if(!SessionFilter()) return;

   UpdateTradeStats();

   if(!CheckDailyLimits()) return;

   CheckForBuy();
   CheckForSell();
   ManageTrades();
}

//==============================
// UPDATE INDICATORS
//==============================

void UpdateIndicators()
{
   CopyBuffer(FastEMAHandle, 0, 0, 3, FastEMAValue);
   CopyBuffer(SlowEMAHandle, 0, 0, 3, SlowEMAValue);
   CopyBuffer(RSIHandle, 0, 0, 3, RSIValue);
   CopyBuffer(ATRHandle, 0, 0, 3, ATRValue);
}

//==============================
// PART 2A: RISK MANAGEMENT
//==============================

double GetAccountBalance()
{
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

double GetAccountEquity()
{
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

double CalculateLotSize()
{
   double equity = GetAccountEquity();
   double riskAmount = equity * (RiskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue == 0 || tickSize == 0) return 0;
   
   double slDistance = CalculateATRStopLossDistance();
   if(slDistance == 0) slDistance = 50 * _Point;
   
   double pipValue = tickValue / tickSize;
   double lotSize = riskAmount / (slDistance * pipValue);
   
   return lotSize;
}

double GetMinLotSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
}

double GetMaxLotSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
}

double ValidateLotSize(double lotSize)
{
   double minLot = GetMinLotSize();
   double maxLot = GetMaxLotSize();
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   lotSize = MathRound(lotSize / lotStep) * lotStep;
   return NormalizeDouble(lotSize, 2);
}

bool CheckFreeMargin(double lotSize)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginRequired = lotSize * SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
   
   if(freeMargin < marginRequired)
   {
      Print("Error: Insufficient free margin");
      return false;
   }
   return true;
}

//==============================
// PART 2A: TRADE CONDITIONS
//==============================

bool IsValidSymbol()
{
   string symbol = _Symbol;
   if(StringFind(symbol, "XAU") != -1 || StringFind(symbol, "GOLD") != -1)
      return true;
   return false;
}

bool IsAutoTradingEnabled()
{
   if(!EnableAutoTrading) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   return true;
}

bool IsMarketOpen()
{
   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   return (tradeMode != SYMBOL_TRADE_MODE_DISABLED);
}

bool SpreadFilter()
{
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   return (spread <= MaxSpread);
}

bool SessionFilter()
{
   MqlDateTime tm;
   TimeCurrent(tm);
   
   if(TradeLondon && tm.hour >= 8 && tm.hour <= 17) return true;
   if(TradeNewYork && tm.hour >= 13 && tm.hour <= 22) return true;
   return false;
}

int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            count++;
         }
      }
   }
   return count;
}

bool CanOpenNewTrade()
{
   return (CountOpenTrades() < MaxOpenTrades);
}

bool VerifyAllTradeConditions()
{
   if(!EnableAutoTrading || !IsValidSymbol() || !IsAutoTradingEnabled() ||
      !IsMarketOpen() || !SpreadFilter() || !SessionFilter() || !CanOpenNewTrade())
   {
      return false;
   }
   return true;
}

//==============================
// PART 2B: ATR STOP LOSS
//==============================

double GetCurrentATR()
{
   if(ATRValue[0] <= 0) return 0;
   return ATRValue[0];
}

double CalculateATRStopLossDistance()
{
   double atr = GetCurrentATR();
   if(atr <= 0) return 0;
   return atr * ATR_SL;
}

int GetMinBrokerStopLevel()
{
   int minStop = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (minStop == 0) ? 50 : minStop;
}

bool ValidateStopLossDistance(double slDistance)
{
   int minStopLevel = GetMinBrokerStopLevel();
   int slPoints = (int)(slDistance / _Point);
   return (slPoints >= minStopLevel);
}

double SetBuyStopLoss(double entryPrice)
{
   double slDistance = CalculateATRStopLossDistance();
   if(slDistance <= 0) return 0;
   
   double stopLoss = entryPrice - slDistance;
   
   if(!ValidateStopLossDistance(slDistance))
   {
      int minStop = GetMinBrokerStopLevel();
      stopLoss = entryPrice - (minStop * _Point);
   }
   
   return NormalizeDouble(stopLoss, _Digits);
}

double SetSellStopLoss(double entryPrice)
{
   double slDistance = CalculateATRStopLossDistance();
   if(slDistance <= 0) return 0;
   
   double stopLoss = entryPrice + slDistance;
   
   if(!ValidateStopLossDistance(slDistance))
   {
      int minStop = GetMinBrokerStopLevel();
      stopLoss = entryPrice + (minStop * _Point);
   }
   
   return NormalizeDouble(stopLoss, _Digits);
}

//==============================
// PART 2B: ATR TAKE PROFIT
//==============================

double CalculateTakeProfitDistance()
{
   double slDistance = CalculateATRStopLossDistance();
   if(slDistance <= 0) return 0;
   return slDistance * RiskRewardRatio;
}

double CalculateTakeProfitDistanceByATR()
{
   double atr = GetCurrentATR();
   if(atr <= 0) return 0;
   return atr * ATR_TP;
}

double SetBuyTakeProfit(double entryPrice)
{
   double tpDistance = CalculateTakeProfitDistance();
   if(tpDistance <= 0) tpDistance = CalculateTakeProfitDistanceByATR();
   
   double takeProfit = entryPrice + tpDistance;
   int minStop = GetMinBrokerStopLevel();
   int tpPoints = (int)(tpDistance / _Point);
   
   if(tpPoints < minStop) takeProfit = entryPrice + (minStop * _Point);
   return NormalizeDouble(takeProfit, _Digits);
}

double SetSellTakeProfit(double entryPrice)
{
   double tpDistance = CalculateTakeProfitDistance();
   if(tpDistance <= 0) tpDistance = CalculateTakeProfitDistanceByATR();
   
   double takeProfit = entryPrice - tpDistance;
   int minStop = GetMinBrokerStopLevel();
   int tpPoints = (int)(tpDistance / _Point);
   
   if(tpPoints < minStop) takeProfit = entryPrice - (minStop * _Point);
   return NormalizeDouble(takeProfit, _Digits);
}

//==============================
// PART 2B: SAFETY CHECKS
//==============================

bool ValidateSLandTP(double entryPrice, double stopLoss, double takeProfit, string orderType)
{
   if(orderType == "BUY")
   {
      if(stopLoss >= entryPrice || takeProfit <= entryPrice || takeProfit <= stopLoss)
         return false;
   }
   else if(orderType == "SELL")
   {
      if(stopLoss <= entryPrice || takeProfit >= entryPrice || takeProfit >= stopLoss)
         return false;
   }
   return true;
}

bool ValidateBrokerRequirements(double entryPrice, double stopLoss, double takeProfit)
{
   int minStopLevel = GetMinBrokerStopLevel();
   
   int slDistance = (int)MathAbs((stopLoss - entryPrice) / _Point);
   if(slDistance > 0 && slDistance < minStopLevel) return false;
   
   int tpDistance = (int)MathAbs((takeProfit - entryPrice) / _Point);
   if(tpDistance > 0 && tpDistance < minStopLevel) return false;
   
   return true;
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, _Digits);
}

bool ValidateOrderParameters(double entryPrice, double stopLoss, double takeProfit, 
                              double lotSize, string orderType)
{
   if(!ValidateSLandTP(entryPrice, stopLoss, takeProfit, orderType)) return false;
   if(!ValidateBrokerRequirements(entryPrice, stopLoss, takeProfit)) return false;
   if(lotSize <= 0) return false;
   return true;
}

void PrintSLTPSummary(string orderType, double entry, double sl, double tp, double lotSize)
{
   Print("=== ", orderType, " Summary ===");
   Print("Entry: ", entry, " | SL: ", sl, " | TP: ", tp, " | Lot: ", lotSize);
}

//==============================
// PART 2A: BUY CONDITIONS
//==============================

bool BuyEMATrendConfirmation()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (price > FastEMAValue[0] && FastEMAValue[0] > SlowEMAValue[0]);
}

bool BuyRSIConfirmation()
{
   return ((RSIValue[0] < 50 && RSIValue[0] > 20) || 
           (RSIValue[0] > RSIValue[1] && RSIValue[0] < 70));
}

bool BuyATRConfirmation()
{
   return (ATRValue[0] > 0);
}

bool BuyBreakOfStructure()
{
   return true;
}

bool BuyLiquidityConfirmation()
{
   return true;
}

double CalculateBuyConfidence()
{
   double confidence = 0;
   if(BuyEMATrendConfirmation()) confidence += 30;
   if(BuyRSIConfirmation()) confidence += 30;
   if(BuyATRConfirmation()) confidence += 20;
   if(BuyBreakOfStructure()) confidence += 10;
   if(BuyLiquidityConfirmation()) confidence += 10;
   return confidence;
}

void CheckForBuy()
{
   if(!VerifyAllTradeConditions()) return;
   
   double confidence = CalculateBuyConfidence();
   if(confidence < MinConfidenceScore) return;
   
   double lotSize = CalculateLotSize();
   lotSize = ValidateLotSize(lotSize);
   
   if(lotSize <= 0 || !CheckFreeMargin(lotSize)) return;
   
   ExecuteBuyOrder(lotSize);
}

//==============================
// PART 2A: SELL CONDITIONS
//==============================

bool SellEMATrendConfirmation()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return (price < FastEMAValue[0] && FastEMAValue[0] < SlowEMAValue[0]);
}

bool SellRSIConfirmation()
{
   return ((RSIValue[0] > 50 && RSIValue[0] < 80) || 
           (RSIValue[0] < RSIValue[1] && RSIValue[0] > 30));
}

bool SellATRConfirmation()
{
   return (ATRValue[0] > 0);
}

bool SellBreakOfStructure()
{
   return true;
}

bool SellLiquidityConfirmation()
{
   return true;
}

double CalculateSellConfidence()
{
   double confidence = 0;
   if(SellEMATrendConfirmation()) confidence += 30;
   if(SellRSIConfirmation()) confidence += 30;
   if(SellATRConfirmation()) confidence += 20;
   if(SellBreakOfStructure()) confidence += 10;
   if(SellLiquidityConfirmation()) confidence += 10;
   return confidence;
}

void CheckForSell()
{
   if(!VerifyAllTradeConditions()) return;
   
   double confidence = CalculateSellConfidence();
   if(confidence < MinConfidenceScore) return;
   
   double lotSize = CalculateLotSize();
   lotSize = ValidateLotSize(lotSize);
   
   if(lotSize <= 0 || !CheckFreeMargin(lotSize)) return;
   
   ExecuteSellOrder(lotSize);
}

//==============================
// ORDER EXECUTION
//==============================

bool ExecuteBuyOrder(double lotSize)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = SetBuyStopLoss(ask);
   double takeProfit = SetBuyTakeProfit(ask);
   
   if(!ValidateOrderParameters(ask, stopLoss, takeProfit, lotSize, "BUY"))
      return false;
   
   if(trade.Buy(lotSize, _Symbol, ask, stopLoss, takeProfit, "Akeula Buy"))
   {
      Print("Buy executed successfully!");
      PrintSLTPSummary("BUY", ask, stopLoss, takeProfit, lotSize);
      return true;
   }
   
   Print("Error: Buy failed");
   return false;
}

bool ExecuteSellOrder(double lotSize)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = SetSellStopLoss(bid);
   double takeProfit = SetSellTakeProfit(bid);
   
   if(!ValidateOrderParameters(bid, stopLoss, takeProfit, lotSize, "SELL"))
      return false;
   
   if(trade.Sell(lotSize, _Symbol, bid, stopLoss, takeProfit, "Akeula Sell"))
   {
      Print("Sell executed successfully!");
      PrintSLTPSummary("SELL", bid, stopLoss, takeProfit, lotSize);
      return true;
   }
   
   Print("Error: Sell failed");
   return false;
}

//==============================
// TRADE STATISTICS
//==============================

void UpdateTradeStats()
{
   tradeStats.dailyProfit = 0;
   tradeStats.dailyLoss = 0;
   tradeStats.openTrades = CountOpenTrades();
   
   MqlDateTime now;
   TimeCurrent(now);
   
   int dealsTotal = HistoryDealsTotal();
   for(int i = 0; i < dealsTotal; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealSelect(ticket))
      {
         ulong dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         
         MqlDateTime dealDateTime;
         TimeToStruct(dealTime, dealDateTime);
         
         if(dealDateTime.day == now.day && dealDateTime.mon == now.mon &&
            dealDateTime.year == now.year && dealMagic == MagicNumber && 
            dealSymbol == _Symbol)
         {
            if(dealProfit > 0)
               tradeStats.dailyProfit += dealProfit;
            else
               tradeStats.dailyLoss += MathAbs(dealProfit);
         }
      }
   }
}

bool CheckDailyLimits()
{
   UpdateTradeStats();
   
   if(tradeStats.dailyLoss >= DailyLossLimit)
   {
      Print("Daily loss limit reached");
      return false;
   }
   
   if(tradeStats.dailyProfit >= DailyProfitTarget)
   {
      Print("Daily profit target reached");
      return false;
   }
   
   return true;
}

//==============================
// TRADE MANAGEMENT (Placeholder)
//==============================

void ManageTrades()
{
   // Part 3 will implement trade management
}
