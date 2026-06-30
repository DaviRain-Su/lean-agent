import LeanAgent.Core
import LeanAgent.AI.Api.AnthropicMessages
import LeanAgent.AI.Api.AzureOpenAIResponses
import LeanAgent.AI.Api.BedrockConverseStream
import LeanAgent.AI.Api.GoogleGenerativeAI
import LeanAgent.AI.Api.GoogleVertex
import LeanAgent.AI.Api.MistralConversations
import LeanAgent.AI.Api.OpenAICompletions
import LeanAgent.AI.Api.OpenAICodexResponses
import LeanAgent.AI.Api.OpenAIResponses
import LeanAgent.AI.Api.SimpleOptions
import LeanAgent.Models.Core

namespace LeanAgent.AI.Providers.Streams

def anthropicThinkingEffort
    (model : LeanAgent.Models.ModelInfo)
    (level : LeanAgent.AI.ThinkingLevel) : String :=
  match LeanAgent.Models.thinkingLevelMapValue? model (.level level) with
  | some (some mapped) => mapped
  | _ =>
      match level with
      | .minimal => "low"
      | .low => "low"
      | .medium => "medium"
      | .high => "high"
      | .xhigh => "high"

def openAICompletionsOptionsFromSimple
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
  let apiOptions := LeanAgent.AI.Api.OpenAICompletions.optionsFromSimple options
  let reasoningValue :=
    match apiOptions.reasoningEffort with
    | some effort => some (LeanAgent.Models.thinkingLevelPayloadValueD model (.level effort) effort.toString)
    | none =>
        match apiOptions.reasoning with
        | some effort => some (LeanAgent.Models.thinkingLevelPayloadValueD model (.level effort) effort.toString)
        | none => none
  let offValue :=
    if model.reasoning && reasoningValue.isNone then
      LeanAgent.Models.offThinkingLevelPayloadValue? model
    else
      none
  let offThinkingEnabled :=
    model.reasoning && LeanAgent.Models.thinkingLevelMapValue? model .off != some none
  { apiOptions with
    reasoningEffortValue := reasoningValue
    offReasoningEffortValue := offValue
    offThinkingEnabled := offThinkingEnabled
    supportsReasoningEffort := model.compat.supportsReasoningEffort
    maxTokensField := model.compat.maxTokensField
    supportsLongCacheRetention := model.compat.supportsLongCacheRetention
    sendSessionAffinityHeaders := model.compat.sendSessionAffinityHeaders
  }

def openAICompletionsModelFromModelInfo
    (model : LeanAgent.Models.ModelInfo) :
    LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsModel :=
  { id := model.id
    provider := model.provider
    api := model.api
    input := model.input
    reasoning := model.reasoning
    supportsStore := model.compat.supportsStore
    supportsDeveloperRole := model.compat.supportsDeveloperRole
    requiresThinkingAsText := model.compat.requiresThinkingAsText
    requiresReasoningContentOnAssistantMessages :=
      model.compat.requiresReasoningContentOnAssistantMessages
    thinkingFormat := model.compat.thinkingFormat
    chatTemplateKwargs := model.compat.chatTemplateKwargs
    zaiToolStream := model.compat.zaiToolStream
    supportsStrictMode := model.compat.supportsStrictMode
    cacheControlFormat := model.compat.cacheControlFormat
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

def contextToProviderRequest
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context) : ProviderRequest :=
  { model := model.id
    system := context.systemPrompt.getD ""
    messages := context.messages.map LeanAgent.AI.toLegacyMessage
    tools := context.tools.map legacyToolFromAITool
  }

def clampMaxTokensToContext
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (maxTokens : Nat) : Nat :=
  LeanAgent.AI.Api.SimpleOptions.clampMaxTokensToContext model.contextWindow context maxTokens

def resolvedMaxTokens?
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    Option Nat :=
  LeanAgent.AI.Api.SimpleOptions.resolvedMaxTokens? model.contextWindow model.maxTokens context options

