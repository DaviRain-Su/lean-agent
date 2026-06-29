import LeanAgent.AI.Providers.Catalog
import LeanAgent.Models

namespace LeanAgent.AI.Providers.AzureOpenAIResponses

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.AI.Providers.Catalog.createCatalogProvider LeanAgent.Models.azureOpenAIResponsesProviderInfo

end LeanAgent.AI.Providers.AzureOpenAIResponses
