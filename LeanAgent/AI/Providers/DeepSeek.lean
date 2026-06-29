import LeanAgent.Models

namespace LeanAgent.AI.Providers.DeepSeek

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.deepSeekProviderInfo

end LeanAgent.AI.Providers.DeepSeek
