//+------------------------------------------------------------------+
//|              NYKX L7/L8 MORNING 5MIN STRATEGY                   |
//|         Converted from TradingView Pine Script to MQ5            |
//|                                                                  |
//|  LOGIC SUMMARY:                                                  |
//|  1. Capture first 5-min candle High/Low of each trading day     |
//|  2. Calculate Midpoint M = (H + L) / 2                          |
//|  3. Derive 8 key price levels using 0.2618% and 0.1309%         |
//|  4. LONG  when price crosses ABOVE L7 (M + 0.1309%)            |
//|  5. SHORT when price crosses BELOW L8 (M - 0.1309%)            |
//|  6. One trade per day only                                       |
//|  7. Fixed SL and TP in pips                                      |
//+------------------------------------------------------------------+
#property copyright  "NYKX Strategy — MT5 EA"
#property version    "1.00"
#property description "L7/L8 Morning Session Strategy based on First 5-Min Candle"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--------------------------------------------------------------------
// INPUT PARAMETERS
//--------------------------------------------------------------------
input group           "=== TRADE SETTINGS ==="
input double          InpLotSize       = 0.1;    // Lot Size
input double          InpSLPips        = 70.0;   // Stop Loss (Pips)
input double          InpTPPips        = 300.0;  // Take Profit (Pips)
input ulong           InpMagicNumber   = 202504; // EA Magic Number

input group           "=== DISPLAY SETTINGS ==="
input bool            InpShowLines     = true;   // Draw All Level Lines
input bool            InpShowLabels    = true;   // Show Line Labels
input int             InpLineWidth     = 2;      // Line Width (1-5)

//--------------------------------------------------------------------
// GLOBAL OBJECTS & VARIABLES
//--------------------------------------------------------------------
CTrade         trade;
CPositionInfo  posInfo;

// Session level values
double  sessHigh      = 0.0;
double  sessLow       = 0.0;
double  sessM         = 0.0;   // Midpoint

// The 8 strategy lines
double  L1 = 0.0;   // H + 0.2618%  (Buy breakout)
double  L2 = 0.0;   // L - 0.2618%  (Sell breakout)
double  L3 = 0.0;   // M + 0.2618%  (Mid Buy breakout)
double  L4 = 0.0;   // M - 0.2618%  (Mid Sell breakout)
double  L5 = 0.0;   // H + 0.1309%  (Buy entry zone)
double  L6 = 0.0;   // L - 0.1309%  (Sell entry zone)
double  L7 = 0.0;   // M + 0.1309%  *** LONG ENTRY ***
double  L8 = 0.0;   // M - 0.1309%  *** SHORT ENTRY ***

