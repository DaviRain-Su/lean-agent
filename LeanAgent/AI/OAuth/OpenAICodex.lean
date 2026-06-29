import LeanAgent.AI.Api.OpenAICodexResponses
import LeanAgent.AI.Auth
import LeanAgent.AI.OAuth.Core
import LeanAgent.AI.OAuth.LocalCallback
import LeanAgent.AI.OAuth.PKCE
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.OAuth.OpenAICodex

def providerId : String := "openai-codex"
def name : String := "OpenAI (ChatGPT Plus/Pro)"
def clientId : String := "app_EMoamEEZ73f0CkXaXp7hrann"
def authBaseUrl : String := "https://auth.openai.com"
def browserLoginMethod : String := "browser"
def deviceCodeLoginMethod : String := "device_code"
def scope : String := "openid profile email offline_access"
def deviceCodeTimeoutSeconds : Nat := 15 * 60

structure Urls where
  authorizeUrl : String
  tokenUrl : String
  redirectUri : String
  deviceUserCodeUrl : String
  deviceTokenUrl : String
  deviceVerificationUri : String
  deviceRedirectUri : String
deriving BEq

structure Runtime where
  urls : Urls
  request : LeanAgent.Http.RequestConfig → IO LeanAgent.Http.JsonPostResponse
  generatePKCE : IO LeanAgent.AI.OAuth.PKCE.PKCE
  generateState : IO String
  nowMs : IO Nat
  sleepMs : Nat → IO Unit
  originator : String := "pi"

def defaultUrls : Urls :=
  { authorizeUrl := authBaseUrl ++ "/oauth/authorize"
    tokenUrl := authBaseUrl ++ "/oauth/token"
    redirectUri := "http://localhost:1455/auth/callback"
    deviceUserCodeUrl := authBaseUrl ++ "/api/accounts/deviceauth/usercode"
    deviceTokenUrl := authBaseUrl ++ "/api/accounts/deviceauth/token"
    deviceVerificationUri := authBaseUrl ++ "/codex/device"
    deviceRedirectUri := authBaseUrl ++ "/deviceauth/callback"
  }

def defaultRuntime : Runtime :=
  { urls := defaultUrls
    request := LeanAgent.Http.requestResponse
    generatePKCE := LeanAgent.AI.OAuth.PKCE.generatePKCE
    generateState := LeanAgent.AI.OAuth.PKCE.randomVerifierRaw 16
    nowMs := LeanAgent.AI.Auth.epochMsNow
    sleepMs := fun ms => IO.sleep (UInt32.ofNat ms)
  }

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

private def jsonStringOrNatField? (json : Lean.Json) (name : String) : Option Nat :=
  match jsonField? json name with
  | some value =>
      match value.getNat?.toOption with
      | some number => some number
      | none =>
          match value.getStr?.toOption with
          | some raw => raw.trimAscii.toString.toNat?
          | none => none
  | none => none

private def parseJsonBody (body : String) : IO Lean.Json :=
  match Lean.Json.parse body with
  | .ok json => pure json
  | .error err => throw (IO.userError s!"Invalid JSON response: {err}")

private def bodySuffix (body : String) : String :=
  let trimmed := body.trimAscii.toString
  if trimmed.isEmpty then "" else s!": {body}"

private def hexValue? (char : Char) : Option Nat :=
  if '0' <= char && char <= '9' then
    some (char.toNat - '0'.toNat)
  else if 'a' <= char && char <= 'f' then
    some (10 + char.toNat - 'a'.toNat)
  else if 'A' <= char && char <= 'F' then
    some (10 + char.toNat - 'A'.toNat)
  else
    none

private partial def percentDecodeLoop : List Char → Except String (List Char)
  | '%' :: hi :: lo :: rest =>
      match hexValue? hi, hexValue? lo with
      | some hiValue, some loValue =>
          do
            let decoded := Char.ofNat (hiValue * 16 + loValue)
            pure (decoded :: (← percentDecodeLoop rest))
      | _, _ => throw "invalid percent-encoding"
  | '%' :: _ => throw "truncated percent-encoding"
  | '+' :: rest => do
      pure (' ' :: (← percentDecodeLoop rest))
  | char :: rest => do
      pure (char :: (← percentDecodeLoop rest))
  | [] => pure []

