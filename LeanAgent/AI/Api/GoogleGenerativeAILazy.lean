import LeanAgent.AI.Api.Lazy
import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Api.GoogleGenerativeAILazy

def googleGenerativeAIApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.Lazy.lazyApi (pure LeanAgent.AI.Providers.Streams.googleGenerativeAIStreams)

end LeanAgent.AI.Api.GoogleGenerativeAILazy
