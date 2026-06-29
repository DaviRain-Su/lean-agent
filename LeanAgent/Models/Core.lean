import LeanAgent.AI.Auth
import LeanAgent.AI.Api.LazyBase
import LeanAgent.AI.Api.OpenAIResponsesShared
import LeanAgent.AI.EventStream
import LeanAgent.AI.OAuth.Core
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Abort
import LeanAgent.AI.Util.Diagnostics

namespace LeanAgent.Models

structure ModelCompat where
  supportsStore : Bool := true
  supportsDeveloperRole : Bool := true
  requiresReasoningContentOnAssistantMessages : Bool := false
  thinkingFormat : Option String := none
  supportsReasoningEffort : Bool := true
  maxTokensField : String := "max_tokens"
  supportsLongCacheRetention : Bool := true
  sendSessionAffinityHeaders : Bool := false
  supportsTemperature : Bool := true
  supportsEagerToolInputStreaming : Bool := true
  supportsCacheControlOnTools : Bool := true
  allowEmptySignature : Bool := false
  forceAdaptiveThinking : Bool := false
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
  thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[]
  input : Array String := #["text"]
  supportsToolCalls : Bool := true
  supportsJsonOutput : Bool := true
  headers : LeanAgent.AI.Auth.ProviderHeaders := #[]
  compat : ModelCompat := {}
deriving Repr, BEq

def ModelInfo.qualifiedId (model : ModelInfo) : String :=
  model.provider ++ "/" ++ model.id

def ModelInfo.toModelRef (model : ModelInfo) : LeanAgent.AI.ModelRef :=
  { id := model.id
    api := model.api
    provider := model.provider
    baseUrl := some model.baseUrl
  }

def ModelInfo.toResponsesModel (model : ModelInfo) :
    LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel :=
  { id := model.id
    provider := model.provider
    api := model.api
    input := model.input
    reasoning := model.reasoning
    supportsDeveloperRole := model.compat.supportsDeveloperRole
    contextWindow := model.contextWindow
    maxTokens := model.maxTokens
    cost := model.cost
    thinkingLevelMap := model.thinkingLevelMap
  }

def cost (input output cacheRead cacheWrite : Float) : LeanAgent.AI.UsageCost :=
  { input := input
    output := output
    cacheRead := cacheRead
    cacheWrite := cacheWrite
  }

inductive ModelsErrorCode where
  | modelSource
  | modelValidation
  | provider
  | stream
  | auth
  | oauth
deriving BEq

def ModelsErrorCode.toString : ModelsErrorCode → String
  | .modelSource => "model_source"
  | .modelValidation => "model_validation"
  | .provider => "provider"
  | .stream => "stream"
  | .auth => "auth"
  | .oauth => "oauth"

def modelsError (code : ModelsErrorCode) (message : String) : IO.Error :=
  IO.userError s!"ModelsError({code.toString}): {message}"

structure ProviderStreams where
  streamSimple :
    ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

def ProviderStreams.stream
    (streams : ProviderStreams)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream :=
  streams.streamSimple model context options.toSimpleStreamOptions

def ProviderStreams.complete
    (streams : ProviderStreams)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← streams.stream model context options
  pure stream.result

def ProviderStreams.completeSimple
    (streams : ProviderStreams)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← streams.streamSimple model context options
  pure stream.result

def ProviderStreams.lazy (load : IO ProviderStreams) : ProviderStreams :=
  { streamSimple := fun model context options => do
      let streams ←
        try
          load
        catch err =>
          return ← LeanAgent.AI.Api.Lazy.setupErrorStream model.toModelRef err.toString
      streams.streamSimple model context options
  }

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

def Provider.stream
    (provider : Provider)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream :=
  provider.streamSimple model context options.toSimpleStreamOptions

def Provider.complete
    (provider : Provider)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← provider.stream model context options
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
            LeanAgent.AI.Api.Lazy.setupErrorStream
              model.toModelRef
              (modelsError .stream s!"Provider {input.id} has no API implementation for \"{model.api}\"").toString
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
  if !model.reasoning then
    #[.off]
  else
    extendedThinkingLevels.filter fun level =>
      match model.thinkingLevelMap.find? (fun entry => entry.level == level) with
      | some { mapped := none, .. } => false
      | some _ => true
      | none => level != .level .xhigh

