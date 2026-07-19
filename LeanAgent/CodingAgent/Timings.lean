import Lean

/-!
# Startup timing instrumentation (Pi `packages/coding-agent/src/core/timings.ts`)

Central profiler gated on `PI_TIMING=1`. `time(label, namespace)` records the
delta since the previous `time`/`reset` in that namespace. `now` is passed
explicitly so offline tests drive deterministic clocks; production callers pass
`IO.monoMsNow`.

`printTimings` returns the formatted report string (Pi writes to `stderr`);
callers print it. Entries with negative deltas are filtered (Pi parity).
-/

namespace LeanAgent.CodingAgent.Timings

/-- Pi `PI_TIMING` env var name. -/
def timingEnvVar : String := "PI_TIMING"

/-- Pi `ENABLED`: `PI_TIMING=1`. -/
def timingEnabled : IO Bool := do
  match ← IO.getEnv timingEnvVar with
  | some "1" => pure true
  | _ => pure false

/-- Pi timing entry. -/
structure TimingEntry where
  label : String
  ms : Int
deriving Inhabited, Repr

/-- Per-namespace accumulator. -/
structure TimingNamespace where
  timings : Array TimingEntry := #[]
  lastTime : Nat := 0
deriving Inhabited

/-- Mutable timing registry (namespace name → state). -/
structure TimingRegistry where
  enabled : Bool
  state : IO.Ref (Std.HashMap String TimingNamespace)

/-- Create a registry; `enabled` is caller-resolved (Pi reads `PI_TIMING` once). -/
def createTimingRegistry (enabled : Bool) : IO TimingRegistry := do
  pure { enabled := enabled, state := ← IO.mkRef {} }

/-- Convenience: create gated on `PI_TIMING=1`. -/
def createDefaultTimingRegistry : IO TimingRegistry := do
  createTimingRegistry (← timingEnabled)

/-- Pi `resetTimings`: clear a namespace and stamp its `lastTime` to `now`. -/
def resetTimings (reg : TimingRegistry) (now : Nat) (nsName : String := "main") : IO Unit :=
  if !reg.enabled then pure ()
  else reg.state.modify (fun m => m.insert nsName { timings := #[], lastTime := now })

/-- Pi `time`: record the delta since the last `time`/`reset` in `namespace`.
Creates the namespace (stamped at `now`) if absent. -/
def time (reg : TimingRegistry) (label : String) (now : Nat) (nsName : String := "main") :
    IO Unit := do
  if !reg.enabled then pure ()
  else
    reg.state.modify fun m =>
      let ns := m.getD nsName { timings := #[], lastTime := now }
      let entry : TimingEntry := { label := label, ms := Int.ofNat now - Int.ofNat ns.lastTime }
      m.insert nsName { ns with timings := ns.timings.push entry, lastTime := now }

/-- Pi filter: drop entries with negative deltas. -/
def printableTimings (timings : Array TimingEntry) : Array TimingEntry :=
  timings.filter (fun t => t.ms ≥ 0)

/-- Format a single timing group (Pi `printTimingGroup`); "" if empty. -/
def formatTimingGroup (title : String) (timings : Array TimingEntry) : String :=
  let printable := printableTimings timings
  if printable.isEmpty then ""
  else
    let total := printable.foldl (fun acc t => acc + t.ms) 0
    let lines := printable.map (fun t => s!"  {t.label}: {t.ms}ms")
    let body := String.intercalate "\n" lines.toList
    let rule := String.mk (List.replicate (title.length + 8) '-')
    s!"\n--- {title} ---\n{body}\n  TOTAL: {total}ms\n{rule}\n"

/-- Pi `printTimings`: render all namespaces. Returns the report string (Pi
prints to stderr; caller decides output). -/
def printTimings (reg : TimingRegistry) : IO String := do
  if !reg.enabled then pure ""
  else
    let m ← reg.state.get
    let groups := m.toArray.map fun (ns, state) =>
      formatTimingGroup (s!"Startup Timings: {ns}") state.timings
    pure (String.intercalate "" groups.toList)

end LeanAgent.CodingAgent.Timings
