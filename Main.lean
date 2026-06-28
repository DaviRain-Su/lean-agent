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
  help : Bool := false

def deepSeekApiKeyEnv : String := "DEEPSEEK_API_KEY"
def deepSeekModelEnv : String := "DEEPSEEK_MODEL"
def deepSeekDefaultModel : String := "deepseek-v4-flash"
def deepSeekProModel : String := "deepseek-v4-pro"
def deepSeekBaseUrl : String := "https://api.deepseek.com"

def openAIKeyEnv : String := "OPENAI_API_KEY"
def openAIModelEnv : String := "OPENAI_MODEL"
def openAIDefaultModel : String := "gpt-4.1-mini"
def openAIBaseUrl : String := "https://api.openai.com/v1"
def leanAgentNoProxyEnv : String := "LEAN_AGENT_NO_PROXY"

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

def envOrDefault (name fallback : String) : IO String := do
  match ← IO.getEnv name with
  | some value =>
      if value.trimAscii.isEmpty then pure fallback else pure value
  | none => pure fallback

def envIsSet (name : String) : IO Bool := do
  match ← IO.getEnv name with
  | some value => pure (!value.trimAscii.isEmpty)
  | none => pure false

def resolveApiKeyEnv (opts : CliOptions) : IO String := do
  match opts.apiKeyEnv with
  | some name => pure name
  | none =>
      if ← envIsSet deepSeekApiKeyEnv then
        pure deepSeekApiKeyEnv
      else
        pure openAIKeyEnv

def resolveBaseUrl (opts : CliOptions) (apiKeyEnv : String) : String :=
  match opts.baseUrl with
  | some url => url
  | none =>
      if apiKeyEnv == deepSeekApiKeyEnv then deepSeekBaseUrl else openAIBaseUrl

def resolveModel (opts : CliOptions) (apiKeyEnv : String) : IO String := do
  match opts.model with
  | some model => pure model
  | none =>
      if apiKeyEnv == deepSeekApiKeyEnv then
        envOrDefault deepSeekModelEnv deepSeekDefaultModel
      else
        envOrDefault openAIModelEnv openAIDefaultModel

def resolveNoProxy (baseUrl : String) : IO (Option String) := do
  match ← IO.getEnv leanAgentNoProxyEnv with
  | some value =>
      let trimmed := value.trimAscii.toString
      pure (if trimmed.isEmpty then none else some trimmed)
  | none =>
      if baseUrl.startsWith deepSeekBaseUrl then
        pure (some "api.deepseek.com")
      else
        pure none

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
  agent : AgentLoopConfig

def apiKeyValue (apiKeyEnv : String) : IO String := do
  match ← IO.getEnv apiKeyEnv with
  | some value =>
      if value.trimAscii.isEmpty then pure "" else pure value
  | none => pure ""

def runtimeFromOptions (opts : CliOptions) : IO (Except String Runtime) := do
  let cwd ← resolveWorkingDir opts
  let apiKeyEnv ← resolveApiKeyEnv opts
  let baseUrl := resolveBaseUrl opts apiKeyEnv
  let model ← resolveModel opts apiKeyEnv
  let noProxy ← resolveNoProxy baseUrl
  let apiKey ← apiKeyValue apiKeyEnv
  if apiKey.isEmpty then
    pure (.error s!"missing API key: set {apiKeyEnv} or pass --api-key-env")
  else
    let provider := LeanAgent.OpenAI.provider
      { apiKey := apiKey
        baseUrl := baseUrl
        noProxy := noProxy
      }
    let tools := LeanAgent.CodingTools.defaultTools cwd
    pure
      (.ok
        { cwd := cwd
          model := model
          agent :=
            { provider := provider
              model := model
              system := defaultSystemPrompt
              tools := tools
              maxTurns := opts.maxTurns
            }
        })

def renderToolCall (call : ToolCall) : String :=
  "-> " ++ call.name ++ " " ++ call.arguments.compress

