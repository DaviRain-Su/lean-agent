import LeanAgent.Core
import LeanAgent.AI.Auth
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
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
  cost : LeanAgent.AI.UsageCost := {}
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

inductive ModelsErrorCode where
  | modelSource
  | modelValidation
  | provider
  | stream
  | auth
deriving BEq

def ModelsErrorCode.toString : ModelsErrorCode → String
  | .modelSource => "model_source"
  | .modelValidation => "model_validation"
  | .provider => "provider"
  | .stream => "stream"
  | .auth => "auth"

def modelsError (code : ModelsErrorCode) (message : String) : IO.Error :=
  IO.userError s!"ModelsError({code.toString}): {message}"

structure ProviderStreams where
  streamSimple :
    ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

def ProviderStreams.completeSimple
    (streams : ProviderStreams)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← streams.streamSimple model context options
  pure stream.result

structure Provider where
  id : String
  name : String
  baseUrl : Option String := none
  headers : LeanAgent.AI.Auth.ProviderHeaders := #[]
  auth : LeanAgent.AI.Auth.ProviderAuth
  getModels : IO (Array ModelInfo)
  refreshModels : Option (IO Unit) := none
  streamSimple :
    ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

def Provider.completeSimple
    (provider : Provider)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← provider.streamSimple model context options
  pure stream.result

structure ApiDispatch where
  api : String
  streams : ProviderStreams

structure CreateProviderOptions where
  id : String
  name : Option String := none
  baseUrl : Option String := none
  headers : LeanAgent.AI.Auth.ProviderHeaders := #[]
  auth : LeanAgent.AI.Auth.ProviderAuth
  models : Array ModelInfo := #[]
  refreshModels : Option (IO (Array ModelInfo)) := none
  apis : Array ApiDispatch

def apiDispatchFor? (dispatches : Array ApiDispatch) (api : String) : Option ProviderStreams :=
  dispatches.findSome? fun dispatch =>
    if dispatch.api == api then some dispatch.streams else none

def createProvider (input : CreateProviderOptions) : IO Provider := do
  let modelsRef ← IO.mkRef input.models
  let refreshModels :=
    input.refreshModels.map fun refresh => do
      let refreshed ← refresh
      modelsRef.set refreshed
  pure
    { id := input.id
      name := input.name.getD input.id
      baseUrl := input.baseUrl
      headers := input.headers
      auth := input.auth
      getModels := modelsRef.get
      refreshModels := refreshModels
      streamSimple := fun model context options => do
        match apiDispatchFor? input.apis model.api with
        | some streams => streams.streamSimple model context options
        | none =>
            throw (modelsError .stream s!"Provider {input.id} has no API implementation for \"{model.api}\"")
    }

def hasApi (model : ModelInfo) (api : String) : Bool :=
  model.api == api

def modelsAreEqual (a b : Option ModelInfo) : Bool :=
  match a, b with
  | some a, some b => a.id == b.id && a.provider == b.provider
  | _, _ => false

def extendedThinkingLevels : Array LeanAgent.AI.ModelThinkingLevel :=
  #[ .off
   , .level .minimal
   , .level .low
   , .level .medium
   , .level .high
   , .level .xhigh
   ]

def getSupportedThinkingLevels (model : ModelInfo) : Array LeanAgent.AI.ModelThinkingLevel :=
  if model.reasoning then extendedThinkingLevels else #[.off]

def thinkingLevelIndex? : LeanAgent.AI.ModelThinkingLevel → Option Nat
  | .off => some 0
  | .level .minimal => some 1
  | .level .low => some 2
  | .level .medium => some 3
  | .level .high => some 4
  | .level .xhigh => some 5

