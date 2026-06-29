import LeanAgent.Models

namespace LeanAgent.AI.Providers.MoonshotAICN

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.moonshotAICNProviderInfo

end LeanAgent.AI.Providers.MoonshotAICN
