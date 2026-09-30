//+------------------------------------------------------------------+
//| Product: ATR Trailing Stop Manager EA                           |
//| Version: v1 Beta                                                |
//| Purpose: Research/demo ATR-based trailing stop manager.         |
//| Core: ATR + high-water/low-water trailing.                      |
//| Trading entry: None.                                            |
//| Live-money recommendation: Not part of this version.            |
//+------------------------------------------------------------------+
#property version   "1.00"
#property description "ATR trailing stop manager. It never opens positions."

const int MIN_MODIFICATION_INTERVAL_SECONDS = 1;

input group "ATR Settings"
input int             ATRPeriod              = 14;
input ENUM_TIMEFRAMES ATRTimeframe           = PERIOD_CURRENT;
input double          ATRMultiplier          = 2.5;

input group "Activation"
input bool            UseActivationThreshold = true;
input double          ActivationATR          = 1.0;

input group "Trailing Step"
input bool            UseMinimumTrailingStep = true;
input double          MinimumStepATR         = 0.10;

input group "Position Filters"
input bool            ManageCurrentSymbolOnly = true;
input bool            ManageManualTrades      = true;
input bool            UseMagicNumberFilter    = false;
input long            MagicNumber             = 0;

input group "Diagnostics"
input bool            EnableDebugLog         = true;

struct PositionTrailState
  {
   ulong              ticket;
   long               identifier;
   string             symbol;
   ENUM_POSITION_TYPE type;
   long               open_time_msc;
   double             open_price;
   double             highest_bid;
   double             lowest_ask;
   double             activation_atr_reference;
   double             activation_price;
   bool               trailing_active;
   double             last_known_sl;
   double             last_candidate_sl;
   datetime           last_modification_time;
   long               magic_number;
   uint               last_retcode;
   int                modification_count;
   int                rejected_modification_count;
  };

struct AtrHandleEntry
  {
   string symbol;
   int    handle;
  };

PositionTrailState g_states[];
AtrHandleEntry     g_atr_handles[];

string PositionTypeText(const ENUM_POSITION_TYPE type)
  {
   return(type == POSITION_TYPE_BUY ? "BUY" : "SELL");
  }

void LogInfo(const string message)
  {
   Print("[ATRTS][INFO] ",message);
  }

void LogWarn(const string message)
  {
   Print("[ATRTS][WARN] ",message);
  }

void LogError(const string message)
  {
   Print("[ATRTS][ERROR] ",message);
  }

void LogDebug(const string message)
  {
   if(EnableDebugLog)
      Print("[ATRTS][DEBUG] ",message);
  }

string GlobalKey(const long identifier,const string field)
  {
   return(StringFormat("ATRTS_%I64d_%I64d_%s",
                       (long)AccountInfoInteger(ACCOUNT_LOGIN),identifier,field));
  }

void DeletePersistentState(const long identifier);

void PersistState(const PositionTrailState &state)
  {
   GlobalVariableSet(GlobalKey(state.identifier,"HIGH"),state.highest_bid);
   GlobalVariableSet(GlobalKey(state.identifier,"LOW"),state.lowest_ask);
   GlobalVariableSet(GlobalKey(state.identifier,"ACTATR"),state.activation_atr_reference);
   GlobalVariableSet(GlobalKey(state.identifier,"ACTPRICE"),state.activation_price);
   GlobalVariableSet(GlobalKey(state.identifier,"ACTIVE"),state.trailing_active ? 1.0 : 0.0);
   GlobalVariableSet(GlobalKey(state.identifier,"TYPE"),(double)state.type);
   GlobalVariableSet(GlobalKey(state.identifier,"OPENMSC"),(double)state.open_time_msc);
  }

