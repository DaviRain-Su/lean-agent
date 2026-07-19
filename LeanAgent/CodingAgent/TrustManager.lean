import Lean
import LeanAgent.Json
import LeanAgent.CodingAgent.Config
import LeanAgent.CodingAgent.Utils.Paths

/-!
# Project trust manager (Pi `packages/coding-agent/src/core/trust-manager.ts`)

Manages project trust decisions persisted in `<agentDir>/trust.json`. A trust
decision is a boolean (`true` = trusted, `false` = not trusted) or `null`
(no decision / cleared). Decisions are keyed by canonicalized absolute path
and inherited from the nearest ancestor directory.

File locking uses a simple `.lock` sentinel with retry (Pi uses
`proper-lockfile` which is Exclusion List §7; the Lean port substitutes a
cooperative lock for single-process safety).

`hasTrustRequiringProjectResources` checks whether a cwd has project-local
resources (`.pi/settings.json`, `.pi/extensions`, `.pi/skills`, `.pi/prompts`,
`.pi/themes`, `.pi/SYSTEM.md`, `.pi/APPEND_SYSTEM.md`, or `.agents/skills`)
that must be gated by project trust.
-/

namespace LeanAgent.CodingAgent.TrustManager

open LeanAgent.CodingAgent.Config
open LeanAgent.CodingAgent.Utils.Paths

-- ============================================================================
-- Types
-- ============================================================================

/-- Pi `ProjectTrustDecision`: `true`, `false`, or `null` (no decision). -/
abbrev ProjectTrustDecision : Type := Option Bool

/-- Pi `ProjectTrustStoreEntry`. -/
structure ProjectTrustStoreEntry where
  path : String
  decision : Bool
deriving Inhabited, BEq

/-- Pi `ProjectTrustUpdate`. -/
structure ProjectTrustUpdate where
  path : String
  decision : ProjectTrustDecision
deriving Inhabited

/-- Pi `ProjectTrustOption`. -/
structure ProjectTrustOption where
  label : String
  trusted : Bool
  updates : Array ProjectTrustUpdate
  savedPath : Option String := none
deriving Inhabited

-- ============================================================================
-- Trust-requiring resources
-- ============================================================================

/-- Pi `TRUST_REQUIRING_PROJECT_CONFIG_RESOURCES`. -/
def trustRequiringProjectConfigResources : Array String :=
  #["settings.json", "extensions", "skills", "prompts", "themes",
    "SYSTEM.md", "APPEND_SYSTEM.md"]

-- ============================================================================
-- Path helpers
-- ============================================================================

/-- Pi `normalizeCwd`: canonicalize + resolve. -/
def normalizeCwd (cwd : String) : IO String :=
  canonicalizePath cwd

/-- Pi `getProjectTrustParentPath`. -/
def getProjectTrustParentPath (cwd : String) : IO (Option String) := do
  let trustPath ← normalizeCwd cwd
  let fp := System.FilePath.mk trustPath
  match fp.parent with
  | some parent =>
      let parentStr := parent.toString
      if parentStr == trustPath then pure none
      else pure (some parentStr)
  | none => pure none

-- ============================================================================
-- Trust file I/O
-- ============================================================================

/-- Read and parse a trust.json file. Returns empty map on missing/invalid. -/
def readTrustFile (path : System.FilePath) : IO (Std.HashMap String (Option Bool)) := do
  if !(← path.pathExists) then
    return {}
  let content ← IO.FS.readFile path
  match Lean.Json.parse content with
  | .error _ => pure {}
  | .ok json =>
      match json.getObj? with
      | .error _ => pure {}
      | .ok obj =>
          let mut m : Std.HashMap String (Option Bool) := {}
          for (key, val) in obj.toArray do
            match val.getBool? with
            | .ok b => m := m.insert key (some b)
            | .error _ =>
                if val.isNull then
                  m := m.insert key none
                else
                  pure ()
          pure m

