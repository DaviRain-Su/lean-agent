import LeanAgent.AI.EventStream
import LeanAgent.Core

namespace LeanAgent

def findTool? (tools : Array AgentTool) (name : String) : Option AgentTool :=
  tools.find? (fun tool => tool.name == name)

def toolResultMessage (result : AgentToolResult) : AgentMessage :=
  let content :=
    match result.error with
    | some err =>
        if result.content.contains err then result.content else result.content ++ "\n\nError: " ++ err
    | none => result.content
  .toolResult result.toolCallId result.name content result.ok

def unknownToolResult (call : ToolCall) : AgentToolResult :=
  let message := s!"unknown tool: {call.name}"
  { toolCallId := call.id
    name := call.name
    ok := false
    content := message
    error := some message
  }

def executeToolCall (tools : Array AgentTool) (call : ToolCall) (sink : EventSink) : IO AgentToolResult := do
  sink (.toolExecutionStart call)
  let result ←
    match findTool? tools call.name with
    | none => pure (unknownToolResult call)
    | some tool =>
        try
          tool.execute call
        catch err =>
          let message := err.toString
          pure
            { toolCallId := call.id
              name := call.name
              ok := false
              content := message
              error := some message
            }
  sink (.toolExecutionEnd result)
  pure result

def emitAssistantStreamEvents (stream : LeanAgent.AI.AssistantMessageEventStream) (sink : EventSink) :
    IO AgentMessage := do
  let mut finalMessage := LeanAgent.AI.toLegacyMessage (.assistant stream.result)
  for event in stream.events do
    match event with
    | .start _ =>
        sink (.messageStart "assistant")
    | .textDelta _ delta _ =>
        if !delta.isEmpty then
          sink (.messageDelta delta)
    | .done _ message =>
        finalMessage := LeanAgent.AI.toLegacyMessage (.assistant message)
        sink (.messageEnd finalMessage)
    | .error _ message =>
        finalMessage := LeanAgent.AI.toLegacyMessage (.assistant message)
        sink (.messageEnd finalMessage)
    | _ => pure ()
  pure finalMessage

def runTurns
    (config : AgentLoopConfig)
    (remainingTurns : Nat)
    (turn : Nat)
    (messages : Array AgentMessage)
    (sink : EventSink) : IO (Array AgentMessage) := do
  match remainingTurns with
  | 0 =>
    sink (.error s!"agent loop stopped after maxTurns={config.maxTurns}")
    pure messages
  | remainingTurns + 1 =>
    sink (.turnStart turn)
    let request :=
      { model := config.model
        system := config.system
        messages := messages
        tools := config.tools
      }
    let stream ← LeanAgent.AI.streamLegacyProvider config.provider request "legacy" "legacy"
    let assistant ← emitAssistantStreamEvents stream sink
    let messages := messages.push assistant
    let toolCalls :=
      match assistant with
      | .assistant _ calls => calls
      | _ => #[]
    if toolCalls.isEmpty then
      sink (.turnEnd turn)
      pure messages
    else
      let mut updated := messages
      for call in toolCalls do
        let result ← executeToolCall config.tools call sink
        updated := updated.push (toolResultMessage result)
      sink (.turnEnd turn)
      runTurns config remainingTurns (turn + 1) updated sink

def runAgentLoop
    (config : AgentLoopConfig)
    (initialMessages : Array AgentMessage)
    (sink : EventSink) : IO (Array AgentMessage) := do
  if config.maxTurns == 0 then
    sink (.error "maxTurns must be at least 1")
    pure initialMessages
  else
    sink .agentStart
    let messages ← runTurns config config.maxTurns 1 initialMessages sink
    sink .agentEnd
    pure messages

end LeanAgent
