import LeanAgent.AI.Api.Lazy
import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.OpenAICompletionsLazy

def openAICompletionsApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.Lazy.lazyApi (pure LeanAgent.AI.Providers.Streams.openAICompatibleStreams)

end LeanAgent.AI.Api.OpenAICompletionsLazy