def thinkingLevelMapValue? (model : ModelInfo) (level : LeanAgent.AI.ModelThinkingLevel) :
    Option (Option String) :=
  (model.thinkingLevelMap.find? fun entry => entry.level == level).map (fun entry => entry.mapped)

def thinkingLevelPayloadValueD
    (model : ModelInfo)
    (level : LeanAgent.AI.ModelThinkingLevel)
    (fallback : String) : String :=
  match thinkingLevelMapValue? model level with
  | some (some value) => value
  | _ => fallback

def offThinkingLevelPayloadValue? (model : ModelInfo) : Option String :=
  match thinkingLevelMapValue? model .off with
  | some (some value) => some value
  | _ => none

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

def applyUsageCost (model : ModelInfo) (usage : LeanAgent.AI.Usage) : LeanAgent.AI.Usage :=
  { usage with cost := calculateCost model usage }

def applyUsageCostToMessage (model : ModelInfo) (message : LeanAgent.AI.AssistantMessage) :
    LeanAgent.AI.AssistantMessage :=
  { message with usage := applyUsageCost model message.usage }

def mapEventMessage
    (f : LeanAgent.AI.AssistantMessage → LeanAgent.AI.AssistantMessage) :
    LeanAgent.AI.AssistantMessageEvent → LeanAgent.AI.AssistantMessageEvent
  | .start snapshot => .start (f snapshot)
  | .textStart index snapshot => .textStart index (f snapshot)
  | .textDelta index delta snapshot => .textDelta index delta (f snapshot)
  | .textEnd index content snapshot => .textEnd index content (f snapshot)
  | .thinkingStart index snapshot => .thinkingStart index (f snapshot)
  | .thinkingDelta index delta snapshot => .thinkingDelta index delta (f snapshot)
  | .thinkingEnd index content snapshot => .thinkingEnd index content (f snapshot)
  | .toolCallStart index snapshot => .toolCallStart index (f snapshot)
  | .toolCallDelta index delta snapshot => .toolCallDelta index delta (f snapshot)
  | .toolCallEnd index call snapshot => .toolCallEnd index call (f snapshot)
  | .done reason message => .done reason (f message)
  | .error reason message => .error reason (f message)

