import Lean

namespace LeanAgent.Tui.Utils

/--
Check if a character is a control character (C0: 0x00-0x1F, DEL: 0x7F).
-/
def isControlChar (c : Char) : Bool :=
  let code := c.val
  code < 0x20 || code == 0x7F

/--
Calculate the visible width of a string in terminal columns.
Simplified version — treats all non-ASCII as width 2 (CJK/emoji), ASCII as width 1.
ANSI escape sequences are stripped before measurement.
-/
def visibleWidth (str : String) : Nat :=
  go str 0
where
  go (s : String) (acc : Nat) : Nat :=
    if s.isEmpty then
      acc
    else
      let c := s.get 0
      let rest := (s.drop 1).toString
      if c == '\x1b' then
        let (_, after) := skipAnsi s
        go after.toString acc
      else if c == '\t' then
        go rest (acc + 3)
      else if isControlChar c then
        go rest acc
      else if c.val > 0x7E then
        go rest (acc + 2)
      else
        go rest (acc + 1)
  termination_by s.length

/--
Skip an ANSI escape sequence starting at position 0 of the string.
Returns (code, rest) where both are Strings.
-/
partial def skipAnsi (str : String) : String × String :=
  if str.isEmpty then ("", "")
  else if str.get 0 != '\x1b' then ("", str)
  else
    let rest := (str.drop 1).toString
    if rest.isEmpty then (str, "")
    else
      let next := rest.get 0
      if next == '[' then
        let after := (rest.drop 1).toString
        let (_, remaining) := skipUntilLetter after
        (str, remaining.toString)
      else if next == ']' then
        let after := (rest.drop 1).toString
        let (_, remaining) := skipUntilOscEnd after
        (str, remaining.toString)
      else if next == '_' then
        let after := (rest.drop 1).toString
        let (_, remaining) := skipUntilOscEnd after
        (str, remaining.toString)
      else
        (str, (rest.drop 1).toString)

partial def skipUntilLetter (str : String) : String × String :=
  if str.isEmpty then ("", "")
  else
    let c := str.get 0
    if c.isAlpha then
      ((str.take 1).toString, (str.drop 1).toString)
    else
      let (code, rest) := skipUntilLetter (str.drop 1).toString
      ((str.take 1).toString ++ code, rest)

partial def skipUntilOscEnd (str : String) : String × String :=
  if str.isEmpty then ("", "")
  else
    let c := str.get 0
    if c == '\x07' then
      ("", (str.drop 1).toString)
    else if c == '\x1b' && str.length > 1 && (str.drop 1).toString.get 0 == '\\' then
      ("", (str.drop 2).toString)
    else
      let (code, rest) := skipUntilOscEnd (str.drop 1).toString
      ((str.take 1).toString ++ code, rest)

/--
Take as many characters as fit within `width` columns from the start of a string.
Returns (taken, rest).
-/
partial def takeWidth (str : String) (width : Nat) : String × String :=
  go str 0 "" width
where
  go (remaining : String) (_col : Nat) (taken : String) (remainingWidth : Nat) : String × String :=
    if remaining.isEmpty || remainingWidth == 0 then
      (taken, remaining)
    else
      let c := remaining.get 0
      let rest := (remaining.drop 1).toString
      let w := if c == '\t' then 3 else if c.val > 0x7E then 2 else 1
      if w > remainingWidth then
        (taken, remaining)
      else
        go rest (_col + w) (taken ++ c.toString) (remainingWidth - w)

/--
Break a word that's too long to fit on one line.
-/
partial def breakWord (word : String) (width : Nat) : Array String :=
  go word
where
  go (remaining : String) : Array String :=
    if remaining.isEmpty then #[]
    else
      let (line, rest) := takeWidth remaining width
      let restLines := go rest
      #[line] ++ restLines

/--
Wrap a single line (no newlines) to fit within width.
-/
partial def wrapSingleLine (line : String) (width : Nat) : Array String :=
  if line.isEmpty then #[""]
  else if visibleWidth line ≤ width then #[line]
  else
    let words : Array String := (line.splitOn " ").toArray
    wrapWords words "" 0 #[]
where
  wrapWords (words : Array String) (currentLine : String) (currentWidth : Nat) (acc : Array String) : Array String :=
    if h : words.size = 0 then
      if currentLine.isEmpty then acc
      else acc.push currentLine
    else
      let word := words[0]
      let rest := words.drop 1
      let wordWidth := visibleWidth word
      let spaceWidth := if currentLine.isEmpty then 0 else 1
      if currentWidth + spaceWidth + wordWidth ≤ width then
        let sep := if currentLine.isEmpty then "" else " "
        wrapWords rest (currentLine ++ sep ++ word) (currentWidth + spaceWidth + wordWidth) acc
      else
        if currentLine.isEmpty then
          let broken := breakWord word width
          wrapWords rest "" 0 (acc ++ broken)
        else
          wrapWords rest word wordWidth (acc.push currentLine)

/--
Wrap text to fit within a given width.
Handles basic word wrapping.
-/
partial def wrapText (text : String) (width : Nat) : Array String :=
  if width == 0 then #[]
  else
    let lines := text.splitOn "\n"
    lines.foldl (fun acc line =>
      acc ++ wrapSingleLine line width
    ) #[]

/--
Pad a string to a given visible width with spaces on the right.
-/
def padRight (str : String) (width : Nat) : String :=
  let vw := visibleWidth str
  if vw ≥ width then str
  else str ++ String.ofList (List.replicate (width - vw) ' ')

/--
Apply a background function to a line, padding to full width.
-/
def applyBackground (line : String) (width : Nat) (bgFn : String → String) : String :=
  let padded := padRight line width
  bgFn padded

/--
Truncate text to fit within a maximum visible width, adding ellipsis if needed.
-/
def truncateToWidth (text : String) (maxWidth : Nat) (ellipsis : String := "...") : String :=
  if maxWidth == 0 then ""
  else if text.isEmpty then ""
  else
    let vw := visibleWidth text
    if vw ≤ maxWidth then text
    else
      let ellipsisWidth := visibleWidth ellipsis
      if ellipsisWidth ≥ maxWidth then
        takeWidth ellipsis maxWidth |>.fst
      else
        let targetWidth := maxWidth - ellipsisWidth
        let (taken, _) := takeWidth text targetWidth
        taken ++ ellipsis

end LeanAgent.Tui.Utils