// State tracking
bool     firstCaptured = false; // Has first 5-min candle been captured today?
bool     tradedToday   = false; // Has a trade been placed today?
datetime lastDay       = 0;     // Last processed day (for daily reset)
datetime lastBarTime   = 0;     // Last processed bar time (to avoid re-processing)
double   prevBarClose  = 0.0;   // Previous bar's close (for crossover detection)
bool     prevCloseSet  = false; // Whether prevBarClose is valid yet

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    // Configure the trade object
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(20);
    trade.SetTypeFilling(ORDER_FILLING_FOK);

    Print("NYKX L7/L8 Strategy EA Initialized on ", Symbol(), " ", EnumToString(Period()));
    Print("SL=", InpSLPips, " pips | TP=", InpTPPips, " pips | Lot=", InpLotSize);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Remove all drawn objects when EA is removed
    ObjectsDeleteAll(0, "NYKX_");
    Comment("");
    Print("NYKX EA removed. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| MAIN TICK FUNCTION                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    //----------------------------------------------------------------
    // STEP 1: DAILY RESET — Reset state at start of each new day
    //----------------------------------------------------------------
    datetime currentTime = TimeCurrent();
    MqlDateTime dtNow;
    TimeToStruct(currentTime, dtNow);

    // Build today's date as a datetime (midnight)
    datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                  dtNow.year, dtNow.mon, dtNow.day));

    if(today != lastDay)
    {
        lastDay        = today;
        firstCaptured  = false;
        tradedToday    = false;
        prevCloseSet   = false;
        prevBarClose   = 0.0;
        sessHigh = sessLow = sessM = 0.0;
        L1 = L2 = L3 = L4 = L5 = L6 = L7 = L8 = 0.0;

        // Clear previous day's lines
        ObjectsDeleteAll(0, "NYKX_");

        Print("=== NEW DAY RESET: ", TimeToString(today, TIME_DATE), " ===");
    }

    //----------------------------------------------------------------
    // STEP 2: CAPTURE THE FIRST 5-MIN CANDLE OF THE DAY
    //         (Only runs until the first candle is found)
    //----------------------------------------------------------------
    if(!firstCaptured)
    {
        MqlRates rates5[];
        ArraySetAsSeries(rates5, true);

        // Fetch enough M5 bars to find today's first candle
        int copied = CopyRates(Symbol(), PERIOD_M5, 0, 200, rates5);
        if(copied <= 0)
        {
            Print("Warning: Could not fetch M5 data. Retrying...");
            return;
        }

        // rates5[0] = current (possibly forming) M5 bar
        // rates5[1] = last closed M5 bar
        // We scan from oldest available back to newest to find the FIRST candle of today

        int firstIdx = -1;
        for(int i = copied - 1; i >= 1; i--)  // i >= 1 ensures the candle is fully closed
        {
            MqlDateTime barDt;
            TimeToStruct(rates5[i].time, barDt);

            datetime barDay = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                              barDt.year, barDt.mon, barDt.day));

            if(barDay == today)
            {
                firstIdx = i;
                break; // Found the FIRST 5-min candle of today
            }
        }

        if(firstIdx == -1)
        {
            // Market just opened — first candle not yet closed; wait
            return;
        }

        // Capture the session open candle
        sessHigh      = rates5[firstIdx].high;
        sessLow       = rates5[firstIdx].low;
        firstCaptured = true;

        // Calculate all 8 levels
        CalculateLevels();

        // Draw lines on chart if enabled
        if(InpShowLines)
            DrawAllLines();

        // Log to Expert tab
        Print("✅ First 5-Min Candle Captured | Date: ",
              TimeToString(rates5[firstIdx].time, TIME_DATE | TIME_MINUTES));
        Print("   H=", DoubleToString(sessHigh, _Digits),
              " | L=", DoubleToString(sessLow,  _Digits),
              " | M=", DoubleToString(sessM,    _Digits));
        Print("   L7 (Long Entry)  = ", DoubleToString(L7, _Digits));
        Print("   L8 (Short Entry) = ", DoubleToString(L8, _Digits));

        // Update on-chart comment
        UpdateComment();
    }

    //----------------------------------------------------------------
    // STEP 3: NEW BAR DETECTION — Only act once per closed bar
    //         This prevents multiple trade signals within one bar
    //----------------------------------------------------------------
    datetime currentBarTime = iTime(Symbol(), Period(), 0);
    if(currentBarTime == lastBarTime)
        return;  // Same bar still forming, wait

    lastBarTime = currentBarTime;

    // Get the close price of the most recently CLOSED bar (index 1)
    double curClose = iClose(Symbol(), Period(), 1);

    //----------------------------------------------------------------
    // STEP 4: ENTRY LOGIC — Crossover/Crossunder Detection
    //         Mirrors Pine Script's ta.crossover() / ta.crossunder()
    //
    //  LONG:  prevBarClose was BELOW L7 AND curClose is NOW ABOVE L7
    //  SHORT: prevBarClose was ABOVE L8 AND curClose is NOW BELOW L8
    //----------------------------------------------------------------
    if(!tradedToday && firstCaptured && L7 > 0 && L8 > 0 && prevCloseSet)
    {
        double pipSize = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10.0;
        double slOff   = InpSLPips * pipSize;
        double tpOff   = InpTPPips * pipSize;
        int    digits  = _Digits;

        // LONG ENTRY: price crosses above L7
        bool longCondition  = (prevBarClose <= L7) && (curClose > L7);

        // SHORT ENTRY: price crosses below L8
        bool shortCondition = (prevBarClose >= L8) && (curClose < L8);

        if(longCondition)
        {
            double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            double sl  = NormalizeDouble(ask - slOff, digits);
            double tp  = NormalizeDouble(ask + tpOff, digits);

            Print("🟢 LONG SIGNAL | Ask=", ask, " | SL=", sl, " | TP=", tp,
                  " | L7=", L7, " | prevClose=", prevBarClose, " curClose=", curClose);

            if(trade.Buy(InpLotSize, Symbol(), ask, sl, tp, "NYKX L7 Long"))
            {
                tradedToday = true;
                Print("✅ Long order placed successfully. Ticket: ", trade.ResultOrder());
            }
            else
            {
                Print("❌ Long order FAILED. Error: ", trade.ResultRetcode(),
                      " — ", trade.ResultRetcodeDescription());
            }
        }
        else if(shortCondition)
        {
            double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
            double sl  = NormalizeDouble(bid + slOff, digits);
            double tp  = NormalizeDouble(bid - tpOff, digits);

            Print("🔴 SHORT SIGNAL | Bid=", bid, " | SL=", sl, " | TP=", tp,
                  " | L8=", L8, " | prevClose=", prevBarClose, " curClose=", curClose);

            if(trade.Sell(InpLotSize, Symbol(), bid, sl, tp, "NYKX L8 Short"))
            {
                tradedToday = true;
                Print("✅ Short order placed successfully. Ticket: ", trade.ResultOrder());
            }
            else
            {
                Print("❌ Short order FAILED. Error: ", trade.ResultRetcode(),
                      " — ", trade.ResultRetcodeDescription());
            }
        }
    }

    // Store this bar's close as "previous" for next bar's crossover check
    prevBarClose = curClose;
    prevCloseSet = true;
}

