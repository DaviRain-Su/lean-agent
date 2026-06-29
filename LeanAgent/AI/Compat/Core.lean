import LeanAgent.AI.Api.AnthropicMessages
import LeanAgent.AI.Api.AnthropicMessagesLazy
import LeanAgent.AI.Api.AzureOpenAIResponses
import LeanAgent.AI.Api.AzureOpenAIResponsesLazy
import LeanAgent.AI.Api.BedrockConverseStream
import LeanAgent.AI.Api.BedrockConverseStreamLazy
import LeanAgent.AI.Api.GoogleGenerativeAI
import LeanAgent.AI.Api.GoogleGenerativeAILazy
import LeanAgent.AI.Api.GoogleVertex
import LeanAgent.AI.Api.GoogleVertexLazy
import LeanAgent.AI.Api.MistralConversations
import LeanAgent.AI.Api.MistralConversationsLazy
import LeanAgent.AI.Api.OpenAICodexResponses
import LeanAgent.AI.Api.OpenAICodexResponsesLazy
import LeanAgent.AI.Api.OpenAICompletionsLazy
import LeanAgent.AI.Api.OpenAIResponsesLazy
import LeanAgent.AI.EnvApiKeys
import LeanAgent.AI.Images.Models
import LeanAgent.AI.Providers.Faux
import LeanAgent.AI.Providers.All
import LeanAgent.AI.Providers.Streams
import LeanAgent.Models

namespace LeanAgent.AI.Compat

structure ApiProvider where
  api : String
  streams : LeanAgent.Models.ProviderStreams

def ApiProvider.ensureApiMatches
    (provider : ApiProvider)
    (model : LeanAgent.Models.ModelInfo) : IO Unit :=
  if model.api == provider.api then
    pure ()
  else
    throw (IO.userError s!"Mismatched api: {model.api} expected {provider.api}")

def ApiProvider.streamSimple
    (provider : ApiProvider)
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  provider.ensureApiMatches model
  provider.streams.streamSimple model context options

def ApiProvider.stream
    (provider : ApiProvider)
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  provider.ensureApiMatches model
  provider.streams.stream model context options

structure RegisteredApiProvider where
  provider : ApiProvider
  sourceId : Option String := none

initialize apiProviderRegistry : IO.Ref (Array RegisteredApiProvider) ← IO.mkRef #[]

def builtinApiSourceId (api : String) : String :=
  s!"compat-builtin:{api}"

def compatModels : IO LeanAgent.Models.Collection :=
  LeanAgent.AI.Providers.All.builtinModels

def registerApiProvider
    (provider : ApiProvider)
    (sourceId : Option String := none) : IO Unit :=
  apiProviderRegistry.modify fun providers =>
    (providers.filter fun entry => entry.provider.api != provider.api).push
      { provider := provider, sourceId := sourceId }

def getApiProvider? (api : String) : IO (Option ApiProvider) := do
  let providers ← apiProviderRegistry.get
  pure (providers.findSome? fun entry =>
    if entry.provider.api == api then some entry.provider else none)

def getApiProvider (api : String) : IO (Option ApiProvider) :=
  getApiProvider? api

def getRegisteredApiProvider? (api : String) : IO (Option RegisteredApiProvider) := do
  let providers ← apiProviderRegistry.get
  pure (providers.findSome? fun entry =>
    if entry.provider.api == api then some entry else none)

def getApiProviders : IO (Array ApiProvider) := do
  let providers ← apiProviderRegistry.get
  pure (providers.map (fun entry => entry.provider))

def unregisterApiProviders (sourceId : String) : IO Unit :=
  apiProviderRegistry.modify fun providers =>
    providers.filter fun entry => entry.sourceId != some sourceId

def clearApiProviders : IO Unit :=
  apiProviderRegistry.set #[]

