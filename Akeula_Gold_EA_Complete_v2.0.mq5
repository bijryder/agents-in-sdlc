//+------------------------------------------------------------------+
//|                                                    Akeula Gold EA|
//|                  Version 2.0 - Complete Professional EA         |
//|                     Author: Bolaji Akeula                        |
//+------------------------------------------------------------------+
#property copyright "Bolaji Akeula"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//==============================
// INPUT PARAMETERS - GENERAL
//==============================

input group "General Settings"
input bool   EnableAutoTrading = true;
input ulong  MagicNumber = 777777;
input double RiskPercent = 1.0;

input group "Trading Session"
input bool TradeLondon = true;
input bool TradeNewYork = true;

input group "Indicators"
input int FastEMA = 20;
input int SlowEMA = 50;
input int RSI_Period = 14;
input int ATR_Period = 14;

input group "Spread & Volatility"
input int MaxSpread = 30;
input double ATR_SL = 1.5;
input double ATR_TP = 3.0;
input double RiskRewardRatio = 2.0;

input group "Account Protection"
input double DailyLossLimit = 5.0;
input double DailyProfitTarget = 3.0;
input double MaxDrawdownPercent = 10.0;
input int MaxConsecutiveLosses = 3;

input group "Trade Management"
input int MaxOpenTrades = 3;
input double MinConfidenceScore = 60.0;
input bool EnableBreakeven = true;
input double BreakEvenProfit = 10.0;
input bool EnableTrailingStop = true;
input double TrailingStopPercent = 1.5;
input bool EnablePartialClose = true;
input double PartialClosePercent = 50.0;

input group "Smart Money Settings"
input bool EnableSMC = true;
input int SwingLookback = 5;
input double FVGThreshold = 0.5;
input bool EnableOrderBlocks = true;

input group "Professional Features"
input bool EnableDashboard = true;
input bool EnableLogging = true;

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
// STRUCTURES
//==============================

struct TradeStats
{
   double dailyProfit;
   double dailyLoss;
   int openTrades;
   int winTrades;
   int lossTrades;
   int consecutiveLosses;
   double maxDrawdown;
   bool pauseTrading;
};

struct SmartMoneyData
{
   double swingHigh;
   double swingLow;
   int swingHighBar;
   int swingLowBar;
   bool bosUp;
   bool bosDown;
   double orderBlockHigh;
   double orderBlockLow;
   double fvgTop;
   double fvgBottom;
};

TradeStats tradeStats;
SmartMoneyData smData;

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

   InitializeTradeStats();
   Print("Akeula Gold EA v2.0 Initialized Successfully");
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
   UpdateTradeStats();

   if(EnableDashboard)
      DrawDashboard();

   if(!SpreadFilter()) return;
   if(!SessionFilter()) return;

   if(!CheckAccountProtection())
   {
      Print("Account protection triggered - Trading paused");
      return;
   }

   ManageOpenTrades();
   
   if(tradeStats.pauseTrading)
   {
      Print("Trading paused due to consecutive losses");
      return;
   }

   CheckForBuy();
   CheckForSell();
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

double ValidateLotSize(double lotSize)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
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
   return (freeMargin >= marginRequired);
}

//==============================
// PART 2A: TRADE CONDITIONS
//==============================

bool IsValidSymbol()
{
   string symbol = _Symbol;
   return (StringFind(symbol, "XAU") != -1 || StringFind(symbol, "GOLD") != -1);
}

bool IsAutoTradingEnabled()
{
   return (EnableAutoTrading && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED));
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
      !SpreadFilter() || !SessionFilter() || !CanOpenNewTrade())
   {
      return false;
   }
   return true;
}

//==============================
// PART 2B: ATR STOP LOSS & TAKE PROFIT
//==============================

double GetCurrentATR()
{
   return (ATRValue[0] > 0) ? ATRValue[0] : 0;
}

double CalculateATRStopLossDistance()
{
   double atr = GetCurrentATR();
   return (atr > 0) ? (atr * ATR_SL) : 0;
}

int GetMinBrokerStopLevel()
{
   int minStop = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (minStop == 0) ? 50 : minStop;
}

