import Lean

namespace LeanAgent.Tui.Utils

def isControlChar (c : Char) : Bool :=
  let code := c.val
  code < 0x20 || code == 0x7F

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

partial def skipAnsi (str : String) : String × String :=
  if str.isEmpty then ("", "")
  else if str.get 0 != '\x1b' then ("", str)
  else
    let rest := (str.drop 1).toString
    if rest.isEmpty then (str, "")
    else
      let next := rest.get 0
      if next == '[' then
        let (_, remaining) := skipUntilLetter (rest.drop 1).toString
        (str, remaining)
      else if next == ']' then
        let (_, remaining) := skipUntilOscEnd (rest.drop 1).toString
        (str, remaining)
      else if next == '_' then
        let (_, remaining) := skipUntilOscEnd (rest.drop 1).toString
        (str, remaining)
      else
        (str, (rest.drop 1).toString)

partial def visibleWidth (str : String) : Nat :=
  go str 0
where
  go (s : String) (acc : Nat) : Nat :=
    if s.isEmpty then acc
    else
      let c := s.get 0
      let rest := (s.drop 1).toString
      if c == '\x1b' then
        let (_, after) := skipAnsi s
        go after acc
      else if c == '\t' then
        go rest (acc + 3)
      else if isControlChar c then
        go rest acc
      else if c.val > 0x7E then
        go rest (acc + 2)
      else
        go rest (acc + 1)

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

partial def breakWord (word : String) (width : Nat) : Array String :=
  go word
where
  go (remaining : String) : Array String :=
    if remaining.isEmpty then #[]
    else
      let (line, rest) := takeWidth remaining width
      #[line] ++ go rest

partial def wrapSingleLine (line : String) (width : Nat) : Array String :=
  if line.isEmpty then #[""]
  else if visibleWidth line <= width then #[line]
  else
    let words : Array String := (line.splitOn " ").toArray
    wrapWords words "" 0 #[]
where
  wrapWords (words : Array String) (currentLine : String) (currentWidth : Nat) (acc : Array String) : Array String :=
    if h : words.size = 0 then
      if currentLine.isEmpty then acc else acc.push currentLine
    else
      let word := words[0]
      let rest := words.drop 1
      let wordWidth := visibleWidth word
      let spaceWidth := if currentLine.isEmpty then 0 else 1
      if currentWidth + spaceWidth + wordWidth <= width then
        let sep := if currentLine.isEmpty then "" else " "
        wrapWords rest (currentLine ++ sep ++ word) (currentWidth + spaceWidth + wordWidth) acc
      else
        if currentLine.isEmpty then
          wrapWords rest "" 0 (acc ++ breakWord word width)
        else
          wrapWords rest word wordWidth (acc.push currentLine)

partial def wrapText (text : String) (width : Nat) : Array String :=
  if width == 0 then #[]
  else
    text.splitOn "\n" |>.foldl (fun acc line => acc ++ wrapSingleLine line width) #[]

def padRight (str : String) (width : Nat) : String :=
  let vw := visibleWidth str
  if vw >= width then str
  else str ++ String.ofList (List.replicate (width - vw) ' ')

def applyBackground (line : String) (width : Nat) (bgFn : String → String) : String :=
  bgFn (padRight line width)

def truncateToWidth (text : String) (maxWidth : Nat) (ellipsis : String := "...") : String :=
  if maxWidth == 0 then ""
  else if text.isEmpty then ""
  else
    let vw := visibleWidth text
    if vw <= maxWidth then text
    else
      let ellipsisWidth := visibleWidth ellipsis
      if ellipsisWidth >= maxWidth then
        takeWidth ellipsis maxWidth |>.fst
      else
        let (taken, _) := takeWidth text (maxWidth - ellipsisWidth)
        taken ++ ellipsis

end LeanAgent.Tui.Utils