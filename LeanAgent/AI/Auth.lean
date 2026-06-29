import Lean
import LeanAgent.AI.Types

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

inductive Credential where
  | apiKey (credential : ApiKeyCredential)
deriving BEq

structure AuthContext where
  env : String → IO (Option String)
  fileExists : String → IO Bool

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

structure ProviderAuth where
  apiKey : Option ApiKeyAuth := none

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
  }

def expandHomePath (path : String) : IO System.FilePath := do
  if path.startsWith "~/" then
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

end LeanAgent.AI.Auth
