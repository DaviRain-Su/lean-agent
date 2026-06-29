import LeanAgent.Models

namespace LeanAgent.AI.Providers.OpenCodeGo

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.opencodeGoProviderInfo

end LeanAgent.AI.Providers.OpenCodeGo
