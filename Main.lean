import LeanAgent

open LeanAgent

structure CliOptions where
  prompt : Option String := none
  cwd : Option System.FilePath := none
  model : Option String := none
  baseUrl : Option String := none
  apiKeyEnv : Option String := none
  maxTurns : Nat := 8
  repl : Bool := false
  session : Option System.FilePath := none
  resume : Option System.FilePath := none
  noSession : Bool := false
  jsonEvents : Bool := false
  continueRun : Bool := false
  listModels : Bool := false
  help : Bool := false

def deepSeekApiKeyEnv : String := LeanAgent.Models.deepSeekApiKeyEnv
def deepSeekModelEnv : String := LeanAgent.Models.deepSeekModelEnv
def deepSeekDefaultModel : String := LeanAgent.Models.deepSeekDefaultModel
def deepSeekBaseUrl : String := LeanAgent.Models.deepSeekBaseUrl

def openAIKeyEnv : String := LeanAgent.Models.openAIKeyEnv
def openAIModelEnv : String := LeanAgent.Models.openAIModelEnv
def openAIDefaultModel : String := LeanAgent.Models.openAIDefaultModel
def openAIBaseUrl : String := LeanAgent.Models.openAIBaseUrl
def leanAgentNoProxyEnv : String := LeanAgent.Models.leanAgentNoProxyEnv

def usage : String :=
  String.intercalate "\n"
    [ "lean-agent, a small Lean coding agent inspired by Tau"
    , ""
    , "Usage:"
    , "  lean-agent -p \"explain this repo\" [--model MODEL]"
    , "  lean-agent --prompt \"fix the failing test\" --cwd /path/to/project"
    , "  lean-agent --repl --cwd /path/to/project"
    , ""
    , "Options:"
    , "  -p, --prompt TEXT        One-shot prompt, or first REPL turn with --repl. If omitted, read one line from stdin."
    , "  --repl                  Start an interactive line REPL that keeps conversation context."
    , "  --session PATH          Persist this run to a JSONL session file."
    , "  --resume PATH           Resume messages from a JSONL session file and append new entries."
    , "  --no-session            Do not persist or resume a session."
    , "  --json-events           Emit AgentEvent values as JSONL."
    , "  --continue              Continue from the loaded session without adding a prompt."
    , "  --list-models           List built-in provider/model catalog and exit."
    , "  --cwd PATH              Working directory for tools."
    , "  --model MODEL           Model name. Defaults to DEEPSEEK_MODEL/deepseek-v4-flash when DeepSeek is configured."
    , "  --base-url URL          OpenAI-compatible base URL. Defaults to DeepSeek first, then OpenAI."
    , "  --api-key-env NAME      Environment variable containing the API key. Defaults to DEEPSEEK_API_KEY first, then OPENAI_API_KEY."
    , "  --max-turns N           Maximum model/tool turns. Defaults to 8."
    , "  -h, --help              Show this help."
    ]

def parseArgs (args : List String) (opts : CliOptions := {}) : Except String CliOptions :=
  match args with
  | [] => pure opts
  | "-h" :: rest => parseArgs rest { opts with help := true }
  | "--help" :: rest => parseArgs rest { opts with help := true }
  | "-p" :: value :: rest => parseArgs rest { opts with prompt := some value }
  | "--prompt" :: value :: rest => parseArgs rest { opts with prompt := some value }
  | "--repl" :: rest => parseArgs rest { opts with repl := true }
  | "--session" :: value :: rest => parseArgs rest { opts with session := some (System.FilePath.mk value) }
  | "--resume" :: value :: rest => parseArgs rest { opts with resume := some (System.FilePath.mk value) }
  | "--no-session" :: rest => parseArgs rest { opts with noSession := true }
  | "--json-events" :: rest => parseArgs rest { opts with jsonEvents := true }
  | "--continue" :: rest => parseArgs rest { opts with continueRun := true }
  | "--list-models" :: rest => parseArgs rest { opts with listModels := true }
  | "--cwd" :: value :: rest => parseArgs rest { opts with cwd := some (System.FilePath.mk value) }
  | "--model" :: value :: rest => parseArgs rest { opts with model := some value }
  | "--base-url" :: value :: rest => parseArgs rest { opts with baseUrl := some value }
  | "--api-key-env" :: value :: rest => parseArgs rest { opts with apiKeyEnv := some value }
  | "--max-turns" :: value :: rest =>
      match value.toNat? with
      | some n => parseArgs rest { opts with maxTurns := n }
      | none => throw s!"invalid --max-turns value: {value}"
  | opt :: _ =>
      if opt.startsWith "-" then
        throw s!"unknown option: {opt}"
      else
        throw s!"unexpected positional argument: {opt}"

