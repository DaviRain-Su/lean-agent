import LeanAgent.AI.Api.OpenAIPromptCache
import LeanAgent.AI.Api.OpenAIResponses
import LeanAgent.AI.Api.OpenAIResponsesShared
import LeanAgent.AI.EnvApiKeys
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.Retry
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.AzureOpenAIResponses

open LeanAgent

def defaultAzureApiVersion : String := "v1"

def azureToolCallProviders : Array String :=
  #["openai", "openai-codex", "opencode", "azure-openai-responses"]

structure AzureOpenAIResponsesConfig where
  apiKey : String
  baseUrl : String := ""
  headers : Array (String × String) := #[]
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

structure AzureOpenAIResponsesOptions extends LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesOptions where
  azureApiVersion : Option String := none
  azureResourceName : Option String := none
  azureBaseUrl : Option String := none
  azureDeploymentName : Option String := none

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : AzureOpenAIResponsesOptions :=
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
    reasoningEffort := options.reasoning
  }

structure AzureResolvedConfig where
  baseUrl : String
  apiVersion : String
deriving BEq

def trimNonEmpty? (value? : Option String) : Option String :=
  match value? with
  | some value =>
      let trimmed := value.trimAscii.toString
      if trimmed.isEmpty then none else some trimmed
  | none => none

def splitOnce (value separator : String) : String × Option String :=
  match value.splitOn separator with
  | [] => (value, none)
  | head :: [] => (head, none)
  | head :: rest => (head, some (String.intercalate separator rest))

def firstSegment (value separator : String) : String :=
  match value.splitOn separator with
  | [] => value
  | head :: _ => head

def stripTrailingSlashes (value : String) : String :=
  String.ofList ((value.toList.reverse.dropWhile (fun char => char == '/')).reverse)

def urlHostAndPath? (baseUrl : String) : Option (String × String × String) :=
  let trimmed := stripTrailingSlashes baseUrl.trimAscii.toString
  let (protocol, rest?) := splitOnce trimmed "://"
  match rest? with
  | none => none
  | some rest =>
      let (beforePath, afterSlash?) := splitOnce rest "/"
      let host := firstSegment (firstSegment beforePath "?") "#"
      if protocol.isEmpty || host.isEmpty then
        none
      else
        let path :=
          match afterSlash? with
          | some value => "/" ++ value
          | none => ""
        some (protocol, host, path)

def normalizedPath (path : String) : String :=
  stripTrailingSlashes (firstSegment (firstSegment path "?") "#")

def isAzureHost (host : String) : Bool :=
  let host := host.toLower
  host.endsWith ".openai.azure.com" ||
    host.endsWith ".cognitiveservices.azure.com" ||
    host.endsWith ".ai.azure.com"

def shouldRewriteAzurePath (path : String) : Bool :=
  let path := normalizedPath path
  path.isEmpty || path == "/" || path == "/openai" || path == "/openai/v1/responses"

def normalizeAzureBaseUrl (baseUrl : String) : Except String String := do
  let trimmed := stripTrailingSlashes baseUrl.trimAscii.toString
  let (protocol, host, path) ←
    match urlHostAndPath? trimmed with
    | some value => pure value
    | none => throw s!"Invalid Azure OpenAI base URL: {baseUrl}"
  if isAzureHost host && shouldRewriteAzurePath path then
    pure s!"{protocol}://{host}/openai/v1"
  else
    pure trimmed

def buildDefaultBaseUrl (resourceName : String) : String :=
  s!"https://{resourceName}.openai.azure.com/openai/v1"

def parseDeploymentNameMap (value : Option String) : Array (String × String) :=
  match value with
  | none => #[]
  | some value =>
      value.splitOn "," |>.toArray |>.filterMap fun entry =>
        let trimmed := entry.trimAscii.toString
        if trimmed.isEmpty then
          none
        else
          let (modelId, deployment?) := splitOnce trimmed "="
          match deployment? with
          | some deployment =>
              let modelId := modelId.trimAscii.toString
              let deployment := deployment.trimAscii.toString
              if modelId.isEmpty || deployment.isEmpty then none else some (modelId, deployment)
          | none => none

