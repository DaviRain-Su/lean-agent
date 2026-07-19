import Lean
import LeanAgent.Json
import LeanAgent.CodingAgent.Config

/-!
# One-time startup migrations (Pi `packages/coding-agent/src/migrations.ts`)

Offline, filesystem-driven migrations run once on startup:

- `migrateAuthToAuthJson`: legacy `oauth.json` + `settings.json` `apiKeys` → `auth.json`
- `migrateSessionsFromAgentRoot`: move stray `~/.pi/agent/*.jsonl` into `sessions/<encoded-cwd>/`
- `migrateCommandsToPrompts`: rename `commands/` → `prompts/`
- `migrateToolsToBin`: move managed `fd`/`rg` binaries `tools/` → `bin/`
- `checkDeprecatedExtensionDirs`: warn about legacy `hooks/` / custom `tools/`

`agentDir` is an explicit parameter so offline tests can drive temp directories
without touching the real config dir. The interactive `showDeprecationWarnings`
keypress wait (stdin raw mode) is Node-only and omitted here; callers receive
the warning strings (`runMigrations` returns them). POSIX file mode `0o600` on
`auth.json` and the `keybindings.json` migration (depends on the unbuilt
`core/keybindings.ts`) are documented subsets.
-/

namespace LeanAgent.CodingAgent.Migrations

open LeanAgent.CodingAgent.Config

/-- Encode a cwd into the session directory name used by session-manager.

`--${cwd without leading slash/backslash, with / \ : replaced by -}--`. -/
def encodeSessionDir (cwd : String) : String :=
  let stripped :=
    match cwd.toList with
    | '/' :: rest => String.ofList rest
    | '\\' :: rest => String.ofList rest
    | _ => cwd
  let replaced :=
    stripped.toList.map fun c =>
      if c == '/' || c == '\\' || c == ':' then '-' else c
  "--" ++ String.ofList replaced ++ "--"

/-- Rebuild a JSON object without `key`. -/
def removeObjectKey (json : Lean.Json) (key : String) : Lean.Json :=
  match json.getObj? with
  | .ok obj => Lean.Json.mkObj (obj.toArray.filter (fun (k, _) => k != key)).toList
  | .error _ => json

/-- Merge a credential object with `{ type: typ }` (Pi `{ type: typ, ...cred }`). -/
def withType (cred : Lean.Json) (typ : String) : Lean.Json :=
  match cred.getObj? with
  | .ok obj => LeanAgent.Json.obj ([("type", LeanAgent.Json.str typ)] ++ obj.toArray.toList)
  | .error _ => LeanAgent.Json.obj [("type", LeanAgent.Json.str typ)]

-- ============================================================================
-- migrateAuthToAuthJson
-- ============================================================================

/-- Pi `migrateAuthToAuthJson`: legacy oauth.json + settings.json apiKeys → auth.json.
Returns the list of provider names migrated. No-op if `auth.json` already exists. -/
def migrateAuthToAuthJson (agentDir : System.FilePath) : IO (Array String) := do
  let authPath := agentDir / "auth.json"
  if (← authPath.pathExists) then pure #[]
  else
    let oauthPath := agentDir / "oauth.json"
    let settingsPath := agentDir / "settings.json"
    let mut migrated : Std.HashMap String Lean.Json := {}
    let mut providers := #[]
    -- oauth.json
    if (← oauthPath.pathExists) then
      try
        let content ← IO.FS.readFile oauthPath
        match Lean.Json.parse content with
        | .ok json =>
            match json.getObj? with
            | .ok obj =>
                for (provider, cred) in obj.toArray do
                  migrated := migrated.insert provider (withType cred "oauth")
                  providers := providers.push provider
                IO.FS.rename oauthPath (System.FilePath.mk (oauthPath.toString ++ ".migrated"))
            | .error _ => pure ()
        | .error _ => pure ()
      catch _ => pure ()
    -- settings.json apiKeys
    if (← settingsPath.pathExists) then
      try
        let content ← IO.FS.readFile settingsPath
        match Lean.Json.parse content with
        | .ok settings =>
            match LeanAgent.Json.optVal? settings "apiKeys" with
            | some apiKeys =>
                match apiKeys.getObj? with
                | .ok keysObj =>
                    for (provider, keyVal) in keysObj.toArray do
                      match keyVal.getStr? with
                      | .ok key =>
                          if !(migrated.contains provider) then
                            migrated := migrated.insert provider
                              (LeanAgent.Json.obj [("type", LeanAgent.Json.str "api_key"), ("key", LeanAgent.Json.str key)])
                            providers := providers.push provider
                      | .error _ => pure ()
                    if !keysObj.toArray.isEmpty then
                      IO.FS.writeFile settingsPath (removeObjectKey settings "apiKeys").pretty
                | .error _ => pure ()
            | none => pure ()
        | .error _ => pure ()
      catch _ => pure ()
    if migrated.isEmpty then pure providers
    else
      if let some parent := authPath.parent then IO.FS.createDirAll parent
      let pairs := migrated.toArray.map (fun (k, v) => (k, v))
      IO.FS.writeFile authPath (LeanAgent.Json.obj pairs.toList).pretty
      pure providers

