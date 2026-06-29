import LeanAgent.AI.Compat

namespace LeanAgent.AI.Compat.Aliases

abbrev AliasStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
    IO LeanAgent.AI.AssistantMessageEventStream

abbrev MistralStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.MistralConversations.MistralOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev OpenAIResponsesStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev AzureOpenAIResponsesStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.AzureOpenAIResponses.AzureOpenAIResponsesOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev OpenAICodexResponsesStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.OpenAICodexResponses.OpenAICodexResponsesOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

def streamForApi (api : String) : AliasStream :=
  fun model context options => LeanAgent.AI.Compat.streamSimpleWithApi api model context options

def withEnvApiKeyForOpenAIResponses
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesOptions) :
    IO LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesOptions := do
  let simple ← LeanAgent.AI.Compat.withEnvApiKey model options.toSimpleStreamOptions
  pure { options with apiKey := simple.apiKey }

def streamOpenAIResponsesWithOptions : OpenAIResponsesStream :=
  fun model context options => do
    LeanAgent.AI.Compat.ensureApiMatches
      { api := "openai-responses"
        streams := LeanAgent.Models.openAIResponsesStreams
      }
      model
    let options ← withEnvApiKeyForOpenAIResponses model options
    let apiKey ← LeanAgent.Models.requireApiKeyOrHeaderAuth model.provider options.toSimpleStreamOptions
    let config : LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesConfig :=
      { apiKey := apiKey
        baseUrl := model.baseUrl
      }
    LeanAgent.AI.Api.OpenAIResponses.completeStreamWithOptions
      config
      model.toResponsesModel
      context
      options

def withEnvApiKeyForAzureOpenAIResponses
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.AzureOpenAIResponses.AzureOpenAIResponsesOptions) :
    IO LeanAgent.AI.Api.AzureOpenAIResponses.AzureOpenAIResponsesOptions := do
  let simple ← LeanAgent.AI.Compat.withEnvApiKey
    model
    options.toOpenAIResponsesOptions.toSimpleStreamOptions
  pure { options with apiKey := simple.apiKey }

def streamAzureOpenAIResponsesWithOptions : AzureOpenAIResponsesStream :=
  fun model context options => do
    LeanAgent.AI.Compat.ensureApiMatches
      { api := "azure-openai-responses"
        streams := LeanAgent.Models.azureOpenAIResponsesStreams
      }
      model
    let options ← withEnvApiKeyForAzureOpenAIResponses model options
    match options.apiKey with
    | none => throw (LeanAgent.Models.modelsError .auth s!"missing API key for provider {model.provider}")
    | some apiKey =>
        let config : LeanAgent.AI.Api.AzureOpenAIResponses.AzureOpenAIResponsesConfig :=
          { apiKey := apiKey
            baseUrl := model.baseUrl
          }
        LeanAgent.AI.Api.AzureOpenAIResponses.completeStreamWithOptions
          config
          model.toResponsesModel
          context
          options

def withEnvApiKeyForOpenAICodexResponses
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.OpenAICodexResponses.OpenAICodexResponsesOptions) :
    IO LeanAgent.AI.Api.OpenAICodexResponses.OpenAICodexResponsesOptions := do
  let simple ← LeanAgent.AI.Compat.withEnvApiKey model options.toSimpleStreamOptions
  pure { options with apiKey := simple.apiKey }

def streamOpenAICodexResponsesWithOptions : OpenAICodexResponsesStream :=
  fun model context options => do
    LeanAgent.AI.Compat.ensureApiMatches
      { api := LeanAgent.AI.Api.OpenAICodexResponses.api
        streams := LeanAgent.Models.openAICodexResponsesStreams
      }
      model
    let options ← withEnvApiKeyForOpenAICodexResponses model options
    match options.apiKey with
    | none => throw (LeanAgent.Models.modelsError .auth s!"missing OAuth access token for provider {model.provider}")
    | some apiKey =>
        let config : LeanAgent.AI.Api.OpenAICodexResponses.OpenAICodexResponsesConfig :=
          { apiKey := apiKey
            baseUrl := model.baseUrl
          }
        LeanAgent.AI.Api.OpenAICodexResponses.completeStreamWithOptions
          config
          model.toResponsesModel
          context
          options

def withEnvApiKeyForMistral
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.MistralConversations.MistralOptions) :
    IO LeanAgent.AI.Api.MistralConversations.MistralOptions := do
  let simple ← LeanAgent.AI.Compat.withEnvApiKey model options.toSimpleStreamOptions
  pure { options with apiKey := simple.apiKey }

def streamMistralWithOptions : MistralStream :=
  fun model context options => do
    LeanAgent.AI.Compat.ensureApiMatches
      { api := LeanAgent.AI.Api.MistralConversations.api
        streams := LeanAgent.Models.mistralConversationsStreams
      }
      model
    let options ← withEnvApiKeyForMistral model options
    let apiKey ← LeanAgent.Models.requireApiKeyOrHeaderAuth model.provider options.toSimpleStreamOptions
    let config : LeanAgent.AI.Api.MistralConversations.MistralConversationsConfig :=
      { apiKey := apiKey
        baseUrl := model.baseUrl
      }
    let stream ← LeanAgent.AI.Api.MistralConversations.completeStreamWithOptions
      config
      model.toModelRef
      model.input
      context
      options
    pure (LeanAgent.Models.applyUsageCostToStream model stream)

def streamAnthropic : AliasStream :=
  streamForApi "anthropic-messages"

def streamSimpleAnthropic : AliasStream :=
  streamAnthropic

def streamBedrockConverseStream : AliasStream :=
  streamForApi "bedrock-converse-stream"

def streamSimpleBedrockConverseStream : AliasStream :=
  streamBedrockConverseStream

def streamAzureOpenAIResponses : AzureOpenAIResponsesStream :=
  streamAzureOpenAIResponsesWithOptions

def streamSimpleAzureOpenAIResponses : AliasStream :=
  streamForApi "azure-openai-responses"

def streamGoogle : AliasStream :=
  streamForApi "google-generative-ai"

def streamSimpleGoogle : AliasStream :=
  streamGoogle

def streamGoogleVertex : AliasStream :=
  streamForApi "google-vertex"

def streamSimpleGoogleVertex : AliasStream :=
  streamGoogleVertex

def streamMistral : MistralStream :=
  streamMistralWithOptions

def streamSimpleMistral : AliasStream :=
  streamForApi "mistral-conversations"

def streamOpenAICodexResponses : OpenAICodexResponsesStream :=
  streamOpenAICodexResponsesWithOptions

def streamSimpleOpenAICodexResponses : AliasStream :=
  streamForApi "openai-codex-responses"

def streamOpenAICompletions : AliasStream :=
  streamForApi "openai-completions"

def streamSimpleOpenAICompletions : AliasStream :=
  streamOpenAICompletions

def streamOpenAIResponses : OpenAIResponsesStream :=
  streamOpenAIResponsesWithOptions

def streamSimpleOpenAIResponses : AliasStream :=
  streamForApi "openai-responses"

end LeanAgent.AI.Compat.Aliases
