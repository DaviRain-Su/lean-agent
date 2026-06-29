import LeanAgent.Json

namespace LeanAgent.AI.Util.JsonParse

def isControlCharacter (char : Char) : Bool :=
  let code := Char.toNat char
  code <= 0x1f

def hexDigit (value : Nat) : String :=
  if value < 10 then
    String.singleton (Char.ofNat (Char.toNat '0' + value))
  else
    String.singleton (Char.ofNat (Char.toNat 'a' + value - 10))

def controlHexEscape (char : Char) : String :=
  let code := Char.toNat char
  "\\u00" ++ hexDigit (code / 16) ++ hexDigit (code % 16)

def escapeControlCharacter (char : Char) : String :=
  if char == Char.ofNat 8 then
    "\\b"
  else if char == Char.ofNat 12 then
    "\\f"
  else if char == '\n' then
    "\\n"
  else if char == '\r' then
    "\\r"
  else if char == '\t' then
    "\\t"
  else
    controlHexEscape char

def isHexDigit (char : Char) : Bool :=
  ('0' <= char && char <= '9') ||
    ('a' <= char && char <= 'f') ||
    ('A' <= char && char <= 'F')

def validJsonEscape (char : Char) : Bool :=
  char == '"' || char == '\\' || char == '/' ||
    char == 'b' || char == 'f' || char == 'n' ||
    char == 'r' || char == 't' || char == 'u'

def fourHex? : List Char → Option (String × List Char)
  | a :: b :: c :: d :: rest =>
      if isHexDigit a && isHexDigit b && isHexDigit c && isHexDigit d then
        some (String.ofList [a, b, c, d], rest)
      else
        none
  | _ => none

partial def repairLoop : List Char → Bool → String
  | [], _ => ""
  | char :: rest, false =>
      String.singleton char ++ repairLoop rest (char == '"')
  | '"' :: rest, true =>
      "\"" ++ repairLoop rest false
  | '\\' :: [], true =>
      "\\\\"
  | '\\' :: next :: rest, true =>
      if next == 'u' then
        match fourHex? rest with
        | some (digits, remaining) => "\\u" ++ digits ++ repairLoop remaining true
        | none =>
            if validJsonEscape next then
              "\\" ++ String.singleton next ++ repairLoop rest true
            else
              "\\\\" ++ repairLoop (next :: rest) true
      else if validJsonEscape next then
        "\\" ++ String.singleton next ++ repairLoop rest true
      else
        "\\\\" ++ repairLoop (next :: rest) true
  | char :: rest, true =>
      (if isControlCharacter char then escapeControlCharacter char else String.singleton char) ++
        repairLoop rest true

def repairJson (json : String) : String :=
  repairLoop json.toList false

def parseJsonWithRepair (json : String) : Except String Lean.Json :=
  match Lean.Json.parse json with
  | .ok parsed => pure parsed
  | .error err =>
      let repaired := repairJson json
      if repaired == json then
        .error err
      else
        Lean.Json.parse repaired

def isAsciiWhitespace (char : Char) : Bool :=
  char == ' ' || char == '\n' || char == '\r' || char == '\t'

def trimRightAscii (value : String) : String :=
  String.ofList ((value.toList.reverse.dropWhile isAsciiWhitespace).reverse)

def stripTrailingComma (value : String) : String :=
  let trimmed := trimRightAscii value
  match trimmed.toList.reverse with
  | ',' :: rest => trimRightAscii (String.ofList rest.reverse)
  | _ => value

partial def danglingFieldPrefixLoop
    (chars : List Char)
    (acc : String)
    (lastCut : Option String)
    (inString escaped : Bool) : Option String :=
  match chars with
  | [] => lastCut
  | char :: rest =>
      let withChar := acc.push char
      if inString then
        if escaped then
          danglingFieldPrefixLoop rest withChar lastCut true false
        else if char == '\\' then
          danglingFieldPrefixLoop rest withChar lastCut true true
        else if char == '"' then
          danglingFieldPrefixLoop rest withChar lastCut false false
        else
          danglingFieldPrefixLoop rest withChar lastCut true false
      else if char == '"' then
        danglingFieldPrefixLoop rest withChar lastCut true false
      else if char == ',' then
        danglingFieldPrefixLoop rest withChar (some (trimRightAscii acc)) false false
      else if char == '{' || char == '[' then
        danglingFieldPrefixLoop rest withChar (some withChar) false false
      else
        danglingFieldPrefixLoop rest withChar lastCut false false

def stripDanglingField (value : String) : String :=
  let trimmed := trimRightAscii value
  match trimmed.toList.reverse with
  | ':' :: rest =>
      let beforeColon := String.ofList rest.reverse
      (danglingFieldPrefixLoop beforeColon.toList "" none false false).getD value
  | _ => value

def preparePartialJson (json : String) : String :=
  stripTrailingComma (stripDanglingField (stripTrailingComma json))

def popMatching (closing : Char) : List Char → List Char
  | expected :: rest => if expected == closing then rest else expected :: rest
  | [] => []

partial def completionLoop :
    List Char → Bool → Bool → List Char → Bool × List Char
  | [], inString, _, stack => (inString, stack)
  | char :: rest, false, _, stack =>
      if char == '"' then
        completionLoop rest true false stack
      else if char == '{' then
        completionLoop rest false false ('}' :: stack)
      else if char == '[' then
        completionLoop rest false false (']' :: stack)
      else if char == '}' || char == ']' then
        completionLoop rest false false (popMatching char stack)
      else
        completionLoop rest false false stack
  | char :: rest, true, escaped, stack =>
      if escaped then
        completionLoop rest true false stack
      else if char == '\\' then
        completionLoop rest true true stack
      else if char == '"' then
        completionLoop rest false false stack
      else
        completionLoop rest true false stack

def completePartialJson (json : String) : String :=
  let (inString, stack) := completionLoop json.toList false false []
  let suffix := (if inString then "\"" else "") ++ String.ofList stack
  json ++ suffix

def parseStreamingJson (partialJson : String) : Lean.Json :=
  if partialJson.trimAscii.isEmpty then
    LeanAgent.Json.obj []
  else
    match parseJsonWithRepair partialJson with
    | .ok parsed => parsed
    | .error _ =>
        let completed := completePartialJson (preparePartialJson (repairJson partialJson))
        match Lean.Json.parse completed with
        | .ok parsed => parsed
        | .error _ => LeanAgent.Json.obj []

def parseStreamingJson? : Option String → Lean.Json
  | none => LeanAgent.Json.obj []
  | some partialJson => parseStreamingJson partialJson

end LeanAgent.AI.Util.JsonParse
