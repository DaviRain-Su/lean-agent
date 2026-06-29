import LeanAgent.AI.Api.OpenRouterImages
import LeanAgent.AI.Types

namespace LeanAgent.AI.Images.Models

def openRouterProviderId : String := LeanAgent.AI.Api.OpenRouterImages.providerId
def openRouterImagesApi : String := LeanAgent.AI.Api.OpenRouterImages.api
def openRouterBaseUrl : String := LeanAgent.AI.Api.OpenRouterImages.baseUrl

def cost (input output cacheRead cacheWrite : Float) : LeanAgent.AI.UsageCost :=
  { input := input
    output := output
    cacheRead := cacheRead
    cacheWrite := cacheWrite
  }

def flux2Flex : LeanAgent.AI.ImagesModel :=
  { id := "black-forest-labs/flux.2-flex"
    name := "Black Forest Labs: FLUX.2 Flex"
    api := openRouterImagesApi
    provider := openRouterProviderId
    baseUrl := openRouterBaseUrl
    input := #["text", "image"]
    output := #["image"]
  }

def gemini25FlashImage : LeanAgent.AI.ImagesModel :=
  { id := "google/gemini-2.5-flash-image"
    name := "Google: Nano Banana (Gemini 2.5 Flash Image)"
    api := openRouterImagesApi
    provider := openRouterProviderId
    baseUrl := openRouterBaseUrl
    input := #["image", "text"]
    output := #["image", "text"]
    cost := cost 0.3 2.5 0.03 0.08333333333333334
  }

def openAIGptImage1 : LeanAgent.AI.ImagesModel :=
  { id := "openai/gpt-image-1"
    name := "OpenAI: GPT Image 1"
    api := openRouterImagesApi
    provider := openRouterProviderId
    baseUrl := openRouterBaseUrl
    input := #["text", "image"]
    output := #["image"]
    cost := cost 5.0 15.0 1.25 0.0
  }

def openRouterAuto : LeanAgent.AI.ImagesModel :=
  { id := "openrouter/auto"
    name := "OpenRouter: Auto"
    api := openRouterImagesApi
    provider := openRouterProviderId
    baseUrl := openRouterBaseUrl
    input := #["text", "image"]
    output := #["image", "text"]
  }

def openRouterImageModels : Array LeanAgent.AI.ImagesModel :=
  #[flux2Flex, gemini25FlashImage, openAIGptImage1, openRouterAuto]

def allImageModels : Array LeanAgent.AI.ImagesModel :=
  openRouterImageModels

def getImageProviders : Array String :=
  #[openRouterProviderId]

def getImageModels (provider : String) : Array LeanAgent.AI.ImagesModel :=
  if provider == openRouterProviderId then
    openRouterImageModels
  else
    #[]

def getImageModel? (provider modelId : String) : Option LeanAgent.AI.ImagesModel :=
  (getImageModels provider).find? fun model => model.id == modelId

end LeanAgent.AI.Images.Models
