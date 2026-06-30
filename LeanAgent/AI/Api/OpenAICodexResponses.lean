import LeanAgent.AI.Api.OpenAIPromptCache
import LeanAgent.AI.Api.OpenAIResponses
import LeanAgent.AI.Api.OpenAIResponsesShared
import LeanAgent.AI.Api.SimpleOptions
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.Retry
import LeanAgent.Core
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.OpenAICodexResponses

open LeanAgent

def api : String := "openai-codex-responses"
def defaultBaseUrl : String := "https://chatgpt.com/backend-api"
def jwtClaimPath : String := "https://api.openai.com/auth"

def codexToolCallProviders : Array String :=
  #["openai", "openai-codex", "opencode"]

structure OpenAICodexResponsesConfig where
  apiKey : String
  baseUrl : String := defaultBaseUrl
  headers : Array (String × String) := #[]
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "pi (lean-agent)"

structure OpenAICodexResponsesOptions extends LeanAgent.AI.SimpleStreamOptions where
  reasoningEffort : Option LeanAgent.AI.ModelThinkingLevel := none
  reasoningSummary : Option String := none
  serviceTier : Option String := none
  textVerbosity : Option String := none

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : OpenAICodexResponsesOptions :=
  { temperature := options.temperature
    maxTokens := options.maxTokens
    signal := options.signal
    apiKey := options.apiKey
    transport := options.transport
    cacheRetention := options.cacheRetention
    sessionId := options.sessionId
    headers := options.headers
    onPayload := options.onPayload
    onResponse := options.onResponse
    timeoutMs := options.timeoutMs
    websocketConnectTimeoutMs := options.websocketConnectTimeoutMs
    maxRetries := options.maxRetries
    maxRetryDelayMs := options.maxRetryDelayMs
    metadata := options.metadata
    env := options.env
    reasoning := options.reasoning
    thinkingBudgets := options.thinkingBudgets
    reasoningEffort := options.reasoning.map LeanAgent.AI.ModelThinkingLevel.level
  }

def OpenAICodexResponsesOptions.toOpenAIResponsesOptions
    (options : OpenAICodexResponsesOptions) :
    LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesOptions :=
  { temperature := options.temperature
    maxTokens := options.maxTokens
    apiKey := options.apiKey
    transport := options.transport
    cacheRetention := options.cacheRetention
    sessionId := options.sessionId
    headers := options.headers
    onPayload := options.onPayload
    onResponse := options.onResponse
    timeoutMs := options.timeoutMs
    websocketConnectTimeoutMs := options.websocketConnectTimeoutMs
    maxRetries := options.maxRetries
    maxRetryDelayMs := options.maxRetryDelayMs
    metadata := options.metadata
    env := options.env
    reasoning := options.reasoning
    thinkingBudgets := options.thinkingBudgets
    reasoningEffort :=
      match options.reasoningEffort with
      | some (.level level) => some level
      | _ => none
    reasoningSummary := options.reasoningSummary
    serviceTier := options.serviceTier
  }

def stripTrailingSlashes (value : String) : String :=
  String.ofList ((value.toList.reverse.dropWhile (fun char => char == '/')).reverse)

def codexResponsesUrl (baseUrl : String) : String :=
  let raw :=
    let trimmed := baseUrl.trimAscii.toString
    if trimmed.isEmpty then defaultBaseUrl else trimmed
  let normalized := stripTrailingSlashes raw
  if normalized.endsWith "/codex/responses" then
    normalized
  else if normalized.endsWith "/codex" then
    normalized ++ "/responses"
  else
    normalized ++ "/codex/responses"

def base64UrlValue? (char : Char) : Option Nat :=
  if 'A' <= char && char <= 'Z' then
    some (char.toNat - 'A'.toNat)
  else if 'a' <= char && char <= 'z' then
    some (26 + char.toNat - 'a'.toNat)
  else if '0' <= char && char <= '9' then
    some (52 + char.toNat - '0'.toNat)
  else if char == '-' then
    some 62
  else if char == '_' then
    some 63
  else
    none

