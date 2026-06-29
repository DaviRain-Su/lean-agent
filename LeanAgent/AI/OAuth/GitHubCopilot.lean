import LeanAgent.AI.Auth
import LeanAgent.AI.OAuth.Core
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.OAuth.GitHubCopilot

def providerId : String := "github-copilot"
def name : String := "GitHub Copilot"
def defaultDomain : String := "github.com"
def defaultBaseUrl : String := "https://api.individual.githubcopilot.com"
def clientId : String := "Iv1.b507a08c87ecfe98"
def apiVersion : String := "2026-06-01"

def headers : Array (String × String) :=
  #[ ("User-Agent", "GitHubCopilotChat/0.35.0")
   , ("Editor-Version", "vscode/1.107.0")
   , ("Editor-Plugin-Version", "copilot-chat/0.35.0")
   , ("Copilot-Integration-Id", "vscode-chat")
   ]

structure Urls where
  deviceCodeUrl : String
  accessTokenUrl : String
  copilotTokenUrl : String
deriving BEq

private def splitOnce (value separator : String) : String × Option String :=
  match value.splitOn separator with
  | [] => (value, none)
  | first :: rest =>
      match rest with
      | [] => (first, none)
      | _ => (first, some (String.intercalate separator rest))

private def beforeDelimiter (value delimiter : String) : String :=
  match value.splitOn delimiter with
  | [] => value
  | first :: _ => first

private def beforeUrlDelimiters (value : String) : String :=
  beforeDelimiter (beforeDelimiter (beforeDelimiter value "/" ) "?") "#"

private def lastSegment (items : List String) : String :=
  match items.reverse with
  | last :: _ => last
  | [] => ""

private def hasWhitespace (value : String) : Bool :=
  value.toList.any fun char =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r'

private def stripUserInfo (authority : String) : String :=
  lastSegment (authority.splitOn "@")

private def stripPort (hostPort : String) : String :=
  if hostPort.startsWith "[" then
    match splitOnce hostPort "]" with
    | (host, some _) => host ++ "]"
    | _ => hostPort
  else
    beforeDelimiter hostPort ":"

def normalizeDomain (input : String) : Option String :=
  let trimmed := input.trimAscii.toString
  if trimmed.isEmpty || hasWhitespace trimmed then
    none
  else
    let rest :=
      match splitOnce trimmed "://" with
      | (_, some afterScheme) => afterScheme
      | _ => trimmed
    let authority := beforeUrlDelimiters rest
    let host := stripPort (stripUserInfo authority) |>.trimAscii.toString |>.toLower
    if host.isEmpty || hasWhitespace host || host.contains "/" || host.contains "\\" then
      none
    else
      some host

def urlsForDomain (domain : String) : Urls :=
  { deviceCodeUrl := s!"https://{domain}/login/device/code"
    accessTokenUrl := s!"https://{domain}/login/oauth/access_token"
    copilotTokenUrl := s!"https://api.{domain}/copilot_internal/v2/token"
  }

def proxyEndpointFromToken? (token : String) : Option String :=
  match splitOnce token "proxy-ep=" with
  | (_, some rest) =>
      let endpoint := beforeDelimiter rest ";" |>.trimAscii.toString
      if endpoint.isEmpty then none else some endpoint
  | _ => none

def baseUrlFromToken? (token : String) : Option String :=
  proxyEndpointFromToken? token |>.map fun proxyHost =>
    let apiHost :=
      if proxyHost.startsWith "proxy." then
        "api." ++ (proxyHost.drop "proxy.".length).toString
      else
        proxyHost
    s!"https://{apiHost}"

def getBaseUrl (token : Option String := none) (enterpriseDomain : Option String := none) : String :=
  match token.bind baseUrlFromToken? with
  | some baseUrl => baseUrl
  | none =>
      match enterpriseDomain with
      | some domain => s!"https://copilot-api.{domain}"
      | none => defaultBaseUrl

private def jsonField? (json : Lean.Json) (name : String) : Option Lean.Json :=
  match json.getObjVal? name with
  | .ok value => some value
  | .error _ => none

private def jsonStringField? (json : Lean.Json) (name : String) : Option String :=
  match jsonField? json name with
  | some value => value.getStr?.toOption
  | none => none

private def jsonBoolField? (json : Lean.Json) (name : String) : Option Bool :=
  match jsonField? json name with
  | some value => value.getBool?.toOption
  | none => none

private def jsonNestedField? (json : Lean.Json) (path : List String) : Option Lean.Json :=
  match path with
  | [] => some json
  | key :: rest =>
      match jsonField? json key with
      | some value => jsonNestedField? value rest
      | none => none

