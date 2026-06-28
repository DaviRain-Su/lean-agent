import Lean

namespace LeanAgent.Json

abbrev J := Lean.Json

def obj (fields : List (String × J)) : J :=
  Lean.Json.mkObj fields

def arr (items : Array J) : J :=
  Lean.Json.arr items

def str (value : String) : J :=
  Lean.Json.str value

def bool (value : Bool) : J :=
  Lean.Json.bool value

def nat (value : Nat) : J :=
  Lean.Json.num (Lean.JsonNumber.fromNat value)

def null : J :=
  Lean.Json.null

def optVal? (json : J) (key : String) : Option J :=
  match json.getObjVal? key with
  | .ok value => some value
  | .error _ => none

def requiredString (json : J) (key : String) : Except String String := do
  (← json.getObjVal? key).getStr?

def optionalString (json : J) (key : String) : Except String (Option String) :=
  match optVal? json key with
  | none => pure none
  | some value => some <$> value.getStr?

def optionalNat (json : J) (key : String) : Except String (Option Nat) :=
  match optVal? json key with
  | none => pure none
  | some value => some <$> value.getNat?

def optionalBool (json : J) (key : String) : Except String (Option Bool) :=
  match optVal? json key with
  | none => pure none
  | some value => some <$> value.getBool?

def parseObjectString (raw : String) : Except String J := do
  let parsed ← Lean.Json.parse raw
  let _ ← parsed.getObj?
  pure parsed

end LeanAgent.Json
