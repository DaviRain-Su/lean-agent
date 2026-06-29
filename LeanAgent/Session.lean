import LeanAgent.Agent
import LeanAgent.Agent.Types
import LeanAgent.Agent.Loop
import LeanAgent.Agent.Agent
import LeanAgent.AI.Types
import LeanAgent.Core
import LeanAgent.Json
import LeanAgent.Loop
import LeanAgent.Models

namespace LeanAgent.Session

abbrev RuntimeAgent := LeanAgent.Agent.Agent
abbrev RuntimeAgentMessage := LeanAgent.Agent.AgentMessage
abbrev RuntimeAgentEvent := LeanAgent.Agent.AgentEvent
abbrev RuntimeAgentEventSink := LeanAgent.Agent.AgentEventSink
abbrev RuntimeAgentLoopConfig := LeanAgent.Agent.AgentLoopConfig


def currentTimestamp : IO String := do
  let output ← IO.Process.output
    { cmd := "date"
      args := #["-u", "+%Y-%m-%dT%H:%M:%SZ"]
      stdin := .null
      stdout := .piped
      stderr := .null
    }
  if output.exitCode == 0 then
    pure output.stdout.trimAscii.toString
  else
    pure s!"mono:{← IO.monoMsNow}"


def newId (idPrefix : String) : IO String := do
  pure s!"{idPrefix}-{← IO.monoNanosNow}"


def toolCallToJson (call : ToolCall) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("id", LeanAgent.Json.str call.id)
    , ("name", LeanAgent.Json.str call.name)
    , ("arguments", call.arguments)
    ]


def toolCallFromJson (json : Lean.Json) : Except String ToolCall := do
  let id ← (← json.getObjVal? "id").getStr?
  let name ← (← json.getObjVal? "name").getStr?
  let arguments ← json.getObjVal? "arguments"
  pure { id := id, name := name, arguments := arguments }


def messageToJson : AgentMessage → Lean.Json
  | .user content =>
      LeanAgent.Json.obj
        [ ("role", LeanAgent.Json.str "user")
        , ("content", LeanAgent.Json.str content)
        ]
  | .assistant content calls =>
      LeanAgent.Json.obj
        [ ("role", LeanAgent.Json.str "assistant")
        , ("content", LeanAgent.Json.str content)
        , ("tool_calls", LeanAgent.Json.arr (calls.map toolCallToJson))
        ]
  | .toolResult toolCallId name content ok =>
      LeanAgent.Json.obj
        [ ("role", LeanAgent.Json.str "tool")
        , ("tool_call_id", LeanAgent.Json.str toolCallId)
        , ("name", LeanAgent.Json.str name)
        , ("content", LeanAgent.Json.str content)
        , ("ok", LeanAgent.Json.bool ok)
        ]


def messageFromJson (json : Lean.Json) : Except String AgentMessage := do
  let role ← (← json.getObjVal? "role").getStr?
  match role with
  | "user" =>
      pure (.user (← (← json.getObjVal? "content").getStr?))
  | "assistant" =>
      let content ← (← json.getObjVal? "content").getStr?
      let toolCalls ←
        match LeanAgent.Json.optVal? json "tool_calls" with
        | some value =>
            let raw ← value.getArr?
            raw.mapM toolCallFromJson
        | none => pure #[]
      pure (.assistant content toolCalls)
  | "tool" =>
      let toolCallId ← (← json.getObjVal? "tool_call_id").getStr?
      let name ←
        match LeanAgent.Json.optVal? json "name" with
        | some value => value.getStr?
        | none => pure "tool"
      let content ← (← json.getObjVal? "content").getStr?
      let ok ←
        match LeanAgent.Json.optVal? json "ok" with
        | some value => value.getBool?
        | none => pure true
      pure (.toolResult toolCallId name content ok)
  | other => throw s!"unknown message role: {other}"


def headerJson (id timestamp cwd model : String) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "session")
    , ("version", LeanAgent.Json.nat 1)
    , ("id", LeanAgent.Json.str id)
    , ("timestamp", LeanAgent.Json.str timestamp)
    , ("cwd", LeanAgent.Json.str cwd)
    , ("model", LeanAgent.Json.str model)
    ]