def isSelectableCopilotModel (item : Lean.Json) : Bool :=
  let pickerEnabled := jsonBoolField? item "model_picker_enabled" == some true
  let policyDisabled :=
    match jsonNestedField? item ["policy"] with
    | some policy => jsonStringField? policy "state" == some "disabled"
    | none => false
  let toolCallsDisabled :=
    match jsonNestedField? item ["capabilities", "supports"] with
    | some supports => jsonBoolField? supports "tool_calls" == some false
    | none => false
  pickerEnabled && !policyDisabled && !toolCallsDisabled

def parseAvailableModelIds (raw : Lean.Json) : Except String (Array String) := do
  let data ←
    match jsonField? raw "data" with
    | some data => data.getArr?
    | none => throw "Invalid Copilot models response"
  let mut ids := #[]
  for item in data do
    match jsonStringField? item "id" with
    | some id =>
        if isSelectableCopilotModel item then
          ids := ids.push id
    | none => pure ()
  pure ids

def extraString? (credential : LeanAgent.AI.Auth.OAuthCredential) (name : String) : Option String :=
  credential.extra.findSome? fun (field, value) =>
    if field == name then value.getStr?.toOption else none

private partial def jsonStringArrayLoop
    (items : Array Lean.Json)
    (index : Nat)
    (out : Array String) : Option (Array String) :=
  match items[index]? with
  | none => some out
  | some item =>
      match item.getStr?.toOption with
      | some value => jsonStringArrayLoop items (index + 1) (out.push value)
      | none => none

def jsonStringArray? (json : Lean.Json) : Option (Array String) :=
  match json.getArr? with
  | .ok items => jsonStringArrayLoop items 0 #[]
  | .error _ => none

def extraStringArray? (credential : LeanAgent.AI.Auth.OAuthCredential) (name : String) :
    Option (Array String) :=
  credential.extra.findSome? fun (field, value) =>
    if field == name then jsonStringArray? value else none

def enterpriseDomain? (credential : LeanAgent.AI.Auth.OAuthCredential) : Option String :=
  match extraString? credential "enterpriseUrl" with
  | some url => normalizeDomain url
  | none => none

def extraHeaders : Array (String × String) :=
  headers.filter fun (headerName, _) => headerName.toLower != "user-agent"

def userAgent : String :=
  match headers.findSome? (fun (headerName, value) =>
      if headerName.toLower == "user-agent" then some value else none) with
  | some value => value
  | none => "GitHubCopilotChat/0.35.0"

def jsonNatField? (json : Lean.Json) (name : String) : Option Nat :=
  match jsonField? json name with
  | some value => value.getNat?.toOption
  | none => none

def encodeHexDigit (value : Nat) : Char :=
  if value < 10 then
    Char.ofNat ('0'.toNat + value)
  else
    Char.ofNat ('A'.toNat + (value - 10))

def percentEncodeByte (value : Nat) : String :=
  String.singleton '%' ++
    String.singleton (encodeHexDigit (value / 16)) ++
    String.singleton (encodeHexDigit (value % 16))

def isFormUnreserved (char : Char) : Bool :=
  char.isAlphanum || char == '-' || char == '.' || char == '_' || char == '~'

def urlEncodeFormComponent (value : String) : String :=
  String.intercalate ""
    (value.toList.map fun char =>
      if isFormUnreserved char then
        String.singleton char
      else if char == ' ' then
        "+"
      else
        percentEncodeByte char.toNat)

def formUrlEncodedBody (fields : Array (String × String)) : String :=
  String.intercalate "&"
    (fields.toList.map fun (name, value) =>
      urlEncodeFormComponent name ++ "=" ++ urlEncodeFormComponent value)

def hasControlOrSpace (value : String) : Bool :=
  value.toList.any fun char =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r' || char.toNat < 0x20 || char.toNat == 0x7f

def isUriAllowedChar (char : Char) : Bool :=
  char.isAlphanum ||
    char == '-' || char == '.' || char == '_' || char == '~' ||
    char == ':' || char == '/' || char == '?' || char == '#' ||
    char == '[' || char == ']' || char == '@' ||
    char == '!' || char == '$' || char == '&' || char == '\'' ||
    char == '(' || char == ')' || char == '*' || char == '+' ||
    char == ',' || char == ';' || char == '=' || char == '%'

def normalizeUriTail (value : String) : String :=
  String.intercalate ""
    (value.toList.map fun char =>
      if isUriAllowedChar char then
        String.singleton char
      else
        percentEncodeByte char.toNat)

