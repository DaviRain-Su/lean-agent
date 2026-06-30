import LeanAgent.AI.Compat.Core
import LeanAgent.AI.Providers.Streams

namespace LeanAgent.AI.Compat.Aliases

abbrev AliasStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
    IO LeanAgent.AI.AssistantMessageEventStream

abbrev AliasComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
    IO LeanAgent.AI.AssistantMessage

abbrev MistralStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.MistralConversations.MistralOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev MistralComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.MistralConversations.MistralOptions →
      IO LeanAgent.AI.AssistantMessage

abbrev OpenAIResponsesStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev OpenAIResponsesComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesOptions →
      IO LeanAgent.AI.AssistantMessage

abbrev AzureOpenAIResponsesStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.AzureOpenAIResponses.AzureOpenAIResponsesOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev AzureOpenAIResponsesComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.AzureOpenAIResponses.AzureOpenAIResponsesOptions →
      IO LeanAgent.AI.AssistantMessage

abbrev OpenAICodexResponsesStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.OpenAICodexResponses.OpenAICodexResponsesOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev OpenAICodexResponsesComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.OpenAICodexResponses.OpenAICodexResponsesOptions →
      IO LeanAgent.AI.AssistantMessage

abbrev OpenAICompletionsStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev OpenAICompletionsComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions →
      IO LeanAgent.AI.AssistantMessage

abbrev AnthropicMessagesStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev AnthropicMessagesComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesOptions →
      IO LeanAgent.AI.AssistantMessage

abbrev GoogleGenerativeAIStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev GoogleGenerativeAIComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIOptions →
      IO LeanAgent.AI.AssistantMessage

abbrev GoogleVertexStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.GoogleVertex.GoogleVertexOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev GoogleVertexComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.GoogleVertex.GoogleVertexOptions →
      IO LeanAgent.AI.AssistantMessage

abbrev BedrockConverseStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.BedrockConverseStream.BedrockOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

abbrev BedrockConverseComplete :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context →
    LeanAgent.AI.Api.BedrockConverseStream.BedrockOptions →
      IO LeanAgent.AI.AssistantMessage

def streamForApi (api : String) : AliasStream :=
  fun model context options => LeanAgent.AI.Compat.streamSimpleWithApi api model context options

def completeForApi (api : String) : AliasComplete :=
  fun model context options => do
    let stream ← streamForApi api model context options
    pure stream.result

def withEnvApiKeyForAnthropicMessages
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesOptions) :
    IO LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesOptions := do
  let simple ← LeanAgent.AI.Compat.withEnvApiKey model options.toSimpleStreamOptions
  pure { options with apiKey := simple.apiKey }

def withModelCompatForAnthropicMessages
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesOptions) :
    LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesOptions :=
  { options with
    supportsTemperature := model.compat.supportsTemperature
    sendSessionAffinityHeaders := model.compat.sendSessionAffinityHeaders
    supportsLongCacheRetention := model.compat.supportsLongCacheRetention
    supportsEagerToolInputStreaming := model.compat.supportsEagerToolInputStreaming
    supportsCacheControlOnTools := model.compat.supportsCacheControlOnTools
    allowEmptySignature := model.compat.allowEmptySignature
    forceAdaptiveThinking := model.compat.forceAdaptiveThinking
  }

