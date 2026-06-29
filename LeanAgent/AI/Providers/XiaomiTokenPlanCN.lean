import LeanAgent.AI.Providers.Catalog
import LeanAgent.Models

namespace LeanAgent.AI.Providers.XiaomiTokenPlanCN

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.AI.Providers.Catalog.createCatalogProvider LeanAgent.Models.xiaomiTokenPlanCNProviderInfo

end LeanAgent.AI.Providers.XiaomiTokenPlanCN