def normalizeVerificationUri (input : String) : Except String String := do
  let trimmed := input.trimAscii.toString
  let schemeRest ←
    if trimmed.startsWith "https://" then
      pure ("https://", trimmed.drop "https://".length |>.toString)
    else if trimmed.startsWith "http://" then
      pure ("http://", trimmed.drop "http://".length |>.toString)
    else
      throw "Untrusted verification_uri in device code response"
  let (scheme, rest) := schemeRest
  let authority := beforeUrlDelimiters rest
  if authority.isEmpty || hasControlOrSpace authority || authority.contains "\\" then
    throw "Untrusted verification_uri in device code response"
  pure (scheme ++ authority ++ normalizeUriTail (rest.drop authority.length |>.toString))

structure Runtime where
  urlsForDomain : String → Urls
  baseUrl : Option String → Option String → String
  request : LeanAgent.Http.RequestConfig → IO LeanAgent.Http.JsonPostResponse
  nowMs : IO Nat
  sleepMs : Nat → IO Unit
  knownModelIds : Array String := #[]

def defaultKnownModelIds : Array String :=
  #[ "claude-fable-5"
   , "claude-haiku-4.5"
   , "claude-opus-4.5"
   , "claude-opus-4.6"
   , "claude-opus-4.7"
   , "claude-opus-4.8"
   , "claude-sonnet-4"
   , "claude-sonnet-4.5"
   , "claude-sonnet-4.6"
   , "gemini-2.5-pro"
   , "gemini-3-flash-preview"
   , "gemini-3.1-pro-preview"
   , "gemini-3.5-flash"
   , "gpt-4.1"
   , "gpt-5-mini"
   , "gpt-5.2"
   , "gpt-5.2-codex"
   , "gpt-5.3-codex"
   , "gpt-5.4"
   , "gpt-5.4-mini"
   , "gpt-5.4-nano"
   , "gpt-5.5"
   ]

def defaultRuntime : Runtime :=
  { urlsForDomain := urlsForDomain
    baseUrl := fun token enterpriseDomain => getBaseUrl token enterpriseDomain
    request := LeanAgent.Http.requestResponse
    nowMs := LeanAgent.AI.Auth.epochMsNow
    sleepMs := fun ms => IO.sleep (UInt32.ofNat ms)
    knownModelIds := defaultKnownModelIds
  }

def requestJson (runtime : Runtime) (config : LeanAgent.Http.RequestConfig) : IO Lean.Json := do
  let response ← runtime.request config
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError s!"{response.status} HTTP request failed: {response.body}")
  match Lean.Json.parse response.body with
  | .ok json => pure json
  | .error err => throw (IO.userError s!"Invalid JSON response: {err}")

def jsonArrayToStrings? (items : Array Lean.Json) : Option (Array String) :=
  jsonStringArrayLoop items 0 #[]

def fetchAvailableModelIdsWith
    (runtime : Runtime)
    (accessToken : String)
    (enterpriseDomain : Option String := none) : IO (Array String) := do
  let baseUrl := runtime.baseUrl (some accessToken) enterpriseDomain
  let headers := (extraHeaders.push ("Accept", "application/json")).push ("X-GitHub-Api-Version", apiVersion)
  let json ← requestJson runtime
    { method := "GET"
      url := baseUrl ++ "/models"
      authorization := some s!"Bearer {accessToken}"
      timeoutSeconds := 5
      connectTimeoutSeconds := 5
      userAgent := userAgent
      headers := headers
    }
  match parseAvailableModelIds json with
  | .ok ids => pure ids
  | .error err => throw (IO.userError err)

def enableModelWith
    (runtime : Runtime)
    (accessToken modelId : String)
    (enterpriseDomain : Option String := none) : IO Bool := do
  let baseUrl := runtime.baseUrl (some accessToken) enterpriseDomain
  let headers := extraHeaders.push ("Content-Type", "application/json")
  let headers := headers.push ("openai-intent", "chat-policy")
  let headers := headers.push ("x-interaction-type", "chat-policy")
  let response ← runtime.request
    { method := "POST"
      url := s!"{baseUrl}/models/{modelId}/policy"
      authorization := some s!"Bearer {accessToken}"
      body := some "{\"state\":\"enabled\"}"
      timeoutSeconds := 5
      connectTimeoutSeconds := 5
      userAgent := userAgent
      headers := headers
    }
  pure (response.status >= 200 && response.status < 300)

def enableKnownModelsWith
    (runtime : Runtime)
    (accessToken : String)
    (enterpriseDomain : Option String := none)
    (onProgress : Option (String → IO Unit) := none) : IO Unit := do
  for modelId in runtime.knownModelIds do
    let success ← enableModelWith runtime accessToken modelId enterpriseDomain
    match onProgress with
    | some progress => progress s!"Enabled GitHub Copilot model {modelId}: {success}"
    | none => pure ()

