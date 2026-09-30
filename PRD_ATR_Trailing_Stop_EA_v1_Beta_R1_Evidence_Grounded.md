# PRD — ATR Trailing Stop Manager EA v1 Beta R1 (Evidence-Grounded)

**Product Name:** ATR Trailing Stop Manager EA  
**Version:** v1 Beta R1  
**Platform:** MetaTrader 5  
**Language:** MQL5  
**Primary Broker for Validation:** HFM Demo MT5  
**Primary Development OS:** Windows  
**Secondary Research OS:** CachyOS / Linux  
**Primary Markets:** EURUSD, GBPUSD, USDJPY, NAS100/US100/USTEC (broker symbol dependent)  
**Status:** Ready for implementation — benchmark-first revision  
**Intended Use:** Research, controlled backtesting, and demo-account forward testing only  
**Revision Basis:** EarnForex ATR Trailing Stop v1.09 + MetaQuotes MQL5 platform documentation  

---

# 0. Evidence and Design Policy

This revision changes the development rule from **feature-first** to **benchmark-first**.

The EA must distinguish between:

## Tier A — Observed in a Mature Public ATR Trailing Implementation

Features documented in EarnForex ATR Trailing Stop v1.09 or its published changelog/forum history.

Examples:

- ATR period and multiplier configuration,
- ATR value shift with `Shift = 1` recommended,
- current-price ATR trailing,
- activation threshold in ATR multiples,
- activation threshold in points,
- symbol filtering,
- BUY/SELL filtering,
- Magic Number filtering,
- comment filtering,
- multi-symbol management,
- tick-size-aware price calculation,
- support for positions with no initial SL,
- large-ticket handling fixes,
- explicit diagnostics for disabled autotrading.

These features may be used as baseline behavior because they have implementation history and reported real-world edge cases.

## Tier B — Required by Official MQL5 Platform Semantics

Features required by MetaQuotes documentation.

Examples:

- position tickets use `ulong`,
- hedging accounts can contain multiple positions for one symbol,
- modify by **ticket**, not merely symbol, when exact-position behavior is required,
- `CTrade::PositionModify()` returning `true` is not sufficient evidence of server execution; `ResultRetcode()` must also be checked,
- `SYMBOL_TRADE_TICK_SIZE` is the minimum price change,
- `SYMBOL_TRADE_STOPS_LEVEL` and `SYMBOL_TRADE_FREEZE_LEVEL` must be respected,
- `OnTradeTransaction()` is the event designed to receive trade-account transaction changes,
- Terminal Global Variables can persist values across terminal restarts, but are deleted after four weeks without access and have a 63-character name limit.

Tier B requirements are mandatory correctness constraints.

## Tier C — Experimental Features of This Project

These remain valuable research ideas, but **must not be treated as superior before testing**:

- favorable-extreme / high-water-low-water anchoring,
- ATR-based minimum modification step,
- persistence of favorable extrema,
- frozen ATR-at-discovery activation reference,
- custom restart recovery based on reconstructed extrema.

Tier C features must:

1. be configurable,
2. be separable from the benchmark path,
3. have a baseline comparison,
4. log enough data for A/B evaluation,
5. not be enabled by default unless later evidence justifies it.

## Tier D — Deferred Speculation

Do not add a feature merely because it sounds useful.

Examples include:

- adaptive ATR multiplier,
- volatility regime switching,
- session-aware behavior,
- spread-based trailing suspension,
- break-even stages,
- structure-based trailing.

A Tier D feature may enter a future version only after a written hypothesis and controlled test plan exist.

## Baseline Principle

The first implementation target is:

```text
simple current-price ATR trailing
+ ATR Shift 1
+ one-way SL movement
+ broker-valid tick-size normalization
+ exact ticket handling
+ retcode verification
+ robust filtering
+ optional activation
```

The previous project concept remains available as an experimental comparison rather than being assumed to be better.


---

# 1. Execution Directive for Codex

Implement this PRD exactly as specified.

Do not ask the user for clarification unless implementation is literally impossible due to a missing external dependency.

When multiple implementation choices are possible:

1. choose the safest MQL5-native approach,
2. prefer broker-agnostic logic,
3. prefer behavior backed by Tier A or Tier B evidence,
4. keep Tier C experimental behavior isolated behind explicit inputs,
5. prefer per-position ticket handling over per-symbol shortcuts,
6. preserve existing SL/TP unless this PRD explicitly says otherwise,
7. never loosen an existing stop loss,
8. log every important state transition and rejected modification,
9. do not add trading-entry logic,
10. do not add speculative features that are outside scope,
11. make the EA compile cleanly in MetaEditor without warnings where reasonably possible.

When the baseline and experimental modes differ, Codex must not silently merge their behavior.

The EA must be usable immediately after compilation with the baseline default parameters defined in this document.

# 2. Product Summary

The product is a MetaTrader 5 Expert Advisor that manages Stop Loss dynamically for already-open positions.

The EA does **not** open BUY or SELL positions.

Positions may originate from:

- manual trading,
- another Expert Advisor,
- a script,
- any other valid MT5 trade source.

The EA's role is limited to trailing-stop management.

v1 Beta R1 contains two intentionally separated trailing concepts:

## Baseline Mode

A benchmark-oriented ATR trailing model:

```text
BUY  CandidateSL = Bid - ATR * ATRMultiplier
SELL CandidateSL = Ask + ATR * ATRMultiplier
```

with one-way SL movement only.

This mode is the default because it is close to the behavior documented by a mature public ATR trailing implementation and does not require hidden state to define the next candidate SL.

## Experimental Favorable-Extreme Mode

The previous project concept remains available:

```text
BUY  CandidateSL = HighestBidSinceOpen - ATR * ATRMultiplier
SELL CandidateSL = LowestAskSinceOpen + ATR * ATRMultiplier
```

This is a Tier C experiment.

It must not be described as better until controlled comparison demonstrates an advantage.

The objective of v1 Beta R1 is not to claim profitability.

The objective is to produce a technically correct, observable, benchmarkable, broker-aware trailing-stop engine suitable for:

- MT5 Strategy Tester,
- controlled A/B comparisons,
- parameter robustness testing,
- out-of-sample testing,
- HFM demo forward testing.

# 3. Product Goals

The EA must:

1. detect eligible open positions,
2. calculate ATR correctly from a configurable symbol/timeframe/period/shift,
3. provide a current-price ATR trailing baseline,
4. optionally provide favorable-extreme trailing as an experimental mode,
5. optionally delay activation using ATR multiples or points,
6. calculate a valid ATR-based Stop Loss,
7. never move Stop Loss in an unfavorable direction,
8. preserve any existing Take Profit,
9. support BUY and SELL,
10. support MT5 netting and hedging account modes,
11. manage exact positions by `ulong` ticket,
12. respect tick size, stop level, and freeze level,
13. check trade-server return codes,
14. diagnose common autotrading-disabled conditions,
15. survive EA restart without unsafe SL behavior,
16. provide detailed logs for research,
17. be usable with HFM Demo,
18. remain broker-agnostic,
19. make baseline-vs-experimental comparisons possible without source-code edits.

# 4. Non-Goals

The following are explicitly outside v1 Beta:

- opening trades,
- trade signal generation,
- market prediction,
- martingale,
- grid trading,
- averaging down,
- pyramiding,
- partial close,
- automatic break-even logic,
- news filtering,
- economic-calendar integration,
- machine learning,
- AI-based trade selection,
- adaptive session strategies,
- dynamic volatility-regime switching,
- auto-selection of ATR multiplier,
- XAUUSD-specific behavior,
- portfolio allocation,
- position sizing,
- risk-per-trade calculation,
- live-money deployment logic,
- VPS orchestration,
- copy trading.

