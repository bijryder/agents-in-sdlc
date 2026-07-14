//+------------------------------------------------------------------+
//|                                                    Akeula Gold EA|
//|                     Version 1.0 - Part 2B                        |
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
input ulong  MagicNumber       = 777777;
input double RiskPercent       = 1.0;

input group "Trading Session"

input bool TradeLondon    = true;
input bool TradeNewYork   = true;

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
input double RiskRewardRatio = 2.0;  // For configurable R:R

input group "Protection"

input double DailyLossLimit = 5.0;
input double DailyProfitTarget = 3.0;

input group "Trade Management"

input int MaxOpenTrades = 3;
input double MinConfidenceScore = 60.0;

//==============================
// Indicator Handles
//==============================

int FastEMAHandle;
int SlowEMAHandle;
int RSIHandle;
int ATRHandle;

//==============================
// Indicator Buffers
//==============================

double FastEMAValue[];
double SlowEMAValue[];
double RSIValue[];
double ATRValue[];

//==============================
// Trade Statistics
//==============================

struct TradeStats
{
   double dailyProfit;
   double dailyLoss;
   int openTrades;
};

TradeStats tradeStats;

//==============================
// Initialization
//==============================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   FastEMAHandle=iMA(_Symbol,
                     PERIOD_M15,
                     FastEMA,
                     0,
                     MODE_EMA,
                     PRICE_CLOSE);

   SlowEMAHandle=iMA(_Symbol,
                     PERIOD_M15,
                     SlowEMA,
                     0,
                     MODE_EMA,
                     PRICE_CLOSE);

   RSIHandle=iRSI(_Symbol,
                  PERIOD_M5,
                  RSI_Period,
                  PRICE_CLOSE);

   ATRHandle=iATR(_Symbol,
                  PERIOD_M5,
                  ATR_Period);

   if(FastEMAHandle==INVALID_HANDLE)
      return(INIT_FAILED);

   if(SlowEMAHandle==INVALID_HANDLE)
      return(INIT_FAILED);

   if(RSIHandle==INVALID_HANDLE)
      return(INIT_FAILED);

   if(ATRHandle==INVALID_HANDLE)
      return(INIT_FAILED);

   Print("Akeula Gold EA Initialized Successfully");

   return(INIT_SUCCEEDED);
}

//==============================
// Deinitialization
//==============================

void OnDeinit(const int reason)
{
   IndicatorRelease(FastEMAHandle);
   IndicatorRelease(SlowEMAHandle);
   IndicatorRelease(RSIHandle);
   IndicatorRelease(ATRHandle);

   Print("EA Removed.");
}

//==============================
// Main Tick Function
//==============================

void OnTick()
{
   if(!EnableAutoTrading)
      return;

   if(!IsValidSymbol())
      return;

   UpdateIndicators();

   if(!SpreadFilter())
      return;

   if(!SessionFilter())
      return;

   UpdateTradeStats();

   if(!CheckDailyLimits())
      return;

   CheckForBuy();
   CheckForSell();
   ManageTrades();
}

//==============================
// Update Indicator Values
//==============================

void UpdateIndicators()
{
   CopyBuffer(FastEMAHandle,0,0,3,FastEMAValue);
   CopyBuffer(SlowEMAHandle,0,0,3,SlowEMAValue);
   CopyBuffer(RSIHandle,0,0,3,RSIValue);
   CopyBuffer(ATRHandle,0,0,3,ATRValue);
}

//==============================
// PART 2B: ATR STOP LOSS
//==============================

/**
 * Read current ATR value
 * Returns the current ATR[0] value
 */
double GetCurrentATR()
{
   if(ATRValue[0] <= 0)
   {
      Print("Error: Invalid ATR value: ", ATRValue[0]);
      return 0;
   }
   
   return ATRValue[0];
}

/**
 * Calculate Stop Loss distance based on ATR
 * Returns the SL distance in points
 */
double CalculateATRStopLossDistance()
{
   double atr = GetCurrentATR();
   
   if(atr <= 0)
      return 0;
   
   // SL distance = ATR * ATR_SL multiplier
   double slDistance = atr * ATR_SL;
   
   Print("ATR: ", DoubleToString(atr, _Digits), 
         " | SL Distance: ", DoubleToString(slDistance, _Digits));
   
   return slDistance;
}

/**
 * Get broker's minimum stop level in points
 * Returns the minimum distance for SL/TP from entry price
 */
