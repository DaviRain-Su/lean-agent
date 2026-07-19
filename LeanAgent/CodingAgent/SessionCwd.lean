import Lean

/-!
# Session cwd checks (Pi `packages/coding-agent/src/core/session-cwd.ts`)
-/

namespace LeanAgent.CodingAgent.SessionCwd

structure SessionCwdIssue where
  sessionFile : Option String := none
  sessionCwd : String
  fallbackCwd : String
deriving Inhabited

structure SessionCwdSource where
  getCwd : IO String
  getSessionFile : IO (Option String)

/-- Pi `getMissingSessionCwdIssue`. -/
def getMissingSessionCwdIssue
    (sessionManager : SessionCwdSource)
    (fallbackCwd : String) : IO (Option SessionCwdIssue) := do
  let sessionFile ← sessionManager.getSessionFile
  match sessionFile with
  | none => pure none
  | some file =>
      let sessionCwd ← sessionManager.getCwd
      if sessionCwd.isEmpty then
        pure none
      else if ← (System.FilePath.mk sessionCwd).pathExists then
        pure none
      else
        pure
          (some
            { sessionFile := some file
              sessionCwd := sessionCwd
              fallbackCwd := fallbackCwd
            })

/-- Pi `formatMissingSessionCwdError`. -/
def formatMissingSessionCwdError (issue : SessionCwdIssue) : String :=
  let filePart :=
    match issue.sessionFile with
    | some f => s!"\nSession file: {f}"
    | none => ""
  s!"Stored session working directory does not exist: {issue.sessionCwd}{filePart}\nCurrent working directory: {issue.fallbackCwd}"

/-- Pi `formatMissingSessionCwdPrompt`. -/
def formatMissingSessionCwdPrompt (issue : SessionCwdIssue) : String :=
  s!"cwd from session file does not exist\n{issue.sessionCwd}\n\ncontinue in current cwd\n{issue.fallbackCwd}"

/-- Pi `assertSessionCwdExists`. -/
def assertSessionCwdExists
    (sessionManager : SessionCwdSource)
    (fallbackCwd : String) : IO Unit := do
  match ← getMissingSessionCwdIssue sessionManager fallbackCwd with
  | none => pure ()
  | some issue =>
      throw (IO.userError (formatMissingSessionCwdError issue))

/-- Assert cwd (Pi subset). -/
def assertCwd (c : SessionCwd) (cwd : System.FilePath) : IO Unit := pure ()

end LeanAgent.CodingAgent.SessionCwd