Do not implement these features in v1 Beta.

---

# 5. Target Instruments

## 5.1 Primary

- EURUSD

## 5.2 Secondary FX Validation

- GBPUSD
- USDJPY

## 5.3 Cross-Asset Validation

- Nasdaq-100 representation offered by broker, commonly named:
  - NAS100
  - US100
  - USTEC
  - or a broker-specific equivalent

The EA must **not hardcode symbol names**.

It must work using the symbol attached to the chart or via eligible-position scanning rules.

---

# 6. Broker Scope

Primary validation broker:

- HFM Demo MT5

The implementation must not contain HFM-specific numeric assumptions.

Do not hardcode:

- digits,
- point value,
- tick size,
- tick value,
- stop level,
- freeze level,
- contract size,
- spread,
- symbol suffix,
- execution mode.

Retrieve relevant symbol properties dynamically using MQL5 APIs.

---

# 7. Account Modes

The EA must support:

## Netting

One net position per symbol.

## Hedging

Multiple simultaneous positions on the same symbol.

In both cases, stop modification must be performed by **position ticket** whenever possible.

Do not assume that modifying by symbol is safe in hedging mode.

---

# 8. Position Eligibility Rules

A position is eligible only when all enabled filters pass.

Expose:

```text
ManageCurrentSymbolOnly
ApplyToDirection
ManageManualTrades
UseMagicNumberFilter
MagicNumber
UseCommentFilter
CommentFilter
```

Recommended enum:

```text
ApplyToDirection:
- APPLY_BUY_AND_SELL
- APPLY_BUY_ONLY
- APPLY_SELL_ONLY
```

Default behavior:

```text
ManageCurrentSymbolOnly = true
ApplyToDirection        = APPLY_BUY_AND_SELL
ManageManualTrades      = true
UseMagicNumberFilter    = false
MagicNumber             = 0
UseCommentFilter        = false
CommentFilter           = ""
```

Interpretation:

- by default, manage positions only on the chart symbol,
- both BUY and SELL are eligible,
- manual trades are eligible,
- Magic Number filtering is disabled,
- comment filtering is disabled.

If Magic Number filtering is enabled, manage only matching positions.

If comment filtering is enabled, use a clearly documented matching rule. For v1 Beta R1 use:

```text
position comment must contain CommentFilter
```

as a case-sensitive substring unless MQL5 implementation constraints justify a documented alternative.

Do not identify a position solely by symbol when hedging mode can contain multiple positions on that symbol.

# 9. ATR Definition

Use the native MQL5 ATR indicator.

Expose:

```text
ATRPeriod
ATRTimeframe
ATRShift
```

Defaults:

```text
ATRPeriod    = 14
ATRTimeframe = PERIOD_CURRENT
ATRShift     = 1
```

`ATRShift = 1` means use the last closed bar's ATR value.

This is the baseline behavior.

Rationale:

- the benchmark implementation explicitly recommends leaving the ATR shift at `1`,
- using a closed-bar ATR avoids intrabar ATR movement changing the trailing distance on every tick solely because the current ATR bar is still forming.

`ATRShift = 0` may be tested later, but it is not the default.

The EA must expose timeframe as a configurable `ENUM_TIMEFRAMES`.

For multi-symbol management:

- calculate ATR using each managed position's symbol,
- use the configured `ATRTimeframe`,
- if `ATRTimeframe = PERIOD_CURRENT`, use the chart timeframe for all managed symbols.

Indicator data must be considered invalid when:

- handle creation fails,
- `CopyBuffer()` cannot provide the requested shifted value,
- ATR is zero, negative, NaN, or otherwise invalid.

# 10. ATR Multiplier

Expose:

```text
ATRMultiplier
```

Baseline default:

```text
ATRMultiplier = 1.0
```

This value is a **benchmark starting point**, not an optimization claim.

The previous project default:

```text
ATRMultiplier = 2.5
```

must remain in the documented experiment presets, but is no longer the baseline default because this project has not yet produced comparative evidence that 2.5 is superior.

Research range:

```text
1.0 to 3.5
```

Suggested optimization step:

```text
0.25
```

Do not claim any multiplier is optimal until tested on a defined instrument, timeframe, sample period, and entry process.

# 11. Trailing Anchor Modes

Expose:

```text
TrailingAnchorMode
```

Recommended enum:

```text
ANCHOR_CURRENT_PRICE
ANCHOR_FAVORABLE_EXTREME
```

Default:

```text
TrailingAnchorMode = ANCHOR_CURRENT_PRICE
```

## 11.1 Baseline — Current Price

BUY:

```text
CandidateSL = Bid - (ATR * ATRMultiplier)
```

SELL:

```text
CandidateSL = Ask + (ATR * ATRMultiplier)
```

The existing-SL one-way rule prevents a later adverse price move from loosening the stop.

This mode does not require a historical high-water or low-water value to calculate the next candidate.

## 11.2 Experimental — Favorable Extreme

For BUY track:

```text
HighestBidSinceOpen
```

and calculate:

```text
CandidateSL =
HighestBidSinceOpen - (ATR * ATRMultiplier)
```

For SELL track:

```text
LowestAskSinceOpen
```

and calculate:

```text
CandidateSL =
LowestAskSinceOpen + (ATR * ATRMultiplier)
```

This mode is Tier C.

It must be evaluated against `ANCHOR_CURRENT_PRICE` using identical entry trades and tick data.

Do not label favorable-extreme anchoring as an improvement until the experiment demonstrates a measurable benefit.

# 12. Price Sources

Always obtain a fresh `MqlTick` snapshot for the position symbol.

For BUY:

```text
current trailing reference price = Bid
```

For SELL:

```text
current trailing reference price = Ask
```

In `ANCHOR_FAVORABLE_EXTREME` mode:

```text
BUY tracking price  = Bid
SELL tracking price = Ask
```

Do not calculate BUY stop placement from Ask.

Do not calculate SELL stop placement from Bid.

If the required price is zero, stale, or unavailable:

```text
skip processing for that position on that cycle
```

and log the reason in debug mode.

# 13. Stop-Loss Direction Rule

This requirement is mandatory.

## BUY

A new SL may only be applied if:

```text
CurrentSL == 0
```

or:

```text
NewSL > CurrentSL
```

## SELL

A new SL may only be applied if:

```text
CurrentSL == 0
```

or:

```text
NewSL < CurrentSL
```

The EA must never loosen an existing Stop Loss.

Once a Stop Loss becomes more protective, it may not be reversed.

---

# 14. Take-Profit Rule

The EA must preserve the existing Take Profit.

If the position has TP:

```text
NewTP = ExistingTP
```

If the position has no TP:

```text
NewTP = 0
```

The EA must never create, remove, widen, or reduce Take Profit.

---

# 15. Activation Logic

Activation is optional.

Expose:

```text
ActivationMode
ActivationATR
ActivationPoints
```

Recommended enum:

```text
ACTIVATION_OFF
ACTIVATION_ATR
ACTIVATION_POINTS
```

Baseline default:

```text
ActivationMode   = ACTIVATION_OFF
ActivationATR    = 1.0
ActivationPoints = 0
```

Reason:

- immediate ATR trailing provides the simplest benchmark,
- the mature reference implementation added optional ATR/points activation in v1.09,
- activation should therefore be tested as a separate factor rather than silently bundled into the baseline.

