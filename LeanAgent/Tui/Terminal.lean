import Lean

/-!
# Terminal utilities

Port of Pi `packages/tui/src/terminal.ts` — offline-testable subset.

Provides terminal size detection, color support checks, and ANSI escape
code generators (pure String functions).
-/

namespace LeanAgent.Tui.Terminal

/-- Terminal dimensions (Pi `TerminalSize`). -/
structure TerminalSize where
  width : Nat
  height : Nat
deriving Repr, Inhabited, BEq

/-- Default terminal size fallback. -/
def defaultSize : TerminalSize := { width := 80, height := 24 }

/-- Check if running in a CI environment (heuristic for isatty). -/
def isTerminal : IO Bool := do
  let ci ← IO.getEnv "CI"
  pure (ci.isNone)

/-- Check TERM env for color support. -/
def supportsColor : IO Bool := do
  let noColor ← IO.getEnv "NO_COLOR"
  let term ← IO.getEnv "TERM"
  if noColor.isSome then pure false
  else match term with
    | some t => pure (t != "dumb")
    | none => pure true

/-- Get terminal size from COLUMNS/LINES env vars, fallback to 80x24. -/
def getTerminalSize : IO TerminalSize := do
  let cols ← IO.getEnv "COLUMNS"
  let lines ← IO.getEnv "LINES"
  let width := match cols with
    | some s => match s.toNat? with | some n => if n > 0 then n else 80 | none => 80
    | none => 80
  let height := match lines with
    | some s => match s.toNat? with | some n => if n > 0 then n else 24 | none => 24
    | none => 24
  pure { width, height }

-- ANSI escape code generators (pure String)

/-- Move cursor up n lines. -/
def cursorUp (n : Nat) : String := s!"\x1b[{n}A"
/-- Move cursor down n lines. -/
def cursorDown (n : Nat) : String := s!"\x1b[{n}B"
/-- Move cursor forward (right) n columns. -/
def cursorForward (n : Nat) : String := s!"\x1b[{n}C"
/-- Move cursor back (left) n columns. -/
def cursorBack (n : Nat) : String := s!"\x1b[{n}D"

/-- Clear the current line. -/
def clearLine : String := "\x1b[2K"
/-- Clear the entire screen. -/
def clearScreen : String := "\x1b[2J"

/-- Hide the cursor. -/
def hideCursor : String := "\x1b[?25l"
/-- Show the cursor. -/
def showCursor : String := "\x1b[?25h"

/-- Enter alternate screen buffer. -/
def enterAltScreen : String := "\x1b[?1049h"
/-- Exit alternate screen buffer. -/
def exitAltScreen : String := "\x1b[?1049l"

/-- Move cursor to a specific row/column (1-indexed). -/
def cursorTo (row : Nat) (col : Nat) : String := s!"\x1b[{row};{col}H"

/-- Save cursor position. -/
def saveCursor : String := "\x1b7"
/-- Restore cursor position. -/
def restoreCursor : String := "\x1b8"

/-- Scroll up n lines. -/
def scrollUp (n : Nat) : String := s!"\x1b[{n}S"
/-- Scroll down n lines. -/
def scrollDown (n : Nat) : String := s!"\x1b[{n}T"

end LeanAgent.Tui.Terminal