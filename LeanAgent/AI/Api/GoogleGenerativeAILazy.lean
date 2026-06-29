import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.GoogleGenerativeAILazy

def googleGenerativeAIApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.Models.ProviderStreams.lazy (pure LeanAgent.AI.Providers.Streams.googleGenerativeAIStreams)

end LeanAgent.AI.Api.GoogleGenerativeAILazy
