//+------------------------------------------------------------------+
//| Product: ATR Trailing Stop Manager EA                           |
//| Version: v1 Beta R1                                             |
//| Purpose: Research/demo ATR-based trailing stop manager.         |
//| Baseline: Current-price ATR trailing with configurable shift.   |
//| Experimental: Favorable extrema and minimum trailing step.      |
//| Trading entry: None. Primary validation: Tester + HFM Demo.     |
//| Live-money deployment: Outside the scope of this version.       |
//+------------------------------------------------------------------+
#property version   "1.10"
#property description "Evidence-grounded ATR trailing manager. It never opens positions."

const int MIN_MODIFICATION_INTERVAL_SECONDS=1;

enum TrailingAnchorMode
  {
   ANCHOR_CURRENT_PRICE=0,
   ANCHOR_FAVORABLE_EXTREME=1
  };

enum ActivationMode
  {
   ACTIVATION_OFF=0,
   ACTIVATION_ATR=1,
   ACTIVATION_POINTS=2
  };

enum ApplyDirection
  {
   APPLY_BUY_AND_SELL=0,
   APPLY_BUY_ONLY=1,
   APPLY_SELL_ONLY=2
  };

input group "ATR Settings"
input int             ATRPeriod=14;
input ENUM_TIMEFRAMES ATRTimeframe=PERIOD_CURRENT;
input int             ATRShift=1;
input double          ATRMultiplier=1.0;

input group "Trailing Model"
input TrailingAnchorMode TrailingAnchor=ANCHOR_CURRENT_PRICE;

input group "Activation"
input ActivationMode  Activation=ACTIVATION_OFF;
input double          ActivationATR=1.0;
input int             ActivationPoints=0;

input group "Experimental Trailing Step"
input bool            UseMinimumTrailingStep=false;
input double          MinimumStepATR=0.10;

input group "Position Filters"
input bool            ManageCurrentSymbolOnly=true;
input ApplyDirection  ApplyToDirection=APPLY_BUY_AND_SELL;
input bool            ManageManualTrades=true;
input bool            UseMagicNumberFilter=false;
input long            MagicNumber=0;
input bool            UseCommentFilter=false;
input string          CommentFilter="";

input group "Diagnostics"
input bool            EnableDebugLog=true;

struct PositionTrailState
  {
   ulong              ticket;
   long               identifier;
   string             symbol;
   ENUM_POSITION_TYPE type;
   long               open_time_msc;
   double             open_price;
   bool               trailing_active;
   double             highest_bid;
   double             lowest_ask;
   double             last_known_sl;
   double             last_candidate_sl;
   double             last_atr;
   double             last_activation_price;
   datetime           last_modification_time;
   uint               modification_count;
   uint               rejected_modification_count;
   uint               last_retcode;
   bool               restored_from_persistence;
   string             last_decision;
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
   return(type==POSITION_TYPE_BUY ? "BUY" : "SELL");
  }

string AnchorModeText(void)
  {
   return(TrailingAnchor==ANCHOR_CURRENT_PRICE ? "CURRENT_PRICE" : "FAVORABLE_EXTREME");
  }

string ActivationModeText(void)
  {
   if(Activation==ACTIVATION_ATR)
      return("ATR");
   if(Activation==ACTIVATION_POINTS)
      return("POINTS");
   return("OFF");
  }

void LogInfo(const string message)  { Print("[ATRTS][INFO] ",message); }
void LogWarn(const string message)  { Print("[ATRTS][WARN] ",message); }
void LogError(const string message) { Print("[ATRTS][ERROR] ",message); }
void LogDebug(const string message)
  {
   if(EnableDebugLog)
      Print("[ATRTS][DEBUG] ",message);
  }

string GlobalKey(const long identifier,const string field)
  {
   return(StringFormat("ATRTS1_%I64d_%I64d_%s",(long)AccountInfoInteger(ACCOUNT_LOGIN),identifier,field));
  }