def registerBuiltInApiProviders : IO Unit := do
  if (← getApiProvider? LeanAgent.AI.Api.AnthropicMessages.api).isNone then
    registerApiProvider
      { api := LeanAgent.AI.Api.AnthropicMessages.api
        streams := LeanAgent.AI.Api.AnthropicMessagesLazy.anthropicMessagesApi
      }
      (some (builtinApiSourceId LeanAgent.AI.Api.AnthropicMessages.api))
  if (← getApiProvider? "openai-completions").isNone then
    registerApiProvider
      { api := "openai-completions"
        streams := LeanAgent.AI.Api.OpenAICompletionsLazy.openAICompletionsApi
      }
      (some (builtinApiSourceId "openai-completions"))
  if (← getApiProvider? "openai-responses").isNone then
    registerApiProvider
      { api := "openai-responses"
        streams := LeanAgent.AI.Api.OpenAIResponsesLazy.openAIResponsesApi
      }
      (some (builtinApiSourceId "openai-responses"))
  if (← getApiProvider? LeanAgent.AI.Api.OpenAICodexResponses.api).isNone then
    registerApiProvider
      { api := LeanAgent.AI.Api.OpenAICodexResponses.api
        streams := LeanAgent.AI.Api.OpenAICodexResponsesLazy.openAICodexResponsesApi
      }
      (some (builtinApiSourceId LeanAgent.AI.Api.OpenAICodexResponses.api))
  if (← getApiProvider? "azure-openai-responses").isNone then
    registerApiProvider
      { api := "azure-openai-responses"
        streams := LeanAgent.AI.Api.AzureOpenAIResponsesLazy.azureOpenAIResponsesApi
      }
      (some (builtinApiSourceId "azure-openai-responses"))
  if (← getApiProvider? LeanAgent.AI.Api.GoogleGenerativeAI.api).isNone then
    registerApiProvider
      { api := LeanAgent.AI.Api.GoogleGenerativeAI.api
        streams := LeanAgent.AI.Api.GoogleGenerativeAILazy.googleGenerativeAIApi
      }
      (some (builtinApiSourceId LeanAgent.AI.Api.GoogleGenerativeAI.api))
  if (← getApiProvider? LeanAgent.AI.Api.GoogleVertex.api).isNone then
    registerApiProvider
      { api := LeanAgent.AI.Api.GoogleVertex.api
        streams := LeanAgent.AI.Api.GoogleVertexLazy.googleVertexApi
      }
      (some (builtinApiSourceId LeanAgent.AI.Api.GoogleVertex.api))
  if (← getApiProvider? LeanAgent.AI.Api.MistralConversations.api).isNone then
    registerApiProvider
      { api := LeanAgent.AI.Api.MistralConversations.api
        streams := LeanAgent.AI.Api.MistralConversationsLazy.mistralConversationsApi
      }
      (some (builtinApiSourceId LeanAgent.AI.Api.MistralConversations.api))
  if (← getApiProvider? LeanAgent.AI.Api.BedrockConverseStream.api).isNone then
    registerApiProvider
      { api := LeanAgent.AI.Api.BedrockConverseStream.api
        streams := LeanAgent.AI.Api.BedrockConverseStreamLazy.bedrockConverseStreamApi
      }
      (some (builtinApiSourceId LeanAgent.AI.Api.BedrockConverseStream.api))

def resetApiProviders : IO Unit := do
  clearApiProviders
  registerBuiltInApiProviders

initialize registerBuiltIns : Unit ← registerBuiltInApiProviders

structure FauxProviderRegistration where
  handle : LeanAgent.AI.Providers.Faux.FauxProviderHandle
  sourceId : String

def FauxProviderRegistration.api (registration : FauxProviderRegistration) : String :=
  registration.handle.api

def FauxProviderRegistration.models (registration : FauxProviderRegistration) :
    Array LeanAgent.Models.ModelInfo :=
  registration.handle.models

def FauxProviderRegistration.getModel? (registration : FauxProviderRegistration) (modelId : String) :
    Option LeanAgent.Models.ModelInfo :=
  registration.handle.getModel? modelId

def FauxProviderRegistration.getModel (registration : FauxProviderRegistration) :
    LeanAgent.Models.ModelInfo :=
  registration.handle.getModel

def FauxProviderRegistration.state (registration : FauxProviderRegistration) :
    IO LeanAgent.AI.Providers.Faux.FauxState :=
  registration.handle.state

def FauxProviderRegistration.setResponses
    (registration : FauxProviderRegistration)
    (responses : Array LeanAgent.AI.Providers.Faux.FauxResponseStep) : IO Unit :=
  registration.handle.setResponses responses

def FauxProviderRegistration.appendResponses
    (registration : FauxProviderRegistration)
    (responses : Array LeanAgent.AI.Providers.Faux.FauxResponseStep) : IO Unit :=
  registration.handle.appendResponses responses

def FauxProviderRegistration.getPendingResponseCount (registration : FauxProviderRegistration) :
    IO Nat :=
  registration.handle.getPendingResponseCount

def FauxProviderRegistration.unregister (registration : FauxProviderRegistration) : IO Unit :=
  unregisterApiProviders registration.sourceId

