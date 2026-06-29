import LeanAgent.Models

namespace LeanAgent.AI.Providers.ZAI

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.zaiProviderInfo

end LeanAgent.AI.Providers.ZAI
