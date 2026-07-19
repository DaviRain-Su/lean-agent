import Lean
import LeanAgent.Json
import LeanAgent.CodingAgent.Config
import LeanAgent.CodingAgent.ResolveConfigValue

/-!
# Auth storage (Pi `auth-storage.ts` offline subset)

JSON file map of provider → credentials. `api_key` credentials carry an
optional `env` map (Pi stores `key` + `env` on the api_key record); `oauth`
credentials carry access/refresh tokens.

OAuth refresh, proper-lockfile concurrent locking, and the OAuth provider
registry are deferred to `LeanAgent.AI.Auth` / `LeanAgent.AI.OAuth`
(Exclusion List §7 for proper-lockfile parity).
-/

namespace LeanAgent.CodingAgent.AuthStorage

open LeanAgent.CodingAgent.Config
open LeanAgent.CodingAgent.ResolveConfigValue

/-- Env map carried by `api_key` credentials (Pi `auth.json` `env` field). -/
abbrev EnvMap := Std.HashMap String String

/-- Empty env map convenience. -/
def emptyEnv : EnvMap := {}

/-- Build an env map from a list of pairs (later wins). -/
def envMapFromList (pairs : List (String × String)) : EnvMap :=
  pairs.foldl (fun m (k, v) => m.insert k v) emptyEnv

inductive AuthCredential where
  | apiKey (key : String) (env : EnvMap := emptyEnv)
  | oauth (access : String) (refresh : Option String := none)
deriving Inhabited, BEq

structure AuthStorage where
  path : System.FilePath
  dataRef : IO.Ref (Std.HashMap String AuthCredential)

namespace AuthStorage

def emptyData : Std.HashMap String AuthCredential := {}

/-- Serialize an env map as a JSON object (omitted when empty). -/
def envToJson (env : EnvMap) : Option Lean.Json :=
  if env.isEmpty then none
  else
    let pairs := env.toArray.map (fun (k, v) => (k, LeanAgent.Json.str v))
    some (LeanAgent.Json.obj pairs.toList)

/-- Parse a JSON object into an env map. -/
def envFromJson (json : Lean.Json) : EnvMap :=
  match json.getObj? with
  | .ok obj =>
      obj.toArray.foldl (fun (m : EnvMap) (k, v) =>
        match v.getStr? with
        | .ok s => m.insert k s
        | .error _ => m) emptyEnv
  | .error _ => emptyEnv

def credentialToJson : AuthCredential → Lean.Json
  | .apiKey key env =>
      let base : List (String × Lean.Json) :=
        [ ("type", LeanAgent.Json.str "api_key")
        , ("key", LeanAgent.Json.str key)
        ]
      match envToJson env with
      | some e => LeanAgent.Json.obj (base ++ [("env", e)])
      | none => LeanAgent.Json.obj base
  | .oauth access refresh =>
      let fields : List (String × Lean.Json) :=
        [ ("type", LeanAgent.Json.str "oauth")
        , ("access", LeanAgent.Json.str access)
        ]
      match refresh with
      | some r => LeanAgent.Json.obj (fields ++ [("refresh", LeanAgent.Json.str r)])
      | none => LeanAgent.Json.obj fields

def credentialFromJson (json : Lean.Json) : Option AuthCredential :=
  match LeanAgent.Json.optVal? json "type" with
  | some (.str "api_key") =>
      match LeanAgent.Json.optVal? json "key" with
      | some (.str key) =>
          let env :=
            match LeanAgent.Json.optVal? json "env" with
            | some e => envFromJson e
            | none => emptyEnv
          some (.apiKey key env)
      | _ => none
  | some (.str "oauth") =>
      match LeanAgent.Json.optVal? json "access" with
      | some (.str access) =>
          let refresh :=
            match LeanAgent.Json.optVal? json "refresh" with
            | some (.str r) => some r
            | _ => none
          some (.oauth access refresh)
      | _ => none
  | _ => none

def loadFromFile (path : System.FilePath) : IO (Std.HashMap String AuthCredential) := do
  if !(← path.pathExists) then
    return emptyData
  let content ← IO.FS.readFile path
  if content.trimAscii.toString.isEmpty then
    return emptyData
  match Lean.Json.parse content with
  | .error _ => pure emptyData
  | .ok json =>
      match json.getObj? with
      | .error _ => pure emptyData
      | .ok obj =>
          let mut m := emptyData
          for (provider, val) in obj.toArray do
            match credentialFromJson val with
            | some c => m := m.insert provider c
            | none => pure ()
          pure m

