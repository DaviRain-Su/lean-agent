import LeanAgent.AI.Providers.Catalog
import LeanAgent.Models

namespace LeanAgent.AI.Providers.OpenCodeGo

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.AI.Providers.Catalog.createCatalogProvider LeanAgent.Models.opencodeGoProviderInfo

end LeanAgent.AI.Providers.OpenCodeGo