Once activation occurs it must remain latched for the lifetime of the managed position.

Do not deactivate trailing because price later falls back below the activation level.

# 16. Activation for BUY

If:

```text
ActivationMode = ACTIVATION_OFF
```

then:

```text
TrailingActive = true
```

when the position becomes eligible.

If:

```text
ActivationMode = ACTIVATION_ATR
```

use the same valid shifted ATR value produced by the configured ATR engine:

```text
ActivationPrice =
PositionOpenPrice + (ATR * ActivationATR)
```

Trailing activates when:

```text
Bid >= ActivationPrice
```

If:

```text
ActivationMode = ACTIVATION_POINTS
```

calculate:

```text
ActivationPrice =
PositionOpenPrice + (ActivationPoints * Point)
```

Trailing activates when:

```text
Bid >= ActivationPrice
```

The activation level may be recomputed before activation when ATR mode is used.

Do **not** freeze ATR at first discovery in the baseline implementation.

A frozen activation ATR reference is retained only as a future experimental idea because this project has not yet validated that behavior.

# 17. Activation for SELL

If:

```text
ActivationMode = ACTIVATION_OFF
```

then:

```text
TrailingActive = true
```

when the position becomes eligible.

If:

```text
ActivationMode = ACTIVATION_ATR
```

calculate:

```text
ActivationPrice =
PositionOpenPrice - (ATR * ActivationATR)
```

Trailing activates when:

```text
Ask <= ActivationPrice
```

If:

```text
ActivationMode = ACTIVATION_POINTS
```

calculate:

```text
ActivationPrice =
PositionOpenPrice - (ActivationPoints * Point)
```

Trailing activates when:

```text
Ask <= ActivationPrice
```

Once activated:

```text
TrailingActive = true
```

and activation remains latched.

# 18. Immediate-Trailing Mode

Immediate trailing is now the baseline.

If:

```text
ActivationMode = ACTIVATION_OFF
```

then trailing is active as soon as the EA begins managing the position.

This creates a clean control condition for later comparison against:

- ATR-multiple activation,
- points-based activation.

The test harness and README must make this distinction explicit.

# 19. Minimum Trailing Step

The minimum trailing step is retained as a Tier C experiment intended to reduce unnecessary modification requests.

Expose:

```text
UseMinimumTrailingStep
MinimumStepATR
```

Defaults:

```text
UseMinimumTrailingStep = false
MinimumStepATR         = 0.10
```

It is disabled by default because this project has not yet measured whether the reduction in modification count is beneficial enough to justify potentially coarser SL updates.

When enabled:

```text
MinimumStepDistance = ATR * MinimumStepATR
```

For BUY with an existing SL:

```text
CandidateSL - CurrentSL >= MinimumStepDistance
```

For SELL with an existing SL:

```text
CurrentSL - CandidateSL >= MinimumStepDistance
```

If `CurrentSL == 0`, the minimum-step rule must not block the first valid SL.

Research must record:

- number of avoided modification requests,
- accepted modifications,
- rejected modifications,
- resulting stop path differences,
- final trade outcome differences.

This allows the feature to be judged from data rather than assumption.

# 20. Broker Stop-Level Validation

Before sending any SL modification, retrieve the symbol's minimum stop distance.

At minimum account for:

```text
SYMBOL_TRADE_STOPS_LEVEL
```

The property is expressed in points.

Convert it into price distance using the symbol's point value.

A BUY SL must be far enough below the applicable current market price.

A SELL SL must be far enough above the applicable current market price.

If a candidate violates the broker stop distance:

1. do not send the invalid request blindly,
2. calculate the nearest broker-valid candidate,
3. normalize it to valid tick size,
4. apply it only if it remains more protective than the existing SL,
5. otherwise skip.

Log the exact reason and relevant broker values.

Do not hardcode Forex pip assumptions.

# 21. Freeze-Level Validation

Account for:

```text
SYMBOL_TRADE_FREEZE_LEVEL
```

The freeze level is expressed in points.

If the requested stop modification is within the broker freeze zone:

```text
skip modification
```

Log:

```text
SKIP_FREEZE_LEVEL
```

Do not repeatedly send the same invalid request every tick when nothing relevant has changed.

Freeze-level behavior must be tested explicitly on a symbol/environment where a non-zero freeze level can be reproduced or simulated.

# 22. Tick-Size Normalization

Candidate SL must be aligned to:

```text
SYMBOL_TRADE_TICK_SIZE
```

because tick size is the platform-defined minimum price change.

Do not assume that `NormalizeDouble(price, digits)` alone produces a tradable stop price.

Use:

```text
SYMBOL_TRADE_TICK_SIZE
SYMBOL_DIGITS
SYMBOL_POINT
```

as appropriate.

A robust normalization function must:

1. obtain tick size,
2. reject zero/invalid tick size,
3. align the candidate to the tick-size grid,
4. normalize display precision using symbol digits,
5. re-check stop/freeze validity after normalization.

This requirement is mandatory for CFD/index compatibility.

# 23. Spread Awareness

The EA must read current:

```text
Bid
Ask
Spread
```

The spread must be logged when SL modification is attempted.

v1 Beta must **not** include a spread filter that disables trailing.

Reason:

the purpose of v1 Beta is observation and baseline testing.

However, spread data must be included in logs so later research can determine whether a spread filter is justified.

---

# 24. Position State Model

Maintain one state object per managed position.

Tickets must use:

```text
ulong
```

Required common state fields:

```text
PositionTicket
PositionIdentifier
Symbol
PositionType
OpenTime
OpenPrice
TrailingActive
LastKnownSL
LastModificationTime
LastCandidateSL
LastRetcode
ModificationCount
RejectedModificationCount
```

Required only for experimental favorable-extreme mode:

```text
HighestBidSinceOpen
LowestAskSinceOpen
```

Recommended diagnostics:

```text
LastATR
LastActivationPrice
LastDecisionCode
LastBid
LastAsk
```

Do not store a position ticket in `int`.

State lookup must be exact per position, especially in hedging accounts.

# 25. State Initialization

When the EA discovers a position it has not seen before:

1. obtain the position ticket as `ulong`,
2. refresh/select the position before reading its fields,
3. read symbol, type, open time, open price, existing SL and TP,
4. read a fresh market tick,
5. obtain valid ATR data using `ATRShift`,
6. initialize common diagnostic state,
7. initialize activation latch according to `ActivationMode`,
8. initialize experimental extrema only when `ANCHOR_FAVORABLE_EXTREME` is selected.

For `ANCHOR_CURRENT_PRICE`, no historical price-extreme reconstruction is required.

For `ANCHOR_FAVORABLE_EXTREME`:

```text
BUY initial high >= max(OpenPrice, CurrentBid)
SELL initial low  <= min(OpenPrice, CurrentAsk)
```

If a persisted valid extreme exists, restore it.

If no persisted extreme exists:

- attempt reconstruction from available history only when the implementation can do so deterministically,
- otherwise initialize conservatively from current/open price,
- log `STATE_DEGRADED_REINIT`,
- never loosen an already-existing SL in an attempt to recreate old state.

Do not pretend an unknown historical extreme is known.

# 26. Restart Persistence Requirement

Restart behavior depends on trailing anchor mode.

## 26.1 Baseline Current-Price Mode

`ANCHOR_CURRENT_PRICE` must remain safe after:

- MT5 restart,
- EA reattachment,
- chart timeframe change,
- reconnect.

Because the next candidate comes from current price and ATR, favorable-extreme persistence is not required for baseline calculation.