-- ============================================================================
-- migrateSessionsFromAgentRoot
-- ============================================================================

/-- First line of a file (the session header for `.jsonl`), or "". -/
def readFirstLine (path : System.FilePath) : IO String := do
  try
    let content ← IO.FS.readFile path
    match content.splitOn "\n" with
    | first :: _ => pure first
    | [] => pure ""
  catch _ => pure ""

/-- Pi `migrateSessionsFromAgentRoot`: move `.jsonl` files left in `agentDir/`
into `agentDir/sessions/<encoded-cwd>/` based on the `cwd` in their header. -/
def migrateSessionsFromAgentRoot (agentDir : System.FilePath) : IO Unit := do
  let dirExists ← agentDir.pathExists
  if !dirExists then pure ()
  else
    try
      let entries ← agentDir.readDir
      for entry in entries do
        let path := entry.path
        let isDir ← path.isDir
        if isDir || !path.toString.endsWith ".jsonl" then pure ()
        else
          let firstLine ← readFirstLine path
          let trimmed := firstLine.trimAscii.toString
          if trimmed.isEmpty then pure ()
          else
            match Lean.Json.parse trimmed with
            | .ok header =>
                match LeanAgent.Json.optVal? header "type", LeanAgent.Json.optVal? header "cwd" with
                | some (.str "session"), some (.str cwd) =>
                    let safePath := encodeSessionDir cwd
                    let correctDir := agentDir / "sessions" / safePath
                    let dirExists ← correctDir.pathExists
                    if !dirExists then IO.FS.createDirAll correctDir
                    let fileName :=
                      match (path.toString.splitOn "/").getLast? with
                      | some f => f
                      | none => path.toString
                    let newPath := correctDir / fileName
                    let targetExists ← newPath.pathExists
                    if targetExists then pure ()
                    else IO.FS.rename path newPath
                | _, _ => pure ()
            | .error _ => pure ()
    catch _ => pure ()

-- ============================================================================
-- migrateCommandsToPrompts
-- ============================================================================

/-- Pi `migrateCommandsToPrompts`: rename `commands/` → `prompts/` when only
the former exists. Returns true if a rename happened. -/
def migrateCommandsToPrompts (baseDir : System.FilePath) : IO Bool := do
  let commandsDir := baseDir / "commands"
  let promptsDir := baseDir / "prompts"
  let commandsExists ← commandsDir.pathExists
  let promptsExists ← promptsDir.pathExists
  if commandsExists && !promptsExists then
    try
      IO.FS.rename commandsDir promptsDir
      pure true
    catch _ => pure false
  else pure false

-- ============================================================================
-- migrateToolsToBin
-- ============================================================================

/-- Names of managed binaries that may live under `tools/`. -/
def managedBinaries : Array String := #["fd", "rg", "fd.exe", "rg.exe"]

