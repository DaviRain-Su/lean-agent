import Lean
import LeanAgent.AI.Api.OpenAIPromptCache
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Retry
import LeanAgent.Core
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.OpenAICompletions

open LeanAgent

structure OpenAICompatibleConfig where
  apiKey : String
  baseUrl : String := "https://api.openai.com/v1"
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

inductive ToolChoice where
  | auto
  | none
  | required
  | function (name : String)
deriving BEq

structure OpenAICompletionsOptions extends LeanAgent.AI.SimpleStreamOptions where
  toolChoice : Option ToolChoice := none
  reasoningEffort : Option LeanAgent.AI.ThinkingLevel := none
deriving BEq

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : OpenAICompletionsOptions :=
  { temperature := options.temperature
    maxTokens := options.maxTokens
    apiKey := options.apiKey
    transport := options.transport
    cacheRetention := options.cacheRetention
    sessionId := options.sessionId
    headers := options.headers
    timeoutMs := options.timeoutMs
    websocketConnectTimeoutMs := options.websocketConnectTimeoutMs
    maxRetries := options.maxRetries
    maxRetryDelayMs := options.maxRetryDelayMs
    metadata := options.metadata
    env := options.env
    reasoning := options.reasoning
    thinkingBudgets := options.thinkingBudgets
  }

def chatCompletionsUrl (baseUrl : String) : String :=
  if baseUrl.endsWith "/chat/completions" then
    baseUrl
  else if baseUrl.endsWith "/" then
    baseUrl ++ "chat/completions"
  else
    baseUrl ++ "/chat/completions"

def ToolChoice.toJson : ToolChoice → Lean.Json
  | .auto => LeanAgent.Json.str "auto"
  | .none => LeanAgent.Json.str "none"
  | .required => LeanAgent.Json.str "required"
  | .function name =>
      LeanAgent.Json.obj
        [ ("type", LeanAgent.Json.str "function")
        , ("function", LeanAgent.Json.obj [("name", LeanAgent.Json.str name)])
        ]

def reasoningEffortString : LeanAgent.AI.ThinkingLevel → String
  | .xhigh => "high"
  | level => level.toString

def toolCallToJson (call : LeanAgent.ToolCall) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("id", LeanAgent.Json.str call.id)
    , ("type", LeanAgent.Json.str "function")
    , ("function",
        LeanAgent.Json.obj
          [ ("name", LeanAgent.Json.str call.name)
          , ("arguments", LeanAgent.Json.str call.arguments.compress)
          ])
    ]

def messageHasToolCall : LeanAgent.AgentMessage → Bool
  | .assistant _ calls => !calls.isEmpty
  | .toolResult _ _ _ _ => true
  | _ => false

def hasToolHistory (messages : Array LeanAgent.AgentMessage) : Bool :=
  messages.any messageHasToolCall

def messageToJson : AgentMessage → Lean.Json
  | .user content =>
      LeanAgent.Json.obj [("role", LeanAgent.Json.str "user"), ("content", LeanAgent.Json.str content)]
  | .assistant content calls =>
      let fields :=
        [ ("role", LeanAgent.Json.str "assistant")
        , ("content", if content.isEmpty then LeanAgent.Json.null else LeanAgent.Json.str content)
        ]
      if calls.isEmpty then
        LeanAgent.Json.obj fields
      else
        LeanAgent.Json.obj (fields ++ [("tool_calls", LeanAgent.Json.arr (calls.map toolCallToJson))])
  | .toolResult toolCallId _name content _ok =>
      LeanAgent.Json.obj
        [ ("role", LeanAgent.Json.str "tool")
        , ("tool_call_id", LeanAgent.Json.str toolCallId)
        , ("content", LeanAgent.Json.str content)
        ]

def toolToJson (tool : AgentTool) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "function")
    , ("function",
        LeanAgent.Json.obj
          [ ("name", LeanAgent.Json.str tool.name)
          , ("description", LeanAgent.Json.str tool.description)
          , ("parameters", tool.inputSchema)
          ])
    ]

