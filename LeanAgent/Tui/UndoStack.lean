import Lean

/-!
# Generic undo stack with clone-on-push semantics

Port of Pi `packages/tui/src/undo-stack.ts`.
-/

namespace LeanAgent.Tui.UndoStack

/-- Generic undo stack backed by IO.Ref (Pi `UndoStack<S>`). -/
structure UndoStack (α : Type) where
  stackRef : IO.Ref (Array α)

/-- Create an empty undo stack. -/
def create (α : Type) : IO (UndoStack α) := do
  pure { stackRef := ← IO.mkRef #[] }

/-- Push a copy of the given state onto the stack (Pi `push`). -/
def push {α : Type} (us : UndoStack α) (state : α) : IO Unit := do
  us.stackRef.modify (·.push state)

/-- Pop and return the most recent snapshot, or none if empty (Pi `pop`). -/
def pop {α : Type} (us : UndoStack α) : IO (Option α) := do
  let stack ← us.stackRef.get
  match stack.back? with
  | some last =>
    us.stackRef.set (stack.take (stack.size - 1))
    pure (some last)
  | none => pure none

/-- Remove all snapshots (Pi `clear`). -/
def clear {α : Type} (us : UndoStack α) : IO Unit :=
  us.stackRef.set #[]

/-- Current stack size. -/
def length {α : Type} (us : UndoStack α) : IO Nat := do
  let stack ← us.stackRef.get
  pure stack.size

end LeanAgent.Tui.UndoStack