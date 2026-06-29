import LeanAgent.AI.Api.LazyBase
import LeanAgent.Models.Core

namespace LeanAgent.AI.Api.Lazy

def lazyApi (load : IO LeanAgent.Models.ProviderStreams) : LeanAgent.Models.ProviderStreams :=
  LeanAgent.Models.ProviderStreams.lazy load

end LeanAgent.AI.Api.Lazy
