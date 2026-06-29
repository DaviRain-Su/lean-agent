import LeanAgent.AI.Api.Lazy
import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.AnthropicMessagesLazy

def anthropicMessagesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.Lazy.lazyApi (pure LeanAgent.AI.Providers.Streams.anthropicMessagesStreams)

end LeanAgent.AI.Api.AnthropicMessagesLazy