bool RestoreState(PositionTrailState &state)
  {
   string high_key=GlobalKey(state.identifier,"HIGH");
   string low_key=GlobalKey(state.identifier,"LOW");
   string atr_key=GlobalKey(state.identifier,"ACTATR");
   string price_key=GlobalKey(state.identifier,"ACTPRICE");
   string active_key=GlobalKey(state.identifier,"ACTIVE");
   string type_key=GlobalKey(state.identifier,"TYPE");
   string open_msc_key=GlobalKey(state.identifier,"OPENMSC");

   if(!GlobalVariableCheck(high_key) || !GlobalVariableCheck(low_key) ||
      !GlobalVariableCheck(atr_key) || !GlobalVariableCheck(price_key) ||
      !GlobalVariableCheck(active_key) || !GlobalVariableCheck(type_key) ||
      !GlobalVariableCheck(open_msc_key))
      return(false);

   if((ENUM_POSITION_TYPE)(long)GlobalVariableGet(type_key)!=state.type ||
      (long)GlobalVariableGet(open_msc_key)!=state.open_time_msc)
     {
      DeletePersistentState(state.identifier);
      LogInfo(StringFormat("STATE_RESET identifier=%I64d reason=GENERATION_OR_DIRECTION_CHANGED",state.identifier));
      return(false);
     }

   state.highest_bid=GlobalVariableGet(high_key);
   state.lowest_ask=GlobalVariableGet(low_key);
   state.activation_atr_reference=GlobalVariableGet(atr_key);
   state.activation_price=GlobalVariableGet(price_key);
   state.trailing_active=(GlobalVariableGet(active_key)>0.5);
   return(state.activation_atr_reference>0.0 && state.activation_price>0.0);
  }

void DeletePersistentState(const long identifier)
  {
   GlobalVariableDel(GlobalKey(identifier,"HIGH"));
   GlobalVariableDel(GlobalKey(identifier,"LOW"));
   GlobalVariableDel(GlobalKey(identifier,"ACTATR"));
   GlobalVariableDel(GlobalKey(identifier,"ACTPRICE"));
   GlobalVariableDel(GlobalKey(identifier,"ACTIVE"));
   GlobalVariableDel(GlobalKey(identifier,"TYPE"));
   GlobalVariableDel(GlobalKey(identifier,"OPENMSC"));
  }

int FindAtrHandle(const string symbol)
  {
   for(int i=0;i<ArraySize(g_atr_handles);i++)
      if(g_atr_handles[i].symbol==symbol)
         return(i);
   return(-1);
  }

int EnsureAtrHandle(const string symbol)
  {
   int index=FindAtrHandle(symbol);
   if(index>=0)
      return(g_atr_handles[index].handle);

   ResetLastError();
   int handle=iATR(symbol,ATRTimeframe,ATRPeriod);
   if(handle==INVALID_HANDLE)
     {
      LogError(StringFormat("ATR_HANDLE_FAILED symbol=%s period=%d error=%d",symbol,ATRPeriod,GetLastError()));
      return(INVALID_HANDLE);
     }

   int new_index=ArraySize(g_atr_handles);
   ArrayResize(g_atr_handles,new_index+1);
   g_atr_handles[new_index].symbol=symbol;
   g_atr_handles[new_index].handle=handle;
   LogDebug(StringFormat("ATR_HANDLE_CREATED symbol=%s handle=%d",symbol,handle));
   return(handle);
  }

bool GetCurrentAtr(const string symbol,double &atr)
  {
   atr=0.0;
   int handle=EnsureAtrHandle(symbol);
   if(handle==INVALID_HANDLE)
      return(false);

   double buffer[];
   ArraySetAsSeries(buffer,true);
   ResetLastError();
   if(CopyBuffer(handle,0,0,1,buffer)!=1 || buffer[0]<=0.0)
     {
      LogDebug(StringFormat("SKIP_INVALID_ATR symbol=%s bars=%d error=%d",symbol,BarsCalculated(handle),GetLastError()));
      return(false);
     }
   atr=buffer[0];
   return(true);
  }

int FindStateByTicket(const ulong ticket)
  {
   for(int i=0;i<ArraySize(g_states);i++)
      if(g_states[i].ticket==ticket)
         return(i);
   return(-1);
  }

void RemoveStateAt(const int index)
  {
   int count=ArraySize(g_states);
   if(index<0 || index>=count)
      return;
   for(int i=index;i<count-1;i++)
      g_states[i]=g_states[i+1];
   ArrayResize(g_states,count-1);
  }

bool IsEligiblePosition(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return(false);

   string symbol=PositionGetString(POSITION_SYMBOL);
   if(ManageCurrentSymbolOnly && symbol!=_Symbol)
      return(false);

   long magic=PositionGetInteger(POSITION_MAGIC);
   if(!ManageManualTrades && magic==0)
      return(false);

   if(UseMagicNumberFilter && magic!=MagicNumber)
      return(false);

   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   return(type==POSITION_TYPE_BUY || type==POSITION_TYPE_SELL);
  }

