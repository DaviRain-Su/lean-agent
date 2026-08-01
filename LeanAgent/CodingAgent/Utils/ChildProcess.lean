import Lean

/-!
# Child-process helpers (Pi `utils/child-process.ts`)

Wraps `IO.Process` to mirror Pi's `spawnProcess` / `spawnProcessSync` /
`waitForChildProcess`.

Pi uses Node's `child_process` module plus `cross-spawn` for Windows path
resolution. Lean's `IO.Process` already handles PATH resolution on all
platforms, so `cross-spawn` is unnecessary.

`waitForChildProcess` in Pi listens for `exit` / `close` / stream `end` /
`data` events to avoid truncating output from detached descendants that
inherit the stdio pipes. Lean's `IO.Process.Child` has a simpler model:
`wait` blocks until the process exits and then reads can drain the pipes.
The grace-period concept (EXIT_STDIO_GRACE_MS) is preserved as a constant
and applied as a post-exit sleep before final stream reads, so any
last-moment output has time to arrive.
-/

namespace LeanAgent.CodingAgent.Utils.ChildProcess

open System

/-- Grace period (ms) after process exit before finalizing stdio reads. -/
def EXIT_STDIO_GRACE_MS : Nat := 100

/-- Pi `SpawnSyncReturns<string>` — result of a synchronous spawn. -/
structure ChildProcessResult where
  exitCode : UInt32 := 0
  stdout : String := ""
  stderr : String := ""
deriving Inhabited, Repr

/-- Options for `spawnProcessSync` (mirrors Pi `SpawnSyncOptionsWithStringEncoding`). -/
structure SpawnSyncOptions where
  cwd : Option FilePath := none
  encoding : String := "utf8"
  timeoutMs : Option Nat := none
deriving Inhabited

/--
Pi `spawnProcess`: spawn a child process with piped stdout/stderr.
Returns the child handle so the caller can read streams incrementally or
call `waitForChildProcess`.
-/
def spawnProcess (command : String) (args : Array String)
    (cwd : Option FilePath := none) :=
  IO.Process.spawn
    { cmd := command
      args := args
      cwd := cwd
      stdin := .null
      stdout := .piped
      stderr := .piped }

/-- Poll loop helper for `spawnProcessSync`. -/
partial def waitWithTimeout {cfg : IO.Process.StdioConfig}
    (child : IO.Process.Child cfg) (maxTicks : Option Nat) (ticks : Nat)
    : IO (Option UInt32) := do
  match ← child.tryWait with
  | some code => pure (some code)
  | none =>
    let timedOut : Bool :=
      match maxTicks with
      | some n => decide (ticks ≥ n)
      | none => false
    if timedOut then pure none
    else do
      IO.sleep 100
      waitWithTimeout child maxTicks (ticks + 1)

/--
Pi `spawnProcessSync`: synchronously run a command and return captured
stdout/stderr/exitCode. If `timeoutMs` is set and exceeded, the child is
killed and the partial output is returned with whatever code `wait` yields.
-/
def spawnProcessSync (command : String) (args : Array String)
    (opts : SpawnSyncOptions := {}) : IO ChildProcessResult := do
  let child ← IO.Process.spawn
    { cmd := command
      args := args
      cwd := opts.cwd
      stdin := .null
      stdout := .piped
      stderr := .piped }
  let maxTicks := opts.timeoutMs.map (fun ms => ms / 100 + 1)
  let code ← match ← waitWithTimeout child maxTicks 0 with
    | some c => pure c
    | none =>
        try child.kill catch _ => pure ()
        child.wait
  let stdout ← child.stdout.readToEnd
  let stderr ← child.stderr.readToEnd
  pure { exitCode := code, stdout := stdout, stderr := stderr }

/--
Pi `waitForChildProcess`: wait for a child process to exit.

In Pi this is an event-driven dance: after `exit`, it re-arms an idle timer
on every `data` chunk so an actively writing detached descendant keeps us
reading, while a quiet inherited handle releases us after
`EXIT_STDIO_GRACE_MS`. Lean's `IO.Process.Child` does not expose per-chunk
stream callbacks, so we approximate: call `wait` for the exit code, then
sleep `EXIT_STDIO_GRACE_MS` to allow any inherited stdio to drain. Returns
the exit code.
-/
def waitForChildProcess {cfg : IO.Process.StdioConfig}
    (child : IO.Process.Child cfg) : IO UInt32 := do
  let code ← child.wait
  -- Grace period: allow detached descendants to finish writing.
  IO.sleep (UInt32.ofNat EXIT_STDIO_GRACE_MS)
  pure code

end LeanAgent.CodingAgent.Utils.ChildProcess