def messageEntryJson (id parentId timestamp : String) (message : AgentMessage) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "message")
    , ("id", LeanAgent.Json.str id)
    , ("parentId", if parentId.isEmpty then LeanAgent.Json.null else LeanAgent.Json.str parentId)
    , ("timestamp", LeanAgent.Json.str timestamp)
    , ("message", messageToJson message)
    ]


def messageEntryJsonFromJson (id parentId timestamp : String) (message : Lean.Json) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "message")
    , ("id", LeanAgent.Json.str id)
    , ("parentId", if parentId.isEmpty then LeanAgent.Json.null else LeanAgent.Json.str parentId)
    , ("timestamp", LeanAgent.Json.str timestamp)
    , ("message", message)
    ]


def customMessageToJson
    (customType : String)
    (content : Array LeanAgent.AI.ContentBlock)
    (display : Bool)
    (timestamp : Nat) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("role", LeanAgent.Json.str "custom")
    , ("customType", LeanAgent.Json.str customType)
    , ("content", LeanAgent.AI.contentArrayToJson content)
    , ("display", LeanAgent.Json.bool display)
    , ("timestamp", LeanAgent.Json.nat timestamp)
    ]


def runtimeMessageToJson : RuntimeAgentMessage → Lean.Json
  | .ofMessage message => messageToJson (LeanAgent.AI.toLegacyMessage message)
  | .custom customType content display timestamp =>
      customMessageToJson customType content display timestamp


def runtimeMessageFromJson
    (modelInfo : LeanAgent.Models.ModelInfo)
    (json : Lean.Json) : Except String RuntimeAgentMessage := do
  let role ← (← json.getObjVal? "role").getStr?
  match role with
  | "custom" =>
      pure
        (.custom
          (← (← json.getObjVal? "customType").getStr?)
          (← LeanAgent.AI.contentArrayFromJson (← json.getObjVal? "content"))
          ((← LeanAgent.Json.optionalBool json "display").getD true)
          ((← LeanAgent.Json.optionalNat json "timestamp").getD 0))
  | _ =>
      let legacyMessage ← messageFromJson json
      pure
        (.ofMessage
          (LeanAgent.AI.fromLegacyMessage
            modelInfo.api
            modelInfo.provider
            modelInfo.id
            0
            legacyMessage))


def appendLine (path : System.FilePath) (line : String) : IO Unit := do
  match path.parent with
  | some parent => IO.FS.createDirAll parent
  | none => pure ()
  IO.FS.withFile path .append fun handle => do
    handle.putStrLn line


def ensureSessionFile (path : System.FilePath) (cwd : System.FilePath) (model : String) : IO Unit := do
  if ← path.pathExists then
    pure ()
  else
    let timestamp ← currentTimestamp
    let id ← newId "session"
    appendLine path (headerJson id timestamp cwd.toString model).compress


def parseSessionLine?
    (modelInfo : LeanAgent.Models.ModelInfo)
    (line : String) : Except String (Option (String × RuntimeAgentMessage)) := do
  let trimmed := line.trimAscii.toString
  if trimmed.isEmpty then
    pure none
  else
    let json ← Lean.Json.parse trimmed
    let entryType ← (← json.getObjVal? "type").getStr?
    if entryType == "message" then
      let id ← (← json.getObjVal? "id").getStr?
      let message ← json.getObjVal? "message"
      let message ← runtimeMessageFromJson modelInfo message
      pure (some (id, message))
    else
      pure none


