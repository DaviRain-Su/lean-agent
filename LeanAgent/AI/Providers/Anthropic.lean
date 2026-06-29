import LeanAgent.Models

namespace LeanAgent.AI.Providers.Anthropic

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.anthropicProviderInfo

end LeanAgent.AI.Providers.Anthropic