def clampSimpleOptionsToContext
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions) : LeanAgent.AI.SimpleStreamOptions :=
  let options :=
    LeanAgent.AI.Api.SimpleOptions.clampStreamOptionsToContext model.contextWindow model.maxTokens context options
  match options.reasoning with
  | none => options
  | some level =>
      match LeanAgent.Models.clampThinkingLevel model (.level level) with
      | .off => { options with reasoning := none }
      | .level clamped => { options with reasoning := some clamped }

def hasHeaderAuth (headers : Array (String × Option String)) : Bool :=
  headers.any fun (name, value) =>
    let name := name.toLower
    let valueSet :=
      match value with
      | some value => !value.trimAscii.isEmpty
      | none => false
    valueSet &&
      (name == "authorization" || name == "x-api-key" || name == "x-goog-api-key" ||
        name == "cf-aig-authorization")

def requireApiKeyOrHeaderAuth
    (providerId : String)
    (options : LeanAgent.AI.SimpleStreamOptions) : IO String := do
  match options.apiKey with
  | some apiKey => pure apiKey
  | none =>
      if hasHeaderAuth options.headers then
        pure ""
      else
        throw (LeanAgent.Models.modelsError .auth s!"missing API key for provider {providerId}")

def openAICompatibleStreams : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
      let config : LeanAgent.AI.Api.OpenAICompletions.OpenAICompatibleConfig :=
        { apiKey := apiKey
          baseUrl := model.baseUrl
        }
      let stream ← LeanAgent.AI.Api.OpenAICompletions.streamContextWithOptions
        config
        (openAICompletionsModelFromModelInfo model)
        context
        (openAICompletionsOptionsFromSimple model options)
      pure (LeanAgent.Models.applyUsageCostToStream model stream)
  }

def openAIResponsesStreams : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
      let config : LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesConfig :=
        { apiKey := apiKey
          baseUrl := model.baseUrl
        }
      LeanAgent.AI.Api.OpenAIResponses.completeStreamWithOptions
        config
        model.toResponsesModel
        context
        (LeanAgent.AI.Api.OpenAIResponses.optionsFromSimple options)
  }

def openAICodexResponsesStreams : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
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
            (LeanAgent.AI.Api.OpenAICodexResponses.optionsFromSimple options)
  }

def azureOpenAIResponsesStreams : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
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
            (LeanAgent.AI.Api.AzureOpenAIResponses.optionsFromSimple options)
  }

def anthropicMessagesOptionsFromSimple
    (model : LeanAgent.Models.ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesOptions :=
  let base :=
    { LeanAgent.AI.Api.AnthropicMessages.optionsFromSimple options with
      supportsTemperature := model.compat.supportsTemperature
      sendSessionAffinityHeaders := model.compat.sendSessionAffinityHeaders
      supportsLongCacheRetention := model.compat.supportsLongCacheRetention
      supportsEagerToolInputStreaming := model.compat.supportsEagerToolInputStreaming
      supportsCacheControlOnTools := model.compat.supportsCacheControlOnTools
      allowEmptySignature := model.compat.allowEmptySignature
      forceAdaptiveThinking := model.compat.forceAdaptiveThinking
    }
  match options.reasoning with
  | none =>
      { base with thinkingEnabled := some false }
  | some level =>
      let maxTokens := (resolvedMaxTokens? model context options).getD model.maxTokens
      if model.compat.forceAdaptiveThinking then
        { base with
          maxTokens := some maxTokens
          thinkingEnabled := some true
          thinkingEffort := some (anthropicThinkingEffort model level)
        }
      else
        let adjusted := LeanAgent.AI.Api.SimpleOptions.adjustMaxTokensForThinking
          (some maxTokens) model.maxTokens level options.thinkingBudgets
        let thinkingBudget := Nat.min adjusted.thinkingBudget (maxTokens - Nat.min maxTokens 1024)
        { base with
          maxTokens := some maxTokens
          thinkingEnabled := some true
          thinkingBudgetTokens := some thinkingBudget
        }

def anthropicMessagesStreams : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
      let config : LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesConfig :=
        { apiKey := apiKey
          baseUrl := model.baseUrl
        }
      let stream ← LeanAgent.AI.Api.AnthropicMessages.completeStreamWithOptions
        config
        model.toModelRef
        model.input
        model.maxTokens
        model.reasoning
        context
        (anthropicMessagesOptionsFromSimple model context options)
      pure (LeanAgent.Models.applyUsageCostToStream model stream)
  }