def refreshAccessTokenWith
    (runtime : Runtime)
    (refreshToken : String)
    (enterpriseDomain : Option String := none) : IO LeanAgent.AI.Auth.OAuthCredential := do
  let domain := enterpriseDomain.getD defaultDomain
  let urls := runtime.urlsForDomain domain
  let json ← requestJson runtime
    { method := "GET"
      url := urls.copilotTokenUrl
      authorization := some s!"Bearer {refreshToken}"
      timeoutSeconds := 5
      connectTimeoutSeconds := 5
      userAgent := userAgent
      headers := extraHeaders.push ("Accept", "application/json")
    }
  let token ←
    match jsonStringField? json "token" with
    | some value => pure value
    | none => throw (IO.userError "Invalid Copilot token response fields")
  let expiresAt ←
    match jsonNatField? json "expires_at" with
    | some value => pure value
    | none => throw (IO.userError "Invalid Copilot token response fields")
  pure
    { access := token
      refresh := refreshToken
      expires := expiresAt * 1000 - 5 * 60 * 1000
      extra :=
        match enterpriseDomain with
        | some domain => #[("enterpriseUrl", LeanAgent.Json.str domain)]
        | none => #[]
    }

def refreshGitHubCopilotTokenWith
    (runtime : Runtime)
    (refreshToken : String)
    (enterpriseDomain : Option String := none) : IO LeanAgent.AI.Auth.OAuthCredential := do
  let credential ← refreshAccessTokenWith runtime refreshToken enterpriseDomain
  let availableModelIds ← fetchAvailableModelIdsWith runtime credential.access enterpriseDomain
  pure
    { credential with
      extra := credential.extra.push ("availableModelIds", LeanAgent.Json.arr (availableModelIds.map LeanAgent.Json.str))
    }

structure DeviceCodeResponse where
  deviceCode : String
  userCode : String
  verificationUri : String
  intervalSeconds : Option Nat := none
  expiresInSeconds : Nat

def startDeviceFlowWith (runtime : Runtime) (domain : String) : IO DeviceCodeResponse := do
  let urls := runtime.urlsForDomain domain
  let json ← requestJson runtime
    { method := "POST"
      url := urls.deviceCodeUrl
      body := some (formUrlEncodedBody #[("client_id", clientId), ("scope", "read:user")])
      timeoutSeconds := 5
      connectTimeoutSeconds := 5
      userAgent := userAgent
      headers :=
        #[ ("Accept", "application/json")
         , ("Content-Type", "application/x-www-form-urlencoded")
         ]
    }
  let deviceCode ←
    match jsonStringField? json "device_code" with
    | some value => pure value
    | none => throw (IO.userError "Invalid device code response")
  let userCode ←
    match jsonStringField? json "user_code" with
    | some value => pure value
    | none => throw (IO.userError "Invalid device code response")
  let verificationUriRaw ←
    match jsonStringField? json "verification_uri" with
    | some value => pure value
    | none => throw (IO.userError "Invalid device code response")
  let expiresInSeconds ←
    match jsonNatField? json "expires_in" with
    | some value => pure value
    | none => throw (IO.userError "Invalid device code response")
  let verificationUri ←
    match normalizeVerificationUri verificationUriRaw with
    | .ok uri => pure uri
    | .error err => throw (IO.userError err)
  pure
    { deviceCode := deviceCode
      userCode := userCode
      verificationUri := verificationUri
      intervalSeconds := jsonNatField? json "interval"
      expiresInSeconds := expiresInSeconds
    }

def pollForAccessTokenWith
    (runtime : Runtime)
    (domain : String)
    (device : DeviceCodeResponse)
    (signal : Option LeanAgent.AI.Util.Abort.AbortSignal := none) : IO String := do
  let urls := runtime.urlsForDomain domain
  LeanAgent.AI.OAuth.pollOAuthDeviceCodeFlow
    { intervalSeconds := device.intervalSeconds
      expiresInSeconds := some device.expiresInSeconds
      nowMs := runtime.nowMs
      sleepMs := runtime.sleepMs
      signal := signal
      poll := do
        let json ← requestJson runtime
          { method := "POST"
            url := urls.accessTokenUrl
            body := some
              (formUrlEncodedBody
                #[ ("client_id", clientId)
                 , ("device_code", device.deviceCode)
                 , ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
                 ])
            timeoutSeconds := 5
            connectTimeoutSeconds := 5
            userAgent := userAgent
            headers :=
              #[ ("Accept", "application/json")
               , ("Content-Type", "application/x-www-form-urlencoded")
               ]
          }
        match jsonStringField? json "access_token" with
        | some token => pure (.complete token)
        | none =>
            match jsonStringField? json "error" with
            | some "authorization_pending" => pure .pending
            | some "slow_down" => pure .slowDown
            | some errorCode =>
                let descriptionSuffix :=
                  match jsonStringField? json "error_description" with
                  | some description => s!": {description}"
                  | none => ""
                pure (.failed s!"Device flow failed: {errorCode}{descriptionSuffix}")
            | none => pure (.failed "Invalid device token response")
    }

