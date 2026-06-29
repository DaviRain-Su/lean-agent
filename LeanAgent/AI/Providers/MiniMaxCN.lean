import LeanAgent.Models

namespace LeanAgent.AI.Providers.MiniMaxCN

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.minimaxCNProviderInfo

end LeanAgent.AI.Providers.MiniMaxCN
