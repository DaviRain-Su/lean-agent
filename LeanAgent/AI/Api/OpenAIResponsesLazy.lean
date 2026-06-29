import LeanAgent.AI.Api.Lazy
import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.OpenAIResponsesLazy

def openAIResponsesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.Lazy.lazyApi (pure LeanAgent.AI.Providers.Streams.openAIResponsesStreams)

end LeanAgent.AI.Api.OpenAIResponsesLazy
