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
def defaultAdcPath : String := "~/.config/gcloud/application_default_credentials.json"
def cloudPlatformScope : String := "https://www.googleapis.com/auth/cloud-platform"

@[extern "lean_agent_sign_jwt_rs256"]
opaque signJwtRs256
  (privateKeyPem headerJson payloadJson : @& String)
  : IO String

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

private def jsonField? (json : Lean.Json) (name : String) : Option Lean.Json :=
  match json.getObjVal? name with
  | .ok value => some value
  | .error _ => none

private def jsonStringField? (json : Lean.Json) (name : String) : Option String :=
  match jsonField? json name with
  | some value => value.getStr?.toOption
  | none => none

private def jsonNatField? (json : Lean.Json) (name : String) : Option Nat :=
  match jsonField? json name with
  | some value => value.getNat?.toOption
  | none => none

private def parseJsonBody (body : String) : IO Lean.Json :=
  match Lean.Json.parse body with
  | .ok json => pure json
  | .error err => throw (IO.userError s!"Invalid JSON response: {err}")

private def bodySuffix (body : String) : String :=
  let trimmed := body.trimAscii.toString
  if trimmed.isEmpty then "" else s!"; body={body}"

private def encodeHexDigit (value : Nat) : Char :=
  if value < 10 then
    Char.ofNat ('0'.toNat + value)
  else
    Char.ofNat ('A'.toNat + (value - 10))

private def percentEncodeByte (value : Nat) : String :=
  String.singleton '%' ++
    String.singleton (encodeHexDigit (value / 16)) ++
    String.singleton (encodeHexDigit (value % 16))

private def isFormUnreserved (char : Char) : Bool :=
  char.isAlphanum || char == '-' || char == '.' || char == '_' || char == '~'

private def urlEncodeFormComponent (value : String) : String :=
  String.intercalate ""
    (value.toList.map fun char =>
      if isFormUnreserved char then
        String.singleton char
      else if char == ' ' then
        "+"
      else
        percentEncodeByte char.toNat)

private def formUrlEncodedBody (fields : Array (String × String)) : String :=
  String.intercalate "&"
    (fields.toList.map fun (field, value) =>
      urlEncodeFormComponent field ++ "=" ++ urlEncodeFormComponent value)

private structure ServiceAccountCredential where
  clientEmail : String
  privateKey : String
  tokenUri : String

private structure AuthorizedUserCredential where
  clientId : String
  clientSecret : String
  refreshToken : String
  tokenUri : String

private inductive AdcCredential where
  | serviceAccount (credential : ServiceAccountCredential)
  | authorizedUser (credential : AuthorizedUserCredential)

private def defaultGoogleTokenUri : String := "https://oauth2.googleapis.com/token"

private def resolveAdcCredentialsPath (options : GoogleVertexOptions) : IO System.FilePath := do
  let path ←
    match ← envValue? options.env "GOOGLE_APPLICATION_CREDENTIALS" with
    | some path => pure path
    | none => pure defaultAdcPath
  LeanAgent.AI.Auth.expandHomePath path

private def parseAdcCredential (json : Lean.Json) : Except String AdcCredential := do
  let credentialType ← LeanAgent.Json.requiredString json "type"
  match credentialType with
  | "service_account" =>
      let clientEmail ← LeanAgent.Json.requiredString json "client_email"
      let privateKey ← LeanAgent.Json.requiredString json "private_key"
      let tokenUri := (jsonStringField? json "token_uri").getD defaultGoogleTokenUri
      pure (.serviceAccount { clientEmail, privateKey, tokenUri })
  | "authorized_user" =>
      let clientId ← LeanAgent.Json.requiredString json "client_id"
      let clientSecret ← LeanAgent.Json.requiredString json "client_secret"
      let refreshToken ← LeanAgent.Json.requiredString json "refresh_token"
      let tokenUri := (jsonStringField? json "token_uri").getD defaultGoogleTokenUri
      pure (.authorizedUser { clientId, clientSecret, refreshToken, tokenUri })
  | other =>
      throw s!"unsupported Google ADC credential type: {other}"

private def loadAdcCredential (options : GoogleVertexOptions) : IO AdcCredential := do
  let path ← resolveAdcCredentialsPath options
  let raw ←
    try
      IO.FS.readFile path
    catch err =>
      throw (IO.userError s!"Failed to read Google ADC credentials from {path}: {err.toString}")
  let json ← parseJsonBody raw
  match parseAdcCredential json with
  | .ok credential => pure credential
  | .error err => throw (IO.userError s!"Invalid Google ADC credentials in {path}: {err}")