def clampThinkingLevel
    (model : ModelInfo)
    (level : LeanAgent.AI.ModelThinkingLevel) : LeanAgent.AI.ModelThinkingLevel :=
  let available := getSupportedThinkingLevels model
  if available.contains level then
    level
  else
    match thinkingLevelIndex? level with
    | none => available[0]?.getD .off
    | some requested =>
        let upward := extendedThinkingLevels.filter fun candidate =>
          match thinkingLevelIndex? candidate with
          | some index => requested <= index && available.contains candidate
          | none => false
        match upward[0]? with
        | some candidate => candidate
        | none =>
            let downward := extendedThinkingLevels.filter fun candidate =>
              match thinkingLevelIndex? candidate with
              | some index => index < requested && available.contains candidate
              | none => false
            match downward.back? with
            | some candidate => candidate
            | none => available[0]?.getD .off

def perMillionCost (rate : Float) (tokens : Nat) : Float :=
  (rate / 1000000.0) * Float.ofNat tokens

def calculateCost (model : ModelInfo) (usage : LeanAgent.AI.Usage) : LeanAgent.AI.UsageCost :=
  let longWrite := usage.cacheWrite1h.getD 0
  let shortWrite := usage.cacheWrite - longWrite
  let input := perMillionCost model.cost.input usage.input
  let output := perMillionCost model.cost.output usage.output
  let cacheRead := perMillionCost model.cost.cacheRead usage.cacheRead
  let cacheWrite :=
    ((model.cost.cacheWrite * Float.ofNat shortWrite) + (model.cost.input * 2.0 * Float.ofNat longWrite)) /
      1000000.0
  { input := input
    output := output
    cacheRead := cacheRead
    cacheWrite := cacheWrite
    total := input + output + cacheRead + cacheWrite
  }

def legacyToolFromAITool (tool : LeanAgent.AI.Tool) : AgentTool :=
  { name := tool.name
    description := tool.description
    inputSchema := tool.parameters
    execute := fun call =>
      pure
        { toolCallId := call.id
          name := call.name
          ok := false
          content := "AI runtime provider placeholder tools are not executable"
          error := some "tool execution is owned by the agent loop"
        }
  }

def contextToProviderRequest (model : ModelInfo) (context : LeanAgent.AI.Context) : ProviderRequest :=
  { model := model.id
    system := context.systemPrompt.getD ""
    messages := context.messages.map LeanAgent.AI.toLegacyMessage
    tools := context.tools.map legacyToolFromAITool
  }

def openAICompatibleStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      match options.apiKey with
      | none => throw (modelsError .auth s!"missing API key for provider {model.provider}")
      | some apiKey =>
          let provider := LeanAgent.OpenAI.provider
            { apiKey := apiKey
              baseUrl := model.baseUrl
            }
          let request := contextToProviderRequest model context
          LeanAgent.AI.streamLegacyProvider provider request model.api model.provider
  }

