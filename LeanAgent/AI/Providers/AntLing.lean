import LeanAgent.Models

namespace LeanAgent.AI.Providers.AntLing

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.antLingProviderInfo

end LeanAgent.AI.Providers.AntLing