def loadMessagesWithLastId
    (modelInfo : LeanAgent.Models.ModelInfo)
    (path : System.FilePath) : IO (Array RuntimeAgentMessage × Option String) := do
  if !(← path.pathExists) then
    pure (#[], none)
  else
    let content ← IO.FS.readFile path
    let mut messages := #[]
    let mut lastId := none
    for line in content.splitOn "\n" do
      match parseSessionLine? modelInfo line with
      | .ok (some (id, message)) =>
          messages := messages.push message
          lastId := some id
      | .ok none => pure ()
      | .error err => throw (IO.userError s!"invalid session line in {path}: {err}")
    pure (messages, lastId)


def loadMessages
    (modelInfo : LeanAgent.Models.ModelInfo)
    (path : System.FilePath) : IO (Array RuntimeAgentMessage) := do
  pure (← loadMessagesWithLastId modelInfo path).fst


structure SessionStore where
  path : System.FilePath
  lastEntryId : Option String := none


inductive Persistence where
  | ephemeral
  | create (path : System.FilePath)
  | resume (path : System.FilePath)


structure AgentSession where
  agent : LeanAgent.Agent.Agent
  store : Option SessionStore := none


def AgentSession.messages (session : AgentSession) : Array RuntimeAgentMessage :=
  session.agent.state.messages


def AgentSession.withMessages
    (session : AgentSession)
    (messages : Array RuntimeAgentMessage) : AgentSession :=
  { session with
    agent := { session.agent with state := { session.agent.state with messages := messages } }
  }


def AgentSession.sessionPath? (session : AgentSession) : Option System.FilePath :=
  session.store.map (fun store => store.path)


def reasoningToThinkingLevel : Option LeanAgent.AI.ThinkingLevel → LeanAgent.AI.ModelThinkingLevel
  | some level => .level level
  | none => .off


def agentOptionsFromConfig
    (config : RuntimeAgentLoopConfig)
    (messages : Array RuntimeAgentMessage) : LeanAgent.Agent.AgentOptions :=
  { initialState :=
      { systemPrompt := ""
        model := config.model
        thinkingLevel := reasoningToThinkingLevel config.reasoning
        messages := messages
      }
    convertToLlm := config.convertToLlm
    transformContext := config.transformContext
    getApiKey := config.getApiKey
    onPayload := config.onPayload
    onResponse := config.onResponse
    beforeToolCall := config.beforeToolCall
    afterToolCall := config.afterToolCall
    prepareNextTurn := config.prepareNextTurn
    sessionId := config.sessionId
    thinkingBudgets := config.thinkingBudgets
    transport := config.transport.getD .auto
    maxRetryDelayMs := config.maxRetryDelayMs
    toolExecution := config.toolExecution
  }


def create
    (config : RuntimeAgentLoopConfig)
    (cwd : System.FilePath)
    (model : String)
    (persistence : Persistence := .ephemeral) : IO AgentSession := do
  let mkSession (messages : Array RuntimeAgentMessage) (store : Option SessionStore) : AgentSession :=
    { agent := LeanAgent.Agent.Agent.create (agentOptionsFromConfig config messages)
      store := store
    }
  match persistence with
  | .ephemeral =>
      pure (mkSession #[] none)
  | .create path =>
      ensureSessionFile path cwd model
      let (messages, lastId) ← loadMessagesWithLastId config.model path
      pure (mkSession messages (some { path := path, lastEntryId := lastId }))
  | .resume path =>
      if !(← path.pathExists) then
        throw (IO.userError s!"session file not found: {path}")
      let (messages, lastId) ← loadMessagesWithLastId config.model path
      pure (mkSession messages (some { path := path, lastEntryId := lastId }))


def persistMessages
    (store : Option SessionStore)
    (messages : Array RuntimeAgentMessage) : IO (Option SessionStore) := do
  match store with
  | none => pure none
  | some store =>
      let mut lastId := store.lastEntryId
      for message in messages do
        let timestamp ← currentTimestamp
        let id ← newId "entry"
        let json := runtimeMessageToJson message
        appendLine store.path (messageEntryJsonFromJson id (lastId.getD "") timestamp json).compress
        lastId := some id
      pure (some { store with lastEntryId := lastId })


def assistantToolCalls : RuntimeAgentMessage → Array LeanAgent.AI.ToolCall
  | .ofMessage (.assistant message) => LeanAgent.AI.contentToolCalls message.content
  | _ => #[]


def emitToolExecutionEvents
    (assistantMessage : RuntimeAgentMessage)
    (toolResultMessage : RuntimeAgentMessage)
    (sink : RuntimeAgentEventSink) : IO Unit := do
  match toolResultMessage with
  | .ofMessage (.toolResult result) =>
      let args :=
        match (assistantToolCalls assistantMessage).find? (fun call => call.id == result.toolCallId) with
        | some call => call.arguments
        | none => Lean.Json.null
      let toolResult : LeanAgent.Agent.AgentToolResult :=
        { content := result.content
          details := result.details
          terminate := false
        }
      sink (.toolExecutionStart result.toolCallId result.toolName args)
      sink (.toolExecutionEnd result.toolCallId result.toolName toolResult result.isError)
  | _ => pure ()


def emitSessionEvents
    (newMessages : Array RuntimeAgentMessage)
    (allMessages : Array RuntimeAgentMessage)
    (sink : RuntimeAgentEventSink) : IO Unit := do
  sink .agentStart
  if !newMessages.isEmpty then
    sink .turnStart
  let mut index := 0
  while index < newMessages.size do
    let message := newMessages[index]!
    sink (.messageStart message)
    sink (.messageEnd message)
    match message with
    | .ofMessage (.assistant _) =>
        let mut toolResults := #[]
        index := index + 1
        while index < newMessages.size do
          let candidate := newMessages[index]!
          match candidate with
          | .ofMessage (.toolResult _) =>
              toolResults := toolResults.push candidate
              emitToolExecutionEvents message candidate sink
              index := index + 1
          | _ =>
              break
        sink (.turnEnd message toolResults)
        if index < newMessages.size then
          sink .turnStart
    | _ =>
        index := index + 1
  sink (.agentEnd allMessages)


def prompt
    (session : AgentSession)
    (content : String)
    (sink : RuntimeAgentEventSink) : IO AgentSession := do
  let before := session.messages.size
  let agent ← session.agent.prompt content
  let newMessages := agent.state.messages.extract before agent.state.messages.size
  emitSessionEvents newMessages agent.state.messages sink
  let store ← persistMessages session.store newMessages
  pure { session with agent := agent, store := store }


def continueSession
    (session : AgentSession)
    (sink : RuntimeAgentEventSink) : IO AgentSession := do
  let before := session.messages.size
  let agent ← session.agent.continue
  let newMessages := agent.state.messages.extract before agent.state.messages.size
  emitSessionEvents newMessages agent.state.messages sink
  let store ← persistMessages session.store newMessages
  pure { session with agent := agent, store := store }


def clear (session : AgentSession) : AgentSession :=
  { session with agent := session.agent.reset }


def runtimeMessagesToJson (messages : Array RuntimeAgentMessage) : Lean.Json :=
  LeanAgent.Json.arr (messages.map runtimeMessageToJson)


def jsonEvent (event : RuntimeAgentEvent) : IO Lean.Json := do
  let timestamp ← currentTimestamp
  let base (fields : List (String × Lean.Json)) :=
    LeanAgent.Json.obj (("timestamp", LeanAgent.Json.str timestamp) :: fields)
  match event with
  | .agentStart => pure (base [("type", LeanAgent.Json.str "agent_start")])
  | .agentEnd messages =>
      pure
        (base
          [ ("type", LeanAgent.Json.str "agent_end")
          , ("messages", runtimeMessagesToJson messages)
          ])
  | .turnStart => pure (base [("type", LeanAgent.Json.str "turn_start")])
  | .turnEnd _ _ => pure (base [("type", LeanAgent.Json.str "turn_end")])
  | .messageStart _ => pure (base [("type", LeanAgent.Json.str "message_start")])
  | .messageUpdate _ _ => pure (base [("type", LeanAgent.Json.str "message_update")])
  | .messageEnd _ => pure (base [("type", LeanAgent.Json.str "message_end")])
  | .toolExecutionStart _ _ _ =>
      pure (base [("type", LeanAgent.Json.str "tool_execution_start")])
  | .toolExecutionUpdate _ _ _ _ =>
      pure (base [("type", LeanAgent.Json.str "tool_execution_update")])
  | .toolExecutionEnd _ _ _ _ =>
      pure (base [("type", LeanAgent.Json.str "tool_execution_end")])


def jsonEventSink : RuntimeAgentEventSink :=
  fun event => do
    let json ← jsonEvent event
    IO.println json.compress

end LeanAgent.Session
