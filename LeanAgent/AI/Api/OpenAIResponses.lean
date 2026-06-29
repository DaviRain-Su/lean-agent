import LeanAgent.AI.Api.OpenAIPromptCache
import LeanAgent.AI.Api.OpenAIResponsesShared
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.JsonParse
import LeanAgent.AI.Util.Retry
import LeanAgent.Core
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.OpenAIResponses

open LeanAgent

structure OpenAIResponsesConfig where
  apiKey : String
  baseUrl : String := "https://api.openai.com/v1"
  headers : Array (String × String) := #[]
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

structure OpenAIResponsesOptions extends LeanAgent.AI.SimpleStreamOptions where
  reasoningEffort : Option LeanAgent.AI.ThinkingLevel := none
  reasoningSummary : Option String := none
  serviceTier : Option String := none
deriving BEq

def responsesUrl (baseUrl : String) : String :=
  if baseUrl.endsWith "/responses" then
    baseUrl
  else if baseUrl.endsWith "/" then
    baseUrl ++ "responses"
  else
    baseUrl ++ "/responses"

def cacheRetentionFromEnv? (env : Array (String × String)) : Option LeanAgent.AI.CacheRetention :=
  env.findSome? fun (name, value) =>
    if name == "PI_CACHE_RETENTION" && value == "long" then
      some .long
    else
      none

def resolveCacheRetention (options : OpenAIResponsesOptions) : LeanAgent.AI.CacheRetention :=
  match options.cacheRetention with
  | some retention => retention
  | none => (cacheRetentionFromEnv? options.env).getD .short

def reasoningEffortString : LeanAgent.AI.ThinkingLevel → String
  | .xhigh => "high"
  | level => level.toString

def requestOptionFields (options : OpenAIResponsesOptions) : List (String × Lean.Json) :=
  let maxTokenFields :=
    match options.maxTokens with
    | some maxTokens => [("max_output_tokens", LeanAgent.Json.nat maxTokens)]
    | none => []
  let temperatureFields :=
    match options.temperature with
    | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
    | none => []
  let serviceTierFields :=
    match options.serviceTier with
    | some tier => [("service_tier", LeanAgent.Json.str tier)]
    | none => []
  maxTokenFields ++ temperatureFields ++ serviceTierFields

def promptCacheFields (options : OpenAIResponsesOptions) : List (String × Lean.Json) :=
  let retention := resolveCacheRetention options
  if retention == .none then
    []
  else
    let keyFields :=
      match LeanAgent.AI.Api.OpenAIPromptCache.clampKey options.sessionId with
      | some key => [("prompt_cache_key", LeanAgent.Json.str key)]
      | none => []
    let retentionFields :=
      if retention == .long then
        [("prompt_cache_retention", LeanAgent.Json.str "24h")]
      else
        []
    keyFields ++ retentionFields

def reasoningFields
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (options : OpenAIResponsesOptions) : List (String × Lean.Json) :=
  if !model.reasoning then
    []
  else
    let effort? :=
      match options.reasoningEffort with
      | some effort => some effort
      | none => options.reasoning
    match effort?, options.reasoningSummary with
    | none, none =>
        [("reasoning", LeanAgent.Json.obj [("effort", LeanAgent.Json.str "none")])]
    | effort?, summary? =>
        let effort := reasoningEffortString (effort?.getD .medium)
        let summary := summary?.getD "auto"
        [ ("reasoning",
            LeanAgent.Json.obj
              [ ("effort", LeanAgent.Json.str effort)
              , ("summary", LeanAgent.Json.str summary)
              ])
        , ("include", LeanAgent.Json.arr #[LeanAgent.Json.str "reasoning.encrypted_content"])
        ]

def requestToJsonWithOptions
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAIResponsesOptions := {})
    (stream : Bool := false) : Lean.Json :=
  let input := LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesMessages model context
    (options := { syntheticTimestamp := 0 })
  let toolFields :=
    if context.tools.isEmpty then
      []
    else
      [ ("tools",
          LeanAgent.Json.arr
            (LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesTools context.tools))
      ]
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str model.id)
     , ("input", LeanAgent.Json.arr input)
     , ("stream", LeanAgent.Json.bool stream)
     , ("store", LeanAgent.Json.bool false)
     ] ++ promptCacheFields options
       ++ requestOptionFields options
       ++ toolFields
       ++ reasoningFields model options)

def requestHeaders (config : OpenAIResponsesConfig) (options : OpenAIResponsesOptions) :
    Array (String × String) :=
  let retention := resolveCacheRetention options
  let sessionHeaders :=
    if retention == .none then
      #[]
    else
      match options.sessionId with
      | some sessionId => #[("session_id", sessionId), ("x-client-request-id", sessionId)]
      | none => #[]
  LeanAgent.AI.Util.Headers.merge
    (LeanAgent.AI.Util.Headers.merge config.headers sessionHeaders)
    (LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers)

def runHttpJson
    (config : OpenAIResponsesConfig)
    (payload : Lean.Json)
    (options : OpenAIResponsesOptions := {}) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := responsesUrl config.baseUrl
      apiKey := config.apiKey
      headers := requestHeaders config options
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
    }
    payload.compress
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError (LeanAgent.AI.Util.Diagnostics.providerHttpErrorMessage response.status response.body))
  pure response.body

def jsonString? : Lean.Json → Option String
  | .str value => some value
  | _ => none

def optionalStringField (json : Lean.Json) (key : String) : Option String :=
  (LeanAgent.Json.optVal? json key).bind jsonString?

