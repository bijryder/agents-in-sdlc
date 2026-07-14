//+------------------------------------------------------------------+
//|                                                    Akeula Gold EA|
//|                     Version 1.0 - Part 2A                        |
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

   // Update trade statistics
   UpdateTradeStats();

   // Check daily limits
   if(!CheckDailyLimits())
      return;

   // Trading Logic
   CheckForBuy();

   CheckForSell();

   // Trade Management
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
// PART 2A: RISK MANAGEMENT
//==============================

/**
 * Calculate account balance
 * Returns the account balance in account currency
 */
double GetAccountBalance()
{
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

/**
 * Calculate account equity
 * Returns the current account equity
 */
double GetAccountEquity()
{
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

/**
 * Calculate automatic lot size based on risk percentage
 * Returns the calculated lot size
 */
double CalculateLotSize()
{
   double balance = GetAccountBalance();
   double equity = GetAccountEquity();
   
   // Use equity for more accurate risk calculation
   double riskAmount = equity * (RiskPercent / 100.0);
   
   // Get symbol info
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue == 0 || tickSize == 0)
   {
      Print("Error: Invalid tick value or tick size for symbol: ", _Symbol);
      return 0;
   }
   
   // Get current price for pip value calculation
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid = (ask + bid) / 2;
   
   // Calculate pip value in account currency
   double pipValue = tickValue / tickSize;
   
   // Assume stop loss of 1.5 * ATR (from ATR_SL input)
   double stopLossPips = ATRValue[0] * ATR_SL;
   
   if(stopLossPips == 0)
      stopLossPips = 50; // Default fallback
   
   // Calculate lot size: Risk Amount / (Stop Loss Pips * Pip Value)
   double lotSize = riskAmount / (stopLossPips * pipValue);
   
   return lotSize;
}

/**
 * Get minimum lot size for the symbol
 */
double GetMinLotSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
}

/**
 * Get maximum lot size for the symbol
 */
double GetMaxLotSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
}

/**
 * Validate lot size (apply min/max checks)
 */
double ValidateLotSize(double lotSize)
{
   double minLot = GetMinLotSize();
   double maxLot = GetMaxLotSize();
   
   // Ensure lot size is within bounds
   if(lotSize < minLot)
   {
      Print("Warning: Calculated lot size ", lotSize, " is below minimum ", minLot);
      return minLot;
   }
   
   if(lotSize > maxLot)
   {
      Print("Warning: Calculated lot size ", lotSize, " exceeds maximum ", maxLot);
      return maxLot;
   }
   
   // Round to symbol's lot step
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathRound(lotSize / lotStep) * lotStep;
   
   return lotSize;
}

/**
 * Check if account has sufficient free margin
 */
bool CheckFreeMargin(double lotSize)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
   double marginRequired = lotSize * SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
   
   if(freeMargin < marginRequired)
   {
      Print("Error: Insufficient free margin. Required: ", marginRequired, 
            " Available: ", freeMargin);
      return false;
   }
   
   return true;
}

//==============================
// PART 2A: TRADE CONDITIONS
//==============================

/**
 * Verify symbol is Gold (supports broker suffixes like XAUUSD, GOLD, etc.)
 */
bool IsValidSymbol()
{
   string symbol = _Symbol;
   
   // Support common gold symbol formats
   if(StringFind(symbol, "XAU") != -1 || 
      StringFind(symbol, "GOLD") != -1)
   {
      return true;
   }
   
   Print("Error: This EA only trades Gold (XAU/USD). Current symbol: ", symbol);
   return false;
}

/**
 * Verify Auto Trading is enabled
 */
bool IsAutoTradingEnabled()
{
   if(!EnableAutoTrading)
   {
      Print("Warning: Auto Trading is disabled in EA settings");
      return false;
   }
   
   // Also check terminal auto trading
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("Warning: Auto Trading is disabled in MetaTrader terminal");
      return false;
   }
   
   return true;
}

/**
 * Verify market is open
 */
bool IsMarketOpen()
{
   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      Print("Error: Symbol trading is disabled");
      return false;
   }
   
   return true;
}

/**
 * Spread Filter
 */
bool SpreadFilter()
{
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                   SymbolInfoDouble(_Symbol, SYMBOL_BID)) /
                   _Point;

   if(spread > MaxSpread)
   {
      Print("Warning: Spread ", spread, " exceeds maximum ", MaxSpread);
      return false;
   }

   return true;
}

/**
 * Session Filter
 */
bool SessionFilter()
{
   MqlDateTime tm;
   TimeCurrent(tm);

   if(TradeLondon)
   {
      if(tm.hour >= 8 && tm.hour <= 17)
         return true;
   }

   if(TradeNewYork)
   {
      if(tm.hour >= 13 && tm.hour <= 22)
         return true;
   }

   return false;
}