def promptFromOptions (opts : CliOptions) : IO String := do
  match opts.prompt with
  | some prompt => pure prompt
  | none =>
      IO.print "lean-agent> "
      let stdin ← IO.getStdin
      stdin.getLine

def resolveWorkingDir (opts : CliOptions) : IO System.FilePath := do
  let raw ←
    (match opts.cwd with
    | some cwd => pure cwd
    | none => IO.currentDir)
  let dirExists ← raw.pathExists
  if !dirExists then
    throw (IO.userError s!"working directory not found: {raw}")
  let path ← IO.FS.realPath raw
  let isDir ← path.isDir
  if !isDir then
    throw (IO.userError s!"working directory is not a directory: {path}")
  pure path

structure Runtime where
  cwd : System.FilePath
  model : String
  extensions : LeanAgent.Project.ProjectExtensions
  session : LeanAgent.Session.AgentSession
  jsonEvents : Bool

def selectedModelInfo (selection : LeanAgent.Models.ProviderSelection) : LeanAgent.Models.ModelInfo :=
  match selection.providerInfo.model? selection.model with
  | some model => { model with baseUrl := selection.baseUrl }
  | none =>
      { id := selection.model
        name := selection.model
        provider := selection.providerInfo.id
        api := "openai-completions"
        baseUrl := selection.baseUrl
      }

def createSessionWithAgent
    (agent : LeanAgent.Agent.Agent)
    (cwd : System.FilePath)
    (model : String)
    (persistence : LeanAgent.Session.Persistence := .ephemeral) :
    IO LeanAgent.Session.AgentSession := do
  match persistence with
  | .ephemeral =>
      pure { agent := agent }
  | .create path =>
      LeanAgent.Session.ensureSessionFile path cwd model
      let (messages, lastId) ← LeanAgent.Session.loadMessagesWithLastId path
      let agent := { agent with state := { agent.state with messages := messages } }
      pure { agent := agent, store := some { path := path, lastEntryId := lastId } }
  | .resume path =>
      if !(← path.pathExists) then
        throw (IO.userError s!"session file not found: {path}")
      let (messages, lastId) ← LeanAgent.Session.loadMessagesWithLastId path
      let agent := { agent with state := { agent.state with messages := messages } }
      pure { agent := agent, store := some { path := path, lastEntryId := lastId } }

def runtimeFromOptions (opts : CliOptions) : IO (Except String Runtime) := do
  if opts.noSession && (opts.session.isSome || opts.resume.isSome) then
    return .error "--no-session cannot be combined with --session or --resume"
  if opts.session.isSome && opts.resume.isSome then
    return .error "--session and --resume are mutually exclusive"
  if opts.continueRun && opts.repl then
    return .error "--continue cannot be combined with --repl"
  if opts.continueRun && opts.prompt.isSome then
    return .error "--continue cannot be combined with --prompt"
  if opts.continueRun && opts.session.isNone && opts.resume.isNone then
    return .error "--continue requires --resume or --session"
  let cwd ← resolveWorkingDir opts
  match ← LeanAgent.Models.resolveSelection
      { model := opts.model
        baseUrl := opts.baseUrl
        apiKeyEnv := opts.apiKeyEnv
      } with
  | .error err => pure (.error err)
  | .ok selection =>
    let extensions ← LeanAgent.Project.loadExtensions cwd
    let system := LeanAgent.Project.applySystemAppendix defaultSystemPrompt extensions
    let modelInfo := selectedModelInfo selection
    let tools := LeanAgent.CodingTools.defaultAgentTools cwd
    let options : LeanAgent.Agent.AgentOptions :=
      { initialState :=
          { systemPrompt := system
            model := modelInfo
            tools := tools
          }
        streamFn := LeanAgent.Agent.defaultStreamFn
        convertToLlm := LeanAgent.Agent.defaultConvertToLlm
        getApiKey := some (fun _ => pure (some selection.apiKey))
      }
    let agent := LeanAgent.Agent.Agent.create options
    let persistence :=
      match opts.resume with
      | some path => LeanAgent.Session.Persistence.resume path
      | none =>
          match opts.session with
          | some path => LeanAgent.Session.Persistence.create path
          | none => LeanAgent.Session.Persistence.ephemeral
    let session ← createSessionWithAgent agent cwd selection.model persistence
    pure
      (.ok
        { cwd := cwd
          model := selection.model
          extensions := extensions
          session := session
          jsonEvents := opts.jsonEvents
        })