def saveToFile (path : System.FilePath) (data : Std.HashMap String AuthCredential) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let fields := data.toArray.map fun (k, v) => (k, credentialToJson v)
  IO.FS.writeFile path (LeanAgent.Json.obj fields.toList).pretty

/-- Open or create auth storage at path (default: `<agentDir>/auth.json`). -/
def openStorage (path? : Option System.FilePath := none) : IO AuthStorage := do
  let path ←
    match path? with
    | some p => pure p
    | none => pure ((← getAgentDir) / "auth.json")
  let data ← loadFromFile path
  pure { path := path, dataRef := ← IO.mkRef data }

def get (s : AuthStorage) (provider : String) : IO (Option AuthCredential) := do
  pure ((← s.dataRef.get).get? provider)

def set (s : AuthStorage) (provider : String) (cred : AuthCredential) : IO Unit := do
  s.dataRef.modify fun m => m.insert provider cred
  saveToFile s.path (← s.dataRef.get)

def erase (s : AuthStorage) (provider : String) : IO Unit := do
  s.dataRef.modify fun m => m.erase provider
  saveToFile s.path (← s.dataRef.get)

def listProviders (s : AuthStorage) : IO (Array String) := do
  pure ((← s.dataRef.get).toArray.map (·.1))

/-- Env list for a provider's api_key credential (empty for oauth/missing). -/
def getProviderEnv (s : AuthStorage) (provider : String) : IO (List (String × String)) := do
  match ← s.get provider with
  | some (.apiKey _ env) => pure env.toList
  | _ => pure []

/--
Resolve API key string for a provider. For `api_key` credentials, interpolate
`$VAR`/`${VAR}` against the credential's own `env` map first, then the ambient
process environment. `includeFallback` is accepted for parity shape but is a
no-op offline (Pi's fallback walks `authStorage.getApiKey` env-var defaults,
which the offline port does not model).
-/
def getApiKey
    (s : AuthStorage) (provider : String) (includeFallback : Bool := true) :
    IO (Option String) := do
  match ← s.get provider with
  | some (.apiKey key env) =>
      LeanAgent.CodingAgent.ResolveConfigValue.resolveConfigValue key env.toList
  | some (.oauth access _) => pure (some access)
  | none => pure none

def setApiKey (s : AuthStorage) (provider : String) (key : String) : IO Unit :=
  s.set provider (.apiKey key)

/-- True iff `provider` has any credential stored (no refresh, no resolution). -/
def hasAuth (s : AuthStorage) (provider : String) : IO Bool := do
  pure ((← s.get provider).isSome)

/--
Pi `AuthStatus` (subset): describe how a provider is authenticated without
resolving secret values. For `api_key` credentials with `$VAR`/`${VAR}`
templates, `source = "environment"` and `label` lists the referenced env vars
(resolved against the credential env map + ambient env). For literal keys,
`source = "stored"`. For oauth, `source = "oauth"`. Unconfigured →
`{ configured := false }`.
-/
structure AuthStatus where
  configured : Bool
  source : Option String := none
  label : Option String := none
deriving Inhabited

def getAuthStatus (s : AuthStorage) (provider : String) : IO AuthStatus := do
  match ← s.get provider with
  | some (.oauth _ _) => pure { configured := true, source := some "oauth" }
  | some (.apiKey key env) =>
      if isCommandConfigValue key then
        pure { configured := true, source := some "stored" }
      else
        let envNames := getConfigValueEnvVarNames key
        if envNames.isEmpty then
          pure { configured := true, source := some "stored" }
        else
          let configured ← isConfigValueConfigured key env.toList
          if configured then
            pure
              { configured := true
                source := some "environment"
                label := some (String.intercalate ", " envNames.toList) }
          else
            pure { configured := false }
  | none => pure { configured := false }

end AuthStorage
/-- Reload (Pi subset). -/
def reload (s : AuthStorage) : IO AuthStorage := pure s


end LeanAgent.CodingAgent.AuthStorage