def requestToolFields
    (request : ProviderRequest)
    (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  if !request.tools.isEmpty || hasToolHistory request.messages then
    [ ("tools", LeanAgent.Json.arr (request.tools.map toolToJson))
    , ("tool_choice", (options.toolChoice.getD .auto).toJson)
    ]
  else
    []

def requestOptionFields (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  let temperatureFields :=
    match options.temperature with
    | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
    | none => []
  let maxTokenFields :=
    match options.maxTokens with
    | some maxTokens => [("max_tokens", LeanAgent.Json.nat maxTokens)]
    | none => []
  let reasoning :=
    match options.reasoningEffort with
    | some effort => some effort
    | none => options.reasoning
  let reasoningFields :=
    match reasoning with
    | some effort => [("reasoning_effort", LeanAgent.Json.str (reasoningEffortString effort))]
    | none => []
  temperatureFields ++ maxTokenFields ++ reasoningFields

def cacheRetentionFromEnv? (env : Array (String × String)) : Option LeanAgent.AI.CacheRetention :=
  env.findSome? fun (name, value) =>
    if name == "PI_CACHE_RETENTION" && value == "long" then
      some .long
    else
      none

def resolveCacheRetention (options : OpenAICompletionsOptions) : LeanAgent.AI.CacheRetention :=
  match options.cacheRetention with
  | some retention => retention
  | none => (cacheRetentionFromEnv? options.env).getD .short

def promptCacheFields (baseUrl : String) (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  let retention := resolveCacheRetention options
  if retention == .none then
    []
  else
    let supportsPromptCacheKey := baseUrl.contains "api.openai.com" || retention == .long
    let keyFields :=
      if supportsPromptCacheKey then
        match LeanAgent.AI.Api.OpenAIPromptCache.clampKey options.sessionId with
        | some key => [("prompt_cache_key", LeanAgent.Json.str key)]
        | none => []
      else
        []
    let retentionFields :=
      if retention == .long then
        [("prompt_cache_retention", LeanAgent.Json.str "24h")]
      else
        []
    keyFields ++ retentionFields

def requestToJsonWithOptions
    (request : ProviderRequest)
    (options : OpenAICompletionsOptions := {})
    (baseUrl : String := "") : Lean.Json :=
  let messages :=
    #[LeanAgent.Json.obj [("role", LeanAgent.Json.str "system"), ("content", LeanAgent.Json.str request.system)]]
      ++ request.messages.map messageToJson
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str request.model)
     , ("messages", LeanAgent.Json.arr messages)
     ] ++ requestOptionFields options
       ++ promptCacheFields baseUrl options
       ++ requestToolFields request options)

def requestToJson (request : ProviderRequest) : Lean.Json :=
  requestToJsonWithOptions request

def runHttpJson (config : OpenAICompatibleConfig) (payload : Lean.Json) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := chatCompletionsUrl config.baseUrl
      apiKey := config.apiKey
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
    }
    payload.compress
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError s!"provider HTTP {response.status}: {response.body}")
  pure response.body

def parseMaybeContent (message : Lean.Json) : String :=
  match LeanAgent.Json.optVal? message "content" with
  | some (Lean.Json.str content) => content
  | _ => ""

def parseToolArguments (raw : String) : Except String Lean.Json :=
  if raw.trimAscii.isEmpty then
    pure (LeanAgent.Json.obj [])
  else
    LeanAgent.Json.parseObjectString raw

def parseToolCall (json : Lean.Json) : Except String LeanAgent.ToolCall := do
  let id ← (← json.getObjVal? "id").getStr?
  let fn ← json.getObjVal? "function"
  let name ← (← fn.getObjVal? "name").getStr?
  let rawArgs ← (← fn.getObjVal? "arguments").getStr?
  let arguments ← parseToolArguments rawArgs
  pure { id := id, name := name, arguments := arguments }

def parseToolCalls (message : Lean.Json) : Except String (Array LeanAgent.ToolCall) := do
  match LeanAgent.Json.optVal? message "tool_calls" with
  | none => pure #[]
  | some Lean.Json.null => pure #[]
  | some value =>
      let rawCalls ← value.getArr?
      let mut calls := #[]
      for rawCall in rawCalls do
        calls := calls.push (← parseToolCall rawCall)
      pure calls

def parseChatCompletion (raw : String) : Except String LeanAgent.ProviderResponse := do
  let json ← Lean.Json.parse raw
  if let some err := LeanAgent.Json.optVal? json "error" then
    let message :=
      match LeanAgent.Json.optVal? err "message" with
      | some (Lean.Json.str text) => text
      | _ => err.compress
    throw message
  let choices ← (← json.getObjVal? "choices").getArr?
  let choice ←
    match choices[0]? with
    | some choice => pure choice
    | none => throw "OpenAI response contained no choices"
  let message ← choice.getObjVal? "message"
  let finishReason :=
    match LeanAgent.Json.optVal? choice "finish_reason" with
    | some (Lean.Json.str value) => some value
    | _ => none
  let toolCalls ← parseToolCalls message
  pure
    { content := parseMaybeContent message
      toolCalls := toolCalls
      finishReason := finishReason
    }

def completeWithOptions
    (config : OpenAICompatibleConfig)
    (request : ProviderRequest)
  (options : OpenAICompletionsOptions := {}) : IO LeanAgent.ProviderResponse := do
  let payload := requestToJsonWithOptions request options config.baseUrl
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy (runHttpJson config payload)
  match parseChatCompletion raw with
  | .ok response => pure response
  | .error err => throw (IO.userError s!"failed to parse provider response: {err}\n{raw}")

def provider (config : OpenAICompatibleConfig) : LeanAgent.ModelProvider :=
  { complete := fun request => completeWithOptions config request }

end LeanAgent.AI.Api.OpenAICompletions