def base64UrlValues (chars : List Char) : Except String (List Nat) :=
  chars.mapM fun char =>
    match base64UrlValue? char with
    | some value => pure value
    | none => throw s!"invalid base64url character: {char}"

def decodeBase64UrlValues : List Nat → Except String (List Nat)
  | [] => pure []
  | a :: b :: [] =>
      pure [a * 4 + b / 16]
  | a :: b :: c :: [] =>
      pure [a * 4 + b / 16, (b % 16) * 16 + c / 4]
  | a :: b :: c :: d :: rest => do
      let bytes :=
        [ a * 4 + b / 16
        , (b % 16) * 16 + c / 4
        , (c % 4) * 64 + d
        ]
      pure (bytes ++ (← decodeBase64UrlValues rest))
  | _ => throw "invalid base64url payload length"

def base64UrlDecodeToString (value : String) : Except String String := do
  let chars := value.toList.filter (fun char => char != '=')
  if chars.length % 4 == 1 then
    throw "invalid base64url payload length"
  let values ← base64UrlValues chars
  let bytes ← decodeBase64UrlValues values
  if bytes.any (fun byte => byte > 255) then
    throw "invalid decoded byte"
  pure (String.ofList (bytes.map Char.ofNat))

def accountIdFromPayload (payload : Lean.Json) : Except String String := do
  let auth ← payload.getObjVal? jwtClaimPath
  let accountId ← (← auth.getObjVal? "chatgpt_account_id").getStr?
  if accountId.trimAscii.isEmpty then
    throw "No account ID in token"
  pure accountId

def extractAccountId (token : String) : Except String String := do
  match token.splitOn "." with
  | _header :: payload :: _signature :: [] =>
      let decoded ← base64UrlDecodeToString payload
      let json ← Lean.Json.parse decoded
      accountIdFromPayload json
  | _ => throw "Invalid token"

def promptCacheFields (options : OpenAICodexResponsesOptions) : List (String × Lean.Json) :=
  match LeanAgent.AI.Api.OpenAIPromptCache.clampKey options.sessionId with
  | some key => [("prompt_cache_key", LeanAgent.Json.str key)]
  | none => []

def requestOptionFields
    (options : OpenAICodexResponsesOptions) : List (String × Lean.Json) :=
  let temperatureFields :=
    match options.temperature with
    | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
    | none => []
  let serviceTierFields :=
    match options.serviceTier with
    | some serviceTier => [("service_tier", LeanAgent.Json.str serviceTier)]
    | none => []
  temperatureFields ++ serviceTierFields

def reasoningEffortValue?
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (effort : LeanAgent.AI.ModelThinkingLevel) : Option String :=
  match effort with
  | .off =>
      match LeanAgent.AI.Api.OpenAIResponses.thinkingLevelMapValue? model .off with
      | some none => none
      | some (some value) => some value
      | none => some "none"
  | .level level =>
      match LeanAgent.AI.Api.OpenAIResponses.thinkingLevelMapValue? model (.level level) with
      | some none => none
      | some (some value) => some value
      | none => some level.toString

def reasoningFields
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (options : OpenAICodexResponsesOptions) : List (String × Lean.Json) :=
  match options.reasoningEffort with
  | none => []
  | some effort =>
      match reasoningEffortValue? model effort with
      | none => []
      | some mapped =>
          [ ("reasoning",
              LeanAgent.Json.obj
                [ ("effort", LeanAgent.Json.str mapped)
                , ("summary", LeanAgent.Json.str (options.reasoningSummary.getD "auto"))
                ])
          ]

