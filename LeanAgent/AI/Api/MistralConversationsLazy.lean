import LeanAgent.AI.Api.Lazy
import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.MistralConversationsLazy

def mistralConversationsApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.Lazy.lazyApi (pure LeanAgent.AI.Providers.Streams.mistralConversationsStreams)

end LeanAgent.AI.Api.MistralConversationsLazy
