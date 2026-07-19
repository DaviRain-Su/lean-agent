import Lean

/-!
# JSON comment strip (Pi `utils/json.ts` stripJsonComments)
-/

namespace LeanAgent.CodingAgent.Utils.JsonComments

/--
Strip `//` line comments and trailing commas before `}`/`]`, leaving string
literals untouched (Pi `stripJsonComments` offline subset).
-/
def stripJsonComments (input : String) : String :=
  Id.run do
    let chars := input.toList.toArray
    let mut out : Array Char := #[]
    let mut i : Nat := 0
    let mut inString := false
    let mut escape := false
    while i < chars.size do
      let c := chars[i]!
      if inString then
        out := out.push c
        if escape then
          escape := false
        else if c == '\\' then
          escape := true
        else if c == '"' then
          inString := false
        i := i + 1
      else if c == '"' then
        inString := true
        out := out.push c
        i := i + 1
      else if c == '/' && i + 1 < chars.size && chars[i + 1]! == '/' then
        -- skip to end of line
        i := i + 2
        while i < chars.size && chars[i]! != '\n' do
          i := i + 1
      else if c == ',' then
        -- trailing comma before } or ]
        let mut j := i + 1
        while j < chars.size && (chars[j]! == ' ' || chars[j]! == '\t' || chars[j]! == '\n' || chars[j]! == '\r') do
          j := j + 1
        if j < chars.size && (chars[j]! == '}' || chars[j]! == ']') then
          i := i + 1 -- drop comma
        else
          out := out.push c
          i := i + 1
      else
        out := out.push c
        i := i + 1
    pure (String.ofList out.toList)

end LeanAgent.CodingAgent.Utils.JsonComments
