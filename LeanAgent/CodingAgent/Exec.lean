import Lean
import LeanAgent.CodingAgent.Config

/-!
# Shared command execution (Pi `packages/coding-agent/src/core/exec.ts`)

Execute a command (no shell) and return `{ stdout, stderr, code, killed }`,
with optional timeout. Used by extensions and custom tools.

Pi's JS `AbortSignal` cancellation has no direct Lean IO equivalent; the port
supports timeout-driven kill (`killed = true`) plus an optional cooperative
`cancel` ref (`IO.Ref Bool`). Polling-based; not true preemptive cancellation.
-/

namespace LeanAgent.CodingAgent.Exec

/-- Pi `ExecResult`. -/
structure ExecResult where
  stdout : String := ""
  stderr : String := ""
  code : UInt32 := 0
  killed : Bool := false
deriving Inhabited, Repr

/-- Pi `ExecOptions` (timeout in milliseconds; cwd passed separately). -/
structure ExecOptions where
  timeoutMs : Option Nat := none
  cancel : Option (IO.Ref Bool) := none

/-- Default poll interval (ms) for the timeout wait loop. -/
def pollIntervalMs : UInt32 := 100

/--
Pi `execCommand`: run `command` with `args` in `cwd`, capturing stdout/stderr.

On timeout (or a set `cancel` ref) the child is killed and `killed = true`.
The wait loop polls every `pollIntervalMs`; `partial` because it recurses on an
`IO`-driven loop bounded by the timeout budget (or until the child exits).
-/
partial def execCommand
    (command : String) (args : Array String) (cwd : System.FilePath)
    (options : ExecOptions := {}) : IO ExecResult := do
  let child ← IO.Process.spawn
    { cmd := command
      args := args
      cwd := some cwd
      stdin := .null
      stdout := .piped
      stderr := .piped }
  let maxTicks := options.timeoutMs.map (fun ms => ms / pollIntervalMs.toNat + 1)
  let rec waitLoop (ticks : Nat) : IO (Option UInt32) := do
    match ← child.tryWait with
    | some code => pure (some code)
    | none =>
        let cancelledNow ←
          match options.cancel with
          | some ref => ref.get
          | none => pure false
        if cancelledNow then pure none
        else
          let timedOut : Bool :=
            match maxTicks with
            | some n => decide (ticks ≥ n)
            | none => false
          if timedOut then pure none
          else do
            IO.sleep pollIntervalMs
            waitLoop (ticks + 1)
  let result? ← waitLoop 0
  let (code, killed) ←
    match result? with
    | some code => pure (code, false)
    | none =>
        try child.kill catch _ => pure ()
        let code ← child.wait
        pure (code, true)
  let stdout ← child.stdout.readToEnd
  let stderr ← child.stderr.readToEnd
  pure { stdout := stdout, stderr := stderr, code := code, killed := killed }

end LeanAgent.CodingAgent.Exec
