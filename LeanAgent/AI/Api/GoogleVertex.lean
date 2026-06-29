import LeanAgent.AI.Api.GoogleGenerativeAI
import LeanAgent.AI.Auth
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.Retry
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.GoogleVertex

open LeanAgent

def api : String := LeanAgent.AI.Api.GoogleShared.apiVertex
def apiVersion : String := "v1"
def vertexCredentialsMarker : String := "gcp-vertex-credentials"

structure GoogleVertexConfig where
  apiKey : String := ""
  baseUrl : String := "https://{location}-aiplatform.googleapis.com"
  headers : Array (String × String) := #[]
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

inductive ToolChoice where
  | auto
  | none
  | any
deriving BEq

structure GoogleVertexOptions extends LeanAgent.AI.SimpleStreamOptions where
  toolChoice : Option ToolChoice := none
  thinkingEnabled : Option Bool := none
  thinkingBudgetTokens : Option Nat := none
  thinkingLevel : Option String := none
  project : Option String := none
  location : Option String := none

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : GoogleVertexOptions :=
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
  }

def toGoogleOptions (options : GoogleVertexOptions) :
    LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIOptions :=
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
    toolChoice :=
      match options.toolChoice with
      | some .auto => some .auto
      | some .none => some .none
      | some .any => some .any
      | none => none
    thinkingEnabled := options.thinkingEnabled
    thinkingBudgetTokens := options.thinkingBudgetTokens
    thinkingLevel := options.thinkingLevel
  }

def trimTrailingSlash (value : String) : String :=
  if value.endsWith "/" then value.dropEnd 1 |>.toString else value

def replaceLocationPlaceholder (baseUrl location : String) : String :=
  String.intercalate location (baseUrl.splitOn "{location}")

def baseUrlIncludesApiVersion (baseUrl : String) : Bool :=
  let lowered := baseUrl.toLower
  lowered.endsWith ("/" ++ apiVersion) ||
    lowered.contains ("/" ++ apiVersion ++ "/") ||
    lowered.endsWith "/v1beta" ||
    lowered.contains "/v1beta/"

def vertexCollectionBaseUrl (baseUrl project location : String) : String :=
  let base := trimTrailingSlash (replaceLocationPlaceholder baseUrl location)
  if baseUrlIncludesApiVersion base then
    base
  else
    base ++ "/" ++ apiVersion ++ "/projects/" ++ project ++ "/locations/" ++ location

def generateContentUrl (baseUrl project location modelId : String) : String :=
  vertexCollectionBaseUrl baseUrl project location ++
    "/publishers/google/models/" ++ modelId ++ ":generateContent"

def streamGenerateContentUrl (baseUrl project location modelId : String) : String :=
  vertexCollectionBaseUrl baseUrl project location ++
    "/publishers/google/models/" ++ modelId ++ ":streamGenerateContent?alt=sse"

def modelRef (config : GoogleVertexConfig) (model : LeanAgent.AI.ModelRef) :
    LeanAgent.AI.ModelRef :=
  { model with baseUrl := some config.baseUrl }

def isPlaceholderApiKey (apiKey : String) : Bool :=
  apiKey.startsWith "<" && apiKey.endsWith ">"

def resolvedApiKey? (apiKey : String) : Option String :=
  let trimmed := apiKey.trimAscii.toString
  if trimmed.isEmpty || trimmed == vertexCredentialsMarker || isPlaceholderApiKey trimmed then
    none
  else
    some trimmed

def envValue? (env : LeanAgent.AI.Auth.ProviderEnv) (name : String) : IO (Option String) := do
  match LeanAgent.AI.Auth.providerEnvGet? env name with
  | some value => pure (some value)
  | none =>
      match ← IO.getEnv name with
      | some value =>
          let trimmed := value.trimAscii.toString
          pure (if trimmed.isEmpty then none else some trimmed)
      | none => pure none