/-- Pi `migrateToolsToBin`: move managed `fd`/`rg` binaries from `tools/` to `bin/`. -/
def migrateToolsToBin (agentDir : System.FilePath) (binDir : System.FilePath) : IO Bool := do
  let toolsDir := agentDir / "tools"
  let toolsExists ← toolsDir.pathExists
  if !toolsExists then pure false
  else
    let binExists ← binDir.pathExists
    if !binExists then IO.FS.createDirAll binDir
    let mut movedAny := false
    for bin in managedBinaries do
      let oldPath := toolsDir / bin
      let newPath := binDir / bin
      let oldExists ← oldPath.pathExists
      if oldExists then
        let newExists ← newPath.pathExists
        if newExists then
          try IO.FS.removeFile oldPath catch _ => pure ()
        else
          try
            IO.FS.rename oldPath newPath
            movedAny := true
          catch _ => pure ()
    pure movedAny

-- ============================================================================
-- checkDeprecatedExtensionDirs
-- ============================================================================

/-- Names that are auto-extracted binaries (not custom tools). -/
def isManagedBinaryName (name : String) : Bool :=
  let lower := name.toLower
  lower == "fd" || lower == "rg" || lower == "fd.exe" || lower == "rg.exe"

/-- Pi `checkDeprecatedExtensionDirs`: warnings for legacy `hooks/` /
custom `tools/` contents. -/
def checkDeprecatedExtensionDirs (baseDir : System.FilePath) (label : String) :
    IO (Array String) := do
  let hooksDir := baseDir / "hooks"
  let toolsDir := baseDir / "tools"
  let mut warnings := #[]
  if (← hooksDir.pathExists) then
    warnings := warnings.push
      (s!"{label} hooks/ directory found. Hooks have been renamed to extensions.")
  if (← toolsDir.pathExists) then
    try
      let entries ← toolsDir.readDir
      let names := entries.map (fun e => e.path.fileName.getD "")
      let custom := names.filter (fun n =>
        !(isManagedBinaryName n) && !(n.startsWith "."))
      if !custom.isEmpty then
        warnings := warnings.push
          (s!"{label} tools/ directory contains custom tools. Custom tools have been merged into extensions.")
    catch _ => pure ()
  pure warnings

-- ============================================================================
-- migrateExtensionSystem + runMigrations
-- ============================================================================

/-- Pi `migrateExtensionSystem`: commands→prompts migration + deprecation warnings. -/
def migrateExtensionSystem (cwd : System.FilePath) (agentDir : System.FilePath) :
    IO (Array String) := do
  let _ ← migrateCommandsToPrompts agentDir
  let _ ← migrateCommandsToPrompts (cwd / configDirName)
  let warnings := #[]
  let warnings := warnings ++ (← checkDeprecatedExtensionDirs agentDir "Global")
  let warnings := warnings ++ (← checkDeprecatedExtensionDirs (cwd / configDirName) "Project")
  pure warnings

/-- Result of `runMigrations`. -/
structure MigrationResult where
  migratedAuthProviders : Array String := #[]
  deprecationWarnings : Array String := #[]
deriving Inhabited, Repr

/-- Pi `runMigrations` (offline subset): auth/session/tools/commands migrations
plus deprecation warnings. `keybindings.json` migration (needs `core/keybindings.ts`)
is not ported. -/
def runMigrations (cwd : System.FilePath) (agentDir : System.FilePath) :
    IO MigrationResult := do
  let migratedAuthProviders ← migrateAuthToAuthJson agentDir
  migrateSessionsFromAgentRoot agentDir
  let binDir := agentDir / "bin"
  let _ ← migrateToolsToBin agentDir binDir
  let deprecationWarnings ← migrateExtensionSystem cwd agentDir
  pure { migratedAuthProviders := migratedAuthProviders, deprecationWarnings := deprecationWarnings }

/-- Convenience: run against the real agent dir (Pi default entrypoint). -/
def runMigrationsWithDefaultAgentDir (cwd : System.FilePath) : IO MigrationResult := do
  runMigrations cwd (← getAgentDir)

/-- Format deprecation warnings as a single message block (Pi `showDeprecationWarnings`
text; the interactive stdin keypress wait is Node-only and omitted). -/
def formatDeprecationWarnings (warnings : Array String) : String :=
  if warnings.isEmpty then ""
  else
    let body := String.intercalate "\n" (warnings.map (fun w => "Warning: " ++ w)).toList
    body ++ "\n\nMove your extensions to the extensions/ directory."

end LeanAgent.CodingAgent.Migrations
