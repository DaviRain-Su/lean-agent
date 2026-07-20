import Lean
import LeanAgent.CodingAgent.Config
import LeanAgent.Agent.Harness.Truncate

/-!
# Shell helpers (Pi `utils/shell.ts`)

Cross-platform bash discovery, shell-env augmentation, and detached-process
tree killing. Ports Pi's `utils/shell.ts`.

The pure resolution logic (`isLegacyWslBashPath`, `getBashShellConfig`,
`findBashOnPath`, `getShellConfig`, `getShellEnv`) is fully offline-testable via
an injectable `ShellDeps` record (platform flag, env probe, existsSync probe,
spawnSync probe) so tests can simulate win32/unix without spawning `which`/
`where`. `defaultShellDeps` wires the real IO (`IO.getEnv`,
`FilePath.pathExists`, `IO.Process`).

`getShellConfig` resolution order matches Pi:
1. user-specified `shellPath` (must exist, else throw),
2. Windows: Git Bash in `%ProgramFiles%` / `%ProgramFiles(x86)%`, then
   `bash.exe` on PATH via `where`,
3. Unix: `/bin/bash`, then `bash` on PATH via `which`, then fallback `sh -c`.

`getShellEnv` returns the augmented PATH (key + value) so callers merge it into
their spawn env; Pi spreads `...process.env` and overrides PATH. The PATH key
lookup is case-insensitive on Windows (Pi scans `Object.keys(env)` for `path`
case-insensitively).

`killProcessTree` / `trackDetachedChildPid` / `untrackDetachedChildPid` /
`killTrackedDetachedChildren` are best-effort process-tree killing:
- Windows: `taskkill /F /T /PID <pid>` (kill tree).
- Unix: `kill -9 -<pid>` (signal the process group); falls back to `kill -9
  <pid>` if the group kill fails. Errors are swallowed (Pi `try/catch`).

`sanitizeBinaryOutput` is re-exported from `Agent.Harness.Truncate` (already
ported) so callers can reach it through this module.
-/

namespace LeanAgent.CodingAgent.Utils.Shell

open System LeanAgent.Agent.Harness.Truncate

-- ===========================================================================
-- ShellConfig
-- ===========================================================================

/-- Pi `commandTransport` (`"argv" | "stdin"`); `none` ≈ argv. -/
inductive CommandTransport where
  | argv
  | stdin
deriving BEq, Repr, Inhabited

/-- Pi `ShellConfig`. -/
structure ShellConfig where
  shell : String
  args : Array String
  commandTransport : Option CommandTransport := none
deriving Repr, Inhabited

-- ===========================================================================
-- ShellDeps (injectable for tests)
-- ===========================================================================

/--
Injectable shell-resolution dependencies. Tests simulate win32/unix without
spawning real processes; `defaultShellDeps` wires the real IO.
-/
structure ShellDeps where
  isWindows : Bool
  getEnv : String → IO (Option String)
  existsSync : String → IO Bool
  /-- Run `cmd args`, return the first trimmed stdout line on exit 0, else none. -/
  spawnSync : String → Array String → IO (Option String)

/-- Real IO shell deps (defers to `IO.getEnv`, `FilePath.pathExists`, `IO.Process`). -/
def defaultShellDeps : ShellDeps :=
  { isWindows := Platform.isWindows
    getEnv := fun k => IO.getEnv k
    existsSync := fun p => (FilePath.mk p).pathExists
    spawnSync := fun cmd args => do
      try
        let child ← IO.Process.spawn
          { cmd := cmd, args := args, stdin := .null, stdout := .piped, stderr := .null }
        let code ← child.wait
        if code != 0 then pure none
        else
          let out ← child.stdout.readToEnd
          let trimmed := out.trimAscii.toString
          let lines := trimmed.splitOn "\n"
          match lines with
          | [] => pure none
          | first :: _ =>
              let f := first.dropRightWhile (· == '\r')
              pure (if f.isEmpty then none else some f)
      catch _ => pure none }

-- ===========================================================================
-- Pure bash-path helpers
-- ===========================================================================

