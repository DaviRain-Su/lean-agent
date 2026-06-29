import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.AzureOpenAIResponsesLazy

def azureOpenAIResponsesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.Models.ProviderStreams.lazy (pure LeanAgent.AI.Providers.Streams.azureOpenAIResponsesStreams)

end LeanAgent.AI.Api.AzureOpenAIResponsesLazy
