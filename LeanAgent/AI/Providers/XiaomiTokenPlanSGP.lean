import LeanAgent.Models

namespace LeanAgent.AI.Providers.XiaomiTokenPlanSGP

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.xiaomiTokenPlanSGPProviderInfo

end LeanAgent.AI.Providers.XiaomiTokenPlanSGP
