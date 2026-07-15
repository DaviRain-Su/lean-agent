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
  listeners : Array AgentListener := #[]
  nextListenerId : Nat := 0
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

/--
Subscribe a listener to agent events. Returns the updated agent and a handle
for `unsubscribe` (Pi `subscribe` → disposer).
-/
def Agent.subscribe
    (agent : Agent)
    (listener : AgentEvent → Option AbortSignal → IO Unit) :
    Agent × ListenerHandle :=
  let handle : ListenerHandle := { id := agent.nextListenerId }
  let entry : AgentListener := { id := handle.id, callback := listener }
  ({ agent with
      listeners := agent.listeners.push entry
      nextListenerId := agent.nextListenerId + 1
    }, handle)

/-- Remove a previously registered listener by handle. -/
def Agent.unsubscribe (agent : Agent) (handle : ListenerHandle) : Agent :=
  { agent with listeners := agent.listeners.filter fun l => l.id != handle.id }

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

/--
Drain steering messages from the live agent ref, writing the reduced queue back.
Matches Pi's mutable `steeringQueue.drain()` semantics.
-/
def Agent.drainSteeringMessages (agentRef : IO.Ref Agent) : IO (Array AgentMessage) := do
  let current ← agentRef.get
  let (msgs, nextQueue) := current.steeringQueue.drain
  agentRef.set { current with steeringQueue := nextQueue }
  pure msgs

/--
Drain follow-up messages from the live agent ref, writing the reduced queue back.
Matches Pi's mutable `followUpQueue.drain()` semantics.
-/
def Agent.drainFollowUpMessages (agentRef : IO.Ref Agent) : IO (Array AgentMessage) := do
  let current ← agentRef.get
  let (msgs, nextQueue) := current.followUpQueue.drain
  agentRef.set { current with followUpQueue := nextQueue }
  pure msgs

/--
Create an AgentLoopConfig bound to a live `IO.Ref Agent`.

Queue drains must update the ref so subsequent polls and the returned agent keep
the reduced queues (Pi class fields are mutable; Lean values are not).

When `skipInitialSteeringPoll` is true, the first steering poll returns `[]`
and later polls drain normally — matching Pi `createLoopConfig({ skipInitialSteeringPoll })`.
-/
def Agent.createLoopConfig
    (agentRef : IO.Ref Agent)
    (skipInitialSteeringPoll : Bool) : IO AgentLoopConfig := do
  let agent ← agentRef.get
  let skipRef ← IO.mkRef skipInitialSteeringPoll
  pure
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
        some (do
          let skip ← skipRef.get
          if skip then
            skipRef.set false
            pure #[]
          else
            Agent.drainSteeringMessages agentRef)
      getFollowUpMessages :=
        some (Agent.drainFollowUpMessages agentRef)
      toolExecution := agent.toolExecution
      reasoning := modelThinkingLevelToOption agent.state.thinkingLevel
      thinkingBudgets := agent.thinkingBudgets
      transport := some agent.transport
      sessionId := agent.sessionId
      maxRetryDelayMs := agent.maxRetryDelayMs
    }

/-- True when a run is currently active (Pi rejects nested `prompt`/`continue`). -/
def Agent.isBusy (agent : Agent) : Bool :=
  agent.activeRun.isSome || agent.state.isStreaming

def Agent.throwIfBusy (agent : Agent) (message : String) : IO Unit := do
  if agent.isBusy then
    throw (IO.userError message)

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
    listener.callback event signal
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
def Agent.runWithLifecycle
    (agent : Agent)
    (executor : Agent → Option AbortSignal → IO Agent) : IO Agent := do
  let abortRef ← IO.mkRef false
  let signal : AbortSignal :=
    { isAborted := abortRef.get
      message := "Run was aborted"
    }
  let runningAgent := { agent with activeRun := some { abortRef := abortRef } }
  try
    let agent ← executor runningAgent (some signal)
    pure (agent.finishRun)
  catch err =>
    let isAborted ← abortRef.get
    runningAgent.handleRunFailure err.toString isAborted

----------------------------------------------------------------------------
-- Agent.promptMessages (defined before prompt to avoid forward reference)
----------------------------------------------------------------------------

/--
Run the agent loop with the given prompt messages, bound to a live agent ref
so steering/follow-up drains persist.
-/
def Agent.runPromptMessages
    (agent : Agent)
    (messages : Array AgentMessage)
    (skipInitialSteeringPoll : Bool := false) : IO Agent := do
  agent.throwIfBusy
    "Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion."
  agent.runWithLifecycle fun runningAgent signal => do
    let agentRef ← IO.mkRef runningAgent
    let context := runningAgent.createContextSnapshot
    let config ← Agent.createLoopConfig agentRef skipInitialSteeringPoll
    let streamFn := runningAgent.streamFn
    let emit : AgentEventSink := fun event => do
      let current ← agentRef.get
      let updated ← current.processEvents event
      agentRef.set updated
    let finalMessages ← runAgentLoop messages context config emit signal streamFn
    let current ← agentRef.get
    pure { current with state := { current.state with messages := finalMessages } }

/--
Send an array of AgentMessages as prompts to the agent.
-/
def Agent.promptMessages (agent : Agent) (messages : Array AgentMessage) : IO Agent :=
  Agent.runPromptMessages agent messages false

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
Send a single AgentMessage prompt (Pi `prompt(message)` overload).
-/
def Agent.promptMessage (agent : Agent) (message : AgentMessage) : IO Agent :=
  Agent.promptMessages agent #[message]

/--
Continue the agent from its current state.

Aligns with Pi `Agent.continue`:
- empty transcript → error
- last message is assistant → drain one-at-a-time/all steering, else follow-ups;
  if both empty → error
- otherwise continue the loop from the current transcript
-/
def Agent.continue (agent : Agent) : IO Agent := do
  agent.throwIfBusy
    "Agent is already processing. Wait for completion before continuing."
  match agent.state.messages.back? with
  | none => throw (IO.userError "cannot continue an empty session")
  | some (.ofMessage (.assistant _)) =>
      -- Pi: resume from assistant tail via queued steering, then follow-ups.
      let agentRef ← IO.mkRef agent
      let steering ← Agent.drainSteeringMessages agentRef
      if !steering.isEmpty then
        let agent ← agentRef.get
        Agent.runPromptMessages agent steering (skipInitialSteeringPoll := true)
      else
        let followUps ← Agent.drainFollowUpMessages agentRef
        if followUps.isEmpty then
          throw (IO.userError
            "cannot continue after an assistant message; add a new prompt first")
        else
          let agent ← agentRef.get
          Agent.runPromptMessages agent followUps false
  | some _ =>
      agent.runWithLifecycle fun runningAgent signal => do
        let agentRef ← IO.mkRef runningAgent
        let context := runningAgent.createContextSnapshot
        let config ← Agent.createLoopConfig agentRef false
        let streamFn := runningAgent.streamFn
        let emit : AgentEventSink := fun event => do
          let current ← agentRef.get
          let updated ← current.processEvents event
          agentRef.set updated
        let finalMessages ← runAgentLoopContinue context config emit signal streamFn
        let current ← agentRef.get
        pure { current with state := { current.state with messages := finalMessages } }

end LeanAgent.Agent
