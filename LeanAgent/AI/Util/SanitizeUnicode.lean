namespace LeanAgent.AI.Util.SanitizeUnicode

def isHighSurrogate (unit : UInt32) : Bool :=
  0xd800 <= unit.toNat && unit.toNat <= 0xdbff

def isLowSurrogate (unit : UInt32) : Bool :=
  0xdc00 <= unit.toNat && unit.toNat <= 0xdfff

partial def sanitizeSurrogateCodeUnits : List UInt32 → List UInt32
  | [] => []
  | unit :: [] =>
      if isHighSurrogate unit || isLowSurrogate unit then
        []
      else
        [unit]
  | first :: second :: rest =>
      if isHighSurrogate first then
        if isLowSurrogate second then
          first :: second :: sanitizeSurrogateCodeUnits rest
        else
          sanitizeSurrogateCodeUnits (second :: rest)
      else if isLowSurrogate first then
        sanitizeSurrogateCodeUnits (second :: rest)
      else
        first :: sanitizeSurrogateCodeUnits (second :: rest)

def sanitizeSurrogates (text : String) : String :=
  String.ofList
    (text.toList.filter fun char =>
      let code := Char.toNat char
      !(0xd800 <= code && code <= 0xdfff))

end LeanAgent.AI.Util.SanitizeUnicode
