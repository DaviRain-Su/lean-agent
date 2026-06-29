import LeanAgent.AI.Api.OpenRouterImages
import LeanAgent.AI.Images

namespace LeanAgent.AI.Api.OpenRouterImagesLazy

def openRouterImagesApi : LeanAgent.AI.Images.ProviderImages :=
  LeanAgent.AI.Images.ProviderImages.lazy
    (pure
      { generateImages := fun model context options =>
          LeanAgent.AI.Api.OpenRouterImages.generateImages model context options
      })

end LeanAgent.AI.Api.OpenRouterImagesLazy
