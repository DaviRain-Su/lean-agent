import Lean

/-!
# HTML entity decoding (Pi `packages/coding-agent/src/utils/html.ts`)

Decodes the HTML entities that appear in tool input and exported session HTML:
the five named entities (`amp`/`lt`/`gt`/`quot`/`apos`) plus numeric
(`#<decimal>`) and hex (`#x<hex>` / `#X<hex>`) code points. `decodeHtmlEntityAt`
scans forward from an `&` to the next `;` (within 16 chars) and returns the
decoded text plus the consumed length.
-/

namespace LeanAgent.CodingAgent.Utils.Html

/-- Pi `DecodedHtmlEntity`. -/
structure DecodedHtmlEntity where
  text : String
  /-- Number of source characters consumed, including the leading `&` and
  trailing `;`. -/
  length : Nat
deriving Inhabited, Repr

/-- Decode a Unicode code point (Pi `decodeCodePoint`); `none` if out of range. -/
def decodeCodePoint? (codePoint : Nat) : Option String :=
  if codePoint > 0x10FFFF then none
  else some (String.singleton (Char.ofNat codePoint))

/-- Parse a non-empty hex string to a Nat, or `none` on a non-hex digit. -/
def parseHex? (s : String) : Option Nat := Id.run do
  if s.isEmpty then pure none
  else
    let chars := s.toList.toArray
    let mut acc : Option Nat := some 0
    let mut i := 0
    while i < chars.size && acc.isSome do
      let c := chars[i]!
      let step (v : Nat) : Option Nat := some (acc.getD 0 * 16 + v)
      acc :=
        match c with
        | '0' => step 0 | '1' => step 1 | '2' => step 2 | '3' => step 3
        | '4' => step 4 | '5' => step 5 | '6' => step 6 | '7' => step 7
        | '8' => step 8 | '9' => step 9
        | 'a' | 'A' => step 10 | 'b' | 'B' => step 11
        | 'c' | 'C' => step 12 | 'd' | 'D' => step 13
        | 'e' | 'E' => step 14 | 'f' | 'F' => step 15
        | _ => none
      i := i + 1
    pure acc

/-- Pi `decodeHtmlEntity`: decode a named/numeric/hex entity body (without the
surrounding `&`/`;`). Returns `none` for unknown entities. -/
def decodeHtmlEntity (entity : String) : Option String :=
  match entity with
  | "amp" => some "&"
  | "lt" => some "<"
  | "gt" => some ">"
  | "quot" => some "\""
  | "apos" => some "'"
  | s =>
    let chars := s.toList.toArray
    if s.startsWith "#x" || s.startsWith "#X" then
      let hex := String.ofList (chars.extract 2 chars.size).toList
      parseHex? hex |>.bind decodeCodePoint?
    else if s.startsWith "#" then
      let dec := String.ofList (chars.extract 1 chars.size).toList
      if !dec.isEmpty && dec.toList.all Char.isDigit then decodeCodePoint? dec.toNat!
      else none
    else none

/--
Pi `decodeHtmlEntityAt`: scan forward from `&` at `index` to the next `;`
(within 16 chars), decode the entity body, and return the decoded text plus the
consumed length. Returns `none` if there is no `;` in range or the entity is
unknown.
-/
def decodeHtmlEntityAt (html : String) (index : Nat) : Option DecodedHtmlEntity := Id.run do
  let chars := html.toList.toArray
  -- Find the next ';' strictly after `index`.
  let mut semi := index + 1
  let mut foundSemi : Option Nat := none
  while semi < chars.size && foundSemi.isNone do
    if chars[semi]! == ';' then foundSemi := some semi
    semi := semi + 1
  match foundSemi with
  | none => pure none
  | some semicolonIndex =>
    if semicolonIndex - index > 16 then pure none
    else
      let entity := String.ofList (chars.extract (index + 1) semicolonIndex).toList
      match decodeHtmlEntity entity with
      | some decoded => pure (some { text := decoded, length := semicolonIndex - index + 1 })
      | none => pure none

end LeanAgent.CodingAgent.Utils.Html
