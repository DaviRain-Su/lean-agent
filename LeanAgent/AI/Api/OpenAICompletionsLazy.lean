import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.OpenAICompletionsLazy

def openAICompletionsApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.Models.ProviderStreams.lazy (pure LeanAgent.AI.Providers.Streams.openAICompatibleStreams)

end LeanAgent.AI.Api.OpenAICompletionsLazy