def loginGitHubCopilotWith
    (runtime : Runtime)
    (callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks) : IO LeanAgent.AI.Auth.OAuthCredential := do
  let input ← callbacks.onPrompt
    { message := "GitHub Enterprise URL/domain (blank for github.com)"
      placeholder := some "company.ghe.com"
      allowEmpty := true
      signal := callbacks.signal
    }
  let trimmed := input.trimAscii.toString
  let enterpriseDomain ←
    if trimmed.isEmpty then
      pure none
    else
      match normalizeDomain input with
      | some domain => pure (some domain)
      | none => throw (IO.userError "Invalid GitHub Enterprise URL/domain")
  let domain := enterpriseDomain.getD defaultDomain
  let device ← startDeviceFlowWith runtime domain
  callbacks.onDeviceCode
    { userCode := device.userCode
      verificationUri := device.verificationUri
      intervalSeconds := device.intervalSeconds
      expiresInSeconds := some device.expiresInSeconds
    }
  let githubAccessToken ← pollForAccessTokenWith runtime domain device callbacks.signal
  let credential ← refreshAccessTokenWith runtime githubAccessToken enterpriseDomain
  if !runtime.knownModelIds.isEmpty then
    match callbacks.onProgress with
    | some progress =>
        progress "Enabling models..."
        enableKnownModelsWith runtime credential.access enterpriseDomain callbacks.onProgress
    | none =>
        enableKnownModelsWith runtime credential.access enterpriseDomain none
  let availableModelIds ← fetchAvailableModelIdsWith runtime credential.access enterpriseDomain
  pure
    { credential with
      extra := credential.extra.push ("availableModelIds", LeanAgent.Json.arr (availableModelIds.map LeanAgent.Json.str))
    }

def loginGitHubCopilot
    (callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks) : IO LeanAgent.AI.Auth.OAuthCredential :=
  loginGitHubCopilotWith defaultRuntime callbacks

def refreshGitHubCopilotToken
    (refreshToken : String)
    (enterpriseDomain : Option String := none) : IO LeanAgent.AI.Auth.OAuthCredential :=
  refreshGitHubCopilotTokenWith defaultRuntime refreshToken enterpriseDomain

def modifyModelRefs
    (models : Array LeanAgent.AI.ModelRef)
    (credential : LeanAgent.AI.Auth.OAuthCredential) : Array LeanAgent.AI.ModelRef :=
  let baseUrl := getBaseUrl (some credential.access) (enterpriseDomain? credential)
  let availableModelIds? := extraStringArray? credential "availableModelIds"
  models.filterMap fun model =>
    if model.provider != providerId then
      some model
    else
      match availableModelIds? with
      | some ids =>
          if ids.contains model.id then
            some { model with baseUrl := some baseUrl }
          else
            none
      | none => some { model with baseUrl := some baseUrl }

def toAuth (credential : LeanAgent.AI.Auth.OAuthCredential) : LeanAgent.AI.Auth.ModelAuth :=
  { apiKey := some credential.access
    baseUrl := some (getBaseUrl (some credential.access) (enterpriseDomain? credential))
    allowedModelIds := extraStringArray? credential "availableModelIds"
  }

def oauthProviderWith (runtime : Runtime) : LeanAgent.AI.OAuth.OAuthProviderInterface :=
  { id := providerId
    name := name
    login := loginGitHubCopilotWith runtime
    usesCallbackServer := false
    refreshToken := fun credential =>
      refreshGitHubCopilotTokenWith runtime credential.refresh (enterpriseDomain? credential)
    getApiKey := fun credential => credential.access
    toAuth := toAuth
    modifyModels := some modifyModelRefs
  }

def oauthProvider : LeanAgent.AI.OAuth.OAuthProviderInterface :=
  oauthProviderWith defaultRuntime

def registerBuiltIn : IO Unit :=
  LeanAgent.AI.OAuth.registerBuiltInOAuthProvider oauthProvider

initialize registerBuiltInProvider : Unit ← registerBuiltIn