private def percentDecodeComponent (value : String) : String :=
  match percentDecodeLoop value.toList with
  | .ok chars => String.ofList chars
  | .error _ => value

private def parseQueryParams (query : String) : Array (String × String) :=
  query.splitOn "&" |>.foldl
    (fun params field =>
      if field.isEmpty then
        params
      else
        let (name, value?) := splitOnce field "="
        params.push (percentDecodeComponent name, percentDecodeComponent (value?.getD "")))
    #[]

private def queryParam? (query name : String) : Option String :=
  (parseQueryParams query).findSome? fun (field, value) =>
    if field == name then some value else none

structure AuthorizationInput where
  code : Option String := none
  state : Option String := none
deriving BEq

def parseAuthorizationInput (input : String) : AuthorizationInput :=
  let trimmed := input.trimAscii.toString
  if trimmed.isEmpty then
    {}
  else
    match splitOnce trimmed "?" with
    | (_, some rest) =>
        let query := beforeDelimiter rest "#"
        let parsed : AuthorizationInput :=
          { code := queryParam? query "code"
            state := queryParam? query "state"
          }
        if parsed.code.isSome || parsed.state.isSome then
          parsed
        else if trimmed.contains "#" then
          match splitOnce trimmed "#" with
          | (code, some state) =>
              { code := some (percentDecodeComponent code)
                state := some (percentDecodeComponent state)
              }
          | _ => { code := some trimmed }
        else
          { code := some trimmed }
      | _ =>
          if trimmed.contains "#" then
            match splitOnce trimmed "#" with
            | (code, some state) =>
                { code := some (percentDecodeComponent code)
                  state := some (percentDecodeComponent state)
                }
            | _ => { code := some trimmed }
          else if trimmed.contains "code=" then
            { code := queryParam? trimmed "code"
              state := queryParam? trimmed "state"
            }
          else
            { code := some trimmed }

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

private def validateAccessToken (token : String) : IO Unit :=
  match LeanAgent.AI.Api.OpenAICodexResponses.extractAccountId token with
  | .ok _ => pure ()
  | .error _ => throw (IO.userError "Failed to extract accountId from token")

def toAuth (credential : LeanAgent.AI.Auth.OAuthCredential) : LeanAgent.AI.Auth.ModelAuth :=
  { apiKey := some credential.access }

structure TokenResult where
  access : String
  refresh : String
  expiresInSeconds : Nat
deriving BEq

private def readTokenResult (response : LeanAgent.Http.JsonPostResponse) (operation : String) :
    IO TokenResult := do
  if response.status < 200 || response.status >= 300 then
    throw
      (IO.userError
        s!"OpenAI Codex token {operation} failed ({response.status}){bodySuffix response.body}")
  let json ← parseJsonBody response.body
  let access ←
    match jsonStringField? json "access_token" with
    | some value => pure value
    | none =>
        throw
          (IO.userError
            s!"OpenAI Codex token {operation} response missing fields: {json.compress}")
  let refresh ←
    match jsonStringField? json "refresh_token" with
    | some value => pure value
    | none =>
        throw
          (IO.userError
            s!"OpenAI Codex token {operation} response missing fields: {json.compress}")
  let expiresInSeconds ←
    match jsonNatField? json "expires_in" with
    | some value => pure value
    | none =>
        throw
          (IO.userError
            s!"OpenAI Codex token {operation} response missing fields: {json.compress}")
  validateAccessToken access
  pure { access, refresh, expiresInSeconds }

private def credentialFromTokenResult
    (runtime : Runtime)
    (token : TokenResult) : IO LeanAgent.AI.Auth.OAuthCredential := do
  let now ← runtime.nowMs
  pure
    { access := token.access
      refresh := token.refresh
      expires := now + token.expiresInSeconds * 1000
    }

