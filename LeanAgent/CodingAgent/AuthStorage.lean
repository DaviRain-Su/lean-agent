import Lean
import LeanAgent.Json
import LeanAgent.CodingAgent.Config
import LeanAgent.CodingAgent.ResolveConfigValue

/-!
# Auth storage (Pi `auth-storage.ts` offline subset)

JSON file map of provider → api_key credentials. OAuth refresh/locking deferred
to AI Auth (process-file locks) / Exclusion for proper-lockfile parity.
-/

namespace LeanAgent.CodingAgent.AuthStorage

open LeanAgent.CodingAgent.Config

inductive AuthCredential where
  | apiKey (key : String)
  | oauth (access : String) (refresh : Option String := none)
deriving Inhabited, BEq

structure AuthStorage where
  path : System.FilePath
  dataRef : IO.Ref (Std.HashMap String AuthCredential)

namespace AuthStorage

def emptyData : Std.HashMap String AuthCredential := {}

def credentialToJson : AuthCredential → Lean.Json
  | .apiKey key =>
      LeanAgent.Json.obj
        [ ("type", LeanAgent.Json.str "api_key")
        , ("key", LeanAgent.Json.str key)
        ]
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
      | some (.str key) => some (.apiKey key)
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

/-- Resolve API key string for a provider (api_key only offline). -/
def getApiKey (s : AuthStorage) (provider : String) : IO (Option String) := do
  match ← s.get provider with
  | some (.apiKey key) =>
      -- Allow `$ENV` templates in stored keys.
      LeanAgent.CodingAgent.ResolveConfigValue.resolveConfigValue key
  | some (.oauth access _) => pure (some access)
  | none => pure none

def setApiKey (s : AuthStorage) (provider : String) (key : String) : IO Unit :=
  s.set provider (.apiKey key)

end AuthStorage
/-- Reload (Pi subset). -/
def reload (s : AuthStorage) : IO AuthStorage := pure s


end LeanAgent.CodingAgent.AuthStorage