def renderToolCall (call : LeanAgent.AI.ToolCall) : String :=
  "-> " ++ call.name ++ " " ++ call.arguments.compress

def assistantToolCalls (message : LeanAgent.Agent.AgentMessage) : Array LeanAgent.AI.ToolCall :=
  match message with
  | .ofMessage (.assistant assistant) => LeanAgent.AI.contentToolCalls assistant.content
  | _ => #[]

def eventDelta? : LeanAgent.AI.AssistantMessageEvent → Option String
  | .textDelta _ delta _ => some delta
  | .thinkingDelta _ delta _ => some delta
  | .toolCallDelta _ delta _ => some delta
  | _ => none

def toolResultStatus (isError : Bool) : String :=
  if isError then "error" else "ok"

def toolResultText (result : LeanAgent.Agent.AgentToolResult) : String :=
  LeanAgent.Agent.AgentToolResult.text result

def renderEvent : LeanAgent.Agent.AgentEventSink
  | .agentStart => IO.println "agent:start"
  | .agentEnd _ => IO.println "agent:end"
  | .turnStart => IO.println "turn:start"
  | .turnEnd _ _ => IO.println "turn:end"
  | .messageStart msg => IO.println s!"message:{LeanAgent.Agent.AgentMessage.role msg}:start"
  | .messageUpdate _ event =>
      match eventDelta? event with
      | some delta => IO.println delta
      | none => pure ()
  | .messageEnd msg => do
      for call in assistantToolCalls msg do
        IO.println (renderToolCall call)
      IO.println "message:end"
  | .toolExecutionStart _ toolName _ => IO.println s!"tool:{toolName}:start"
  | .toolExecutionUpdate _ _ _ _ => pure ()
  | .toolExecutionEnd _ toolName result isError => do
      IO.println s!"tool:{toolName}:{toolResultStatus isError}"
      let text := toolResultText result
      if !text.trimAscii.isEmpty then
        IO.println text

def renderReplEvent : LeanAgent.Agent.AgentEventSink
  | .agentStart => pure ()
  | .agentEnd _ => pure ()
  | .turnStart => pure ()
  | .turnEnd _ _ => pure ()
  | .messageStart msg =>
      if LeanAgent.Agent.AgentMessage.role msg == "assistant" then
        IO.println "assistant:"
      else
        pure ()
  | .messageUpdate _ event =>
      match eventDelta? event with
      | some delta =>
          if !delta.trimAscii.isEmpty then
            IO.println delta
          else
            pure ()
      | none => pure ()
  | .messageEnd msg => do
      for call in assistantToolCalls msg do
        IO.println s!"[tool request] {renderToolCall call}"
  | .toolExecutionStart _ toolName _ => IO.println s!"[tool] {toolName}:start"
  | .toolExecutionUpdate _ _ _ _ => pure ()
  | .toolExecutionEnd _ toolName result isError => do
      IO.println s!"[tool] {toolName}:{toolResultStatus isError}"
      let text := toolResultText result
      if !text.trimAscii.isEmpty then
        IO.println text

def replHelp : String :=
  String.intercalate "\n"
    [ "REPL commands:"
    , "  /help      Show this help."
    , "  /context   Show current model, cwd, and message count."
    , "  /session   Show current session details."
    , "  /commands  List discovered .omp slash commands."
    , "  /skills    List discovered .omp skills."
    , "  /clear     Clear conversation context."
    , "  /exit      Exit the REPL."
    , "  /quit      Exit the REPL."
    ]

def isExitCommand (input : String) : Bool :=
  input == "/exit" || input == "/quit" || input == ":q"

def printReplContext (runtime : Runtime) (session : LeanAgent.Session.AgentSession) : IO Unit := do
  IO.println s!"model: {runtime.model}"
  IO.println s!"cwd: {runtime.cwd}"
  IO.println s!"messages: {session.agent.state.messages.size}"
  IO.println s!"commands: {runtime.extensions.commands.size}"
  IO.println s!"skills: {runtime.extensions.skills.size}"

def printSessionInfo (runtime : Runtime) (session : LeanAgent.Session.AgentSession) : IO Unit := do
  IO.println s!"model: {runtime.model}"
  IO.println s!"cwd: {runtime.cwd}"
  IO.println s!"messages: {session.agent.state.messages.size}"
  match session.sessionPath? with
  | some path => IO.println s!"session: {path}"
  | none => IO.println "session: ephemeral"