void ReconstructWatermarks(PositionTrailState &state,const MqlTick &current_tick)
  {
   state.highest_bid=MathMax(state.open_price,current_tick.bid);
   state.lowest_ask=MathMin(state.open_price,current_tick.ask);

   MqlTick historical_ticks[];
   ulong from_msc=(ulong)state.open_time_msc;
   int copied=CopyTicksRange(state.symbol,historical_ticks,COPY_TICKS_INFO,from_msc,current_tick.time_msc);
   if(copied<=0)
     {
      LogDebug(StringFormat("STATE_HISTORY_UNAVAILABLE ticket=%I64u error=%d",state.ticket,GetLastError()));
      return;
     }

   for(int i=0;i<copied;i++)
     {
      if(historical_ticks[i].bid>0.0)
         state.highest_bid=MathMax(state.highest_bid,historical_ticks[i].bid);
      if(historical_ticks[i].ask>0.0)
         state.lowest_ask=MathMin(state.lowest_ask,historical_ticks[i].ask);
     }
  }

bool InitializeState(const ulong ticket,const MqlTick &tick,const double atr,PositionTrailState &state)
  {
   if(!PositionSelectByTicket(ticket))
      return(false);

   state.ticket=ticket;
   state.identifier=PositionGetInteger(POSITION_IDENTIFIER);
   state.symbol=PositionGetString(POSITION_SYMBOL);
   state.type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   state.open_time_msc=PositionGetInteger(POSITION_TIME_MSC);
   state.open_price=PositionGetDouble(POSITION_PRICE_OPEN);
   state.last_known_sl=PositionGetDouble(POSITION_SL);
   state.last_candidate_sl=0.0;
   state.last_modification_time=0;
   state.magic_number=PositionGetInteger(POSITION_MAGIC);
   state.last_retcode=0;
   state.modification_count=0;
   state.rejected_modification_count=0;

   if(RestoreState(state))
     {
      LogInfo(StringFormat("STATE_RESTORED ticket=%I64u identifier=%I64d symbol=%s",state.ticket,state.identifier,state.symbol));
      return(true);
     }

   state.activation_atr_reference=atr;
   state.activation_price=(state.type==POSITION_TYPE_BUY)
                          ? state.open_price+(atr*ActivationATR)
                          : state.open_price-(atr*ActivationATR);
   state.trailing_active=!UseActivationThreshold;
   ReconstructWatermarks(state,tick);
   PersistState(state);
   LogInfo(StringFormat("STATE_INITIALIZED ticket=%I64u identifier=%I64d symbol=%s high=%.10f low=%.10f activation=%.10f",
                        state.ticket,state.identifier,state.symbol,state.highest_bid,state.lowest_ask,state.activation_price));
   return(true);
  }

double NormalizeToTick(const double price,const double tick_size,const int digits,const bool round_down)
  {
   if(price<=0.0 || tick_size<=0.0)
      return(0.0);
   double ticks=price/tick_size;
   double normalized=(round_down ? MathFloor(ticks+1e-10) : MathCeil(ticks-1e-10))*tick_size;
   return(NormalizeDouble(normalized,digits));
  }

bool IsBetterStop(const PositionTrailState &state,const double candidate,const double current_sl,const double tick_size)
  {
   if(candidate<=0.0)
      return(false);
   if(current_sl==0.0)
      return(true);
   return(state.type==POSITION_TYPE_BUY ? candidate>current_sl : candidate<current_sl);
  }

void LogDecision(const string decision,const PositionTrailState &state,const MqlTick &tick,
                 const double atr,const double candidate,const double normalized_candidate,
                 const double minimum_step,const int stops_level,const int freeze_level,
                 const uint retcode)
  {
   if(!EnableDebugLog && (decision=="TRAILING_NOT_ACTIVATED" || decision=="NO_BETTER_SL" ||
                          decision=="SKIP_MIN_STEP" || decision=="SKIP_STOP_LEVEL" ||
                          decision=="SKIP_FREEZE_LEVEL" || decision=="SKIP_INVALID_ATR"))
      return;

   int digits=(int)SymbolInfoInteger(state.symbol,SYMBOL_DIGITS);
   double spread=tick.ask-tick.bid;
   PrintFormat("[ATRTS] %s ticket=%I64u id=%I64d symbol=%s type=%s open=%s bid=%s ask=%s spread=%s atr=%s mult=%.2f water=%s active=%s activation=%s sl=%s candidate=%s normalized=%s step=%s stops=%d freeze=%d retcode=%u",
               decision,state.ticket,state.identifier,state.symbol,PositionTypeText(state.type),
               DoubleToString(state.open_price,digits),DoubleToString(tick.bid,digits),DoubleToString(tick.ask,digits),
               DoubleToString(spread,digits),DoubleToString(atr,digits),ATRMultiplier,
               DoubleToString(state.type==POSITION_TYPE_BUY ? state.highest_bid : state.lowest_ask,digits),
               state.trailing_active ? "true" : "false",DoubleToString(state.activation_price,digits),
               DoubleToString(state.last_known_sl,digits),DoubleToString(candidate,digits),
               DoubleToString(normalized_candidate,digits),DoubleToString(minimum_step,digits),
               stops_level,freeze_level,retcode);
  }

