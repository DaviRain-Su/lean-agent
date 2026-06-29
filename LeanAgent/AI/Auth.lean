import Lean
import LeanAgent.AI.Types
import LeanAgent.Json
import Std.Time

namespace LeanAgent.AI.Auth

abbrev ProviderEnv := Array (String × String)
abbrev ProviderHeaders := Array (String × String)

structure ModelAuth where
  apiKey : Option String := none
  headers : ProviderHeaders := #[]
  baseUrl : Option String := none
deriving BEq

structure ApiKeyCredential where
  key : Option String := none
  env : ProviderEnv := #[]
deriving BEq

structure OAuthCredential where
  access : String
  refresh : String
  expires : Nat
  extra : Array (String × Lean.Json) := #[]
deriving BEq

inductive Credential where
  | apiKey (credential : ApiKeyCredential)
  | oauth (credential : OAuthCredential)
deriving BEq

def providerEnvToJson (env : ProviderEnv) : Lean.Json :=
  LeanAgent.Json.obj (env.toList.map fun (name, value) => (name, LeanAgent.Json.str value))

def providerEnvFromJson (json : Lean.Json) : Except String ProviderEnv := do
  let obj ← json.getObj?
  let mut env := #[]
  for (name, value) in Std.TreeMap.Raw.toList obj do
    let value ← value.getStr?
    env := env.push (name, value)
  pure env

def apiKeyCredentialToJson (credential : ApiKeyCredential) : Lean.Json :=
  let fields :=
    [("type", LeanAgent.Json.str "api_key")]
      ++ (match credential.key with
          | some key => [("key", LeanAgent.Json.str key)]
          | none => [])
      ++ (if credential.env.isEmpty then [] else [("env", providerEnvToJson credential.env)])
  LeanAgent.Json.obj fields

def isOAuthCredentialReservedField (name : String) : Bool :=
  name == "type" || name == "access" || name == "refresh" || name == "expires"

def oauthCredentialToJson (credential : OAuthCredential) : Lean.Json :=
  let extra := credential.extra.toList.filter fun (name, _) => !isOAuthCredentialReservedField name
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str "oauth")
     , ("access", LeanAgent.Json.str credential.access)
     , ("refresh", LeanAgent.Json.str credential.refresh)
     , ("expires", LeanAgent.Json.nat credential.expires)
     ] ++ extra)

def credentialToJson : Credential → Lean.Json
  | .apiKey credential => apiKeyCredentialToJson credential
  | .oauth credential => oauthCredentialToJson credential

def apiKeyCredentialFromJson (json : Lean.Json) : Except String ApiKeyCredential := do
  let key ← LeanAgent.Json.optionalString json "key"
  let env ←
    match LeanAgent.Json.optVal? json "env" with
    | some value => providerEnvFromJson value
    | none => pure #[]
  pure { key, env }

def requiredNat (json : Lean.Json) (key : String) : Except String Nat := do
  match LeanAgent.Json.optionalNat json key with
  | .ok (some value) => pure value
  | .ok none => throw s!"property not found: {key}"
  | .error err => throw err

def oauthCredentialFromJson (json : Lean.Json) : Except String OAuthCredential := do
  let access ← LeanAgent.Json.requiredString json "access"
  let refresh ← LeanAgent.Json.requiredString json "refresh"
  let expires ← requiredNat json "expires"
  let obj ← json.getObj?
  let mut extra := #[]
  for (name, value) in Std.TreeMap.Raw.toList obj do
    if !isOAuthCredentialReservedField name then
      extra := extra.push (name, value)
  pure { access, refresh, expires, extra }

def credentialFromJson (json : Lean.Json) : Except String Credential := do
  match ← (← json.getObjVal? "type").getStr? with
  | "api_key" => pure (.apiKey (← apiKeyCredentialFromJson json))
  | "oauth" => pure (.oauth (← oauthCredentialFromJson json))
  | other => throw s!"unsupported credential type: {other}"

def epochMsNow : IO Nat := do
  let timestamp ← Std.Time.Timestamp.now
  pure timestamp.toMillisecondsSinceUnixEpoch.val.toNat

structure AuthContext where
  env : String → IO (Option String)
  fileExists : String → IO Bool
  nowMs : IO Nat := epochMsNow

structure AuthResult where
  auth : ModelAuth
  env : ProviderEnv := #[]
  source : Option String := none
deriving BEq

structure CredentialStore where
  read : String → IO (Option Credential)
  modify : String → (Option Credential → IO (Option Credential)) → IO (Option Credential)
  delete : String → IO Unit

structure ApiKeyAuth where
  name : String
  resolve : AuthContext → Option ApiKeyCredential → Option String → IO (Option AuthResult)

structure OAuthAuth where
  name : String
  login : Option (IO OAuthCredential) := none
  refresh : OAuthCredential → IO OAuthCredential
  toAuth : OAuthCredential → IO ModelAuth

structure LazyOAuthOptions where
  name : String
  load : IO OAuthAuth