def streamAnthropicWithOptions : AnthropicMessagesStream :=
  fun model context options => do
    LeanAgent.AI.Compat.ensureApiMatches
      { api := LeanAgent.AI.Api.AnthropicMessages.api
        streams := LeanAgent.AI.Providers.Streams.anthropicMessagesStreams
      }
      model
    let options := withModelCompatForAnthropicMessages model options
    let options ← withEnvApiKeyForAnthropicMessages model options
    let apiKey ← LeanAgent.AI.Providers.Streams.requireApiKeyOrHeaderAuth model.provider options.toSimpleStreamOptions
    let config : LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesConfig :=
      { apiKey := apiKey
        baseUrl := model.baseUrl
      }
    LeanAgent.AI.Api.AnthropicMessages.completeStreamWithOptions
      config
      model.toModelRef
      model.input
      model.maxTokens
      model.reasoning
      context
      options

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
        streams := LeanAgent.AI.Providers.Streams.openAIResponsesStreams
      }
      model
    let options ← withEnvApiKeyForOpenAIResponses model options
    let apiKey ← LeanAgent.AI.Providers.Streams.requireApiKeyOrHeaderAuth model.provider options.toSimpleStreamOptions
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
        streams := LeanAgent.AI.Providers.Streams.azureOpenAIResponsesStreams
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
        streams := LeanAgent.AI.Providers.Streams.openAICodexResponsesStreams
      }
      model
    let options ← withEnvApiKeyForOpenAICodexResponses model options
    match options.apiKey with
    | none => throw (LeanAgent.Models.modelsError .oauth s!"missing OAuth access token for provider {model.provider}")
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

def withEnvApiKeyForOpenAICompletions
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions) :
    IO LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions := do
  let simple ← LeanAgent.AI.Compat.withEnvApiKey model options.toSimpleStreamOptions
  pure { options with apiKey := simple.apiKey }

def withModelCompatForOpenAICompletions
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions) :
    LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
  let reasoningValue :=
    match options.reasoningEffortValue with
    | some value => some value
    | none =>
        match options.reasoningEffort with
        | some effort =>
            some (LeanAgent.Models.thinkingLevelPayloadValueD model (.level effort) effort.toString)
        | none =>
            match options.reasoning with
            | some effort =>
                some (LeanAgent.Models.thinkingLevelPayloadValueD model (.level effort) effort.toString)
            | none => none
  let offValue :=
    match options.offReasoningEffortValue with
    | some value => some value
    | none =>
        if model.reasoning && reasoningValue.isNone then
          LeanAgent.Models.offThinkingLevelPayloadValue? model
        else
          none
  { options with
    reasoningEffortValue := reasoningValue
    offReasoningEffortValue := offValue
    supportsReasoningEffort := model.compat.supportsReasoningEffort
    maxTokensField := model.compat.maxTokensField
    supportsLongCacheRetention := model.compat.supportsLongCacheRetention
    sendSessionAffinityHeaders := model.compat.sendSessionAffinityHeaders
  }

def streamOpenAICompletionsWithOptions : OpenAICompletionsStream :=
  fun model context options => do
    LeanAgent.AI.Compat.ensureApiMatches
      { api := "openai-completions"
        streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams
      }
      model
    let options := withModelCompatForOpenAICompletions model options
    let options ← withEnvApiKeyForOpenAICompletions model options
    let apiKey ← LeanAgent.AI.Providers.Streams.requireApiKeyOrHeaderAuth model.provider options.toSimpleStreamOptions
    let config : LeanAgent.AI.Api.OpenAICompletions.OpenAICompatibleConfig :=
      { apiKey := apiKey
        baseUrl := model.baseUrl
      }
    let stream ← LeanAgent.AI.Api.OpenAICompletions.streamContextWithOptions
      config
      (LeanAgent.AI.Providers.Streams.openAICompletionsModelFromModelInfo model)
      context
      options
    pure (LeanAgent.Models.applyUsageCostToStream model stream)

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
        streams := LeanAgent.AI.Providers.Streams.mistralConversationsStreams
      }
      model
    let options ← withEnvApiKeyForMistral model options
    let apiKey ← LeanAgent.AI.Providers.Streams.requireApiKeyOrHeaderAuth model.provider options.toSimpleStreamOptions
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

def withEnvApiKeyForGoogleGenerativeAI
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIOptions) :
    IO LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIOptions := do
  let simple ← LeanAgent.AI.Compat.withEnvApiKey model options.toSimpleStreamOptions
  pure { options with apiKey := simple.apiKey }

