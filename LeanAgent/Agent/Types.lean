import LeanAgent.AI.Types
import LeanAgent.AI.Util.Abort
import LeanAgent.Models

namespace LeanAgent.Agent

/-!
Pi-compatible agent-level types. These wrap `LeanAgent.AI.Types` (Message, ContentBlock,
AssistantMessageEvent, etc.) and add agent-specific concepts: hooks, queues, tool execution
modes, and agent state.
-/

----------------------------------------------------------------------------
-- AgentMessage
----------------------------------------------------------------------------

/--
Agent-level message that wraps `LeanAgent.AI.Message` (user/assistant/toolResult)
and adds a `custom` escape hatch for agent-internal messages (bashExecution,
branchSummary, compactionSummary, etc.).
-/
inductive AgentMessage where
  | ofMessage (message : LeanAgent.AI.Message)
  | custom (customType : String) (content : Array LeanAgent.AI.ContentBlock) (display : Bool) (timestamp : Nat)
deriving BEq, Inhabited

namespace AgentMessage

def role : AgentMessage → String
  | .ofMessage msg =>
      match msg with
      | .user _ => "user"
      | .assistant _ => "assistant"
      | .toolResult _ => "toolResult"
  | .custom _ _ _ _ => "custom"

def timestamp : AgentMessage → Nat
  | .ofMessage msg =>
      match msg with
      | .user m => m.timestamp
      | .assistant m => m.timestamp
      | .toolResult m => m.timestamp
  | .custom _ _ _ ts => ts

def toAI? : AgentMessage → Option LeanAgent.AI.Message
  | .ofMessage msg => some msg
  | .custom _ _ _ _ => none

def fromAI (message : LeanAgent.AI.Message) : AgentMessage :=
  .ofMessage message

end AgentMessage

----------------------------------------------------------------------------
-- AgentToolResult and AgentTool
----------------------------------------------------------------------------

inductive ToolExecutionMode where
  | sequential
  | parallel
deriving BEq, Repr

/--
Pi-compatible tool result. `content` is an array of `ContentBlock` (text, thinking,
image, toolCall). `details` carries tool-specific metadata. `terminate` signals
the agent loop to stop.
-/
structure AgentToolResult where
  content : Array LeanAgent.AI.ContentBlock
  details : Option Lean.Json := none
  terminate : Bool := false
deriving Inhabited

namespace AgentToolResult

def isError (result : AgentToolResult) : Bool :=
  result.content.any fun block =>
    match block with
    | .text t => t.text.contains "Error" || t.text.contains "error"
    | _ => false

def text (result : AgentToolResult) : String :=
  String.intercalate "\n" (result.content.filterMap fun block =>
    match block with
    | .text t => some t.text
    | _ => none
  ).toList

end AgentToolResult

/--
Pi-compatible tool definition. `execute` receives the tool call id, validated
parameters, an optional abort signal, and an optional update callback for
streaming partial results.
-/
structure AgentTool where
  name : String
  description : String
  parameters : Lean.Json
  label : String
  prepareArguments : Option (Lean.Json → Lean.Json) := none
  execute :
    String → Lean.Json → Option LeanAgent.AI.Util.Abort.AbortSignal →
      Option (AgentToolResult → IO Unit) → IO AgentToolResult
  executionMode : Option ToolExecutionMode := none

----------------------------------------------------------------------------
-- AgentContext and AgentState
----------------------------------------------------------------------------

structure AgentContext where
  systemPrompt : String
  messages : Array AgentMessage
  tools : Array AgentTool := #[]

structure AgentState where
  systemPrompt : String
  model : LeanAgent.Models.ModelInfo
  thinkingLevel : LeanAgent.AI.ModelThinkingLevel := .off
  tools : Array AgentTool := #[]
  messages : Array AgentMessage := #[]
  isStreaming : Bool := false
  streamingMessage : Option AgentMessage := none
  pendingToolCalls : Array String := #[]
  errorMessage : Option String := none

instance : Inhabited AgentState where
  default :=
    { systemPrompt := ""
      model :=
        { id := ""
          name := ""
          provider := ""
          api := ""
          baseUrl := ""
        }
    }
-- AgentEvent
----------------------------------------------------------------------------

/--
Pi-compatible agent event. No `error` constructor — errors are encoded in
`agentEnd` with an assistant message whose `stopReason` is `error` or `aborted`.
-/
inductive AgentEvent where
  | agentStart
  | agentEnd (messages : Array AgentMessage)
  | turnStart
  | turnEnd (message : AgentMessage) (toolResults : Array AgentMessage)
  | messageStart (message : AgentMessage)
  | messageUpdate (message : AgentMessage) (assistantEvent : LeanAgent.AI.AssistantMessageEvent)
  | messageEnd (message : AgentMessage)
  | toolExecutionStart (toolCallId : String) (toolName : String) (args : Lean.Json)
  | toolExecutionUpdate (toolCallId : String) (toolName : String) (args : Lean.Json) (partialResult : AgentToolResult)
  | toolExecutionEnd (toolCallId : String) (toolName : String) (result : AgentToolResult) (isError : Bool)

