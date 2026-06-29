import LeanAgent.AI.EnvApiKeys
import LeanAgent.Models

namespace LeanAgent.AI.Compat

structure ApiProvider where
  api : String
  streams : LeanAgent.Models.ProviderStreams

structure RegisteredApiProvider where
  provider : ApiProvider
  sourceId : Option String := none

initialize apiProviderRegistry : IO.Ref (Array RegisteredApiProvider) ← IO.mkRef #[]

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

def getApiProviders : IO (Array ApiProvider) := do
  let providers ← apiProviderRegistry.get
  pure (providers.map (fun entry => entry.provider))

def unregisterApiProviders (sourceId : String) : IO Unit :=
  apiProviderRegistry.modify fun providers =>
    providers.filter fun entry => entry.sourceId != some sourceId

def clearApiProviders : IO Unit :=
  apiProviderRegistry.set #[]

def registerBuiltInApiProviders : IO Unit := do
  if (← getApiProvider? "openai-completions").isNone then
    registerApiProvider { api := "openai-completions", streams := LeanAgent.Models.openAICompatibleStreams }
  if (← getApiProvider? "openai-responses").isNone then
    registerApiProvider { api := "openai-responses", streams := LeanAgent.Models.openAIResponsesStreams }
  if (← getApiProvider? LeanAgent.AI.Api.OpenAICodexResponses.api).isNone then
    registerApiProvider
      { api := LeanAgent.AI.Api.OpenAICodexResponses.api
        streams := LeanAgent.Models.openAICodexResponsesStreams
      }
  if (← getApiProvider? "azure-openai-responses").isNone then
    registerApiProvider { api := "azure-openai-responses", streams := LeanAgent.Models.azureOpenAIResponsesStreams }
  if (← getApiProvider? LeanAgent.AI.Api.GoogleGenerativeAI.api).isNone then
    registerApiProvider { api := LeanAgent.AI.Api.GoogleGenerativeAI.api, streams := LeanAgent.Models.googleGenerativeAIStreams }
  if (← getApiProvider? LeanAgent.AI.Api.GoogleVertex.api).isNone then
    registerApiProvider { api := LeanAgent.AI.Api.GoogleVertex.api, streams := LeanAgent.Models.googleVertexStreams }
  if (← getApiProvider? LeanAgent.AI.Api.MistralConversations.api).isNone then
    registerApiProvider { api := LeanAgent.AI.Api.MistralConversations.api, streams := LeanAgent.Models.mistralConversationsStreams }
  if (← getApiProvider? LeanAgent.AI.Api.BedrockConverseStream.api).isNone then
    registerApiProvider
      { api := LeanAgent.AI.Api.BedrockConverseStream.api
        streams := LeanAgent.Models.bedrockConverseStreamStreams
      }

def resetApiProviders : IO Unit := do
  clearApiProviders
  registerBuiltInApiProviders

initialize registerBuiltIns : Unit ← registerBuiltInApiProviders

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
  if model.api == provider.api then
    pure ()
  else
    throw (IO.userError s!"Mismatched api: {model.api} expected {provider.api}")

def resolveApiProvider (api : String) : IO ApiProvider := do
  match ← getApiProvider? api with
  | some provider => pure provider
  | none => throw (IO.userError s!"No API provider registered for api: {api}")

def streamSimple
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  let provider ← resolveApiProvider model.api
  ensureApiMatches provider model
  let options ← withEnvApiKey model options
  provider.streams.streamSimple model context options

def streamSimpleWithApi
    (api : String)
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  let provider ← resolveApiProvider api
  ensureApiMatches provider model
  let options ← withEnvApiKey model options
  provider.streams.streamSimple model context options

def completeSimple
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessage := do
  let stream ← streamSimple model context options
  pure stream.result

def completeSimpleWithApi
    (api : String)
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessage := do
  let stream ← streamSimpleWithApi api model context options
  pure stream.result

end LeanAgent.AI.Compat
