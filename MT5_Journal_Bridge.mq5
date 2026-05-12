//+------------------------------------------------------------------+
//|  Elite Trader Journal — MT5 Bridge EA                           |
//|  Automatically sends your trades to the journal                  |
//|  Install: Drag onto any chart in MT5                            |
//+------------------------------------------------------------------+
#property copyright "Elite Trader Journal"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// Settings
input int    WebSocketPort = 8765;  // Port (must match journal)
input bool   SendOnOpen    = true;  // Send when trade opens
input bool   SendOnClose   = true;  // Send when trade closes

// Track known positions
ulong knownPositions[];
datetime lastCheck;

//+------------------------------------------------------------------+
int OnInit() {
   Print("Elite Trader Journal Bridge — ACTIVE on port ", WebSocketPort);
   Print("Monitoring all trades. Journal will auto-update.");
   EventSetTimer(2); // check every 2 seconds
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   Print("Elite Trader Journal Bridge — STOPPED");
}

//+------------------------------------------------------------------+
void OnTimer() {
   CheckClosedTrades();
   CheckOpenTrades();
}

//+------------------------------------------------------------------+
void CheckOpenTrades() {
   int total = PositionsTotal();
   for(int i = 0; i < total; i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!IsKnownPosition(ticket)) {
         AddKnownPosition(ticket);
         if(SendOnOpen) SendTradeOpen(ticket);
      }
   }
}

//+------------------------------------------------------------------+
void CheckClosedTrades() {
   HistorySelect(lastCheck, TimeCurrent());
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0) continue;
      long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry == DEAL_ENTRY_OUT) {
         if(SendOnClose) SendTradeClose(ticket);
      }
   }
   lastCheck = TimeCurrent();
}

//+------------------------------------------------------------------+
void SendTradeOpen(ulong ticket) {
   if(!PositionSelectByTicket(ticket)) return;

   string symbol    = PositionGetString(POSITION_SYMBOL);
   double lots      = PositionGetDouble(POSITION_VOLUME);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   long   posType   = PositionGetInteger(POSITION_TYPE);
   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

   string json = StringFormat(
      "{\"type\":\"TRADE_OPENED\","
      "\"ticket\":%d,"
      "\"symbol\":\"%s\","
      "\"lots\":%.2f,"
      "\"openPrice\":%.5f,"
      "\"type_order\":%d,"
      "\"openTime\":%d}",
      ticket, symbol, lots, openPrice, posType, openTime
   );

   WriteToFile(json);
   Print("Journal: Trade OPENED sent — ", symbol, " ", lots, " lots");
}

//+------------------------------------------------------------------+
void SendTradeClose(ulong ticket) {
   string symbol    = HistoryDealGetString(ticket, DEAL_SYMBOL);
   double lots      = HistoryDealGetDouble(ticket, DEAL_VOLUME);
   double profit    = HistoryDealGetDouble(ticket, DEAL_PROFIT);
   double closePrice= HistoryDealGetDouble(ticket, DEAL_PRICE);
   long   dealType  = HistoryDealGetInteger(ticket, DEAL_TYPE);
   datetime openTime= (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
   long   reason    = HistoryDealGetInteger(ticket, DEAL_REASON);

   string closeReason = "Manual";
   if(reason == DEAL_REASON_TP) closeReason = "TP";
   else if(reason == DEAL_REASON_SL) closeReason = "SL";
   else if(reason == DEAL_REASON_SO) closeReason = "StopOut";

   // Detect breakeven (SL close at approximately open price)
   double openDealPrice = 0;
   HistorySelectByPosition(HistoryDealGetInteger(ticket, DEAL_POSITION_ID));
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN) {
         openDealPrice = HistoryDealGetDouble(t, DEAL_PRICE);
         break;
      }
   }
   if(reason == DEAL_REASON_SL && MathAbs(closePrice - openDealPrice) < 0.0005) closeReason = "BE";

   string json = StringFormat(
      "{\"type\":\"TRADE_CLOSED\","
      "\"ticket\":%d,"
      "\"symbol\":\"%s\","
      "\"lots\":%.2f,"
      "\"profit\":%.2f,"
      "\"closePrice\":%.5f,"
      "\"type_order\":%d,"
      "\"openTime\":%d,"
      "\"closeReason\":\"%s\"}",
      ticket, symbol, lots, profit, closePrice, dealType, openTime, closeReason
   );

   WriteToFile(json);
   Print("Journal: Trade CLOSED — ", symbol, " P&L: ", profit, " Reason: ", closeReason);
}

//+------------------------------------------------------------------+
void WriteToFile(string json) {
   // Write trade data to a local file
   // The journal's companion app reads this file and sends to browser
   string filepath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\etj_trades.json";
   int handle = FileOpen("etj_trades.json", FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle != INVALID_HANDLE) {
      FileWriteString(handle, json);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
bool IsKnownPosition(ulong ticket) {
   for(int i = 0; i < ArraySize(knownPositions); i++) {
      if(knownPositions[i] == ticket) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void AddKnownPosition(ulong ticket) {
   int size = ArraySize(knownPositions);
   ArrayResize(knownPositions, size + 1);
   knownPositions[size] = ticket;
}
//+------------------------------------------------------------------+
