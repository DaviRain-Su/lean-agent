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

def openRouterModel
    (id name : String)
    (input output : Array String)
    (modelCost : LeanAgent.AI.UsageCost := {}) : LeanAgent.AI.ImagesModel :=
  { id := id
    name := name
    api := openRouterImagesApi
    provider := openRouterProviderId
    baseUrl := openRouterBaseUrl
    input := input
    output := output
    cost := modelCost
  }

def flux2Flex : LeanAgent.AI.ImagesModel :=
  openRouterModel "black-forest-labs/flux.2-flex" "Black Forest Labs: FLUX.2 Flex"
    #["text", "image"] #["image"]

def gemini25FlashImage : LeanAgent.AI.ImagesModel :=
  openRouterModel "google/gemini-2.5-flash-image" "Google: Nano Banana (Gemini 2.5 Flash Image)"
    #["image", "text"] #["image", "text"] (cost 0.3 2.5 0.03 0.08333333333333334)

def openAIGptImage1 : LeanAgent.AI.ImagesModel :=
  openRouterModel "openai/gpt-image-1" "OpenAI: GPT Image 1"
    #["text", "image"] #["image"] (cost 10 10 1.25 0)

def openRouterAuto : LeanAgent.AI.ImagesModel :=
  openRouterModel "openrouter/auto" "Auto Router"
    #["text", "image"] #["text", "image"] (cost (-1000000) (-1000000) 0 0)

def openRouterImageModels : Array LeanAgent.AI.ImagesModel :=
  #[ flux2Flex
   , openRouterModel "black-forest-labs/flux.2-klein-4b" "Black Forest Labs: FLUX.2 Klein 4B"
      #["text", "image"] #["image"]
   , openRouterModel "black-forest-labs/flux.2-max" "Black Forest Labs: FLUX.2 Max"
      #["text", "image"] #["image"]
   , openRouterModel "black-forest-labs/flux.2-pro" "Black Forest Labs: FLUX.2 Pro"
      #["text", "image"] #["image"]
   , openRouterModel "bytedance-seed/seedream-4.5" "ByteDance Seed: Seedream 4.5"
      #["image", "text"] #["image"]
   , gemini25FlashImage
   , openRouterModel "google/gemini-3-pro-image" "Google: Nano Banana Pro (Gemini 3 Pro Image)"
      #["image", "text"] #["image", "text"] (cost 2 12 0.19999999999999998 0.375)
   , openRouterModel "google/gemini-3-pro-image-preview" "Google: Nano Banana Pro (Gemini 3 Pro Image Preview)"
      #["image", "text"] #["image", "text"] (cost 2 12 0.19999999999999998 0.375)
   , openRouterModel "google/gemini-3.1-flash-image" "Google: Nano Banana 2 (Gemini 3.1 Flash Image)"
      #["image", "text"] #["image", "text"] (cost 0.5 3 0 0)
   , openRouterModel "google/gemini-3.1-flash-image-preview" "Google: Nano Banana 2 (Gemini 3.1 Flash Image Preview)"
      #["image", "text"] #["image", "text"] (cost 0.5 3 0 0)
   , openRouterModel "microsoft/mai-image-2.5" "Microsoft: MAI-Image-2.5"
      #["text", "image"] #["image"] (cost 5 0 0 0)
   , openRouterModel "openai/gpt-5-image" "OpenAI: GPT-5 Image"
      #["image", "text"] #["image", "text"] (cost 10 10 1.25 0)
   , openRouterModel "openai/gpt-5-image-mini" "OpenAI: GPT-5 Image Mini"
      #["image", "text"] #["image", "text"] (cost 2.5 2 0.25 0)
   , openRouterModel "openai/gpt-5.4-image-2" "OpenAI: GPT-5.4 Image 2"
      #["image", "text"] #["image", "text"] (cost 8 15 2 0)
   , openAIGptImage1
   , openRouterModel "openai/gpt-image-1-mini" "OpenAI: GPT Image 1 Mini"
      #["text", "image"] #["image"] (cost 2.5 2.5 0.25 0)
   , openRouterModel "openai/gpt-image-2" "OpenAI: GPT Image 2"
      #["text", "image"] #["image"] (cost 8 8 2 0)
   , openRouterAuto
   , openRouterModel "recraft/recraft-v3" "Recraft: Recraft V3"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4" "Recraft: Recraft V4"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4-pro" "Recraft: Recraft V4 Pro"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4-pro-vector" "Recraft: Recraft V4 Pro Vector"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4-vector" "Recraft: Recraft V4 Vector"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4.1" "Recraft: Recraft V4.1"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4.1-pro" "Recraft: Recraft V4.1 Pro"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4.1-pro-vector" "Recraft: Recraft V4.1 Pro Vector"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4.1-utility" "Recraft: Recraft V4.1 Utility"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4.1-utility-pro" "Recraft: Recraft V4.1 Utility Pro"
      #["text", "image"] #["image"]
   , openRouterModel "recraft/recraft-v4.1-vector" "Recraft: Recraft V4.1 Vector"
      #["text", "image"] #["image"]
   , openRouterModel "sourceful/riverflow-v2-fast" "Sourceful: Riverflow V2 Fast"
      #["text", "image"] #["image"]
   , openRouterModel "sourceful/riverflow-v2-fast-preview" "Sourceful: Riverflow V2 Fast Preview"
      #["text", "image"] #["image"]
   , openRouterModel "sourceful/riverflow-v2-max-preview" "Sourceful: Riverflow V2 Max Preview"
      #["text", "image"] #["image"]
   , openRouterModel "sourceful/riverflow-v2-pro" "Sourceful: Riverflow V2 Pro"
      #["text", "image"] #["image"]
   , openRouterModel "sourceful/riverflow-v2-standard-preview" "Sourceful: Riverflow V2 Standard Preview"
      #["text", "image"] #["image"]
   , openRouterModel "sourceful/riverflow-v2.5-fast" "Sourceful: Riverflow V2.5 Fast"
      #["text", "image"] #["image"]
   , openRouterModel "sourceful/riverflow-v2.5-pro" "Sourceful: Riverflow V2.5 Pro"
      #["text", "image"] #["image"]
   , openRouterModel "x-ai/grok-imagine-image-quality" "xAI: Grok Imagine Image Quality"
      #["text", "image"] #["image"]
   ]

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