def deploymentNameMapGet? (entries : Array (String × String)) (modelId : String) : Option String :=
  entries.findSome? fun (id, deployment) =>
    if id == modelId then some deployment else none

def resolveDeploymentName
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (options : AzureOpenAIResponsesOptions := {}) : IO String := do
  match trimNonEmpty? options.azureDeploymentName with
  | some deployment => pure deployment
  | none =>
      let rawMap ← LeanAgent.AI.EnvApiKeys.envValue? options.env "AZURE_OPENAI_DEPLOYMENT_NAME_MAP"
      pure ((deploymentNameMapGet? (parseDeploymentNameMap rawMap) model.id).getD model.id)

def resolveAzureConfig
    (config : AzureOpenAIResponsesConfig)
    (options : AzureOpenAIResponsesOptions := {}) : IO AzureResolvedConfig := do
  let apiVersion ←
    match trimNonEmpty? options.azureApiVersion with
    | some value => pure value
    | none =>
        match ← LeanAgent.AI.EnvApiKeys.envValue? options.env "AZURE_OPENAI_API_VERSION" with
        | some value => pure value
        | none => pure defaultAzureApiVersion
  let baseUrlFromEnv ← LeanAgent.AI.EnvApiKeys.envValue? options.env "AZURE_OPENAI_BASE_URL"
  let resourceFromEnv ← LeanAgent.AI.EnvApiKeys.envValue? options.env "AZURE_OPENAI_RESOURCE_NAME"
  let baseUrl? :=
    match trimNonEmpty? options.azureBaseUrl with
    | some value => some value
    | none =>
        match trimNonEmpty? baseUrlFromEnv with
        | some value => some value
        | none =>
            match trimNonEmpty? options.azureResourceName with
            | some resourceName => some (buildDefaultBaseUrl resourceName)
            | none =>
                match trimNonEmpty? resourceFromEnv with
                | some resourceName => some (buildDefaultBaseUrl resourceName)
                | none => trimNonEmpty? (some config.baseUrl)
  match baseUrl? with
  | none =>
      throw (IO.userError
        "Azure OpenAI base URL is required. Set AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME, or pass azureBaseUrl, azureResourceName, or model.baseUrl.")
  | some baseUrl =>
      match normalizeAzureBaseUrl baseUrl with
      | .ok normalized => pure { baseUrl := normalized, apiVersion := apiVersion }
      | .error err => throw (IO.userError err)

def jsonFieldsFor? (key : String) (value : Option Lean.Json) : List (String × Lean.Json) :=
  match value with
  | some value => [(key, value)]
  | none => []

def requestOptionFields (options : AzureOpenAIResponsesOptions) : List (String × Lean.Json) :=
  let maxTokenFields :=
    match options.maxTokens with
    | some maxTokens => [("max_output_tokens", LeanAgent.Json.nat maxTokens)]
    | none => []
  let temperatureFields :=
    match options.temperature with
    | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
    | none => []
  maxTokenFields ++ temperatureFields

def promptCacheFields (options : AzureOpenAIResponsesOptions) : List (String × Lean.Json) :=
  jsonFieldsFor? "prompt_cache_key"
    (LeanAgent.AI.Api.OpenAIPromptCache.clampKey options.sessionId |>.map LeanAgent.Json.str)

def requestToJsonWithOptions
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : AzureOpenAIResponsesOptions := {})
    (deploymentName : String := model.id)
    (stream : Bool := false) : Lean.Json :=
  let input := LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesMessages
    model context azureToolCallProviders { syntheticTimestamp := 0 }
  let toolFields :=
    if context.tools.isEmpty then
      []
    else
      [ ("tools",
          LeanAgent.Json.arr
            (LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesTools context.tools))
      ]
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str deploymentName)
     , ("input", LeanAgent.Json.arr input)
     , ("stream", LeanAgent.Json.bool stream)
     , ("store", LeanAgent.Json.bool false)
     ] ++ promptCacheFields options
       ++ requestOptionFields options
       ++ toolFields
       ++ LeanAgent.AI.Api.OpenAIResponses.reasoningFields model options.toOpenAIResponsesOptions)