/-- Write a trust.json file (sorted keys, pretty-printed). -/
def writeTrustFile (path : System.FilePath) (data : Std.HashMap String (Option Bool)) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  -- Sort keys and build JSON object.
  let mut keys : Array String := data.toArray.map (·.1)
  keys := keys.qsort (fun a b => a < b)
  let mut fields : List (String × LeanAgent.Json.J) := []
  for key in keys do
    match data.get? key with
    | some (some true) => fields := fields ++ [(key, LeanAgent.Json.bool true)]
    | some (some false) => fields := fields ++ [(key, LeanAgent.Json.bool false)]
    | some none => fields := fields ++ [(key, LeanAgent.Json.null)]
    | none => pure ()
  let json := LeanAgent.Json.obj fields
  IO.FS.writeFile path (json.pretty ++ "\n")

-- ============================================================================
-- File locking (simple sentinel, Pi `proper-lockfile` substitute)
-- ============================================================================

/--
Acquire a cooperative lock file. Retries up to `maxAttempts` times with
`delayMs` between attempts. Returns the lock path for later release.

Pi uses `proper-lockfile` (Exclusion List §7); the Lean port substitutes a
simple `.lock` sentinel file for single-process safety.
-/
def acquireTrustLock (path : System.FilePath) (maxAttempts : Nat := 10) (delayMs : Nat := 20) :
    IO System.FilePath := do
  let lockPath := System.FilePath.mk (path.toString ++ ".lock")
  if let some parent := lockPath.parent then
    IO.FS.createDirAll parent
  let mut n : Nat := 0
  let mut acquired := false
  while !acquired && n < maxAttempts do
    try
      let handle ← IO.FS.Handle.mk lockPath IO.FS.Mode.write
      handle.putStr (toString (← IO.Process.getPID))
      handle.flush
      acquired := true
    catch _ =>
      -- Lock file exists; wait and retry.
      let start ← IO.monoMsNow
      let mut waited := false
      while !waited do
        let now ← IO.monoMsNow
        if now - start ≥ delayMs then
          waited := true
        else
          pure ()
      n := n + 1
  if !acquired then
    throw (IO.userError s!"Failed to acquire trust store lock after {maxAttempts} attempts")
  pure lockPath

/-- Release a previously acquired lock file. -/
def releaseTrustLock (lockPath : System.FilePath) : IO Unit := do
  try
    if (← lockPath.pathExists) then
      IO.FS.removeFile lockPath
  catch _ =>
    pure ()

/-- Pi `withTrustFileLock`: execute `fn` under the trust file lock. -/
def withTrustFileLock (path : System.FilePath) (fn : IO α) : IO α := do
  let lockPath ← acquireTrustLock path
  try
    fn
  finally
    releaseTrustLock lockPath

-- ============================================================================
-- Trust entry lookup
-- ============================================================================

/--
Pi `findNearestTrustEntry`: walk up the directory tree from `cwd` looking
for the nearest ancestor with a trust decision.
-/
def findNearestTrustEntry (data : Std.HashMap String (Option Bool)) (cwd : String) :
    IO (Option ProjectTrustStoreEntry) := do
  let mut currentDir ← normalizeCwd cwd
  let mut found : Option ProjectTrustStoreEntry := none
  let mut done := false
  while !done do
    match data.get? currentDir with
    | some (some b) =>
        found := some { path := currentDir, decision := b }
        done := true
    | _ =>
        let fp := System.FilePath.mk currentDir
        match fp.parent with
        | some parent =>
            let parentStr := parent.toString
            if parentStr == currentDir then
              done := true
            else
              currentDir := parentStr
        | none => done := true
  pure found

-- ============================================================================
-- Trust options
-- ============================================================================

