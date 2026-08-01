import Lean

/-!
# Key mapping and parsing

Port of Pi `packages/tui/src/keys.ts` — offline-testable key mapping subset.
-/

namespace LeanAgent.Tui.Keys

/-- Key action type (Pi key events). -/
inductive KeyAction
  | up
  | down
  | left
  | right
  | enter
  | escape
  | tab
  | backspace
  | delete
  | home
  | end
  | pageUp
  | pageDown
  | ctrlKey (c : Char)
  | altKey (c : Char)
  | shiftKey (c : Char)
  | metaKey (c : Char)
  | charKey (c : Char)
  | unknown
deriving Repr, BEq, Inhabited

/-- Human-readable key name (Pi `keyName`). -/
def keyName (a : KeyAction) : String :=
  match a with
  | KeyAction.up => "Up"
  | KeyAction.down => "Down"
  | KeyAction.left => "Left"
  | KeyAction.right => "Right"
  | KeyAction.enter => "Enter"
  | KeyAction.escape => "Escape"
  | KeyAction.tab => "Tab"
  | KeyAction.backspace => "Backspace"
  | KeyAction.delete => "Delete"
  | KeyAction.home => "Home"
  | KeyAction.end => "End"
  | KeyAction.pageUp => "PageUp"
  | KeyAction.pageDown => "PageDown"
  | KeyAction.ctrlKey c => s!"Ctrl+{c.toUpper}"
  | KeyAction.altKey c => s!"Alt+{c}"
  | KeyAction.shiftKey c => s!"Shift+{c.toUpper}"
  | KeyAction.metaKey c => s!"Meta+{c}"
  | KeyAction.charKey c => s!"{c}"
  | KeyAction.unknown => "Unknown"

/--
Parse a byte sequence into a KeyAction.
(Pi `parseKey` subset)
-/
def parseKey (bytes : Array UInt8) : KeyAction :=
  if bytes.size == 0 then KeyAction.unknown
  else if bytes.size == 1 then
    let b := bytes[0]!
    if b == 13 || b == 10 then KeyAction.enter
    else if b == 27 then KeyAction.escape
    else if b == 9 then KeyAction.tab
    else if b == 127 || b == 8 then KeyAction.backspace
    else if b < 32 then KeyAction.ctrlKey (Char.ofNat (b.toNat + 96))
    else KeyAction.charKey (Char.ofNat b.toNat)
  else if bytes.size >= 3 && bytes[0]! == 27 && bytes[1]! == 91 then
    let c := bytes[2]!
    if c == 65 then KeyAction.up
    else if c == 66 then KeyAction.down
    else if c == 67 then KeyAction.right
    else if c == 68 then KeyAction.left
    else if c == 72 then KeyAction.home
    else if c == 70 then KeyAction.end
    else if c == 53 && bytes.size >= 4 && bytes[3]! == 126 then KeyAction.pageUp
    else if c == 54 && bytes.size >= 4 && bytes[3]! == 126 then KeyAction.pageDown
    else if c == 51 && bytes.size >= 4 && bytes[3]! == 126 then KeyAction.delete
    else if c == 49 && bytes.size >= 4 && bytes[3]! == 126 then KeyAction.home
    else if c == 52 && bytes.size >= 4 && bytes[3]! == 126 then KeyAction.end
    else KeyAction.unknown
  else if bytes.size >= 3 && bytes[0]! == 27 && bytes[1]! == 79 then
    let c := bytes[2]!
    if c == 65 then KeyAction.up
    else if c == 66 then KeyAction.down
    else if c == 67 then KeyAction.right
    else if c == 68 then KeyAction.left
    else if c == 72 then KeyAction.home
    else if c == 70 then KeyAction.end
    else KeyAction.unknown
  else if bytes.size >= 2 && bytes[0]! == 27 then
    KeyAction.altKey (Char.ofNat (bytes[1]!.toNat))
  else KeyAction.unknown

/-- Check if a key action is a printable character. -/
def isPrintable (a : KeyAction) : Bool :=
  match a with
  | KeyAction.charKey c => !c.isWhitespace || c == ' '
  | _ => false

/-- Check if a key action is a modifier+key combination. -/
def isModified (a : KeyAction) : Bool :=
  match a with
  | KeyAction.ctrlKey _ | KeyAction.altKey _ | KeyAction.shiftKey _ | KeyAction.metaKey _ => true
  | _ => false

/-- Check if a key action is a navigation key. -/
def isNavigation (a : KeyAction) : Bool :=
  match a with
  | KeyAction.up | KeyAction.down | KeyAction.left | KeyAction.right
  | KeyAction.home | KeyAction.end | KeyAction.pageUp | KeyAction.pageDown => true
  | _ => false

end LeanAgent.Tui.Keys