import Lean

/-!
# Windows self-update (Pi `utils/windows-self-update.ts`)

Windows-specific native-dependency quarantine for self-updating. Pi
quarantines loaded `.node` shared objects before replacing them so a
running process does not hold a write lock on its own native addons.

This module is an **Exclusion** (Exclusion List §7-adjacent):
- `process.report.getReport().sharedObjects` is a Node/V8 internal —
  no Lean equivalent.
- `toNamespacedPath` / `renameSync` quarantine dance is Windows-specific.
- The quarantine mechanism only matters for `bun build --compile`
  executables on Windows.

On non-Windows platforms, all functions are no-ops. On Windows, they
are documented stubs — the quarantine logic requires Node process
internals not available in Lean.
-/

namespace LeanAgent.CodingAgent.Utils.WindowsSelfUpdate

/-- Quarantine directory name (Pi `QUARANTINE_DIR_NAME`). -/
def QUARANTINE_DIR_NAME : String := ".pi-native-quarantine"

/--
Pi `checkForSelfUpdate`: check whether a self-update is needed.

Returns `none` on all platforms. On Windows, the update check requires
`process.versions` introspection and Bun-specific update APIs not
available in Lean (Exclusion-adjacent).
-/
def checkForSelfUpdate : IO (Option String) := do
  pure none

/--
Pi `performSelfUpdate`: perform a self-update.

No-op on all platforms. On Windows, the update mechanism requires
replacing the running executable and quarantining native dependencies,
which needs Node process internals (Exclusion-adjacent).
-/
def performSelfUpdate : IO Unit := do
  pure ()

/--
Pi `cleanupWindowsSelfUpdateQuarantine`: remove the quarantine directory.

No-op on all platforms. On Windows, requires Node `fs.rmSync` recursive
(Exclusion-adjacent).
-/
def cleanupWindowsSelfUpdateQuarantine (packageDir : String) : IO Unit := do
  pure ()

/--
Pi `quarantineWindowsNativeDependencies`: quarantine loaded `.node`
shared objects before self-update.

No-op on all platforms. On Windows, requires
`process.report.getReport().sharedObjects` (Node V8 internal —
Exclusion-adjacent).
-/
def quarantineWindowsNativeDependencies (packageDir : String) : IO Unit := do
  pure ()

end LeanAgent.CodingAgent.Utils.WindowsSelfUpdate