bool ModifyStopLossByTicket(PositionTrailState &state,const double sl,const double tp,
                            const MqlTick &tick,const double atr,const double raw_candidate,
                            const double minimum_step,const int stops_level,const int freeze_level)
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action=TRADE_ACTION_SLTP;
   request.position=state.ticket;
   request.symbol=state.symbol;
   request.sl=sl;
   request.tp=tp;

   LogDecision("SL_MODIFY_SENT",state,tick,atr,raw_candidate,sl,minimum_step,stops_level,freeze_level,0);
   ResetLastError();
   bool sent=OrderSend(request,result);
   state.last_retcode=result.retcode;
   if(!sent)
     {
      state.rejected_modification_count++;
      LogError(StringFormat("SL_MODIFY_REJECTED ticket=%I64u local_error=%d retcode=%u comment=%s",
                            state.ticket,GetLastError(),result.retcode,result.comment));
      LogDecision("SL_MODIFY_REJECTED",state,tick,atr,raw_candidate,sl,minimum_step,stops_level,freeze_level,result.retcode);
      return(false);
     }

   if(result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_PLACED)
     {
      state.rejected_modification_count++;
      LogWarn(StringFormat("SL_MODIFY_REJECTED ticket=%I64u retcode=%u comment=%s",state.ticket,result.retcode,result.comment));
      LogDecision("SL_MODIFY_REJECTED",state,tick,atr,raw_candidate,sl,minimum_step,stops_level,freeze_level,result.retcode);
      return(false);
     }

   state.last_known_sl=sl;
   state.last_modification_time=TimeCurrent();
   state.modification_count++;
   LogInfo(StringFormat("SL_MODIFY_SUCCESS ticket=%I64u sl=%.10f tp=%.10f retcode=%u",state.ticket,sl,tp,result.retcode));
   LogDecision("SL_MODIFY_SUCCESS",state,tick,atr,raw_candidate,sl,minimum_step,stops_level,freeze_level,result.retcode);
   return(true);
  }

