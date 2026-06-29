import LeanAgent.AI.Providers.Catalog
import LeanAgent.Models

namespace LeanAgent.AI.Providers.XiaomiTokenPlanAMS

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.AI.Providers.Catalog.createCatalogProvider LeanAgent.Models.xiaomiTokenPlanAMSProviderInfo

end LeanAgent.AI.Providers.XiaomiTokenPlanAMS
