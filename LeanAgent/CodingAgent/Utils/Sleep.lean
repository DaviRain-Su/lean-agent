import Lean
import LeanAgent.AI.Util.Abort

/-!
# Abort-aware sleep (Pi `utils/sleep.ts`)
-/

namespace LeanAgent.CodingAgent.Utils.Sleep

open LeanAgent.AI.Util.Abort

/-- Pi `sleep(ms, signal?)`. -/
def sleep (ms : Nat) (signal : Option AbortSignal := none) : IO Unit := do
  if ← isAborted signal then
    throw (IO.userError "Aborted")
  -- Poll abort while sleeping in small steps.
  let mut remaining := ms
  while remaining > 0 do
    if ← isAborted signal then
      throw (IO.userError "Aborted")
    let step := min remaining 20
    IO.sleep (UInt32.ofNat step)
    remaining := remaining - step

end LeanAgent.CodingAgent.Utils.Sleep
