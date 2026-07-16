import LeanAgent.Agent.Types
import LeanAgent.AI.Compat
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Abort
import LeanAgent.Models

namespace LeanAgent.Agent

open LeanAgent.AI
open LeanAgent.AI.Util.Abort

----------------------------------------------------------------------------
-- StreamFn
----------------------------------------------------------------------------

/--
Stream function signature: model → context → options → event stream.
-/
abbrev StreamFn :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
    IO LeanAgent.AI.AssistantMessageEventStream

/--
Default stream function: wraps `LeanAgent.AI.Compat.streamSimple` to match
the `StreamFn` signature (no default arguments).
-/
def defaultStreamFn : StreamFn :=
  fun model context options => LeanAgent.AI.Compat.streamSimple model context options

----------------------------------------------------------------------------
-- Tool conversion helpers
----------------------------------------------------------------------------

/-- Convert an AgentTool to an AI.Tool for the LLM context. -/
def agentToolToAITool (tool : AgentTool) : LeanAgent.AI.Tool :=
  { name := tool.name
    description := tool.description
    parameters := tool.parameters
  }

/-- Convert an array of AgentTools to AI.Tools. -/
def agentToolsToAITools (tools : Array AgentTool) : Array LeanAgent.AI.Tool :=
  tools.map agentToolToAITool

----------------------------------------------------------------------------
-- streamAssistantResponse
----------------------------------------------------------------------------

/--
Stream an assistant response from the LLM, emitting events via `emit`.
Returns the final assistant `AgentMessage`.
-/
def streamAssistantResponse
    (context : AgentContext)
    (config : AgentLoopConfig)
    (signal : Option AbortSignal)
    (emit : AgentEventSink)
    (streamFn : StreamFn := defaultStreamFn) :
    IO AgentMessage := do
  -- 1. Apply transformContext if set
  let messages ←
    match config.transformContext with
    | some transform => transform context.messages
    | none => pure context.messages
  -- 2. Convert to LLM messages
  let llmMessages := messages.filterMap config.convertToLlm
  -- 3. Build AI.Context
  let llmContext : LeanAgent.AI.Context :=
    { systemPrompt := some context.systemPrompt
      messages := llmMessages
      tools := agentToolsToAITools context.tools
    }
  -- 4. Resolve API key
  let apiKey ←
    match config.getApiKey with
    | some getKey => getKey config.model.provider
    | none => pure none
  -- 5. Build SimpleStreamOptions
  let options : LeanAgent.AI.SimpleStreamOptions :=
    { signal := signal
      apiKey := apiKey
      reasoning := config.reasoning
      thinkingBudgets := config.thinkingBudgets
      transport := config.transport
      sessionId := config.sessionId
      maxRetryDelayMs := config.maxRetryDelayMs
      onPayload := config.onPayload
      onResponse := config.onResponse
    }
  -- 6. Call streamFn
  let stream ← streamFn config.model llmContext options
  -- 7. Iterate events
  let mut finalMessage : Option AgentMessage := none
  for event in stream.events do
    match event with
    | .start snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageStart agentMsg)
    | .textStart _ snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageUpdate agentMsg event)
    | .textDelta _ _ snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageUpdate agentMsg event)
    | .textEnd _ _ snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageUpdate agentMsg event)
    | .thinkingStart _ snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageUpdate agentMsg event)
    | .thinkingDelta _ _ snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageUpdate agentMsg event)
    | .thinkingEnd _ _ snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageUpdate agentMsg event)
    | .toolCallStart _ snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageUpdate agentMsg event)
    | .toolCallDelta _ _ snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageUpdate agentMsg event)
    | .toolCallEnd _ _ snapshot =>
        let agentMsg := AgentMessage.ofMessage (.assistant snapshot)
        emit (.messageUpdate agentMsg event)
    | .done _ message =>
        let agentMsg := AgentMessage.ofMessage (.assistant message)
        finalMessage := some agentMsg
        emit (.messageEnd agentMsg)
    | .error _ message =>
        let agentMsg := AgentMessage.ofMessage (.assistant message)
        finalMessage := some agentMsg
        emit (.messageEnd agentMsg)
  match finalMessage with
  | some msg => pure msg
  | none =>
      -- Stream produced no final event; synthesize an error message
      let timestamp ← IO.monoMsNow
      let errorMsg : LeanAgent.AI.AssistantMessage :=
        { content := #[.text { text := "Stream ended without a final event" }]
          api := config.model.api
          provider := config.model.provider
          model := config.model.id
          stopReason := .error
          errorMessage := some "Stream ended without a final event"
          timestamp := timestamp
        }
      let agentMsg := AgentMessage.ofMessage (.assistant errorMsg)
      emit (.messageEnd agentMsg)
      pure agentMsg

