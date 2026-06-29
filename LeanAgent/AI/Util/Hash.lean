namespace LeanAgent.AI.Util.Hash

def utf16UnitsForChar (char : Char) : List UInt32 :=
  let code := Char.toNat char
  if code <= 0xffff then
    [UInt32.ofNat code]
  else
    let offset := code - 0x10000
    [ UInt32.ofNat (0xd800 + offset / 0x400)
    , UInt32.ofNat (0xdc00 + offset % 0x400)
    ]

def utf16Units (value : String) : List UInt32 :=
  value.toList.foldr (fun char units => utf16UnitsForChar char ++ units) []

def imul (a b : UInt32) : UInt32 :=
  a * b

def mixInput (state : UInt32 × UInt32) (codeUnit : UInt32) : UInt32 × UInt32 :=
  let h1 := imul (state.fst ^^^ codeUnit) (UInt32.ofNat 2654435761)
  let h2 := imul (state.snd ^^^ codeUnit) (UInt32.ofNat 1597334677)
  (h1, h2)

def finalize (state : UInt32 × UInt32) : UInt32 × UInt32 :=
  let h1 :=
    imul (state.fst ^^^ (state.fst >>> 16)) (UInt32.ofNat 2246822507) ^^^
      imul (state.snd ^^^ (state.snd >>> 13)) (UInt32.ofNat 3266489909)
  let h2 :=
    imul (state.snd ^^^ (state.snd >>> 16)) (UInt32.ofNat 2246822507) ^^^
      imul (h1 ^^^ (h1 >>> 13)) (UInt32.ofNat 3266489909)
  (h1, h2)

def base36Digit (value : Nat) : String :=
  if value < 10 then
    String.singleton (Char.ofNat (Char.toNat '0' + value))
  else
    String.singleton (Char.ofNat (Char.toNat 'a' + value - 10))

partial def natToBase36 (value : Nat) : String :=
  if value < 36 then
    base36Digit value
  else
    natToBase36 (value / 36) ++ base36Digit (value % 36)

/-- Fast deterministic hash matching Pi's TypeScript `shortHash`. -/
def shortHash (value : String) : String :=
  let initial := (UInt32.ofNat 0xdeadbeef, UInt32.ofNat 0x41c6ce57)
  let (h1, h2) := finalize (utf16Units value |>.foldl mixInput initial)
  natToBase36 h2.toNat ++ natToBase36 h1.toNat

end LeanAgent.AI.Util.Hash
