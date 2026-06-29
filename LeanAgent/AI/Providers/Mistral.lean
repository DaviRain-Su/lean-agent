import LeanAgent.Models

namespace LeanAgent.AI.Providers.Mistral

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.mistralProviderInfo

end LeanAgent.AI.Providers.Mistral
