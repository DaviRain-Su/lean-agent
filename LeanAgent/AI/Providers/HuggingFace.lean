import LeanAgent.Models

namespace LeanAgent.AI.Providers.HuggingFace

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.huggingFaceProviderInfo

end LeanAgent.AI.Providers.HuggingFace
