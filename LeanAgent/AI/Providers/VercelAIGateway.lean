import LeanAgent.Models

namespace LeanAgent.AI.Providers.VercelAIGateway

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.vercelAIGatewayProviderInfo

end LeanAgent.AI.Providers.VercelAIGateway