void DeletePersistentState(const long identifier)
  {
   GlobalVariableDel(GlobalKey(identifier,"H"));
   GlobalVariableDel(GlobalKey(identifier,"L"));
   GlobalVariableDel(GlobalKey(identifier,"A"));
   GlobalVariableDel(GlobalKey(identifier,"T"));
   GlobalVariableDel(GlobalKey(identifier,"O"));
  }

void PersistActivationState(const PositionTrailState &state)
  {
   GlobalVariableSet(GlobalKey(state.identifier,"A"),state.trailing_active ? 1.0 : 0.0);
   GlobalVariableSet(GlobalKey(state.identifier,"T"),(double)state.type);
   GlobalVariableSet(GlobalKey(state.identifier,"O"),(double)state.open_time_msc);
  }

void PersistExperimentalState(const PositionTrailState &state)
  {
   PersistActivationState(state);
   GlobalVariableSet(GlobalKey(state.identifier,"H"),state.highest_bid);
   GlobalVariableSet(GlobalKey(state.identifier,"L"),state.lowest_ask);
  }

bool IsPersistentGenerationValid(const PositionTrailState &state)
  {
   string type_key=GlobalKey(state.identifier,"T");
   string open_key=GlobalKey(state.identifier,"O");
   if(!GlobalVariableCheck(type_key) || !GlobalVariableCheck(open_key))
      return(false);
   if((ENUM_POSITION_TYPE)(long)GlobalVariableGet(type_key)==state.type &&
      (long)GlobalVariableGet(open_key)==state.open_time_msc)
      return(true);
   DeletePersistentState(state.identifier);
   LogInfo(StringFormat("STATE_RESET identifier=%I64d reason=GENERATION_OR_DIRECTION_CHANGED",state.identifier));
   return(false);
  }

bool RestoreActivationState(PositionTrailState &state)
  {
   if(!IsPersistentGenerationValid(state) || !GlobalVariableCheck(GlobalKey(state.identifier,"A")))
      return(false);
   state.trailing_active=(GlobalVariableGet(GlobalKey(state.identifier,"A"))>0.5);
   return(true);
  }

