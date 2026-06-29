import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.OpenAICodexResponsesLazy

def openAICodexResponsesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.Models.ProviderStreams.lazy (pure LeanAgent.AI.Providers.Streams.openAICodexResponsesStreams)

end LeanAgent.AI.Api.OpenAICodexResponsesLazy
