import Lean

/-!
# Deprecation warnings (Pi `utils/deprecation.ts`)
-/

namespace LeanAgent.CodingAgent.Utils.Deprecation

/-- Process-local set of already-emitted deprecation messages. -/
structure DeprecationState where
  seenRef : IO.Ref (Std.HashSet String)

def createState : IO DeprecationState := do
  pure { seenRef := ← IO.mkRef {} }

/-- Pi `warnDeprecation` — emit once per unique message. -/
def warnDeprecation (state : DeprecationState) (message : String) : IO Unit := do
  let seen ← state.seenRef.get
  if seen.contains message then
    pure ()
  else
    state.seenRef.modify fun s => s.insert message
    IO.eprintln s!"Deprecation warning: {message}"

/-- Pi `clearDeprecationWarningsForTests`. -/
def clearDeprecationWarnings (state : DeprecationState) : IO Unit :=
  state.seenRef.set {}

end LeanAgent.CodingAgent.Utils.Deprecation
