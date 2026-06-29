import LeanAgent.Models

namespace LeanAgent.AI.Providers.MiniMax

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.minimaxProviderInfo

end LeanAgent.AI.Providers.MiniMax
