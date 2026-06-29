import LeanAgent.Models

namespace LeanAgent.AI.Providers.Cerebras

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.cerebrasProviderInfo

end LeanAgent.AI.Providers.Cerebras