/**
 * Verify no existing trades (or respect max open trades)
 */
bool CanOpenNewTrade()
{
   int openTrades = CountOpenTrades();
   
   if(openTrades >= MaxOpenTrades)
   {
      Print("Warning: Maximum open trades (", MaxOpenTrades, ") already reached. Current: ", openTrades);
      return false;
   }
   
   return true;
}

/**
 * Count open trades with magic number
 */
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

/**
 * Verify all trade conditions before entry
 */
bool VerifyAllTradeConditions()
{
   if(!EnableAutoTrading)
      return false;
   
   if(!IsValidSymbol())
      return false;
   
   if(!IsAutoTradingEnabled())
      return false;
   
   if(!IsMarketOpen())
      return false;
   
   if(!SpreadFilter())
      return false;
   
   if(!SessionFilter())
      return false;
   
   if(!CanOpenNewTrade())
      return false;
   
   return true;
}

//==============================
// PART 2A: BUY CONDITIONS
//==============================

/**
 * EMA Trend confirmation for Buy
 * Returns true if price is above both EMAs (uptrend)
 */
bool BuyEMATrendConfirmation()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Price should be above both EMAs for uptrend
   if(price > FastEMAValue[0] && FastEMAValue[0] > SlowEMAValue[0])
   {
      return true;
   }
   
   return false;
}

/**
 * RSI confirmation for Buy
 * Returns true if RSI is in oversold or momentum zone
 */
bool BuyRSIConfirmation()
{
   // RSI < 50 = selling pressure easing, or RSI 30-50 = reversal zone
   if(RSIValue[0] < 50 && RSIValue[0] > 20)
   {
      return true;
   }
   
   // Also accept if RSI is rising from oversold
   if(RSIValue[0] > RSIValue[1] && RSIValue[0] < 70)
   {
      return true;
   }
   
   return false;
}

/**
 * ATR Volatility confirmation for Buy
 * Returns true if ATR is in acceptable range
 */
bool BuyATRConfirmation()
{
   // ATR should be present (not zero) and reasonable
   if(ATRValue[0] > 0)
   {
      return true;
   }
   
   return false;
}

/**
 * Break of Structure confirmation (placeholder for Part 4)
 */
bool BuyBreakOfStructure()
{
   // TODO: Implement Break of Structure logic in Part 4
   // For now, return true (placeholder)
   return true;
}

/**
 * Liquidity confirmation (placeholder for Part 4)
 */
bool BuyLiquidityConfirmation()
{
   // TODO: Implement Liquidity confirmation in Part 4
   // For now, return true (placeholder)
   return true;
}

/**
 * Calculate Buy confidence score (0-100)
 */
double CalculateBuyConfidence()
{
   double confidence = 0;
   double maxScore = 100;
   
   // EMA Trend: 30 points
   if(BuyEMATrendConfirmation())
      confidence += 30;
   
   // RSI: 30 points
   if(BuyRSIConfirmation())
      confidence += 30;
   
   // ATR: 20 points
   if(BuyATRConfirmation())
      confidence += 20;
   
   // Break of Structure: 10 points (placeholder)
   if(BuyBreakOfStructure())
      confidence += 10;
   
   // Liquidity: 10 points (placeholder)
   if(BuyLiquidityConfirmation())
      confidence += 10;
   
   return confidence;
}

/**
 * Check for Buy conditions and execute
 */
void CheckForBuy()
{
   if(!VerifyAllTradeConditions())
      return;
   
   // Calculate confidence
   double confidence = CalculateBuyConfidence();
   
   Print("Buy Signal - Confidence: ", DoubleToString(confidence, 2), "%");
   
   if(confidence < MinConfidenceScore)
   {
      Print("Buy confidence ", confidence, " below minimum threshold ", MinConfidenceScore);
      return;
   }
   
   // Calculate lot size
   double lotSize = CalculateLotSize();
   lotSize = ValidateLotSize(lotSize);
   
   if(lotSize <= 0)
   {
      Print("Error: Invalid lot size calculated");
      return;
   }
   
   // Check free margin
   if(!CheckFreeMargin(lotSize))
      return;
   
   // Execute buy
   ExecuteBuyOrder(lotSize);
}

//==============================
// PART 2A: SELL CONDITIONS
//==============================

/**
 * EMA Trend confirmation for Sell
 * Returns true if price is below both EMAs (downtrend)
 */
bool SellEMATrendConfirmation()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Price should be below both EMAs for downtrend
   if(price < FastEMAValue[0] && FastEMAValue[0] < SlowEMAValue[0])
   {
      return true;
   }
   
   return false;
}