def renderEvent : EventSink
  | .agentStart => IO.println "agent:start"
  | .agentEnd => IO.println "agent:end"
  | .turnStart turn => IO.println s!"turn:{turn}:start"
  | .turnEnd turn => IO.println s!"turn:{turn}:end"
  | .messageStart role => IO.println s!"message:{role}:start"
  | .messageDelta delta => IO.println delta
  | .messageEnd (.assistant _ calls) => do
      for call in calls do
        IO.println (renderToolCall call)
      IO.println "message:assistant:end"
  | .messageEnd _ => IO.println "message:end"
  | .toolExecutionStart call => IO.println s!"tool:{call.name}:start"
  | .toolExecutionEnd result => do
      IO.println s!"tool:{result.name}:{resultStatus result}"
      if !result.content.trimAscii.isEmpty then
        IO.println result.content
  | .error message => IO.eprintln s!"error: {message}"

def renderReplEvent : EventSink
  | .agentStart => pure ()
  | .agentEnd => pure ()
  | .turnStart turn =>
      if turn > 1 then
        IO.println s!"[agent turn {turn}]"
      else
        pure ()
  | .turnEnd _ => pure ()
  | .messageStart "assistant" => IO.println "assistant:"
  | .messageStart _ => pure ()
  | .messageDelta delta =>
      if !delta.trimAscii.isEmpty then
        IO.println delta
      else
        pure ()
  | .messageEnd (.assistant _ calls) => do
      for call in calls do
        IO.println s!"[tool request] {renderToolCall call}"
  | .messageEnd _ => pure ()
  | .toolExecutionStart call => IO.println s!"[tool] {call.name}:start"
  | .toolExecutionEnd result => do
      IO.println s!"[tool] {result.name}:{resultStatus result}"
      if !result.content.trimAscii.isEmpty then
        IO.println result.content
  | .error message => IO.eprintln s!"error: {message}"

def replHelp : String :=
  String.intercalate "\n"
    [ "REPL commands:"
    , "  /help      Show this help."
    , "  /context   Show current model, cwd, and message count."
    , "  /clear     Clear conversation context."
    , "  /exit      Exit the REPL."
    , "  /quit      Exit the REPL."
    ]

def isExitCommand (input : String) : Bool :=
  input == "/exit" || input == "/quit" || input == ":q"

def printReplContext (runtime : Runtime) (messages : Array AgentMessage) : IO Unit := do
  IO.println s!"model: {runtime.model}"
  IO.println s!"cwd: {runtime.cwd}"
  IO.println s!"messages: {messages.size}"

def runReplTurn (runtime : Runtime) (messages : Array AgentMessage) (input : String) :
    IO (Array AgentMessage) := do
  runAgentLoop runtime.agent (messages.push (.user input)) renderReplEvent

partial def replLoop (runtime : Runtime) (messages : Array AgentMessage) : IO UInt32 := do
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
      replLoop runtime messages
    else if isExitCommand input then
      pure 0
    else if input == "/help" then
      IO.println replHelp
      replLoop runtime messages
    else if input == "/context" then
      printReplContext runtime messages
      replLoop runtime messages
    else if input == "/clear" then
      IO.println "context cleared"
      replLoop runtime #[]
    else
      let updated ← runReplTurn runtime messages input
      replLoop runtime updated

def runRepl (runtime : Runtime) (initialPrompt? : Option String) : IO UInt32 := do
  IO.println "lean-agent REPL. Type /help for commands, /exit to quit."
  let messages ←
    match initialPrompt? with
    | none => pure #[]
    | some prompt =>
        let input := prompt.trimAscii.toString
        if input.isEmpty then
          pure #[]
        else
          runReplTurn runtime #[] input
  replLoop runtime messages

def runOneShot (opts : CliOptions) (runtime : Runtime) : IO UInt32 := do
  let prompt ← promptFromOptions opts
  if prompt.trimAscii.isEmpty then
    IO.eprintln "prompt must not be empty"
    return 2
  let _ ← runAgentLoop runtime.agent #[.user prompt] renderEvent
  pure 0

def run (opts : CliOptions) : IO UInt32 := do
  if opts.help then
    IO.println usage
    return 0
  match ← runtimeFromOptions opts with
  | .error message =>
      IO.eprintln message
      pure 2
  | .ok runtime =>
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
