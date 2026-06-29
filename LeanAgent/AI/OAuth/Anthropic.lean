import LeanAgent.AI.Auth
import LeanAgent.AI.OAuth.Core
import LeanAgent.AI.OAuth.LocalCallback
import LeanAgent.AI.OAuth.PKCE
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.OAuth.Anthropic

def providerId : String := "anthropic"
def name : String := "Anthropic (Claude Pro/Max)"
def clientId : String := "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
def authorizeUrl : String := "https://claude.ai/oauth/authorize"
def tokenUrl : String := "https://platform.claude.com/v1/oauth/token"
def redirectUri : String := "http://localhost:53692/callback"
def scopes : String :=
  "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

structure Runtime where
  authorizeUrl : String := authorizeUrl
  tokenUrl : String := tokenUrl
  redirectUri : String := redirectUri
  request : LeanAgent.Http.RequestConfig → IO LeanAgent.Http.JsonPostResponse
  generatePKCE : IO LeanAgent.AI.OAuth.PKCE.PKCE
  nowMs : IO Nat

def defaultRuntime : Runtime :=
  { request := LeanAgent.Http.requestResponse
    generatePKCE := LeanAgent.AI.OAuth.PKCE.generatePKCE
    nowMs := LeanAgent.AI.Auth.epochMsNow
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
      | some hiValue, some loValue => do
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

private def urlEncodeQueryComponent (value : String) : String :=
  String.intercalate ""
    (value.toList.map fun char =>
      if isFormUnreserved char then
        String.singleton char
      else
        percentEncodeByte char.toNat)

private def encodeQuery (fields : Array (String × String)) : String :=
  String.intercalate "&"
    (fields.toList.map fun (field, value) =>
      urlEncodeQueryComponent field ++ "=" ++ urlEncodeQueryComponent value)

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

private def requestJson
    (runtime : Runtime)
    (url : String)
    (payload : Lean.Json) :
    IO LeanAgent.Http.JsonPostResponse :=
  runtime.request
    { method := "POST"
      url := url
      body := some payload.compress
      timeoutSeconds := 30
      connectTimeoutSeconds := 30
      headers :=
        #[ ("Content-Type", "application/json")
         , ("Accept", "application/json")
         ]
    }

private def readTokenResponse
    (runtime : Runtime)
    (response : LeanAgent.Http.JsonPostResponse)
    (operation : String) :
    IO LeanAgent.AI.Auth.OAuthCredential := do
  if response.status < 200 || response.status >= 300 then
    throw
      (IO.userError
        s!"Anthropic token {operation} request failed. url={runtime.tokenUrl}; status={response.status}{bodySuffix response.body}")
  let json ← parseJsonBody response.body
  let access ←
    match jsonStringField? json "access_token" with
    | some value => pure value
    | none => throw (IO.userError s!"Anthropic token {operation} returned invalid JSON: {json.compress}")
  let refresh ←
    match jsonStringField? json "refresh_token" with
    | some value => pure value
    | none => throw (IO.userError s!"Anthropic token {operation} returned invalid JSON: {json.compress}")
  let expiresIn ←
    match jsonNatField? json "expires_in" with
    | some value => pure value
    | none => throw (IO.userError s!"Anthropic token {operation} returned invalid JSON: {json.compress}")
  let now ← runtime.nowMs
  pure
    { access := access
      refresh := refresh
      expires := now + expiresIn * 1000 - 5 * 60 * 1000
    }

def toAuth (credential : LeanAgent.AI.Auth.OAuthCredential) : LeanAgent.AI.Auth.ModelAuth :=
  { apiKey := some credential.access }

def exchangeAuthorizationCodeWith
    (runtime : Runtime)
    (code state verifier : String)
    (redirectUri : String := redirectUri) :
    IO LeanAgent.AI.Auth.OAuthCredential := do
  let response ← requestJson runtime runtime.tokenUrl
    (LeanAgent.Json.obj
      [ ("grant_type", LeanAgent.Json.str "authorization_code")
      , ("client_id", LeanAgent.Json.str clientId)
      , ("code", LeanAgent.Json.str code)
      , ("state", LeanAgent.Json.str state)
      , ("redirect_uri", LeanAgent.Json.str redirectUri)
      , ("code_verifier", LeanAgent.Json.str verifier)
      ])
  readTokenResponse runtime response "exchange"

def refreshAnthropicTokenWith
    (runtime : Runtime)
    (refreshToken : String) :
    IO LeanAgent.AI.Auth.OAuthCredential := do
  let response ← requestJson runtime runtime.tokenUrl
    (LeanAgent.Json.obj
      [ ("grant_type", LeanAgent.Json.str "refresh_token")
      , ("client_id", LeanAgent.Json.str clientId)
      , ("refresh_token", LeanAgent.Json.str refreshToken)
      ])
  readTokenResponse runtime response "refresh"

