import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.AnthropicMessagesLazy

def anthropicMessagesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.Models.ProviderStreams.lazy (pure LeanAgent.AI.Providers.Streams.anthropicMessagesStreams)

end LeanAgent.AI.Api.AnthropicMessagesLazy
