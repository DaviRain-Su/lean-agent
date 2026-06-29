import LeanAgent.AI.EventStream
import LeanAgent.AI.Types

namespace LeanAgent.AI.Api.Lazy

def setupErrorMessage (model : LeanAgent.AI.ModelRef) (message : String) (timestamp : Nat) :
    LeanAgent.AI.AssistantMessage :=
  { content := #[]
    api := model.api
    provider := model.provider
    model := model.id
    usage := LeanAgent.AI.Usage.empty
    stopReason := .error
    errorMessage := some message
    timestamp := timestamp
  }

def setupErrorStream (model : LeanAgent.AI.ModelRef) (message : String) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  let timestamp ← IO.monoMsNow
  pure (LeanAgent.AI.fromMessage (setupErrorMessage model message timestamp))

def lazyStream
    (model : LeanAgent.AI.ModelRef)
    (setup : IO LeanAgent.AI.AssistantMessageEventStream) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  try
    setup
  catch err =>
    setupErrorStream model err.toString

end LeanAgent.AI.Api.Lazy
