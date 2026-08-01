import Lean

/-!
# Kill ring for Emacs-style kill/yank operations

Port of Pi `packages/tui/src/kill-ring.ts`.
-/

namespace LeanAgent.Tui.KillRing

/-- Ring buffer for kill/yank, backed by IO.Ref (Pi `KillRing`). -/
structure KillRing where
  ringRef : IO.Ref (Array String)

/-- Create an empty kill ring. -/
def create : IO KillRing := do
  pure { ringRef := ← IO.mkRef #[] }

/-- Add text to the kill ring (Pi `push`). -/
def push (kr : KillRing) (text : String) (prepend : Bool) (accumulate : Bool := false) : IO Unit := do
  if text.isEmpty then return
  let ring ← kr.ringRef.get
  if accumulate && ring.size > 0 then
    let last := ring[ring.size - 1]!
    let merged := if prepend then text ++ last else last ++ text
    kr.ringRef.set (ring.set! (ring.size - 1) merged)
  else
    kr.ringRef.set (ring.push text)

/-- Get most recent entry without modifying the ring (Pi `peek`). -/
def peek (kr : KillRing) : IO (Option String) := do
  let ring ← kr.ringRef.get
  pure (ring.back?)

/-- Move last entry to front (for yank-pop cycling, Pi `rotate`). -/
def rotate (kr : KillRing) : IO Unit := do
  let ring ← kr.ringRef.get
  if ring.size > 1 then
    let last := ring[ring.size - 1]!
    let front := ring.take (ring.size - 1)
    kr.ringRef.set (#[last] ++ front)
  else
    pure ()

/-- Current ring size. -/
def length (kr : KillRing) : IO Nat := do
  let ring ← kr.ringRef.get
  pure ring.size

end LeanAgent.Tui.KillRing