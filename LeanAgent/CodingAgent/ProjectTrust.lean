import Lean
import LeanAgent.CodingAgent.Config
import LeanAgent.CodingAgent.TrustManager

/-!
# Project trust resolution (Pi `packages/coding-agent/src/core/project-trust.ts`)

Resolves whether a project directory is trusted. Priority:
1. Explicit `trustOverride` flag
2. No trust-requiring resources → trusted
3. Extension `project_trust` event (stubbed; extensions not yet ported)
4. Saved trust decision in `ProjectTrustStore`
5. `defaultProjectTrust` setting (`always` / `never` / `ask`)
6. UI prompt (injectable via `ProjectTrustContext`)

The `AppMode` type and `ProjectTrustContext` UI interface are modeled as
injectable records so offline tests can drive resolution without a TUI.

Extensions integration (`emitProjectTrustEvent`) is deferred until the
extensions runner is ported (Exclusion List §7 adjacent — no Node event
loop in Lean).
-/

namespace LeanAgent.CodingAgent.ProjectTrust

open LeanAgent.CodingAgent.TrustManager

-- ============================================================================
-- Types
-- ============================================================================

/-- Pi `AppMode`. -/
inductive AppMode where
  | interactive
  | print
  | json
  | rpc
deriving Inhabited, BEq

/-- Pi `DefaultProjectTrust` setting. -/
inductive DefaultProjectTrust where
  | always
  | never
  | ask
deriving Inhabited, BEq

/-- Pi `ProjectTrustContext`: injectable UI for trust prompts.
Offline tests supply a mock; the real TUI supplies `select`. -/
structure ProjectTrustContext where
  hasUI : Bool
  /-- Present a trust prompt and return the selected option label, or none if cancelled. -/
  select : String → Array String → IO (Option String) := fun _ _ => pure none
deriving Inhabited

/-- Pi `LoadExtensionsResult` stub (extensions not yet ported). -/
structure LoadExtensionsResult where
  extensions : Array Unit := #[]
deriving Inhabited

/-- Pi `ResolveProjectTrustedOptions`. -/
structure ResolveProjectTrustedOptions where
  cwd : String
  trustStore : ProjectTrustStore
  trustOverride : Option Bool := none
  defaultProjectTrust : DefaultProjectTrust := .ask
  extensionsResult : Option LoadExtensionsResult := none
  projectTrustContext : ProjectTrustContext
  onExtensionError : String → IO Unit := fun _ => pure ()
deriving Inhabited

-- ============================================================================
-- Helpers
-- ============================================================================

/-- Pi `formatProjectTrustPrompt`. -/
def formatProjectTrustPrompt (cwd : String) : String :=
  s!"Trust project folder?\n{cwd}\n\nThis allows pi to load {Config.configDirName} settings and resources, install missing project packages, and execute project extensions."

/-- Pi `selectProjectTrustOption`: present options via the context UI. -/
def selectProjectTrustOption (cwd : String) (ctx : ProjectTrustContext) :
    IO (Option ProjectTrustOption) := do
  let options ← getProjectTrustOptions cwd true
  let labels := options.map (·.label)
  match ← ctx.select (formatProjectTrustPrompt cwd) labels with
  | none => pure none
  | some selected =>
      pure (options.find? (fun o => o.label == selected))

/-- Pi `saveProjectTrustPromptResult`. -/
def saveProjectTrustPromptResult (trustStore : ProjectTrustStore) (result : ProjectTrustOption) :
    IO Unit := do
  if result.updates.size > 0 then
    trustStore.setMany result.updates

-- ============================================================================
-- resolveProjectTrusted
-- ============================================================================

/--
Pi `resolveProjectTrusted`: determine whether `cwd` is trusted.

Priority:
1. Explicit `trustOverride` → return it
2. No trust-requiring resources → trusted
3. Extension `project_trust` event → use extension result (stubbed)
4. Saved trust decision → use it
5. `defaultProjectTrust` = `always` → trusted
6. `defaultProjectTrust` = `never` → not trusted
7. `defaultProjectTrust` = `ask` → prompt user (if UI available)
-/
def resolveProjectTrusted (options : ResolveProjectTrustedOptions) : IO Bool := do
  -- 1. Explicit override.
  match options.trustOverride with
  | some b => return b
  | none => pure ()
  -- 2. No trust-requiring resources → trusted.
  if !(← hasTrustRequiringProjectResources options.cwd) then
    return true
  -- 3. Extension project_trust event (stubbed until extensions ported).
  if let some _extResult := options.extensionsResult then
    -- Pi: emitProjectTrustEvent(extensionsResult, ...) → result
    -- Stub: extensions not yet ported; skip.
    pure ()
  -- 4. Saved trust decision.
  match ← options.trustStore.get options.cwd with
  | some b => return b
  | none => pure ()
  -- 5-6. defaultProjectTrust setting.
  match options.defaultProjectTrust with
  | .always => return true
  | .never => return false
  | .ask => pure ()
  -- 7. UI prompt.
  if !options.projectTrustContext.hasUI then
    return false
  match ← selectProjectTrustOption options.cwd options.projectTrustContext with
  | some selected =>
      saveProjectTrustPromptResult options.trustStore selected
      return selected.trusted
  | none => return false

end LeanAgent.CodingAgent.ProjectTrust