int GetMinBrokerStopLevel()
{
   int minStop = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   
   if(minStop == 0)
   {
      // Default to 50 points if broker doesn't specify
      minStop = 50;
   }
   
   return minStop;
}

/**
 * Validate Stop Loss against broker requirements
 * Ensures SL meets minimum broker stop level
 */
bool ValidateStopLossDistance(double slDistance)
{
   int minStopLevel = GetMinBrokerStopLevel();
   int slPoints = (int)(slDistance / _Point);
   
   if(slPoints < minStopLevel)
   {
      Print("Warning: Calculated SL distance (", slPoints, " points) is below broker minimum (", 
            minStopLevel, " points). Adjusting to minimum.");
      return false;
   }
   
   Print("SL distance ", slPoints, " points meets broker minimum of ", minStopLevel, " points");
   return true;
}

/**
 * Set Stop Loss for Buy order
 * Returns the calculated SL price
 */
double SetBuyStopLoss(double entryPrice)
{
   double slDistance = CalculateATRStopLossDistance();
   
   if(slDistance <= 0)
   {
      Print("Error: Invalid SL distance calculated");
      return 0;
   }
   
   // For Buy: SL is below entry price
   double stopLoss = entryPrice - slDistance;
   
   // Validate against broker requirements
   if(!ValidateStopLossDistance(slDistance))
   {
      // Adjust to broker minimum if needed
      int minStop = GetMinBrokerStopLevel();
      stopLoss = entryPrice - (minStop * _Point);
   }
   
   // Normalize the price
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   
   Print("Buy SL Set: Entry=", entryPrice, " | SL=", stopLoss);
   
   return stopLoss;
}

/**
 * Set Stop Loss for Sell order
 * Returns the calculated SL price
 */
double SetSellStopLoss(double entryPrice)
{
   double slDistance = CalculateATRStopLossDistance();
   
   if(slDistance <= 0)
   {
      Print("Error: Invalid SL distance calculated");
      return 0;
   }
   
   // For Sell: SL is above entry price
   double stopLoss = entryPrice + slDistance;
   
   // Validate against broker requirements
   if(!ValidateStopLossDistance(slDistance))
   {
      // Adjust to broker minimum if needed
      int minStop = GetMinBrokerStopLevel();
      stopLoss = entryPrice + (minStop * _Point);
   }
   
   // Normalize the price
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   
   Print("Sell SL Set: Entry=", entryPrice, " | SL=", stopLoss);
   
   return stopLoss;
}

//==============================
// PART 2B: ATR TAKE PROFIT
//==============================

/**
 * Calculate Take Profit using configurable Risk:Reward ratio
 * TP = Entry + (SL Distance * Risk:Reward Ratio)
 * Returns the TP distance in points
 */
double CalculateTakeProfitDistance()
{
   double slDistance = CalculateATRStopLossDistance();
   
   if(slDistance <= 0)
   {
      Print("Error: Cannot calculate TP with invalid SL distance");
      return 0;
   }
   
   // TP distance = SL distance * Risk:Reward Ratio
   double tpDistance = slDistance * RiskRewardRatio;
   
   Print("TP Distance calculated using R:R ratio of ", RiskRewardRatio, 
         " | TP Distance: ", DoubleToString(tpDistance, _Digits));
   
   return tpDistance;
}

/**
 * Alternative: Calculate Take Profit using ATR_TP multiplier
 * Returns the TP distance in points
 */
double CalculateTakeProfitDistanceByATR()
{
   double atr = GetCurrentATR();
   
   if(atr <= 0)
      return 0;
   
   // TP distance = ATR * ATR_TP multiplier
   double tpDistance = atr * ATR_TP;
   
   Print("TP Distance (using ATR multiplier): ", DoubleToString(tpDistance, _Digits));
   
   return tpDistance;
}

/**
 * Set Take Profit for Buy order
 * Returns the calculated TP price
 */
double SetBuyTakeProfit(double entryPrice)
{
   // Use Risk:Reward ratio method
   double tpDistance = CalculateTakeProfitDistance();
   
   if(tpDistance <= 0)
   {
      Print("Error: Invalid TP distance calculated, using ATR method");
      tpDistance = CalculateTakeProfitDistanceByATR();
   }
   
   // For Buy: TP is above entry price
   double takeProfit = entryPrice + tpDistance;
   
   // Validate against broker requirements
   int minStop = GetMinBrokerStopLevel();
   int tpPoints = (int)(tpDistance / _Point);
   
   if(tpPoints < minStop)
   {
      Print("Warning: TP distance (", tpPoints, " points) below broker minimum (", minStop, " points)");
      takeProfit = entryPrice + (minStop * _Point);
   }
   
   // Normalize the price
   takeProfit = NormalizeDouble(takeProfit, _Digits);
   
   Print("Buy TP Set: Entry=", entryPrice, " | TP=", takeProfit);
   
   return takeProfit;
}

