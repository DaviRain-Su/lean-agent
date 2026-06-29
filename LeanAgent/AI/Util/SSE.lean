namespace LeanAgent.AI.Util.SSE

structure Event where
  data : String
deriving BEq, Repr

def stripTrailingCR (line : String) : String :=
  match line.toList.reverse with
  | '\r' :: rest => String.ofList rest.reverse
  | _ => line

def dataLine? (line : String) : Option String :=
  if line.startsWith ":" then
    none
  else if line.startsWith "data:" then
    let value := line.drop 5 |>.toString
    if value.startsWith " " then
      some (value.drop 1 |>.toString)
    else
      some value
  else
    none

def flush (pending : Array String) (events : Array Event) : Array Event :=
  if pending.isEmpty then
    events
  else
    events.push { data := String.intercalate "\n" pending.toList }

def parseLines : List String → Array String → Array Event → Array Event
  | [], pending, events => flush pending events
  | rawLine :: rest, pending, events =>
      let line := stripTrailingCR rawLine
      if line.isEmpty then
        parseLines rest #[] (flush pending events)
      else
        match dataLine? line with
        | some value => parseLines rest (pending.push value) events
        | none => parseLines rest pending events

def parse (raw : String) : Array Event :=
  parseLines (raw.splitOn "\n") #[] #[]

end LeanAgent.AI.Util.SSE