Existing broker-side SL remains the authoritative protection level.

After restart the EA must still enforce:

```text
never loosen existing SL
preserve TP
use fresh ATR/tick/broker properties
```

## 26.2 Experimental Favorable-Extreme Mode

`ANCHOR_FAVORABLE_EXTREME` requires persistent or reconstructed extrema to preserve identical behavior across restart.

Preferred storage:

```text
MT5 Terminal Global Variables
```

Key design must stay within the platform name-length limit.

Persist at minimum:

```text
HighestBidSinceOpen
LowestAskSinceOpen
TrailingActive
```

Optional:

```text
last candidate
state schema version
```

Terminal Global Variables persist across terminal restart, but the platform may delete them after four weeks without access.

When important state changes, write it.

After a coherent state batch has been updated, `GlobalVariablesFlush()` may be used at controlled transition points when stronger crash persistence is desired.

Do not flush on every tick.

## 26.3 Restart Recovery Conflict Rule

A restored experimental extreme can imply a theoretical candidate that is no longer valid relative to the current Bid/Ask.

In that case:

1. never place an SL on the invalid side of current market price,
2. never loosen an existing SL,
3. apply normal tick-size, stop-level, and freeze-level validation,
4. if no valid improving stop exists, skip,
5. log `STATE_RESTORED_CANDIDATE_INVALID`.

Persistence preserves research state; it does not override broker rules.

# 27. State Cleanup

When a position is closed:

- remove its in-memory state,
- remove its persistent Global Variables,
- log cleanup.

Do not retain stale position state indefinitely.

---

# 28. Event Architecture

Use standard MQL5 EA event handling.

Required:

```text
OnInit()
OnDeinit()
OnTick()
OnTradeTransaction()
```

`OnTick()` is responsible for market-driven trailing evaluation.

`OnTradeTransaction()` is responsible for synchronizing position/trade state when account transactions occur, including:

- newly created positions,
- closed positions,
- externally modified SL/TP,
- trade-request execution results where relevant.

Do not assume trade-transaction callbacks arrive in a custom logical order.

Always re-read fresh position state when correctness depends on current server state.

Do not use blocking loops.

Do not use `Sleep()` inside normal tick-processing logic.

# 29. ATR Handle Management

Create indicator handles efficiently.

Do not recreate an ATR indicator handle on every tick.

Cache ATR handles by:

```text
symbol + timeframe + ATR period
```

Release handles appropriately on deinitialization.

If ATR data is not ready:

- skip that update cycle,
- do not use zero or stale value silently,
- log only if debug logging is enabled.

---

# 30. Position Scan Frequency

Default:

process on every new tick.

However, do not submit an SL modification unless:

- trailing is active,
- candidate is better,
- minimum-step rule is satisfied,
- broker rules permit it.

This preserves responsiveness while avoiding server spam.

---

# 31. Modification API

Modify positions by exact ticket.

Preferred interface:

```text
CTrade::PositionModify(ticket, newSL, existingTP)
```

The symbol-based overload must not be used as the primary path for exact-position management in hedging accounts.

Reason:

- hedging mode can contain several positions for the same symbol,
- symbol-based modification may target the lowest-ticket position rather than the intended position.

Before modifying:

1. refresh/select the exact position,
2. confirm ticket still exists,
3. re-read current SL and TP,
4. re-check that the candidate still improves SL,
5. preserve current TP.

After calling `PositionModify()`:

- inspect the Boolean return,
- inspect `ResultRetcode()`,
- record `ResultRetcodeDescription()` where useful,
- do not interpret Boolean `true` as proof that the trade server executed the modification.

Use the exact current TP value in the request.

# 32. Modification Retry Policy

Do not use aggressive retry loops.

Default:

```text
MaxImmediateRetries = 0
```

If a modification is rejected:

- log it,
- wait for a future tick,
- re-evaluate from fresh market data.

This prevents request flooding.

---

# 33. Logging System

Expose:

```text
EnableDebugLog
```

Default:

```text
EnableDebugLog = true
```

Log levels:

```text
INFO
DEBUG
WARN
ERROR
```

Minimum log fields for trailing evaluation:

```text
timestamp
ticket as unsigned 64-bit value
position identifier
symbol
position type
anchor mode
activation mode
open price
bid
ask
spread
ATR
ATR shift
ATR multiplier
high-water / low-water when applicable
activation state
activation price when applicable
current SL
candidate SL
normalized candidate SL
minimum step when enabled
tick size
point
stops level
freeze level
decision
local modify return
server retcode
server retcode description
```

Autotrading diagnostics must distinguish as far as MQL5 exposes:

```text
terminal-level permission/state
program/EA permission/state
account/server/symbol trading restrictions
```

Do not emit only a generic `AUTOTRADING_DISABLED` message when the source can be identified.

Avoid duplicate debug spam when the state and decision have not changed.

# 34. Standard Decision Codes

Use consistent text labels in logs.

Minimum set:

```text
POSITION_DISCOVERED
STATE_INITIALIZED
STATE_RESTORED
STATE_DEGRADED_REINIT
STATE_RESTORED_CANDIDATE_INVALID

TRAILING_NOT_ACTIVATED
TRAILING_ACTIVATED

NO_BETTER_SL
SKIP_MIN_STEP
SKIP_STOP_LEVEL
SKIP_FREEZE_LEVEL
SKIP_INVALID_ATR
SKIP_INVALID_TICK
SKIP_INVALID_PRICE
SKIP_POSITION_GONE

AUTOTRADING_DISABLED_TERMINAL
AUTOTRADING_DISABLED_PROGRAM
ACCOUNT_TRADE_NOT_ALLOWED
SYMBOL_TRADE_DISABLED

SL_MODIFY_SENT
SL_MODIFY_SUCCESS
SL_MODIFY_REJECTED

POSITION_CLOSED
STATE_CLEANUP
```

Where exact MQL5 conditions cannot be distinguished, log the most specific condition supported by the platform data available at runtime.

# 35. User Inputs

The EA must expose at least:

```text
group "ATR Settings"
ATRPeriod
ATRTimeframe
ATRShift
ATRMultiplier

group "Trailing Model"
TrailingAnchorMode

group "Activation"
ActivationMode
ActivationATR
ActivationPoints

group "Experimental Trailing Step"
UseMinimumTrailingStep
MinimumStepATR

group "Position Filters"
ManageCurrentSymbolOnly
ApplyToDirection
ManageManualTrades
UseMagicNumberFilter
MagicNumber
UseCommentFilter
CommentFilter

group "Diagnostics"
EnableDebugLog
```

Optional visual diagnostics may be added only if they remain isolated from core logic:

```text
ShowPotentialSLLine
ShowActivationLine
```

A large control panel is not required for v1 Beta R1.

# 36. Default Input Values

Baseline defaults:

```text
ATRPeriod                 = 14
ATRTimeframe              = PERIOD_CURRENT
ATRShift                  = 1
ATRMultiplier             = 1.0

TrailingAnchorMode        = ANCHOR_CURRENT_PRICE

ActivationMode            = ACTIVATION_OFF
ActivationATR             = 1.0
ActivationPoints          = 0

UseMinimumTrailingStep    = false
MinimumStepATR            = 0.10

ManageCurrentSymbolOnly   = true
ApplyToDirection          = APPLY_BUY_AND_SELL
ManageManualTrades        = true
UseMagicNumberFilter      = false
MagicNumber               = 0
UseCommentFilter          = false
CommentFilter             = ""

EnableDebugLog            = true
```

Document this previous-concept experiment preset separately:

```text
TrailingAnchorMode        = ANCHOR_FAVORABLE_EXTREME
ATRMultiplier             = 2.5
ActivationMode            = ACTIVATION_ATR
ActivationATR             = 1.0
UseMinimumTrailingStep    = true
MinimumStepATR            = 0.10
```

The experiment preset is **not** the default and must not be described as superior.

# 37. Input Validation

On initialization, validate inputs.

Reject invalid values such as:

```text
ATRPeriod <= 0
ATRShift < 0
ATRMultiplier <= 0
ActivationATR < 0
ActivationPoints < 0
MinimumStepATR < 0
```

Also reject or safely disable impossible combinations.

Examples:

- invalid enum values,
- activation mode requiring a zero/invalid point value,
- comment filter enabled with an empty comment string if that would unintentionally match all positions.

If invalid:

- print a clear error,
- fail initialization using the appropriate MQL5 init result.

Do not silently auto-correct obviously invalid research parameters.

# 38. Research Parameter Ranges

These are exploratory ranges, not validated optimums.

## ATR Period

```text
7
10
14
20
21
28
```

## ATR Shift

Primary comparison:

```text
1
```

Optional sensitivity test:

```text
0
1
```

Do not mix shift testing with early anchor-mode testing.

## ATR Multiplier

```text
1.0 to 3.5
step 0.25
```

## Activation

First compare:

```text
ACTIVATION_OFF
ACTIVATION_ATR
```

For ATR activation:

```text
0.50
0.75
1.00
1.25
1.50
2.00
```

Points-based activation should be tested only with symbol-appropriate point values and must not be compared across instruments as if equal points mean equal volatility.

## Minimum Step ATR

Only after baseline correctness:

```text
0.00
0.05
0.10
0.20
0.25
```

## Anchor Mode

Mandatory A/B comparison:

```text
ANCHOR_CURRENT_PRICE
ANCHOR_FAVORABLE_EXTREME
```

Change one major factor at a time in the first experiments.

# 39. Trailing Algorithm — BUY

Conceptual flow:

```text
detect eligible BUY position

load/init exact-ticket state

get fresh Bid/Ask

get ATR[ATRShift]

if ATR invalid:
    skip

if anchor mode == FAVORABLE_EXTREME:
    HighestBidSinceOpen =
        max(HighestBidSinceOpen, Bid)

evaluate activation

if not active:
    stop processing this position for this tick

if anchor mode == CURRENT_PRICE:
    AnchorPrice = Bid
else:
    AnchorPrice = HighestBidSinceOpen

CandidateSL =
    AnchorPrice - ATR * ATRMultiplier

normalize CandidateSL to valid tick size

refresh exact position

validate:
    candidate is below valid BUY market side
    candidate improves CurrentSL
    optional minimum trailing step
    stop level
    freeze level
    TP preservation

if valid:
    modify SL by position ticket
    check local result
    check server retcode
```

No step may loosen an existing SL.

# 40. Trailing Algorithm — SELL

Conceptual flow:

```text
detect eligible SELL position

load/init exact-ticket state

get fresh Bid/Ask

get ATR[ATRShift]

if ATR invalid:
    skip

if anchor mode == FAVORABLE_EXTREME:
    LowestAskSinceOpen =
        min(LowestAskSinceOpen, Ask)

evaluate activation

if not active:
    stop processing this position for this tick

if anchor mode == CURRENT_PRICE:
    AnchorPrice = Ask
else:
    AnchorPrice = LowestAskSinceOpen

CandidateSL =
    AnchorPrice + ATR * ATRMultiplier

normalize CandidateSL to valid tick size

refresh exact position

validate:
    candidate is above valid SELL market side
    candidate improves CurrentSL
    optional minimum trailing step
    stop level
    freeze level
    TP preservation

if valid:
    modify SL by position ticket
    check local result
    check server retcode
```

No step may loosen an existing SL.

# 41. ATR Semantics and Activation Reference

The baseline uses one ATR retrieval rule:

```text
ATR = ATR value at configured ATRShift
```

Default:

```text
ATRShift = 1
```

The same shifted ATR value is used in a processing cycle for:

- trailing distance,
- ATR-based activation calculation.

This avoids mixing an intrabar ATR for one decision with a closed-bar ATR for another.

The previous behavior:

```text
freeze ATR at first discovery and use it forever as activation reference
```

is removed from baseline requirements.

It may return later only as a separately named experiment, for example:

```text
ActivationATRReferenceMode = FROZEN_AT_DISCOVERY
```

after the simpler baseline has been tested.

Do not add that input in v1 Beta R1 unless implementation is otherwise complete and the mode remains disabled by default.

# 42. Existing Stop Loss Handling

If an eligible position already has an SL:

- preserve it until the EA has a strictly more protective valid SL.

Never replace an existing protective SL with a worse one.

Examples:

## BUY

Existing:

```text
SL = 1.1020
```

Calculated:

```text
CandidateSL = 1.1015
```

Action:

```text
do nothing
```

## SELL

Existing:

```text
SL = 1.0980
```

Calculated:

```text
CandidateSL = 1.0990
```

Action:

```text
do nothing
```

---

# 43. No-Initial-SL Behavior

The EA may manage a position whose initial SL is zero.

Before trailing activation:

```text
SL remains unchanged
```

After trailing activation:

if a valid candidate SL exists:

```text
set the first SL
```

This behavior is intentional for v1 Beta.

---

# 44. Timeframe Behavior

The EA must support normal MT5 timeframes.

Default:

```text
ATRTimeframe = PERIOD_CURRENT
```

If current-symbol-only mode is false:

- ATR must be calculated from each position's symbol,
- timeframe remains the configured `ATRTimeframe`,
- when `PERIOD_CURRENT` is selected, the attached chart timeframe is used for all managed symbols.

This behavior must be documented because it can otherwise be misinterpreted during multi-symbol testing.

Changing chart timeframe may reinitialize the EA.

Baseline current-price mode must resume safely without needing extrema persistence.

Experimental favorable-extreme mode must follow the persistence/reconstruction rules in Section 26.

# 45. NAS100 Compatibility

Nasdaq symbols may have:

- different digits,
- much larger nominal prices,
- different tick sizes,
- different contract specifications,
- different stop-level constraints.

Therefore the implementation must not use Forex-specific pip assumptions.

Do not implement logic such as:

```text
1 pip = 0.0001
```

inside the generic engine.

Everything must derive from symbol properties.

---

# 46. No Pip-Based Core Logic

The trailing engine must use:

```text
price units
ATR
tick size
point
symbol properties
```

Do not make pip-distance a required concept in v1 Beta.

This keeps the EA compatible across:

- EURUSD,
- GBPUSD,
- USDJPY,
- NAS100.

---

# 47. Backtest Readiness

The EA must compile and run in MT5 Strategy Tester.

It must not depend on:

- external DLLs,
- web APIs,
- network requests,
- Python,
- local external files,
- external indicators.

ATR must use built-in MT5 functionality.

---

# 48. Forward-Demo Readiness

The same compiled EA used in Strategy Tester must work on HFM Demo without code changes.

Only inputs may differ.

No separate "demo version" is allowed.

---

# 49. Strategy Tester Limitation

Because this EA does not open trades, standalone backtesting requires positions to exist.

For v1 Beta, support one of these testing approaches without changing core logic:

## Preferred research approach

Create a separate minimal test harness EA or script that opens deterministic test trades.

The trailing manager logic must remain isolated.

OR

Use a future entry EA that creates positions while this manager handles exits.