def modelIdLower (model : LeanAgent.Models.ModelInfo) : String :=
  model.id.toLower

def isGemini3ProModel (model : LeanAgent.Models.ModelInfo) : Bool :=
  let id := modelIdLower model
  id.startsWith "gemini-3-pro" || id.startsWith "gemini-3.1-pro"

def isGemini3FlashModel (model : LeanAgent.Models.ModelInfo) : Bool :=
  let id := modelIdLower model
  id.startsWith "gemini-3-flash" ||
    id.startsWith "gemini-3.1-flash" ||
    id == "gemini-flash-latest" ||
    id == "gemini-flash-lite-latest"

def isGemma4Model (model : LeanAgent.Models.ModelInfo) : Bool :=
  (modelIdLower model).contains "gemma-4"

def googleDisabledThinkingLevel? (model : LeanAgent.Models.ModelInfo) : Option String :=
  if isGemini3ProModel model then
    some "LOW"
  else if isGemini3FlashModel model || isGemma4Model model then
    some "MINIMAL"
  else
    none

def googleThinkingLevel
    (model : LeanAgent.Models.ModelInfo)
    (effort : LeanAgent.AI.ThinkingLevel) : String :=
  if isGemini3ProModel model then
    match effort with
    | .minimal => "LOW"
    | .low => "LOW"
    | .medium => "HIGH"
    | .high => "HIGH"
    | .xhigh => "HIGH"
  else if isGemma4Model model then
    match effort with
    | .minimal => "MINIMAL"
    | .low => "MINIMAL"
    | .medium => "HIGH"
    | .high => "HIGH"
    | .xhigh => "HIGH"
  else
    match effort with
    | .minimal => "MINIMAL"
    | .low => "LOW"
    | .medium => "MEDIUM"
    | .high => "HIGH"
    | .xhigh => "HIGH"

def budgetForLevel (budgets : LeanAgent.AI.ThinkingBudgets) :
    LeanAgent.AI.ThinkingLevel → Option Nat
  | .minimal => budgets.minimal
  | .low => budgets.low
  | .medium => budgets.medium
  | .high => budgets.high
  | .xhigh => budgets.high

def googleThinkingBudget
    (model : LeanAgent.Models.ModelInfo)
    (effort : LeanAgent.AI.ThinkingLevel)
    (customBudgets : Option LeanAgent.AI.ThinkingBudgets) : Int :=
  match customBudgets.bind (fun budgets => budgetForLevel budgets effort) with
  | some budget => Int.ofNat budget
  | none =>
      if model.id.contains "2.5-pro" then
        match effort with
        | .minimal => 128
        | .low => 2048
        | .medium => 8192
        | .high => 32768
        | .xhigh => 32768
      else if model.id.contains "2.5-flash-lite" then
        match effort with
        | .minimal => 512
        | .low => 2048
        | .medium => 8192
        | .high => 24576
        | .xhigh => 24576
      else if model.id.contains "2.5-flash" then
        match effort with
        | .minimal => 128
        | .low => 2048
        | .medium => 8192
        | .high => 24576
        | .xhigh => 24576
      else
        -1

def googleGenerativeAIOptionsFromSimple
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIOptions :=
  let base := LeanAgent.AI.Api.GoogleGenerativeAI.optionsFromSimple options
  match options.reasoning with
  | none =>
      { base with
        thinkingEnabled := some false
        thinkingLevel := googleDisabledThinkingLevel? model
      }
  | some effort =>
      if isGemini3ProModel model || isGemini3FlashModel model || isGemma4Model model then
        { base with
          thinkingEnabled := some true
          thinkingLevel := some (googleThinkingLevel model effort)
        }
      else
        let budget := googleThinkingBudget model effort options.thinkingBudgets
        { base with
          thinkingEnabled := some true
          thinkingBudgetTokens := if budget < 0 then none else some budget.toNat
        }

