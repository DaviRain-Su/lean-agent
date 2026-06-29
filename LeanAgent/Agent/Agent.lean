import LeanAgent.Agent.Types
import LeanAgent.Agent.Loop
import LeanAgent.AI.Compat
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Abort
import LeanAgent.Models

namespace LeanAgent.Agent

open LeanAgent.AI
open LeanAgent.AI.Util.Abort

----------------------------------------------------------------------------
-- ActiveRun
----------------------------------------------------------------------------

/--
Tracks an active agent run, including an abort reference.
-/
structure ActiveRun where
  abortRef : IO.Ref Bool
  abortMessage : String := "Run was aborted"

----------------------------------------------------------------------------
-- Agent
----------------------------------------------------------------------------

/--
Stateful agent wrapper. All methods return an updated `Agent` value
(functional update — Lean structures are immutable).
-/
structure Agent where
  state : AgentState
  listeners : Array (AgentEvent → Option AbortSignal → IO Unit) := #[]
  steeringQueue : PendingMessageQueue := { mode := .oneAtATime }
  followUpQueue : PendingMessageQueue := { mode := .oneAtATime }
  convertToLlm : AgentMessage → Option LeanAgent.AI.Message := defaultConvertToLlm
  transformContext : Option (Array AgentMessage → IO (Array AgentMessage)) := none
  streamFn : StreamFn := defaultStreamFn
  getApiKey : Option (String → IO (Option String)) := none
  onPayload : Option LeanAgent.AI.PayloadHook := none
  onResponse : Option LeanAgent.AI.ResponseHook := none
  beforeToolCall : Option (BeforeToolCallContext → IO (Option BeforeToolCallResult)) := none
  afterToolCall : Option (AfterToolCallContext → IO (Option AfterToolCallResult)) := none
  prepareNextTurn : Option (PrepareNextTurnContext → IO (Option AgentLoopTurnUpdate)) := none
  sessionId : Option String := none
  thinkingBudgets : Option LeanAgent.AI.ThinkingBudgets := none
  transport : LeanAgent.AI.Transport := .auto
  maxRetryDelayMs : Option Nat := none
  toolExecution : ToolExecutionMode := .parallel
  activeRun : Option ActiveRun := none

----------------------------------------------------------------------------
-- AgentOptions
----------------------------------------------------------------------------

/--
Options for creating an Agent.
-/
structure AgentOptions where
  initialState : AgentState := default
  convertToLlm : AgentMessage → Option LeanAgent.AI.Message := defaultConvertToLlm
  transformContext : Option (Array AgentMessage → IO (Array AgentMessage)) := none
  streamFn : StreamFn := defaultStreamFn
  getApiKey : Option (String → IO (Option String)) := none
  onPayload : Option LeanAgent.AI.PayloadHook := none
  onResponse : Option LeanAgent.AI.ResponseHook := none
  beforeToolCall : Option (BeforeToolCallContext → IO (Option BeforeToolCallResult)) := none
  afterToolCall : Option (AfterToolCallContext → IO (Option AfterToolCallResult)) := none
  prepareNextTurn : Option (PrepareNextTurnContext → IO (Option AgentLoopTurnUpdate)) := none
  steeringMode : QueueMode := .oneAtATime
  followUpMode : QueueMode := .oneAtATime
  sessionId : Option String := none
  thinkingBudgets : Option LeanAgent.AI.ThinkingBudgets := none
  transport : LeanAgent.AI.Transport := .auto
  maxRetryDelayMs : Option Nat := none
  toolExecution : ToolExecutionMode := .parallel

instance : Inhabited AgentOptions where
  default :=
    { initialState := default
      convertToLlm := defaultConvertToLlm
      streamFn := defaultStreamFn
    }

----------------------------------------------------------------------------
-- Agent.create
----------------------------------------------------------------------------

def Agent.create (options : AgentOptions := default) : Agent :=
  { state := options.initialState
    convertToLlm := options.convertToLlm
    transformContext := options.transformContext
    streamFn := options.streamFn
    getApiKey := options.getApiKey
    onPayload := options.onPayload
    onResponse := options.onResponse
    beforeToolCall := options.beforeToolCall
    afterToolCall := options.afterToolCall
    prepareNextTurn := options.prepareNextTurn
    steeringQueue := { mode := options.steeringMode }
    followUpQueue := { mode := options.followUpMode }
    sessionId := options.sessionId
    thinkingBudgets := options.thinkingBudgets
    transport := options.transport
    maxRetryDelayMs := options.maxRetryDelayMs
    toolExecution := options.toolExecution
  }

----------------------------------------------------------------------------
-- Agent methods (functional update)
----------------------------------------------------------------------------

