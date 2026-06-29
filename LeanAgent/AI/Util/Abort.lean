namespace LeanAgent.AI.Util.Abort

def requestAbortedMessage : String := "Request was aborted"

structure AbortSignal where
  isAborted : IO Bool
  message : String := requestAbortedMessage

structure CombinedAbortSignal where
  signal : Option AbortSignal := none
  cleanup : IO Unit := pure ()

def isAborted (signal? : Option AbortSignal) : IO Bool := do
  match signal? with
  | some signal => signal.isAborted
  | none => pure false

def throwIfAborted (signal? : Option AbortSignal) (message : Option String := none) : IO Unit := do
  match signal? with
  | some signal =>
      if ← signal.isAborted then
        throw (IO.userError (message.getD signal.message))
      else
        pure ()
  | none => pure ()

def combineAbortSignals (signals : Array (Option AbortSignal)) : CombinedAbortSignal :=
  let activeSignals := signals.filterMap id
  match activeSignals.size with
  | 0 => { cleanup := pure () }
  | 1 => { signal := activeSignals[0]?, cleanup := pure () }
  | _ =>
      let message :=
        match activeSignals[0]? with
        | some signal => signal.message
        | none => requestAbortedMessage
      { signal :=
          some
            { isAborted := do
                for signal in activeSignals do
                  if ← signal.isAborted then
                    return true
                pure false
              message := message
            }
        cleanup := pure ()
      }

partial def sleep
    (sleepMs : Nat → IO Unit)
    (totalMs : Nat)
    (signal? : Option AbortSignal := none)
    (chunkMs : Nat := 50)
    (message : Option String := none) : IO Unit := do
  if totalMs == 0 then
    pure ()
  else
    match signal? with
    | none => sleepMs totalMs
    | some _ =>
        let chunkMs := Nat.max 1 chunkMs
        let rec loop (remaining : Nat) : IO Unit := do
          throwIfAborted signal? message
          if remaining == 0 then
            pure ()
          else
            let next := Nat.min remaining chunkMs
            sleepMs next
            loop (remaining - next)
        loop totalMs

def isAbortErrorMessage
    (message : String)
    (abortMessage : String := requestAbortedMessage) : Bool :=
  message.contains abortMessage

end LeanAgent.AI.Util.Abort
