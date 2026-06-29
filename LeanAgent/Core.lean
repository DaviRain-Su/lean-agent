import Lean

namespace LeanAgent

@[deprecated "Use LeanAgent.Agent.Types.ToolCall (LeanAgent.AI.Types.ToolCall) instead"]
structure ToolCall where
  id : String
  name : String
  arguments : Lean.Json

@[deprecated "Use LeanAgent.Agent.Types.AgentToolResult instead"]
structure AgentToolResult where
  toolCallId : String
  name : String
  ok : Bool
  content : String
  data : Option Lean.Json := none
  error : Option String := none

/--
Legacy message shape used by the current agent loop and session JSONL format.
Pi-compatible AI code should use `LeanAgent.AI.Message`; conversion helpers live
in `LeanAgent.AI.Types` while the runtime migration is staged.
-/
@[deprecated "Use LeanAgent.Agent.Types.AgentMessage instead"]
inductive AgentMessage where
  | user (content : String)
  | assistant (content : String) (toolCalls : Array ToolCall)
  | toolResult (toolCallId : String) (name : String) (content : String) (ok : Bool)

def AgentMessage.role : AgentMessage → String
  | .user _ => "user"
  | .assistant _ _ => "assistant"
  | .toolResult _ _ _ _ => "tool"

@[deprecated "Use LeanAgent.Agent.Types.AgentTool instead"]
structure AgentTool where
  name : String
  description : String
  inputSchema : Lean.Json
  execute : ToolCall → IO AgentToolResult

@[deprecated "Use LeanAgent.AI.Context instead"]
structure ProviderRequest where
  model : String
  system : String
  messages : Array AgentMessage
  tools : Array AgentTool

@[deprecated "Use LeanAgent.AI.Usage instead"]
structure ProviderUsage where
  input : Nat := 0
  output : Nat := 0
  cacheRead : Nat := 0
  cacheWrite : Nat := 0
  cacheWrite1h : Option Nat := none
  reasoning : Option Nat := none
  totalTokens : Nat := 0
deriving BEq

@[deprecated "Use LeanAgent.AI.AssistantMessage instead"]
structure ProviderResponse where
  content : String := ""
  toolCalls : Array ToolCall := #[]
  finishReason : Option String := none
  usage : Option ProviderUsage := none

@[deprecated "Use LeanAgent.AI.Compat.streamSimple instead"]
structure ModelProvider where
  complete : ProviderRequest → IO ProviderResponse

@[deprecated "Use LeanAgent.Agent.Types.AgentEvent instead"]
inductive AgentEvent where
  | agentStart
  | agentEnd
  | turnStart (turn : Nat)
  | turnEnd (turn : Nat)
  | messageStart (role : String)
  | messageDelta (delta : String)
  | messageEnd (message : AgentMessage)
  | toolExecutionStart (toolCall : ToolCall)
  | toolExecutionEnd (result : AgentToolResult)
  | error (message : String)

abbrev EventSink := AgentEvent → IO Unit

@[deprecated "Use LeanAgent.Agent.Types.AgentLoopConfig instead"]
structure AgentLoopConfig where
  provider : ModelProvider
  model : String
  system : String
  tools : Array AgentTool
  maxTurns : Nat := 8

def toolCallSummary (call : ToolCall) : String :=
  call.name ++ "(" ++ call.id ++ ")"

def resultStatus (result : AgentToolResult) : String :=
  if result.ok then "ok" else "error"

end LeanAgent
