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
  minIssues ++ maxIssues

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
