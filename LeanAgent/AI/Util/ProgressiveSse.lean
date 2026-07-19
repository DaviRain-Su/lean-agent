import LeanAgent.AI.Util.SSE
import LeanAgent.Http

namespace LeanAgent.AI.Util.ProgressiveSse

/--
Run a progressive body producer while feeding completed SSE events to `onEvent`.

`produce` must invoke its `onChunk` callback for body bytes (e.g. via
`Http.postJsonResponseProgressive`). Returns the full body string from `produce`
plus the number of completed SSE events (including `finish` flush).

If `onEvent` returns an error, further events are skipped; the error is returned
alongside the body so callers can fall back to batch parse.
-/
def feedWhile
    (produce : (String → IO Unit) → IO String)
    (onEvent : LeanAgent.AI.Util.SSE.Event → IO (Except String Unit)) :
    IO (String × Nat × Option String) := do
  let sseRef ← IO.mkRef ({} : LeanAgent.AI.Util.SSE.Parser)
  let countRef ← IO.mkRef (0 : Nat)
  let errRef ← IO.mkRef (none : Option String)
  let handleEvents (events : Array LeanAgent.AI.Util.SSE.Event) : IO Unit := do
    if (← errRef.get).isSome then
      pure ()
    else
      for event in events do
        if (← errRef.get).isSome then
          pure ()
        else
          countRef.modify (· + 1)
          match ← onEvent event with
          | .error err => errRef.set (some err)
          | .ok () => pure ()
  let body ← produce fun chunk => do
    if (← errRef.get).isSome then
      pure ()
    else
      let p ← sseRef.get
      let (p', events) := LeanAgent.AI.Util.SSE.feed p chunk
      sseRef.set p'
      handleEvents events
  if (← errRef.get).isNone then
    handleEvents (LeanAgent.AI.Util.SSE.finish (← sseRef.get))
  pure (body, ← countRef.get, ← errRef.get)

/-- Progressive JSON POST that feeds completed SSE events. -/
def postJsonFeed
    (config : LeanAgent.Http.JsonPostConfig)
    (payload : String)
    (onEvent : LeanAgent.AI.Util.SSE.Event → IO (Except String Unit)) :
    IO (LeanAgent.Http.JsonPostResponse × Nat × Option String) := do
  let sseRef ← IO.mkRef ({} : LeanAgent.AI.Util.SSE.Parser)
  let countRef ← IO.mkRef (0 : Nat)
  let errRef ← IO.mkRef (none : Option String)
  let handleEvents (events : Array LeanAgent.AI.Util.SSE.Event) : IO Unit := do
    if (← errRef.get).isSome then
      pure ()
    else
      for event in events do
        if (← errRef.get).isSome then
          pure ()
        else
          countRef.modify (· + 1)
          match ← onEvent event with
          | .error err => errRef.set (some err)
          | .ok () => pure ()
  let response ← LeanAgent.Http.postJsonResponseProgressive config payload fun chunk => do
    if (← errRef.get).isSome then
      pure ()
    else
      let p ← sseRef.get
      let (p', events) := LeanAgent.AI.Util.SSE.feed p chunk
      sseRef.set p'
      handleEvents events
  if (← errRef.get).isNone then
    handleEvents (LeanAgent.AI.Util.SSE.finish (← sseRef.get))
  pure (response, ← countRef.get, ← errRef.get)

end LeanAgent.AI.Util.ProgressiveSse
