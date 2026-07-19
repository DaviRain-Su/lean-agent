import Lean

/-!
# Experimental features flag (Pi `experimental.ts`)
-/

namespace LeanAgent.CodingAgent.Experimental

/-- Pi `areExperimentalFeaturesEnabled` (`PI_EXPERIMENTAL=1`). -/
def areExperimentalFeaturesEnabled : IO Bool := do
  match ← IO.getEnv "PI_EXPERIMENTAL" with
  | some "1" => pure true
  | _ => pure false

end LeanAgent.CodingAgent.Experimental