def registerFauxProvider
    (options : LeanAgent.AI.Providers.Faux.FauxOptions := {}) :
    IO FauxProviderRegistration := do
  let handle ← LeanAgent.AI.Providers.Faux.fauxProvider options
  let timestamp ← IO.monoMsNow
  let sourceId := s!"faux-provider-{handle.api}-{timestamp}"
  registerApiProvider
    { api := handle.api
      streams := { streamSimple := handle.provider.streamSimple }
    }
    (some sourceId)
  pure { handle := handle, sourceId := sourceId }

def getProviders : Array String :=
  LeanAgent.AI.Providers.All.getBuiltinProviders

def getModels (providerId : String) : Array LeanAgent.Models.ModelInfo :=
  LeanAgent.AI.Providers.All.getBuiltinModels providerId

def getModel? (providerId modelId : String) : Option LeanAgent.Models.ModelInfo :=
  LeanAgent.AI.Providers.All.getBuiltinModel? providerId modelId

def getModel (providerId modelId : String) : IO LeanAgent.Models.ModelInfo := do
  match getModel? providerId modelId with
  | some model => pure model
  | none => throw (IO.userError s!"Unknown built-in model: {providerId}/{modelId}")

def registerImagesApiProvider
    (provider : LeanAgent.AI.Images.ImagesApiProvider)
    (sourceId : Option String := none) : IO Unit :=
  LeanAgent.AI.Images.registerImagesApiProvider provider sourceId

def getImagesApiProvider? (api : LeanAgent.AI.ImagesApi) :
    IO (Option LeanAgent.AI.Images.ImagesApiProvider) :=
  LeanAgent.AI.Images.getImagesApiProvider? api

def getImagesApiProvider (api : LeanAgent.AI.ImagesApi) :
    IO (Option LeanAgent.AI.Images.ImagesApiProvider) :=
  getImagesApiProvider? api

def getImagesApiProviders : IO (Array LeanAgent.AI.Images.ImagesApiProvider) :=
  LeanAgent.AI.Images.getImagesApiProviders

def unregisterImagesApiProviders (sourceId : String) : IO Unit :=
  LeanAgent.AI.Images.unregisterImagesApiProviders sourceId

def clearImagesApiProviders : IO Unit :=
  LeanAgent.AI.Images.clearImagesApiProviders

def registerBuiltInImagesApiProviders : IO Unit :=
  LeanAgent.AI.Images.registerBuiltInImagesApiProviders

def resetImagesApiProviders : IO Unit :=
  LeanAgent.AI.Images.resetImagesApiProviders

def generateImagesWithApi
    (api : LeanAgent.AI.ImagesApi)
    (model : LeanAgent.AI.ImagesModel)
    (context : LeanAgent.AI.ImagesContext)
    (options : LeanAgent.AI.ImagesOptions := {}) :
    IO LeanAgent.AI.AssistantImages :=
  LeanAgent.AI.Images.generateImagesWithApi api model context options

def generateImages
    (model : LeanAgent.AI.ImagesModel)
    (context : LeanAgent.AI.ImagesContext)
    (options : LeanAgent.AI.ImagesOptions := {}) :
    IO LeanAgent.AI.AssistantImages :=
  LeanAgent.AI.Images.generateImages model context options

def getImageProviders : Array String :=
  LeanAgent.AI.Images.Models.getImageProviders

def getImageModels (providerId : String) : Array LeanAgent.AI.ImagesModel :=
  LeanAgent.AI.Images.Models.getImageModels providerId

def getImageModel? (providerId modelId : String) : Option LeanAgent.AI.ImagesModel :=
  LeanAgent.AI.Images.Models.getImageModel? providerId modelId

def getImageModel (providerId modelId : String) : IO LeanAgent.AI.ImagesModel := do
  match getImageModel? providerId modelId with
  | some model => pure model
  | none => throw (IO.userError s!"Unknown built-in image model: {providerId}/{modelId}")

def providerEnvApiKey? (model : LeanAgent.Models.ModelInfo) (env : LeanAgent.AI.Auth.ProviderEnv) :
    IO (Option String) :=
  LeanAgent.AI.EnvApiKeys.getEnvApiKey model.provider env

def withEnvApiKey
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    IO LeanAgent.AI.SimpleStreamOptions := do
  match options.apiKey with
  | some value =>
      if value.trimAscii.isEmpty then
        let key? ← providerEnvApiKey? model options.env
        pure { options with apiKey := key? }
      else
        pure options
  | none =>
      let key? ← providerEnvApiKey? model options.env
      pure { options with apiKey := key? }

def ensureApiMatches (provider : ApiProvider) (model : LeanAgent.Models.ModelInfo) : IO Unit :=
  provider.ensureApiMatches model