def streamGoogleWithOptions : GoogleGenerativeAIStream :=
  fun model context options => do
    LeanAgent.AI.Compat.ensureApiMatches
      { api := LeanAgent.AI.Api.GoogleGenerativeAI.api
        streams := LeanAgent.AI.Providers.Streams.googleGenerativeAIStreams
      }
      model
    let options ← withEnvApiKeyForGoogleGenerativeAI model options
    let apiKey ← LeanAgent.AI.Providers.Streams.requireApiKeyOrHeaderAuth model.provider options.toSimpleStreamOptions
    let config : LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIConfig :=
      { apiKey := apiKey
        baseUrl := model.baseUrl
      }
    let stream ← LeanAgent.AI.Api.GoogleGenerativeAI.completeStreamWithOptions
      config
      model.toModelRef
      model.input
      model.reasoning
      context
      options
    pure (LeanAgent.Models.applyUsageCostToStream model stream)

def withEnvApiKeyForGoogleVertex
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.GoogleVertex.GoogleVertexOptions) :
    IO LeanAgent.AI.Api.GoogleVertex.GoogleVertexOptions := do
  let simple ← LeanAgent.AI.Compat.withEnvApiKey model options.toSimpleStreamOptions
  pure { options with apiKey := simple.apiKey }

def streamGoogleVertexWithOptions : GoogleVertexStream :=
  fun model context options => do
    LeanAgent.AI.Compat.ensureApiMatches
      { api := LeanAgent.AI.Api.GoogleVertex.api
        streams := LeanAgent.AI.Providers.Streams.googleVertexStreams
      }
      model
    let options ← withEnvApiKeyForGoogleVertex model options
    let config : LeanAgent.AI.Api.GoogleVertex.GoogleVertexConfig :=
      { apiKey := options.apiKey.getD ""
        baseUrl := model.baseUrl
      }
    let stream ← LeanAgent.AI.Api.GoogleVertex.completeStreamWithOptions
      config
      model.toModelRef
      model.input
      model.reasoning
      context
      options
    pure (LeanAgent.Models.applyUsageCostToStream model stream)

def nonPlaceholderToken? (token : Option String) : Option String :=
  match token with
  | none => none
  | some token =>
      let token := token.trimAscii.toString
      if token.isEmpty || (token.startsWith "<" && token.endsWith ">") then none else some token

def withEnvApiKeyForBedrockConverseStream
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.Api.BedrockConverseStream.BedrockOptions) :
    IO LeanAgent.AI.Api.BedrockConverseStream.BedrockOptions := do
  let simple ← LeanAgent.AI.Compat.withEnvApiKey model options.toSimpleStreamOptions
  pure
    { options with
      apiKey := simple.apiKey
      bearerToken := options.bearerToken <|> nonPlaceholderToken? simple.apiKey
    }

def streamBedrockConverseStreamWithOptions : BedrockConverseStream :=
  fun model context options => do
    LeanAgent.AI.Compat.ensureApiMatches
      { api := LeanAgent.AI.Api.BedrockConverseStream.api
        streams := LeanAgent.AI.Providers.Streams.bedrockConverseStreamStreams
      }
      model
    let options ← withEnvApiKeyForBedrockConverseStream model options
    let config : LeanAgent.AI.Api.BedrockConverseStream.BedrockConverseStreamConfig :=
      { baseUrl := model.baseUrl }
    let stream ← LeanAgent.AI.Api.BedrockConverseStream.completeStreamWithOptions
      config
      model.toModelRef
      model.input
      model.name
      model.thinkingLevelMap
      model.reasoning
      context
      options
    pure (LeanAgent.Models.applyUsageCostToStream model stream)

def streamAnthropic : AnthropicMessagesStream :=
  streamAnthropicWithOptions

def completeAnthropic : AnthropicMessagesComplete :=
  fun model context options => do
    let stream ← streamAnthropic model context options
    pure stream.result