/--
Pi `isLegacyWslBashPath`: matches `c:\windows\system32\bash.exe` or
`c:\windows\sysnative\bash.exe` (forward slashes normalized to backslashes,
case-insensitive drive letter + path). Legacy WSL bash must run via `-s` /
`stdin` transport.
-/
def isLegacyWslBashPath (path : String) : Bool :=
  let normalized := (path.map fun c => if c == '/' then '\\' else c).toLower
  let parts := normalized.splitOn "\\"
  match parts with
  | drive :: "windows" :: sub :: "bash.exe" :: [] =>
      let d := drive.toList
      d.length == 2 &&
      d.head!.isAlpha &&
      d.tail!.head? == some ':' &&
      (sub == "system32" || sub == "sysnative")
  | _ => false

/-- Pi `getBashShellConfig`: legacy WSL bash uses `-s` + stdin; otherwise `-c`. -/
def getBashShellConfig (shell : String) : ShellConfig :=
  if isLegacyWslBashPath shell then
    { shell, args := #["-s"], commandTransport := some .stdin }
  else
    { shell, args := #["-c"], commandTransport := none }

-- ===========================================================================
-- findBashOnPath
-- ===========================================================================

/--
Pi `findBashOnPath`: probe `where bash.exe` (Windows, verifying the result
exists) or `which bash` (Unix, trusting the output). Returns the first match or
none. Errors are swallowed.
-/
def findBashOnPath (deps : ShellDeps) : IO (Option String) := do
  if deps.isWindows then
    match ← deps.spawnSync "where" #["bash.exe"] with
    | some first => if ← deps.existsSync first then pure (some first) else pure none
    | none => pure none
  else
    match ← deps.spawnSync "which" #["bash"] with
    | some first => pure (if first.isEmpty then none else some first)
    | none => pure none

-- ===========================================================================
-- getShellConfig
-- ===========================================================================

/--
Pi `getShellConfig`: resolve the shell config from `customShellPath` (must
exist), Windows Git Bash locations, PATH search, or Unix `/bin/bash` → PATH →
`sh` fallback. Throws on Windows when no bash is found.
-/
def getShellConfig (deps : ShellDeps) (customShellPath : Option String := none) : IO ShellConfig := do
  match customShellPath with
  | some p =>
      if ← deps.existsSync p then pure (getBashShellConfig p)
      else throw <| IO.userError s!"Custom shell path not found: {p}"
  | none =>
      if deps.isWindows then do
        let mut candidates : Array String := #[]
        match ← deps.getEnv "ProgramFiles" with
        | some pf => candidates := candidates.push s!"{pf}\\Git\\bin\\bash.exe"
        | none => pure ()
        match ← deps.getEnv "ProgramFiles(x86)" with
        | some pf => candidates := candidates.push s!"{pf}\\Git\\bin\\bash.exe"
        | none => pure ()
        let mut found : Option ShellConfig := none
        for c in candidates do
          if found.isNone && (← deps.existsSync c) then
            found := some (getBashShellConfig c)
        match found with
        | some cfg => pure cfg
        | none =>
            match ← findBashOnPath deps with
            | some b => pure (getBashShellConfig b)
            | none =>
                throw <| IO.userError
                  ("No bash shell found. Options:\n" ++
                   "  1. Install Git for Windows: https://git-scm.com/download/win\n" ++
                   "  2. Add your bash to PATH (Cygwin, MSYS2, etc.)\n" ++
                   "  3. Set shellPath in settings.json\n")
      else
        if ← deps.existsSync "/bin/bash" then pure (getBashShellConfig "/bin/bash")
        else
          match ← findBashOnPath deps with
          | some b => pure (getBashShellConfig b)
          | none => pure { shell := "sh", args := #["-c"], commandTransport := none }

/-- `getShellConfig` over the real IO deps. -/
def getShellConfigIO (customShellPath : Option String := none) : IO ShellConfig :=
  getShellConfig defaultShellDeps customShellPath

-- ===========================================================================
-- getShellEnv
-- ===========================================================================

/-- PATH-list delimiter (`;` on Windows, `:` on Unix). -/
def pathDelimiter (isWindows : Bool) : Char := if isWindows then ';' else ':'

/--
Find the env key matching `path` case-insensitively (Windows has `Path`,
Unix `PATH`). Returns the existing key or `"PATH"`.
-/
def findPathKey (getEnv : String → IO (Option String)) (isWindows : Bool) : IO String := do
  let candidates := if isWindows then #["PATH", "Path", "path"] else #["PATH"]
  let mut found := "PATH"
  for k in candidates do
    if found == "PATH" then
      match ← getEnv k with
      | some _ => found := k
      | none => pure ()
  pure found

/--
Pi `getShellEnv`: augment PATH with `binDir` (if not already present) and
return `(pathKey, augmentedPathValue)`. Pi spreads `...process.env` and
overrides the PATH entry; the Lean port returns the updated PATH pair so the
caller merges it into its spawn env.
-/
def getShellEnv (deps : ShellDeps) (binDir : String) : IO (String × String) := do
  let pathKey ← findPathKey deps.getEnv deps.isWindows
  let current ← match ← deps.getEnv pathKey with
    | some v => pure v
    | none => pure ""
  let sep := pathDelimiter deps.isWindows
  let entries := current.split sep |>.toList.filter (·.isEmpty == false)
  let hasBinDir := entries.contains binDir
  let updated :=
    if hasBinDir || current.isEmpty then
      if current.isEmpty then binDir else current
    else
      s!"{binDir}{sep}{current}"
  pure (pathKey, updated)

/-- `getShellEnv` over the real IO deps + `Config.getBinDir`. -/
def getShellEnvIO (binDirOverride : Option String := none) : IO (String × String) := do
  let binDir := (← LeanAgent.CodingAgent.Config.getBinDir binDirOverride).toString
  getShellEnv defaultShellDeps binDir

-- ===========================================================================
-- Process-tree killing (best-effort)
-- ===========================================================================

/--
Pi `killProcessTree`: kill `pid` and all its children.
- Windows: `taskkill /F /T /PID <pid>`.
- Unix: `kill -9 -<pid>` (signal the process group); falls back to
  `kill -9 <pid>`. Errors swallowed.
-/
def killProcessTree (pid : Nat) : IO Unit := do
  if Platform.isWindows then
    try
      let _ ← IO.Process.spawn
        { cmd := "taskkill", args := #["/F", "/T", "/PID", toString pid]
          stdin := .null, stdout := .null, stderr := .null, setsid := true }
    catch _ => pure ()
  else
    let ok : Bool ← try
        let child ← IO.Process.spawn
          { cmd := "kill", args := #["-9", s!"-{pid}"]
            stdin := .null, stdout := .null, stderr := .null }
        let code ← child.wait
        pure (code == 0)
      catch _ => pure false
    if !ok then
      try
        let child ← IO.Process.spawn
          { cmd := "kill", args := #["-9", toString pid]
            stdin := .null, stdout := .null, stderr := .null }
        let _ ← child.wait
      catch _ => pure ()

-- ===========================================================================
-- Tracked detached children (best-effort)
-- ===========================================================================

/-- Process-local set of tracked detached child pids. -/
initialize trackedPids : IO.Ref (Std.HashSet Nat) ← IO.mkRef {}

/-- Pi `trackDetachedChildPid`. -/
def trackDetachedChildPid (pid : Nat) : IO Unit :=
  trackedPids.modify fun s => s.insert pid

/-- Pi `untrackDetachedChildPid`. -/
def untrackDetachedChildPid (pid : Nat) : IO Unit :=
  trackedPids.modify fun s => s.erase pid

/--
Pi `killTrackedDetachedChildren`: kill all tracked detached children on parent
shutdown. Errors swallowed per child.
-/
def killTrackedDetachedChildren : IO Unit := do
  let pids ← trackedPids.get
  for pid in pids.toList do
    killProcessTree pid
  trackedPids.set {}

-- ===========================================================================
-- sanitizeBinaryOutput (re-export from Harness.Truncate)
-- ===========================================================================

/-- Alias of `Agent.Harness.Truncate.sanitizeBinaryOutput` (already ported). -/
def sanitizeBinaryOutput (str : String) : String :=
  LeanAgent.Agent.Harness.Truncate.sanitizeBinaryOutput str

end LeanAgent.CodingAgent.Utils.Shell