def exchangeAuthorizationCodeWith
    (runtime : Runtime)
    (code verifier : String)
    (redirectUri : String := defaultUrls.redirectUri) :
    IO LeanAgent.AI.Auth.OAuthCredential := do
  let response ← runtime.request
    { method := "POST"
      url := runtime.urls.tokenUrl
      body := some
        (formUrlEncodedBody
          #[ ("grant_type", "authorization_code")
           , ("client_id", clientId)
           , ("code", code)
           , ("code_verifier", verifier)
           , ("redirect_uri", redirectUri)
           ])
      timeoutSeconds := 5
      connectTimeoutSeconds := 5
      headers :=
        #[ ("Content-Type", "application/x-www-form-urlencoded")
         , ("Accept", "application/json")
         ]
    }
  credentialFromTokenResult runtime (← readTokenResult response "exchange")

def refreshOpenAICodexTokenWith
    (runtime : Runtime)
    (refreshToken : String) : IO LeanAgent.AI.Auth.OAuthCredential := do
  let response ← runtime.request
    { method := "POST"
      url := runtime.urls.tokenUrl
      body := some
        (formUrlEncodedBody
          #[ ("grant_type", "refresh_token")
           , ("refresh_token", refreshToken)
           , ("client_id", clientId)
           ])
      timeoutSeconds := 5
      connectTimeoutSeconds := 5
      headers :=
        #[ ("Content-Type", "application/x-www-form-urlencoded")
         , ("Accept", "application/json")
         ]
    }
  credentialFromTokenResult runtime (← readTokenResult response "refresh")

def refreshOpenAICodexToken
    (refreshToken : String) : IO LeanAgent.AI.Auth.OAuthCredential :=
  refreshOpenAICodexTokenWith defaultRuntime refreshToken

structure DeviceAuthInfo where
  deviceAuthId : String
  userCode : String
  intervalSeconds : Nat
deriving BEq

structure DeviceAuthToken where
  authorizationCode : String
  codeVerifier : String
deriving BEq

def startOpenAICodexDeviceAuthWith (runtime : Runtime) : IO DeviceAuthInfo := do
  let response ← runtime.request
    { method := "POST"
      url := runtime.urls.deviceUserCodeUrl
      body := some ((LeanAgent.Json.obj [("client_id", LeanAgent.Json.str clientId)]).compress)
      timeoutSeconds := 5
      connectTimeoutSeconds := 5
      headers :=
        #[ ("Content-Type", "application/json")
         , ("Accept", "application/json")
         ]
    }
  if response.status == 404 then
    throw
      (IO.userError
        "OpenAI Codex device code login is not enabled for this server. Use browser login or verify the server URL.")
  if response.status < 200 || response.status >= 300 then
    throw
      (IO.userError
        s!"OpenAI Codex device code request failed with status {response.status}{bodySuffix response.body}")
  let json ← parseJsonBody response.body
  let deviceAuthId ←
    match jsonStringField? json "device_auth_id" with
    | some value => pure value
    | none => throw (IO.userError s!"Invalid OpenAI Codex device code response: {json.compress}")
  let userCode ←
    match jsonStringField? json "user_code" with
    | some value => pure value
    | none => throw (IO.userError s!"Invalid OpenAI Codex device code response: {json.compress}")
  let intervalSeconds ←
    match jsonStringOrNatField? json "interval" with
    | some value => pure value
    | none => throw (IO.userError s!"Invalid OpenAI Codex device code response: {json.compress}")
  pure { deviceAuthId, userCode, intervalSeconds }

private def deviceTokenErrorCode? (response : LeanAgent.Http.JsonPostResponse) : Option String :=
  match Lean.Json.parse response.body with
  | .ok json =>
      match jsonStringField? json "error" with
      | some errorCode => some errorCode
      | none =>
          match jsonField? json "error" with
          | some error =>
              jsonStringField? error "code"
          | none => none
  | .error _ => none

