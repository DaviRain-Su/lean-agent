import LeanAgent.AI.Api.OpenRouterImages
import LeanAgent.AI.Images.Registry

namespace LeanAgent.AI.Providers.OpenRouterImages

def provider : LeanAgent.AI.Images.ImagesApiProvider :=
  { api := LeanAgent.AI.Api.OpenRouterImages.api
    generateImages := fun model context options =>
      LeanAgent.AI.Api.OpenRouterImages.generateImages model context options
  }

def register : IO Unit :=
  LeanAgent.AI.Images.registerImagesApiProvider provider

def registerBuiltIn : IO Unit :=
  LeanAgent.AI.Images.registerBuiltInImagesApiProvider provider

initialize registerBuiltInProvider : Unit ← registerBuiltIn

end LeanAgent.AI.Providers.OpenRouterImages
