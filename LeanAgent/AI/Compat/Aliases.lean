import LeanAgent.AI.Compat

namespace LeanAgent.AI.Compat.Aliases

abbrev AliasStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
    IO LeanAgent.AI.AssistantMessageEventStream

abbrev MistralStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.MistralConversations.MistralOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

def streamForApi (api : String) : AliasStream :=
  fun model context options => LeanAgent.AI.Compat.streamSimpleWithApi api model context options

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

def streamAzureOpenAIResponses : AliasStream :=
  streamForApi "azure-openai-responses"

def streamSimpleAzureOpenAIResponses : AliasStream :=
  streamAzureOpenAIResponses

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

def streamOpenAICodexResponses : AliasStream :=
  streamForApi "openai-codex-responses"

def streamSimpleOpenAICodexResponses : AliasStream :=
  streamOpenAICodexResponses

def streamOpenAICompletions : AliasStream :=
  streamForApi "openai-completions"

def streamSimpleOpenAICompletions : AliasStream :=
  streamOpenAICompletions

def streamOpenAIResponses : AliasStream :=
  streamForApi "openai-responses"

def streamSimpleOpenAIResponses : AliasStream :=
  streamOpenAIResponses

end LeanAgent.AI.Compat.Aliases
