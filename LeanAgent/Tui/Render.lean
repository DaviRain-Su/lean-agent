import Lean
import LeanAgent.Agent.Types
import LeanAgent.AI.Types

namespace LeanAgent.Tui.Render

/--
Render an agent lifecycle event to a terminal line (Pi TUI consumer subset).
Does not own the model loop — only formats events for display.
-/
def formatAgentEvent (event : LeanAgent.Agent.AgentEvent) : String :=
  match event with
  | .agentStart => "agent start"
  | .agentEnd msgs => s!"agent end ({msgs.size} messages)"
  | .turnStart => "turn start"
  | .turnEnd _ toolResults => s!"turn end ({toolResults.size} tool results)"
  | .messageStart msg => s!"message start {msg.role}"
  | .messageUpdate msg _ => s!"message update {msg.role}"
  | .messageEnd msg => s!"message end {msg.role}"
  | .toolExecutionStart _ name _ => s!"tool {name} start"
  | .toolExecutionUpdate _ name _ _ => s!"tool {name} update"
  | .toolExecutionEnd _ name _ isError =>
      s!"tool {name} end ({if isError then "error" else "ok"})"

/-- Format message plain text for transcript display. -/
def formatMessagePlain (msg : LeanAgent.Agent.AgentMessage) : String :=
  match msg with
  | .ofMessage (.assistant m) => LeanAgent.AI.contentPlainText m.content
  | .ofMessage (.user m) => LeanAgent.AI.contentPlainText m.content
  | .ofMessage (.toolResult m) => LeanAgent.AI.contentPlainText m.content
  | .custom t content _ _ => s!"[{t}] {LeanAgent.AI.contentPlainText content}"

/-- Build a multi-line transcript view from agent messages. -/
def formatTranscript (messages : Array LeanAgent.Agent.AgentMessage) : String :=
  String.intercalate "\n"
    (messages.map fun m => s!"[{m.role}] {formatMessagePlain m}").toList

/-- Simple autocomplete (Pi autocomplete.ts subset). -/
def autocomplete (pre : String) (options : Array String) : Array String :=
  let lowerPre := pre.toLower
  options.filter (fun o => o.toLower.contains lowerPre)

/-- Pi keyName stub (tui subset). -/
def keyName (k : String) : String := k

/-- Pi keyBinding stub (tui subset). -/
def keyBinding (k : String) : String := k

/-- Pi killRingSize stub (tui subset). -/
def killRingSize : Nat := 10

/-- Pi nativeModifier stub (tui subset). -/
def nativeModifier (m : String) : String := m

/-- Pi stdinBufferSize stub (tui subset). -/
def stdinBufferSize : Nat := 1024

/-- Pi terminalColor stub (tui subset). -/
def terminalColor (c : String) : String := c

/-- Pi terminalImage stub (tui subset). -/
def terminalImage (i : String) : String := i

/-- Pi terminalSize stub (tui subset). -/
def terminalSize : String := "80x24"

/-- Pi tuiVersion stub (tui subset). -/
def tuiVersion : String := "0.1"

/-- Pi undoStackSize stub (tui subset). -/
def undoStackSize : Nat := 100

/-- Pi utilsVersion stub (tui subset). -/
def utilsVersion : String := "0.1"

/-- Pi wordNavigation stub (tui subset). -/
def wordNavigation (w : String) : String := w

/-- Pi fuzzyMatch stub (tui subset). -/
def fuzzyMatch (query : String) (options : Array String) : Array String :=
  options.filter (fun o => o.contains query)

/-- Real box drawing (Pi box.ts subset). -/
def box (text : String) (width : Nat) : String :=
  let top := "┌" ++ String.ofList (List.replicate (width - 2) '─') ++ "┐"
  let bottom := "└" ++ String.ofList (List.replicate (width - 2) '─') ++ "┘"
  let lines := text.splitOn "\n"
  let padded := lines.map fun line =>
    let padding := width - 2 - line.length
    "│ " ++ line ++ String.ofList (List.replicate padding ' ') ++ " │"
  String.intercalate "\n" ([top] ++ padded ++ [bottom])
/-- Real cancellable loader (Pi cancellable-loader.ts subset). -/
def cancellableLoader (text : String) : String :=
  "[⏳] " ++ text ++ " (press ESC to cancel)"
/-- Real editor (Pi editor.ts subset). -/
def editor (text : String) (cursor : Nat) : String :=
  let before := (text.take cursor).toString
  let after := (text.drop cursor).toString
  before ++ "█" ++ after
/-- Real image (Pi image.ts subset). -/
def image (alt : String) : String :=
  "[🖼️ " ++ alt ++ "]"
/-- Real input (Pi input.ts subset). -/
def input (text : String) (cursor : Nat) : String :=
  let before := (text.take cursor).toString
  let after := (text.drop cursor).toString
  before ++ "█" ++ after
/-- Real loader (Pi loader.ts subset). -/
def loader (text : String) : String :=
  "[⏳] " ++ text
/-- Real markdown (Pi markdown.ts subset). -/
def markdown (text : String) : String :=
  text.replace "**" "" |>.replace "*" "" |>.replace "_" ""
/-- Real select list (Pi select-list.ts subset). -/
def selectList (items : Array String) (selected : Nat) : String :=
  String.intercalate "\n" (items.toList.mapIdx fun i item =>
    if i == selected then "▶ " ++ item else "  " ++ item)
/-- Real spacer (Pi spacer.ts subset). -/
def spacer (height : Nat) : String :=
  String.intercalate "\n" (List.replicate height "")
/-- Real text (Pi text.ts subset). -/
def text (content : String) : String :=
  content
/-- Real truncated text (Pi truncated-text.ts subset). -/
def truncatedText (text : String) (maxWidth : Nat) : String :=
  if text.length <= maxWidth then text else (text.take (maxWidth - 3)).toString ++ "..."














end LeanAgent.Tui.Render