/**
 * RSI confirmation for Sell
 * Returns true if RSI is in overbought or momentum zone
 */
bool SellRSIConfirmation()
{
   // RSI > 50 = buying pressure fading, or RSI 50-70 = reversal zone
   if(RSIValue[0] > 50 && RSIValue[0] < 80)
   {
      return true;
   }
   
   // Also accept if RSI is falling from overbought
   if(RSIValue[0] < RSIValue[1] && RSIValue[0] > 30)
   {
      return true;
   }
   
   return false;
}

/**
 * ATR Volatility confirmation for Sell
 * Returns true if ATR is in acceptable range
 */
bool SellATRConfirmation()
{
   // ATR should be present (not zero) and reasonable
   if(ATRValue[0] > 0)
   {
      return true;
   }
   
   return false;
}

/**
 * Break of Structure confirmation (placeholder for Part 4)
 */
bool SellBreakOfStructure()
{
   // TODO: Implement Break of Structure logic in Part 4
   // For now, return true (placeholder)
   return true;
}

/**
 * Liquidity confirmation (placeholder for Part 4)
 */
bool SellLiquidityConfirmation()
{
   // TODO: Implement Liquidity confirmation in Part 4
   // For now, return true (placeholder)
   return true;
}

/**
 * Calculate Sell confidence score (0-100)
 */
double CalculateSellConfidence()
{
   double confidence = 0;
   double maxScore = 100;
   
   // EMA Trend: 30 points
   if(SellEMATrendConfirmation())
      confidence += 30;
   
   // RSI: 30 points
   if(SellRSIConfirmation())
      confidence += 30;
   
   // ATR: 20 points
   if(SellATRConfirmation())
      confidence += 20;
   
   // Break of Structure: 10 points (placeholder)
   if(SellBreakOfStructure())
      confidence += 10;
   
   // Liquidity: 10 points (placeholder)
   if(SellLiquidityConfirmation())
      confidence += 10;
   
   return confidence;
}

/**
 * Check for Sell conditions and execute
 */
void CheckForSell()
{
   if(!VerifyAllTradeConditions())
      return;
   
   // Calculate confidence
   double confidence = CalculateSellConfidence();
   
   Print("Sell Signal - Confidence: ", DoubleToString(confidence, 2), "%");
   
   if(confidence < MinConfidenceScore)
   {
      Print("Sell confidence ", confidence, " below minimum threshold ", MinConfidenceScore);
      return;
   }
   
   // Calculate lot size
   double lotSize = CalculateLotSize();
   lotSize = ValidateLotSize(lotSize);
   
   if(lotSize <= 0)
   {
      Print("Error: Invalid lot size calculated");
      return;
   }
   
   // Check free margin
   if(!CheckFreeMargin(lotSize))
      return;
   
   // Execute sell
   ExecuteSellOrder(lotSize);
}

//==============================
// PART 2A: ORDER EXECUTION
//==============================

/**
 * Execute Buy Order
 */
bool ExecuteBuyOrder(double lotSize)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate Stop Loss and Take Profit
   double stopLoss = ask - (ATRValue[0] * ATR_SL);
   double takeProfit = ask + (ATRValue[0] * ATR_TP);
   
   // Normalize prices
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   takeProfit = NormalizeDouble(takeProfit, _Digits);
   
   string comment = "Akeula Gold EA - Buy - " + TimeToString(TimeCurrent());
   
   Print("Executing BUY order...");
   Print("Lot Size: ", lotSize, " | SL: ", stopLoss, " | TP: ", takeProfit);
   
   // Execute trade
   if(trade.Buy(lotSize, _Symbol, ask, stopLoss, takeProfit, comment))
   {
      Print("Buy order executed successfully!");
      Print("Ticket: ", trade.ResultOrder(), 
            " | Entry: ", ask,
            " | SL: ", stopLoss,
            " | TP: ", takeProfit);
      RecordTradeInfo(trade.ResultOrder(), "BUY", ask, lotSize);
      return true;
   }
   else
   {
      Print("Error: Buy order failed!");
      Print("Error Code: ", trade.ResultRetcode(),
            " | Error Description: ", trade.ResultRetcodeDescription());
      HandleExecutionError(trade.ResultRetcode());
      return false;
   }
}

/**
 * Execute Sell Order
 */
