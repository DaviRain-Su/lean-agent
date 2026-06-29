import LeanAgent.AI.Api.Lazy
import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.OpenAICodexResponsesLazy

def openAICodexResponsesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.Lazy.lazyApi (pure LeanAgent.AI.Providers.Streams.openAICodexResponsesStreams)

end LeanAgent.AI.Api.OpenAICodexResponsesLazy
