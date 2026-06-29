import LeanAgent.AI.Api.Lazy
import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.AzureOpenAIResponsesLazy

def azureOpenAIResponsesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.Lazy.lazyApi (pure LeanAgent.AI.Providers.Streams.azureOpenAIResponsesStreams)

end LeanAgent.AI.Api.AzureOpenAIResponsesLazy
