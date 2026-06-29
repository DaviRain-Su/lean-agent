import LeanAgent.Models

namespace LeanAgent.AI.Providers.XiaomiTokenPlanAMS

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.xiaomiTokenPlanAMSProviderInfo

end LeanAgent.AI.Providers.XiaomiTokenPlanAMS