def googleGenerativeAIStreams : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
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
        (googleGenerativeAIOptionsFromSimple model options)
      pure (LeanAgent.Models.applyUsageCostToStream model stream)
  }

def googleVertexOptionsFromSimple
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.GoogleVertex.GoogleVertexOptions :=
  let googleOptions := googleGenerativeAIOptionsFromSimple model options
  { temperature := googleOptions.temperature
    maxTokens := googleOptions.maxTokens
    apiKey := googleOptions.apiKey
    transport := googleOptions.transport
    cacheRetention := googleOptions.cacheRetention
    sessionId := googleOptions.sessionId
    headers := googleOptions.headers
    onPayload := googleOptions.onPayload
    onResponse := googleOptions.onResponse
    timeoutMs := googleOptions.timeoutMs
    websocketConnectTimeoutMs := googleOptions.websocketConnectTimeoutMs
    maxRetries := googleOptions.maxRetries
    maxRetryDelayMs := googleOptions.maxRetryDelayMs
    metadata := googleOptions.metadata
    env := googleOptions.env
    reasoning := googleOptions.reasoning
    thinkingBudgets := googleOptions.thinkingBudgets
    toolChoice :=
      match googleOptions.toolChoice with
      | some .auto => some .auto
      | some .none => some .none
      | some .any => some .any
      | none => none
    thinkingEnabled := googleOptions.thinkingEnabled
    thinkingBudgetTokens := googleOptions.thinkingBudgetTokens
    thinkingLevel := googleOptions.thinkingLevel
  }

def googleVertexStreams : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
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
        (googleVertexOptionsFromSimple model options)
      pure (LeanAgent.Models.applyUsageCostToStream model stream)
  }

def usesMistralReasoningEffort (model : LeanAgent.Models.ModelInfo) : Bool :=
  model.id == "mistral-small-2603" ||
    model.id == "mistral-small-latest" ||
    model.id == "mistral-medium-3.5"

def mistralReasoningEffort
    (model : LeanAgent.Models.ModelInfo)
    (level : LeanAgent.AI.ThinkingLevel) : String :=
  LeanAgent.Models.thinkingLevelPayloadValueD model (.level level) "high"

def mistralOptionsFromSimple
    (model : LeanAgent.Models.ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.MistralConversations.MistralOptions :=
  let base := LeanAgent.AI.Api.MistralConversations.optionsFromSimple options
  match options.reasoning with
  | none => base
  | some requested =>
      if !model.reasoning then
        base
      else
        match LeanAgent.Models.clampThinkingLevel model (.level requested) with
        | .off => base
        | .level level =>
            if usesMistralReasoningEffort model then
              { base with reasoningEffort := some (mistralReasoningEffort model level) }
            else
              { base with promptMode := some "reasoning" }

def mistralConversationsStreams : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
      let config : LeanAgent.AI.Api.MistralConversations.MistralConversationsConfig :=
        { apiKey := apiKey
          baseUrl := model.baseUrl
        }
      let stream ← LeanAgent.AI.Api.MistralConversations.completeStreamWithOptions
        config
        model.toModelRef
        model.input
        context
        (mistralOptionsFromSimple model options)
      pure (LeanAgent.Models.applyUsageCostToStream model stream)
  }

def placeholderAuthToken (value : String) : Bool :=
  value.startsWith "<" && value.endsWith ">"

def bedrockOptionsFromSimple
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.BedrockConverseStream.BedrockOptions :=
  let base := LeanAgent.AI.Api.BedrockConverseStream.optionsFromSimple options
  let bearerToken :=
    match options.apiKey with
    | some key =>
        let key := key.trimAscii.toString
        if key.isEmpty || placeholderAuthToken key then none else some key
    | none => none
  { base with bearerToken := bearerToken }

def bedrockConverseStreamStreams : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
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
        (bedrockOptionsFromSimple options)
      pure (LeanAgent.Models.applyUsageCostToStream model stream)
  }

end LeanAgent.AI.Providers.Streams
