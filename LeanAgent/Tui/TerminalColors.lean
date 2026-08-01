import Lean

/-!
# Terminal color utilities

Port of Pi `packages/tui/src/terminal-colors.ts`.

Provides color capability detection and RGB-to-ANSI color conversion.
Pure functions where possible; env-var checks are IO.
-/

namespace LeanAgent.Tui.TerminalColors

/-- Check if terminal supports true color (24-bit). -/
def supportsTrueColor : IO Bool := do
  let colorterm ← IO.getEnv "COLORTERM"
  match colorterm with
  | some v => pure (v.contains "truecolor" || v.contains "24bit")
  | none => pure false

/-- Check if terminal supports 256 colors. -/
def supports256Color : IO Bool := do
  let term ← IO.getEnv "TERM"
  match term with
  | some v => pure (v.contains "256color" || v.contains "256colour")
  | none => pure false

/-- Check NO_COLOR env var. -/
def isColorDisabled : IO Bool := do
  let noColor ← IO.getEnv "NO_COLOR"
  pure noColor.isSome

/--
Check if color output is enabled (combination of env checks).
Returns the color level: 0 = none, 1 = 16-color, 2 = 256-color, 3 = true-color.
-/
def colorLevel : IO Nat := do
  if (← isColorDisabled) then pure 0
  else if (← supportsTrueColor) then pure 3
  else if (← supports256Color) then pure 2
  else
    let term ← IO.getEnv "TERM"
    match term with
    | some v => pure (if v != "dumb" then 1 else 0)
    | none => pure 1

/-- Check if any color output is enabled. -/
def colorEnabled : IO Bool := do
  pure ((← colorLevel) > 0)

/--
Convert RGB values to a 256-color ANSI code.
Uses the standard 6x6x6 color cube (16-231) plus grayscale ramp (232-255).
-/
def rgbToAnsi256 (r : Nat) (g : Nat) (b : Nat) : Nat :=
  -- Check if the color is a grayscale
  let toXLevel (v : Nat) : Nat :=
    if v < 48 then 0
    else if v < 115 then 1
    else
      -- Map to 0-5 in the 6x6x6 cube
      let level := (v - 35) / 40
      if level > 5 then 5 else level
  -- Check for grayscale
  if r == g && g == b then
    if r < 8 then 16
    else if r > 248 then 231
    else
      -- Grayscale ramp: 232-255
      let grayLevel := (r - 8) / 10
      if grayLevel > 23 then 255 else 232 + grayLevel
  else
    let x := toXLevel r
    let y := toXLevel g
    let z := toXLevel b
    16 + 36 * x + 6 * y + z

/--
Convert RGB values to basic 16-color ANSI code.
Uses luminance threshold and channel dominance.
-/
def rgbToAnsi (r : Nat) (g : Nat) (b : Nat) : Nat :=
  -- Clamp to 0-255
  let clamp (v : Nat) : Nat := min v 255
  let r := clamp r
  let g := clamp g
  let b := clamp b
  -- Compute luminance
  let lum := (r * 299 + g * 587 + b * 114) / 1000
  if lum == 0 then 0  -- black
  else if lum >= 250 then 15  -- white
  else
    -- Determine if bright
    let bright := lum > 128
    -- Channel dominance
    let maxVal := max (max r g) b
    let minVal := min (min r g) b
    if maxVal == r && maxVal == g then if bright then 14 else 6  -- yellow
    else if maxVal == r && maxVal == b then if bright then 13 else 5  -- magenta
    else if maxVal == g && maxVal == b then if bright then 11 else 2  -- cyan
    else if maxVal == r then if bright then 9 else 1  -- red
    else if maxVal == g then if bright then 10 else 2  -- green
    else if maxVal == b then if bright then 12 else 4  -- blue
    else if bright then 7 else 8  -- white/gray

/-- Generate a foreground ANSI color escape (256-color mode). -/
def fg256 (code : Nat) : String := s!"\x1b[38;5;{code}m"

/-- Generate a background ANSI color escape (256-color mode). -/
def bg256 (code : Nat) : String := s!"\x1b[48;5;{code}m"

/-- Generate a foreground ANSI color escape (true-color mode). -/
def fgTrueColor (r : Nat) (g : Nat) (b : Nat) : String := s!"\x1b[38;2;{r};{g};{b}m"

/-- Generate a background ANSI color escape (true-color mode). -/
def bgTrueColor (r : Nat) (g : Nat) (b : Nat) : String := s!"\x1b[48;2;{r};{g};{b}m"

/-- Reset all attributes. -/
def reset : String := "\x1b[0m"

end LeanAgent.Tui.TerminalColors