void ProcessState(PositionTrailState &state,const MqlTick &tick,const double atr)
  {
   if(!PositionSelectByTicket(state.ticket))
      return;

   state.last_known_sl=PositionGetDouble(POSITION_SL);
   double current_tp=PositionGetDouble(POSITION_TP);
   double tracking_price=(state.type==POSITION_TYPE_BUY ? tick.bid : tick.ask);
   bool water_changed=false;
   if(state.type==POSITION_TYPE_BUY && tracking_price>state.highest_bid)
     {
      state.highest_bid=tracking_price;
      water_changed=true;
     }
   if(state.type==POSITION_TYPE_SELL && tracking_price<state.lowest_ask)
     {
      state.lowest_ask=tracking_price;
      water_changed=true;
     }

   if(!state.trailing_active)
     {
      bool activate=(!UseActivationThreshold ||
                     (state.type==POSITION_TYPE_BUY && tick.bid>=state.activation_price) ||
                     (state.type==POSITION_TYPE_SELL && tick.ask<=state.activation_price));
      if(activate)
        {
         state.trailing_active=true;
         PersistState(state);
         LogDecision("TRAILING_ACTIVATED",state,tick,atr,0.0,0.0,0.0,0,0,0);
        }
      else
        {
         if(water_changed)
            PersistState(state);
         LogDecision("TRAILING_NOT_ACTIVATED",state,tick,atr,0.0,0.0,0.0,0,0,0);
         return;
        }
     }
   else if(water_changed)
      PersistState(state);

   double tick_size=SymbolInfoDouble(state.symbol,SYMBOL_TRADE_TICK_SIZE);
   double point=SymbolInfoDouble(state.symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(state.symbol,SYMBOL_DIGITS);
   if(tick_size<=0.0)
      tick_size=point;
   if(tick_size<=0.0)
     {
      LogWarn(StringFormat("SKIP_STOP_LEVEL ticket=%I64u invalid_tick_size",state.ticket));
      return;
     }

   double raw_candidate=(state.type==POSITION_TYPE_BUY)
                        ? state.highest_bid-(atr*ATRMultiplier)
                        : state.lowest_ask+(atr*ATRMultiplier);
   double candidate=NormalizeToTick(raw_candidate,tick_size,digits,state.type==POSITION_TYPE_BUY);
   state.last_candidate_sl=candidate;
   int stops_level=(int)SymbolInfoInteger(state.symbol,SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level=(int)SymbolInfoInteger(state.symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minimum_step=(UseMinimumTrailingStep ? atr*MinimumStepATR : 0.0);

   // Move the candidate only enough to satisfy stops level, and only if it remains protective.
   double stops_distance=stops_level*point;
   if(state.type==POSITION_TYPE_BUY)
     {
      double maximum_allowed=NormalizeToTick(tick.bid-stops_distance,tick_size,digits,true);
      if(candidate>maximum_allowed)
         candidate=maximum_allowed;
     }
   else
     {
      double minimum_allowed=NormalizeToTick(tick.ask+stops_distance,tick_size,digits,false);
      if(candidate<minimum_allowed)
         candidate=minimum_allowed;
     }

   if(!IsBetterStop(state,candidate,state.last_known_sl,tick_size))
     {
      LogDecision("NO_BETTER_SL",state,tick,atr,raw_candidate,candidate,minimum_step,stops_level,freeze_level,0);
      return;
     }

   if(state.last_known_sl!=0.0 && UseMinimumTrailingStep)
     {
      double improvement=(state.type==POSITION_TYPE_BUY ? candidate-state.last_known_sl : state.last_known_sl-candidate);
      if(improvement<minimum_step)
        {
         LogDecision("SKIP_MIN_STEP",state,tick,atr,raw_candidate,candidate,minimum_step,stops_level,freeze_level,0);
         return;
        }
     }

   if(state.last_modification_time>0 && TimeCurrent()-state.last_modification_time<MIN_MODIFICATION_INTERVAL_SECONDS)
     {
      LogDecision("SKIP_MIN_STEP",state,tick,atr,raw_candidate,candidate,minimum_step,stops_level,freeze_level,0);
      return;
     }

   // The adjusted candidate must still satisfy the broker stop distance before it is sent.
   bool violates_stop=(state.type==POSITION_TYPE_BUY ? tick.bid-candidate<stops_distance : candidate-tick.ask<stops_distance);
   if(candidate<=0.0 || violates_stop)
     {
      LogDecision("SKIP_STOP_LEVEL",state,tick,atr,raw_candidate,candidate,minimum_step,stops_level,freeze_level,0);
      return;
     }

   double freeze_distance=freeze_level*point;
   bool frozen=(state.type==POSITION_TYPE_BUY ? tick.bid-candidate<=freeze_distance : candidate-tick.ask<=freeze_distance);
   if(frozen)
     {
      LogDecision("SKIP_FREEZE_LEVEL",state,tick,atr,raw_candidate,candidate,minimum_step,stops_level,freeze_level,0);
      return;
     }

   // TRADE_ACTION_SLTP preserves current_tp exactly; no TP creation or removal occurs here.
   ModifyStopLossByTicket(state,candidate,current_tp,tick,atr,raw_candidate,minimum_step,stops_level,freeze_level);
  }

void ProcessPosition(const ulong ticket)
  {
   if(!IsEligiblePosition(ticket) || !PositionSelectByTicket(ticket))
      return;

   string symbol=PositionGetString(POSITION_SYMBOL);
   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick) || tick.bid<=0.0 || tick.ask<=0.0)
     {
      LogDebug(StringFormat("SKIP_NO_TICK ticket=%I64u symbol=%s",ticket,symbol));
      return;
     }

   double atr=0.0;
   if(!GetCurrentAtr(symbol,atr))
     {
      PositionTrailState temporary_state;
      ZeroMemory(temporary_state);
      temporary_state.ticket=ticket;
      temporary_state.identifier=PositionGetInteger(POSITION_IDENTIFIER);
      temporary_state.symbol=symbol;
      temporary_state.type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      temporary_state.open_price=PositionGetDouble(POSITION_PRICE_OPEN);
      temporary_state.last_known_sl=PositionGetDouble(POSITION_SL);
      LogDecision("SKIP_INVALID_ATR",temporary_state,tick,0.0,0.0,0.0,0.0,0,0,0);
      return;
     }

   int index=FindStateByTicket(ticket);
   ENUM_POSITION_TYPE position_type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   long position_open_time_msc=PositionGetInteger(POSITION_TIME_MSC);
   if(index>=0 && (g_states[index].type!=position_type ||
                   g_states[index].open_time_msc!=position_open_time_msc))
     {
      DeletePersistentState(g_states[index].identifier);
      LogInfo(StringFormat("STATE_RESET ticket=%I64u identifier=%I64d reason=GENERATION_OR_DIRECTION_CHANGED",g_states[index].ticket,g_states[index].identifier));
      RemoveStateAt(index);
      index=-1;
     }

   if(index<0)
     {
      PositionTrailState new_state;
      ZeroMemory(new_state);
      if(!InitializeState(ticket,tick,atr,new_state))
         return;
      index=ArraySize(g_states);
      ArrayResize(g_states,index+1);
      g_states[index]=new_state;
      LogInfo(StringFormat("POSITION_DISCOVERED ticket=%I64u identifier=%I64d symbol=%s",new_state.ticket,new_state.identifier,new_state.symbol));
     }

   PositionTrailState state=g_states[index];
   ProcessState(state,tick,atr);
   g_states[index]=state;
  }

bool HasOpenPositionIdentifier(const long identifier)
  {
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket!=0 && PositionGetInteger(POSITION_IDENTIFIER)==identifier)
         return(true);
     }
   return(false);
  }

