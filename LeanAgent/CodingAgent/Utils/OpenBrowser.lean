import Lean

/-!
# Open URL in browser (Pi `packages/coding-agent/src/utils/open-browser.ts`)

`openBrowser` launches the platform default handler for a URL or file. It
intentionally never invokes a shell: on Windows it avoids `cmd /c start`
(cmd.exe would re-parse metacharacters before `start` runs and make
attacker-controlled URLs injectable). Launch is best-effort — launcher errors
are swallowed (callers still present the target to the user).
-/

namespace LeanAgent.CodingAgent.Utils.OpenBrowser

/-- Select the launcher command + args for a target on the current platform.
Returns `(cmd, args)`. Exposed for offline tests. -/
def launcherFor (target : String) : String × Array String :=
  let t := System.Platform.target
  if t.startsWith "x86_64-apple-darwin" || t.startsWith "aarch64-apple-darwin" then
    ("open", #[target])
  else if t.startsWith "x86_64-pc-windows" || t.startsWith "aarch64-pc-windows" then
    ("rundll32", #["url.dll,FileProtocolHandler", target])
  else
    ("xdg-open", #[target])

/--
Pi `openBrowser`: spawn the platform launcher detached with ignored stdio.
Best-effort — spawn errors are caught and discarded so a missing launcher
(e.g. no `xdg-open`) never crashes the process.
-/
def openBrowser (target : String) : IO Unit := do
  let (cmd, args) := launcherFor target
  try
    let _child ← IO.Process.spawn
      { cmd := cmd
        args := args
        stdin := .null
        stdout := .null
        stderr := .null }
    -- Detached: do not wait. Lean does not expose `unref`; the child is fire-and-forget.
    pure ()
  catch _ =>
    -- Swallow launcher errors (best-effort, matching Pi's `.on("error", () => {})`).
    pure ()

end LeanAgent.CodingAgent.Utils.OpenBrowser