def resolveApiProvider (api : String) : IO ApiProvider := do
  match ← getApiProvider? api with
  | some provider => pure provider
  | none => throw (IO.userError s!"No API provider registered for api: {api}")

def shouldUseBuiltinModels (model : LeanAgent.Models.ModelInfo) : IO Bool := do
  let models ← compatModels
  match ← models.getModel? model.provider model.id with
  | some builtin =>
      match ← getRegisteredApiProvider? model.api with
      | some entry =>
          pure
            (builtin.api == model.api &&
              entry.sourceId == some (builtinApiSourceId model.api))
      | none => pure false
  | none => pure false

def abortedCompatMessage
    (model : LeanAgent.Models.ModelInfo)
    (timestamp : Nat) : LeanAgent.AI.AssistantMessage :=
  { content := #[]
    api := model.api
    provider := model.provider
    model := model.id
    stopReason := .aborted
    errorMessage := some LeanAgent.AI.Util.Abort.requestAbortedMessage
    timestamp := timestamp
  }

def abortedCompatStream
    (model : LeanAgent.Models.ModelInfo)
    (timestamp : Nat) : LeanAgent.AI.AssistantMessageEventStream :=
  LeanAgent.AI.fromMessage (abortedCompatMessage model timestamp)

def streamBuiltinSimple
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  if ← LeanAgent.AI.Util.Abort.isAborted options.signal then
    return abortedCompatStream model (← IO.monoMsNow)
  let models ← compatModels
  let builtinProvider ← models.requireProvider model
  let (requestModel, requestOptions) ← models.applyAuth builtinProvider model options
  let (responseRef, requestOptions) ← LeanAgent.Models.withCapturedResponseHook requestOptions
  let provider ← resolveApiProvider requestModel.api
  ensureApiMatches provider requestModel
  try
    provider.streams.streamSimple requestModel context requestOptions
  catch err =>
    if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
      pure (abortedCompatStream requestModel (← IO.monoMsNow))
    else
      pure (LeanAgent.Models.errorEventStream requestModel err (← IO.monoMsNow) (← responseRef.get))

def streamSimple
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  if ← shouldUseBuiltinModels model then
    return ← streamBuiltinSimple model context options
  if ← LeanAgent.AI.Util.Abort.isAborted options.signal then
    return abortedCompatStream model (← IO.monoMsNow)
  let provider ← resolveApiProvider model.api
  ensureApiMatches provider model
  let options ← withEnvApiKey model options
  let (responseRef, options) ← LeanAgent.Models.withCapturedResponseHook options
  try
    provider.streams.streamSimple model context options
  catch err =>
    if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
      pure (abortedCompatStream model (← IO.monoMsNow))
    else
      pure (LeanAgent.Models.errorEventStream model err (← IO.monoMsNow) (← responseRef.get))

def stream
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  if ← shouldUseBuiltinModels model then
    streamBuiltinSimple model context options.toSimpleStreamOptions
  else
    streamSimple model context options.toSimpleStreamOptions

def streamSimpleWithApi
    (api : String)
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  if api == model.api && (← shouldUseBuiltinModels model) then
    return ← streamBuiltinSimple model context options
  if ← LeanAgent.AI.Util.Abort.isAborted options.signal then
    return abortedCompatStream model (← IO.monoMsNow)
  let provider ← resolveApiProvider api
  ensureApiMatches provider model
  let options ← withEnvApiKey model options
  let (responseRef, options) ← LeanAgent.Models.withCapturedResponseHook options
  try
    provider.streams.streamSimple model context options
  catch err =>
    if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
      pure (abortedCompatStream model (← IO.monoMsNow))
    else
      pure (LeanAgent.Models.errorEventStream model err (← IO.monoMsNow) (← responseRef.get))

def streamWithApi
    (api : String)
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  if api == model.api && (← shouldUseBuiltinModels model) then
    streamBuiltinSimple model context options.toSimpleStreamOptions
  else
    streamSimpleWithApi api model context options.toSimpleStreamOptions

def completeSimple
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessage := do
  let stream ← streamSimple model context options
  pure stream.result

def complete
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessage := do
  let resultStream ← stream model context options
  pure resultStream.result

def completeSimpleWithApi
    (api : String)
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessage := do
  let stream ← streamSimpleWithApi api model context options
  pure stream.result

def completeWithApi
    (api : String)
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.StreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessage := do
  let resultStream ← streamWithApi api model context options
  pure resultStream.result

end LeanAgent.AI.Compat