def splitQuery (url : String) : String × Option String :=
  splitOnce url "?"

def responsesUrlNoQuery (baseUrl : String) : String :=
  if baseUrl.endsWith "/responses" then
    baseUrl
  else if baseUrl.endsWith "/" then
    baseUrl ++ "responses"
  else
    baseUrl ++ "/responses"

def azureResponsesUrl (baseUrl apiVersion : String) : String :=
  let (base, query?) := splitQuery baseUrl
  let path := responsesUrlNoQuery base
  match query? with
  | some query =>
      if query.isEmpty then
        path ++ "?api-version=" ++ apiVersion
      else
        path ++ "?" ++ query ++ "&api-version=" ++ apiVersion
  | none => path ++ "?api-version=" ++ apiVersion

def requestHeaders
    (config : AzureOpenAIResponsesConfig)
    (options : AzureOpenAIResponsesOptions) : Array (String × String) :=
  LeanAgent.AI.Util.Headers.merge
    (config.headers.push ("api-key", config.apiKey))
    (LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers)

def modelRef
    (resolved : AzureResolvedConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel) : LeanAgent.AI.ModelRef :=
  { id := model.id
    api := model.api
    provider := model.provider
    baseUrl := some resolved.baseUrl
  }

def runHttpJson
    (config : AzureOpenAIResponsesConfig)
    (resolved : AzureResolvedConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (payload : Lean.Json)
    (options : AzureOpenAIResponsesOptions := {}) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := azureResponsesUrl resolved.baseUrl resolved.apiVersion
      apiKey := ""
      headers := requestHeaders config options
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
    }
    payload.compress
  LeanAgent.AI.Api.OpenAIResponses.callResponseHook options.toOpenAIResponsesOptions (modelRef resolved model) response
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError (LeanAgent.AI.Util.Diagnostics.providerHttpErrorMessage response.status response.body))
  pure response.body

def completeWithOptions
    (config : AzureOpenAIResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : AzureOpenAIResponsesOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let resolved ← resolveAzureConfig config options
  let deploymentName ← resolveDeploymentName model options
  let ref := modelRef resolved model
  let payload ← LeanAgent.AI.Api.OpenAIResponses.applyPayloadHook
    options.toOpenAIResponsesOptions
    ref
    (requestToJsonWithOptions model context options deploymentName false)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config resolved model payload options)
    options.signal
  let timestamp ← IO.monoMsNow
  match LeanAgent.AI.Api.OpenAIResponses.parseResponse model.api model.provider model.id timestamp raw with
  | .ok response =>
      pure (LeanAgent.AI.Api.OpenAIResponses.applyMessageUsageCost
        model options.toOpenAIResponsesOptions response)
  | .error err => throw (IO.userError s!"failed to parse Azure OpenAI response: {err}\n{raw}")

def completeStreamWithOptions
    (config : AzureOpenAIResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : AzureOpenAIResponsesOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  let resolved ← resolveAzureConfig config options
  let deploymentName ← resolveDeploymentName model options
  let ref := modelRef resolved model
  let payload ← LeanAgent.AI.Api.OpenAIResponses.applyPayloadHook
    options.toOpenAIResponsesOptions
    ref
    (requestToJsonWithOptions model context options deploymentName true)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config resolved model payload options)
    options.signal
  let timestamp ← IO.monoMsNow
  match LeanAgent.AI.Api.OpenAIResponses.parseStreamingEventStream model.api model.provider model.id timestamp raw with
  | .ok stream =>
      pure (LeanAgent.AI.Api.OpenAIResponses.applyStreamUsageCost
        model options.toOpenAIResponsesOptions stream)
  | .error err => throw (IO.userError s!"failed to parse Azure OpenAI streaming response: {err}\n{raw}")

end LeanAgent.AI.Api.AzureOpenAIResponses
