import LeanAgent.Models

namespace LeanAgent.AI.Providers.OpenAI

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.openAIProviderInfo

end LeanAgent.AI.Providers.OpenAI