/-- Subscribe a listener to agent events. -/
def Agent.subscribe (agent : Agent) (listener : AgentEvent → Option AbortSignal → IO Unit) : Agent :=
  { agent with listeners := agent.listeners.push listener }

/-- Add a steering message to the queue. -/
def Agent.steer (agent : Agent) (message : AgentMessage) : Agent :=
  { agent with steeringQueue := agent.steeringQueue.enqueue message }

/-- Add a follow-up message to the queue. -/
def Agent.followUp (agent : Agent) (message : AgentMessage) : Agent :=
  { agent with followUpQueue := agent.followUpQueue.enqueue message }

/-- Clear the steering queue. -/
def Agent.clearSteeringQueue (agent : Agent) : Agent :=
  { agent with steeringQueue := agent.steeringQueue.clear }

/-- Clear the follow-up queue. -/
def Agent.clearFollowUpQueue (agent : Agent) : Agent :=
  { agent with followUpQueue := agent.followUpQueue.clear }

/-- Clear all queues. -/
def Agent.clearAllQueues (agent : Agent) : Agent :=
  { agent with
    steeringQueue := agent.steeringQueue.clear
    followUpQueue := agent.followUpQueue.clear
  }

/-- Check if any queue has pending messages. -/
def Agent.hasQueuedMessages (agent : Agent) : Bool :=
  agent.steeringQueue.hasItems || agent.followUpQueue.hasItems

/-- Abort the active run. -/
def Agent.abort (agent : Agent) : IO Unit := do
  match agent.activeRun with
  | some run => run.abortRef.set true
  | none => pure ()

/-- Reset the agent: clear transcript, queues, and streaming state. -/
def Agent.reset (agent : Agent) : Agent :=
  { agent with
    state := { agent.state with
      messages := #[]
      isStreaming := false
      streamingMessage := none
      pendingToolCalls := #[]
      errorMessage := none
    }
    steeringQueue := agent.steeringQueue.clear
    followUpQueue := agent.followUpQueue.clear
  }

----------------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------------

/-- Create an AgentContext snapshot from the current agent state. -/
def Agent.createContextSnapshot (agent : Agent) : AgentContext :=
  { systemPrompt := agent.state.systemPrompt
    messages := agent.state.messages
    tools := agent.state.tools
  }

/-- Convert ModelThinkingLevel to Option ThinkingLevel for AgentLoopConfig. -/
def modelThinkingLevelToOption (level : LeanAgent.AI.ModelThinkingLevel) : Option LeanAgent.AI.ThinkingLevel :=
  match level with
  | .off => none
  | .level l => some l

/-- Create an AgentLoopConfig from the current agent configuration. -/
def Agent.createLoopConfig (agent : Agent) (skipInitialSteeringPoll : Bool) : AgentLoopConfig :=
  { model := agent.state.model
    convertToLlm := agent.convertToLlm
    transformContext := agent.transformContext
    getApiKey := agent.getApiKey
    onPayload := agent.onPayload
    onResponse := agent.onResponse
    beforeToolCall := agent.beforeToolCall
    afterToolCall := agent.afterToolCall
    shouldStopAfterTurn := none
    prepareNextTurn := agent.prepareNextTurn
    getSteeringMessages :=
      if skipInitialSteeringPoll then
        none
      else
        some (do
          let (msgs, _) := agent.steeringQueue.drain
          pure msgs)
    getFollowUpMessages :=
      some (do
        let (msgs, _) := agent.followUpQueue.drain
        pure msgs)
    toolExecution := agent.toolExecution
    reasoning := modelThinkingLevelToOption agent.state.thinkingLevel
    thinkingBudgets := agent.thinkingBudgets
    transport := some agent.transport
    sessionId := agent.sessionId
    maxRetryDelayMs := agent.maxRetryDelayMs
  }