double SetBuyStopLoss(double entryPrice)
{
   double slDistance = CalculateATRStopLossDistance();
   if(slDistance <= 0) return 0;
   
   double stopLoss = entryPrice - slDistance;
   
   int minStop = GetMinBrokerStopLevel();
   int slPoints = (int)(slDistance / _Point);
   if(slPoints < minStop) stopLoss = entryPrice - (minStop * _Point);
   
   return NormalizeDouble(stopLoss, _Digits);
}

double SetSellStopLoss(double entryPrice)
{
   double slDistance = CalculateATRStopLossDistance();
   if(slDistance <= 0) return 0;
   
   double stopLoss = entryPrice + slDistance;
   
   int minStop = GetMinBrokerStopLevel();
   int slPoints = (int)(slDistance / _Point);
   if(slPoints < minStop) stopLoss = entryPrice + (minStop * _Point);
   
   return NormalizeDouble(stopLoss, _Digits);
}

double CalculateTakeProfitDistance()
{
   double slDistance = CalculateATRStopLossDistance();
   return (slDistance > 0) ? (slDistance * RiskRewardRatio) : 0;
}

double SetBuyTakeProfit(double entryPrice)
{
   double tpDistance = CalculateTakeProfitDistance();
   if(tpDistance <= 0) tpDistance = GetCurrentATR() * ATR_TP;
   
   double takeProfit = entryPrice + tpDistance;
   
   int minStop = GetMinBrokerStopLevel();
   int tpPoints = (int)(tpDistance / _Point);
   if(tpPoints < minStop) takeProfit = entryPrice + (minStop * _Point);
   
   return NormalizeDouble(takeProfit, _Digits);
}

double SetSellTakeProfit(double entryPrice)
{
   double tpDistance = CalculateTakeProfitDistance();
   if(tpDistance <= 0) tpDistance = GetCurrentATR() * ATR_TP;
   
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
      return (stopLoss < entryPrice && takeProfit > entryPrice && takeProfit > stopLoss);
   }
   else if(orderType == "SELL")
   {
      return (stopLoss > entryPrice && takeProfit < entryPrice && takeProfit < stopLoss);
   }
   return false;
}

bool ValidateBrokerRequirements(double entryPrice, double stopLoss, double takeProfit)
{
   int minStopLevel = GetMinBrokerStopLevel();
   int slDistance = (int)MathAbs((stopLoss - entryPrice) / _Point);
   int tpDistance = (int)MathAbs((takeProfit - entryPrice) / _Point);
   
   return ((slDistance <= 0 || slDistance >= minStopLevel) && 
           (tpDistance <= 0 || tpDistance >= minStopLevel));
}

bool ValidateOrderParameters(double entryPrice, double stopLoss, double takeProfit, 
                              double lotSize, string orderType)
{
   return (ValidateSLandTP(entryPrice, stopLoss, takeProfit, orderType) &&
           ValidateBrokerRequirements(entryPrice, stopLoss, takeProfit) &&
           lotSize > 0);
}

//==============================
// PART 2C: POSITION MANAGEMENT
//==============================

void InitializeTradeStats()
{
   tradeStats.dailyProfit = 0;
   tradeStats.dailyLoss = 0;
   tradeStats.openTrades = 0;
   tradeStats.winTrades = 0;
   tradeStats.lossTrades = 0;
   tradeStats.consecutiveLosses = 0;
   tradeStats.maxDrawdown = 0;
   tradeStats.pauseTrading = false;
}

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
            {
               tradeStats.dailyProfit += dealProfit;
               tradeStats.winTrades++;
               tradeStats.consecutiveLosses = 0;
            }
            else
            {
               tradeStats.dailyLoss += MathAbs(dealProfit);
               tradeStats.lossTrades++;
               tradeStats.consecutiveLosses++;
            }
         }
      }
   }
}

double GetWinRate()
{
   int totalTrades = tradeStats.winTrades + tradeStats.lossTrades;
   return (totalTrades > 0) ? ((double)tradeStats.winTrades / totalTrades * 100) : 0;
}

double GetMaxDrawdown()
{
   double balance = GetAccountBalance();
   double equity = GetAccountEquity();
   double drawdown = ((balance - equity) / balance) * 100;
   return MathMax(drawdown, 0);
}

//==============================
// PART 3B: ACCOUNT PROTECTION
//==============================

