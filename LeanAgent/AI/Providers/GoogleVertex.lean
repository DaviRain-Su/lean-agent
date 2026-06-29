import LeanAgent.Models

namespace LeanAgent.AI.Providers.GoogleVertex

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.googleVertexProviderInfo

end LeanAgent.AI.Providers.GoogleVertex