----------------------------------------------------------------------------
-- executeToolCalls
----------------------------------------------------------------------------

/--
Internal result of preparing a tool call: either an immediate outcome
(blocked or error) or a prepared call ready to execute.
-/
inductive PreparedToolCall where
  | immediate (toolCallId : String) (toolName : String) (result : AgentToolResult) (isError : Bool)
  | ready (toolCallId : String) (toolName : String) (args : Lean.Json) (tool : AgentTool)

/--
Internal result after executing a prepared tool call.
-/
structure ExecutedToolCall where
  toolCallId : String
  toolName : String
  args : Lean.Json
  result : AgentToolResult
  isError : Bool
deriving Inhabited

/--
Find a tool by name in the context.
-/
def findToolByName (tools : Array AgentTool) (name : String) : Option AgentTool :=
  tools.find? (fun t => t.name == name)

/--
Prepare a single tool call: find the tool, apply prepareArguments, validate,
and call the beforeToolCall hook. Returns either an immediate outcome or a
prepared call.
-/
def prepareToolCall
    (context : AgentContext)
    (assistantMessage : AgentMessage)
    (toolCall : LeanAgent.AI.ToolCall)
    (config : AgentLoopConfig)
    (signal : Option AbortSignal) :
    IO PreparedToolCall := do
  let toolName := toolCall.name
  match findToolByName context.tools toolName with
  | none =>
      let errorResult : AgentToolResult :=
        { content := #[.text { text := s!"unknown tool: {toolName}" }]
          details := none
          terminate := false
        }
      pure (.immediate toolCall.id toolName errorResult true)
  | some tool =>
      -- Apply prepareArguments if set
      let args :=
        match tool.prepareArguments with
        | some prepare => prepare toolCall.arguments
        | none => toolCall.arguments
      -- Call beforeToolCall hook
      match config.beforeToolCall with
      | some hook =>
          let hookCtx : BeforeToolCallContext :=
            { assistantMessage := assistantMessage
              toolCall := toolCall
              args := args
              context := context
            }
          let hookResult ← hook hookCtx
          match hookResult with
          | some result =>
              if result.block then
                let blockResult : AgentToolResult :=
                  { content :=
                      #[.text { text :=
                        match result.reason with
                        | some reason => s!"tool call blocked: {reason}"
                        | none => "tool call blocked"
                      }]
                    details := none
                    terminate := false
                  }
                pure (.immediate toolCall.id toolName blockResult true)
              else
                pure (.ready toolCall.id toolName args tool)
          | none =>
              pure (.ready toolCall.id toolName args tool)
      | none =>
          pure (.ready toolCall.id toolName args tool)