bool RestoreExperimentalState(PositionTrailState &state)
  {
   if(!RestoreActivationState(state) || !GlobalVariableCheck(GlobalKey(state.identifier,"H")) ||
      !GlobalVariableCheck(GlobalKey(state.identifier,"L")))
      return(false);
   state.highest_bid=GlobalVariableGet(GlobalKey(state.identifier,"H"));
   state.lowest_ask=GlobalVariableGet(GlobalKey(state.identifier,"L"));
   return(state.highest_bid>0.0 && state.lowest_ask>0.0);
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
      LogError(StringFormat("ATR_HANDLE_FAILED symbol=%s period=%d timeframe=%d error=%d",symbol,ATRPeriod,ATRTimeframe,GetLastError()));
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
   if(CopyBuffer(handle,0,ATRShift,1,buffer)!=1 || buffer[0]<=0.0 || !MathIsValidNumber(buffer[0]))
     {
      LogDebug(StringFormat("SKIP_INVALID_ATR symbol=%s shift=%d bars=%d error=%d",symbol,ATRShift,BarsCalculated(handle),GetLastError()));
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

   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(type!=POSITION_TYPE_BUY && type!=POSITION_TYPE_SELL)
      return(false);
   if(ApplyToDirection==APPLY_BUY_ONLY && type!=POSITION_TYPE_BUY)
      return(false);
   if(ApplyToDirection==APPLY_SELL_ONLY && type!=POSITION_TYPE_SELL)
      return(false);

   long magic=PositionGetInteger(POSITION_MAGIC);
   if(!ManageManualTrades && magic==0)
      return(false);
   if(UseMagicNumberFilter && magic!=MagicNumber)
      return(false);

   if(UseCommentFilter && StringFind(PositionGetString(POSITION_COMMENT),CommentFilter)<0)
      return(false);
   return(true);
  }

void ReconstructWatermarks(PositionTrailState &state,const MqlTick &current_tick)
  {
   state.highest_bid=MathMax(state.open_price,current_tick.bid);
   state.lowest_ask=MathMin(state.open_price,current_tick.ask);

   MqlTick historical_ticks[];
   ResetLastError();
   int copied=CopyTicksRange(state.symbol,historical_ticks,COPY_TICKS_INFO,(ulong)state.open_time_msc,current_tick.time_msc);
   if(copied<=0)
     {
      LogInfo(StringFormat("STATE_DEGRADED_REINIT ticket=%I64u reason=HISTORY_UNAVAILABLE error=%d",state.ticket,GetLastError()));
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

bool InitializeState(const ulong ticket,const MqlTick &tick,PositionTrailState &state)
  {
   if(!PositionSelectByTicket(ticket))
      return(false);

   ZeroMemory(state);
   state.ticket=ticket;
   state.identifier=PositionGetInteger(POSITION_IDENTIFIER);
   state.symbol=PositionGetString(POSITION_SYMBOL);
   state.type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   state.open_time_msc=PositionGetInteger(POSITION_TIME_MSC);
   state.open_price=PositionGetDouble(POSITION_PRICE_OPEN);
   state.last_known_sl=PositionGetDouble(POSITION_SL);

   if(TrailingAnchor==ANCHOR_FAVORABLE_EXTREME && RestoreExperimentalState(state))
     {
      state.restored_from_persistence=true;
      LogInfo(StringFormat("STATE_RESTORED ticket=%I64u identifier=%I64d anchor=%s",state.ticket,state.identifier,AnchorModeText()));
     }
   else
     {
      if(TrailingAnchor==ANCHOR_FAVORABLE_EXTREME)
         ReconstructWatermarks(state,tick);
      else
         RestoreActivationState(state);
      if(Activation==ACTIVATION_OFF)
         state.trailing_active=true;
      if(TrailingAnchor==ANCHOR_FAVORABLE_EXTREME)
         PersistExperimentalState(state);
      else
         PersistActivationState(state);
      LogInfo(StringFormat("STATE_INITIALIZED ticket=%I64u identifier=%I64d anchor=%s",state.ticket,state.identifier,AnchorModeText()));
     }
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

bool IsBetterStop(const PositionTrailState &state,const double candidate,const double current_sl)
  {
   if(candidate<=0.0)
      return(false);
   if(current_sl==0.0)
      return(true);
   return(state.type==POSITION_TYPE_BUY ? candidate>current_sl : candidate<current_sl);
  }

void LogDecision(const string decision,PositionTrailState &state,const MqlTick &tick,const double atr,
                 const double anchor,const double raw_candidate,const double normalized_candidate,
                 const double minimum_step,const double tick_size,const double point,
                 const int stops_level,const int freeze_level,const uint retcode,const string detail="")
  {
   bool repeat=(state.last_decision==decision);
   state.last_decision=decision;
   if(!EnableDebugLog && (decision=="TRAILING_NOT_ACTIVATED" || decision=="NO_BETTER_SL" ||
      decision=="SKIP_MIN_STEP" || decision=="SKIP_MODIFICATION_INTERVAL" || decision=="SKIP_STOP_LEVEL" || decision=="SKIP_FREEZE_LEVEL" ||
      decision=="SKIP_INVALID_ATR" || decision=="SKIP_INVALID_TICK" || decision=="SKIP_INVALID_PRICE"))
      return;
   if(repeat && (decision=="TRAILING_NOT_ACTIVATED" || decision=="NO_BETTER_SL" || decision=="SKIP_MIN_STEP" ||
      decision=="SKIP_MODIFICATION_INTERVAL" || decision=="SKIP_STOP_LEVEL" || decision=="SKIP_FREEZE_LEVEL" || decision=="SKIP_INVALID_ATR"))
      return;

   int digits=(int)SymbolInfoInteger(state.symbol,SYMBOL_DIGITS);
   PrintFormat("[ATRTS] %s ticket=%I64u id=%I64d symbol=%s type=%s anchor_mode=%s activation_mode=%s open=%s bid=%s ask=%s spread=%s atr=%s atr_shift=%d mult=%.2f anchor=%s high=%s low=%s active=%s activation=%s sl=%s raw=%s normalized=%s step=%s tick_size=%s point=%s stops=%d freeze=%d retcode=%u detail=%s",
               decision,state.ticket,state.identifier,state.symbol,PositionTypeText(state.type),AnchorModeText(),ActivationModeText(),
               DoubleToString(state.open_price,digits),DoubleToString(tick.bid,digits),DoubleToString(tick.ask,digits),DoubleToString(tick.ask-tick.bid,digits),
               DoubleToString(atr,digits),ATRShift,ATRMultiplier,DoubleToString(anchor,digits),DoubleToString(state.highest_bid,digits),
               DoubleToString(state.lowest_ask,digits),state.trailing_active ? "true" : "false",DoubleToString(state.last_activation_price,digits),
               DoubleToString(state.last_known_sl,digits),DoubleToString(raw_candidate,digits),DoubleToString(normalized_candidate,digits),
               DoubleToString(minimum_step,digits),DoubleToString(tick_size,digits),DoubleToString(point,digits),stops_level,freeze_level,retcode,detail);
  }

bool CheckTradePermissions(PositionTrailState &state,const MqlTick &tick,const double atr)
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      LogDecision("AUTOTRADING_DISABLED_TERMINAL",state,tick,atr,0.0,0.0,0.0,0.0,0.0,0.0,0,0,0);
      return(false);
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      LogDecision("AUTOTRADING_DISABLED_PROGRAM",state,tick,atr,0.0,0.0,0.0,0.0,0.0,0.0,0,0,0);
      return(false);
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      LogDecision("ACCOUNT_TRADE_NOT_ALLOWED",state,tick,atr,0.0,0.0,0.0,0.0,0.0,0.0,0,0,0);
      return(false);
     }
   if(SymbolInfoInteger(state.symbol,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED)
     {
      LogDecision("SYMBOL_TRADE_DISABLED",state,tick,atr,0.0,0.0,0.0,0.0,0.0,0.0,0,0,0);
      return(false);
     }
   return(true);
  }

bool ModifyStopLossByTicket(PositionTrailState &state,const double sl,const MqlTick &tick,const double atr,
                            const double anchor,const double raw_candidate,const double minimum_step,
                            const double tick_size,const double point,const int stops_level,const int freeze_level)
  {
   if(!PositionSelectByTicket(state.ticket))
     {
      LogDecision("SKIP_POSITION_GONE",state,tick,atr,anchor,raw_candidate,sl,minimum_step,tick_size,point,stops_level,freeze_level,0);
      return(false);
     }

   double current_sl=PositionGetDouble(POSITION_SL);
   double current_tp=PositionGetDouble(POSITION_TP);
   if(!IsBetterStop(state,sl,current_sl))
     {
      state.last_known_sl=current_sl;
      LogDecision("NO_BETTER_SL",state,tick,atr,anchor,raw_candidate,sl,minimum_step,tick_size,point,stops_level,freeze_level,0);
      return(false);
     }
   if(!CheckTradePermissions(state,tick,atr))
      return(false);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action=TRADE_ACTION_SLTP;
   request.position=state.ticket;
   request.symbol=state.symbol;
   request.sl=sl;
   request.tp=current_tp;

   LogDecision("SL_MODIFY_SENT",state,tick,atr,anchor,raw_candidate,sl,minimum_step,tick_size,point,stops_level,freeze_level,0);
   ResetLastError();
   bool sent=OrderSend(request,result);
   state.last_retcode=result.retcode;
   if(!sent || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_PLACED))
     {
      state.rejected_modification_count++;
      string detail=StringFormat("local=%s error=%d retcode_description=%s",sent ? "true" : "false",GetLastError(),result.comment);
      LogWarn(StringFormat("SL_MODIFY_REJECTED ticket=%I64u retcode=%u %s",state.ticket,result.retcode,detail));
      LogDecision("SL_MODIFY_REJECTED",state,tick,atr,anchor,raw_candidate,sl,minimum_step,tick_size,point,stops_level,freeze_level,result.retcode,detail);
      return(false);
     }

   state.last_known_sl=sl;
   state.last_modification_time=TimeCurrent();
   state.modification_count++;
   string success_detail=StringFormat("local=true retcode_description=%s",result.comment);
   LogInfo(StringFormat("SL_MODIFY_SUCCESS ticket=%I64u sl=%.10f tp=%.10f retcode=%u %s",state.ticket,sl,current_tp,result.retcode,success_detail));
   LogDecision("SL_MODIFY_SUCCESS",state,tick,atr,anchor,raw_candidate,sl,minimum_step,tick_size,point,stops_level,freeze_level,result.retcode,success_detail);
   return(true);
  }

void ProcessState(PositionTrailState &state,const MqlTick &tick,const double atr)
  {
   if(!PositionSelectByTicket(state.ticket))
     {
      LogDecision("SKIP_POSITION_GONE",state,tick,atr,0.0,0.0,0.0,0.0,0.0,0.0,0,0,0);
      return;
     }

   state.last_known_sl=PositionGetDouble(POSITION_SL);
   state.last_atr=atr;
   double point=SymbolInfoDouble(state.symbol,SYMBOL_POINT);
   double tick_size=SymbolInfoDouble(state.symbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(state.symbol,SYMBOL_DIGITS);
   if(point<=0.0 || tick_size<=0.0)
     {
      LogDecision("SKIP_INVALID_PRICE",state,tick,atr,0.0,0.0,0.0,0.0,tick_size,point,0,0,0);
      return;
     }

   double tracking_price=(state.type==POSITION_TYPE_BUY ? tick.bid : tick.ask);
   if(tracking_price<=0.0 || !MathIsValidNumber(tracking_price))
     {
      LogDecision("SKIP_INVALID_TICK",state,tick,atr,0.0,0.0,0.0,0.0,tick_size,point,0,0,0);
      return;
     }

   bool watermark_changed=false;
   if(TrailingAnchor==ANCHOR_FAVORABLE_EXTREME)
     {
      if(state.type==POSITION_TYPE_BUY && tracking_price>state.highest_bid)
        {
         state.highest_bid=tracking_price;
         watermark_changed=true;
        }
      if(state.type==POSITION_TYPE_SELL && tracking_price<state.lowest_ask)
        {
         state.lowest_ask=tracking_price;
         watermark_changed=true;
        }
      if(watermark_changed)
         PersistExperimentalState(state);
     }

   if(!state.trailing_active)
     {
      if(Activation==ACTIVATION_OFF)
         state.trailing_active=true;
      else if(Activation==ACTIVATION_ATR)
         state.last_activation_price=(state.type==POSITION_TYPE_BUY ? state.open_price+atr*ActivationATR : state.open_price-atr*ActivationATR);
      else
         state.last_activation_price=(state.type==POSITION_TYPE_BUY ? state.open_price+ActivationPoints*point : state.open_price-ActivationPoints*point);

      bool activate=(Activation==ACTIVATION_OFF ||
                     (state.type==POSITION_TYPE_BUY && tick.bid>=state.last_activation_price) ||
                     (state.type==POSITION_TYPE_SELL && tick.ask<=state.last_activation_price));
      if(!activate)
        {
         LogDecision("TRAILING_NOT_ACTIVATED",state,tick,atr,0.0,0.0,0.0,0.0,tick_size,point,0,0,0);
         return;
        }
      state.trailing_active=true;
      if(TrailingAnchor==ANCHOR_FAVORABLE_EXTREME)
         PersistExperimentalState(state);
      else
         PersistActivationState(state);
      LogDecision("TRAILING_ACTIVATED",state,tick,atr,0.0,0.0,0.0,0.0,tick_size,point,0,0,0);
     }

   double anchor=(TrailingAnchor==ANCHOR_CURRENT_PRICE ? tracking_price :
                  (state.type==POSITION_TYPE_BUY ? state.highest_bid : state.lowest_ask));
   double raw_candidate=(state.type==POSITION_TYPE_BUY ? anchor-atr*ATRMultiplier : anchor+atr*ATRMultiplier);
   double candidate=NormalizeToTick(raw_candidate,tick_size,digits,state.type==POSITION_TYPE_BUY);
   state.last_candidate_sl=candidate;
   int stops_level=(int)SymbolInfoInteger(state.symbol,SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level=(int)SymbolInfoInteger(state.symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minimum_step=(UseMinimumTrailingStep ? atr*MinimumStepATR : 0.0);
   double stops_distance=stops_level*point;
   bool restored_candidate_invalid=(state.restored_from_persistence && TrailingAnchor==ANCHOR_FAVORABLE_EXTREME &&
                                    (state.type==POSITION_TYPE_BUY ? tick.bid-candidate<stops_distance : candidate-tick.ask<stops_distance));
   if(restored_candidate_invalid)
      LogDecision("STATE_RESTORED_CANDIDATE_INVALID",state,tick,atr,anchor,raw_candidate,candidate,minimum_step,tick_size,point,stops_level,freeze_level,0,
                  "candidate_revalidated_against_current_market");

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

   if(!IsBetterStop(state,candidate,state.last_known_sl))
     {
      LogDecision("NO_BETTER_SL",state,tick,atr,anchor,raw_candidate,candidate,minimum_step,tick_size,point,stops_level,freeze_level,0);
      return;
     }
   if(state.last_known_sl!=0.0 && UseMinimumTrailingStep)
     {
      double improvement=(state.type==POSITION_TYPE_BUY ? candidate-state.last_known_sl : state.last_known_sl-candidate);
      if(improvement<minimum_step)
        {
         LogDecision("SKIP_MIN_STEP",state,tick,atr,anchor,raw_candidate,candidate,minimum_step,tick_size,point,stops_level,freeze_level,0);
         return;
        }
     }
   if(state.last_modification_time>0 && TimeCurrent()-state.last_modification_time<MIN_MODIFICATION_INTERVAL_SECONDS)
     {
      LogDecision("SKIP_MODIFICATION_INTERVAL",state,tick,atr,anchor,raw_candidate,candidate,minimum_step,tick_size,point,stops_level,freeze_level,0);
      return;
     }

   bool violates_stop=(state.type==POSITION_TYPE_BUY ? tick.bid-candidate<stops_distance : candidate-tick.ask<stops_distance);
   if(candidate<=0.0 || violates_stop)
     {
      string decision=(state.restored_from_persistence && TrailingAnchor==ANCHOR_FAVORABLE_EXTREME ?
                       "STATE_RESTORED_CANDIDATE_INVALID" : "SKIP_STOP_LEVEL");
      LogDecision(decision,state,tick,atr,anchor,raw_candidate,candidate,minimum_step,tick_size,point,stops_level,freeze_level,0);
      return;
     }
   double freeze_distance=freeze_level*point;
   bool frozen=(state.type==POSITION_TYPE_BUY ? tick.bid-candidate<=freeze_distance : candidate-tick.ask<=freeze_distance);
   if(frozen)
     {
      LogDecision("SKIP_FREEZE_LEVEL",state,tick,atr,anchor,raw_candidate,candidate,minimum_step,tick_size,point,stops_level,freeze_level,0);
      return;
     }

   ModifyStopLossByTicket(state,candidate,tick,atr,anchor,raw_candidate,minimum_step,tick_size,point,stops_level,freeze_level);
  }

void ProcessPosition(const ulong ticket)
  {
   if(!IsEligiblePosition(ticket) || !PositionSelectByTicket(ticket))
      return;

   string symbol=PositionGetString(POSITION_SYMBOL);
   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick) || tick.bid<=0.0 || tick.ask<=0.0)
     {
      LogDebug(StringFormat("SKIP_INVALID_TICK ticket=%I64u symbol=%s",ticket,symbol));
      return;
     }

   double atr=0.0;
   if(!GetCurrentAtr(symbol,atr))
     {
      PositionTrailState temporary;
      ZeroMemory(temporary);
      temporary.ticket=ticket;
      temporary.identifier=PositionGetInteger(POSITION_IDENTIFIER);
      temporary.symbol=symbol;
      temporary.type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      temporary.open_price=PositionGetDouble(POSITION_PRICE_OPEN);
      LogDecision("SKIP_INVALID_ATR",temporary,tick,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0,0,0);
      return;
     }

   int index=FindStateByTicket(ticket);
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   long open_time_msc=PositionGetInteger(POSITION_TIME_MSC);
   if(index>=0 && (g_states[index].type!=type || g_states[index].open_time_msc!=open_time_msc))
     {
      DeletePersistentState(g_states[index].identifier);
      LogInfo(StringFormat("STATE_RESET ticket=%I64u identifier=%I64d reason=GENERATION_OR_DIRECTION_CHANGED",g_states[index].ticket,g_states[index].identifier));
      RemoveStateAt(index);
      index=-1;
     }
   if(index<0)
     {
      PositionTrailState state;
      if(!InitializeState(ticket,tick,state))
         return;
      index=ArraySize(g_states);
      ArrayResize(g_states,index+1);
      g_states[index]=state;
      LogInfo(StringFormat("POSITION_DISCOVERED ticket=%I64u identifier=%I64d symbol=%s",state.ticket,state.identifier,state.symbol));
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
   string prefix=StringFormat("ATRTS1_%I64d_",(long)AccountInfoInteger(ACCOUNT_LOGIN));
   int prefix_length=StringLen(prefix);
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
     {
      string key=GlobalVariableName(i);
      if(StringFind(key,prefix)!=0 || StringFind(key,"_T")!=StringLen(key)-2)
         continue;
      string identifier_text=StringSubstr(key,prefix_length,StringLen(key)-prefix_length-2);
      long identifier=(long)StringToInteger(identifier_text);
      if(identifier>0 && !HasOpenPositionIdentifier(identifier))
        {
         DeletePersistentState(identifier);
         LogInfo(StringFormat("STATE_CLEANUP identifier=%I64d reason=ORPHANED_PERSISTENCE",identifier));
        }
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
      RemoveStateAt(i);
     }
  }

void ProcessAllPositions(void)
  {
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket!=0)
         ProcessPosition(ticket);
     }
   CleanupClosedStates();
  }

int OnInit(void)
  {
   if(ATRPeriod<=0 || ATRShift<0 || ATRMultiplier<=0.0 || ActivationATR<0.0 || ActivationPoints<0 || MinimumStepATR<0.0 ||
      TrailingAnchor<ANCHOR_CURRENT_PRICE || TrailingAnchor>ANCHOR_FAVORABLE_EXTREME ||
      Activation<ACTIVATION_OFF || Activation>ACTIVATION_POINTS ||
      ApplyToDirection<APPLY_BUY_AND_SELL || ApplyToDirection>APPLY_SELL_ONLY ||
      (UseCommentFilter && StringLen(CommentFilter)==0))
     {
      LogError("Invalid inputs: check ATR, activation, step, and comment-filter values.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(EnsureAtrHandle(_Symbol)==INVALID_HANDLE)
      return(INIT_FAILED);
   CleanupOrphanedPersistentStates();
   LogInfo(StringFormat("INITIALIZED version=v1-beta-r1.0 chart_symbol=%s period=%d shift=%d anchor=%s activation=%s",_Symbol,ATRPeriod,ATRShift,AnchorModeText(),ActivationModeText()));
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

void OnTick(void) { ProcessAllPositions(); }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   // Transaction order is not guaranteed. Reconcile cached state now; the next tick evaluates with fresh market data.
   CleanupClosedStates();
   if(trans.position==0)
      return;

   int index=FindStateByTicket(trans.position);
   if(index<0 || !PositionSelectByTicket(trans.position))
      return;

   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   long open_time_msc=PositionGetInteger(POSITION_TIME_MSC);
   if(g_states[index].type!=type || g_states[index].open_time_msc!=open_time_msc)
     {
      DeletePersistentState(g_states[index].identifier);
      LogInfo(StringFormat("STATE_RESET ticket=%I64u identifier=%I64d reason=TRADE_TRANSACTION_GENERATION_CHANGED",g_states[index].ticket,g_states[index].identifier));
      RemoveStateAt(index);
      return;
     }

   // External SL/TP changes are re-read before every request; update the cached diagnostic value immediately too.
   g_states[index].last_known_sl=PositionGetDouble(POSITION_SL);
  }
