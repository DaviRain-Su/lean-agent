import LeanAgent.Models

namespace LeanAgent.AI.Providers.MoonshotAI

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.moonshotAIProviderInfo

end LeanAgent.AI.Providers.MoonshotAI