Do not add entry logic into the trailing manager itself merely to make backtesting convenient.

---

# 50. Testing Harness Recommendation

If Codex creates a testing harness, it must be a separate source file.

Suggested file:

```text
ATR_Trailing_TestHarness.mq5
```

Its purpose is only to generate repeatable test positions.

It is not part of the production trailing manager.

The main EA file should remain:

```text
ATR_Trailing_Manager_v1_Beta.mq5
```

---

# 51. Required Test Cases

At minimum test:

1. BUY with no initial SL.
2. SELL with no initial SL.
3. BUY with existing SL.
4. SELL with existing SL.
5. current-price anchor BUY.
6. current-price anchor SELL.
7. favorable-extreme anchor BUY.
8. favorable-extreme anchor SELL.
9. immediate activation.
10. ATR activation before threshold.
11. ATR activation crossing threshold.
12. points activation crossing threshold.
13. activation remains latched.
14. ATR Shift 1 uses the requested closed-bar value.
15. ATR unavailable / CopyBuffer failure.
16. minimum-step disabled.
17. minimum-step enabled and blocks a modification.
18. stop-level blocks or adjusts a candidate safely.
19. freeze-level blocks modification.
20. valid tick-size normalization.
21. CFD/index-like non-Forex tick size.
22. valid SL modification.
23. local modify call failure.
24. server-retcode rejection after local request validation.
25. multiple hedged positions on the same symbol.
26. exact ticket modification targets the intended hedged position.
27. netting account behavior.
28. ticket greater than signed 32-bit integer range.
29. manual trade.
30. Magic Number included.
31. Magic Number excluded.
32. comment filter included.
33. comment filter excluded.
34. BUY-only filter.
35. SELL-only filter.
36. multi-symbol management when current-symbol-only is false.
37. symbol suffix.
38. chart timeframe behavior.
39. EA restart in current-price mode.
40. EA restart in favorable-extreme mode with valid persisted state.
41. favorable-extreme restart with missing state.
42. restored extreme implies invalid current candidate.
43. position closed while EA runs.
44. SL externally modified while EA runs.
45. TP remains unchanged after multiple SL updates.
46. terminal/program autotrading disabled diagnostics.
47. symbol trading disabled.
48. market closed / no valid tick.
49. state cleanup.
50. no immediate retry flooding.

For regression testing, create deterministic cases corresponding to public benchmark bug classes:

```text
large ticket IDs
cross-symbol calculations
non-Forex tick sizes / CFDs
disabled autotrading diagnostics
```

A feature is not considered complete merely because the happy path works.

# 52. Acceptance Criteria — Functional

v1 Beta R1 is functionally accepted only when all are true:

- EA compiles successfully.
- EA detects eligible positions.
- default baseline uses current-price ATR trailing.
- ATR Shift 1 is implemented correctly.
- BUY and SELL calculations are correct.
- activation OFF works.
- ATR activation works.
- points activation works.
- activation remains latched.
- SL never moves backward.
- TP is never changed.
- first SL can be created if current SL is zero.
- ticket variables use `ulong`.
- exact-ticket modification works in hedging mode.
- invalid stop distances are not sent blindly.
- freeze constraints are handled.
- prices are tick-size normalized.
- server retcodes are checked.
- large-ticket regression test passes.
- current-symbol and multi-symbol behavior are documented and tested.
- Magic Number, comment, and direction filters work.
- current-price mode resumes safely after restart.
- experimental favorable-extreme mode follows its persistence rules.
- stale state is removed after position close.
- debug logging can be disabled.
- autotrading-disabled diagnostics are specific where the platform allows.
- EA works in Strategy Tester with a separate harness.
- EA works on HFM Demo without source-code changes.

Profitability is not an acceptance criterion.

# 53. Acceptance Criteria — Research Quality

The implementation must make controlled comparisons possible without source edits.

At minimum compare:

```text
TrailingAnchorMode
ActivationMode
ATRMultiplier
ATRPeriod
ATRShift
UseMinimumTrailingStep
MinimumStepATR
```

The research harness must be able to feed the **same entries** to competing trailing configurations.

The logs must be sufficient to answer:

- why trailing was or was not active,
- which ATR bar/shift was used,
- what anchor price was used,
- why an SL did not move,
- why a modification was rejected,
- whether broker normalization changed the candidate,
- how many modification requests each mode generated,
- whether restart changed the stop path,
- whether a feature reduced requests at the cost of different exit behavior.

Do not compare two trailing modes using different entry trades and call the result evidence about the trailing rule.

# 54. Acceptance Criteria — Safety

The EA must never:

- open a new trade,
- increase position volume,
- average down,
- remove an existing TP,
- loosen an SL,
- modify an unrelated position,
- intentionally bypass broker stop/freeze constraints,
- repeatedly flood the trade server with immediate retries.

---

# 55. Suggested File Structure

```text
/EA
  ATR_Trailing_Manager_v1_Beta.mq5

/include
  optional helper .mqh files if needed

/tests
  ATR_Trailing_TestHarness.mq5
```

If helper classes are used, keep them focused.

Suggested logical modules:

```text
PositionScanner
PositionState
ATRProvider
TrailingEngine
BrokerRules
TradeExecutor
Logger
Persistence
```

These may be classes or clean functions.

Do not over-engineer if a simpler architecture remains readable.

---

# 56. Suggested Internal Data Structure

Recommended conceptual structure:

```cpp
struct PositionTrailState
{
   ulong  ticket;
   long   identifier;
   string symbol;

   ENUM_POSITION_TYPE type;

   datetime open_time;
   double   open_price;

   bool trailing_active;

   // Used only by ANCHOR_FAVORABLE_EXTREME.
   double highest_bid;
   double lowest_ask;

   double last_known_sl;
   double last_candidate_sl;
   double last_atr;
   double last_activation_price;

   datetime last_modification_time;

   uint modification_count;
   uint rejection_count;

   uint last_retcode;
};
```

Exact field types may be adapted to valid MQL5 syntax.

Do not store tickets or trade identifiers in narrow signed integer types when MQL5 exposes them as 64-bit values.

# 57. Persistence Key Design

Persistence is required only for state that must survive restart.

For experimental extrema, keys must avoid collisions across:

- accounts,
- positions,
- state schema versions.

Recommended compact concept:

```text
ATRTS1_<AccountLogin>_<PositionIdentifier>_<Field>
```

Examples:

```text
ATRTS1_123456_987654321_H
ATRTS1_123456_987654321_L
ATRTS1_123456_987654321_A
```

Keep every key within the Terminal Global Variable name limit.

Use short field suffixes rather than verbose names.

Because terminal global variables are shared among MQL5 programs in the same client terminal, use a unique project prefix.

Delete stale keys when the position closes.

Do not depend on terminal globals as indefinite archival storage.

# 58. Performance Requirements

The EA should be lightweight.

It must not:

- repeatedly rebuild all indicator handles,
- perform full historical scans every tick,
- write excessive duplicate logs when nothing changed,
- use blocking operations,
- use unnecessary file I/O.

Persistence writes should occur when relevant state changes, not blindly on every tick if avoidable.

---

# 59. Robustness Requirements

Handle gracefully:

- temporary missing ticks,
- invalid Bid/Ask,
- indicator handle failure,
- `CopyBuffer()` data not ready,
- reconnects,
- market closed,
- terminal/program autotrading disabled,
- account trading not allowed,
- symbol trading disabled,
- invalid tick size,
- invalid stop,
- stop-level constraint,
- freeze-level constraint,
- trade request rejection,
- position closed between scan and modification,
- externally modified SL/TP,
- multiple hedged positions on one symbol,
- very large position ticket IDs,
- stale indicator handle,
- terminal deinitialization,
- missing or stale experimental persisted state.

