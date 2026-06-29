import LeanAgent.AI.Providers.Catalog
import LeanAgent.Models

namespace LeanAgent.AI.Providers.ZAI

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.AI.Providers.Catalog.createCatalogProvider LeanAgent.Models.zaiProviderInfo

end LeanAgent.AI.Providers.ZAI
