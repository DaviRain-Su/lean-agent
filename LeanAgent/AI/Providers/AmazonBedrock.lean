import LeanAgent.Models

namespace LeanAgent.AI.Providers.AmazonBedrock

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.amazonBedrockProviderInfo

end LeanAgent.AI.Providers.AmazonBedrock
