import LeanAgent.Models

namespace LeanAgent.AI.Providers.OpenAICodex

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.openAICodexProviderInfo

end LeanAgent.AI.Providers.OpenAICodex