/--
Execute a prepared tool call, handling the update callback and errors.
-/
def executePreparedToolCall
    (prepared : PreparedToolCall)
    (signal : Option AbortSignal)
    (emit : AgentEventSink) :
    IO ExecutedToolCall := do
  match prepared with
  | .immediate toolCallId toolName result isError =>
      emit (.toolExecutionStart toolCallId toolName Lean.Json.null)
      emit (.toolExecutionEnd toolCallId toolName result isError)
      pure { toolCallId := toolCallId, toolName := toolName, args := Lean.Json.null, result := result, isError := isError }
  | .ready toolCallId toolName args tool =>
      emit (.toolExecutionStart toolCallId toolName args)
      -- Update callback for streaming partial results
      let updateCallback : Option (AgentToolResult → IO Unit) :=
        some (fun partialResult => do
          emit (.toolExecutionUpdate toolCallId toolName args partialResult))
      try
        let result ← tool.execute toolCallId args signal updateCallback
        let isError := result.isError
        emit (.toolExecutionEnd toolCallId toolName result isError)
        pure { toolCallId := toolCallId, toolName := toolName, args := args, result := result, isError := isError }
      catch err =>
        let errorResult : AgentToolResult :=
          { content := #[.text { text := err.toString }]
            details := none
            terminate := false
          }
        emit (.toolExecutionEnd toolCallId toolName errorResult true)
        pure { toolCallId := toolCallId, toolName := toolName, args := args, result := errorResult, isError := true }

/--
Finalize an executed tool call: call the afterToolCall hook and merge overrides.
-/
def finalizeExecutedToolCall
    (executed : ExecutedToolCall)
    (assistantMessage : AgentMessage)
    (toolCall : LeanAgent.AI.ToolCall)
    (context : AgentContext)
    (config : AgentLoopConfig) :
    IO ExecutedToolCall := do
  match config.afterToolCall with
  | some hook =>
      let hookCtx : AfterToolCallContext :=
        { assistantMessage := assistantMessage
          toolCall := toolCall
          args := executed.args
          result := executed.result
          isError := executed.isError
          context := context
        }
      let hookResult ← hook hookCtx
      match hookResult with
      | some overrides =>
          let content := overrides.content.getD executed.result.content
          let details :=
            match overrides.details with
            | some d => some d
            | none => executed.result.details
          let isError := overrides.isError.getD executed.isError
          let terminate := overrides.terminate.getD executed.result.terminate
          pure { executed with
            result := { content := content, details := details, terminate := terminate }
            isError := isError
          }
      | none => pure executed
  | none => pure executed

/--
Create a tool result AgentMessage from an executed tool call.
-/
def createToolResultMessage (executed : ExecutedToolCall) (timestamp : Nat) : AgentMessage :=
  AgentMessage.ofMessage (.toolResult
    { toolCallId := executed.toolCallId
      toolName := executed.toolName
      content := executed.result.content
      details := executed.result.details
      isError := executed.isError
      timestamp := timestamp
    })

/--
Pi `shouldTerminateToolBatch`: a tool batch terminates further tool-driven turns
only when every finalized result sets `terminate = true` (and the batch is non-empty).
-/
def shouldTerminateExecutedBatch (executed : Array ExecutedToolCall) : Bool :=
  !executed.isEmpty && executed.all fun e => e.result.terminate

/-- Emit message_start/message_end for a tool result (Pi emitToolResultMessage). -/
def emitToolResultMessage (message : AgentMessage) (emit : AgentEventSink) : IO Unit := do
  emit (.messageStart message)
  emit (.messageEnd message)

/-- Extract tool calls from an assistant AgentMessage. -/
def assistantToolCalls (assistantMessage : AgentMessage) : Array LeanAgent.AI.ToolCall :=
  match assistantMessage with
  | .ofMessage (.assistant msg) =>
      msg.content.filterMap fun block =>
        match block with
        | .toolCall call => some call
        | _ => none
  | _ => #[]

/--
True when config is sequential or any matching tool declares `executionMode = sequential`
(Pi agent-loop force-sequential rule).
-/
def shouldRunToolsSequentially
    (context : AgentContext)
    (toolCalls : Array LeanAgent.AI.ToolCall)
    (config : AgentLoopConfig) : Bool :=
  match config.toolExecution with
  | .sequential => true
  | .parallel =>
      toolCalls.any fun call =>
        match findToolByName context.tools call.name with
        | some tool => tool.executionMode == some .sequential
        | none => false