bool ExecuteSellOrder(double lotSize)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate Stop Loss and Take Profit
   double stopLoss = bid + (ATRValue[0] * ATR_SL);
   double takeProfit = bid - (ATRValue[0] * ATR_TP);
   
   // Normalize prices
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   takeProfit = NormalizeDouble(takeProfit, _Digits);
   
   string comment = "Akeula Gold EA - Sell - " + TimeToString(TimeCurrent());
   
   Print("Executing SELL order...");
   Print("Lot Size: ", lotSize, " | SL: ", stopLoss, " | TP: ", takeProfit);
   
   // Execute trade
   if(trade.Sell(lotSize, _Symbol, bid, stopLoss, takeProfit, comment))
   {
      Print("Sell order executed successfully!");
      Print("Ticket: ", trade.ResultOrder(),
            " | Entry: ", bid,
            " | SL: ", stopLoss,
            " | TP: ", takeProfit);
      RecordTradeInfo(trade.ResultOrder(), "SELL", bid, lotSize);
      return true;
   }
   else
   {
      Print("Error: Sell order failed!");
      Print("Error Code: ", trade.ResultRetcode(),
            " | Error Description: ", trade.ResultRetcodeDescription());
      HandleExecutionError(trade.ResultRetcode());
      return false;
   }
}

/**
 * Handle execution errors
 */
void HandleExecutionError(uint errorCode)
{
   switch(errorCode)
   {
      case TRADE_RETCODE_INSUFFICIENT_FUNDS:
         Print("Error: Insufficient funds to open position");
         break;
      case TRADE_RETCODE_POSITION_NOT_FOUND:
         Print("Error: Position not found");
         break;
      case TRADE_RETCODE_MARKET_CLOSED:
         Print("Error: Market is closed");
         break;
      case TRADE_RETCODE_INVALID_VOLUME:
         Print("Error: Invalid volume for trade");
         break;
      case TRADE_RETCODE_INVALID_PRICE:
         Print("Error: Invalid price for trade");
         break;
      default:
         Print("Error: Execution error code ", errorCode);
         break;
   }
}

/**
 * Record trade information
 */
void RecordTradeInfo(ulong ticket, string tradeType, double entryPrice, double lotSize)
{
   Print("=== Trade Record ===");
   Print("Ticket: ", ticket);
   Print("Type: ", tradeType);
   Print("Entry Price: ", entryPrice);
   Print("Lot Size: ", lotSize);
   Print("Time: ", TimeToString(TimeCurrent()));
   Print("====================");
}

//==============================
// TRADE STATISTICS & DAILY LIMITS
//==============================

/**
 * Update daily trading statistics
 */
void UpdateTradeStats()
{
   tradeStats.dailyProfit = 0;
   tradeStats.dailyLoss = 0;
   tradeStats.openTrades = 0;
   
   MqlDateTime now;
   TimeCurrent(now);
   
   // Check all deals/orders from today
   int dealsTotal = HistoryDealsTotal();
   
   for(int i = 0; i < dealsTotal; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      
      if(HistoryDealSelect(ticket))
      {
         ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
         ulong dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         
         MqlDateTime dealDateTime;
         TimeToStruct(dealTime, dealDateTime);
         
         // Check if deal is from today and has our magic number
         if(dealDateTime.day == now.day && 
            dealDateTime.mon == now.mon &&
            dealDateTime.year == now.year &&
            dealMagic == MagicNumber &&
            dealSymbol == _Symbol)
         {
            if(dealProfit > 0)
               tradeStats.dailyProfit += dealProfit;
            else
               tradeStats.dailyLoss += MathAbs(dealProfit);
         }
      }
   }
   
   tradeStats.openTrades = CountOpenTrades();
}

/**
 * Check daily loss and profit limits
 */
bool CheckDailyLimits()
{
   UpdateTradeStats();
   
   // Check daily loss limit
   if(tradeStats.dailyLoss >= DailyLossLimit)
   {
      Print("Warning: Daily loss limit reached! Loss: ", tradeStats.dailyLoss, 
            " Limit: ", DailyLossLimit);
      return false;
   }
   
   // Check daily profit target
   if(tradeStats.dailyProfit >= DailyProfitTarget)
   {
      Print("Notice: Daily profit target reached! Profit: ", tradeStats.dailyProfit,
            " Target: ", DailyProfitTarget);
      return false;
   }
   
   return true;
}

/**
 * Print daily statistics
 */
void PrintDailyStats()
{
   Print("=== Daily Statistics ===");
   Print("Daily Profit: ", DoubleToString(tradeStats.dailyProfit, 2));
   Print("Daily Loss: ", DoubleToString(tradeStats.dailyLoss, 2));
   Print("Open Trades: ", tradeStats.openTrades);
   Print("========================");
}

//==============================
// Manage Trades
//==============================

void ManageTrades()
{
   // Placeholder for Part 3 (Trade Management)
   // This section will handle:
   // - Trailing stops
   // - Breakeven management
   // - Partial profit taking
   // - Dynamic SL adjustment
}