/**
 * Set Take Profit for Sell order
 * Returns the calculated TP price
 */
double SetSellTakeProfit(double entryPrice)
{
   // Use Risk:Reward ratio method
   double tpDistance = CalculateTakeProfitDistance();
   
   if(tpDistance <= 0)
   {
      Print("Error: Invalid TP distance calculated, using ATR method");
      tpDistance = CalculateTakeProfitDistanceByATR();
   }
   
   // For Sell: TP is below entry price
   double takeProfit = entryPrice - tpDistance;
   
   // Validate against broker requirements
   int minStop = GetMinBrokerStopLevel();
   int tpPoints = (int)(tpDistance / _Point);
   
   if(tpPoints < minStop)
   {
      Print("Warning: TP distance (", tpPoints, " points) below broker minimum (", minStop, " points)");
      takeProfit = entryPrice - (minStop * _Point);
   }
   
   // Normalize the price
   takeProfit = NormalizeDouble(takeProfit, _Digits);
   
   Print("Sell TP Set: Entry=", entryPrice, " | TP=", takeProfit);
   
   return takeProfit;
}

//==============================
// PART 2B: SAFETY CHECKS
//==============================

/**
 * Validate Stop Loss and Take Profit
 * Ensures SL is on correct side of entry and TP is on correct side of SL
 */
bool ValidateSLandTP(double entryPrice, double stopLoss, double takeProfit, string orderType)
{
   if(orderType == "BUY")
   {
      // For BUY: SL should be below entry, TP should be above entry
      if(stopLoss >= entryPrice)
      {
         Print("Error: Buy SL (", stopLoss, ") is not below entry price (", entryPrice, ")");
         return false;
      }
      
      if(takeProfit <= entryPrice)
      {
         Print("Error: Buy TP (", takeProfit, ") is not above entry price (", entryPrice, ")");
         return false;
      }
      
      if(takeProfit <= stopLoss)
      {
         Print("Error: Buy TP (", takeProfit, ") is not above SL (", stopLoss, ")");
         return false;
      }
      
      Print("Buy SL/TP validation passed - SL: ", stopLoss, " | Entry: ", entryPrice, " | TP: ", takeProfit);
      return true;
   }
   else if(orderType == "SELL")
   {
      // For SELL: SL should be above entry, TP should be below entry
      if(stopLoss <= entryPrice)
      {
         Print("Error: Sell SL (", stopLoss, ") is not above entry price (", entryPrice, ")");
         return false;
      }
      
      if(takeProfit >= entryPrice)
      {
         Print("Error: Sell TP (", takeProfit, ") is not below entry price (", entryPrice, ")");
         return false;
      }
      
      if(takeProfit >= stopLoss)
      {
         Print("Error: Sell TP (", takeProfit, ") is not below SL (", stopLoss, ")");
         return false;
      }
      
      Print("Sell SL/TP validation passed - TP: ", takeProfit, " | Entry: ", entryPrice, " | SL: ", stopLoss);
      return true;
   }
   
   Print("Error: Invalid order type: ", orderType);
   return false;
}

/**
 * Validate broker requirements for SL and TP
 * Ensures both SL and TP meet broker's minimum distance requirements
 */
bool ValidateBrokerRequirements(double entryPrice, double stopLoss, double takeProfit)
{
   int minStopLevel = GetMinBrokerStopLevel();
   
   // Check SL distance
   int slDistance = (int)MathAbs((stopLoss - entryPrice) / _Point);
   if(slDistance < minStopLevel && slDistance > 0)
   {
      Print("Error: SL distance (", slDistance, " points) below broker minimum (", minStopLevel, " points)");
      return false;
   }
   
   // Check TP distance
   int tpDistance = (int)MathAbs((takeProfit - entryPrice) / _Point);
   if(tpDistance < minStopLevel && tpDistance > 0)
   {
      Print("Error: TP distance (", tpDistance, " points) below broker minimum (", minStopLevel, " points)");
      return false;
   }
   
   Print("Broker requirements validation passed");
   return true;
}

/**
 * Normalize prices to broker's required decimal places
 * Ensures all prices comply with broker standards
 */
