import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.OpenAIResponsesLazy

def openAIResponsesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.Models.ProviderStreams.lazy (pure LeanAgent.AI.Providers.Streams.openAIResponsesStreams)

end LeanAgent.AI.Api.OpenAIResponsesLazy
