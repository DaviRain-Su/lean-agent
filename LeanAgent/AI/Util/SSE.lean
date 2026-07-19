namespace LeanAgent.AI.Util.SSE

structure Event where
  data : String
deriving BEq, Repr, Inhabited

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

/-! Incremental SSE parser for progressive HTTP body chunks. -/

/--
Stateful SSE parser. Feed arbitrary body chunks as they arrive; completed
events (delimited by blank lines) are returned from `feed`. Call `finish` after
the transfer ends to flush any trailing event without a final blank line.
-/
structure Parser where
  lineBuf : String := ""
  pendingData : Array String := #[]
deriving Inhabited

private def foldCompleteLines
    (pending : Array String)
    (events : Array Event) :
    List String → Array String × Array Event
  | [] => (pending, events)
  | rawLine :: rest =>
      let line := stripTrailingCR rawLine
      if line.isEmpty then
        foldCompleteLines #[] (flush pending events) rest
      else
        match dataLine? line with
        | some value => foldCompleteLines (pending.push value) events rest
        | none => foldCompleteLines pending events rest

/--
Feed newly arrived body bytes. Returns completed SSE events (may be empty when
the chunk only contains a partial line).

Note: `splitOn "\n"` leaves a trailing empty string when the input ends with
`\\n`. That artifact is *not* an SSE blank line — only an interior empty part
(from `\\n\\n`) is an event boundary.
-/
def feed (p : Parser) (chunk : String) : Parser × Array Event :=
  if chunk.isEmpty then
    (p, #[])
  else
    let combined := p.lineBuf ++ chunk
    let parts := combined.splitOn "\n"
    -- Always drop the last split segment: it is either an incomplete line
    -- (no trailing newline) or the empty split artifact of a trailing newline.
    match parts.reverse with
    | [] => (p, #[])
    | last :: completeRev =>
        let completeLines := completeRev.reverse
        let (pending, events) := foldCompleteLines p.pendingData #[] completeLines
        let lineBuf := if combined.endsWith "\n" then "" else last
        ({ lineBuf := lineBuf, pendingData := pending }, events)

/--
Flush remaining buffered line / data fields after the transfer completes.
Matches the batch `parse` end behavior (flush pending multi-line data).
-/
def finish (p : Parser) : Array Event :=
  let (p, events) :=
    if p.lineBuf.isEmpty then
      (p, #[])
    else
      -- Treat leftover as a complete line without requiring a trailing newline.
      feed { lineBuf := "", pendingData := p.pendingData } (p.lineBuf ++ "\n")
  flush p.pendingData events

/-- Convenience: feed all chunks then finish; should match `parse` on the concat. -/
def parseIncremental (chunks : Array String) : Array Event :=
  let (p, mid) :=
    chunks.foldl
      (fun (acc : Parser × Array Event) chunk =>
        let (p, events) := feed acc.1 chunk
        (p, acc.2 ++ events))
      (({} : Parser), #[])
  mid ++ finish p

end LeanAgent.AI.Util.SSE