double NormalizePrice(double price)
{
   return NormalizeDouble(price, _Digits);
}

/**
 * Normalize lot size to broker's volume step
 * Ensures lot size is valid for the broker
 */
double NormalizeLotSize(double lotSize)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Ensure within limits
   if(lotSize < minLot)
      lotSize = minLot;
   
   if(lotSize > maxLot)
      lotSize = maxLot;
   
   // Round to lot step
   lotSize = MathRound(lotSize / lotStep) * lotStep;
   
   return NormalizeDouble(lotSize, 2);
}

/**
 * Comprehensive validation for all SL, TP, and order parameters
 */
bool ValidateOrderParameters(double entryPrice, double stopLoss, double takeProfit, 
                              double lotSize, string orderType)
{
   Print("=== Validating Order Parameters ===");
   
   // 1. Validate SL and TP logic
   if(!ValidateSLandTP(entryPrice, stopLoss, takeProfit, orderType))
   {
      Print("Error: SL/TP validation failed");
      return false;
   }
   
   // 2. Validate broker requirements
   if(!ValidateBrokerRequirements(entryPrice, stopLoss, takeProfit))
   {
      Print("Error: Broker requirements validation failed");
      return false;
   }
   
   // 3. Check prices are normalized
   if(entryPrice != NormalizePrice(entryPrice))
   {
      Print("Error: Entry price not properly normalized");
      return false;
   }
   
   if(stopLoss != NormalizePrice(stopLoss))
   {
      Print("Error: SL price not properly normalized");
      return false;
   }
   
   if(takeProfit != NormalizePrice(takeProfit))
   {
      Print("Error: TP price not properly normalized");
      return false;
   }
   
   // 4. Check lot size is normalized
   if(lotSize != NormalizeLotSize(lotSize))
   {
      Print("Warning: Lot size adjusted to broker standards");
   }
   
   // 5. Verify lot size is positive
   if(lotSize <= 0)
   {
      Print("Error: Invalid lot size: ", lotSize);
      return false;
   }
   
   Print("=== Order Parameters Valid ===");
   return true;
}

//==============================
// HELPER FUNCTIONS
//==============================

/**
 * Get account balance
 */
double GetAccountBalance()
{
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

/**
 * Get account equity
 */
double GetAccountEquity()
{
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

/**
 * Calculate lot size based on risk
 */
double CalculateLotSize()
{
   double equity = GetAccountEquity();
   double riskAmount = equity * (RiskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue == 0 || tickSize == 0)
      return 0;
   
   double slDistance = CalculateATRStopLossDistance();
   if(slDistance == 0)
      return 0;
   
   double pipValue = tickValue / tickSize;
   double lotSize = riskAmount / (slDistance * pipValue);
   
   return lotSize;
}

/**
 * Check if auto trading is enabled
 */
bool IsAutoTradingEnabled()
{
   if(!EnableAutoTrading)
      return false;
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   
   return true;
}

/**
 * Verify symbol is Gold
 */
bool IsValidSymbol()
{
   string symbol = _Symbol;
   
   if(StringFind(symbol, "XAU") != -1 || 
      StringFind(symbol, "GOLD") != -1)
   {
      return true;
   }
   
   return false;
}

/**
 * Print SL/TP summary
 */
void PrintSLTPSummary(string orderType, double entry, double sl, double tp, double lotSize)
{
   Print("=== ", orderType, " Order Summary ===");
   Print("Entry Price: ", entry);
   Print("Stop Loss: ", sl);
   Print("Take Profit: ", tp);
   Print("Lot Size: ", lotSize);
   Print("SL Distance: ", MathAbs((sl - entry) / _Point), " points");
   Print("TP Distance: ", MathAbs((tp - entry) / _Point), " points");
   Print("Risk:Reward: 1:", RiskRewardRatio);
   Print("===========================");
}

//==============================
// Buy and Sell Placeholders
//==============================

void CheckForBuy()
{
   // Placeholder - will be integrated with Part 2A logic
}

void CheckForSell()
{
   // Placeholder - will be integrated with Part 2A logic
}

//==============================
// Trade Management
//==============================

void ManageTrades()
{
   // Placeholder for Part 3
}

//==============================
// Trade Statistics
//==============================

void UpdateTradeStats()
{
   // Placeholder
}

bool CheckDailyLimits()
{
   return true;
}

bool SpreadFilter()
{
   return true;
}

bool SessionFilter()
{
   return true;
}
