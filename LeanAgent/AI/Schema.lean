import LeanAgent.Json

namespace LeanAgent.AI.Schema

structure ValidationIssue where
  path : String
  message : String
deriving Repr, BEq

def stringEnum (values : Array String) (description : Option String := none) (default? : Option String := none) :
    Lean.Json :=
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str "string")
     , ("enum", LeanAgent.Json.arr (values.map LeanAgent.Json.str))
     ] ++
      (match description with
      | some value => [("description", LeanAgent.Json.str value)]
      | none => []) ++
      (match default? with
      | some value => [("default", LeanAgent.Json.str value)]
      | none => []))

def objectEntries? (json : Lean.Json) : Option (List (String × Lean.Json)) :=
  match json.getObj? with
  | .ok obj => some obj.toList
  | .error _ => none

def schemaTypes (schema : Lean.Json) : List String :=
  match LeanAgent.Json.optVal? schema "type" with
  | some (Lean.Json.str value) => [value]
  | some (Lean.Json.arr values) =>
      values.toList.filterMap fun
        | Lean.Json.str value => some value
        | _ => none
  | _ => []

def requiredKeys (schema : Lean.Json) : List String :=
  match LeanAgent.Json.optVal? schema "required" with
  | some (Lean.Json.arr values) =>
      values.toList.filterMap fun
        | Lean.Json.str value => some value
        | _ => none
  | _ => []

def enumValues (schema : Lean.Json) : List Lean.Json :=
  match LeanAgent.Json.optVal? schema "enum" with
  | some (Lean.Json.arr values) => values.toList
  | _ => []

def enumValues? (schema : Lean.Json) : Option (List Lean.Json) :=
  match LeanAgent.Json.optVal? schema "enum" with
  | some (Lean.Json.arr values) => some values.toList
  | _ => none

def propertySchemas (schema : Lean.Json) : List (String × Lean.Json) :=
  match LeanAgent.Json.optVal? schema "properties" with
  | some properties => (objectEntries? properties).getD []
  | none => []

def itemSchema? (schema : Lean.Json) : Option Lean.Json :=
  match LeanAgent.Json.optVal? schema "items" with
  | some value@(.obj _) => some value
  | _ => none

def tupleItemSchemas (schema : Lean.Json) : Array Lean.Json :=
  match LeanAgent.Json.optVal? schema "items" with
  | some (Lean.Json.arr values) => values
  | _ => #[]

def additionalProperties? (schema : Lean.Json) : Option Lean.Json :=
  LeanAgent.Json.optVal? schema "additionalProperties"

def natKeyword? (schema : Lean.Json) (key : String) : Option Nat :=
  match LeanAgent.Json.optVal? schema key with
  | some value =>
      match value.getNat? with
      | .ok nat => some nat
      | .error _ => none
  | none => none

def boolKeyword? (schema : Lean.Json) (key : String) : Option Bool :=
  match LeanAgent.Json.optVal? schema key with
  | some (.bool value) => some value
  | _ => none

def numberKeyword? (schema : Lean.Json) (key : String) : Option Lean.JsonNumber :=
  match LeanAgent.Json.optVal? schema key with
  | some (.num value) => some value
  | _ => none

