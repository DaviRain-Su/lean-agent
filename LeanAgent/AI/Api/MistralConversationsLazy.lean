import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.MistralConversationsLazy

def mistralConversationsApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.Models.ProviderStreams.lazy (pure LeanAgent.AI.Providers.Streams.mistralConversationsStreams)

end LeanAgent.AI.Api.MistralConversationsLazy