def applyUsageCostToStream
    (model : ModelInfo)
    (stream : LeanAgent.AI.AssistantMessageEventStream) :
    LeanAgent.AI.AssistantMessageEventStream :=
  let update := applyUsageCostToMessage model
  { events := stream.events.map (mapEventMessage update)
    finalResult := update stream.finalResult
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

def rebuildSimpleStreamOptions
    (options : LeanAgent.AI.SimpleStreamOptions)
    (apiKey : Option String := options.apiKey)
    (headers : Array (String × Option String) := options.headers)
    (env : Array (String × String) := options.env)
    (onResponse : Option LeanAgent.AI.ResponseHook := options.onResponse) :
    LeanAgent.AI.SimpleStreamOptions :=
  { temperature := options.temperature
    maxTokens := options.maxTokens
    signal := options.signal
    apiKey := apiKey
    transport := options.transport
    cacheRetention := options.cacheRetention
    sessionId := options.sessionId
    headers := headers
    onPayload := options.onPayload
    onResponse := onResponse
    timeoutMs := options.timeoutMs
    websocketConnectTimeoutMs := options.websocketConnectTimeoutMs
    maxRetries := options.maxRetries
    maxRetryDelayMs := options.maxRetryDelayMs
    metadata := options.metadata
    env := env
    reasoning := options.reasoning
    thinkingBudgets := options.thinkingBudgets
  }

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

def Collection.deleteProvider (collection : Collection) (id : String) : IO Unit := do
  collection.providersRef.modify fun providers => providers.filter fun provider => provider.id != id

def Collection.clearProviders (collection : Collection) : IO Unit :=
  collection.providersRef.set #[]

def providerModelsOrEmpty (provider : Provider) : IO (Array ModelInfo) := do
  try
    provider.getModels
  catch _ =>
    pure #[]

def applyResolvedAuthToModels
    (provider : Provider)
    (models : Array ModelInfo)
    (resolution : LeanAgent.AI.Auth.AuthResult) : Array ModelInfo :=
  let models :=
    match resolution.auth.allowedModelIds with
    | some allowedModelIds =>
        models.filter fun model =>
          model.provider != provider.id || allowedModelIds.contains model.id
    | none => models
  match resolution.auth.baseUrl, resolution.source with
  | some baseUrl, some "OAuth" =>
      models.map fun model =>
        if model.provider == provider.id then
          { model with baseUrl := baseUrl }
        else
          model
  | _, _ => models

def modifiedOAuthModelRefFor?
    (refs : Array LeanAgent.AI.ModelRef)
    (model : ModelInfo) : Option LeanAgent.AI.ModelRef :=
  refs.findSome? fun ref =>
    if ref.provider == model.provider && ref.id == model.id then some ref else none

def applyModifiedOAuthModelRefs
    (models : Array ModelInfo)
    (refs : Array LeanAgent.AI.ModelRef) : Array ModelInfo :=
  models.filterMap fun model =>
    match modifiedOAuthModelRefFor? refs model with
    | some ref =>
        some
          { model with
            api := ref.api
            baseUrl := ref.baseUrl.getD model.baseUrl
          }
    | none => none

def collectionStoredOAuthCredential?
    (collection : Collection)
    (provider : Provider) : IO (Option LeanAgent.AI.Auth.OAuthCredential) := do
  match provider.auth.oauth with
  | none => pure none
  | some oauth =>
      match ← LeanAgent.AI.Auth.readCredential collection.credentials provider.id with
      | some (.oauth credential) =>
          LeanAgent.AI.Auth.refreshStoredOAuthCredential
            collection.authContext
            collection.credentials
            provider.id
            oauth
            credential
      | _ => pure none

def applyRegisteredOAuthModelModification
    (providerId : String)
    (models : Array ModelInfo)
    (credential : LeanAgent.AI.Auth.OAuthCredential) : IO (Option (Array ModelInfo)) := do
  match ← LeanAgent.AI.OAuth.getOAuthProvider? providerId with
  | some oauthProvider =>
      match oauthProvider.modifyModels with
      | some modify =>
          pure (some (applyModifiedOAuthModelRefs models (modify (models.map ModelInfo.toModelRef) credential)))
      | none => pure none
  | none => pure none

def collectionProviderModels
    (collection : Collection)
    (provider : Provider) : IO (Array ModelInfo) := do
  let baseModels ← providerModelsOrEmpty provider
  let (models, appliedOAuthModelHook) ←
    try
      match ← collectionStoredOAuthCredential? collection provider with
      | some credential =>
          match ← applyRegisteredOAuthModelModification provider.id baseModels credential with
          | some modified => pure (modified, true)
          | none => pure (baseModels, false)
      | none => pure (baseModels, false)
    catch _ =>
      pure (baseModels, false)
  try
    match ←
        LeanAgent.AI.Auth.resolveProviderAuth
          provider.id
          provider.auth
          collection.credentials
          collection.authContext with
    | some resolution =>
        if appliedOAuthModelHook then
          pure models
        else
          pure (applyResolvedAuthToModels provider models resolution)
    | none => pure models
  catch _ =>
    pure models

def Collection.getModels (collection : Collection) (providerId : Option String := none) : IO (Array ModelInfo) := do
  match providerId with
  | some id =>
      match ← collection.getProvider? id with
      | some provider => collectionProviderModels collection provider
      | none => pure #[]
  | none =>
      let providers ← collection.getProviders
      let mut models := #[]
      for provider in providers do
        models := models ++ (← collectionProviderModels collection provider)
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
      LeanAgent.AI.Auth.resolveProviderAuthForModel
        model.toModelRef
        provider.id
        provider.auth
        collection.credentials
        collection.authContext
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
    LeanAgent.AI.Auth.resolveProviderAuthForModel
      model.toModelRef
      provider.id
      provider.auth
      collection.credentials
      collection.authContext
      { apiKey := options.apiKey, env := options.env }
  let providerModelHeaders :=
    authHeadersToStreamHeaders provider.headers
      (authHeadersToStreamHeaders model.headers options.headers)
  match resolution with
  | none =>
      pure (model, rebuildSimpleStreamOptions options (headers := providerModelHeaders))
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
        rebuildSimpleStreamOptions
          options
          (apiKey := apiKey)
          (headers :=
            authHeadersToStreamHeaders provider.headers
              (authHeadersToStreamHeaders model.headers
                (authHeadersToStreamHeaders resolution.auth.headers options.headers)))
          (env := LeanAgent.AI.Auth.providerEnvMerge resolution.env options.env)
      pure (requestModel, requestOptions)

def abortedAssistantMessage (model : ModelInfo) (timestamp : Nat) : LeanAgent.AI.AssistantMessage :=
  { content := #[]
    api := model.api
    provider := model.provider
    model := model.id
    stopReason := .aborted
    errorMessage := some LeanAgent.AI.Util.Abort.requestAbortedMessage
    timestamp := timestamp
  }

def abortedEventStream (model : ModelInfo) (timestamp : Nat) : LeanAgent.AI.AssistantMessageEventStream :=
  LeanAgent.AI.fromMessage (abortedAssistantMessage model timestamp)

def captureResponseHook
    (responseRef : IO.Ref (Option LeanAgent.AI.ProviderResponse))
    (hook? : Option LeanAgent.AI.ResponseHook) : LeanAgent.AI.ResponseHook :=
  fun response model => do
    responseRef.set (some response)
    match hook? with
    | some hook => hook response model
    | none => pure ()

def withCapturedResponseHook
    (options : LeanAgent.AI.SimpleStreamOptions) :
    IO (IO.Ref (Option LeanAgent.AI.ProviderResponse) × LeanAgent.AI.SimpleStreamOptions) := do
  let responseRef ← IO.mkRef none
  let wrapped : LeanAgent.AI.ResponseHook := captureResponseHook responseRef options.onResponse
  pure (responseRef, rebuildSimpleStreamOptions options (onResponse := some wrapped))

def errorEventStream
    (model : ModelInfo)
    (error : IO.Error)
    (timestamp : Nat)
    (response : Option LeanAgent.AI.ProviderResponse := none) :
    LeanAgent.AI.AssistantMessageEventStream :=
  let diagnostic :=
    LeanAgent.AI.Util.Diagnostics.createAssistantMessageDiagnosticFromError
      "provider_error"
      error
      timestamp
      response
  let message : LeanAgent.AI.AssistantMessage :=
    { content := #[]
      api := model.api
      provider := model.provider
      model := model.id
      stopReason := .error
      errorMessage := some error.toString
      diagnostics := #[diagnostic]
      timestamp := timestamp
    }
  LeanAgent.AI.errorStream message

def Collection.streamSimple
    (collection : Collection)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  if ← LeanAgent.AI.Util.Abort.isAborted options.signal then
    return abortedEventStream model (← IO.monoMsNow)
  let provider ← collection.requireProvider model
  let (requestModel, requestOptions) ← collection.applyAuth provider model options
  let (responseRef, requestOptions) ← withCapturedResponseHook requestOptions
  try
    provider.streamSimple requestModel context requestOptions
  catch err =>
    if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
      pure (abortedEventStream requestModel (← IO.monoMsNow))
    else
      pure (errorEventStream requestModel err (← IO.monoMsNow) (← responseRef.get))

def Collection.completeSimple
    (collection : Collection)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← collection.streamSimple model context options
  pure stream.result

def Collection.stream
    (collection : Collection)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream :=
  collection.streamSimple model context options.toSimpleStreamOptions

def Collection.complete
    (collection : Collection)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← collection.stream model context options
  pure stream.result

end LeanAgent.Models
