import LeanAgent.Models

namespace LeanAgent.AI.Providers.AzureOpenAIResponses

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.azureOpenAIResponsesProviderInfo

end LeanAgent.AI.Providers.AzureOpenAIResponses
