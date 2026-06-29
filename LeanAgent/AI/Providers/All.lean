import LeanAgent.AI.Images
import LeanAgent.AI.Providers.AmazonBedrock
import LeanAgent.AI.Providers.Anthropic
import LeanAgent.AI.Providers.AntLing
import LeanAgent.AI.Providers.AzureOpenAIResponses
import LeanAgent.AI.Providers.Cerebras
import LeanAgent.AI.Providers.CloudflareAIGateway
import LeanAgent.AI.Providers.CloudflareWorkersAI
import LeanAgent.AI.Providers.DeepSeek
import LeanAgent.AI.Providers.Fireworks
import LeanAgent.AI.Providers.Google
import LeanAgent.AI.Providers.GoogleVertex
import LeanAgent.AI.Providers.Groq
import LeanAgent.AI.Providers.HuggingFace
import LeanAgent.AI.Providers.KimiCoding
import LeanAgent.AI.Providers.MiniMax
import LeanAgent.AI.Providers.MiniMaxCN
import LeanAgent.AI.Providers.Mistral
import LeanAgent.AI.Providers.MoonshotAI
import LeanAgent.AI.Providers.MoonshotAICN
import LeanAgent.AI.Providers.NVIDIA
import LeanAgent.AI.Providers.OpenCode
import LeanAgent.AI.Providers.OpenCodeGo
import LeanAgent.AI.Providers.OpenAI
import LeanAgent.AI.Providers.OpenAICodex
import LeanAgent.AI.Providers.OpenRouterImages
import LeanAgent.AI.Providers.OpenRouter
import LeanAgent.AI.Providers.Together
import LeanAgent.AI.Providers.VercelAIGateway
import LeanAgent.AI.Providers.XAI
import LeanAgent.AI.Providers.Xiaomi
import LeanAgent.AI.Providers.XiaomiTokenPlanAMS
import LeanAgent.AI.Providers.XiaomiTokenPlanCN
import LeanAgent.AI.Providers.XiaomiTokenPlanSGP
import LeanAgent.AI.Providers.ZAI
import LeanAgent.AI.Providers.ZAICodingCN
import LeanAgent.Models

namespace LeanAgent.AI.Providers.All

def cloudflareProviderIds : Array String :=
  #[ LeanAgent.AI.Providers.CloudflareAIGateway.providerId
   , LeanAgent.AI.Providers.CloudflareWorkersAI.providerId
   ]

def getBuiltinProviders : Array String :=
  LeanAgent.Models.defaultCatalog.providers.map (fun provider => provider.id) ++ cloudflareProviderIds

def cloudflareModels : Array LeanAgent.Models.ModelInfo :=
  LeanAgent.AI.Providers.CloudflareAIGateway.models ++
    LeanAgent.AI.Providers.CloudflareWorkersAI.models

def getBuiltinModels (providerId : String) : Array LeanAgent.Models.ModelInfo :=
  match LeanAgent.Models.defaultCatalog.provider? providerId with
  | some provider => provider.models
  | none => cloudflareModels.filter (fun model => model.provider == providerId)

def getBuiltinModel? (providerId modelId : String) : Option LeanAgent.Models.ModelInfo :=
  (getBuiltinModels providerId).find? (fun model => model.id == modelId)

def catalogProviders : IO (Array LeanAgent.Models.Provider) := do
  pure
    #[ ← LeanAgent.AI.Providers.DeepSeek.provider
     , ← LeanAgent.AI.Providers.OpenAI.provider
     , ← LeanAgent.AI.Providers.OpenAICodex.provider
     , ← LeanAgent.AI.Providers.OpenRouter.provider
     , ← LeanAgent.AI.Providers.Groq.provider
     , ← LeanAgent.AI.Providers.XAI.provider
     , ← LeanAgent.AI.Providers.Cerebras.provider
     , ← LeanAgent.AI.Providers.Together.provider
     , ← LeanAgent.AI.Providers.Fireworks.provider
     , ← LeanAgent.AI.Providers.AntLing.provider
     , ← LeanAgent.AI.Providers.HuggingFace.provider
     , ← LeanAgent.AI.Providers.MoonshotAI.provider
     , ← LeanAgent.AI.Providers.MoonshotAICN.provider
     , ← LeanAgent.AI.Providers.NVIDIA.provider
     , ← LeanAgent.AI.Providers.Xiaomi.provider
     , ← LeanAgent.AI.Providers.XiaomiTokenPlanAMS.provider
     , ← LeanAgent.AI.Providers.XiaomiTokenPlanCN.provider
     , ← LeanAgent.AI.Providers.XiaomiTokenPlanSGP.provider
     , ← LeanAgent.AI.Providers.ZAI.provider
     , ← LeanAgent.AI.Providers.ZAICodingCN.provider
     , ← LeanAgent.AI.Providers.Anthropic.provider
     , ← LeanAgent.AI.Providers.KimiCoding.provider
     , ← LeanAgent.AI.Providers.MiniMax.provider
     , ← LeanAgent.AI.Providers.MiniMaxCN.provider
     , ← LeanAgent.AI.Providers.VercelAIGateway.provider
     , ← LeanAgent.AI.Providers.OpenCode.provider
     , ← LeanAgent.AI.Providers.OpenCodeGo.provider
     , ← LeanAgent.AI.Providers.Google.provider
     , ← LeanAgent.AI.Providers.GoogleVertex.provider
     , ← LeanAgent.AI.Providers.Mistral.provider
     , ← LeanAgent.AI.Providers.AmazonBedrock.provider
     , ← LeanAgent.AI.Providers.AzureOpenAIResponses.provider
     ]

def builtinProviders : IO (Array LeanAgent.Models.Provider) := do
  let mut providers ← catalogProviders
  providers := providers.push (← LeanAgent.AI.Providers.CloudflareAIGateway.provider)
  providers := providers.push (← LeanAgent.AI.Providers.CloudflareWorkersAI.provider)
  pure providers

def builtinModels
    (credentials : Option LeanAgent.AI.Auth.CredentialStore := none)
    (authContext : LeanAgent.AI.Auth.AuthContext := LeanAgent.AI.Auth.defaultProviderAuthContext) :
    IO LeanAgent.Models.Collection := do
  let collection ← LeanAgent.Models.createModels credentials authContext
  for provider in (← builtinProviders) do
    collection.setProvider provider
  pure collection

def builtinImagesProviders : IO (Array LeanAgent.AI.Images.ImagesProvider) := do
  pure #[← LeanAgent.AI.Providers.OpenRouterImages.openRouterImagesProvider]

def builtinImagesModels
    (credentials : Option LeanAgent.AI.Auth.CredentialStore := none)
    (authContext : LeanAgent.AI.Auth.AuthContext := LeanAgent.AI.Auth.defaultProviderAuthContext) :
    IO LeanAgent.AI.Images.Collection := do
  let collection ← LeanAgent.AI.Images.createImagesModels credentials authContext
  for provider in (← builtinImagesProviders) do
    collection.setProvider provider
  pure collection

end LeanAgent.AI.Providers.All