def stringKeyword? (schema : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? schema key with
  | some (.str value) => some value
  | _ => none

def schemaArray? (schema : Lean.Json) (key : String) : Option (Array Lean.Json) :=
  match LeanAgent.Json.optVal? schema key with
  | some (.arr values) =>
      some (values.filter fun
        | .obj _ => true
        | _ => false)
  | _ => none

def constValue? (schema : Lean.Json) : Option Lean.Json :=
  LeanAgent.Json.optVal? schema "const"

def schemaObject? (schema : Lean.Json) (key : String) : Option Lean.Json :=
  match LeanAgent.Json.optVal? schema key with
  | some value@(.obj _) => some value
  | _ => none

def enumerateList {α : Type} (items : List α) : List (Nat × α) :=
  let rec loop : List α → Nat → List (Nat × α)
    | [], _ => []
    | item :: rest, index => (index, item) :: loop rest (index + 1)
  loop items 0

def hasDuplicateJson (values : List Lean.Json) : Bool :=
  match values with
  | [] => false
  | value :: rest => rest.contains value || hasDuplicateJson rest

def parseJsonNumberString? (value : String) : Option Lean.Json :=
  let trimmed := value.trimAscii.toString
  if trimmed.isEmpty then
    none
  else
    match Lean.Json.parse trimmed with
    | .ok value@(.num _) => some value
    | _ => none

def intStringJson? (value : String) : Option Lean.Json :=
  let trimmed := value.trimAscii.toString
  match trimmed.toInt? with
  | some int => some (Lean.Json.num (Lean.JsonNumber.fromInt int))
  | none => none

def jsonNat? (value : Lean.Json) : Option Nat :=
  match value.getNat? with
  | .ok nat => some nat
  | .error _ => none

def jsonInteger? : Lean.Json → Bool
  | .num number => number.exponent == 0
  | _ => false

def jsonNumIsZero (value : Lean.Json) : Bool :=
  jsonNat? value == some 0

def jsonNumIsOne (value : Lean.Json) : Bool :=
  jsonNat? value == some 1

def coercePrimitiveByType (value : Lean.Json) (schemaType : String) : Lean.Json :=
  match schemaType, value with
  | "number", .str raw => (parseJsonNumberString? raw).getD value
  | "number", .bool raw => LeanAgent.Json.nat (if raw then 1 else 0)
  | "number", .null => LeanAgent.Json.nat 0
  | "integer", .str raw => (intStringJson? raw).getD value
  | "integer", .bool raw => LeanAgent.Json.nat (if raw then 1 else 0)
  | "integer", .null => LeanAgent.Json.nat 0
  | "boolean", .str "true" => Lean.Json.bool true
  | "boolean", .str "false" => Lean.Json.bool false
  | "boolean", value@(.num _) =>
      if jsonNumIsOne value then Lean.Json.bool true
      else if jsonNumIsZero value then Lean.Json.bool false
      else value
  | "boolean", .null => Lean.Json.bool false
  | "string", .num _ => LeanAgent.Json.str value.compress
  | "string", .bool raw => LeanAgent.Json.str (if raw then "true" else "false")
  | "string", .null => LeanAgent.Json.str ""
  | "null", .str "" => Lean.Json.null
  | "null", value@(.num _) => if jsonNumIsZero value then Lean.Json.null else value
  | "null", .bool false => Lean.Json.null
  | _, _ => value

def matchesJsonType (value : Lean.Json) : String → Bool
  | "number" =>
      match value with
      | .num _ => true
      | _ => false
  | "integer" => jsonInteger? value
  | "boolean" =>
      match value with
      | .bool _ => true
      | _ => false
  | "string" =>
      match value with
      | .str _ => true
      | _ => false
  | "null" =>
      match value with
      | .null => true
      | _ => false
  | "array" =>
      match value with
      | .arr _ => true
      | _ => false
  | "object" =>
      match value with
      | .obj _ => true
      | _ => false
  | _ => false

partial def coerceWithJsonSchema (value : Lean.Json) (schema : Lean.Json) : Lean.Json :=
  let value :=
    match schemaArray? schema "allOf" with
    | some schemas => schemas.foldl (fun current nested => coerceWithJsonSchema current nested) value
    | none => value
  let schemaTypes := schemaTypes schema
  let matchesUnionMember :=
    schemaTypes.length > 1 && schemaTypes.any (matchesJsonType value)
  let coerced :=
    if schemaTypes.isEmpty || matchesUnionMember then
      value
    else
      schemaTypes.foldl
        (fun current schemaType =>
          if current == value then coercePrimitiveByType current schemaType else current)
        value
  match coerced with
  | .obj fields =>
      let properties := propertySchemas schema
      let additional := additionalProperties? schema
      let updated := fields.toList.map fun (key, fieldValue) =>
        match properties.find? (fun item => item.fst == key) with
        | some (_, propertySchema) => (key, coerceWithJsonSchema fieldValue propertySchema)
        | none =>
            match additional with
            | some extraSchema@(.obj _) => (key, coerceWithJsonSchema fieldValue extraSchema)
            | _ => (key, fieldValue)
      LeanAgent.Json.obj updated
  | .arr values =>
      let tupleSchemas := tupleItemSchemas schema
      match itemSchema? schema with
      | some itemSchema => LeanAgent.Json.arr (values.map fun item => coerceWithJsonSchema item itemSchema)
      | none =>
          if tupleSchemas.isEmpty then
            coerced
          else
            LeanAgent.Json.arr
              (values.mapIdx fun index item =>
                match tupleSchemas[index]? with
                | some itemSchema => coerceWithJsonSchema item itemSchema
                | none => item)
  | _ => coerced

def pathChild (path key : String) : String :=
  if path == "root" then key else path ++ "." ++ key

def pathIndex (path : String) (index : Nat) : String :=
  path ++ "." ++ toString index

def typeIssue (path : String) (schemaTypes : List String) : ValidationIssue :=
  { path := path
    message := "expected " ++ String.intercalate " or " schemaTypes
  }

def requiredIssue (path key : String) : ValidationIssue :=
  { path := pathChild path key, message := "required property missing" }

def enumIssue (path : String) : ValidationIssue :=
  { path := path, message := "expected one of enum values" }

def constIssue (path : String) : ValidationIssue :=
  { path := path, message := "expected const value" }

def anyOfIssue (path : String) : ValidationIssue :=
  { path := path, message := "expected to match at least one schema" }

def oneOfIssue (path : String) : ValidationIssue :=
  { path := path, message := "expected to match exactly one schema" }

def notIssue (path : String) : ValidationIssue :=
  { path := path, message := "expected not to match schema" }

def minLengthIssue (path : String) (minLength : Nat) : ValidationIssue :=
  { path := path, message := s!"expected length >= {minLength}" }

def maxLengthIssue (path : String) (maxLength : Nat) : ValidationIssue :=
  { path := path, message := s!"expected length <= {maxLength}" }

def patternIssue (path pattern : String) : ValidationIssue :=
  { path := path, message := s!"expected to match pattern /{pattern}/" }

def minPropertiesIssue (path : String) (minProperties : Nat) : ValidationIssue :=
  { path := path, message := s!"expected object property count >= {minProperties}" }

def maxPropertiesIssue (path : String) (maxProperties : Nat) : ValidationIssue :=
  { path := path, message := s!"expected object property count <= {maxProperties}" }

def minItemsIssue (path : String) (minItems : Nat) : ValidationIssue :=
  { path := path, message := s!"expected array length >= {minItems}" }

def maxItemsIssue (path : String) (maxItems : Nat) : ValidationIssue :=
  { path := path, message := s!"expected array length <= {maxItems}" }

def uniqueItemsIssue (path : String) : ValidationIssue :=
  { path := path, message := "expected unique array items" }

def containsIssue (path : String) : ValidationIssue :=
  { path := path, message := "expected array to contain matching item" }

def minContainsIssue (path : String) (minContains : Nat) : ValidationIssue :=
  { path := path, message := s!"expected matching item count >= {minContains}" }

def maxContainsIssue (path : String) (maxContains : Nat) : ValidationIssue :=
  { path := path, message := s!"expected matching item count <= {maxContains}" }

def minimumIssue (path : String) (minimum : Lean.JsonNumber) : ValidationIssue :=
  { path := path, message := s!"expected number >= {minimum}" }

def maximumIssue (path : String) (maximum : Lean.JsonNumber) : ValidationIssue :=
  { path := path, message := s!"expected number <= {maximum}" }

def exclusiveMinimumIssue (path : String) (minimum : Lean.JsonNumber) : ValidationIssue :=
  { path := path, message := s!"expected number > {minimum}" }

def exclusiveMaximumIssue (path : String) (maximum : Lean.JsonNumber) : ValidationIssue :=
  { path := path, message := s!"expected number < {maximum}" }

/-- Small JSON Schema `pattern` regex subset. Unsupported JS RegExp forms fail open. -/
inductive PatternClassItem where
  | single (char : Char)
  | range (first last : Char)
  | digit (negated : Bool)
  | word (negated : Bool)
  | space (negated : Bool)
deriving Repr, BEq

inductive PatternAtom where
  | literal (char : Char)
  | any
  | digit (negated : Bool)
  | word (negated : Bool)
  | space (negated : Bool)
  | charClass (negated : Bool) (items : List PatternClassItem)
deriving Repr, BEq

inductive PatternQuant where
  | one
  | zeroOrMore
  | oneOrMore
  | optional
  | range (min : Nat) (max : Option Nat)
deriving Repr, BEq

structure PatternPiece where
  atom : PatternAtom
  quant : PatternQuant := .one
deriving Repr, BEq

structure CompiledPattern where
  startAnchored : Bool
  endAnchored : Bool
  pieces : List PatternPiece
deriving Repr, BEq

def isAsciiDigit (char : Char) : Bool :=
  '0'.toNat <= char.toNat && char.toNat <= '9'.toNat

def isAsciiAlpha (char : Char) : Bool :=
  ('a'.toNat <= char.toNat && char.toNat <= 'z'.toNat) ||
    ('A'.toNat <= char.toNat && char.toNat <= 'Z'.toNat)

def isAsciiWord (char : Char) : Bool :=
  isAsciiAlpha char || isAsciiDigit char || char == '_'

def isAsciiSpace (char : Char) : Bool :=
  char == ' ' || char == '\t' || char == '\n' || char == '\r'

def unescapePatternLiteral : Char → Char
  | 'n' => '\n'
  | 'r' => '\r'
  | 't' => '\t'
  | other => other

def escapedPatternAtom? : Char → Option PatternAtom
  | 'd' => some (.digit false)
  | 'D' => some (.digit true)
  | 'w' => some (.word false)
  | 'W' => some (.word true)
  | 's' => some (.space false)
  | 'S' => some (.space true)
  | other => some (.literal (unescapePatternLiteral other))

def escapedClassItem? : Char → Option PatternClassItem
  | 'd' => some (.digit false)
  | 'D' => some (.digit true)
  | 'w' => some (.word false)
  | 'W' => some (.word true)
  | 's' => some (.space false)
  | 'S' => some (.space true)
  | other => some (.single (unescapePatternLiteral other))

def classItemSingleChar? : PatternClassItem → Option Char
  | .single char => some char
  | _ => none

def classItemMatches (item : PatternClassItem) (char : Char) : Bool :=
  match item with
  | .single expected => char == expected
  | .range first last => first.toNat <= char.toNat && char.toNat <= last.toNat
  | .digit false => isAsciiDigit char
  | .digit true => !isAsciiDigit char
  | .word false => isAsciiWord char
  | .word true => !isAsciiWord char
  | .space false => isAsciiSpace char
  | .space true => !isAsciiSpace char

def atomMatches (atom : PatternAtom) (char : Char) : Bool :=
  match atom with
  | .literal expected => char == expected
  | .any => true
  | .digit false => isAsciiDigit char
  | .digit true => !isAsciiDigit char
  | .word false => isAsciiWord char
  | .word true => !isAsciiWord char
  | .space false => isAsciiSpace char
  | .space true => !isAsciiSpace char
  | .charClass negated items =>
      let matched := items.any (fun item => classItemMatches item char)
      if negated then !matched else matched

def parseNatChars? (chars : List Char) : Option Nat :=
  if chars.isEmpty || chars.any (fun char => !isAsciiDigit char) then
    none
  else
    chars.foldl
      (fun acc char => acc.map fun value => value * 10 + (char.toNat - '0'.toNat))
      (some 0)

partial def parseClassAtom : List Char → Option (PatternClassItem × List Char)
  | [] => none
  | '\\' :: escaped :: rest => do
      let item ← escapedClassItem? escaped
      pure (item, rest)
  | char :: rest => some (.single char, rest)

partial def parseClassItems (acc : List PatternClassItem) : List Char →
    Option (List PatternClassItem × List Char)
  | [] => none
  | ']' :: rest => some (acc.reverse, rest)
  | chars => do
      let (firstItem, afterFirst) ← parseClassAtom chars
      match classItemSingleChar? firstItem, afterFirst with
      | some first, '-' :: afterDash =>
          match afterDash with
          | [] => none
          | ']' :: _ => parseClassItems (firstItem :: acc) afterFirst
          | _ => do
              let (lastItem, afterLast) ← parseClassAtom afterDash
              match classItemSingleChar? lastItem with
              | some last => parseClassItems (.range first last :: acc) afterLast
              | none => parseClassItems (lastItem :: .single '-' :: firstItem :: acc) afterLast
      | _, _ => parseClassItems (firstItem :: acc) afterFirst

def parseCharClass : List Char → Option (PatternAtom × List Char)
  | '^' :: rest => do
      let (items, remaining) ← parseClassItems [] rest
      pure (.charClass true items, remaining)
  | rest => do
      let (items, remaining) ← parseClassItems [] rest
      pure (.charClass false items, remaining)

def unsupportedPatternChar (char : Char) : Bool :=
  char == '(' || char == ')' || char == '|'

partial def parsePatternAtom : List Char → Option (PatternAtom × List Char)
  | [] => none
  | '\\' :: escaped :: rest => do
      let atom ← escapedPatternAtom? escaped
      pure (atom, rest)
  | '[' :: rest => parseCharClass rest
  | '.' :: rest => some (.any, rest)
  | char :: rest =>
      if unsupportedPatternChar char ||
          char == '*' || char == '+' || char == '?' || char == '{' || char == '}' then
        none
      else
        some (.literal char, rest)

partial def takeUntilClosingBrace (acc : List Char) : List Char → Option (List Char × List Char)
  | [] => none
  | '}' :: rest => some (acc.reverse, rest)
  | char :: rest => takeUntilClosingBrace (char :: acc) rest

def splitAtComma (chars : List Char) : Option (List Char × List Char) :=
  let rec loop (acc : List Char) : List Char → Option (List Char × List Char)
    | [] => none
    | ',' :: rest => some (acc.reverse, rest)
    | char :: rest => loop (char :: acc) rest
  loop [] chars

def parseRangeQuant? (body : List Char) : Option PatternQuant := do
  match splitAtComma body with
  | none =>
      let count ← parseNatChars? body
      pure (.range count (some count))
  | some (minChars, maxChars) =>
      let min ← parseNatChars? minChars
      if maxChars.isEmpty then
        pure (.range min none)
      else
        let max ← parseNatChars? maxChars
        if max < min then none else pure (.range min (some max))

def parsePatternQuant : List Char → Option (PatternQuant × List Char)
  | '*' :: rest => some (.zeroOrMore, rest)
  | '+' :: rest => some (.oneOrMore, rest)
  | '?' :: rest => some (.optional, rest)
  | '{' :: rest => do
      let (body, remaining) ← takeUntilClosingBrace [] rest
      let quant ← parseRangeQuant? body
      pure (quant, remaining)
  | rest => some (.one, rest)

partial def parsePatternPieces (acc : List PatternPiece) : List Char →
    Option (List PatternPiece × Bool)
  | [] => some (acc.reverse, false)
  | '$' :: [] => some (acc.reverse, true)
  | chars => do
      let (atom, afterAtom) ← parsePatternAtom chars
      let (quant, afterQuant) ← parsePatternQuant afterAtom
      parsePatternPieces ({ atom, quant } :: acc) afterQuant

def compilePattern? (pattern : String) : Option CompiledPattern :=
  let chars := pattern.toList
  let (startAnchored, rest) :=
    match chars with
    | '^' :: rest => (true, rest)
    | _ => (false, chars)
  match parsePatternPieces [] rest with
  | some (pieces, endAnchored) => some { startAnchored, endAnchored, pieces }
  | none => none

partial def consumePatternAtomMatches (atom : PatternAtom) (chars : List Char) (fuel : Nat) :
    List (Nat × List Char) :=
  let base := [(0, chars)]
  match fuel, chars with
  | 0, _ => base
  | _ + 1, char :: rest =>
      if atomMatches atom char then
        base ++ (consumePatternAtomMatches atom rest fuel).map fun (count, remaining) =>
          (count + 1, remaining)
      else
        base
  | _, [] => base

def quantBounds (quant : PatternQuant) : Nat × Option Nat :=
  match quant with
  | .one => (1, some 1)
  | .zeroOrMore => (0, none)
  | .oneOrMore => (1, none)
  | .optional => (0, some 1)
  | .range min max => (min, max)

def remaindersAfterQuant (atom : PatternAtom) (quant : PatternQuant) (chars : List Char) :
    List (List Char) :=
  let (min, max?) := quantBounds quant
  consumePatternAtomMatches atom chars chars.length |>.filterMap fun (count, remaining) =>
    let underMax :=
      match max? with
      | some max => count <= max
      | none => true
    if min <= count && underMax then some remaining else none

partial def matchPatternPieces (pieces : List PatternPiece) (chars : List Char) : List (List Char) :=
  match pieces with
  | [] => [chars]
  | piece :: rest =>
      remaindersAfterQuant piece.atom piece.quant chars |>.flatMap fun remaining =>
        matchPatternPieces rest remaining

def suffixes (chars : List Char) : List (List Char) :=
  let rec loop : List Char → List (List Char)
    | [] => [[]]
    | current@(_ :: rest) => current :: loop rest
  loop chars

def compiledPatternMatches (compiled : CompiledPattern) (value : String) : Bool :=
  let candidates :=
    if compiled.startAnchored then [value.toList] else suffixes value.toList
  candidates.any fun candidate =>
    matchPatternPieces compiled.pieces candidate |>.any fun remaining =>
      if compiled.endAnchored then remaining.isEmpty else true

def patternMatches (pattern value : String) : Bool :=
  match compilePattern? pattern with
  | some compiled => compiledPatternMatches compiled value
  | none => true

def definedPropertyKeys (schema : Lean.Json) : List String :=
  propertySchemas schema |>.map Prod.fst

def stringBoundIssues (schema : Lean.Json) (value path : String) : List ValidationIssue :=
  let minIssues :=
    match natKeyword? schema "minLength" with
    | some minLength =>
        if value.length < minLength then [minLengthIssue path minLength] else []
    | none => []
  let maxIssues :=
    match natKeyword? schema "maxLength" with
    | some maxLength =>
        if value.length > maxLength then [maxLengthIssue path maxLength] else []
    | none => []
  let patternIssues :=
    match stringKeyword? schema "pattern" with
    | some pattern =>
        if patternMatches pattern value then [] else [patternIssue path pattern]
    | none => []
  minIssues ++ maxIssues ++ patternIssues

def objectBoundIssues (schema : Lean.Json) (fieldCount : Nat) (path : String) :
    List ValidationIssue :=
  let minIssues :=
    match natKeyword? schema "minProperties" with
    | some minProperties =>
        if fieldCount < minProperties then [minPropertiesIssue path minProperties] else []
    | none => []
  let maxIssues :=
    match natKeyword? schema "maxProperties" with
    | some maxProperties =>
        if fieldCount > maxProperties then [maxPropertiesIssue path maxProperties] else []
    | none => []
  minIssues ++ maxIssues

def arrayBoundIssues (schema : Lean.Json) (values : Array Lean.Json) (path : String) :
    List ValidationIssue :=
  let minIssues :=
    match natKeyword? schema "minItems" with
    | some minItems =>
        if values.size < minItems then [minItemsIssue path minItems] else []
    | none => []
  let maxIssues :=
    match natKeyword? schema "maxItems" with
    | some maxItems =>
        if values.size > maxItems then [maxItemsIssue path maxItems] else []
    | none => []
  let uniqueIssues :=
    match boolKeyword? schema "uniqueItems" with
    | some true =>
        if hasDuplicateJson values.toList then [uniqueItemsIssue path] else []
    | _ => []
  minIssues ++ maxIssues ++ uniqueIssues

def numberBoundIssues (schema : Lean.Json) (value : Lean.JsonNumber) (path : String) :
    List ValidationIssue :=
  let minimumIssues :=
    match numberKeyword? schema "minimum", boolKeyword? schema "exclusiveMinimum" with
    | some _, some true => []
    | some minimum, _ =>
        if Lean.JsonNumber.lt value minimum then [minimumIssue path minimum] else []
    | none, _ => []
  let maximumIssues :=
    match numberKeyword? schema "maximum", boolKeyword? schema "exclusiveMaximum" with
    | some _, some true => []
    | some maximum, _ =>
        if Lean.JsonNumber.lt maximum value then [maximumIssue path maximum] else []
    | none, _ => []
  let exclusiveMinimumIssues :=
    match numberKeyword? schema "exclusiveMinimum" with
    | some minimum =>
        if Lean.JsonNumber.lt minimum value then [] else [exclusiveMinimumIssue path minimum]
    | none =>
        match numberKeyword? schema "minimum", boolKeyword? schema "exclusiveMinimum" with
        | some minimum, some true =>
            if Lean.JsonNumber.lt minimum value then [] else [exclusiveMinimumIssue path minimum]
        | _, _ => []
  let exclusiveMaximumIssues :=
    match numberKeyword? schema "exclusiveMaximum" with
    | some maximum =>
        if Lean.JsonNumber.lt value maximum then [] else [exclusiveMaximumIssue path maximum]
    | none =>
        match numberKeyword? schema "maximum", boolKeyword? schema "exclusiveMaximum" with
        | some maximum, some true =>
            if Lean.JsonNumber.lt value maximum then [] else [exclusiveMaximumIssue path maximum]
        | _, _ => []
  minimumIssues ++ maximumIssues ++ exclusiveMinimumIssues ++ exclusiveMaximumIssues

partial def validateJsonAt (schema value : Lean.Json) (path : String := "root") :
    List ValidationIssue :=
  let schemaTypes := schemaTypes schema
  let typeIssues :=
    if schemaTypes.isEmpty || schemaTypes.any (matchesJsonType value) then
      []
    else
      [typeIssue path schemaTypes]
  let enumIssues :=
    match enumValues? schema with
    | some values =>
        if values.any (fun enumValue => enumValue == value) then [] else [enumIssue path]
    | none => []
  let constIssues :=
    match constValue? schema with
    | some expected => if expected == value then [] else [constIssue path]
    | none => []
  let scalarIssues :=
    match value with
    | .str text => stringBoundIssues schema text path
    | .num number => numberBoundIssues schema number path
    | _ => []
  let objectIssues :=
    match value with
    | .obj fields =>
        let fieldList := fields.toList
        let boundIssues := objectBoundIssues schema fieldList.length path
        let requiredIssues :=
          requiredKeys schema |>.filterMap fun key =>
            if fieldList.any (fun field => field.fst == key) then
              none
            else
              some (requiredIssue path key)
        let propertyIssues :=
          propertySchemas schema |>.flatMap fun (key, propertySchema) =>
            match fieldList.find? (fun field => field.fst == key) with
            | some (_, fieldValue) => validateJsonAt propertySchema fieldValue (pathChild path key)
            | none => []
        let additionalIssues :=
          match additionalProperties? schema with
          | some (Lean.Json.bool false) =>
              let definedKeys := definedPropertyKeys schema
              fieldList.filterMap fun (key, _) =>
                if definedKeys.contains key then none
                else some { path := pathChild path key, message := "additional property not allowed" }
          | some extraSchema@(.obj _) =>
              let definedKeys := definedPropertyKeys schema
              fieldList.flatMap fun (key, fieldValue) =>
                if definedKeys.contains key then []
                else validateJsonAt extraSchema fieldValue (pathChild path key)
          | _ => []
        boundIssues ++ requiredIssues ++ propertyIssues ++ additionalIssues
    | _ => []
  let arrayIssues :=
    match value with
    | .arr values =>
        let boundIssues := arrayBoundIssues schema values path
        let itemIssues :=
          match itemSchema? schema with
          | some itemSchema =>
              enumerateList values.toList |>.flatMap fun (index, item) =>
                validateJsonAt itemSchema item (pathIndex path index)
          | none =>
              let tupleSchemas := tupleItemSchemas schema
              if tupleSchemas.isEmpty then
                []
              else
                enumerateList values.toList |>.flatMap fun (index, item) =>
                  match tupleSchemas[index]? with
                  | some itemSchema => validateJsonAt itemSchema item (pathIndex path index)
                  | none => []
        let containsIssues :=
          match schemaObject? schema "contains" with
          | some containsSchema =>
              let matchCount :=
                enumerateList values.toList |>.foldl
                  (fun count (index, item) =>
                    if (validateJsonAt containsSchema item (pathIndex path index)).isEmpty then
                      count + 1
                    else
                      count)
                  0
              let minIssues :=
                match natKeyword? schema "minContains" with
                | some minContains =>
                    if matchCount < minContains then [minContainsIssue path minContains] else []
                | none =>
                    if matchCount == 0 then [containsIssue path] else []
              let maxIssues :=
                match natKeyword? schema "maxContains" with
                | some maxContains =>
                    if matchCount > maxContains then [maxContainsIssue path maxContains] else []
                | none => []
              minIssues ++ maxIssues
          | none => []
        boundIssues ++ itemIssues ++ containsIssues
    | _ => []
  let allOfIssues :=
    match schemaArray? schema "allOf" with
    | some schemas =>
        schemas.toList.flatMap fun nested => validateJsonAt nested value path
    | none => []
  let anyOfIssues :=
    match schemaArray? schema "anyOf" with
    | some schemas =>
        if schemas.any (fun nested => (validateJsonAt nested value path).isEmpty) then
          []
        else
          [anyOfIssue path]
    | none => []
  let oneOfIssues :=
    match schemaArray? schema "oneOf" with
    | some schemas =>
        let matchingSchemas :=
          schemas.toList.filter fun nested => (validateJsonAt nested value path).isEmpty
        if matchingSchemas.length == 1 then [] else [oneOfIssue path]
    | none => []
  let notIssues :=
    match schemaObject? schema "not" with
    | some nested =>
        if (validateJsonAt nested value path).isEmpty then [notIssue path] else []
    | none => []
  typeIssues ++ enumIssues ++ constIssues ++ scalarIssues ++ objectIssues ++ arrayIssues ++
    allOfIssues ++ anyOfIssues ++ oneOfIssues ++ notIssues

def validateJson (schema value : Lean.Json) : Except (List ValidationIssue) Lean.Json :=
  let coerced := coerceWithJsonSchema value schema
  match validateJsonAt schema coerced with
  | [] => .ok coerced
  | issues => .error issues

end LeanAgent.AI.Schema