abbrev AgentEventSink := AgentEvent → IO Unit

----------------------------------------------------------------------------
-- Hook context types
----------------------------------------------------------------------------

structure BeforeToolCallContext where
  assistantMessage : AgentMessage
  toolCall : LeanAgent.AI.ToolCall
  args : Lean.Json
  context : AgentContext

structure BeforeToolCallResult where
  block : Bool := false
  reason : Option String := none

structure AfterToolCallContext where
  assistantMessage : AgentMessage
  toolCall : LeanAgent.AI.ToolCall
  args : Lean.Json
  result : AgentToolResult
  isError : Bool
  context : AgentContext

structure AfterToolCallResult where
  content : Option (Array LeanAgent.AI.ContentBlock) := none
  details : Option Lean.Json := none
  isError : Option Bool := none
  terminate : Option Bool := none

structure ShouldStopAfterTurnContext where
  message : AgentMessage
  toolResults : Array AgentMessage
  context : AgentContext
  newMessages : Array AgentMessage

structure PrepareNextTurnContext extends ShouldStopAfterTurnContext

structure AgentLoopTurnUpdate where
  context : Option AgentContext := none
  model : Option LeanAgent.Models.ModelInfo := none
  thinkingLevel : Option LeanAgent.AI.ModelThinkingLevel := none

----------------------------------------------------------------------------
-- AgentLoopConfig
----------------------------------------------------------------------------

/--
Default conversion from AgentMessage to LLM Message. Filters out custom messages.
-/
def defaultConvertToLlm (message : AgentMessage) : Option LeanAgent.AI.Message :=
  match message with
  | .ofMessage msg => some msg
  | .custom _ _ _ _ => none

/--
Pi-compatible agent loop configuration. Hooks mirror the TypeScript `AgentLoopConfig`
from `packages/agent/src/types.ts`.
-/
structure AgentLoopConfig where
  model : LeanAgent.Models.ModelInfo
  convertToLlm : AgentMessage → Option LeanAgent.AI.Message
  transformContext : Option (Array AgentMessage → IO (Array AgentMessage)) := none
  getApiKey : Option (String → IO (Option String)) := none
  onPayload : Option LeanAgent.AI.PayloadHook := none
  onResponse : Option LeanAgent.AI.ResponseHook := none
  beforeToolCall : Option (BeforeToolCallContext → IO (Option BeforeToolCallResult)) := none
  afterToolCall : Option (AfterToolCallContext → IO (Option AfterToolCallResult)) := none
  shouldStopAfterTurn : Option (ShouldStopAfterTurnContext → IO Bool) := none
  prepareNextTurn : Option (PrepareNextTurnContext → IO (Option AgentLoopTurnUpdate)) := none
  getSteeringMessages : Option (IO (Array AgentMessage)) := none
  getFollowUpMessages : Option (IO (Array AgentMessage)) := none
  toolExecution : ToolExecutionMode := .parallel
  reasoning : Option LeanAgent.AI.ThinkingLevel := none
  thinkingBudgets : Option LeanAgent.AI.ThinkingBudgets := none
  transport : Option LeanAgent.AI.Transport := none
  sessionId : Option String := none
  maxRetryDelayMs : Option Nat := none

----------------------------------------------------------------------------
-- QueueMode and PendingMessageQueue
----------------------------------------------------------------------------

inductive QueueMode where
  | all
  | oneAtATime
deriving BEq, Repr

structure PendingMessageQueue where
  messages : Array AgentMessage := #[]
  mode : QueueMode := .oneAtATime

namespace PendingMessageQueue

def enqueue (queue : PendingMessageQueue) (message : AgentMessage) : PendingMessageQueue :=
  { queue with messages := queue.messages.push message }

def hasItems (queue : PendingMessageQueue) : Bool :=
  !queue.messages.isEmpty

def drain (queue : PendingMessageQueue) : Array AgentMessage × PendingMessageQueue :=
  match queue.mode with
  | .all => (queue.messages, { queue with messages := #[] })
  | .oneAtATime =>
      if queue.messages.isEmpty then
        (#[], queue)
      else
        (#[queue.messages[0]!], { queue with messages := queue.messages.extract 1 queue.messages.size })

def clear (queue : PendingMessageQueue) : PendingMessageQueue :=
  { queue with messages := #[] }

end PendingMessageQueue

end LeanAgent.Agent