def resolveProject (options : GoogleVertexOptions) : IO String := do
  match options.project with
  | some project =>
      if project.trimAscii.toString.isEmpty then
        throw (IO.userError "Vertex AI requires a project ID. Set GOOGLE_CLOUD_PROJECT/GCLOUD_PROJECT or pass project in options.")
      else
        pure project
  | none =>
      match ← envValue? options.env "GOOGLE_CLOUD_PROJECT" with
      | some project => pure project
      | none =>
          match ← envValue? options.env "GCLOUD_PROJECT" with
          | some project => pure project
          | none =>
              throw (IO.userError "Vertex AI requires a project ID. Set GOOGLE_CLOUD_PROJECT/GCLOUD_PROJECT or pass project in options.")

def resolveLocation (options : GoogleVertexOptions) : IO String := do
  match options.location with
  | some location =>
      if location.trimAscii.toString.isEmpty then
        throw (IO.userError "Vertex AI requires a location. Set GOOGLE_CLOUD_LOCATION or pass location in options.")
      else
        pure location
  | none =>
      match ← envValue? options.env "GOOGLE_CLOUD_LOCATION" with
      | some location => pure location
      | none =>
          throw (IO.userError "Vertex AI requires a location. Set GOOGLE_CLOUD_LOCATION or pass location in options.")

def applyPayloadHook
    (options : GoogleVertexOptions)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json) : IO Lean.Json := do
  LeanAgent.AI.Api.GoogleGenerativeAI.applyPayloadHook (toGoogleOptions options) model payload

def callResponseHook
    (options : GoogleVertexOptions)
    (model : LeanAgent.AI.ModelRef)
    (response : LeanAgent.Http.JsonPostResponse) : IO Unit := do
  match options.onResponse with
  | none => pure ()
  | some hook => hook { status := response.status, headers := response.headers } model

def requestToJsonWithOptions
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : GoogleVertexOptions := {}) : Lean.Json :=
  LeanAgent.AI.Api.GoogleGenerativeAI.requestToJsonWithOptions
    model
    input
    reasoning
    context
    (toGoogleOptions options)

def requestHeaders
    (config : GoogleVertexConfig)
    (options : GoogleVertexOptions) : Array (String × String) :=
  let authHeaders :=
    match resolvedApiKey? config.apiKey with
    | some apiKey => #[("x-goog-api-key", apiKey)]
    | none => #[]
  LeanAgent.AI.Util.Headers.merge
    (config.headers ++ (authHeaders ++ #[("accept", "application/json")]))
    (LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers)

def runHttpJson
    (config : GoogleVertexConfig)
    (model : LeanAgent.AI.ModelRef)
    (url : String)
    (payload : Lean.Json)
    (options : GoogleVertexOptions := {}) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := url
      apiKey := ""
      headers := requestHeaders config options
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
    }
    payload.compress
  callResponseHook options (modelRef config model) response
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError (LeanAgent.AI.Util.Diagnostics.providerHttpErrorMessage response.status response.body))
  pure response.body

def completeWithOptions
    (config : GoogleVertexConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : GoogleVertexOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let ref := modelRef config model
  let payload ← applyPayloadHook options ref
    (requestToJsonWithOptions ref input reasoning context options)
  let project ← resolveProject options
  let location ← resolveLocation options
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config ref (generateContentUrl config.baseUrl project location model.id) payload options)
  let timestamp ← IO.monoMsNow
  match LeanAgent.AI.Api.GoogleGenerativeAI.parseResponse model.api model.provider model.id timestamp raw with
  | .ok message => pure message
  | .error err => throw (IO.userError s!"failed to parse Google Vertex response: {err}\n{raw}")

def completeStreamWithOptions
    (config : GoogleVertexConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : GoogleVertexOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  let ref := modelRef config model
  let payload ← applyPayloadHook options ref
    (requestToJsonWithOptions ref input reasoning context options)
  let project ← resolveProject options
  let location ← resolveLocation options
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config ref (streamGenerateContentUrl config.baseUrl project location model.id) payload options)
  let timestamp ← IO.monoMsNow
  match LeanAgent.AI.Api.GoogleGenerativeAI.parseStreamingEventStream model.api model.provider model.id timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse Google Vertex stream: {err}\n{raw}")

end LeanAgent.AI.Api.GoogleVertex