bool CheckAccountProtection()
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
   
   double maxDD = GetMaxDrawdown();
   if(maxDD >= MaxDrawdownPercent)
   {
      Print("Maximum drawdown reached: ", maxDD);
      return false;
   }
   
   if(tradeStats.consecutiveLosses >= MaxConsecutiveLosses)
   {
      tradeStats.pauseTrading = true;
      Print("Max consecutive losses reached - Pausing trades");
      return false;
   }
   
   return true;
}

//==============================
// PART 3A: TRADE MANAGEMENT
//==============================

void ManageOpenTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                                                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPoints = (type == POSITION_TYPE_BUY) ? (currentPrice - entryPrice) / _Point :
                                                           (entryPrice - currentPrice) / _Point;
         
         if(EnableBreakeven && profitPoints >= BreakEvenProfit)
            ApplyBreakeven(ticket, entryPrice);
         
         if(EnableTrailingStop && profitPoints > BreakEvenProfit)
            ApplyTrailingStop(ticket, currentPrice, type);
         
         if(EnablePartialClose && profitPoints >= (BreakEvenProfit * 2))
            ApplyPartialClose(ticket, type);
      }
   }
}

void ApplyBreakeven(ulong ticket, double entryPrice)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double currentSL = PositionGetDouble(POSITION_SL);
   
   if(currentSL < entryPrice)
   {
      trade.PositionModify(ticket, entryPrice, PositionGetDouble(POSITION_TP));
   }
}

void ApplyTrailingStop(ulong ticket, double currentPrice, ENUM_POSITION_TYPE type)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double currentSL = PositionGetDouble(POSITION_SL);
   double atr = GetCurrentATR();
   double newSL = 0;
   
   if(type == POSITION_TYPE_BUY)
   {
      newSL = currentPrice - (atr * TrailingStopPercent);
      if(newSL > currentSL)
         trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
   }
   else if(type == POSITION_TYPE_SELL)
   {
      newSL = currentPrice + (atr * TrailingStopPercent);
      if(newSL < currentSL)
         trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
   }
}

void ApplyPartialClose(ulong ticket, ENUM_POSITION_TYPE type)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double volume = PositionGetDouble(POSITION_VOLUME);
   double partialVolume = volume * (PartialClosePercent / 100.0);
   
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   partialVolume = MathRound(partialVolume / lotStep) * lotStep;
   
   if(partialVolume > 0)
   {
      if(type == POSITION_TYPE_BUY)
         trade.Sell(partialVolume, _Symbol);
      else
         trade.Buy(partialVolume, _Symbol);
   }
}

//==============================
// PART 4A: SMART MONEY - SWING DETECTION
//==============================

void DetectSwingHighLow()
{
   int bars = SwingLookback;
   
   for(int i = bars; i < bars * 3; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M15, i);
      double low = iLow(_Symbol, PERIOD_M15, i);
      
      bool isSwingHigh = true;
      bool isSwingLow = true;
      
      for(int j = 1; j <= bars; j++)
      {
         if(iHigh(_Symbol, PERIOD_M15, i + j) >= high) isSwingHigh = false;
         if(iHigh(_Symbol, PERIOD_M15, i - j) >= high) isSwingHigh = false;
         if(iLow(_Symbol, PERIOD_M15, i + j) <= low) isSwingLow = false;
         if(iLow(_Symbol, PERIOD_M15, i - j) <= low) isSwingLow = false;
      }
      
      if(isSwingHigh && high > smData.swingHigh)
      {
         smData.swingHigh = high;
         smData.swingHighBar = i;
      }
      
      if(isSwingLow && low < smData.swingLow)
      {
         smData.swingLow = low;
         smData.swingLowBar = i;
      }
   }
}

//==============================
// PART 4A: BREAK OF STRUCTURE
//==============================

bool DetectBreakOfStructure(string direction)
{
   DetectSwingHighLow();
   
   if(direction == "UP")
   {
      double high = iHigh(_Symbol, PERIOD_M15, 0);
      return (high > smData.swingHigh);
   }
   else if(direction == "DOWN")
   {
      double low = iLow(_Symbol, PERIOD_M15, 0);
      return (low < smData.swingLow);
   }
   
   return false;
}

//==============================
// PART 4B: FAIR VALUE GAPS
//==============================

