import LeanAgent.Models

namespace LeanAgent.AI.Providers.KimiCoding

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.kimiCodingProviderInfo

end LeanAgent.AI.Providers.KimiCoding