def lazyOAuth (input : LazyOAuthOptions) : IO OAuthAuth := do
  let loaded ← IO.mkRef (none : Option OAuthAuth)
  let loadOnce : IO OAuthAuth := do
    match ← loaded.get with
    | some oauth => pure oauth
    | none =>
        let oauth ← input.load
        loaded.set (some oauth)
        pure oauth
  pure
    { name := input.name
      login := some do
        let oauth ← loadOnce
        match oauth.login with
        | some login => login
        | none => throw (IO.userError s!"OAuth login is not available for {input.name}")
      refresh := fun credential => do
        let oauth ← loadOnce
        oauth.refresh credential
      toAuth := fun credential => do
        let oauth ← loadOnce
        oauth.toAuth credential
    }

structure ProviderAuth where
  apiKey : Option ApiKeyAuth := none
  oauth : Option OAuthAuth := none

structure AuthOverrides where
  apiKey : Option String := none
  env : ProviderEnv := #[]
deriving BEq

def providerEnvGet? (env : ProviderEnv) (name : String) : Option String :=
  env.findSome? fun (entryName, value) =>
    if entryName == name && !value.trimAscii.isEmpty then some value else none

def providerEnvMerge (base override : ProviderEnv) : ProviderEnv :=
  let withoutOverridden := base.filter fun (name, _) =>
    override.all fun (overrideName, _) => overrideName != name
  withoutOverridden ++ override

def headersMerge (base override : ProviderHeaders) : ProviderHeaders :=
  let withoutOverridden := base.filter fun (name, _) =>
    override.all fun (overrideName, _) => overrideName != name
  withoutOverridden ++ override

def overlayEnvAuthContext (base : AuthContext) (env : ProviderEnv) : AuthContext :=
  { env := fun name => do
      match providerEnvGet? env name with
      | some value => pure (some value)
      | none => base.env name
    fileExists := base.fileExists
    nowMs := base.nowMs
  }

def expandHomePath (path : String) : IO System.FilePath := do
  if path.startsWith "~" then
    match ← IO.getEnv "HOME" with
    | some home => pure (System.FilePath.mk (home ++ path.drop 1))
    | none => pure (System.FilePath.mk path)
  else
    pure (System.FilePath.mk path)

def defaultProviderAuthContext : AuthContext :=
  { env := fun name => do
      match ← IO.getEnv name with
      | some value =>
          let trimmed := value.trimAscii.toString
          pure (if trimmed.isEmpty then none else some trimmed)
      | none => pure none
    fileExists := fun path => do
      let resolved ← expandHomePath path
      resolved.pathExists
    nowMs := epochMsNow
  }

def resolveEnvApiKey (ctx : AuthContext) (envVars : Array String) : IO (Option (String × String)) := do
  let mut found := none
  for envVar in envVars do
    if found.isNone then
      match ← ctx.env envVar with
      | some value => found := some (envVar, value)
      | none => pure ()
  pure found

def envApiKeyAuth (name : String) (envVars : Array String) : ApiKeyAuth :=
  { name := name
    resolve := fun ctx credential _modelBaseUrl => do
      match credential with
      | some credential =>
          match credential.key with
          | some key =>
              if key.trimAscii.isEmpty then
                pure none
              else
                pure (some { auth := { apiKey := some key }, env := credential.env, source := some "stored credential" })
          | none =>
              match ← resolveEnvApiKey (overlayEnvAuthContext ctx credential.env) envVars with
              | some (source, key) =>
                  pure (some { auth := { apiKey := some key }, env := credential.env, source := some source })
              | none => pure none
      | none =>
          match ← resolveEnvApiKey ctx envVars with
          | some (source, key) => pure (some { auth := { apiKey := some key }, source := some source })
          | none => pure none
  }

def resolveApiKey
    (ctx : AuthContext)
    (apiKeyAuth : ApiKeyAuth)
    (credential : Option ApiKeyCredential)
    (modelBaseUrl : Option String := none) : IO (Option AuthResult) :=
  apiKeyAuth.resolve ctx credential modelBaseUrl

def oauthModelsError (message : String) : IO.Error :=
  IO.userError s!"ModelsError(oauth): {message}"

def oauthCredentialIsExpired (ctx : AuthContext) (credential : OAuthCredential) : IO Bool := do
  let now ← ctx.nowMs
  pure (now >= credential.expires)

def resolveStoredOAuth
    (ctx : AuthContext)
    (credentials : CredentialStore)
    (providerId : String)
    (oauth : OAuthAuth)
    (stored : OAuthCredential) : IO (Option AuthResult) := do
  let mut credential := stored
  if ← oauthCredentialIsExpired ctx credential then
    let post ←
      try
        credentials.modify providerId fun current => do
          match current with
          | some (.oauth currentOAuth) =>
              if ← oauthCredentialIsExpired ctx currentOAuth then
                pure (some (.oauth (← oauth.refresh currentOAuth)))
              else
                pure none
          | _ => pure none
      catch _ =>
        throw (oauthModelsError s!"Failed to refresh OAuth token for {providerId}")
    match post with
    | some (.oauth refreshed) => credential := refreshed
    | _ => return none
  pure (some { auth := (← oauth.toAuth credential), source := some "OAuth" })