//+------------------------------------------------------------------+
//| CALCULATE ALL 8 PRICE LEVELS FROM SESSION HIGH/LOW              |
//+------------------------------------------------------------------+
void CalculateLevels()
{
    sessM = (sessHigh + sessLow) / 2.0;

    // 0.2618% levels (outer zone)
    L1 = sessHigh * (1.0 + 0.002618);   // Buy  breakout level
    L2 = sessLow  * (1.0 - 0.002618);   // Sell breakout level
    L3 = sessM    * (1.0 + 0.002618);   // Mid  buy  level
    L4 = sessM    * (1.0 - 0.002618);   // Mid  sell level

    // 0.1309% levels (inner zone — entry triggers)
    L5 = sessHigh * (1.0 + 0.001309);   // Buy  entry zone
    L6 = sessLow  * (1.0 - 0.001309);   // Sell entry zone
    L7 = sessM    * (1.0 + 0.001309);   // *** LONG  ENTRY LINE ***
    L8 = sessM    * (1.0 - 0.001309);   // *** SHORT ENTRY LINE ***
}

//+------------------------------------------------------------------+
//| DRAW A SINGLE HORIZONTAL LINE ON CHART                          |
//+------------------------------------------------------------------+
void DrawLine(string name, double price, color clr, string tooltip, ENUM_LINE_STYLE style = STYLE_SOLID)
{
    // Remove existing object with same name if any
    if(ObjectFind(0, name) >= 0)
        ObjectDelete(0, name);

    // Create horizontal line
    if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
    {
        Print("Warning: Could not create line ", name);
        return;
    }

    ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,     InpLineWidth);
    ObjectSetInteger(0, name, OBJPROP_STYLE,     style);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,    false);
    ObjectSetString( 0, name, OBJPROP_TOOLTIP,   tooltip);

    // Optionally add a text label near the line
    if(InpShowLabels)
    {
        string lblName = name + "_LBL";
        if(ObjectFind(0, lblName) >= 0) ObjectDelete(0, lblName);

        datetime labelTime = TimeCurrent() + PeriodSeconds(Period()) * 3;
        ObjectCreate(0, lblName, OBJ_TEXT, 0, labelTime, price);
        ObjectSetString( 0, lblName, OBJPROP_TEXT,      tooltip + " = " + DoubleToString(price, _Digits));
        ObjectSetInteger(0, lblName, OBJPROP_COLOR,     clr);
        ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE,  8);
        ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
    }
}