bool DetectBullishFVG()
{
   double gap = iLow(_Symbol, PERIOD_M15, 0) - iHigh(_Symbol, PERIOD_M15, 2);
   smData.fvgBottom = iHigh(_Symbol, PERIOD_M15, 2);
   smData.fvgTop = iLow(_Symbol, PERIOD_M15, 0);
   
   return (gap > (GetCurrentATR() * FVGThreshold));
}

bool DetectBearishFVG()
{
   double gap = iLow(_Symbol, PERIOD_M15, 2) - iHigh(_Symbol, PERIOD_M15, 0);
   smData.fvgTop = iLow(_Symbol, PERIOD_M15, 2);
   smData.fvgBottom = iHigh(_Symbol, PERIOD_M15, 0);
   
   return (gap > (GetCurrentATR() * FVGThreshold));
}

//==============================
// PART 4C: INSTITUTIONAL LOGIC - ORDER BLOCKS
//==============================

void DetectOrderBlocks()
{
   if(!EnableOrderBlocks) return;
   
   for(int i = 5; i < 20; i++)
   {
      double bodySize = MathAbs(iClose(_Symbol, PERIOD_M15, i) - iOpen(_Symbol, PERIOD_M15, i));
      double atr = GetCurrentATR();
      
      if(bodySize > atr * 0.5)
      {
         smData.orderBlockHigh = iHigh(_Symbol, PERIOD_M15, i);
         smData.orderBlockLow = iLow(_Symbol, PERIOD_M15, i);
         break;
      }
   }
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

double CalculateBuyConfidence()
{
   double confidence = 0;
   if(BuyEMATrendConfirmation()) confidence += 30;
   if(BuyRSIConfirmation()) confidence += 30;
   if(BuyATRConfirmation()) confidence += 20;
   if(EnableSMC && DetectBreakOfStructure("UP")) confidence += 10;
   if(EnableSMC && DetectBullishFVG()) confidence += 10;
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

double CalculateSellConfidence()
{
   double confidence = 0;
   if(SellEMATrendConfirmation()) confidence += 30;
   if(SellRSIConfirmation()) confidence += 30;
   if(SellATRConfirmation()) confidence += 20;
   if(EnableSMC && DetectBreakOfStructure("DOWN")) confidence += 10;
   if(EnableSMC && DetectBearishFVG()) confidence += 10;
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
      if(EnableLogging)
         Print("BUY executed - SL: ", stopLoss, " TP: ", takeProfit);
      return true;
   }
   
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
      if(EnableLogging)
         Print("SELL executed - SL: ", stopLoss, " TP: ", takeProfit);
      return true;
   }
   
   return false;
}

//==============================
// PART 5: DASHBOARD
//==============================

void DrawDashboard()
{
   int y = 20;
   
   DrawText("Balance: $" + DoubleToString(GetAccountBalance(), 2), 10, y);
   y += 20;
   DrawText("Equity: $" + DoubleToString(GetAccountEquity(), 2), 10, y);
   y += 20;
   DrawText("Daily P/L: +" + DoubleToString(tradeStats.dailyProfit, 2) + " / -" + 
            DoubleToString(tradeStats.dailyLoss, 2), 10, y);
   y += 20;
   DrawText("Win Rate: " + DoubleToString(GetWinRate(), 1) + "%", 10, y);
   y += 20;
   DrawText("Open Trades: " + IntegerToString(tradeStats.openTrades), 10, y);
   y += 20;
   DrawText("Drawdown: " + DoubleToString(GetMaxDrawdown(), 2) + "%", 10, y);
   y += 20;
   DrawText("Current Trend: " + GetCurrentTrend(), 10, y);
   y += 20;
   DrawText("Spread: " + DoubleToString((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - 
            SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point, 1) + " pips", 10, y);
   y += 20;
   DrawText("ATR: " + DoubleToString(GetCurrentATR(), _Digits), 10, y);
   y += 20;
   DrawText("RSI: " + DoubleToString(RSIValue[0], 1), 10, y);
}

void DrawText(string text, int x, int y)
{
   static int counter = 0;
   string objName = "Dashboard_" + IntegerToString(counter++);
   
   ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
}

string GetCurrentTrend()
{
   if(FastEMAValue[0] > SlowEMAValue[0])
      return "UPTREND";
   else if(FastEMAValue[0] < SlowEMAValue[0])
      return "DOWNTREND";
   else
      return "SIDEWAYS";
}

//==============================
// END OF EA
//==============================
