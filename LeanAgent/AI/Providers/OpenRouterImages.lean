import LeanAgent.AI.Api.OpenRouterImages
import LeanAgent.AI.Auth
import LeanAgent.AI.Images
import LeanAgent.AI.Images.Models
import LeanAgent.AI.Images.Registry

namespace LeanAgent.AI.Providers.OpenRouterImages

def apiProvider : LeanAgent.AI.Images.ImagesApiProvider :=
  { api := LeanAgent.AI.Api.OpenRouterImages.api
    generateImages := fun model context options =>
      LeanAgent.AI.Api.OpenRouterImages.generateImages model context options
  }

def providerImages : LeanAgent.AI.Images.ProviderImages :=
  { generateImages := fun model context options =>
      LeanAgent.AI.Api.OpenRouterImages.generateImages model context options
  }

def auth : LeanAgent.AI.Auth.ProviderAuth :=
  { apiKey := some (LeanAgent.AI.Auth.envApiKeyAuth "OpenRouter API key" #[LeanAgent.AI.Api.OpenRouterImages.apiKeyEnv]) }

def openRouterImagesProvider : IO LeanAgent.AI.Images.ImagesProvider :=
  LeanAgent.AI.Images.createImagesProvider
    { id := LeanAgent.AI.Api.OpenRouterImages.providerId
      name := some "OpenRouter"
      auth := auth
      models := LeanAgent.AI.Images.Models.openRouterImageModels
      api := providerImages
    }

def register : IO Unit :=
  LeanAgent.AI.Images.registerImagesApiProvider apiProvider

def registerBuiltIn : IO Unit :=
  LeanAgent.AI.Images.registerBuiltInImagesApiProvider apiProvider

initialize registerBuiltInProvider : Unit ← registerBuiltIn

end LeanAgent.AI.Providers.OpenRouterImages