def streamSimpleAnthropic : AliasStream :=
  streamForApi "anthropic-messages"

def completeSimpleAnthropic : AliasComplete :=
  completeForApi "anthropic-messages"

def streamBedrockConverseStream : BedrockConverseStream :=
  streamBedrockConverseStreamWithOptions

def completeBedrockConverseStream : BedrockConverseComplete :=
  fun model context options => do
    let stream ← streamBedrockConverseStream model context options
    pure stream.result

def streamSimpleBedrockConverseStream : AliasStream :=
  streamForApi "bedrock-converse-stream"

def completeSimpleBedrockConverseStream : AliasComplete :=
  completeForApi "bedrock-converse-stream"

def streamAzureOpenAIResponses : AzureOpenAIResponsesStream :=
  streamAzureOpenAIResponsesWithOptions

def completeAzureOpenAIResponses : AzureOpenAIResponsesComplete :=
  fun model context options => do
    let stream ← streamAzureOpenAIResponses model context options
    pure stream.result

def streamSimpleAzureOpenAIResponses : AliasStream :=
  streamForApi "azure-openai-responses"

def completeSimpleAzureOpenAIResponses : AliasComplete :=
  completeForApi "azure-openai-responses"

def streamGoogle : GoogleGenerativeAIStream :=
  streamGoogleWithOptions

def completeGoogle : GoogleGenerativeAIComplete :=
  fun model context options => do
    let stream ← streamGoogle model context options
    pure stream.result

def streamSimpleGoogle : AliasStream :=
  streamForApi "google-generative-ai"

def completeSimpleGoogle : AliasComplete :=
  completeForApi "google-generative-ai"

def streamGoogleVertex : GoogleVertexStream :=
  streamGoogleVertexWithOptions

def completeGoogleVertex : GoogleVertexComplete :=
  fun model context options => do
    let stream ← streamGoogleVertex model context options
    pure stream.result

def streamSimpleGoogleVertex : AliasStream :=
  streamForApi "google-vertex"

def completeSimpleGoogleVertex : AliasComplete :=
  completeForApi "google-vertex"

def streamMistral : MistralStream :=
  streamMistralWithOptions

def completeMistral : MistralComplete :=
  fun model context options => do
    let stream ← streamMistral model context options
    pure stream.result

def streamSimpleMistral : AliasStream :=
  streamForApi "mistral-conversations"

def completeSimpleMistral : AliasComplete :=
  completeForApi "mistral-conversations"

def streamOpenAICodexResponses : OpenAICodexResponsesStream :=
  streamOpenAICodexResponsesWithOptions

def completeOpenAICodexResponses : OpenAICodexResponsesComplete :=
  fun model context options => do
    let stream ← streamOpenAICodexResponses model context options
    pure stream.result

def streamSimpleOpenAICodexResponses : AliasStream :=
  streamForApi "openai-codex-responses"

def completeSimpleOpenAICodexResponses : AliasComplete :=
  completeForApi "openai-codex-responses"

def streamOpenAICompletions : OpenAICompletionsStream :=
  streamOpenAICompletionsWithOptions

def completeOpenAICompletions : OpenAICompletionsComplete :=
  fun model context options => do
    let stream ← streamOpenAICompletions model context options
    pure stream.result

def streamSimpleOpenAICompletions : AliasStream :=
  streamForApi "openai-completions"

def completeSimpleOpenAICompletions : AliasComplete :=
  completeForApi "openai-completions"

def streamOpenAIResponses : OpenAIResponsesStream :=
  streamOpenAIResponsesWithOptions

def completeOpenAIResponses : OpenAIResponsesComplete :=
  fun model context options => do
    let stream ← streamOpenAIResponses model context options
    pure stream.result

def streamSimpleOpenAIResponses : AliasStream :=
  streamForApi "openai-responses"

def completeSimpleOpenAIResponses : AliasComplete :=
  completeForApi "openai-responses"

end LeanAgent.AI.Compat.Aliases
