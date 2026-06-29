import LeanAgent.Models

namespace LeanAgent.AI.Providers.OpenCode

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.opencodeProviderInfo

end LeanAgent.AI.Providers.OpenCode
