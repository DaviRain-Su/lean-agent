import LeanAgent.Models

namespace LeanAgent.AI.Providers.Xiaomi

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.xiaomiProviderInfo

end LeanAgent.AI.Providers.Xiaomi
