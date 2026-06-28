import LeanAgent.Core
import LeanAgent.Json
import LeanAgent.Loop

namespace LeanAgent.Session

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

def parseSessionLine? (line : String) : Except String (Option (String × AgentMessage)) := do
  let trimmed := line.trimAscii.toString
  if trimmed.isEmpty then
    pure none
  else
    let json ← Lean.Json.parse trimmed
    let entryType ← (← json.getObjVal? "type").getStr?
    if entryType == "message" then
      let id ← (← json.getObjVal? "id").getStr?
      let message ← json.getObjVal? "message"
      let message ← messageFromJson message
      pure (some (id, message))
    else
      pure none

def loadMessagesWithLastId (path : System.FilePath) : IO (Array AgentMessage × Option String) := do
  if !(← path.pathExists) then
    pure (#[], none)
  else
    let content ← IO.FS.readFile path
    let mut messages := #[]
    let mut lastId := none
    for line in content.splitOn "\n" do
      match parseSessionLine? line with
      | .ok (some (id, message)) =>
          messages := messages.push message
          lastId := some id
      | .ok none => pure ()
      | .error err => throw (IO.userError s!"invalid session line in {path}: {err}")
    pure (messages, lastId)

def loadMessages (path : System.FilePath) : IO (Array AgentMessage) := do
  pure (← loadMessagesWithLastId path).fst

structure SessionStore where
  path : System.FilePath
  lastEntryId : Option String := none

inductive Persistence where
  | ephemeral
  | create (path : System.FilePath)
  | resume (path : System.FilePath)

structure AgentSession where
  config : AgentLoopConfig
  messages : Array AgentMessage := #[]
  store : Option SessionStore := none

def AgentSession.withMessages (session : AgentSession) (messages : Array AgentMessage) : AgentSession :=
  { session with messages := messages }

def AgentSession.sessionPath? (session : AgentSession) : Option System.FilePath :=
  session.store.map (fun store => store.path)

def create
    (config : AgentLoopConfig)
    (cwd : System.FilePath)
    (model : String)
    (persistence : Persistence := .ephemeral) : IO AgentSession := do
  match persistence with
  | .ephemeral =>
      pure { config := config }
  | .create path =>
      ensureSessionFile path cwd model
      let (messages, lastId) ← loadMessagesWithLastId path
      pure { config := config, messages := messages, store := some { path := path, lastEntryId := lastId } }
  | .resume path =>
      if !(← path.pathExists) then
        throw (IO.userError s!"session file not found: {path}")
      let (messages, lastId) ← loadMessagesWithLastId path
      pure { config := config, messages := messages, store := some { path := path, lastEntryId := lastId } }

def persistMessages (store : Option SessionStore) (messages : Array AgentMessage) : IO (Option SessionStore) := do
  match store with
  | none => pure none
  | some store =>
      let mut lastId := store.lastEntryId
      for message in messages do
        let timestamp ← currentTimestamp
        let id ← newId "entry"
        appendLine store.path (messageEntryJson id (lastId.getD "") timestamp message).compress
        lastId := some id
      pure (some { store with lastEntryId := lastId })

def prompt (session : AgentSession) (content : String) (sink : EventSink) : IO AgentSession := do
  let before := session.messages.size
  let initial := session.messages.push (.user content)
  let updated ← runAgentLoop session.config initial sink
  let newMessages := updated.extract before updated.size
  let store ← persistMessages session.store newMessages
  pure { session with messages := updated, store := store }

def canContinueFrom? : AgentMessage → Bool
  | .user _ => true
  | .toolResult _ _ _ _ => true
  | .assistant _ _ => false

def continueSession (session : AgentSession) (sink : EventSink) : IO AgentSession := do
  match session.messages.back? with
  | none => throw (IO.userError "cannot continue an empty session")
  | some message =>
      if canContinueFrom? message then
        pure ()
      else
        throw (IO.userError "cannot continue after an assistant message; add a new prompt or resume a session ending in user/tool output")
  let before := session.messages.size
  let updated ← runAgentLoop session.config session.messages sink
  let newMessages := updated.extract before updated.size
  let store ← persistMessages session.store newMessages
  pure { session with messages := updated, store := store }

def clear (session : AgentSession) : AgentSession :=
  { session with messages := #[] }

def jsonEvent (event : AgentEvent) : IO Lean.Json := do
  let timestamp ← currentTimestamp
  let base (fields : List (String × Lean.Json)) :=
    LeanAgent.Json.obj (("timestamp", LeanAgent.Json.str timestamp) :: fields)
  match event with
  | .agentStart => pure (base [("type", LeanAgent.Json.str "agent_start")])
  | .agentEnd => pure (base [("type", LeanAgent.Json.str "agent_end")])
  | .turnStart turn =>
      pure (base [("type", LeanAgent.Json.str "turn_start"), ("turn", LeanAgent.Json.nat turn)])
  | .turnEnd turn =>
      pure (base [("type", LeanAgent.Json.str "turn_end"), ("turn", LeanAgent.Json.nat turn)])
  | .messageStart role =>
      pure (base [("type", LeanAgent.Json.str "message_start"), ("role", LeanAgent.Json.str role)])
  | .messageDelta delta =>
      pure (base [("type", LeanAgent.Json.str "message_delta"), ("delta", LeanAgent.Json.str delta)])
  | .messageEnd message =>
      pure (base [("type", LeanAgent.Json.str "message_end"), ("message", messageToJson message)])
  | .toolExecutionStart call =>
      pure (base [("type", LeanAgent.Json.str "tool_execution_start"), ("tool_call", toolCallToJson call)])
  | .toolExecutionEnd result =>
      pure
        (base
          [ ("type", LeanAgent.Json.str "tool_execution_end")
          , ("tool_call_id", LeanAgent.Json.str result.toolCallId)
          , ("name", LeanAgent.Json.str result.name)
          , ("ok", LeanAgent.Json.bool result.ok)
          , ("content", LeanAgent.Json.str result.content)
          , ("error", match result.error with | some err => LeanAgent.Json.str err | none => LeanAgent.Json.null)
          ])
  | .error message =>
      pure (base [("type", LeanAgent.Json.str "error"), ("message", LeanAgent.Json.str message)])

def jsonEventSink : EventSink :=
  fun event => do
    let json ← jsonEvent event
    IO.println json.compress

end LeanAgent.Session