/--
Execute all tool calls from an assistant message. Returns the tool result
messages and a `terminate` flag (true only when every tool result terminates).
-/
def executeToolCalls
    (context : AgentContext)
    (assistantMessage : AgentMessage)
    (config : AgentLoopConfig)
    (signal : Option AbortSignal)
    (emit : AgentEventSink) :
    IO (Array AgentMessage × Bool) := do
  let toolCalls := assistantToolCalls assistantMessage
  if toolCalls.isEmpty then
    pure (#[], false)
  else
    let timestamp ← IO.monoMsNow
    let sequential := shouldRunToolsSequentially context toolCalls config
    if sequential then
      let mut results : Array AgentMessage := #[]
      let mut executedBatch : Array ExecutedToolCall := #[]
      for call in toolCalls do
        if ← isAborted signal then
          let abortResult : AgentToolResult :=
            { content := #[.text { text := requestAbortedMessage }]
              details := none
              terminate := true
            }
          let abortExecuted : ExecutedToolCall :=
            { toolCallId := call.id
              toolName := call.name
              args := call.arguments
              result := abortResult
              isError := true
            }
          let abortMsg := createToolResultMessage abortExecuted timestamp
          emit (.toolExecutionStart call.id call.name call.arguments)
          emit (.toolExecutionEnd call.id call.name abortResult true)
          emitToolResultMessage abortMsg emit
          results := results.push abortMsg
          executedBatch := executedBatch.push abortExecuted
          -- Pi stops scheduling further tools once aborted.
          break
        else
          let prepared ← prepareToolCall context assistantMessage call config signal
          let executed ← executePreparedToolCall prepared signal emit
          let finalized ← finalizeExecutedToolCall executed assistantMessage call context config
          let toolMsg := createToolResultMessage finalized timestamp
          emitToolResultMessage toolMsg emit
          results := results.push toolMsg
          executedBatch := executedBatch.push finalized
      pure (results, shouldTerminateExecutedBatch executedBatch)
    else
      -- Prepare all tool calls sequentially (hooks may have side effects)
      let mut preparedList : Array (LeanAgent.AI.ToolCall × PreparedToolCall) := #[]
      let mut aborted := false
      for call in toolCalls do
        if aborted then
          pure ()
        else if ← isAborted signal then
          aborted := true
        else
          let prepared ← prepareToolCall context assistantMessage call config signal
          preparedList := preparedList.push (call, prepared)
      if aborted then
        let mut abortMsgs := #[]
        let mut abortExecuted : Array ExecutedToolCall := #[]
        for call in toolCalls do
          let abortResult : AgentToolResult :=
            { content := #[.text { text := requestAbortedMessage }]
              details := none
              terminate := true
            }
          let abortEx : ExecutedToolCall :=
            { toolCallId := call.id
              toolName := call.name
              args := call.arguments
              result := abortResult
              isError := true
            }
          let abortMsg := createToolResultMessage abortEx timestamp
          emit (.toolExecutionStart call.id call.name call.arguments)
          emit (.toolExecutionEnd call.id call.name abortResult true)
          emitToolResultMessage abortMsg emit
          abortMsgs := abortMsgs.push abortMsg
          abortExecuted := abortExecuted.push abortEx
        pure (abortMsgs, shouldTerminateExecutedBatch abortExecuted)
      else
        -- Execute ready calls concurrently via IO.asTasks
        let mut taskRefs := #[]
        for (_, prepared) in preparedList do
          match prepared with
          | .immediate _ _ _ _ => pure ()
          | .ready _ _ _ _ =>
              let task ← IO.asTask (executePreparedToolCall prepared signal emit)
              taskRefs := taskRefs.push task
        let mut concurrentResults := #[]
        for task in taskRefs do
          match ← IO.wait task with
          | .ok result => concurrentResults := concurrentResults.push result
          | .error err =>
              concurrentResults := concurrentResults.push
                { toolCallId := "unknown"
                  toolName := "unknown"
                  args := Lean.Json.null
                  result :=
                    { content := #[.text { text := err.toString }]
                      details := none
                      terminate := false
                    }
                  isError := true
                }
        -- Merge immediate and concurrent results in source order
        let mut allResults : Array AgentMessage := #[]
        let mut executedBatch : Array ExecutedToolCall := #[]
        let mut concurrentIdx := 0
        for (call, prepared) in preparedList do
          match prepared with
          | .immediate _ _ _ _ =>
              let executed ← executePreparedToolCall prepared signal emit
              let finalized ← finalizeExecutedToolCall executed assistantMessage call context config
              let toolMsg := createToolResultMessage finalized timestamp
              emitToolResultMessage toolMsg emit
              allResults := allResults.push toolMsg
              executedBatch := executedBatch.push finalized
          | .ready _ _ _ _ =>
              if concurrentIdx < concurrentResults.size then
                let executed := concurrentResults[concurrentIdx]!
                concurrentIdx := concurrentIdx + 1
                let finalized ← finalizeExecutedToolCall executed assistantMessage call context config
                let toolMsg := createToolResultMessage finalized timestamp
                emitToolResultMessage toolMsg emit
                allResults := allResults.push toolMsg
                executedBatch := executedBatch.push finalized
        pure (allResults, shouldTerminateExecutedBatch executedBatch)

----------------------------------------------------------------------------
-- runLoop (shared inner loop)
----------------------------------------------------------------------------

/-- Poll steering messages from the loop config, if configured. -/
def pollSteeringMessages (config : AgentLoopConfig) : IO (Array AgentMessage) :=
  match config.getSteeringMessages with
  | some getMsgs => getMsgs
  | none => pure #[]

/-- Poll follow-up messages from the loop config, if configured. -/
def pollFollowUpMessages (config : AgentLoopConfig) : IO (Array AgentMessage) :=
  match config.getFollowUpMessages with
  | some getMsgs => getMsgs
  | none => pure #[]

/-- Apply an optional prepareNextTurn update to context/config. -/
def applyTurnUpdate
    (ctx : AgentContext)
    (cfg : AgentLoopConfig)
    (update : Option AgentLoopTurnUpdate) : AgentContext × AgentLoopConfig :=
  match update with
  | none => (ctx, cfg)
  | some turnUpdate =>
      let nextCtx := turnUpdate.context.getD ctx
      let nextCfg :=
        match turnUpdate.model, turnUpdate.thinkingLevel with
        | some m, some (.level tl) => { cfg with model := m, reasoning := some tl }
        | some m, some .off => { cfg with model := m, reasoning := none }
        | some m, none => { cfg with model := m }
        | none, some (.level tl) => { cfg with reasoning := some tl }
        | none, some .off => { cfg with reasoning := none }
        | none, none => cfg
      (nextCtx, nextCfg)

/--
Shared loop: processes tool calls, steering messages, and follow-up messages.

Aligned with Pi `packages/agent/src/agent-loop.ts` `runLoop`:
1. Initial steering poll (may be skipped once via Agent.createLoopConfig)
2. Inject pending messages, stream, execute tools, emit turn_end
3. prepareNextTurn, then optional shouldStopAfterTurn early exit
4. Post-turn steering poll; continue while tools remain or steering is pending
5. When idle, poll follow-ups; if any, inject and continue; else stop
-/
partial def runLoop
    (initialContext : AgentContext)
    (newMessages : Array AgentMessage)
    (initialConfig : AgentLoopConfig)
    (signal : Option AbortSignal)
    (emit : AgentEventSink)
    (streamFn : StreamFn) :
    IO AgentContext := do
  let context := { initialContext with messages := initialContext.messages ++ newMessages }
  -- Pi: first steering poll before the first turn (user may have typed while waiting).
  let initialPending ← pollSteeringMessages initialConfig
  -- Pi `firstTurn`: runAgentLoop already emitted turn_start before entering runLoop.
  let rec loop
      (ctx : AgentContext)
      (cfg : AgentLoopConfig)
      (pending : Array AgentMessage)
      (firstTurn : Bool) : IO AgentContext := do
    if ← isAborted signal then
      pure ctx
    else
      -- Inject pending steering/follow-up messages before the next assistant response.
      let ctx :=
        if pending.isEmpty then
          ctx
        else
          { ctx with messages := ctx.messages ++ pending }
      if !firstTurn then
        emit .turnStart
      let assistantMsg ← streamAssistantResponse ctx cfg signal emit streamFn
      let ctx := { ctx with messages := ctx.messages.push assistantMsg }
      let (toolResults, terminate) ← executeToolCalls ctx assistantMsg cfg signal emit
      let ctx := { ctx with messages := ctx.messages ++ toolResults }
      emit (.turnEnd assistantMsg toolResults)
      -- prepareNextTurn (Pi applies this before shouldStop / next steering poll)
      let (ctx, cfg) ←
        match cfg.prepareNextTurn with
        | some hook => do
            let prepCtx : PrepareNextTurnContext :=
              { message := assistantMsg
                toolResults := toolResults
                context := ctx
                newMessages := newMessages
              }
            let update ← hook prepCtx
            pure (applyTurnUpdate ctx cfg update)
        | none => pure (ctx, cfg)
      -- Explicit shouldStopAfterTurn early-exits without draining remaining queues.
      let forceStop ←
        match cfg.shouldStopAfterTurn with
        | some hook =>
            hook
              { message := assistantMsg
                toolResults := toolResults
                context := ctx
                newMessages := newMessages
              }
        | none => pure false
      if forceStop then
        pure ctx
      else
        let hasMoreToolCalls := !toolResults.isEmpty && !terminate
        -- Pi always re-polls steering after each completed turn.
        let nextPending ← pollSteeringMessages cfg
        if hasMoreToolCalls || !nextPending.isEmpty then
          loop ctx cfg nextPending false
        else
          let followUps ← pollFollowUpMessages cfg
          if followUps.isEmpty then
            pure ctx
          else
            -- Follow-ups become pending so the next iteration injects them before streaming.
            loop ctx cfg followUps false
  loop context initialConfig initialPending true

----------------------------------------------------------------------------
-- runAgentLoop
----------------------------------------------------------------------------

/--
Start a new agent loop with the given prompts. Appends prompts to context
messages, emits agentStart/turnStart/messageStart/messageEnd for each prompt,
then enters the shared runLoop.
-/
def runAgentLoop
    (prompts : Array AgentMessage)
    (context : AgentContext)
    (config : AgentLoopConfig)
    (emit : AgentEventSink)
    (signal : Option AbortSignal := none)
    (streamFn : StreamFn := defaultStreamFn) :
    IO (Array AgentMessage) := do
  emit .agentStart
  -- Emit turnStart and message events for each prompt
  emit .turnStart
  for prompt in prompts do
    emit (.messageStart prompt)
    emit (.messageEnd prompt)
  -- Run the loop
  let finalCtx ← runLoop context prompts config signal emit streamFn
  -- Emit agentEnd with final messages
  emit (.agentEnd finalCtx.messages)
  pure finalCtx.messages

----------------------------------------------------------------------------
-- runAgentLoopContinue
----------------------------------------------------------------------------

/--
Continue an existing agent loop. Validates that the last message is not an
assistant message, emits agentStart/turnStart, then enters the shared runLoop.
-/
def runAgentLoopContinue
    (context : AgentContext)
    (config : AgentLoopConfig)
    (emit : AgentEventSink)
    (signal : Option AbortSignal := none)
    (streamFn : StreamFn := defaultStreamFn) :
    IO (Array AgentMessage) := do
  -- Validate last message is not assistant
  match context.messages.back? with
  | none => throw (IO.userError "cannot continue an empty context")
  | some lastMsg =>
      match lastMsg with
      | .ofMessage (.assistant _) =>
          throw (IO.userError "cannot continue after an assistant message; add a new prompt first")
      | _ => pure ()
  emit .agentStart
  emit .turnStart
  -- Run the loop with no new prompts
  let finalCtx ← runLoop context #[] config signal emit streamFn
  emit (.agentEnd finalCtx.messages)
  pure finalCtx.messages

end LeanAgent.Agent