private def tokenRequest
    (config : GoogleVertexConfig)
    (url : String)
    (body : String) :
    IO LeanAgent.Http.JsonPostResponse :=
  LeanAgent.Http.requestResponse
    { method := "POST"
      url := url
      body := some body
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
      headers :=
        #[ ("Content-Type", "application/x-www-form-urlencoded")
         , ("Accept", "application/json")
         ]
    }

private def readAccessToken
    (response : LeanAgent.Http.JsonPostResponse)
    (source : String) :
    IO String := do
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError s!"Google ADC token request failed for {source} ({response.status}){bodySuffix response.body}")
  let json ← parseJsonBody response.body
  match jsonStringField? json "access_token" with
  | some token =>
      if token.trimAscii.toString.isEmpty then
        throw (IO.userError s!"Google ADC token response for {source} was empty")
      else
        pure token
  | none =>
      throw (IO.userError s!"Google ADC token response for {source} missing access_token: {json.compress}")

private def serviceAccountAssertion
    (credential : ServiceAccountCredential)
    (nowMs : Nat) :
    IO String := do
  let nowSeconds := nowMs / 1000
  let header :=
    LeanAgent.Json.obj
      [ ("alg", LeanAgent.Json.str "RS256")
      , ("typ", LeanAgent.Json.str "JWT")
      ]
  let claims :=
    LeanAgent.Json.obj
      [ ("iss", LeanAgent.Json.str credential.clientEmail)
      , ("sub", LeanAgent.Json.str credential.clientEmail)
      , ("scope", LeanAgent.Json.str cloudPlatformScope)
      , ("aud", LeanAgent.Json.str credential.tokenUri)
      , ("iat", LeanAgent.Json.nat nowSeconds)
      , ("exp", LeanAgent.Json.nat (nowSeconds + 3600))
      ]
  signJwtRs256 credential.privateKey header.compress claims.compress

private def fetchServiceAccountAccessToken
    (config : GoogleVertexConfig)
    (_options : GoogleVertexOptions)
    (credential : ServiceAccountCredential) :
    IO String := do
  let nowMs ← LeanAgent.AI.Auth.epochMsNow
  let assertion ← serviceAccountAssertion credential nowMs
  let response ← tokenRequest config credential.tokenUri
    (formUrlEncodedBody
      #[ ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
       , ("assertion", assertion)
       ])
  readAccessToken response "service_account"

private def fetchAuthorizedUserAccessToken
    (config : GoogleVertexConfig)
    (credential : AuthorizedUserCredential) :
    IO String := do
  let response ← tokenRequest config credential.tokenUri
    (formUrlEncodedBody
      #[ ("grant_type", "refresh_token")
       , ("refresh_token", credential.refreshToken)
       , ("client_id", credential.clientId)
       , ("client_secret", credential.clientSecret)
       ])
  readAccessToken response "authorized_user"

private def fetchAdcAccessToken
    (config : GoogleVertexConfig)
    (options : GoogleVertexOptions) :
    IO String := do
  match ← loadAdcCredential options with
  | .serviceAccount credential => fetchServiceAccountAccessToken config options credential
  | .authorizedUser credential => fetchAuthorizedUserAccessToken config credential

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

def resolvedRequestHeaders
    (config : GoogleVertexConfig)
    (options : GoogleVertexOptions) : IO (Array (String × String)) := do
  let headers := requestHeaders config options
  if LeanAgent.Http.hasHeaderNameCI headers "authorization" ||
      LeanAgent.Http.hasHeaderNameCI headers "x-goog-api-key" then
    pure headers
  else if config.apiKey.trimAscii.toString == vertexCredentialsMarker then
    let token ← fetchAdcAccessToken config options
    pure (headers.push ("Authorization", "Bearer " ++ token))
  else
    pure headers

def runHttpJson
    (config : GoogleVertexConfig)
    (model : LeanAgent.AI.ModelRef)
    (url : String)
    (payload : Lean.Json)
    (options : GoogleVertexOptions := {}) : IO String := do
  let headers ← resolvedRequestHeaders config options
  let response ← LeanAgent.Http.postJsonResponse
    { url := url
      apiKey := ""
      headers := headers
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
    options.signal
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
    options.signal
  let timestamp ← IO.monoMsNow
  match LeanAgent.AI.Api.GoogleGenerativeAI.parseStreamingEventStream model.api model.provider model.id timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse Google Vertex stream: {err}\n{raw}")

end LeanAgent.AI.Api.GoogleVertex