void CleanupOrphanedPersistentStates(void)
  {
   string prefix=StringFormat("ATRTS_%I64d_",(long)AccountInfoInteger(ACCOUNT_LOGIN));
   int prefix_length=StringLen(prefix);
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
     {
      string key=GlobalVariableName(i);
      if(StringFind(key,prefix)!=0 || StringFind(key,"_HIGH")!=StringLen(key)-5)
         continue;

      string identifier_text=StringSubstr(key,prefix_length,StringLen(key)-prefix_length-5);
      long identifier=(long)StringToInteger(identifier_text);
      if(identifier<=0 || HasOpenPositionIdentifier(identifier))
         continue;

      DeletePersistentState(identifier);
      LogInfo(StringFormat("STATE_CLEANUP identifier=%I64d reason=ORPHANED_PERSISTENCE",identifier));
     }
  }

void CleanupClosedStates(void)
  {
   for(int i=ArraySize(g_states)-1;i>=0;i--)
     {
      if(PositionSelectByTicket(g_states[i].ticket))
         continue;
      LogInfo(StringFormat("POSITION_CLOSED ticket=%I64u identifier=%I64d",g_states[i].ticket,g_states[i].identifier));
      if(!HasOpenPositionIdentifier(g_states[i].identifier))
        {
         DeletePersistentState(g_states[i].identifier);
         LogInfo(StringFormat("STATE_CLEANUP ticket=%I64u identifier=%I64d",g_states[i].ticket,g_states[i].identifier));
        }
      else
         LogInfo(StringFormat("STATE_MEMORY_CLEANUP ticket=%I64u identifier=%I64d reason=IDENTIFIER_STILL_OPEN",g_states[i].ticket,g_states[i].identifier));
      RemoveStateAt(i);
     }
  }

void ProcessAllPositions(void)
  {
   int total=PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket!=0)
         ProcessPosition(ticket);
     }
   CleanupClosedStates();
  }

int OnInit(void)
  {
   if(ATRPeriod<=0 || ATRMultiplier<=0.0 || ActivationATR<0.0 || MinimumStepATR<0.0)
     {
      LogError("Invalid inputs: ATRPeriod and ATRMultiplier must be positive; ActivationATR and MinimumStepATR cannot be negative.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(EnsureAtrHandle(_Symbol)==INVALID_HANDLE)
      return(INIT_FAILED);

   CleanupOrphanedPersistentStates();
   LogInfo(StringFormat("INITIALIZED version=v1-beta.0 chart_symbol=%s atr_period=%d atr_timeframe=%d",_Symbol,ATRPeriod,ATRTimeframe));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   for(int i=0;i<ArraySize(g_atr_handles);i++)
      if(g_atr_handles[i].handle!=INVALID_HANDLE)
         IndicatorRelease(g_atr_handles[i].handle);
   ArrayResize(g_atr_handles,0);
   LogInfo(StringFormat("DEINITIALIZED reason=%d",reason));
  }

void OnTick(void)
  {
   ProcessAllPositions();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   // Closed positions are removed promptly; newly opened positions are initialized on the next tick.
   CleanupClosedStates();
  }
