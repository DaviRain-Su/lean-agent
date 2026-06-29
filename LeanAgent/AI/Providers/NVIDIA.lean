import LeanAgent.Models

namespace LeanAgent.AI.Providers.NVIDIA

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createCatalogProvider LeanAgent.Models.nvidiaProviderInfo

end LeanAgent.AI.Providers.NVIDIA
