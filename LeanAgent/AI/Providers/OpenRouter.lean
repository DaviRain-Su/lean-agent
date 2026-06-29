import LeanAgent.Models

namespace LeanAgent.AI.Providers.OpenRouter

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.openRouterProviderInfo

end LeanAgent.AI.Providers.OpenRouter