def pollOpenAICodexDeviceAuthWith
    (runtime : Runtime)
    (device : DeviceAuthInfo)
    (signal : Option LeanAgent.AI.Util.Abort.AbortSignal := none) : IO DeviceAuthToken :=
  LeanAgent.AI.OAuth.pollOAuthDeviceCodeFlow
    { intervalSeconds := some device.intervalSeconds
      expiresInSeconds := some deviceCodeTimeoutSeconds
      nowMs := runtime.nowMs
      sleepMs := runtime.sleepMs
      signal := signal
      poll := do
        let response ← runtime.request
          { method := "POST"
            url := runtime.urls.deviceTokenUrl
            body := some
              ((LeanAgent.Json.obj
                [ ("device_auth_id", LeanAgent.Json.str device.deviceAuthId)
                , ("user_code", LeanAgent.Json.str device.userCode)
                ]).compress)
            timeoutSeconds := 5
            connectTimeoutSeconds := 5
            headers :=
              #[ ("Content-Type", "application/json")
               , ("Accept", "application/json")
               ]
          }
        if response.status >= 200 && response.status < 300 then
          let json ← parseJsonBody response.body
          match jsonStringField? json "authorization_code", jsonStringField? json "code_verifier" with
          | some authorizationCode, some codeVerifier =>
              pure (.complete { authorizationCode, codeVerifier })
          | _, _ =>
              pure (.failed s!"Invalid OpenAI Codex device auth token response: {json.compress}")
        else if response.status == 403 || response.status == 404 then
          pure .pending
        else
          match deviceTokenErrorCode? response with
          | some "deviceauth_authorization_pending" => pure .pending
          | some "slow_down" => pure .slowDown
          | _ =>
              pure
                (.failed
                  s!"OpenAI Codex device auth failed with status {response.status}{bodySuffix response.body}")
    }

def loginOpenAICodexDeviceCodeWith
    (runtime : Runtime)
    (onDeviceCode : LeanAgent.AI.OAuth.OAuthDeviceCodeInfo → IO Unit)
    (signal : Option LeanAgent.AI.Util.Abort.AbortSignal := none) :
    IO LeanAgent.AI.Auth.OAuthCredential := do
  let device ← startOpenAICodexDeviceAuthWith runtime
  onDeviceCode
    { userCode := device.userCode
      verificationUri := runtime.urls.deviceVerificationUri
      intervalSeconds := some device.intervalSeconds
      expiresInSeconds := some deviceCodeTimeoutSeconds
    }
  let token ← pollOpenAICodexDeviceAuthWith runtime device signal
  exchangeAuthorizationCodeWith
    runtime
    token.authorizationCode
    token.codeVerifier
    runtime.urls.deviceRedirectUri

def loginOpenAICodexDeviceCode
    (onDeviceCode : LeanAgent.AI.OAuth.OAuthDeviceCodeInfo → IO Unit) :
    IO LeanAgent.AI.Auth.OAuthCredential :=
  loginOpenAICodexDeviceCodeWith defaultRuntime onDeviceCode

structure AuthorizationFlow where
  verifier : String
  state : String
  url : String
deriving BEq

def createAuthorizationFlowWith (runtime : Runtime) : IO AuthorizationFlow := do
  let pkce ← runtime.generatePKCE
  let state ← runtime.generateState
  let url := runtime.urls.authorizeUrl ++ "?" ++
    formUrlEncodedBody
      #[ ("response_type", "code")
       , ("client_id", clientId)
       , ("redirect_uri", runtime.urls.redirectUri)
       , ("scope", scope)
       , ("code_challenge", pkce.challenge)
       , ("code_challenge_method", "S256")
       , ("state", state)
       , ("id_token_add_organizations", "true")
       , ("codex_cli_simplified_flow", "true")
       , ("originator", runtime.originator)
       ]
  pure { verifier := pkce.verifier, state, url }

private def requireMatchingState (expected : String) (input : AuthorizationInput) : IO Unit :=
  match input.state with
  | some state =>
      if state == expected then
        pure ()
      else
        throw (IO.userError "State mismatch")
  | none => pure ()

private def manualAuthorizationCode?
    (expectedState : String)
    (rawInput : String) :
    IO (Option String) := do
  let parsed := parseAuthorizationInput rawInput
  requireMatchingState expectedState parsed
  pure parsed.code

