//+------------------------------------------------------------------+
//| ATR Trailing Stop Test Harness                                  |
//| Opens one deterministic test position for MT5 Strategy Tester.  |
//| This file is intentionally separate from the production manager.|
//+------------------------------------------------------------------+
#property version   "1.00"
#property description "Optional test harness. Opens one deterministic position only."

enum TestDirection
  {
   TEST_BUY = 0,
   TEST_SELL = 1
  };

input group "Test Position"
input TestDirection Direction                 = TEST_BUY;
input double        TestVolume                = 0.01;
input bool          SetInitialStopLoss        = false;
input int           InitialStopLossPoints     = 500;
input bool          SetInitialTakeProfit      = false;
input int           InitialTakeProfitPoints   = 1000;

input group "Execution"
input ulong         TestMagicNumber           = 8152026;
input int           DeviationPoints           = 20;
input bool          CloseTestPositionOnDeinit = false;

bool g_order_attempted=false;
ulong g_opened_ticket=0;

void LogHarness(const string level,const string message)
  {
   Print("[ATRTEST][",level,"] ",message);
  }

int DecimalPrecision(const double value)
  {
   for(int digits=0;digits<=8;digits++)
     {
      double scaled=value*MathPow(10.0,digits);
      if(MathAbs(scaled-MathRound(scaled))<=1e-8)
         return(digits);
     }
   return(8);
  }

double NormalizeVolume(const string symbol,const double requested)
  {
   double minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maximum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minimum<=0.0 || maximum<minimum || step<=0.0)
      return(0.0);

   double bounded=MathMax(minimum,MathMin(maximum,requested));
   double normalized=minimum+MathFloor((bounded-minimum)/step+1e-10)*step;
   int volume_digits=(int)MathMax(DecimalPrecision(minimum),DecimalPrecision(step));
   return(NormalizeDouble(normalized,volume_digits));
  }

ENUM_ORDER_TYPE_FILLING ResolveFillingMode(const string symbol)
  {
   long filling=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
      return(ORDER_FILLING_FOK);
   if((filling & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
      return(ORDER_FILLING_IOC);
   return(ORDER_FILLING_RETURN);
  }

bool OpenTestPosition(void)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0.0 || tick.ask<=0.0)
     {
      LogHarness("WARN","No valid tick yet; test order will not be retried automatically.");
      return(false);
     }

   double volume=NormalizeVolume(_Symbol,TestVolume);
   if(volume<=0.0)
     {
      LogHarness("ERROR","Invalid volume or unavailable symbol volume specification.");
      return(false);
     }

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0)
     {
      LogHarness("ERROR","Invalid symbol point.");
      return(false);
     }

   bool buy=(Direction==TEST_BUY);
   double price=(buy ? tick.ask : tick.bid);
   double sl=0.0;
   double tp=0.0;
   if(SetInitialStopLoss)
      sl=NormalizeDouble(buy ? price-InitialStopLossPoints*point : price+InitialStopLossPoints*point,digits);
   if(SetInitialTakeProfit)
      tp=NormalizeDouble(buy ? price+InitialTakeProfitPoints*point : price-InitialTakeProfitPoints*point,digits);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action=TRADE_ACTION_DEAL;
   request.symbol=_Symbol;
   request.magic=TestMagicNumber;
   request.volume=volume;
   request.type=(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   request.price=price;
   request.sl=sl;
   request.tp=tp;
   request.deviation=DeviationPoints;
   request.type_filling=ResolveFillingMode(_Symbol);
   request.comment="ATR_TRAILING_TEST";

   ResetLastError();
   if(!OrderSend(request,result))
     {
      LogHarness("ERROR",StringFormat("ORDER_REJECTED local_error=%d retcode=%u comment=%s",GetLastError(),result.retcode,result.comment));
      return(false);
     }

   if(result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_PLACED)
     {
      LogHarness("ERROR",StringFormat("ORDER_REJECTED retcode=%u comment=%s",result.retcode,result.comment));
      return(false);
     }

   LogHarness("INFO",StringFormat("TEST_ORDER_SENT direction=%s volume=%.2f price=%.10f sl=%.10f tp=%.10f order=%I64u deal=%I64u",
                                   buy ? "BUY" : "SELL",volume,price,sl,tp,result.order,result.deal));
   return(true);
  }

bool ClosePositionByTicket(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return(false);

   string symbol=PositionGetString(POSITION_SYMBOL);
   double volume=PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE position_type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick))
      return(false);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action=TRADE_ACTION_DEAL;
   request.position=ticket;
   request.symbol=symbol;
   request.volume=volume;
   request.type=(position_type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.price=(position_type==POSITION_TYPE_BUY ? tick.bid : tick.ask);
   request.deviation=DeviationPoints;
   request.type_filling=ResolveFillingMode(symbol);

   if(!OrderSend(request,result) || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_PLACED))
     {
      LogHarness("WARN",StringFormat("CLOSE_REJECTED ticket=%I64u retcode=%u comment=%s",ticket,result.retcode,result.comment));
      return(false);
     }
   LogHarness("INFO",StringFormat("TEST_POSITION_CLOSED ticket=%I64u retcode=%u",ticket,result.retcode));
   return(true);
  }

int OnInit(void)
  {
   if(!MQLInfoInteger(MQL_TESTER))
     {
      LogHarness("ERROR","This test harness may run only in the MT5 Strategy Tester.");
      return(INIT_FAILED);
     }

   if(TestVolume<=0.0 || InitialStopLossPoints<0 || InitialTakeProfitPoints<0 || DeviationPoints<0)
     {
      LogHarness("ERROR","Invalid test inputs.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   LogHarness("INFO",StringFormat("READY symbol=%s magic=%I64u direction=%s",_Symbol,TestMagicNumber,
                                   Direction==TEST_BUY ? "BUY" : "SELL"));
   return(INIT_SUCCEEDED);
  }

void OnTick(void)
  {
   if(g_order_attempted)
      return;
   g_order_attempted=true;
   OpenTestPosition();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0 || !HistoryDealSelect(trans.deal))
      return;

   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol ||
      HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=(long)TestMagicNumber ||
      HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_IN)
      return;

   long position_identifier=HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket!=0 && PositionGetInteger(POSITION_IDENTIFIER)==position_identifier)
        {
         g_opened_ticket=ticket;
         LogHarness("INFO",StringFormat("TEST_POSITION_OPENED ticket=%I64u identifier=%I64d",ticket,position_identifier));
         return;
        }
     }
  }

void OnDeinit(const int reason)
  {
   if(CloseTestPositionOnDeinit && g_opened_ticket!=0)
      ClosePositionByTicket(g_opened_ticket);
   LogHarness("INFO",StringFormat("DEINITIALIZED reason=%d",reason));
  }