Failures must not crash the EA.

A failure in one position or symbol must not corrupt state for another.

# 60. Default Runtime Behavior

After attaching the EA to EURUSD with baseline defaults:

1. initialize ATR(14),
2. use `ATRShift = 1`,
3. use chart timeframe,
4. monitor eligible EURUSD positions,
5. include manual trades,
6. manage BUY and SELL,
7. use current-price anchor,
8. activate trailing immediately,
9. calculate BUY SL from `Bid - 1.0 × ATR`,
10. calculate SELL SL from `Ask + 1.0 × ATR`,
11. move SL only in the protective direction,
12. do not apply a minimum-step gate,
13. normalize to valid symbol tick size,
14. respect stop/freeze constraints,
15. preserve TP,
16. modify by exact position ticket,
17. check server retcode,
18. log decisions.

To reproduce the previous project hypothesis, load the documented experimental preset instead of changing source code.

# 61. Example BUY Scenario

Assume baseline settings:

```text
Bid           = 1.10300
ATRShift      = 1
ATR[1]        = 0.00110
ATRMultiplier = 1.0
AnchorMode    = CURRENT_PRICE
Activation    = OFF
```

Then:

```text
AnchorPrice = 1.10300
CandidateSL = 1.10300 - 0.00110
            = 1.10190
```

The EA then:

- aligns `1.10190` to valid tick size,
- re-checks current SL,
- verifies it is a protective improvement,
- checks stop level,
- checks freeze level,
- preserves TP,
- modifies by exact ticket,
- checks the server retcode.

If the same trade is run in favorable-extreme mode and the stored high is:

```text
HighestBidSinceOpen = 1.10500
```

then the experimental raw candidate would be:

```text
1.10500 - 0.00110 = 1.10390
```

The difference must be measured, not assumed to be better.

# 62. Example SELL Scenario

Assume baseline settings:

```text
Ask           = 1.09700
ATRShift      = 1
ATR[1]        = 0.00110
ATRMultiplier = 1.0
AnchorMode    = CURRENT_PRICE
Activation    = OFF
```

Then:

```text
AnchorPrice = 1.09700
CandidateSL = 1.09700 + 0.00110
            = 1.09810
```

The EA then performs the same normalization, protection-direction, broker-rule, TP-preservation, exact-ticket, and retcode checks.

If the same trade is run in favorable-extreme mode and:

```text
LowestAskSinceOpen = 1.09500
```

the experimental raw candidate would be:

```text
1.09500 + 0.00110 = 1.09610
```

Again, the experiment determines whether the different stop path is useful.

# 63. Research Workflow

The intended workflow is:

```text
Implement benchmark baseline
    ↓
logic/regression testing
    ↓
verify broker/platform correctness
    ↓
establish deterministic entry harness
    ↓
record baseline stop path
    ↓
A/B test ONE experimental feature
    ↓
out-of-sample repeat
    ↓
cross-symbol repeat
    ↓
HFM Demo forward observation
    ↓
compare historical vs demo execution behavior
    ↓
promote, reject, or revise the experimental feature
```

A Tier C feature may become a future default only after evidence is recorded.

Do not optimize several experimental dimensions simultaneously before baseline behavior is stable.

# 64. Suggested Initial Experiment Matrix

Primary market:

```text
EURUSD
```

Then:

```text
GBPUSD
USDJPY
NAS100 / US100 / USTEC broker equivalent
```

## Stage A — Correctness and Benchmark Baseline

Keep fixed:

```text
ATRPeriod        = 14
ATRShift         = 1
ATRMultiplier    = 1.0
Anchor           = CURRENT_PRICE
Activation       = OFF
MinimumStep      = OFF
```

Goal:

```text
prove deterministic and broker-valid behavior
```

## Stage B — Anchor Experiment

Change only:

```text
CURRENT_PRICE
vs
FAVORABLE_EXTREME
```

Use identical entries and tick data.

## Stage C — Activation Experiment

With the preferred anchor from Stage B held fixed:

```text
OFF
vs
ATR threshold
```

Then separately test points-based activation if useful for compatibility.

## Stage D — Minimum-Step Experiment

Compare:

```text
OFF
vs
0.05 ATR
vs
0.10 ATR
vs
0.20 ATR
```

Primary question:

```text
Does request reduction materially change stop path or exit result?
```

## Stage E — ATR Multiplier

```text
1.0 to 3.5
step 0.25
```

## Stage F — ATR Period

```text
7, 10, 14, 20, 21, 28
```

## Stage G — Cross-Market Validation

Repeat the chosen configurations across FX and the broker's Nasdaq representation.

Do not interpret one-market optimization as universal evidence.

# 65. Metrics to Export or Record

For trailing-engine research record at minimum:

```text
ticket
symbol
position side
entry time
entry price
exit time
exit price
anchor mode
activation mode
ATR period
ATR shift
ATR multiplier
minimum-step mode/value
SL modification count
SL modification success count
SL modification rejection count
minimum-step skip count
stop-level skip/adjust count
freeze-level skip count
retcodes
maximum favorable excursion
maximum adverse excursion
time to activation
average trailing distance
maximum locked-in price distance
restart/state-restore events
```

Portfolio-level metrics may include:

- Net Profit,
- Profit Factor,
- Max Drawdown,
- Expected Payoff,
- Sharpe Ratio if available,
- Recovery Factor,
- trade count,
- average holding time.

The EA itself does not need to compute every portfolio metric.

The exported/logged data must be sufficient to compare trailing behavior independently from entry logic.

# 66. v1 Beta Success Definition

v1 Beta is successful when:

> The EA behaves deterministically, safely, and observably across supported symbols and account modes, and its trailing logic can be subjected to controlled research.

Profitability is not a v1 Beta acceptance criterion.

---

# 67. Planned v2 Research Topics

Do not implement now unless promoted by evidence from v1 Beta R1.

Candidates:

- frozen ATR-at-entry or ATR-at-discovery activation reference,
- break-even stage,
- regime-dependent ATR multiplier,
- session-aware parameters,
- volatility-normalized activation,
- normalized ATR / ATR percentage,
- spread filter,
- structure-based trailing,
- chandelier-style reference comparison,
- swing-high/swing-low trailing,
- moving-average trailing,
- hybrid trailing,
- XAUUSD stress testing.

Each feature requires:

```text
hypothesis
baseline
controlled variable
measurement
accept/reject criterion
```

before implementation becomes a default behavior.

# 68. Versioning

Use semantic-style development labels.

Recommended sequence for this revised PRD:

```text
v1-beta-r1.0
baseline current-price ATR + Shift 1 + exact ticket

v1-beta-r1.1
broker tick-size/stops/freeze validation + retcode diagnostics

v1-beta-r1.2
filters + activation ATR/points + autotrading diagnostics

v1-beta-r1.3
experimental favorable-extreme mode + conditional persistence

v1-beta-r1.4
deterministic test harness + regression suite

v1-beta-r1.5
HFM Demo forward validation

v1-beta-r1.6
evidence review and default-parameter decision
```

Codex may deliver all functionality in one implementation, but code comments and changelog must make the benchmark baseline and experimental modes distinguishable.

# 69. Code Quality Requirements

Code must:

- use descriptive names,
- contain comments for non-obvious trading logic,
- avoid magic numbers,
- separate configuration from logic,
- avoid duplicated BUY/SELL code where clean abstraction is possible,
- not hide important behavior in overly complex macros,
- expose meaningful error messages,
- avoid unnecessary dependencies.

---

# 70. Changelog Requirement

Include a header comment in the `.mq5` file:

```text
Product:
ATR Trailing Stop Manager EA

Version:
v1 Beta R1

Purpose:
Research/demo ATR-based trailing stop manager.

Baseline:
Current-price ATR trailing using configurable ATR shift.

Experimental:
Favorable-extreme anchoring and minimum-step filtering.

Trading entry:
None.

Primary validation:
Strategy Tester + HFM Demo.

Live-money deployment:
Outside scope of this version.
```

Also maintain a concise internal changelog that records:

- behavioral changes,
- default-value changes,
- broker-compatibility fixes,
- regression bugs,
- test evidence that justified promoting an experimental feature.

# 71. Final Deliverables

Codex should produce:

```text
ATR_Trailing_Manager_v1_Beta_R1.mq5
```

Required test deliverable:

```text
ATR_Trailing_TestHarness.mq5
```

Also produce:

```text
README.md
TEST_MATRIX.md
CHANGELOG.md
```

README must contain:

- installation,
- compilation,
- how to attach to chart,
- baseline defaults,
- benchmark-vs-experimental distinction,
- how to test with a manual demo position,
- how to use Strategy Tester with test harness,
- interpretation of logs,
- known v1 Beta R1 limitations.

`TEST_MATRIX.md` must contain:

- every required test case,
- expected result,
- actual result placeholder,
- pass/fail field,
- broker/build/symbol/timeframe fields.

This prevents "implemented" from being confused with "tested".

# 72. Final Implementation Principle

The EA should be:

```text
simple enough to audit
+
strict enough to test
+
close enough to a known baseline to benchmark
+
flexible enough to isolate experiments
+
safe enough for demo validation
```

Do not optimize prematurely.

Do not add entry strategy.

Do not promote an experimental feature because it sounds logical.

Do not hide behavior.

Do not make assumptions that only work for EURUSD.

Do not use fixed pip logic.

Do not loosen Stop Loss.

Do not overwrite Take Profit.

Do not target positions only by symbol in hedging mode.

Do not treat a local trade-function return value as server confirmation.

Do not ask the user for configuration details already defined in this PRD.

Implement the baseline first, then the experiment modes.

# 73. Ready-to-Build Status

This PRD is **implementation-ready as an evidence-grounded revision**.

No additional user clarification is required for v1 Beta R1.

Codex must implement in this priority order:

1. exact-ticket and broker correctness,
2. current-price ATR baseline,
3. ATR Shift 1 behavior,
4. retcode and diagnostics,
5. filters,
6. optional activation,
7. deterministic test harness,
8. experimental favorable-extreme mode,
9. experimental minimum-step mode,
10. persistence needed by the experimental mode.

If a minor technical decision is not explicitly specified, Codex must:

1. use standard MQL5 conventions,
2. choose the safer option,
3. prefer documented platform behavior,
4. preserve broker compatibility,
5. preserve benchmark/experimental separation,
6. document the decision in code comments,
7. continue implementation without asking the user.

---

# 74. Evidence Register

This revision is grounded in the following public implementation history and platform documentation.

## 74.1 EarnForex ATR Trailing Stop

Repository:

https://github.com/EarnForex/ATR-Trailing-Stop

Product documentation and changelog:

https://www.earnforex.com/metatrader-expert-advisors/atr-trailing-stop/

Evidence used by this PRD:

- the stop distance is ATR-based relative to current price,
- ATR value shift is configurable and `1` is recommended,
- activation threshold is available in ATR multiples and points in v1.09,
- filtering supports current symbol, direction/type, Magic Number, and comment,
- multi-symbol management is supported,
- v1.06 fixed cross-symbol SL calculation and tick-size handling for CFDs,
- v1.08 fixed MT5 failure with large position ticket numbers,
- v1.09 improved diagnostics for disabled autotrading.

The public changelog is evidence that these edge cases occurred in an implementation used outside this project.

It is **not** evidence that any particular ATR multiplier or activation threshold is universally profitable.

## 74.2 MetaQuotes MQL5 Documentation

Position ticket type:

https://www.mql5.com/en/docs/trading/positiongetticket

`PositionGetTicket()` returns `ulong`.

Position modification:

https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionmodify

Important behavior used by this PRD:

- position can be modified by ticket,
- in hedging mode multiple positions can exist for one symbol,
- symbol-based modification may affect the lowest-ticket position,
- `PositionModify()` success does not guarantee server execution,
- the server result must be checked with `ResultRetcode()`.

Symbol properties:

https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants

Important properties:

```text
SYMBOL_POINT
SYMBOL_TRADE_TICK_SIZE
SYMBOL_TRADE_STOPS_LEVEL
SYMBOL_TRADE_FREEZE_LEVEL
```

Trade transaction event:

https://www.mql5.com/en/docs/event_handlers/ontradetransaction

Terminal Global Variables:

https://www.mql5.com/en/docs/globals

Persistence facts used by this PRD:

- terminal global variables survive program scope and terminal sessions,
- they are shared across MQL5 programs in the client terminal,
- they are deleted after four weeks without access,
- global-variable names have a length limit.

Forced persistence:

https://www.mql5.com/en/docs/globals/globalvariablesflush

`GlobalVariablesFlush()` can force terminal global-variable contents to disk, but it should not be abused on every tick.

---

# 75. R1 Decision Log

The following major changes were made from the previous PRD.

| Previous Design | R1 Decision | Reason |
|---|---|---|
| Favorable-extreme anchor was mandatory | Current-price anchor is baseline; favorable-extreme is experimental | Avoid assuming an untested project-specific variant is superior |
| ATR Shift not explicit | `ATRShift = 1` default | Mature implementation explicitly recommends shift 1 |
| Activation ATR was frozen at first management | Baseline activation uses configured shifted ATR; frozen reference deferred | Remove extra state assumption until tested |
| Activation was enabled by default at 1 ATR | Immediate trailing is baseline; ATR/points activation optional | Gives clean control condition and matches mature feature design as optional |
| Minimum step 0.10 ATR enabled | Minimum step disabled by default | Benefit has not yet been measured |
| ATR multiplier 2.5 default | Baseline 1.0; 2.5 preserved as experiment preset | Separate benchmark starting point from prior hypothesis |
| High/low persistence mandatory for all modes | Persistence required only for favorable-extreme behavior | Current-price baseline does not need hidden extrema to define next candidate |
| Basic filters only | Added direction and comment filters | Mature implementation exposes these filters |
| Ticket concept present | `ulong` made explicit and regression-tested | MQL5 API uses `ulong`; benchmark had a real large-ticket bug |
| Tick-size awareness present | Promoted to explicit mandatory normalization pipeline | Benchmark changelog contains a CFD/tick-size fix |
| Retcode check present | Promoted to mandatory acceptance requirement | MetaQuotes explicitly states local success does not prove server execution |
| `OnTradeTransaction()` optional | Required | It is the platform event for trade-account transactions |
| Generic diagnostics | Specific autotrading/trading-disabled codes | Mature v1.09 specifically improved this area |
| Test list | Added benchmark bug-class regression tests and A/B methodology | Implementation history should become executable regression evidence |

R1 deliberately does **not** claim that the benchmark implementation is profitable or optimal.

The benchmark is used to reduce avoidable engineering speculation and to provide a stable control against which project-specific ideas can be tested.
