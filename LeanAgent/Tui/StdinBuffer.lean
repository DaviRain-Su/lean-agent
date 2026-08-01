import Lean

/-!
# Stdin buffer for terminal input

Port of Pi `packages/tui/src/stdin-buffer.ts` — offline-testable subset.
-/

namespace LeanAgent.Tui.StdinBuffer

/-- Stdin buffer backed by IO.Ref (Pi `StdinBuffer`). -/
structure StdinBuffer where
  bufRef : IO.Ref String
  posRef : IO.Ref Nat

/-- Create an empty stdin buffer. -/
def create : IO StdinBuffer := do
  pure { bufRef := ← IO.mkRef "", posRef := ← IO.mkRef 0 }

/-- Append a character to the buffer. -/
def pushChar (sb : StdinBuffer) (c : Char) : IO Unit :=
  sb.bufRef.modify (·.push c)

/-- Remove and return the last character, or none if empty. -/
def popChar (sb : StdinBuffer) : IO (Option Char) := do
  let buf ← sb.bufRef.get
  match buf.toList.getLast? with
  | some last =>
    let front := String.ofList (buf.toList.take (buf.toList.length - 1))
    sb.bufRef.set front
    pure (some last)
  | none => pure none

/-- Return the last character without removing, or none if empty. -/
def peekChar (sb : StdinBuffer) : IO (Option Char) := do
  let buf ← sb.bufRef.get
  pure (buf.toList.getLast?)

/-- Reset buffer to empty. -/
def clear (sb : StdinBuffer) : IO Unit := do
  sb.bufRef.set ""
  sb.posRef.set 0

/-- Get current buffer contents. -/
def toString (sb : StdinBuffer) : IO String :=
  sb.bufRef.get

/-- Current buffer length. -/
def length (sb : StdinBuffer) : IO Nat := do
  let buf ← sb.bufRef.get
  pure buf.length

/-- Check if a byte represents a control character (0x00-0x1F, 0x7F). -/
def isControlByte (b : UInt8) : Bool :=
  b < 32 || b == 127

/-- Check if a byte is a UTF-8 continuation byte (10xxxxxx). -/
def isContinuationByte (b : UInt8) : Bool :=
  b &&& 0xC0 == 0x80

/--
Process a raw byte: filter control characters and handle UTF-8.
Control bytes (except CR/LF/Tab) are dropped.
-/
def processByte (sb : StdinBuffer) (b : UInt8) : IO (Option Char) := do
  if isControlByte b && b != 13 && b != 10 && b != 9 then
    pure none
  else if b < 128 then
    let c := Char.ofNat b.toNat
    pushChar sb c
    pure (some c)
  else
    -- Multi-byte UTF-8: simplified — treat each high byte as a char
    let c := Char.ofNat b.toNat
    pushChar sb c
    pure (some c)

end LeanAgent.Tui.StdinBuffer