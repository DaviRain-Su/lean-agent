import LeanAgent.Models

namespace LeanAgent.AI.Providers.XiaomiTokenPlanCN

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.xiaomiTokenPlanCNProviderInfo

end LeanAgent.AI.Providers.XiaomiTokenPlanCN