def readCredential (credentials : CredentialStore) (providerId : String) : IO (Option Credential) :=
  credentials.read providerId

def resolveProviderAuth
    (providerId : String)
    (auth : ProviderAuth)
    (credentials : CredentialStore)
    (ctx : AuthContext)
    (overrides : AuthOverrides := {})
    (modelBaseUrl : Option String := none) : IO (Option AuthResult) := do
  let requestCtx :=
    if overrides.env.isEmpty then
      ctx
    else
      overlayEnvAuthContext ctx overrides.env
  match overrides.apiKey, auth.apiKey with
  | some apiKey, some apiKeyAuth =>
      resolveApiKey requestCtx apiKeyAuth (some { key := some apiKey, env := overrides.env }) modelBaseUrl
  | _, _ =>
      match ← readCredential credentials providerId with
      | some (.apiKey credential) =>
          match auth.apiKey with
          | some apiKeyAuth =>
              let credential :=
                if overrides.env.isEmpty then
                  credential
                else
                  { credential with env := providerEnvMerge credential.env overrides.env }
              resolveApiKey requestCtx apiKeyAuth credential modelBaseUrl
          | none => pure none
      | some (.oauth credential) =>
          match auth.oauth with
          | some oauth => resolveStoredOAuth requestCtx credentials providerId oauth credential
          | none => pure none
      | none =>
          match auth.apiKey with
          | some apiKeyAuth => resolveApiKey requestCtx apiKeyAuth none modelBaseUrl
          | none => pure none

def InMemoryCredentialStore.mk : IO CredentialStore := do
  let credentials ← IO.mkRef (Array.empty : Array (String × Credential))
  let readCredential (providerId : String) : IO (Option Credential) := do
    let entries ← credentials.get
    pure (entries.findSome? fun (id, credential) => if id == providerId then some credential else none)
  let writeCredential (providerId : String) (credential : Credential) : IO Unit := do
    credentials.modify fun entries =>
      let withoutProvider := entries.filter fun (id, _) => id != providerId
      withoutProvider.push (providerId, credential)
  let deleteCredential (providerId : String) : IO Unit := do
    credentials.modify fun entries => entries.filter fun (id, _) => id != providerId
  pure
    { read := readCredential
      modify := fun providerId fn => do
        let current ← readCredential providerId
        let next ← fn current
        match next with
        | some credential => writeCredential providerId credential
        | none => pure ()
        match next with
        | some credential => pure (some credential)
        | none => pure current
      delete := deleteCredential
    }

namespace FileCredentialStore

def entriesToJson (entries : Array (String × Credential)) : Lean.Json :=
  LeanAgent.Json.obj (entries.toList.map fun (providerId, credential) =>
    (providerId, credentialToJson credential))

def entriesFromJson (json : Lean.Json) : Except String (Array (String × Credential)) := do
  let obj ← json.getObj?
  let mut entries := #[]
  for (providerId, rawCredential) in Std.TreeMap.Raw.toList obj do
    entries := entries.push (providerId, (← credentialFromJson rawCredential))
  pure entries

def readEntries (path : System.FilePath) : IO (Array (String × Credential)) := do
  if !(← path.pathExists) then
    pure #[]
  else
    let raw ← IO.FS.readFile path
    if raw.trimAscii.isEmpty then
      pure #[]
    else
      match Lean.Json.parse raw >>= entriesFromJson with
      | .ok entries => pure entries
      | .error err => throw (IO.userError s!"failed to read credential store {path}: {err}")

def writeEntries (path : System.FilePath) (entries : Array (String × Credential)) : IO Unit := do
  match path.parent with
  | some parent => IO.FS.createDirAll parent
  | none => pure ()
  IO.FS.writeFile path (entriesToJson entries).pretty

def readProvider (path : System.FilePath) (providerId : String) : IO (Option Credential) := do
  let entries ← readEntries path
  pure (entries.findSome? fun (id, credential) => if id == providerId then some credential else none)

def writeProvider (path : System.FilePath) (providerId : String) (credential : Credential) : IO Unit := do
  let entries ← readEntries path
  let withoutProvider := entries.filter fun (id, _) => id != providerId
  writeEntries path (withoutProvider.push (providerId, credential))

def deleteProvider (path : System.FilePath) (providerId : String) : IO Unit := do
  let entries ← readEntries path
  writeEntries path (entries.filter fun (id, _) => id != providerId)

def mk (path : System.FilePath) : IO CredentialStore :=
  pure
    { read := readProvider path
      modify := fun providerId fn => do
        let current ← readProvider path providerId
        let next ← fn current
        match next with
        | some credential => writeProvider path providerId credential
        | none => pure ()
        match next with
        | some credential => pure (some credential)
        | none => pure current
      delete := deleteProvider path
    }

end FileCredentialStore

end LeanAgent.AI.Auth