def parseUsage (rawUsage : Lean.Json) : LeanAgent.AI.Usage :=
  let inputTokens :=
    match LeanAgent.Json.optVal? rawUsage "input_tokens" with
    | some value => value.getNat?.toOption.getD 0
    | none => 0
  let outputTokens :=
    match LeanAgent.Json.optVal? rawUsage "output_tokens" with
    | some value => value.getNat?.toOption.getD 0
    | none => 0
  let totalTokens :=
    match LeanAgent.Json.optVal? rawUsage "total_tokens" with
    | some value => value.getNat?.toOption.getD (inputTokens + outputTokens)
    | none => inputTokens + outputTokens
  let cachedTokens :=
    match LeanAgent.Json.optVal? rawUsage "input_tokens_details" with
    | some details =>
        match LeanAgent.Json.optVal? details "cached_tokens" with
        | some value => value.getNat?.toOption.getD 0
        | none => 0
    | none => 0
  let reasoningTokens :=
    match LeanAgent.Json.optVal? rawUsage "output_tokens_details" with
    | some details =>
        match LeanAgent.Json.optVal? details "reasoning_tokens" with
        | some value => some (value.getNat?.toOption.getD 0)
        | none => none
    | none => none
  { input := inputTokens - cachedTokens
    output := outputTokens
    cacheRead := cachedTokens
    cacheWrite := 0
    reasoning := reasoningTokens
    totalTokens := totalTokens
  }

def parseUsage? (json : Lean.Json) : LeanAgent.AI.Usage :=
  match LeanAgent.Json.optVal? json "usage" with
  | some usage => parseUsage usage
  | none => {}

def mapStopReason (status? : Option String) : LeanAgent.AI.StopReason :=
  match status? with
  | some "completed" => .stop
  | some "incomplete" => .length
  | some "failed" => .error
  | some "cancelled" => .error
  | _ => .stop

def outputTextFromContentItem? (item : Lean.Json) : Option String :=
  match optionalStringField item "type" with
  | some "output_text" => optionalStringField item "text"
  | some "refusal" => optionalStringField item "refusal"
  | _ => none

def parseMessageText (item : Lean.Json) : String :=
  match LeanAgent.Json.optVal? item "content" with
  | some content =>
      match content.getArr? with
      | .ok parts =>
          String.intercalate "" (parts.toList.filterMap outputTextFromContentItem?)
      | .error _ => ""
  | none => ""

def parseReasoningText (item : Lean.Json) : String :=
  let textFromArray (key : String) :=
    match LeanAgent.Json.optVal? item key with
    | some value =>
        match value.getArr? with
        | .ok parts =>
            String.intercalate "\n\n"
              (parts.toList.filterMap fun part =>
                optionalStringField part "text")
        | .error _ => ""
    | none => ""
  let summary := textFromArray "summary"
  if summary.isEmpty then textFromArray "content" else summary

def parseToolArguments (raw : String) : Lean.Json :=
  match LeanAgent.AI.Util.JsonParse.parseJsonWithRepair raw with
  | .ok value => value
  | .error _ => LeanAgent.Json.obj []

def parseOutputItem (item : Lean.Json) : Array LeanAgent.AI.ContentBlock :=
  match optionalStringField item "type" with
  | some "message" =>
      let text := parseMessageText item
      if text.isEmpty then
        #[]
      else
        let signature :=
          match optionalStringField item "id" with
          | some id => some (LeanAgent.AI.Api.OpenAIResponsesShared.encodeTextSignatureV1 id)
          | none => none
        #[LeanAgent.AI.ContentBlock.text { text := text, textSignature := signature }]
  | some "function_call" =>
      let callId := optionalStringField item "call_id" |>.getD ""
      let itemId? := optionalStringField item "id"
      let id :=
        match itemId? with
        | some itemId => callId ++ "|" ++ itemId
        | none => callId
      let name := optionalStringField item "name" |>.getD ""
      let rawArgs := optionalStringField item "arguments" |>.getD "{}"
      #[LeanAgent.AI.ContentBlock.toolCall
        { id := id
          name := name
          arguments := parseToolArguments rawArgs
        }]
  | some "reasoning" =>
      let thinking := parseReasoningText item
      #[LeanAgent.AI.ContentBlock.thinking
        { thinking := thinking
          thinkingSignature := some item.compress
        }]
  | _ => #[]

def parseOutputContent (json : Lean.Json) : Array LeanAgent.AI.ContentBlock :=
  match LeanAgent.Json.optVal? json "output" with
  | some output =>
      match output.getArr? with
      | .ok items =>
          items.foldl (fun content item => content ++ parseOutputItem item) #[]
      | .error _ => #[]
  | none => #[]

def parseResponse
    (api provider model : String)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantMessage := do
  let json ← Lean.Json.parse raw
  if (LeanAgent.Json.optVal? json "error").isSome then
    throw (LeanAgent.AI.Util.Diagnostics.providerParseErrorMessage json.compress)
  let mut content := parseOutputContent json
  let mut stopReason := mapStopReason (optionalStringField json "status")
  if (content.any fun
      | .toolCall _ => true
      | _ => false) && stopReason == .stop then
    stopReason := .toolUse
  pure
    { content := content
      api := api
      provider := provider
      model := model
      responseId := optionalStringField json "id"
      usage := parseUsage? json
      stopReason := stopReason
      timestamp := timestamp
    }

def completeWithOptions
    (config : OpenAIResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAIResponsesOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let payload := requestToJsonWithOptions model context options false
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config payload options)
  let timestamp ← IO.monoMsNow
  match parseResponse model.api model.provider model.id timestamp raw with
  | .ok response => pure response
  | .error err => throw (IO.userError s!"failed to parse provider response: {err}\n{raw}")

def completeStreamWithOptions
    (config : OpenAIResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAIResponsesOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  let response ← completeWithOptions config model context options
  pure (LeanAgent.AI.fromMessage response)

end LeanAgent.AI.Api.OpenAIResponses
