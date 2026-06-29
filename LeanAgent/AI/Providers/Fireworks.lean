import LeanAgent.Models

namespace LeanAgent.AI.Providers.Fireworks

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.fireworksProviderInfo

end LeanAgent.AI.Providers.Fireworks