/-- Process an agent event: update state and notify listeners. -/
def Agent.processEvents (agent : Agent) (event : AgentEvent) : IO Agent := do
  let mut agent := agent
  -- Update state based on event
  match event with
  | .agentStart =>
      agent := { agent with state := { agent.state with isStreaming := true, errorMessage := none } }
  | .agentEnd _ =>
      agent := { agent with state := { agent.state with isStreaming := false, streamingMessage := none } }
  | .turnStart => pure ()
  | .turnEnd _ _ => pure ()
  | .messageStart msg =>
      agent := { agent with state := { agent.state with streamingMessage := some msg } }
  | .messageUpdate msg _ =>
      agent := { agent with state := { agent.state with streamingMessage := some msg } }
  | .messageEnd msg =>
      agent := { agent with
        state := { agent.state with
          messages := agent.state.messages.push msg
          streamingMessage := none
        }
      }
  | .toolExecutionStart toolCallId _ _ =>
      agent := { agent with state := { agent.state with pendingToolCalls := agent.state.pendingToolCalls.push toolCallId } }
  | .toolExecutionUpdate _ _ _ _ => pure ()
  | .toolExecutionEnd toolCallId _ _ _ =>
      agent := { agent with
        state := { agent.state with
          pendingToolCalls := agent.state.pendingToolCalls.filter (fun id => id != toolCallId)
        }
      }
  -- Notify listeners
  let signal ←
    match agent.activeRun with
    | some run =>
        let aborted ← run.abortRef.get
        pure (some { isAborted := pure aborted, message := run.abortMessage } : Option AbortSignal)
    | none => pure none
  for listener in agent.listeners do
    listener event signal
  pure agent

/-- Handle a run failure: set error message and clean up. -/
def Agent.handleRunFailure (agent : Agent) (errorMessage : String) (aborted : Bool) : IO Agent := do
  let stopReason : StopReason := if aborted then .aborted else .error
  let timestamp ← IO.monoMsNow
  let errorMsg : LeanAgent.AI.AssistantMessage :=
    { content := #[.text { text := errorMessage }]
      api := agent.state.model.api
      provider := agent.state.model.provider
      model := agent.state.model.id
      stopReason := stopReason
      errorMessage := some errorMessage
      timestamp := timestamp
    }
  let agentMsg := AgentMessage.ofMessage (.assistant errorMsg)
  let agent := { agent with
    state := { agent.state with
      messages := agent.state.messages.push agentMsg
      isStreaming := false
      streamingMessage := none
      errorMessage := some errorMessage
    }
    activeRun := none
  }
  pure agent

/-- Finish a run: clear activeRun. -/
def Agent.finishRun (agent : Agent) : Agent :=
  { agent with activeRun := none }

/-- Run with lifecycle management: create abort ref, set activeRun, execute, clean up. -/
def Agent.runWithLifecycle (agent : Agent) (executor : Option AbortSignal → IO Agent) : IO Agent := do
  let abortRef ← IO.mkRef false
  let signal : AbortSignal :=
    { isAborted := abortRef.get
      message := "Run was aborted"
    }
  let agent := { agent with activeRun := some { abortRef := abortRef } }
  try
    let agent ← executor (some signal)
    pure (agent.finishRun)
  catch err =>
    let isAborted ← abortRef.get
    agent.handleRunFailure err.toString isAborted

----------------------------------------------------------------------------
-- Agent.promptMessages (defined before prompt to avoid forward reference)
----------------------------------------------------------------------------

/--
Send an array of AgentMessages as prompts to the agent.
-/
def Agent.promptMessages (agent : Agent) (messages : Array AgentMessage) : IO Agent :=
  agent.runWithLifecycle fun signal => do
    let context := agent.createContextSnapshot
    let config := agent.createLoopConfig false
    let emit : AgentEventSink := fun _ => pure ()
    -- Run the loop
    let finalMessages ← runAgentLoop messages context config emit signal agent.streamFn
    -- Update agent state with final messages
    let agent := { agent with
      state := { agent.state with messages := finalMessages }
    }
    pure agent

/--
Send a text prompt to the agent. Normalizes the input to an AgentMessage
and delegates to `promptMessages`.
-/
def Agent.prompt (agent : Agent) (input : String) : IO Agent := do
  let timestamp ← IO.monoMsNow
  let userMsg : LeanAgent.AI.UserMessage :=
    { content := #[.text { text := input }]
      timestamp := timestamp
    }
  let agentMsg := AgentMessage.ofMessage (.user userMsg)
  Agent.promptMessages agent #[agentMsg]

/--
Continue the agent from its current state. Validates that the last message
is not an assistant message.
-/
def Agent.continue (agent : Agent) : IO Agent := do
  -- Validate last message
  match agent.state.messages.back? with
  | none => throw (IO.userError "cannot continue an empty session")
  | some lastMsg =>
      match lastMsg with
      | .ofMessage (.assistant _) =>
          throw (IO.userError "cannot continue after an assistant message; add a new prompt first")
      | _ => pure ()
  agent.runWithLifecycle fun signal => do
    let context := agent.createContextSnapshot
    let config := agent.createLoopConfig true
    let emit : AgentEventSink := fun _ => pure ()
    let finalMessages ← runAgentLoopContinue context config emit signal agent.streamFn
    let agent := { agent with
      state := { agent.state with messages := finalMessages }
    }
    pure agent

end LeanAgent.Agent
