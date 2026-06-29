import LeanAgent.Models

namespace LeanAgent.AI.Providers.ZAICodingCN

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.zaiCodingCNProviderInfo

end LeanAgent.AI.Providers.ZAICodingCN
