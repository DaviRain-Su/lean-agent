import LeanAgent.Core
import LeanAgent.OpenAI

namespace LeanAgent.Models

def deepSeekProviderId : String := "deepseek"
def deepSeekApiKeyEnv : String := "DEEPSEEK_API_KEY"
def deepSeekModelEnv : String := "DEEPSEEK_MODEL"
def deepSeekDefaultModel : String := "deepseek-v4-flash"
def deepSeekBaseUrl : String := "https://api.deepseek.com"

def openAIProviderId : String := "openai"
def openAIKeyEnv : String := "OPENAI_API_KEY"
def openAIModelEnv : String := "OPENAI_MODEL"
def openAIDefaultModel : String := "gpt-4.1-mini"
def openAIBaseUrl : String := "https://api.openai.com/v1"

structure ModelCompat where
  supportsStore : Bool := true
  supportsDeveloperRole : Bool := true
  requiresReasoningContentOnAssistantMessages : Bool := false
  thinkingFormat : Option String := none
deriving Repr, BEq

structure ModelInfo where
  id : String
  name : String
  provider : String
  api : String
  baseUrl : String
  contextWindow : Nat := 0
  maxTokens : Nat := 0
  reasoning : Bool := false
  input : Array String := #["text"]
  supportsToolCalls : Bool := true
  supportsJsonOutput : Bool := true
  compat : ModelCompat := {}
deriving Repr, BEq

def ModelInfo.qualifiedId (model : ModelInfo) : String :=
  model.provider ++ "/" ++ model.id

def deepSeekCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    requiresReasoningContentOnAssistantMessages := true
    thinkingFormat := some "deepseek"
  }

def deepSeekV4Flash : ModelInfo :=
  { id := deepSeekDefaultModel
    name := "DeepSeek V4 Flash"
    provider := deepSeekProviderId
    api := "openai-completions"
    baseUrl := deepSeekBaseUrl
    contextWindow := 1000000
    maxTokens := 384000
    reasoning := true
    compat := deepSeekCompat
  }

def deepSeekV4Pro : ModelInfo :=
  { id := "deepseek-v4-pro"
    name := "DeepSeek V4 Pro"
    provider := deepSeekProviderId
    api := "openai-completions"
    baseUrl := deepSeekBaseUrl
    contextWindow := 1000000
    maxTokens := 384000
    reasoning := true
    compat := deepSeekCompat
  }

def openAIGpt41Mini : ModelInfo :=
  { id := openAIDefaultModel
    name := "OpenAI GPT-4.1 Mini"
    provider := openAIProviderId
    api := "openai-completions"
    baseUrl := openAIBaseUrl
  }

structure ProviderInfo where
  id : String
  name : String
  baseUrl : String
  apiKeyEnv : String
  modelEnv : Option String := none
  defaultModel : String
  models : Array ModelInfo := #[]
deriving Repr, BEq

def ProviderInfo.model? (provider : ProviderInfo) (modelId : String) : Option ModelInfo :=
  provider.models.find? (fun model => model.id == modelId)

def deepSeekProviderInfo : ProviderInfo :=
  { id := deepSeekProviderId
    name := "DeepSeek"
    baseUrl := deepSeekBaseUrl
    apiKeyEnv := deepSeekApiKeyEnv
    modelEnv := some deepSeekModelEnv
    defaultModel := deepSeekDefaultModel
    models := #[deepSeekV4Flash, deepSeekV4Pro]
  }

def openAIProviderInfo : ProviderInfo :=
  { id := openAIProviderId
    name := "OpenAI"
    baseUrl := openAIBaseUrl
    apiKeyEnv := openAIKeyEnv
    modelEnv := some openAIModelEnv
    defaultModel := openAIDefaultModel
    models := #[openAIGpt41Mini]
  }

structure ProviderCatalog where
  providers : Array ProviderInfo := #[]
deriving Repr, BEq

def defaultCatalog : ProviderCatalog :=
  { providers := #[deepSeekProviderInfo, openAIProviderInfo] }

def ProviderCatalog.provider? (catalog : ProviderCatalog) (id : String) : Option ProviderInfo :=
  catalog.providers.find? (fun provider => provider.id == id)

def ProviderCatalog.providerByApiKeyEnv? (catalog : ProviderCatalog) (apiKeyEnv : String) : Option ProviderInfo :=
  catalog.providers.find? (fun provider => provider.apiKeyEnv == apiKeyEnv)

def ProviderCatalog.model? (catalog : ProviderCatalog) (providerId modelId : String) : Option ModelInfo :=
  match catalog.provider? providerId with
  | some provider => provider.model? modelId
  | none => none

def ProviderCatalog.defaultModelIdForApiKeyEnv? (catalog : ProviderCatalog) (apiKeyEnv : String) : Option String :=
  catalog.providerByApiKeyEnv? apiKeyEnv |>.map (fun provider => provider.defaultModel)

def modelLine (model : ModelInfo) : String :=
  let context :=
    if model.contextWindow == 0 then
      "context=unknown"
    else
      s!"context={model.contextWindow}"
  let maxTokens :=
    if model.maxTokens == 0 then
      "max_output=unknown"
    else
      s!"max_output={model.maxTokens}"
  s!"{model.qualifiedId}  {model.name}  api={model.api}  {context}  {maxTokens}"

def providerLines (provider : ProviderInfo) : List String :=
  s!"# {provider.name} ({provider.id})" :: provider.models.toList.map modelLine

def catalogLines : List ProviderInfo → List String
  | [] => []
  | provider :: rest => providerLines provider ++ catalogLines rest

def renderCatalog (catalog : ProviderCatalog := defaultCatalog) : String :=
  String.intercalate "\n" (catalogLines catalog.providers.toList)

def provider
    (baseUrl apiKey : String)
    (noProxy : Option String := none) : ModelProvider :=
  LeanAgent.OpenAI.provider
    { apiKey := apiKey
      baseUrl := baseUrl
      noProxy := noProxy
    }

end LeanAgent.Models
