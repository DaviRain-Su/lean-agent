import LeanAgent.AI.Providers.Catalog
import LeanAgent.Models

namespace LeanAgent.AI.Providers.VercelAIGateway

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.AI.Providers.Catalog.createCatalogProvider LeanAgent.Models.vercelAIGatewayProviderInfo

end LeanAgent.AI.Providers.VercelAIGateway
