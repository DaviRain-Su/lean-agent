import LeanAgent.AI.Providers.Catalog
import LeanAgent.Models

namespace LeanAgent.AI.Providers.XiaomiTokenPlanSGP

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.AI.Providers.Catalog.createCatalogProvider LeanAgent.Models.xiaomiTokenPlanSGPProviderInfo

end LeanAgent.AI.Providers.XiaomiTokenPlanSGP
