import LeanAgent.AI.Providers.Catalog
import LeanAgent.Models

namespace LeanAgent.AI.Providers.OpenAI

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.AI.Providers.Catalog.createCatalogProvider LeanAgent.Models.openAIProviderInfo

end LeanAgent.AI.Providers.OpenAI