/--
Pi `getProjectTrustOptions`: build the list of trust options for a cwd.
Includes "Trust", "Trust parent folder", "Do not trust", and optionally
session-only variants.
-/
def getProjectTrustOptions (cwd : String) (includeSessionOnly : Bool := false) :
    IO (Array ProjectTrustOption) := do
  let trustPath ← normalizeCwd cwd
  let mut options : Array ProjectTrustOption := #[
    { label := "Trust"
      trusted := true
      updates := #[{ path := trustPath, decision := some true }]
      savedPath := some trustPath }
  ]
  let parentPath? ← getProjectTrustParentPath cwd
  match parentPath? with
  | some parentPath =>
      options := options.push
        { label := s!"Trust parent folder ({parentPath})"
          trusted := true
          updates := #[
            { path := parentPath, decision := some true },
            { path := trustPath, decision := none }
          ]
          savedPath := some parentPath }
  | none => pure ()
  if includeSessionOnly then
    options := options.push
      { label := "Trust (this session only)"
        trusted := true
        updates := #[] }
  options := options.push
    { label := "Do not trust"
      trusted := false
      updates := #[{ path := trustPath, decision := some false }]
      savedPath := some trustPath }
  if includeSessionOnly then
    options := options.push
      { label := "Do not trust (this session only)"
        trusted := false
        updates := #[] }
  pure options

-- ============================================================================
-- hasTrustRequiringProjectResources
-- ============================================================================

/--
Pi `hasTrustRequiringProjectResources`: returns true when `cwd` has
project-local resources that must be gated by project trust.

Checks for trust-requiring entries under `<cwd>/.pi` and `.agents/skills`
in cwd or ancestors (excluding the user-global `~/.agents/skills`).
-/
def hasTrustRequiringProjectResources (cwd : String) : IO Bool := do
  let homeDir ← match ← IO.getEnv "HOME" with
    | some h => canonicalizePath h
    | none => pure ""
  let userAgentsSkillsDir :=
    if homeDir.isEmpty then System.FilePath.mk ".agents/skills"
    else System.FilePath.mk homeDir / ".agents" / "skills"
  let startDir ← canonicalizePath cwd
  -- Check `<cwd>/.pi` for trust-requiring resources.
  let configDir := System.FilePath.mk startDir / configDirName
  for entry in trustRequiringProjectConfigResources do
    if ← (configDir / entry).pathExists then
      return true
  -- Walk up checking `.agents/skills`.
  let mut currentDir := startDir
  let mut found := false
  let mut done := false
  while !done do
    let agentsSkillsDir := System.FilePath.mk currentDir / ".agents" / "skills"
    if agentsSkillsDir.toString != userAgentsSkillsDir.toString then
      if ← agentsSkillsDir.pathExists then
        found := true
        done := true
    if !done then
      let fp := System.FilePath.mk currentDir
      match fp.parent with
      | some parent =>
          let parentStr := parent.toString
          if parentStr == currentDir then
            done := true
          else
            currentDir := parentStr
      | none => done := true
  pure found

-- ============================================================================
-- ProjectTrustStore
-- ============================================================================

/--
Pi `ProjectTrustStore`: persisted trust decisions in `<agentDir>/trust.json`.
-/
structure ProjectTrustStore where
  trustPath : System.FilePath
deriving Inhabited

namespace ProjectTrustStore

/-- Pi `ProjectTrustStore` constructor: open the trust store at `<agentDir>/trust.json`. -/
def create (agentDir : System.FilePath) : IO ProjectTrustStore := do
  let trustPath ← canonicalizePath (agentDir / "trust.json").toString
  pure { trustPath := System.FilePath.mk trustPath }

/-- Pi `getEntry`: read trust file and find nearest entry for cwd. -/
def getEntry (store : ProjectTrustStore) (cwd : String) : IO (Option ProjectTrustStoreEntry) :=
  withTrustFileLock store.trustPath do
    let data ← readTrustFile store.trustPath
    findNearestTrustEntry data cwd

/-- Pi `get`: return the boolean decision or null. -/
def get (store : ProjectTrustStore) (cwd : String) : IO ProjectTrustDecision := do
  match ← getEntry store cwd with
  | some e => pure (some e.decision)
  | none => pure none

/-- Pi `setMany`: update multiple trust decisions atomically. -/
def setMany (store : ProjectTrustStore) (decisions : Array ProjectTrustUpdate) : IO Unit :=
  withTrustFileLock store.trustPath do
    let mut data ← readTrustFile store.trustPath
    for update in decisions do
      let key ← normalizeCwd update.path
      data := data.insert key update.decision
    writeTrustFile store.trustPath data

/-- Pi `set`: convenience wrapper for a single decision. -/
def set (store : ProjectTrustStore) (cwd : String) (decision : ProjectTrustDecision) : IO Unit :=
  setMany store #[{ path := cwd, decision := decision }]

end ProjectTrustStore

end LeanAgent.CodingAgent.TrustManager