def loginOpenAICodexBrowserWith
    (runtime : Runtime)
    (callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks) :
    IO LeanAgent.AI.Auth.OAuthCredential := do
  let flow ← createAuthorizationFlowWith runtime
  let callbackServer ←
    LeanAgent.AI.OAuth.LocalCallback.start
      { redirectUri := runtime.urls.redirectUri
        expectedState := some flow.state
        successMessage := "OpenAI authentication completed. You can close this window."
        callbackErrorMessage := "OpenAI authentication did not complete."
        listenErrorBehavior := .disable
      }
  callbacks.onAuth
    { url := flow.url
      instructions := some "A browser window should open. Complete login to finish."
    }
  let mut code? : Option String := none
  let mut redirectUriForExchange := runtime.urls.redirectUri
  let manualPromptAborted ← IO.mkRef false
  let manualPromptSignal :=
    LeanAgent.AI.Util.Abort.combineAbortSignals
      #[
        callbacks.signal,
        some
          { isAborted := manualPromptAborted.get
            message := LeanAgent.AI.OAuth.cancelMessage
          }
      ]
  try
    match callbacks.onManualCodeInput with
    | some manualInput =>
        let manualTask ← IO.asTask do
          try
            let value ← manualInput
              { message := "Complete login in your browser, or paste the authorization code / redirect URL here:"
                placeholder := some runtime.urls.redirectUri
                signal := manualPromptSignal.signal
              }
            callbackServer.cancelWait
            pure value
          catch err =>
            callbackServer.cancelWait
            throw err
        match ← callbackServer.waitForCode with
        | some result =>
            code? := some result.code
            redirectUriForExchange := callbackServer.redirectUri
        | none =>
            match ← IO.wait manualTask with
            | .ok value =>
                code? := ← manualAuthorizationCode? flow.state value
            | .error err => throw err
    | none =>
        match ← callbackServer.waitForCode with
        | some result =>
            code? := some result.code
            redirectUriForExchange := callbackServer.redirectUri
        | none => pure ()
    if code?.isNone then
      let prompted ← callbacks.onPrompt
        { message := "Paste the authorization code (or full redirect URL):"
          placeholder := some runtime.urls.redirectUri
          signal := callbacks.signal
        }
      code? := ← manualAuthorizationCode? flow.state prompted
    let code ←
      match code? with
      | some value => pure value
      | none => throw (IO.userError "Missing authorization code")
    match callbacks.onProgress with
    | some progress => progress "Exchanging authorization code for tokens..."
    | none => pure ()
    exchangeAuthorizationCodeWith runtime code flow.verifier redirectUriForExchange
  finally
    manualPromptAborted.set true
    manualPromptSignal.cleanup
    callbackServer.close

def loginOpenAICodexWith
    (runtime : Runtime)
    (callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks) :
    IO LeanAgent.AI.Auth.OAuthCredential := do
  let method? ← callbacks.onSelect
    { message := "Select OpenAI Codex login method:"
      options :=
        #[ { id := browserLoginMethod, label := "Browser login (default)" }
         , { id := deviceCodeLoginMethod, label := "Device code login (headless)" }
         ]
    }
  match method? with
  | none => throw (IO.userError LeanAgent.AI.OAuth.cancelMessage)
  | some method =>
      if method == deviceCodeLoginMethod then
        loginOpenAICodexDeviceCodeWith runtime callbacks.onDeviceCode callbacks.signal
      else if method == browserLoginMethod then
        loginOpenAICodexBrowserWith runtime callbacks
      else
        throw (IO.userError s!"Unknown OpenAI Codex login method: {method}")

def loginOpenAICodex
    (callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks) :
    IO LeanAgent.AI.Auth.OAuthCredential :=
  loginOpenAICodexWith defaultRuntime callbacks

def oauthProviderWith (runtime : Runtime) : LeanAgent.AI.OAuth.OAuthProviderInterface :=
  { id := providerId
    name := "ChatGPT Plus/Pro (Codex Subscription)"
    login := loginOpenAICodexWith runtime
    usesCallbackServer := true
    refreshToken := fun credential =>
      refreshOpenAICodexTokenWith runtime credential.refresh
    getApiKey := fun credential => credential.access
    toAuth := toAuth
  }

def oauthProvider : LeanAgent.AI.OAuth.OAuthProviderInterface :=
  oauthProviderWith defaultRuntime

def registerBuiltIn : IO Unit :=
  LeanAgent.AI.OAuth.registerBuiltInOAuthProvider oauthProvider

initialize registerBuiltInProvider : Unit ← registerBuiltIn

end LeanAgent.AI.OAuth.OpenAICodex
