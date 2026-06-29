import LeanAgent.Models

namespace LeanAgent.AI.Providers.XAI

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.xaiProviderInfo

end LeanAgent.AI.Providers.XAI