def refreshAnthropicToken
    (refreshToken : String) : IO LeanAgent.AI.Auth.OAuthCredential :=
  refreshAnthropicTokenWith defaultRuntime refreshToken

private def manualAuthorizationInput?
    (expectedState : String)
    (rawInput : String) : IO (Option (String × String)) := do
  let parsed := parseAuthorizationInput rawInput
  match parsed.state with
  | some parsedState =>
      if parsedState != expectedState then
        throw (IO.userError "OAuth state mismatch")
      else
        pure ()
  | none => pure ()
  match parsed.code with
  | some code => pure (some (code, parsed.state.getD expectedState))
  | none => pure none

def loginAnthropicWith
    (runtime : Runtime)
    (callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks) :
    IO LeanAgent.AI.Auth.OAuthCredential := do
  let pkce ← runtime.generatePKCE
  let state := pkce.verifier
  let callbackServer ←
    LeanAgent.AI.OAuth.LocalCallback.start
      { redirectUri := runtime.redirectUri
        expectedState := some state
        successMessage := "Anthropic authentication completed. You can close this window."
        callbackErrorMessage := "Anthropic authentication did not complete."
        missingCodeOrStateMessage := some "Missing code or state parameter."
      }
  let authUrl := runtime.authorizeUrl ++ "?" ++
    encodeQuery
      #[ ("code", "true")
       , ("client_id", clientId)
       , ("response_type", "code")
       , ("redirect_uri", runtime.redirectUri)
       , ("scope", scopes)
       , ("code_challenge", pkce.challenge)
       , ("code_challenge_method", "S256")
       , ("state", state)
       ]
  callbacks.onAuth
    { url := authUrl
      instructions :=
        some "Complete login in your browser. If the browser is on another machine, paste the final redirect URL here."
    }
  let mut code? : Option String := none
  let mut resolvedState? : Option String := none
  let mut redirectUriForExchange := runtime.redirectUri
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
                placeholder := some runtime.redirectUri
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
            resolvedState? := result.state
            redirectUriForExchange := callbackServer.redirectUri
        | none =>
            match ← IO.wait manualTask with
            | .ok value =>
                match ← manualAuthorizationInput? state value with
                | some (code, resolvedState) =>
                    code? := some code
                    resolvedState? := some resolvedState
                | none => pure ()
            | .error err => throw err
    | none =>
        match ← callbackServer.waitForCode with
        | some result =>
            code? := some result.code
            resolvedState? := result.state
            redirectUriForExchange := callbackServer.redirectUri
        | none => pure ()
    if code?.isNone then
      let prompted ← callbacks.onPrompt
        { message := "Paste the authorization code or full redirect URL:"
          placeholder := some runtime.redirectUri
          signal := callbacks.signal
        }
      match ← manualAuthorizationInput? state prompted with
      | some (code, resolvedState) =>
          code? := some code
          resolvedState? := some resolvedState
      | none => pure ()
    let code ←
      match code? with
      | some code => pure code
      | none => throw (IO.userError "Missing authorization code")
    let resolvedState := resolvedState?.getD state
    match callbacks.onProgress with
    | some progress => progress "Exchanging authorization code for tokens..."
    | none => pure ()
    exchangeAuthorizationCodeWith runtime code resolvedState pkce.verifier redirectUriForExchange
  finally
    manualPromptAborted.set true
    manualPromptSignal.cleanup
    callbackServer.close

def loginAnthropic
    (callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks) :
    IO LeanAgent.AI.Auth.OAuthCredential :=
  loginAnthropicWith defaultRuntime callbacks

def oauthProviderWith (runtime : Runtime) : LeanAgent.AI.OAuth.OAuthProviderInterface :=
  { id := providerId
    name := name
    login := loginAnthropicWith runtime
    usesCallbackServer := true
    refreshToken := fun credential =>
      refreshAnthropicTokenWith runtime credential.refresh
    getApiKey := fun credential => credential.access
    toAuth := toAuth
  }

def oauthProvider : LeanAgent.AI.OAuth.OAuthProviderInterface :=
  oauthProviderWith defaultRuntime

def registerBuiltIn : IO Unit :=
  LeanAgent.AI.OAuth.registerBuiltInOAuthProvider oauthProvider

initialize registerBuiltInProvider : Unit ← registerBuiltIn

end LeanAgent.AI.OAuth.Anthropic
