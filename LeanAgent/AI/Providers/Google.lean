import LeanAgent.Models

namespace LeanAgent.AI.Providers.Google

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.googleProviderInfo

end LeanAgent.AI.Providers.Google
