import LeanAgent.Models

namespace LeanAgent.AI.Providers.Together

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.togetherProviderInfo

end LeanAgent.AI.Providers.Together
