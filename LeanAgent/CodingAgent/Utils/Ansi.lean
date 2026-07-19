import Lean

/-!
# ANSI escape stripping (Pi `packages/coding-agent/src/utils/ansi.ts`)

`stripAnsi` removes ANSI CSI and OSC escape sequences from a string. Ports the
`ansi-regex` / `strip-ansi` behavior Pi bundles (Sindre Sorhus, MIT):
- OSC: `ESC ]` ... `ST` where `ST` is BEL (`0x07`), `ESC \` (`0x1B 0x5C`), or
  `0x9C`. Un-terminated OSC is left intact.
- CSI: `ESC` (or `0x9B`) + optional intermediates `[]()#;?` + optional numeric
  params (`\d{1,4}` separated by `;`/`:`) + exactly one final byte from the
  class `[0-9A-PR-TZ c-n q-u y = > < ~]`. Greedy params backtrack so a trailing
  digit can serve as the final byte (e.g. `\x1b(0`).

The fast path skips scanning when the input has no `ESC` (`0x1B`) and no CSI
(`0x9B`).
-/

namespace LeanAgent.CodingAgent.Utils.Ansi

/-- Final-byte class for a CSI sequence. -/
def isFinalByte (c : Char) : Bool :=
  (c ≥ '0' && c ≤ '9')
    || (c ≥ 'A' && c ≤ 'P')
    || (c ≥ 'R' && c ≤ 'T')
    || c == 'Z'
    || (c ≥ 'c' && c ≤ 'n')
    || (c ≥ 'q' && c ≤ 'u')
    || c == 'y'
    || c == '=' || c == '>' || c == '<' || c == '~'

/-- True if `c` is a CSI intermediate byte (`[`, `]`, `(`, `)`, `#`, `;`, `?`). -/
def isIntermediate (c : Char) : Bool :=
  match c with
  | '[' | ']' | '(' | ')' | '#' | ';' | '?' => true
  | _ => false

/-- True if `c` is a param byte: digit, `;`, or `:`. -/
def isParamByte (c : Char) : Bool :=
  c.isDigit || c == ';' || c == ':'

/-- The string-terminator bytes for an OSC sequence: BEL, or ESC followed by
`\`, or `0x9C`. -/
inductive STKind where
  | bel           -- 0x07 (length 1)
  | escBackslash  -- ESC \ = 0x1B 0x5C (length 2)
  | c1            -- 0x9C (length 1)
deriving Inhabited

/--
Find the OSC string terminator (`ST`) starting at `fromIdx`. Returns the index
of the terminator start and its kind, or `none` if none is found.
-/
def findOscST? (chars : Array Char) (fromIdx : Nat) : Option (Nat × STKind) := Id.run do
  let mut i := fromIdx
  let mut found : Option (Nat × STKind) := none
  while i < chars.size && found.isNone do
    let c := chars[i]!
    if c.toNat == 0x07 then found := some (i, .bel)
    else if c.toNat == 0x9C then found := some (i, .c1)
    else if c.toNat == 0x1B && i + 1 < chars.size && chars[i + 1]! == '\\' then
      found := some (i, .escBackslash)
    i := i + 1
  found

/-- Length consumed by an OSC terminator (BEL/C1 = 1, ESC\ = 2). -/
def stLength : STKind → Nat
  | .bel => 1
  | .c1 => 1
  | .escBackslash => 2

/--
Try to consume a CSI sequence starting at `escIdx` (the ESC/0x9B byte).
Returns the index just past the consumed sequence, or `none` if no valid CSI
matches here (the ESC should then be treated as a literal).
-/
def consumeCsi? (chars : Array Char) (escIdx : Nat) : Option Nat := Id.run do
  let size := chars.size
  let mut j := escIdx + 1
  -- Greedy intermediates.
  while j < size && isIntermediate chars[j]! do j := j + 1
  let interEnd := j
  -- Greedy param bytes.
  let mut p := interEnd
  while p < size && isParamByte chars[p]! do p := p + 1
  -- Try the longest param run first; require a final byte immediately after.
  -- If that fails, backtrack one param byte at a time (the last param byte
  -- becomes the final). Digits are valid finals.
  let mut result : Option Nat := none
  let mut k := p
  while k ≥ interEnd && result.isNone && k ≤ p do
    -- Final byte must exist at index k (one past the param prefix [interEnd, k)).
    if k < size && isFinalByte chars[k]! then
      result := some (k + 1)
    if result.isNone then
      -- Backtrack: shrink the param region by one byte.
      if k > interEnd then k := k - 1 else break
  -- Also consider the no-param case (interEnd itself is the final).
  if result.isNone && interEnd < size && isFinalByte chars[interEnd]! then
    result := some (interEnd + 1)
  result

/--
Pi `stripAnsi`: remove CSI/OSC escape sequences. Fast path: if the input has
neither `ESC` (0x1B) nor 0x9B, return it unchanged.
-/
partial def stripAnsi (value : String) : String :=
  if !(value.contains (Char.ofNat 0x1B)) && !(value.contains (Char.ofNat 0x9B)) then value
  else
    let chars := value.toList.toArray
    go chars 0 ""
where
  go (chars : Array Char) (i : Nat) (acc : String) : String :=
    if i ≥ chars.size then acc
    else
      let c := chars[i]!
      if c.toNat == 0x1B || c.toNat == 0x9B then
        -- Possible escape sequence.
        let nextIdx := i + 1
        if nextIdx ≥ chars.size then
          go chars (i + 1) (acc ++ String.singleton c)
        else
          let nextC := chars[nextIdx]!
          if nextC == ']' then
            -- OSC: ESC ] ... ST.
            match findOscST? chars (i + 2) with
            | some (stIdx, kind) => go chars (stIdx + stLength kind) acc
            | none => go chars (i + 1) (acc ++ String.singleton c)
          else
            match consumeCsi? chars i with
            | some stop => go chars stop acc
            | none => go chars (i + 1) (acc ++ String.singleton c)
      else go chars (i + 1) (acc ++ String.singleton c)

end LeanAgent.CodingAgent.Utils.Ansi
