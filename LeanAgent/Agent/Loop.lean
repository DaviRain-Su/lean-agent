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
Execute all tool calls from an assistant message. Returns the tool result
messages and a `terminate` flag.
-/
def executeToolCalls
    (context : AgentContext)
    (assistantMessage : AgentMessage)
    (config : AgentLoopConfig)
    (signal : Option AbortSignal)
    (emit : AgentEventSink) :
    IO (Array AgentMessage × Bool) := do
  -- Extract tool calls from the assistant message
  let toolCalls ←
    match assistantMessage with
    | .ofMessage (.assistant msg) =>
        pure (msg.content.filterMap fun block =>
          match block with
          | .toolCall call => some call
          | _ => none
        )
    | _ => pure #[]
  if toolCalls.isEmpty then
    pure (#[], false)
  else
    let timestamp ← IO.monoMsNow
    match config.toolExecution with
    | .sequential =>
        let mut results := #[]
        let mut terminate := false
        for call in toolCalls do
          if terminate then
            pure ()
          else if ← isAborted signal then
            let abortResult : AgentToolResult :=
              { content := #[.text { text := requestAbortedMessage }]
                details := none
                terminate := true
              }
            let abortMsg := createToolResultMessage
              { toolCallId := call.id, toolName := call.name, args := call.arguments, result := abortResult, isError := true }
              timestamp
            results := results.push abortMsg
            terminate := true
          else
            let prepared ← prepareToolCall context assistantMessage call config signal
            let executed ← executePreparedToolCall prepared signal emit
            let finalized ← finalizeExecutedToolCall executed assistantMessage call context config
            let toolMsg := createToolResultMessage finalized timestamp
            results := results.push toolMsg
            if finalized.result.terminate then
              terminate := true
        pure (results, terminate)
    | .parallel =>
        -- Prepare all tool calls sequentially (hooks may have side effects)
        let mut preparedList := #[]
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
          -- All calls aborted
          let mut abortMsgs := #[]
          for call in toolCalls do
            let abortResult : AgentToolResult :=
              { content := #[.text { text := requestAbortedMessage }]
                details := none
                terminate := true
              }
            let abortMsg := createToolResultMessage
              { toolCallId := call.id, toolName := call.name, args := call.arguments, result := abortResult, isError := true }
              timestamp
            abortMsgs := abortMsgs.push abortMsg
          pure (abortMsgs, true)
        else
          -- Execute ready calls concurrently via IO.asTasks
          let mut taskRefs := #[]
          for (call, prepared) in preparedList do
            match prepared with
            | .immediate _ _ _ _ => pure ()
            | .ready _ _ _ _ =>
                let task ← IO.asTask (executePreparedToolCall prepared signal emit)
                taskRefs := taskRefs.push task
          -- Wait for all concurrent tasks
          let mut concurrentResults := #[]
          for task in taskRefs do
            match ← IO.wait task with
            | .ok result => concurrentResults := concurrentResults.push result
            | .error err =>
                let errorResult : ExecutedToolCall :=
                  { toolCallId := "unknown"
                    toolName := "unknown"
                    args := Lean.Json.null
                    result := { content := #[.text { text := err.toString }], details := none, terminate := false }
                    isError := true
                  }
                concurrentResults := concurrentResults.push errorResult
          -- Merge immediate and concurrent results in source order
          let mut allResults := #[]
          let mut terminate := false
          let mut concurrentIdx := 0
          for (call, prepared) in preparedList do
            if terminate then
              pure ()
            else
              match prepared with
              | .immediate _ _ _ _ =>
                  let executed ← executePreparedToolCall prepared signal emit
                  let finalized ← finalizeExecutedToolCall executed assistantMessage call context config
                  let toolMsg := createToolResultMessage finalized timestamp
                  allResults := allResults.push toolMsg
                  if finalized.result.terminate then
                    terminate := true
              | .ready _ _ _ _ =>
                  if concurrentIdx < concurrentResults.size then
                    let executed := concurrentResults[concurrentIdx]!
                    concurrentIdx := concurrentIdx + 1
                    let finalized ← finalizeExecutedToolCall executed assistantMessage call context config
                    let toolMsg := createToolResultMessage finalized timestamp
                    allResults := allResults.push toolMsg
                    if finalized.result.terminate then
                      terminate := true
          pure (allResults, terminate)

----------------------------------------------------------------------------
-- runLoop (shared inner loop)
----------------------------------------------------------------------------

/--
Shared inner loop: processes tool calls, steering messages, and follow-up
messages. Continues until the model produces a response without tool calls
and no follow-up messages are queued. Returns the final AgentContext.
-/
partial def runLoop
    (initialContext : AgentContext)
    (newMessages : Array AgentMessage)
    (initialConfig : AgentLoopConfig)
    (signal : Option AbortSignal)
    (emit : AgentEventSink)
    (streamFn : StreamFn) :
    IO AgentContext := do
  let mut context := initialContext
  let mut config := initialConfig
  -- Append new messages to context
  context := { context with messages := context.messages ++ newMessages }
  -- Outer loop: continues when follow-up messages arrive after agent would stop
  let rec outerLoop (ctx : AgentContext) (cfg : AgentLoopConfig) : IO AgentContext := do
    if ← isAborted signal then
      pure ctx
    else
      -- Inner loop: processes tool calls and steering messages
      let rec innerLoop (innerCtx : AgentContext) (innerCfg : AgentLoopConfig) : IO AgentContext := do
        if ← isAborted signal then
          pure innerCtx
        else
          -- Poll steering messages
          let steeringMessages ←
            match innerCfg.getSteeringMessages with
            | some getMsgs => getMsgs
            | none => pure #[]
          let innerCtx :=
            if steeringMessages.isEmpty then
              innerCtx
            else
              { innerCtx with messages := innerCtx.messages ++ steeringMessages }
          -- Stream assistant response
          emit .turnStart
          let assistantMsg ← streamAssistantResponse innerCtx innerCfg signal emit streamFn
          let innerCtx := { innerCtx with messages := innerCtx.messages.push assistantMsg }
          -- Execute tool calls
          let (toolResults, terminate) ← executeToolCalls innerCtx assistantMsg innerCfg signal emit
          let innerCtx := { innerCtx with messages := innerCtx.messages ++ toolResults }
          -- Emit turnEnd
          emit (.turnEnd assistantMsg toolResults)
          -- Check shouldStopAfterTurn hook
          let shouldStop ←
            match innerCfg.shouldStopAfterTurn with
            | some hook =>
                let stopCtx : ShouldStopAfterTurnContext :=
                  { message := assistantMsg
                    toolResults := toolResults
                    context := innerCtx
                    newMessages := newMessages
                  }
                hook stopCtx
            | none => pure (toolResults.isEmpty && !terminate)
          if shouldStop then
            -- Check prepareNextTurn hook
            match innerCfg.prepareNextTurn with
            | some hook =>
                let prepCtx : PrepareNextTurnContext :=
                  { message := assistantMsg
                    toolResults := toolResults
                    context := innerCtx
                    newMessages := newMessages
                  }
                let update ← hook prepCtx
                match update with
                | some turnUpdate =>
                    let nextCtx := turnUpdate.context.getD innerCtx
                    let nextCfg :=
                      match turnUpdate.model, turnUpdate.thinkingLevel with
                      | some m, some (.level tl) => { innerCfg with model := m, reasoning := some tl }
                      | some m, some .off => { innerCfg with model := m, reasoning := none }
                      | some m, none => { innerCfg with model := m }
                      | none, some (.level tl) => { innerCfg with reasoning := some tl }
                      | none, some .off => { innerCfg with reasoning := none }
                      | none, none => innerCfg
                    -- Poll follow-up messages
                    let followUpMessages ←
                      match nextCfg.getFollowUpMessages with
                      | some getMsgs => getMsgs
                      | none => pure #[]
                    if followUpMessages.isEmpty then
                      pure innerCtx
                    else
                      let nextCtx := { nextCtx with messages := nextCtx.messages ++ followUpMessages }
                      outerLoop nextCtx nextCfg
                | none => pure innerCtx
            | none => pure innerCtx
          else
            -- Continue inner loop with tool results
            innerLoop innerCtx innerCfg
      innerLoop ctx cfg
  outerLoop context config

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