//+------------------------------------------------------------------+
//| DRAW ALL 9 STRATEGY LINES ON CHART                              |
//+------------------------------------------------------------------+
void DrawAllLines()
{
    // 0.2618% Outer Levels
    DrawLine("NYKX_L1", L1,    clrLime,        "L1 Buy  H+0.2618%");
    DrawLine("NYKX_L2", L2,    clrRed,         "L2 Sell L-0.2618%");
    DrawLine("NYKX_L3", L3,    clrSpringGreen, "L3 Mid Buy  M+0.2618%");
    DrawLine("NYKX_L4", L4,    clrOrangeRed,   "L4 Mid Sell M-0.2618%");

    // 0.1309% Inner Levels
    DrawLine("NYKX_L5", L5,    clrAqua,        "L5 Buy  H+0.1309%");
    DrawLine("NYKX_L6", L6,    clrPink,        "L6 Sell L-0.1309%");

    // Entry Lines (thicker/highlighted)
    DrawLine("NYKX_L7", L7,    clrYellow,      "L7 LONG ENTRY M+0.1309% ⚡",  STYLE_SOLID);
    DrawLine("NYKX_L8", L8,    clrMagenta,     "L8 SHORT ENTRY M-0.1309% ⚡", STYLE_SOLID);

    // Midpoint
    DrawLine("NYKX_M",  sessM, clrWhite,       "Midpoint (H+L)/2", STYLE_DOT);

    // Session high/low reference lines
    DrawLine("NYKX_H",  sessHigh, clrDodgerBlue, "Session H (First 5-Min)", STYLE_DASH);
    DrawLine("NYKX_L",  sessLow,  clrDeepPink,   "Session L (First 5-Min)", STYLE_DASH);
}

//+------------------------------------------------------------------+
//| UPDATE ON-CHART INFO COMMENT                                    |
//+------------------------------------------------------------------+
void UpdateComment()
{
    string info = "";
    info += "╔══════════════════════════════╗\n";
    info += "║   NYKX L7/L8 Morning 5Min    ║\n";
    info += "╠══════════════════════════════╣\n";
    info += StringFormat("║  Session H  : %s\n", DoubleToString(sessHigh, _Digits));
    info += StringFormat("║  Session L  : %s\n", DoubleToString(sessLow,  _Digits));
    info += StringFormat("║  Midpoint M : %s\n", DoubleToString(sessM,    _Digits));
    info += "║──────────────────────────────║\n";
    info += StringFormat("║  L1 (H+0.26%%): %s\n", DoubleToString(L1, _Digits));
    info += StringFormat("║  L2 (L-0.26%%): %s\n", DoubleToString(L2, _Digits));
    info += StringFormat("║  L3 (M+0.26%%): %s\n", DoubleToString(L3, _Digits));
    info += StringFormat("║  L4 (M-0.26%%): %s\n", DoubleToString(L4, _Digits));
    info += StringFormat("║  L5 (H+0.13%%): %s\n", DoubleToString(L5, _Digits));
    info += StringFormat("║  L6 (L-0.13%%): %s\n", DoubleToString(L6, _Digits));
    info += StringFormat("║  L7 LONG ⚡  : %s\n", DoubleToString(L7, _Digits));
    info += StringFormat("║  L8 SHORT ⚡ : %s\n", DoubleToString(L8, _Digits));
    info += "║──────────────────────────────║\n";
    info += StringFormat("║  SL Pips    : %.0f\n", InpSLPips);
    info += StringFormat("║  TP Pips    : %.0f\n", InpTPPips);
    info += StringFormat("║  Traded Today: %s\n",  tradedToday ? "YES ✅" : "NO ⏳");
    info += "╚══════════════════════════════╝";

    Comment(info);
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION HANDLER (optional — for logging)              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        if(trans.deal_type == DEAL_TYPE_BUY)
            Print("📈 BUY deal confirmed. Deal #", trans.deal, " Volume=", trans.volume);
        else if(trans.deal_type == DEAL_TYPE_SELL)
            Print("📉 SELL deal confirmed. Deal #", trans.deal, " Volume=", trans.volume);
    }
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
