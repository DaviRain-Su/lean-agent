import LeanAgent.AI.Api.Lazy
import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.BedrockConverseStreamLazy

initialize bedrockProviderModuleOverride :
    IO.Ref (Option LeanAgent.Models.ProviderStreams) ← IO.mkRef none

def setBedrockProviderModule (streams : LeanAgent.Models.ProviderStreams) : IO Unit :=
  bedrockProviderModuleOverride.set (some streams)

def resetBedrockProviderModule : IO Unit :=
  bedrockProviderModuleOverride.set none

def bedrockConverseStreamApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.Lazy.lazyApi do
    match ← bedrockProviderModuleOverride.get with
    | some streams => pure streams
    | none => pure LeanAgent.AI.Providers.Streams.bedrockConverseStreamStreams

end LeanAgent.AI.Api.BedrockConverseStreamLazy
