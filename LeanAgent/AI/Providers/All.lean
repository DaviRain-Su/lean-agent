import LeanAgent.AI.Images
import LeanAgent.AI.Providers.CloudflareAIGateway
import LeanAgent.AI.Providers.CloudflareWorkersAI
import LeanAgent.AI.Providers.OpenRouterImages
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
  let mut providers := #[]
  for info in LeanAgent.Models.defaultCatalog.providers do
    providers := providers.push (← LeanAgent.Models.createCatalogProvider info)
  pure providers

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
