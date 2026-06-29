import LeanAgent.AI.Auth
import LeanAgent.AI.OAuth
import LeanAgent.Json
import LeanAgent.Models

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

def toAuth (credential : LeanAgent.AI.Auth.OAuthCredential) : LeanAgent.AI.Auth.ModelAuth :=
  { apiKey := some credential.access
    baseUrl := some (getBaseUrl (some credential.access) (enterpriseDomain? credential))
  }

def modifyModels
    (models : Array LeanAgent.Models.ModelInfo)
    (credential : LeanAgent.AI.Auth.OAuthCredential) : Array LeanAgent.Models.ModelInfo :=
  let baseUrl := getBaseUrl (some credential.access) (enterpriseDomain? credential)
  let availableModelIds? := extraStringArray? credential "availableModelIds"
  models.filterMap fun model =>
    if model.provider != providerId then
      some model
    else
      match availableModelIds? with
      | some ids =>
          if ids.contains model.id then
            some { model with baseUrl := baseUrl }
          else
            none
      | none => some { model with baseUrl := baseUrl }

def oauthProvider : LeanAgent.AI.OAuth.OAuthProviderInterface :=
  { id := providerId
    name := name
    login := fun _callbacks =>
      throw (IO.userError
        ("GitHub Copilot device-code login is not yet implemented. " ++
        "Set GITHUB_COPILOT_TOKEN env var with a valid Copilot token."))
    usesCallbackServer := false
    refreshToken := fun _credential =>
      throw (IO.userError
        ("GitHub Copilot token refresh is not yet implemented. " ++
        "Manually update the stored credential or re-login when the token expires."))
    getApiKey := fun credential => credential.access
  }

def registerBuiltIn : IO Unit :=
  LeanAgent.AI.OAuth.registerBuiltInOAuthProvider oauthProvider
