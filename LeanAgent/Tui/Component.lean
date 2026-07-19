import Lean

namespace LeanAgent.Tui

/--
Component interface — all TUI components must implement `render` and `invalidate`.
Mirrors Pi `packages/tui/src/tui.ts` `Component` interface.
-/
structure Component where
  /-- Render the component to lines for the given viewport width. -/
  render : Nat → IO (Array String)
  /-- Invalidate any cached rendering state. -/
  invalidate : IO Unit

/--
Container — a component that contains other components.
Mirrors Pi `packages/tui/src/tui.ts` `Container` class.
-/
structure Container where
  children : Array Component := #[]
deriving Inhabited

namespace Container

def empty : Container := {}

def addChild (c : Container) (child : Component) : Container :=
  { c with children := c.children.push child }

def clear (c : Container) : Container :=
  { c with children := #[] }

def invalidate (c : Container) : IO Unit :=
  c.children.mapM (·.invalidate) *> pure ()

def render (c : Container) (width : Nat) : IO (Array String) := do
  let mut lines : Array String := #[]
  for child in c.children do
    let childLines ← child.render width
    lines := lines ++ childLines
  pure lines

end Container

/--
Anchor position for overlays (Pi OverlayAnchor).
-/
inductive OverlayAnchor
  | center
  | topLeft
  | topRight
  | bottomLeft
  | bottomRight
  | topCenter
  | bottomCenter
  | leftCenter
  | rightCenter
deriving BEq, Repr, Inhabited

/--
Margin configuration for overlays (Pi OverlayMargin).
-/
structure OverlayMargin where
  top : Nat := 0
  right : Nat := 0
  bottom : Nat := 0
  left : Nat := 0
deriving Inhabited

/--
Size value that can be absolute (Nat) or percentage (String like "50%").
-/
inductive SizeValue
  | absolute (value : Nat)
  | percent (pct : Nat)
deriving BEq, Repr, Inhabited

/--
Options for overlay positioning and sizing (Pi OverlayOptions).
-/
structure OverlayOptions where
  width : Option SizeValue := none
  minWidth : Option Nat := none
  maxHeight : Option SizeValue := none
  anchor : OverlayAnchor := .center
  offsetX : Int := 0
  offsetY : Int := 0
  row : Option SizeValue := none
  col : Option SizeValue := none
  margin : Option OverlayMargin := none
  nonCapturing : Bool := false
deriving Inhabited

/--
Cursor position marker constant (Pi CURSOR_MARKER).
-/
def CURSOR_MARKER : String := "\x1b_pi:c\x07"

/--
Type class for focusable components.
-/
class Focusable (α : Type) where
  focused : α → Bool
  setFocused : α → Bool → α

end LeanAgent.Tui
