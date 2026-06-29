import LeanAgent.Models

namespace LeanAgent.AI.Providers.Groq

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.groqProviderInfo

end LeanAgent.AI.Providers.Groq
