import Lean

/-!
# Word navigation utilities

Port of Pi `packages/tui/src/word-navigation.ts`.
-/

namespace LeanAgent.Tui.WordNavigation

/-- Check if a character is whitespace. -/
def isWhitespaceChar (c : Char) : Bool :=
  c == ' ' || c == '\t' || c == '\n' || c == '\r'

/-- Check if a character is punctuation (word boundary). -/
def isPunctuationChar (c : Char) : Bool :=
  c ∈ ['-', '_', '.', '/', ':', '!', '?', ',', ';', '(', ')', '[', ']', '{', '}', '`', '\'', '"', '@', '#', '$', '%', '^', '&', '*', '+', '=', '|', '\\', '<', '>', '~']

/-- Check if a character is a word character (not whitespace or punctuation). -/
def isWordChar (c : Char) : Bool :=
  !isWhitespaceChar c && !isPunctuationChar c

/-- Skip backward through chars matching predicate, return first non-matching position. -/
partial def skipBack (chars : List Char) (i : Nat) (pred : Char → Bool) : Nat :=
  if i == 0 then 0
  else if pred (chars.getD (i - 1) ' ') then skipBack chars (i - 1) pred
  else i

/--
Find the cursor position after moving one word backward from `cursor` in `text`.
Pure function. (Pi `findWordBackward`)
-/
def findWordBackward (text : String) (cursor : Nat) : Nat :=
  if cursor == 0 then 0
  else
    let chars := text.toList
    let afterWs := skipBack chars cursor isWhitespaceChar
    if afterWs == 0 then 0
    else
      let lastChar := chars.getD (afterWs - 1) ' '
      if isPunctuationChar lastChar then
        skipBack chars afterWs isPunctuationChar
      else
        skipBack chars afterWs isWordChar

/-- Skip forward through chars matching predicate. -/
partial def skipFwd (chars : List Char) (n : Nat) (i : Nat) (pred : Char → Bool) : Nat :=
  if i >= n then n
  else if pred (chars.getD i ' ') then skipFwd chars n (i + 1) pred
  else i

/-- Skip forward through whitespace. -/
partial def skipWsFwd (chars : List Char) (n : Nat) (i : Nat) : Nat :=
  if i >= n then n
  else if isWhitespaceChar (chars.getD i ' ') then skipWsFwd chars n (i + 1)
  else i

/--
Find the cursor position after moving one word forward from `cursor` in `text`.
Pure function. (Pi `findWordForward`)
-/
def findWordForward (text : String) (cursor : Nat) : Nat :=
  let chars := text.toList
  let n := chars.length
  if cursor >= n then n
  else
    let c := chars.getD cursor ' '
    let afterBlock :=
      if isWordChar c then skipFwd chars n cursor isWordChar
      else if isPunctuationChar c then skipFwd chars n cursor isPunctuationChar
      else cursor
    skipWsFwd chars n afterBlock

end LeanAgent.Tui.WordNavigation