def requestToJsonWithOptions
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAICodexResponsesOptions := {}) : Lean.Json :=
  let input := LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesMessages
    model
    context
    codexToolCallProviders
    { includeSystemPrompt := false, syntheticTimestamp := 0 }
  let toolFields :=
    if context.tools.isEmpty then
      []
    else
      [ ("tools",
          LeanAgent.Json.arr
            (LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesTools context.tools none))
      ]
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str model.id)
     , ("store", LeanAgent.Json.bool false)
     , ("stream", LeanAgent.Json.bool true)
     , ("instructions", LeanAgent.Json.str (context.systemPrompt.getD "You are a helpful assistant."))
     , ("input", LeanAgent.Json.arr input)
     , ("text", LeanAgent.Json.obj [("verbosity", LeanAgent.Json.str (options.textVerbosity.getD "low"))])
     , ("include", LeanAgent.Json.arr #[LeanAgent.Json.str "reasoning.encrypted_content"])
     , ("tool_choice", LeanAgent.Json.str "auto")
     , ("parallel_tool_calls", LeanAgent.Json.bool true)
     ] ++ promptCacheFields options
       ++ requestOptionFields options
       ++ toolFields
       ++ reasoningFields model options)

def requestHeaders
    (config : OpenAICodexResponsesConfig)
    (accountId : String)
    (options : OpenAICodexResponsesOptions) :
    Array (String × String) :=
  let sessionHeaders :=
    match options.sessionId with
    | some sessionId => #[("session-id", sessionId), ("x-client-request-id", sessionId)]
    | none => #[]
  LeanAgent.AI.Util.Headers.merge
    (LeanAgent.AI.Util.Headers.merge
      (LeanAgent.AI.Util.Headers.merge
        config.headers
        #[ ("chatgpt-account-id", accountId)
         , ("originator", "pi")
         , ("OpenAI-Beta", "responses=experimental")
         , ("Accept", "text/event-stream")
         , ("Content-Type", "application/json")
         ])
      sessionHeaders)
    (LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers)

def modelRef
    (config : OpenAICodexResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel) : LeanAgent.AI.ModelRef :=
  { id := model.id
    api := model.api
    provider := model.provider
    baseUrl := some config.baseUrl
  }

def runHttpJson
    (config : OpenAICodexResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (payload : Lean.Json)
    (options : OpenAICodexResponsesOptions := {}) : IO String := do
  let accountId ←
    match extractAccountId config.apiKey with
    | .ok accountId => pure accountId
    | .error err => throw (IO.userError s!"Failed to extract accountId from token: {err}")
  let response ← LeanAgent.Http.postJsonResponse
    { url := codexResponsesUrl config.baseUrl
      apiKey := config.apiKey
      signal := options.signal
      headers := requestHeaders config accountId options
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
    }
    payload.compress
  LeanAgent.AI.Api.OpenAIResponses.callResponseHook
    options.toOpenAIResponsesOptions
    (modelRef config model)
    response
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError (LeanAgent.AI.Util.Diagnostics.providerHttpErrorMessage response.status response.body))
  pure response.body

def completeStreamWithOptions
    (config : OpenAICodexResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAICodexResponsesOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  LeanAgent.AI.Util.Abort.throwIfAborted options.signal
  let ref := modelRef config model
  let payload ← LeanAgent.AI.Api.OpenAIResponses.applyPayloadHook
    options.toOpenAIResponsesOptions
    ref
    (requestToJsonWithOptions model context options)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config model payload options)
    options.signal
  let timestamp ← IO.monoMsNow
  match LeanAgent.AI.Api.OpenAIResponses.parseStreamingEventStream model.api model.provider model.id timestamp raw with
  | .ok stream =>
      pure (LeanAgent.AI.Api.OpenAIResponses.applyStreamUsageCost
        model
        options.toOpenAIResponsesOptions
        stream)
  | .error err => throw (IO.userError s!"failed to parse Codex streaming provider response: {err}\n{raw}")

end LeanAgent.AI.Api.OpenAICodexResponses