def sinkForRuntime (runtime : Runtime) (repl : Bool) : LeanAgent.Agent.AgentEventSink :=
  if runtime.jsonEvents then
    LeanAgent.Session.jsonEventSink
  else if repl then
    renderReplEvent
  else
    renderEvent

def runtimeWithEventSink (runtime : Runtime) (repl : Bool) : Runtime :=
  let sink := sinkForRuntime runtime repl
  let agent := runtime.session.agent.subscribe (fun event _ => sink event)
  { runtime with session := { runtime.session with agent := agent } }

def persistSessionAgent
    (session : LeanAgent.Session.AgentSession)
    (beforeCount : Nat)
    (agent : LeanAgent.Agent.Agent) : IO LeanAgent.Session.AgentSession := do
  let messages := agent.state.messages
  let newMessages := messages.extract beforeCount messages.size
  let store ← LeanAgent.Session.persistMessages session.store newMessages
  pure { session with agent := agent, store := store }

def runReplTurn (runtime : Runtime) (session : LeanAgent.Session.AgentSession) (input : String) :
    IO LeanAgent.Session.AgentSession := do
  let expanded := LeanAgent.Project.expandPrompt runtime.extensions input
  let beforeCount := session.agent.state.messages.size
  let agent ← session.agent.prompt expanded
  persistSessionAgent session beforeCount agent

partial def replLoop (runtime : Runtime) (session : LeanAgent.Session.AgentSession) : IO UInt32 := do
  let stdout ← IO.getStdout
  stdout.putStr "lean-agent> "
  stdout.flush
  let stdin ← IO.getStdin
  let line ← stdin.getLine
  if line.isEmpty then
    IO.println ""
    pure 0
  else
    let input := line.trimAscii.toString
    if input.isEmpty then
      replLoop runtime session
    else if isExitCommand input then
      pure 0
    else if input == "/help" then
      IO.println replHelp
      replLoop runtime session
    else if input == "/context" then
      printReplContext runtime session
      replLoop runtime session
    else if input == "/session" then
      printSessionInfo runtime session
      replLoop runtime session
    else if input == "/commands" then
      IO.println (LeanAgent.Project.renderCommandList runtime.extensions)
      replLoop runtime session
    else if input == "/skills" then
      IO.println (LeanAgent.Project.renderSkillList runtime.extensions)
      replLoop runtime session
    else if input == "/clear" then
      IO.println "context cleared"
      replLoop runtime (LeanAgent.Session.clear session)
    else
      let updated ← runReplTurn runtime session input
      replLoop runtime updated

def runRepl (runtime : Runtime) (initialPrompt? : Option String) : IO UInt32 := do
  IO.println "lean-agent REPL. Type /help for commands, /exit to quit."
  let session ←
    match initialPrompt? with
    | none => pure runtime.session
    | some prompt =>
        let input := prompt.trimAscii.toString
        if input.isEmpty then
          pure runtime.session
        else
          runReplTurn runtime runtime.session input
  replLoop runtime session

def runOneShot (opts : CliOptions) (runtime : Runtime) : IO UInt32 := do
  if opts.continueRun then
    if runtime.session.agent.state.messages.isEmpty then
      IO.eprintln "--continue requires a non-empty --resume or --session file"
      return 2
    let beforeCount := runtime.session.agent.state.messages.size
    let agent ← runtime.session.agent.continue
    let _ ← persistSessionAgent runtime.session beforeCount agent
    return 0
  let prompt ← promptFromOptions opts
  if prompt.trimAscii.isEmpty then
    IO.eprintln "prompt must not be empty"
    return 2
  let expanded := LeanAgent.Project.expandPrompt runtime.extensions prompt
  let beforeCount := runtime.session.agent.state.messages.size
  let agent ← runtime.session.agent.prompt expanded
  let _ ← persistSessionAgent runtime.session beforeCount agent
  pure 0

def run (opts : CliOptions) : IO UInt32 := do
  if opts.help then
    IO.println usage
    return 0
  if opts.listModels then
    IO.println (LeanAgent.Models.renderCatalog LeanAgent.Models.defaultCatalog)
    return 0
  match ← runtimeFromOptions opts with
  | .error message =>
      IO.eprintln message
      pure 2
  | .ok runtime =>
      let runtime := runtimeWithEventSink runtime opts.repl
      if opts.repl then
        runRepl runtime opts.prompt
      else
        runOneShot opts runtime

def main (args : List String) : IO UInt32 := do
  match parseArgs args with
  | .ok opts =>
      try
        run opts
      catch err =>
        IO.eprintln err.toString
        pure 1
  | .error err =>
      IO.eprintln err
      IO.eprintln usage
      pure 2
