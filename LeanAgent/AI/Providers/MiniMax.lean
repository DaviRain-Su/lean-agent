import LeanAgent.AI.Providers.Catalog
import LeanAgent.Models

namespace LeanAgent.AI.Providers.MiniMax

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.AI.Providers.Catalog.createCatalogProvider LeanAgent.Models.minimaxProviderInfo

end LeanAgent.AI.Providers.MiniMax
