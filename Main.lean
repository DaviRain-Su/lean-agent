import LeanAgent

open LeanAgent

structure CliOptions where
  prompt : Option String := none
  cwd : Option System.FilePath := none
  model : Option String := none
  baseUrl : Option String := none
  apiKeyEnv : Option String := none
  maxTurns : Nat := 8
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
    , ""
    , "Options:"
    , "  -p, --prompt TEXT        One-shot prompt. If omitted, read one line from stdin."
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

def run (opts : CliOptions) : IO UInt32 := do
  if opts.help then
    IO.println usage
    return 0

  let prompt ← promptFromOptions opts
  if prompt.trimAscii.isEmpty then
    IO.eprintln "prompt must not be empty"
    return 2

  let cwd ← resolveWorkingDir opts
  let apiKeyEnv ← resolveApiKeyEnv opts
  let baseUrl := resolveBaseUrl opts apiKeyEnv
  let model ← resolveModel opts apiKeyEnv
  let noProxy ← resolveNoProxy baseUrl
  let apiKey? ← IO.getEnv apiKeyEnv
  let apiKey :=
    match apiKey? with
    | some value =>
        if value.trimAscii.isEmpty then "" else value
    | none => ""
  if apiKey.isEmpty then
    IO.eprintln s!"missing API key: set {apiKeyEnv} or pass --api-key-env"
    return 2

  let provider := LeanAgent.OpenAI.provider
    { apiKey := apiKey
      baseUrl := baseUrl
      noProxy := noProxy
    }
  let tools := LeanAgent.CodingTools.defaultTools cwd
  let _ ← runAgentLoop
    { provider := provider
      model := model
      system := defaultSystemPrompt
      tools := tools
      maxTurns := opts.maxTurns
    }
    #[.user prompt]
    renderEvent
  pure 0

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
