import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.GoogleVertexLazy

def googleVertexApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.Models.ProviderStreams.lazy (pure LeanAgent.AI.Providers.Streams.googleVertexStreams)

end LeanAgent.AI.Api.GoogleVertexLazy