def authForProviderInfo (info : ProviderInfo) : LeanAgent.AI.Auth.ProviderAuth :=
  { apiKey := some (LeanAgent.AI.Auth.envApiKeyAuth (info.name ++ " API key") #[info.apiKeyEnv]) }

def createCatalogProvider (info : ProviderInfo) : IO Provider :=
  createProvider
    { id := info.id
      name := some info.name
      baseUrl := some info.baseUrl
      auth := authForProviderInfo info
      models := info.models
      apis := #[{ api := "openai-completions", streams := openAICompatibleStreams }]
    }

def streamHeaderNames (headers : Array (String × Option String)) : Array String :=
  headers.map Prod.fst

def authHeadersToStreamHeaders
    (authHeaders : LeanAgent.AI.Auth.ProviderHeaders)
    (requestHeaders : Array (String × Option String)) : Array (String × Option String) :=
  let requestNames := streamHeaderNames requestHeaders
  let inherited := authHeaders.filterMap fun (name, value) =>
    if requestNames.contains name then none else some (name, some value)
  inherited ++ requestHeaders

structure Collection where
  providersRef : IO.Ref (Array Provider)
  credentials : LeanAgent.AI.Auth.CredentialStore
  authContext : LeanAgent.AI.Auth.AuthContext

def createModels
    (credentials : Option LeanAgent.AI.Auth.CredentialStore := none)
    (authContext : LeanAgent.AI.Auth.AuthContext := LeanAgent.AI.Auth.defaultProviderAuthContext) :
    IO Collection := do
  let credentials ←
    match credentials with
    | some credentials => pure credentials
    | none => LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let providersRef ← IO.mkRef (Array.empty : Array Provider)
  pure { providersRef := providersRef, credentials := credentials, authContext := authContext }

def Collection.getProviders (collection : Collection) : IO (Array Provider) :=
  collection.providersRef.get

def Collection.getProvider? (collection : Collection) (id : String) : IO (Option Provider) := do
  let providers ← collection.getProviders
  pure (providers.find? fun provider => provider.id == id)

def Collection.setProvider (collection : Collection) (provider : Provider) : IO Unit := do
  collection.providersRef.modify fun providers =>
    (providers.filter fun current => current.id != provider.id).push provider

def createDefaultModels
    (credentials : Option LeanAgent.AI.Auth.CredentialStore := none)
    (authContext : LeanAgent.AI.Auth.AuthContext := LeanAgent.AI.Auth.defaultProviderAuthContext) :
    IO Collection := do
  let collection ← createModels credentials authContext
  for info in defaultCatalog.providers do
    let provider ← createCatalogProvider info
    collection.setProvider provider
  pure collection

def Collection.deleteProvider (collection : Collection) (id : String) : IO Unit := do
  collection.providersRef.modify fun providers => providers.filter fun provider => provider.id != id

def Collection.clearProviders (collection : Collection) : IO Unit :=
  collection.providersRef.set #[]

def providerModelsOrEmpty (provider : Provider) : IO (Array ModelInfo) := do
  try
    provider.getModels
  catch _ =>
    pure #[]

def Collection.getModels (collection : Collection) (providerId : Option String := none) : IO (Array ModelInfo) := do
  match providerId with
  | some id =>
      match ← collection.getProvider? id with
      | some provider => providerModelsOrEmpty provider
      | none => pure #[]
  | none =>
      let providers ← collection.getProviders
      let mut models := #[]
      for provider in providers do
        models := models ++ (← providerModelsOrEmpty provider)
      pure models

def Collection.getModel? (collection : Collection) (providerId modelId : String) : IO (Option ModelInfo) := do
  let models ← collection.getModels (some providerId)
  pure (models.find? fun model => model.id == modelId)

def Collection.refresh (collection : Collection) (providerId : Option String := none) : IO Unit := do
  match providerId with
  | some id =>
      match ← collection.getProvider? id with
      | some provider =>
          match provider.refreshModels with
          | some refresh => refresh
          | none => pure ()
      | none => pure ()
  | none =>
      let providers ← collection.getProviders
      for provider in providers do
        match provider.refreshModels with
        | some refresh =>
            try
              refresh
            catch _ =>
              pure ()
        | none => pure ()

def Collection.getAuth (collection : Collection) (model : ModelInfo) : IO (Option LeanAgent.AI.Auth.AuthResult) := do
  match ← collection.getProvider? model.provider with
  | some provider =>
      LeanAgent.AI.Auth.resolveProviderAuth provider.id provider.auth collection.credentials collection.authContext
  | none => pure none

def Collection.requireProvider (collection : Collection) (model : ModelInfo) : IO Provider := do
  match ← collection.getProvider? model.provider with
  | some provider => pure provider
  | none => throw (modelsError .provider s!"Unknown provider: {model.provider}")

def Collection.applyAuth
    (collection : Collection)
    (provider : Provider)
    (model : ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    IO (ModelInfo × LeanAgent.AI.SimpleStreamOptions) := do
  let resolution ←
    LeanAgent.AI.Auth.resolveProviderAuth provider.id provider.auth collection.credentials collection.authContext
      { apiKey := options.apiKey, env := options.env }
  match resolution with
  | none => pure (model, options)
  | some resolution =>
      let requestModel :=
        match resolution.auth.baseUrl with
        | some baseUrl => { model with baseUrl := baseUrl }
        | none => model
      let apiKey :=
        match options.apiKey with
        | some value => some value
        | none => resolution.auth.apiKey
      let requestOptions :=
        { options with
          apiKey := apiKey
          headers := authHeadersToStreamHeaders resolution.auth.headers options.headers
          env := LeanAgent.AI.Auth.providerEnvMerge resolution.env options.env
        }
      pure (requestModel, requestOptions)

def Collection.streamSimple
    (collection : Collection)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  let provider ← collection.requireProvider model
  let (requestModel, requestOptions) ← collection.applyAuth provider model options
  provider.streamSimple requestModel context requestOptions

def Collection.completeSimple
    (collection : Collection)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← collection.streamSimple model context options
  pure stream.result

structure SelectionOptions where
  model : Option String := none
  baseUrl : Option String := none
  apiKeyEnv : Option String := none

structure ProviderSelection where
  providerInfo : ProviderInfo
  model : String
  baseUrl : String
  apiKeyEnv : String
  apiKey : String
  noProxy : Option String := none

def leanAgentNoProxyEnv : String := "LEAN_AGENT_NO_PROXY"

def envValue (name : String) : IO (Option String) := do
  match ← IO.getEnv name with
  | some value =>
      let trimmed := value.trimAscii.toString
      pure (if trimmed.isEmpty then none else some trimmed)
  | none => pure none

def envIsSet (name : String) : IO Bool := do
  pure (Option.isSome (← envValue name))

def envOrDefault (name fallback : String) : IO String := do
  match ← envValue name with
  | some value => pure value
  | none => pure fallback

def resolveApiKeyEnv (opts : SelectionOptions) (catalog : ProviderCatalog := defaultCatalog) : IO String := do
  match opts.apiKeyEnv with
  | some name => pure name
  | none =>
      let mut selected := none
      for provider in catalog.providers do
        if selected.isNone then
          if ← envIsSet provider.apiKeyEnv then
            selected := some provider.apiKeyEnv
      pure (selected.getD openAIKeyEnv)

def resolveProviderForApiKeyEnv
    (apiKeyEnv : String)
    (catalog : ProviderCatalog := defaultCatalog) : ProviderInfo :=
  match catalog.providerByApiKeyEnv? apiKeyEnv with
  | some provider => provider
  | none => openAIProviderInfo

def resolveBaseUrl (opts : SelectionOptions) (provider : ProviderInfo) : String :=
  match opts.baseUrl with
  | some baseUrl => baseUrl
  | none => provider.baseUrl

def resolveModel (opts : SelectionOptions) (provider : ProviderInfo) : IO String := do
  match opts.model with
  | some model => pure model
  | none =>
      match provider.modelEnv with
      | some modelEnv => envOrDefault modelEnv provider.defaultModel
      | none => pure provider.defaultModel

def resolveNoProxy (baseUrl : String) : IO (Option String) := do
  match ← envValue leanAgentNoProxyEnv with
  | some value => pure (some value)
  | none =>
      if baseUrl.startsWith deepSeekBaseUrl then
        pure (some "api.deepseek.com")
      else
        pure none

def resolveSelection
    (opts : SelectionOptions)
    (catalog : ProviderCatalog := defaultCatalog) : IO (Except String ProviderSelection) := do
  let apiKeyEnv ← resolveApiKeyEnv opts catalog
  let provider := resolveProviderForApiKeyEnv apiKeyEnv catalog
  let baseUrl := resolveBaseUrl opts provider
  let model ← resolveModel opts provider
  let noProxy ← resolveNoProxy baseUrl
  match ← envValue apiKeyEnv with
  | some apiKey =>
      pure (.ok
        { providerInfo := provider
          model := model
          baseUrl := baseUrl
          apiKeyEnv := apiKeyEnv
          apiKey := apiKey
          noProxy := noProxy
        })
  | none =>
      pure (.error s!"missing API key: set {apiKeyEnv} or pass --api-key-env")

def legacyProviderFromSelection (selection : ProviderSelection) : ModelProvider :=
  provider selection.baseUrl selection.apiKey selection.noProxy

end LeanAgent.Models
