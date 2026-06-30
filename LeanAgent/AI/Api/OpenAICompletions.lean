import Lean
import LeanAgent.AI.Api.OpenAIPromptCache
import LeanAgent.AI.Api.TransformMessages
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.JsonParse
import LeanAgent.AI.Util.Retry
import LeanAgent.AI.Util.SSE
import LeanAgent.AI.Util.SanitizeUnicode
import LeanAgent.Core
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.OpenAICompletions

open LeanAgent

structure OpenAICompatibleConfig where
  apiKey : String
  baseUrl : String := "https://api.openai.com/v1"
  providerId : String := ""
  headers : Array (String × String) := #[]
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

inductive ToolChoice where
  | auto
  | none
  | required
  | function (name : String)
deriving BEq

structure OpenAICompletionsOptions extends LeanAgent.AI.SimpleStreamOptions where
  toolChoice : Option ToolChoice := none
  reasoningEffort : Option LeanAgent.AI.ThinkingLevel := none
  reasoningEffortValue : Option String := none
  offReasoningEffortValue : Option String := none
  offThinkingEnabled : Bool := false
  supportsReasoningEffort : Bool := true
  supportsUsageInStreaming : Bool := true
  maxTokensField : String := "max_tokens"
  supportsLongCacheRetention : Bool := true
  sendSessionAffinityHeaders : Bool := false

structure OpenAICompletionsModel extends LeanAgent.AI.Api.TransformMessages.TargetModel where
  reasoning : Bool := false
  thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[]
  supportsStore : Bool := true
  supportsDeveloperRole : Bool := true
  requiresThinkingAsText : Bool := false
  requiresReasoningContentOnAssistantMessages : Bool := false
  requiresToolResultName : Bool := false
  requiresAssistantAfterToolResult : Bool := false
  thinkingFormat : Option String := none
  chatTemplateKwargs : Option Lean.Json := none
  openRouterRouting : Option Lean.Json := none
  vercelGatewayRouting : Option Lean.Json := none
  zaiToolStream : Bool := false
  supportsStrictMode : Bool := true
  cacheControlFormat : Option String := none
deriving BEq

structure OpenAICompletionsCompatOverride where
  supportsStore : Option Bool := none
  supportsDeveloperRole : Option Bool := none
  requiresThinkingAsText : Option Bool := none
  requiresReasoningContentOnAssistantMessages : Option Bool := none
  requiresToolResultName : Option Bool := none
  requiresAssistantAfterToolResult : Option Bool := none
  thinkingFormat : Option String := none
  chatTemplateKwargs : Option Lean.Json := none
  openRouterRouting : Option Lean.Json := none
  vercelGatewayRouting : Option Lean.Json := none
  zaiToolStream : Option Bool := none
  supportsStrictMode : Option Bool := none
  cacheControlFormat : Option String := none
  supportsReasoningEffort : Option Bool := none
  supportsUsageInStreaming : Option Bool := none
  maxTokensField : Option String := none
  supportsLongCacheRetention : Option Bool := none
  sendSessionAffinityHeaders : Option Bool := none

structure ResolvedOpenAICompletionsCompat where
  supportsStore : Bool := true
  supportsDeveloperRole : Bool := true
  requiresThinkingAsText : Bool := false
  requiresReasoningContentOnAssistantMessages : Bool := false
  requiresToolResultName : Bool := false
  requiresAssistantAfterToolResult : Bool := false
  thinkingFormat : Option String := some "openai"
  chatTemplateKwargs : Option Lean.Json := none
  openRouterRouting : Option Lean.Json := none
  vercelGatewayRouting : Option Lean.Json := none
  zaiToolStream : Bool := false
  supportsStrictMode : Bool := true
  cacheControlFormat : Option String := none
  supportsReasoningEffort : Bool := true
  supportsUsageInStreaming : Bool := true
  maxTokensField : String := "max_completion_tokens"
  supportsLongCacheRetention : Bool := true
  sendSessionAffinityHeaders : Bool := false

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : OpenAICompletionsOptions :=
  { temperature := options.temperature
    maxTokens := options.maxTokens
    signal := options.signal
    apiKey := options.apiKey
    transport := options.transport
    cacheRetention := options.cacheRetention
    sessionId := options.sessionId
    headers := options.headers
    onPayload := options.onPayload
    onResponse := options.onResponse
    timeoutMs := options.timeoutMs
    websocketConnectTimeoutMs := options.websocketConnectTimeoutMs
    maxRetries := options.maxRetries
    maxRetryDelayMs := options.maxRetryDelayMs
    metadata := options.metadata
    env := options.env
    reasoning := options.reasoning
    thinkingBudgets := options.thinkingBudgets
  }

def detectCompat
    (provider baseUrl modelId : String) : ResolvedOpenAICompletionsCompat :=
  let togetherReasoningEffortModelIds : Array String :=
    #["openai/gpt-oss-120b", "openai/gpt-oss-20b"]
  let togetherReasoningOnlyModelIds : Array String :=
    #["deepseek-ai/DeepSeek-R1", "MiniMaxAI/MiniMax-M2.7"]
  let isZai :=
    provider == "zai" || provider == "zai-coding-cn" ||
      baseUrl.contains "api.z.ai" || baseUrl.contains "open.bigmodel.cn"
  let isTogether :=
    provider == "together" || baseUrl.contains "api.together.ai" || baseUrl.contains "api.together.xyz"
  let isTogetherReasoningEffort :=
    isTogether && togetherReasoningEffortModelIds.contains modelId
  let isTogetherReasoningOnly :=
    isTogether && togetherReasoningOnlyModelIds.contains modelId
  let isMoonshot :=
    provider == "moonshotai" || provider == "moonshotai-cn" || baseUrl.contains "api.moonshot."
  let isOpenRouter := provider == "openrouter" || baseUrl.contains "openrouter.ai"
  let isCloudflareWorkersAI :=
    provider == "cloudflare-workers-ai" || baseUrl.contains "api.cloudflare.com"
  let isCloudflareAiGateway :=
    provider == "cloudflare-ai-gateway" || baseUrl.contains "gateway.ai.cloudflare.com"
  let isNvidia := provider == "nvidia" || baseUrl.contains "integrate.api.nvidia.com"
  let isAntLing := provider == "ant-ling" || baseUrl.contains "api.ant-ling.com"
  let isCerebras := provider == "cerebras" || baseUrl.contains "cerebras.ai"
  let isGrok := provider == "xai" || baseUrl.contains "api.x.ai"
  let isDeepSeek := provider == "deepseek" || baseUrl.contains "deepseek.com"
  let isOpenCode := provider == "opencode" || baseUrl.contains "opencode.ai"
  let isNonStandard :=
    isNvidia || isCerebras || isGrok || isTogether || baseUrl.contains "chutes.ai" ||
      baseUrl.contains "deepseek.com" || isZai || isMoonshot || isOpenCode ||
      isCloudflareWorkersAI || isCloudflareAiGateway || isAntLing
  let useMaxTokens :=
    baseUrl.contains "chutes.ai" || isMoonshot || isCloudflareAiGateway ||
      isTogether || isNvidia || isAntLing
  let supportsDeveloperRole :=
    (isOpenRouter && (modelId.startsWith "anthropic/" || modelId.startsWith "openai/")) ||
      (!isNonStandard && !isOpenRouter)
  let thinkingFormat :=
    if isDeepSeek then
      some "deepseek"
    else if isMoonshot then
      some "deepseek"
    else if isZai then
      some "zai"
    else if isTogether && !(isTogetherReasoningEffort || isTogetherReasoningOnly) then
      some "together"
    else if isAntLing then
      some "ant-ling"
    else if isOpenRouter then
      some "openrouter"
    else
      some "openai"
  let cacheControlFormat :=
    if provider == "openrouter" && modelId.startsWith "anthropic/" then
      some "anthropic"
    else
      none
  { supportsStore := !isNonStandard
    supportsDeveloperRole := supportsDeveloperRole
    requiresThinkingAsText := false
    requiresReasoningContentOnAssistantMessages := isDeepSeek
    requiresToolResultName := false
    requiresAssistantAfterToolResult := false
    thinkingFormat := thinkingFormat
    chatTemplateKwargs := none
    openRouterRouting := none
    vercelGatewayRouting := none
    zaiToolStream := false
    supportsStrictMode := !(isMoonshot || isTogether || isCloudflareAiGateway || isNvidia)
    cacheControlFormat := cacheControlFormat
    supportsReasoningEffort :=
      isTogetherReasoningEffort ||
        !(isGrok || isZai || isMoonshot || isTogether || isCloudflareAiGateway || isNvidia || isAntLing)
    supportsUsageInStreaming := true
    maxTokensField := if useMaxTokens then "max_tokens" else "max_completion_tokens"
    supportsLongCacheRetention :=
      !(isTogether || isCloudflareWorkersAI || isCloudflareAiGateway || isNvidia || isAntLing)
    sendSessionAffinityHeaders := false
  }

def resolveCompat
    (provider baseUrl modelId : String)
    (override : OpenAICompletionsCompatOverride := {}) : ResolvedOpenAICompletionsCompat :=
  let detected := detectCompat provider baseUrl modelId
  { supportsStore := override.supportsStore.getD detected.supportsStore
    supportsDeveloperRole := override.supportsDeveloperRole.getD detected.supportsDeveloperRole
    requiresThinkingAsText := override.requiresThinkingAsText.getD detected.requiresThinkingAsText
    requiresReasoningContentOnAssistantMessages :=
      override.requiresReasoningContentOnAssistantMessages.getD
        detected.requiresReasoningContentOnAssistantMessages
    requiresToolResultName :=
      override.requiresToolResultName.getD detected.requiresToolResultName
    requiresAssistantAfterToolResult :=
      override.requiresAssistantAfterToolResult.getD
        detected.requiresAssistantAfterToolResult
    thinkingFormat := override.thinkingFormat <|> detected.thinkingFormat
    chatTemplateKwargs := override.chatTemplateKwargs <|> detected.chatTemplateKwargs
    openRouterRouting := override.openRouterRouting <|> detected.openRouterRouting
    vercelGatewayRouting := override.vercelGatewayRouting <|> detected.vercelGatewayRouting
    zaiToolStream := override.zaiToolStream.getD detected.zaiToolStream
    supportsStrictMode := override.supportsStrictMode.getD detected.supportsStrictMode
    cacheControlFormat := override.cacheControlFormat <|> detected.cacheControlFormat
    supportsReasoningEffort := override.supportsReasoningEffort.getD detected.supportsReasoningEffort
    supportsUsageInStreaming :=
      override.supportsUsageInStreaming.getD detected.supportsUsageInStreaming
    maxTokensField := override.maxTokensField.getD detected.maxTokensField
    supportsLongCacheRetention :=
      override.supportsLongCacheRetention.getD detected.supportsLongCacheRetention
    sendSessionAffinityHeaders :=
      override.sendSessionAffinityHeaders.getD detected.sendSessionAffinityHeaders
  }

def chatCompletionsUrl (baseUrl : String) : String :=
  if baseUrl.endsWith "/chat/completions" then
    baseUrl
  else if baseUrl.endsWith "/" then
    baseUrl ++ "chat/completions"
  else
    baseUrl ++ "/chat/completions"

def ToolChoice.toJson : ToolChoice → Lean.Json
  | .auto => LeanAgent.Json.str "auto"
  | .none => LeanAgent.Json.str "none"
  | .required => LeanAgent.Json.str "required"
  | .function name =>
      LeanAgent.Json.obj
        [ ("type", LeanAgent.Json.str "function")
        , ("function", LeanAgent.Json.obj [("name", LeanAgent.Json.str name)])
        ]

def reasoningEffortString : LeanAgent.AI.ThinkingLevel → String
  | .xhigh => "high"
  | level => level.toString

def requestReasoningEffortString
    (options : OpenAICompletionsOptions)
    (effort : LeanAgent.AI.ThinkingLevel) : String :=
  options.reasoningEffortValue.getD (reasoningEffortString effort)

def OpenAICompletionsModel.toModelRef
    (model : OpenAICompletionsModel)
    (baseUrl : String) : LeanAgent.AI.ModelRef :=
  { id := model.id
    api := model.api
    provider := model.provider
    baseUrl := some baseUrl
  }

def takeChars (value : String) (count : Nat) : String :=
  String.ofList (value.toList.take count)

def normalizeToolCallIdValue (provider : String) (id : String) : String :=
  if id.contains "|" then
    let callId := (id.splitOn "|").head!
    LeanAgent.AI.Api.TransformMessages.sanitizeToolCallId callId 40
  else if provider == "openai" && id.length > 40 then
    takeChars id 40
  else
    id

def normalizeToolCallId
    (model : OpenAICompletionsModel) :
    LeanAgent.AI.Api.TransformMessages.NormalizeToolCallId :=
  fun id _target _source => normalizeToolCallIdValue model.provider id

def toolCallToJson (call : LeanAgent.ToolCall) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("id", LeanAgent.Json.str call.id)
    , ("type", LeanAgent.Json.str "function")
    , ("function",
        LeanAgent.Json.obj
          [ ("name", LeanAgent.Json.str call.name)
          , ("arguments", LeanAgent.Json.str call.arguments.compress)
          ])
    ]

def messageHasToolCall : LeanAgent.AgentMessage → Bool
  | .assistant _ calls => !calls.isEmpty
  | .toolResult _ _ _ _ => true
  | _ => false

def hasToolHistory (messages : Array LeanAgent.AgentMessage) : Bool :=
  messages.any messageHasToolCall

def sanitize (text : String) : String :=
  LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates text

def contentPartTextJson (text : String) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "text")
    , ("text", LeanAgent.Json.str (sanitize text))
    ]

def contentPartImageJson (image : LeanAgent.AI.ImageContent) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "image_url")
    , ("image_url",
        LeanAgent.Json.obj
          [ ("url", LeanAgent.Json.str s!"data:{image.mimeType};base64,{image.data}") ])
    ]

def contentText? : LeanAgent.AI.ContentBlock → Option String
  | .text content => some content.text
  | _ => none

def contentImage? : LeanAgent.AI.ContentBlock → Option LeanAgent.AI.ImageContent
  | .image content => some content
  | _ => none

def userContentParts (content : Array LeanAgent.AI.ContentBlock) : Array Lean.Json :=
  content.filterMap fun block =>
    match block with
    | .text text => some (contentPartTextJson text.text)
    | .image image => some (contentPartImageJson image)
    | _ => none

def aiToolCallToJson (call : LeanAgent.AI.ToolCall) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("id", LeanAgent.Json.str call.id)
    , ("type", LeanAgent.Json.str "function")
    , ("function",
        LeanAgent.Json.obj
          [ ("name", LeanAgent.Json.str call.name)
          , ("arguments", LeanAgent.Json.str call.arguments.compress)
          ])
    ]

def aiToolToJson (supportsStrictMode : Bool) (tool : LeanAgent.AI.Tool) : Lean.Json :=
  let functionFields :=
    [ ("name", LeanAgent.Json.str tool.name)
    , ("description", LeanAgent.Json.str tool.description)
    , ("parameters", tool.parameters)
    ] ++ if supportsStrictMode then [("strict", LeanAgent.Json.bool false)] else []
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "function")
    , ("function", LeanAgent.Json.obj functionFields)
    ]

def messageHasAIToolHistory : LeanAgent.AI.Message → Bool
  | .assistant assistant =>
      assistant.content.any fun block =>
        match block with
        | .toolCall _ => true
        | _ => false
  | .toolResult _ => true
  | .user _ => false

def hasAIToolHistory (messages : Array LeanAgent.AI.Message) : Bool :=
  messages.any messageHasAIToolHistory

def requestToolsForContext?
    (model : OpenAICompletionsModel)
    (context : LeanAgent.AI.Context)
    (messages : Array LeanAgent.AI.Message) : Option (Array Lean.Json) :=
  if !context.tools.isEmpty || hasAIToolHistory messages then
    some (context.tools.map (aiToolToJson model.supportsStrictMode))
  else
    none

def requestToolChoiceForContext?
    (context : LeanAgent.AI.Context)
    (messages : Array LeanAgent.AI.Message)
    (options : OpenAICompletionsOptions) : Option Lean.Json :=
  if !context.tools.isEmpty || hasAIToolHistory messages then
    some ((options.toolChoice.getD .auto).toJson)
  else
    none

def requestToolStreamForContext?
    (model : OpenAICompletionsModel)
    (context : LeanAgent.AI.Context) : Option Lean.Json :=
  if model.zaiToolStream && !context.tools.isEmpty then
    some (LeanAgent.Json.bool true)
  else
    none

def reasoningTextBlocks (content : Array LeanAgent.AI.ContentBlock) :
    Array LeanAgent.AI.ThinkingContent :=
  content.filterMap fun block =>
    match block with
    | .thinking thinking =>
        if thinking.thinking.trimAscii.toString.isEmpty then none else some thinking
    | _ => none

def assistantText (content : Array LeanAgent.AI.ContentBlock) : String :=
  String.intercalate ""
    (content.toList.filterMap fun block =>
      match block with
      | .text text =>
          if text.text.trimAscii.toString.isEmpty then none else some (sanitize text.text)
      | _ => none)

def assistantTextParts (content : Array LeanAgent.AI.ContentBlock) : Array Lean.Json :=
  content.filterMap fun block =>
    match block with
    | .text text =>
        if text.text.trimAscii.toString.isEmpty then
          none
        else
          some (contentPartTextJson text.text)
    | _ => none

def assistantThinkingText?
    (content : Array LeanAgent.AI.ContentBlock) : Option String :=
  let thinkingBlocks := reasoningTextBlocks content
  if thinkingBlocks.isEmpty then
    none
  else
    some
      (sanitize
        (String.intercalate "\n\n" (thinkingBlocks.map (·.thinking) |>.toList)))

def normalizeReasoningSignature (provider signature : String) : String :=
  if provider == "opencode-go" && signature == "reasoning" then
    "reasoning_content"
  else
    signature

def assistantThinkingField?
    (model : OpenAICompletionsModel)
    (content : Array LeanAgent.AI.ContentBlock) : Option (String × Lean.Json) :=
  let thinkingBlocks := reasoningTextBlocks content
  match thinkingBlocks[0]? with
  | some first =>
      match first.thinkingSignature with
      | some signature =>
          let key := normalizeReasoningSignature model.provider signature
          some
            (key,
              LeanAgent.Json.str
                (sanitize (String.intercalate "\n" (thinkingBlocks.map (·.thinking) |>.toList))))
      | none =>
          if model.reasoning && model.requiresReasoningContentOnAssistantMessages then
            some ("reasoning_content", LeanAgent.Json.str "")
          else
            none
  | none =>
      if model.reasoning && model.requiresReasoningContentOnAssistantMessages then
        some ("reasoning_content", LeanAgent.Json.str "")
      else
        none

def assistantMessageJson?
    (model : OpenAICompletionsModel)
    (assistant : LeanAgent.AI.AssistantMessage) : Option Lean.Json :=
  let content := assistantText assistant.content
  let contentParts := assistantTextParts assistant.content
  let toolCalls := LeanAgent.AI.contentToolCalls assistant.content
  let thinkingText? := assistantThinkingText? assistant.content
  let thinkingField? :=
    if model.requiresThinkingAsText then none else assistantThinkingField? model assistant.content
  let reasoningDetails :=
    toolCalls.filterMap fun call =>
      call.thoughtSignature.bind fun raw =>
        match Lean.Json.parse raw with
        | .ok parsed => some parsed
        | .error _ => none
  let contentJson? :=
    if model.requiresThinkingAsText then
      match thinkingText? with
      | some thinkingText =>
          let replayParts := #[contentPartTextJson thinkingText] ++ contentParts
          if replayParts.isEmpty then none else some (LeanAgent.Json.arr replayParts)
      | none =>
          if content.isEmpty then none else some (LeanAgent.Json.str content)
    else if content.isEmpty then
      none
    else
      some (LeanAgent.Json.str content)
  let hasContent := contentJson?.isSome
  if !hasContent && toolCalls.isEmpty then
    none
  else
    let emptyAssistantContent :=
      if model.requiresAssistantAfterToolResult then
        LeanAgent.Json.str ""
      else
        LeanAgent.Json.null
    let baseFields :=
      [ ("role", LeanAgent.Json.str "assistant")
      , ("content", contentJson?.getD emptyAssistantContent)
      ]
    let toolFields :=
      if toolCalls.isEmpty then
        []
      else
        [("tool_calls", LeanAgent.Json.arr (toolCalls.map aiToolCallToJson))]
    let reasoningDetailFields :=
      if reasoningDetails.isEmpty then
        []
      else
        [("reasoning_details", LeanAgent.Json.arr reasoningDetails)]
    let thinkingFields :=
      match thinkingField? with
      | some (key, value) => [(key, value)]
      | none => []
    some (LeanAgent.Json.obj (baseFields ++ toolFields ++ reasoningDetailFields ++ thinkingFields))

def toolResultCallId (id : String) : String :=
  match id.splitOn "|" with
  | [] => id
  | callId :: _ => callId

def toolResultText (content : Array LeanAgent.AI.ContentBlock) : String :=
  String.intercalate "\n" (content.toList.filterMap contentText?)

def toolResultImageParts (content : Array LeanAgent.AI.ContentBlock) : Array Lean.Json :=
  content.filterMap fun block => (contentImage? block).map contentPartImageJson

def toolResultMessageJson (message : LeanAgent.AI.ToolResultMessage) : Lean.Json :=
  let text := toolResultText message.content
  let rendered := if text.isEmpty then "(see attached image)" else text
  LeanAgent.Json.obj
    [ ("role", LeanAgent.Json.str "tool")
    , ("tool_call_id", LeanAgent.Json.str (toolResultCallId message.toolCallId))
    , ("content", LeanAgent.Json.str (sanitize rendered))
    ]

def compatToolResultMessageJson
    (model : OpenAICompletionsModel)
    (message : LeanAgent.AI.ToolResultMessage) : Lean.Json :=
  let fields :=
    [ ("role", LeanAgent.Json.str "tool")
    , ("tool_call_id", LeanAgent.Json.str (toolResultCallId message.toolCallId))
    , ("content", LeanAgent.Json.str (sanitize (if (toolResultText message.content).isEmpty then "(see attached image)" else toolResultText message.content)))
    ] ++
      if model.requiresToolResultName then
        [("name", LeanAgent.Json.str message.toolName)]
      else
        []
  LeanAgent.Json.obj fields

def assistantToolResultBridgeMessageJson : Lean.Json :=
  LeanAgent.Json.obj
    [ ("role", LeanAgent.Json.str "assistant")
    , ("content", LeanAgent.Json.str "I have processed the tool results.")
    ]

def groupedToolResultImageMessageJson (imageParts : Array Lean.Json) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("role", LeanAgent.Json.str "user")
    , ("content",
        LeanAgent.Json.arr
          (#[contentPartTextJson "Attached image(s) from tool result:"] ++ imageParts))
    ]

def collectLeadingToolResultsAux
    (acc : Array LeanAgent.AI.ToolResultMessage) :
    List LeanAgent.AI.Message → Array LeanAgent.AI.ToolResultMessage × List LeanAgent.AI.Message
  | .toolResult message :: rest => collectLeadingToolResultsAux (acc.push message) rest
  | remaining => (acc, remaining)

def collectLeadingToolResults :
    List LeanAgent.AI.Message → Array LeanAgent.AI.ToolResultMessage × List LeanAgent.AI.Message :=
  collectLeadingToolResultsAux #[]

partial def convertMessagesLoop
    (model : OpenAICompletionsModel)
    (messages : List LeanAgent.AI.Message)
    (afterToolResult : Bool := false)
    (acc : Array Lean.Json := #[]) : Array Lean.Json :=
  match messages with
  | [] => acc
  | .user user :: rest =>
      let acc :=
        if model.requiresAssistantAfterToolResult && afterToolResult then
          acc.push assistantToolResultBridgeMessageJson
        else
          acc
      let content := userContentParts user.content
      let acc :=
        if content.isEmpty then
          acc
        else
          acc.push
            (LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "user")
              , ("content", LeanAgent.Json.arr content)
              ])
      convertMessagesLoop model rest false acc
  | .assistant assistant :: rest =>
      let acc :=
        match assistantMessageJson? model assistant with
        | some json => acc.push json
        | none => acc
      convertMessagesLoop model rest false acc
  | .toolResult _ :: _ =>
      let (toolResults, remaining) := collectLeadingToolResults messages
      let (acc, imageParts) :=
        toolResults.foldl
          (fun (state : Array Lean.Json × Array Lean.Json) toolResult =>
            let textJson := compatToolResultMessageJson model toolResult
            let images :=
              if model.input.contains "image" then
                state.snd ++ toolResultImageParts toolResult.content
              else
                state.snd
            (state.fst.push textJson, images))
          (acc, #[])
      let acc :=
        if imageParts.isEmpty then
          acc
        else
          let acc :=
            if model.requiresAssistantAfterToolResult then
              acc.push assistantToolResultBridgeMessageJson
            else
              acc
          acc.push (groupedToolResultImageMessageJson imageParts)
      convertMessagesLoop model remaining imageParts.isEmpty acc

def transformedContextMessages
    (model : OpenAICompletionsModel)
    (context : LeanAgent.AI.Context) : Array LeanAgent.AI.Message :=
  LeanAgent.AI.Api.TransformMessages.transformMessages
    context.messages
    { id := model.id
      provider := model.provider
      api := model.api
      input := model.input
    }
    { normalizeToolCallId? := some (normalizeToolCallId model) }

def convertMessagesFromTransformed
    (model : OpenAICompletionsModel)
    (systemPrompt : Option String)
    (messages : Array LeanAgent.AI.Message) : Array Lean.Json :=
  let systemMessages :=
    match systemPrompt with
    | some systemPrompt =>
        let role :=
          if model.reasoning && model.supportsDeveloperRole then "developer" else "system"
        #[LeanAgent.Json.obj
          [ ("role", LeanAgent.Json.str role)
          , ("content", LeanAgent.Json.str (sanitize systemPrompt))
          ]]
    | none => #[]
  systemMessages ++ convertMessagesLoop model messages.toList

def convertMessages
    (model : OpenAICompletionsModel)
    (context : LeanAgent.AI.Context) : Array Lean.Json :=
  convertMessagesFromTransformed model context.systemPrompt (transformedContextMessages model context)

def messageToJson : AgentMessage → Lean.Json
  | .user content =>
      LeanAgent.Json.obj [("role", LeanAgent.Json.str "user"), ("content", LeanAgent.Json.str (sanitize content))]
  | .assistant content calls =>
      let content := sanitize content
      let fields :=
        [ ("role", LeanAgent.Json.str "assistant")
        , ("content", if content.isEmpty then LeanAgent.Json.null else LeanAgent.Json.str content)
        ]
      if calls.isEmpty then
        LeanAgent.Json.obj fields
      else
        LeanAgent.Json.obj (fields ++ [("tool_calls", LeanAgent.Json.arr (calls.map toolCallToJson))])
  | .toolResult toolCallId _name content _ok =>
      LeanAgent.Json.obj
        [ ("role", LeanAgent.Json.str "tool")
        , ("tool_call_id", LeanAgent.Json.str toolCallId)
        , ("content", LeanAgent.Json.str (sanitize content))
        ]

def toolToJson (supportsStrictMode : Bool) (tool : AgentTool) : Lean.Json :=
  let functionFields :=
    [ ("name", LeanAgent.Json.str tool.name)
    , ("description", LeanAgent.Json.str tool.description)
    , ("parameters", tool.inputSchema)
    ] ++ if supportsStrictMode then [("strict", LeanAgent.Json.bool false)] else []
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "function")
    , ("function", LeanAgent.Json.obj functionFields)
    ]

def requestToolsForLegacy?
    (request : ProviderRequest)
    (supportsStrictMode : Bool) : Option (Array Lean.Json) :=
  if !request.tools.isEmpty || hasToolHistory request.messages then
    some (request.tools.map (toolToJson supportsStrictMode))
  else
    none

def requestToolChoiceForLegacy?
    (request : ProviderRequest)
    (options : OpenAICompletionsOptions) : Option Lean.Json :=
  if !request.tools.isEmpty || hasToolHistory request.messages then
    some ((options.toolChoice.getD .auto).toJson)
  else
    none

def requestToolStreamForLegacy?
    (request : ProviderRequest)
    (compat : ResolvedOpenAICompletionsCompat) : Option Lean.Json :=
  if compat.zaiToolStream && !request.tools.isEmpty then
    some (LeanAgent.Json.bool true)
  else
    none

def requestToolFields
    (request : ProviderRequest)
    (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  let tools? := requestToolsForLegacy? request true
  let toolChoice? := requestToolChoiceForLegacy? request options
  (match tools? with
   | some tools => [("tools", LeanAgent.Json.arr tools)]
   | none => []) ++
    (match toolChoice? with
     | some toolChoice => [("tool_choice", toolChoice)]
     | none => [])

def requestOptionFields (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  let temperatureFields :=
    match options.temperature with
    | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
    | none => []
  let maxTokenFields :=
    match options.maxTokens with
    | some maxTokens => [(options.maxTokensField, LeanAgent.Json.nat maxTokens)]
    | none => []
  let reasoning :=
    if options.supportsReasoningEffort then
      match options.reasoningEffort with
      | some effort => some effort
      | none => options.reasoning
    else
      none
  let reasoningFields :=
    match reasoning with
    | some effort => [("reasoning_effort", LeanAgent.Json.str (requestReasoningEffortString options effort))]
    | none =>
        if options.supportsReasoningEffort then
          match options.offReasoningEffortValue with
          | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
          | none => []
        else
          []
  temperatureFields ++ maxTokenFields ++ reasoningFields

def resolvedLegacyOptions
    (baseUrl providerId modelId : String)
    (options : OpenAICompletionsOptions) :
    OpenAICompletionsOptions × Option ResolvedOpenAICompletionsCompat :=
  if baseUrl.isEmpty && providerId.isEmpty then
    (options, none)
  else
    let compat := resolveCompat providerId baseUrl modelId
    let options :=
      { options with
        supportsReasoningEffort :=
          if options.supportsReasoningEffort then compat.supportsReasoningEffort else false
        supportsUsageInStreaming :=
          if options.supportsUsageInStreaming then compat.supportsUsageInStreaming else false
        maxTokensField :=
          if options.maxTokensField == "max_tokens" then compat.maxTokensField else options.maxTokensField
        supportsLongCacheRetention :=
          if options.supportsLongCacheRetention then compat.supportsLongCacheRetention else false
        sendSessionAffinityHeaders :=
          if options.sendSessionAffinityHeaders then true else compat.sendSessionAffinityHeaders
      }
    (options, some compat)

def requestCompatOptionFields
    (compat : ResolvedOpenAICompletionsCompat)
    (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  let temperatureFields :=
    match options.temperature with
    | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
    | none => []
  let maxTokenFields :=
    match options.maxTokens with
    | some maxTokens => [(options.maxTokensField, LeanAgent.Json.nat maxTokens)]
    | none => []
  let storeFields :=
    if compat.supportsStore then
      [("store", LeanAgent.Json.bool false)]
    else
      []
  let reasoningLevel? :=
    match options.reasoningEffort with
    | some effort => some effort
    | none => options.reasoning
  let reasoningValue? :=
    match reasoningLevel? with
    | some effort => some (requestReasoningEffortString options effort)
    | none => none
  let offThinkingEnabled :=
    options.offThinkingEnabled || options.offReasoningEffortValue.isSome
  let reasoningFields :=
    match compat.thinkingFormat with
    | some "zai" =>
        let thinkingFields :=
          [("thinking",
            LeanAgent.Json.obj
              [("type", LeanAgent.Json.str (if reasoningValue?.isSome then "enabled" else "disabled"))])]
        let effortFields :=
          if options.supportsReasoningEffort then
            match reasoningValue? with
            | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
            | none => []
          else
            []
        thinkingFields ++ effortFields
    | some "qwen" =>
        [("enable_thinking", LeanAgent.Json.bool reasoningValue?.isSome)]
    | some "qwen-chat-template" =>
        [("chat_template_kwargs",
          LeanAgent.Json.obj
            [ ("enable_thinking", LeanAgent.Json.bool reasoningValue?.isSome)
            , ("preserve_thinking", LeanAgent.Json.bool true)
            ])]
    | some "chat-template" =>
        []
    | some "deepseek" =>
        let thinkingFields :=
          if reasoningValue?.isSome then
            [("thinking", LeanAgent.Json.obj [("type", LeanAgent.Json.str "enabled")])]
          else if offThinkingEnabled then
            [("thinking", LeanAgent.Json.obj [("type", LeanAgent.Json.str "disabled")])]
          else
            []
        let effortFields :=
          if options.supportsReasoningEffort then
            match reasoningValue? with
            | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
            | none => []
          else
            []
        thinkingFields ++ effortFields
    | some "openrouter" =>
        match reasoningValue?, offThinkingEnabled with
        | some effort, _ =>
            [("reasoning", LeanAgent.Json.obj [("effort", LeanAgent.Json.str effort)])]
        | none, true =>
            [("reasoning",
              LeanAgent.Json.obj
                [("effort", LeanAgent.Json.str (options.offReasoningEffortValue.getD "none"))])]
        | none, false => []
    | some "ant-ling" =>
        match reasoningValue? with
        | some effort => [("reasoning", LeanAgent.Json.obj [("effort", LeanAgent.Json.str effort)])]
        | none => []
    | some "together" =>
        let toggleFields :=
          [("reasoning", LeanAgent.Json.obj [("enabled", LeanAgent.Json.bool reasoningValue?.isSome)])]
        let effortFields :=
          if options.supportsReasoningEffort then
            match reasoningValue? with
            | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
            | none => []
          else
            []
        toggleFields ++ effortFields
    | some "string-thinking" =>
        match reasoningValue? with
        | some effort => [("thinking", LeanAgent.Json.str effort)]
        | none =>
            if offThinkingEnabled then
              [("thinking", LeanAgent.Json.str (options.offReasoningEffortValue.getD "none"))]
            else
              []
    | _ =>
        if options.supportsReasoningEffort then
          match reasoningValue? with
          | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
          | none =>
              match options.offReasoningEffortValue with
              | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
              | none => []
        else
          []
  let routingFields :=
    (match compat.openRouterRouting with
     | some routing => [("provider", routing)]
     | none => []) ++
      (match compat.vercelGatewayRouting with
       | some (.obj fields) =>
           let gatewayFields :=
             fields.foldl (init := ([] : List (String × Lean.Json))) fun acc key value =>
               if key == "only" || key == "order" then
                 (key, value) :: acc
               else
                 acc
           if gatewayFields.isEmpty then
             []
           else
             [ ("providerOptions",
                 LeanAgent.Json.obj
                   [("gateway", LeanAgent.Json.obj gatewayFields.reverse)])
             ]
       | _ => [])
  temperatureFields ++ maxTokenFields ++ storeFields ++ reasoningFields ++ routingFields

def jsonStringField? (json : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? json key with
  | some (Lean.Json.str value) => some value
  | _ => none

def jsonBoolField? (json : Lean.Json) (key : String) : Option Bool :=
  match LeanAgent.Json.optVal? json key with
  | some (Lean.Json.bool value) => some value
  | _ => none

def requestedReasoningLevel? (options : OpenAICompletionsOptions) :
    Option LeanAgent.AI.ThinkingLevel :=
  match options.reasoningEffort with
  | some effort => some effort
  | none => options.reasoning

def modelThinkingLevelMapValue?
    (model : OpenAICompletionsModel)
    (level : LeanAgent.AI.ModelThinkingLevel) : Option (Option String) :=
  (model.thinkingLevelMap.find? fun entry => entry.level == level).map (fun entry => entry.mapped)

def requestedReasoningValue?
    (model : OpenAICompletionsModel)
    (options : OpenAICompletionsOptions) : Option String :=
  match requestedReasoningLevel? options with
  | some effort =>
      match options.reasoningEffortValue with
      | some value => some value
      | none =>
          match modelThinkingLevelMapValue? model (.level effort) with
          | some none => none
          | some (some value) => some value
          | none => some (reasoningEffortString effort)
  | none => none

def offThinkingEnabled
    (model : OpenAICompletionsModel)
    (options : OpenAICompletionsOptions) : Bool :=
  if !model.reasoning then
    false
  else
    match modelThinkingLevelMapValue? model .off with
    | some none => false
    | some _ => true
    | none => options.offThinkingEnabled

def chatTemplateKwargValue?
    (model : OpenAICompletionsModel)
    (options : OpenAICompletionsOptions)
    (value : Lean.Json) : Option Lean.Json :=
  match value with
  | .obj _ =>
      match jsonStringField? value "$var" with
      | some "thinking.enabled" =>
          some (LeanAgent.Json.bool (requestedReasoningLevel? options).isSome)
      | some "thinking.effort" =>
          if (requestedReasoningLevel? options).isNone &&
              jsonBoolField? value "omitWhenOff" == some true then
            none
          else
            match requestedReasoningValue? model options with
            | some effort => some (LeanAgent.Json.str effort)
            | none => options.offReasoningEffortValue.map LeanAgent.Json.str
      | _ => some value
  | _ => some value

def buildChatTemplateKwargs?
    (model : OpenAICompletionsModel)
    (options : OpenAICompletionsOptions) : Option Lean.Json :=
  match model.chatTemplateKwargs with
  | some (.obj kwargs) =>
      let fields :=
        kwargs.foldl (init := ([] : List (String × Lean.Json))) fun acc key value =>
          match chatTemplateKwargValue? model options value with
          | some resolved => (key, resolved) :: acc
          | none => acc
      if fields.isEmpty then
        none
      else
        some (LeanAgent.Json.obj fields.reverse)
  | _ => none

def requestContextOptionFields
    (model : OpenAICompletionsModel)
    (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  let temperatureFields :=
    match options.temperature with
    | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
    | none => []
  let maxTokenFields :=
    match options.maxTokens with
    | some maxTokens => [(options.maxTokensField, LeanAgent.Json.nat maxTokens)]
    | none => []
  let storeFields :=
    if model.supportsStore then
      [("store", LeanAgent.Json.bool false)]
    else
      []
  let reasoningValue? := requestedReasoningValue? model options
  let offThinkingEnabled := offThinkingEnabled model options
  let reasoningFields :=
    match model.thinkingFormat with
    | some "zai" =>
        let thinkingFields :=
          if model.reasoning then
            [("thinking",
              LeanAgent.Json.obj
                [("type", LeanAgent.Json.str (if reasoningValue?.isSome then "enabled" else "disabled"))])]
          else
            []
        let effortFields :=
          if options.supportsReasoningEffort then
            match reasoningValue? with
            | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
            | none => []
          else
            []
        thinkingFields ++ effortFields
    | some "qwen" =>
        if model.reasoning then
          [("enable_thinking", LeanAgent.Json.bool reasoningValue?.isSome)]
        else
          []
    | some "qwen-chat-template" =>
        if model.reasoning then
          [("chat_template_kwargs",
            LeanAgent.Json.obj
              [ ("enable_thinking", LeanAgent.Json.bool reasoningValue?.isSome)
              , ("preserve_thinking", LeanAgent.Json.bool true)
              ])]
        else
          []
    | some "chat-template" =>
        if model.reasoning then
          match buildChatTemplateKwargs? model options with
          | some kwargs => [("chat_template_kwargs", kwargs)]
          | none => []
        else
          []
    | some "deepseek" =>
        let thinkingFields :=
          if model.reasoning then
            if reasoningValue?.isSome then
              [("thinking", LeanAgent.Json.obj [("type", LeanAgent.Json.str "enabled")])]
            else if offThinkingEnabled then
              [("thinking", LeanAgent.Json.obj [("type", LeanAgent.Json.str "disabled")])]
            else
              []
          else
            []
        let effortFields :=
          if options.supportsReasoningEffort then
            match reasoningValue? with
            | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
            | none => []
          else
            []
        thinkingFields ++ effortFields
    | some "openrouter" =>
        if model.reasoning then
          match reasoningValue?, offThinkingEnabled with
          | some effort, _ =>
              [("reasoning", LeanAgent.Json.obj [("effort", LeanAgent.Json.str effort)])]
          | none, true =>
              [("reasoning",
                LeanAgent.Json.obj
                  [("effort", LeanAgent.Json.str (options.offReasoningEffortValue.getD "none"))])]
          | none, false => []
        else
          []
    | some "ant-ling" =>
        if model.reasoning then
          match reasoningValue? with
          | some effort => [("reasoning", LeanAgent.Json.obj [("effort", LeanAgent.Json.str effort)])]
          | none => []
        else
          []
    | some "together" =>
        let toggleFields :=
          if model.reasoning then
            [("reasoning", LeanAgent.Json.obj [("enabled", LeanAgent.Json.bool reasoningValue?.isSome)])]
          else
            []
        let effortFields :=
          if options.supportsReasoningEffort then
            match reasoningValue? with
            | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
            | none => []
          else
            []
        toggleFields ++ effortFields
    | some "string-thinking" =>
        if model.reasoning then
          match reasoningValue? with
          | some effort => [("thinking", LeanAgent.Json.str effort)]
          | none =>
              if offThinkingEnabled then
                [("thinking", LeanAgent.Json.str (options.offReasoningEffortValue.getD "none"))]
              else
                []
        else
          []
    | _ =>
        if model.reasoning && options.supportsReasoningEffort then
          match reasoningValue? with
          | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
          | none =>
              match options.offReasoningEffortValue with
              | some effort => [("reasoning_effort", LeanAgent.Json.str effort)]
              | none => []
        else
          []
  let routingFields :=
    (match model.openRouterRouting with
     | some routing => [("provider", routing)]
     | none => []) ++
      (match model.vercelGatewayRouting with
       | some (.obj fields) =>
           let gatewayFields :=
             fields.foldl (init := ([] : List (String × Lean.Json))) fun acc key value =>
               if key == "only" || key == "order" then
                 (key, value) :: acc
               else
                 acc
           if gatewayFields.isEmpty then
             []
           else
             [ ("providerOptions",
                 LeanAgent.Json.obj
                   [("gateway", LeanAgent.Json.obj gatewayFields.reverse)])
             ]
       | _ => [])
  temperatureFields ++ maxTokenFields ++ storeFields ++ reasoningFields ++ routingFields

def streamingUsageFields (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  if options.supportsUsageInStreaming then
    [("stream_options", LeanAgent.Json.obj [("include_usage", LeanAgent.Json.bool true)])]
  else
    []

def cacheRetentionFromEnv? (env : Array (String × String)) : Option LeanAgent.AI.CacheRetention :=
  env.findSome? fun (name, value) =>
    if name == "PI_CACHE_RETENTION" && value == "long" then
      some .long
    else
      none

def resolveCacheRetention (options : OpenAICompletionsOptions) : LeanAgent.AI.CacheRetention :=
  match options.cacheRetention with
  | some retention => retention
  | none => (cacheRetentionFromEnv? options.env).getD .short

def promptCacheFields (baseUrl : String) (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  let retention := resolveCacheRetention options
  if retention == .none then
    []
  else
    let supportsPromptCacheKey :=
      baseUrl.contains "api.openai.com" ||
        (retention == .long && options.supportsLongCacheRetention)
    let keyFields :=
      if supportsPromptCacheKey then
        match LeanAgent.AI.Api.OpenAIPromptCache.clampKey options.sessionId with
        | some key => [("prompt_cache_key", LeanAgent.Json.str key)]
        | none => []
      else
        []
    let retentionFields :=
      if retention == .long && options.supportsLongCacheRetention then
        [("prompt_cache_retention", LeanAgent.Json.str "24h")]
      else
        []
    keyFields ++ retentionFields

def sessionAffinityHeaders (options : OpenAICompletionsOptions) : Array (String × String) :=
  if !options.sendSessionAffinityHeaders || resolveCacheRetention options == .none then
    #[]
  else
    match options.sessionId with
    | some sessionId =>
        #[ ("session_id", sessionId)
         , ("x-client-request-id", sessionId)
         , ("x-session-affinity", sessionId)
         ]
    | none => #[]

def requestHeaders (options : OpenAICompletionsOptions) : Array (String × String) :=
  LeanAgent.AI.Util.Headers.mergeProvider
    (sessionAffinityHeaders options)
    options.headers

def jsonObjectInsert (json : Lean.Json) (key : String) (value : Lean.Json) : Lean.Json :=
  match json.getObj? with
  | .ok fields => Lean.Json.obj (fields.insert key value)
  | .error _ => json

def updateJsonArrayAt
    (items : Array Lean.Json)
    (target : Nat)
    (f : Lean.Json → Lean.Json) : Array Lean.Json :=
  Id.run do
    let mut out := #[]
    for i in [0:items.size] do
      let item := items[i]!
      out := out.push (if i == target then f item else item)
    pure out

def compatCacheControlJson?
    (model : OpenAICompletionsModel)
    (options : OpenAICompletionsOptions) : Option Lean.Json :=
  if model.cacheControlFormat != some "anthropic" || resolveCacheRetention options == .none then
    none
  else
    let ttlFields :=
      if resolveCacheRetention options == .long && options.supportsLongCacheRetention then
        [("ttl", LeanAgent.Json.str "1h")]
      else
        []
    some (LeanAgent.Json.obj ([("type", LeanAgent.Json.str "ephemeral")] ++ ttlFields))

def addCacheControlToLastTextPart
    (content : Array Lean.Json)
    (cacheControl : Lean.Json) : Option (Array Lean.Json) := Id.run do
  let mut target? : Option Nat := none
  for offset in [0:content.size] do
    if target?.isNone then
      let idx := content.size - offset - 1
      if jsonStringField? content[idx]! "type" == some "text" then
        target? := some idx
  match target? with
  | some target =>
      pure (some (updateJsonArrayAt content target (fun part => jsonObjectInsert part "cache_control" cacheControl)))
  | none => pure none

def addCacheControlToTextContent
    (message : Lean.Json)
    (cacheControl : Lean.Json) : Lean.Json × Bool :=
  match LeanAgent.Json.optVal? message "content" with
  | some (Lean.Json.str text) =>
      if text.isEmpty then
        (message, false)
      else
        let content :=
          LeanAgent.Json.arr
            #[LeanAgent.Json.obj
              [ ("type", LeanAgent.Json.str "text")
              , ("text", LeanAgent.Json.str text)
              , ("cache_control", cacheControl)
              ]]
        (jsonObjectInsert message "content" content, true)
  | some (Lean.Json.arr content) =>
      match addCacheControlToLastTextPart content cacheControl with
      | some updated => (jsonObjectInsert message "content" (LeanAgent.Json.arr updated), true)
      | none => (message, false)
  | _ => (message, false)

def findFirstInstructionIndex? (messages : Array Lean.Json) : Option Nat := Id.run do
  let mut result : Option Nat := none
  for i in [0:messages.size] do
    if result.isNone then
      match jsonStringField? messages[i]! "role" with
      | some "system" => result := some i
      | some "developer" => result := some i
      | _ => pure ()
  pure result

def findLastConversationIndex? (messages : Array Lean.Json) : Option Nat := Id.run do
  let mut result : Option Nat := none
  for offset in [0:messages.size] do
    if result.isNone then
      let idx := messages.size - offset - 1
      match jsonStringField? messages[idx]! "role" with
      | some "user" => result := some idx
      | some "assistant" => result := some idx
      | _ => pure ()
  pure result

def applyAnthropicCacheControl
    (messages : Array Lean.Json)
    (tools : Option (Array Lean.Json))
    (cacheControl : Lean.Json) : Array Lean.Json × Option (Array Lean.Json) :=
  let messages :=
    match findFirstInstructionIndex? messages with
    | some index =>
        updateJsonArrayAt messages index (fun message => (addCacheControlToTextContent message cacheControl).fst)
    | none => messages
  let messages :=
    match findLastConversationIndex? messages with
    | some index =>
        updateJsonArrayAt messages index (fun message => (addCacheControlToTextContent message cacheControl).fst)
    | none => messages
  let tools :=
    match tools with
    | some toolArray =>
        if toolArray.isEmpty then
          some toolArray
        else
          let index := toolArray.size - 1
          some (updateJsonArrayAt toolArray index (fun tool => jsonObjectInsert tool "cache_control" cacheControl))
    | none => none
  (messages, tools)

def modelRef
    (config : OpenAICompatibleConfig)
    (request : ProviderRequest)
    (api provider : String) : LeanAgent.AI.ModelRef :=
  let provider :=
    if provider.isEmpty then config.providerId else provider
  { id := request.model
    api := api
    provider := provider
    baseUrl := some config.baseUrl
  }

def applyPayloadHook
    (options : OpenAICompletionsOptions)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json) : IO Lean.Json := do
  match options.onPayload with
  | none => pure payload
  | some hook =>
      match ← hook payload model with
      | some nextPayload => pure nextPayload
      | none => pure payload

def callResponseHook
    (options : OpenAICompletionsOptions)
    (model : LeanAgent.AI.ModelRef)
    (response : LeanAgent.Http.JsonPostResponse) : IO Unit := do
  match options.onResponse with
  | none => pure ()
  | some hook =>
      hook { status := response.status, headers := response.headers } model

def requestToJsonWithOptions
    (request : ProviderRequest)
    (options : OpenAICompletionsOptions := {})
    (baseUrl : String := "")
    (providerId : String := "") : Lean.Json :=
  let (options, compat?) := resolvedLegacyOptions baseUrl providerId request.model options
  let messages :=
    #[LeanAgent.Json.obj [("role", LeanAgent.Json.str "system"), ("content", LeanAgent.Json.str request.system)]]
      ++ request.messages.map messageToJson
  let tools? :=
    match compat? with
    | some compat => requestToolsForLegacy? request compat.supportsStrictMode
    | none => requestToolsForLegacy? request true
  let toolChoice? := requestToolChoiceForLegacy? request options
  let toolStream? := compat?.bind (requestToolStreamForLegacy? request)
  let (messages, tools?) :=
    match compat? with
    | some compat =>
        let cacheModel : OpenAICompletionsModel :=
          { id := request.model
            provider := providerId
            api := "openai-completions"
            input := #["text"]
            cacheControlFormat := compat.cacheControlFormat
          }
        match compatCacheControlJson? cacheModel options with
        | some cacheControl => applyAnthropicCacheControl messages tools? cacheControl
        | none => (messages, tools?)
    | none => (messages, tools?)
  let optionFields :=
    match compat? with
    | some compat => requestCompatOptionFields compat options
    | none => requestOptionFields options
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str request.model)
     , ("messages", LeanAgent.Json.arr messages)
     ] ++ optionFields
       ++ promptCacheFields baseUrl options
       ++ (match tools? with
           | some tools => [("tools", LeanAgent.Json.arr tools)]
           | none => [])
       ++ (match toolChoice? with
           | some toolChoice => [("tool_choice", toolChoice)]
           | none => [])
       ++ (match toolStream? with
           | some toolStream => [("tool_stream", toolStream)]
           | none => []))

def requestToJson (request : ProviderRequest) : Lean.Json :=
  requestToJsonWithOptions request

def requestToStreamingJsonWithOptions
    (request : ProviderRequest)
    (options : OpenAICompletionsOptions := {})
    (baseUrl : String := "")
    (providerId : String := "") : Lean.Json :=
  let (options, compat?) := resolvedLegacyOptions baseUrl providerId request.model options
  let messages :=
    #[LeanAgent.Json.obj [("role", LeanAgent.Json.str "system"), ("content", LeanAgent.Json.str request.system)]]
      ++ request.messages.map messageToJson
  let tools? :=
    match compat? with
    | some compat => requestToolsForLegacy? request compat.supportsStrictMode
    | none => requestToolsForLegacy? request true
  let toolChoice? := requestToolChoiceForLegacy? request options
  let toolStream? := compat?.bind (requestToolStreamForLegacy? request)
  let (messages, tools?) :=
    match compat? with
    | some compat =>
        let cacheModel : OpenAICompletionsModel :=
          { id := request.model
            provider := providerId
            api := "openai-completions"
            input := #["text"]
            cacheControlFormat := compat.cacheControlFormat
          }
        match compatCacheControlJson? cacheModel options with
        | some cacheControl => applyAnthropicCacheControl messages tools? cacheControl
        | none => (messages, tools?)
    | none => (messages, tools?)
  let optionFields :=
    match compat? with
    | some compat => requestCompatOptionFields compat options
    | none => requestOptionFields options
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str request.model)
     , ("messages", LeanAgent.Json.arr messages)
     , ("stream", LeanAgent.Json.bool true)
     ] ++ streamingUsageFields options
       ++ optionFields
       ++ promptCacheFields baseUrl options
       ++ (match tools? with
           | some tools => [("tools", LeanAgent.Json.arr tools)]
           | none => [])
       ++ (match toolChoice? with
           | some toolChoice => [("tool_choice", toolChoice)]
           | none => [])
       ++ (match toolStream? with
           | some toolStream => [("tool_stream", toolStream)]
           | none => []))

def requestToJsonWithContextOptions
    (model : OpenAICompletionsModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAICompletionsOptions := {})
    (baseUrl : String := "") : Lean.Json :=
  let transformedMessages := transformedContextMessages model context
  let messages := convertMessagesFromTransformed model context.systemPrompt transformedMessages
  let tools? := requestToolsForContext? model context transformedMessages
  let toolChoice? := requestToolChoiceForContext? context transformedMessages options
  let toolStream? := requestToolStreamForContext? model context
  let (messages, tools?) :=
    match compatCacheControlJson? model options with
    | some cacheControl => applyAnthropicCacheControl messages tools? cacheControl
    | none => (messages, tools?)
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str model.id)
     , ("messages", LeanAgent.Json.arr messages)
     ] ++ requestContextOptionFields model options
       ++ promptCacheFields baseUrl options
       ++ (match tools? with
           | some tools => [("tools", LeanAgent.Json.arr tools)]
           | none => [])
       ++ (match toolChoice? with
           | some toolChoice => [("tool_choice", toolChoice)]
           | none => [])
       ++ (match toolStream? with
           | some toolStream => [("tool_stream", toolStream)]
           | none => []))

def requestToStreamingJsonWithContextOptions
    (model : OpenAICompletionsModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAICompletionsOptions := {})
    (baseUrl : String := "") : Lean.Json :=
  let transformedMessages := transformedContextMessages model context
  let messages := convertMessagesFromTransformed model context.systemPrompt transformedMessages
  let tools? := requestToolsForContext? model context transformedMessages
  let toolChoice? := requestToolChoiceForContext? context transformedMessages options
  let toolStream? := requestToolStreamForContext? model context
  let (messages, tools?) :=
    match compatCacheControlJson? model options with
    | some cacheControl => applyAnthropicCacheControl messages tools? cacheControl
    | none => (messages, tools?)
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str model.id)
     , ("messages", LeanAgent.Json.arr messages)
     , ("stream", LeanAgent.Json.bool true)
     ] ++ streamingUsageFields options
       ++ requestContextOptionFields model options
       ++ promptCacheFields baseUrl options
       ++ (match tools? with
           | some tools => [("tools", LeanAgent.Json.arr tools)]
           | none => [])
       ++ (match toolChoice? with
           | some toolChoice => [("tool_choice", toolChoice)]
           | none => [])
       ++ (match toolStream? with
           | some toolStream => [("tool_stream", toolStream)]
           | none => []))

def runHttpJson
    (config : OpenAICompatibleConfig)
    (payload : Lean.Json)
    (headers : Array (String × String) := #[])
    (options : OpenAICompletionsOptions := {})
    (model : LeanAgent.AI.ModelRef := { id := "", api := "openai-completions", provider := "" }) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := chatCompletionsUrl config.baseUrl
      apiKey := config.apiKey
      headers := LeanAgent.AI.Util.Headers.merge config.headers headers
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
    }
    payload.compress
  callResponseHook options model response
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError (LeanAgent.AI.Util.Diagnostics.providerHttpErrorMessage response.status response.body))
  pure response.body

def parseMaybeContent (message : Lean.Json) : String :=
  match LeanAgent.Json.optVal? message "content" with
  | some (Lean.Json.str content) => content
  | _ => ""

def parseToolArguments (raw : String) : Except String Lean.Json :=
  if raw.trimAscii.isEmpty then
    pure (LeanAgent.Json.obj [])
  else do
    let parsed ← LeanAgent.AI.Util.JsonParse.parseJsonWithRepair raw
    let _ ← parsed.getObj?
    pure parsed

def parseToolCall (json : Lean.Json) : Except String LeanAgent.ToolCall := do
  let id ← (← json.getObjVal? "id").getStr?
  let fn ← json.getObjVal? "function"
  let name ← (← fn.getObjVal? "name").getStr?
  let rawArgs ← (← fn.getObjVal? "arguments").getStr?
  let arguments ← parseToolArguments rawArgs
  pure { id := id, name := name, arguments := arguments }

def parseToolCalls (message : Lean.Json) : Except String (Array LeanAgent.ToolCall) := do
  match LeanAgent.Json.optVal? message "tool_calls" with
  | none => pure #[]
  | some Lean.Json.null => pure #[]
  | some value =>
      let rawCalls ← value.getArr?
      let mut calls := #[]
      for rawCall in rawCalls do
        calls := calls.push (← parseToolCall rawCall)
      pure calls

def natFieldD (json : Lean.Json) (key : String) (default : Nat := 0) : Nat :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getNat? with
      | .ok number => number
      | .error _ => default
  | none => default

def natField? (json : Lean.Json) (key : String) : Option Nat :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getNat? with
      | .ok number => some number
      | .error _ => none
  | none => none

def objField? (json : Lean.Json) (key : String) : Option Lean.Json :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getObj? with
      | .ok _ => some value
      | .error _ => none
  | none => none

def parseUsage (rawUsage : Lean.Json) : LeanAgent.ProviderUsage :=
  let promptTokens := natFieldD rawUsage "prompt_tokens"
  let completionTokens := natFieldD rawUsage "completion_tokens"
  let promptDetails := objField? rawUsage "prompt_tokens_details"
  let completionDetails := objField? rawUsage "completion_tokens_details"
  let cacheReadTokens :=
    match promptDetails with
    | some details => natFieldD details "cached_tokens" (natFieldD rawUsage "prompt_cache_hit_tokens")
    | none => natFieldD rawUsage "prompt_cache_hit_tokens"
  let cacheWriteTokens :=
    match promptDetails with
    | some details => natFieldD details "cache_write_tokens"
    | none => 0
  let reasoningTokens :=
    match completionDetails with
    | some details => natFieldD details "reasoning_tokens"
    | none => 0
  let inputTokens := promptTokens - cacheReadTokens - cacheWriteTokens
  { input := inputTokens
    output := completionTokens
    cacheRead := cacheReadTokens
    cacheWrite := cacheWriteTokens
    reasoning := some reasoningTokens
    totalTokens := inputTokens + completionTokens + cacheReadTokens + cacheWriteTokens
  }

def parseUsage? (json : Lean.Json) : Option LeanAgent.ProviderUsage :=
  match LeanAgent.Json.optVal? json "usage" with
  | some value => some (parseUsage value)
  | none => none

inductive StreamBlockKey where
  | text
  | thinking
  | tool (streamIndex : Nat)
deriving BEq

structure StreamingToolState where
  streamIndex : Nat
  id : String := ""
  name : String := ""
  partialArguments : String := ""
  thoughtSignature : Option String := none
deriving BEq

structure StreamingState where
  text : String := ""
  thinking : String := ""
  thinkingSignature : Option String := none
  toolStates : Array StreamingToolState := #[]
  toolIndexAliases : Array (Nat × Nat) := #[]
  pendingReasoningDetails : Array (String × String) := #[]
  order : Array StreamBlockKey := #[]
  responseId : Option String := none
  responseModel : Option String := none
  usage : Option LeanAgent.ProviderUsage := none
  finishReason : Option String := none
  sawFinishReason : Bool := false
deriving BEq

inductive ParsedStreamEvent where
  | textStart (contentIndex : Nat)
  | textDelta (contentIndex : Nat) (delta : String)
  | textEnd (contentIndex : Nat) (content : String)
  | thinkingStart (contentIndex : Nat)
  | thinkingDelta (contentIndex : Nat) (delta : String)
  | thinkingEnd (contentIndex : Nat) (content : String)
  | toolCallStart (contentIndex : Nat)
  | toolCallDelta (contentIndex : Nat) (delta : String)
  | toolCallEnd (contentIndex : Nat) (call : LeanAgent.AI.ToolCall)
deriving BEq

def indexOfBlock? (order : Array StreamBlockKey) (key : StreamBlockKey) : Option Nat :=
  let rec loop (items : List StreamBlockKey) (index : Nat) :=
    match items with
    | [] => none
    | item :: rest => if item == key then some index else loop rest (index + 1)
  loop order.toList 0

def ensureBlock (state : StreamingState) (key : StreamBlockKey) : StreamingState × Nat × Bool :=
  match indexOfBlock? state.order key with
  | some index => (state, index, false)
  | none =>
      let nextIndex := state.order.size
      ({ state with order := state.order.push key }, nextIndex, true)

def findToolState? (states : Array StreamingToolState) (streamIndex : Nat) : Option StreamingToolState :=
  states.find? fun state => state.streamIndex == streamIndex

def findToolStateById? (states : Array StreamingToolState) (id : String) : Option StreamingToolState :=
  states.find? fun state => state.id == id

def upsertToolState (states : Array StreamingToolState) (next : StreamingToolState) :
    Array StreamingToolState :=
  if states.any fun state => state.streamIndex == next.streamIndex then
    states.map fun state => if state.streamIndex == next.streamIndex then next else state
  else
    states.push next

def upsertPendingReasoningDetail
    (pending : Array (String × String))
    (id signature : String) : Array (String × String) :=
  if pending.any fun entry => entry.fst == id then
    pending.map fun entry => if entry.fst == id then (id, signature) else entry
  else
    pending.push (id, signature)

def toolIndexAlias? (aliases : Array (Nat × Nat)) (providerIndex : Nat) : Option Nat :=
  aliases.findSome? fun entry => if entry.fst == providerIndex then some entry.snd else none

def upsertToolIndexAlias
    (aliases : Array (Nat × Nat))
    (providerIndex internalIndex : Nat) : Array (Nat × Nat) :=
  if aliases.any fun entry => entry.fst == providerIndex then
    aliases.map fun entry => if entry.fst == providerIndex then (providerIndex, internalIndex) else entry
  else
    aliases.push (providerIndex, internalIndex)

def syntheticToolStreamIndex (ordinal : Nat) : Nat :=
  1000000 + ordinal

def pendingReasoningDetail?
    (pending : Array (String × String))
    (id : String) : Option String :=
  pending.findSome? fun entry => if entry.fst == id then some entry.snd else none

def removePendingReasoningDetail
    (pending : Array (String × String))
    (id : String) : Array (String × String) :=
  pending.filter fun entry => entry.fst != id

def partialArgumentsJson (raw : String) : Lean.Json :=
  LeanAgent.AI.Util.JsonParse.parseStreamingJson raw

def toolCallFromStatePartial (state : StreamingToolState) : LeanAgent.AI.ToolCall :=
  { id := state.id
    name := state.name
    arguments := partialArgumentsJson state.partialArguments
    thoughtSignature := state.thoughtSignature
  }

def toolCallFromState (state : StreamingToolState) : Except String LeanAgent.AI.ToolCall := do
  let arguments ← parseToolArguments state.partialArguments
  pure
    { id := state.id
      name := state.name
      arguments := arguments
      thoughtSignature := state.thoughtSignature
    }

def contentFromState (state : StreamingState) : Array LeanAgent.AI.ContentBlock :=
  state.order.filterMap fun key =>
    match key with
    | .text =>
        some (LeanAgent.AI.ContentBlock.text { text := state.text })
    | .thinking =>
        some (LeanAgent.AI.ContentBlock.thinking
          { thinking := state.thinking
            thinkingSignature := state.thinkingSignature
          })
    | .tool streamIndex =>
        (findToolState? state.toolStates streamIndex).map fun toolState =>
          LeanAgent.AI.ContentBlock.toolCall (toolCallFromStatePartial toolState)

def openAICompatibleStopReasonAndError
    (finishReason : Option String)
    (sawFinishReason : Bool) : LeanAgent.AI.StopReason × Option String :=
  match finishReason with
  | some "stop" => (.stop, none)
  | some "end" => (.stop, none)
  | some "length" => (.length, none)
  | some "function_call" => (.toolUse, none)
  | some "tool_calls" => (.toolUse, none)
  | some "tool_use" => (.toolUse, none)
  | some "content_filter" => (.error, some "Provider finish_reason: content_filter")
  | some "network_error" => (.error, some "Provider finish_reason: network_error")
  | some reason => (.error, some s!"Provider finish_reason: {reason}")
  | none =>
      if sawFinishReason then
        (.stop, none)
      else
        (.error, some "Stream ended without finish_reason")

def messageFromStreamingState
    (api provider model : String)
    (timestamp : Nat)
    (state : StreamingState) : LeanAgent.AI.AssistantMessage :=
  let (stopReason, errorMessage) :=
    openAICompatibleStopReasonAndError state.finishReason state.sawFinishReason
  { content := contentFromState state
    api := api
    provider := provider
    model := model
    responseId := state.responseId
    responseModel := state.responseModel
    usage := (state.usage.map LeanAgent.AI.usageFromLegacyProviderUsage).getD LeanAgent.AI.Usage.empty
    stopReason := stopReason
    errorMessage := errorMessage
    timestamp := timestamp
  }

def parsedEventToAssistantEvent
    (message : LeanAgent.AI.AssistantMessage) : ParsedStreamEvent → LeanAgent.AI.AssistantMessageEvent
  | .textStart index => .textStart index message
  | .textDelta index delta => .textDelta index delta message
  | .textEnd index content => .textEnd index content message
  | .thinkingStart index => .thinkingStart index message
  | .thinkingDelta index delta => .thinkingDelta index delta message
  | .thinkingEnd index content => .thinkingEnd index content message
  | .toolCallStart index => .toolCallStart index message
  | .toolCallDelta index delta => .toolCallDelta index delta message
  | .toolCallEnd index call => .toolCallEnd index call message

def optionalStringField (json : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? json key with
  | some (Lean.Json.str value) => some value
  | _ => none

def optionalObjectField (json : Lean.Json) (key : String) : Option Lean.Json :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getObj? with
      | .ok _ => some value
      | .error _ => none
  | none => none

def optionalArrayField (json : Lean.Json) (key : String) : Option (Array Lean.Json) :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getArr? with
      | .ok arr => some arr
      | .error _ => none
  | none => none

def encryptedReasoningDetail? (json : Lean.Json) : Option (String × String) :=
  match jsonStringField? json "type", jsonStringField? json "id", jsonStringField? json "data" with
  | some "reasoning.encrypted", some id, some _ =>
      if id.isEmpty then none else some (id, json.compress)
  | _, _, _ => none

def firstChoice? (chunk : Lean.Json) : Option Lean.Json :=
  match optionalArrayField chunk "choices" with
  | some choices => choices[0]?
  | none => none

def usageFromChoice? (choice : Lean.Json) : Option LeanAgent.ProviderUsage :=
  match LeanAgent.Json.optVal? choice "usage" with
  | some value => some (parseUsage value)
  | none => none

def optionPrefer (first second : Option α) : Option α :=
  match first with
  | some value => some value
  | none => second

def reasoningDelta? (provider : String) (delta : Lean.Json) : Option (String × String) :=
  match optionalStringField delta "reasoning_content" with
  | some value => if value.isEmpty then none else some ("reasoning_content", value)
  | none =>
      match optionalStringField delta "reasoning" with
      | some value =>
          if value.isEmpty then
            none
          else
            some (normalizeReasoningSignature provider "reasoning", value)
      | none =>
          match optionalStringField delta "reasoning_text" with
          | some value => if value.isEmpty then none else some ("reasoning_text", value)
          | none => none

def applyTextDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (delta : String) : StreamingState × Array ParsedStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let (state, index, created) := ensureBlock state .text
    let events := if created then events.push (.textStart index) else events
    ({ state with text := state.text ++ delta }, events.push (.textDelta index delta))

def applyThinkingDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (signature delta : String) : StreamingState × Array ParsedStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let (state, index, created) := ensureBlock state .thinking
    let events := if created then events.push (.thinkingStart index) else events
    let signature := state.thinkingSignature.getD signature
    ({ state with thinking := state.thinking ++ delta, thinkingSignature := some signature },
      events.push (.thinkingDelta index delta))

def resolvedToolDeltaStreamIndex
    (state : StreamingState)
    (toolDelta : Lean.Json) : Nat × Array (Nat × Nat) :=
  let toolId := optionalStringField toolDelta "id"
  match natField? toolDelta "index" with
  | some providerIndex =>
      match toolIndexAlias? state.toolIndexAliases providerIndex with
      | some internalIndex => (internalIndex, state.toolIndexAliases)
      | none =>
          match findToolState? state.toolStates providerIndex with
          | some _ => (providerIndex, state.toolIndexAliases)
          | none =>
              match toolId.bind (findToolStateById? state.toolStates) with
              | some existing =>
                  let aliases :=
                    upsertToolIndexAlias state.toolIndexAliases providerIndex existing.streamIndex
                  (existing.streamIndex, aliases)
              | none => (providerIndex, state.toolIndexAliases)
  | none =>
      match toolId.bind (findToolStateById? state.toolStates) with
      | some existing => (existing.streamIndex, state.toolIndexAliases)
      | none => (syntheticToolStreamIndex state.toolStates.size, state.toolIndexAliases)

def applyToolDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (toolDelta : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let (streamIndex, toolIndexAliases) := resolvedToolDeltaStreamIndex state toolDelta
  let key := StreamBlockKey.tool streamIndex
  let (state, contentIndex, created) := ensureBlock state key
  let current := (findToolState? state.toolStates streamIndex).getD { streamIndex := streamIndex }
  let fn := optionalObjectField toolDelta "function"
  let name :=
    match fn.bind (fun value => optionalStringField value "name") with
    | some value => if current.name.isEmpty then value else current.name
    | none => current.name
  let id :=
    match optionalStringField toolDelta "id" with
    | some value => if current.id.isEmpty then value else current.id
    | none => current.id
  let argumentDelta :=
    match fn.bind (fun value => optionalStringField value "arguments") with
    | some value => value
    | none => ""
  let next :=
    { current with
      id := id
      name := name
      partialArguments := current.partialArguments ++ argumentDelta
      thoughtSignature :=
        match current.thoughtSignature with
        | some signature => some signature
        | none =>
            if id.isEmpty then
              none
            else
              pendingReasoningDetail? state.pendingReasoningDetails id
    }
  let pendingReasoningDetails :=
    if id.isEmpty then
      state.pendingReasoningDetails
    else
      removePendingReasoningDetail state.pendingReasoningDetails id
  let state :=
    { state with
      toolStates := upsertToolState state.toolStates next
      toolIndexAliases := toolIndexAliases
      pendingReasoningDetails := pendingReasoningDetails
    }
  let events := if created then events.push (.toolCallStart contentIndex) else events
  let events :=
    if argumentDelta.isEmpty then
      events
    else
      events.push (.toolCallDelta contentIndex argumentDelta)
  (state, events)

def applyToolDeltas
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (toolDeltas : Array Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  Id.run do
    let mut state := state
    let mut events := events
    for toolDelta in toolDeltas do
      let (nextState, nextEvents) := applyToolDelta state events toolDelta
      state := nextState
      events := nextEvents
    pure (state, events)

def applyReasoningDetail
    (state : StreamingState)
    (detail : Lean.Json) : StreamingState :=
  match encryptedReasoningDetail? detail with
  | some (id, signature) =>
      match findToolStateById? state.toolStates id with
      | some toolState =>
          let updated := { toolState with thoughtSignature := some signature }
          { state with toolStates := upsertToolState state.toolStates updated }
      | none =>
          { state with
            pendingReasoningDetails :=
              upsertPendingReasoningDetail state.pendingReasoningDetails id signature
          }
  | none => state

def applyStreamingChunk
    (provider model : String)
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (chunk : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let responseId := optionPrefer state.responseId (optionalStringField chunk "id")
  let responseModel :=
    match state.responseModel, optionalStringField chunk "model" with
    | some value, _ => some value
    | none, some value => if value.isEmpty || value == model then none else some value
    | none, none => none
  let usage := optionPrefer (parseUsage? chunk) state.usage
  match firstChoice? chunk with
  | none => ({ state with responseId := responseId, responseModel := responseModel, usage := usage }, events)
  | some choice =>
      let usage := optionPrefer (usageFromChoice? choice) usage
      let finishReason :=
        match optionalStringField choice "finish_reason" with
        | some value => some value
        | none => state.finishReason
      let sawFinishReason :=
        match optionalStringField choice "finish_reason" with
        | some _ => true
        | none => state.sawFinishReason
      let state :=
        { state with
          responseId := responseId
          responseModel := responseModel
          usage := usage
          finishReason := finishReason
          sawFinishReason := sawFinishReason
        }
      match optionalObjectField choice "delta" with
      | none => (state, events)
      | some delta =>
          let (state, events) :=
            match optionalStringField delta "content" with
            | some content => applyTextDelta state events content
            | none => (state, events)
          let (state, events) :=
            match reasoningDelta? provider delta with
            | some (signature, value) => applyThinkingDelta state events signature value
            | none => (state, events)
          let (state, events) :=
            match optionalArrayField delta "tool_calls" with
            | some toolDeltas => applyToolDeltas state events toolDeltas
            | none => (state, events)
          let state :=
            match optionalArrayField delta "reasoning_details" with
            | some details => details.foldl applyReasoningDetail state
            | none => state
          (state, events)

def parseStreamingChunks (raw : String) : Except String (Array Lean.Json) := do
  let mut chunks := #[]
  for event in LeanAgent.AI.Util.SSE.parse raw do
    let data := event.data.trimAscii.toString
    if data == "[DONE]" then
      pure ()
    else
      let json ← Lean.Json.parse event.data
      if (LeanAgent.Json.optVal? json "error").isSome then
        throw (LeanAgent.AI.Util.Diagnostics.providerParseErrorMessage json.compress)
      chunks := chunks.push json
  pure chunks

def finalParsedEvents (state : StreamingState) : Except String (Array ParsedStreamEvent) := do
  let mut events := #[]
  for key in state.order do
    match key with
    | .text =>
        match indexOfBlock? state.order .text with
        | some index => events := events.push (.textEnd index state.text)
        | none => pure ()
    | .thinking =>
        match indexOfBlock? state.order .thinking with
        | some index => events := events.push (.thinkingEnd index state.thinking)
        | none => pure ()
    | .tool streamIndex =>
        match indexOfBlock? state.order (.tool streamIndex), findToolState? state.toolStates streamIndex with
        | some index, some toolState =>
            let call ← toolCallFromState toolState
            events := events.push (.toolCallEnd index call)
        | _, _ => pure ()
  pure events

def parseStreamingEventStream
    (api provider model : String)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantMessageEventStream := do
  let chunks ← parseStreamingChunks raw
  let mut state : StreamingState := {}
  let mut parsedEvents : Array ParsedStreamEvent := #[]
  for chunk in chunks do
    let (nextState, nextEvents) := applyStreamingChunk provider model state parsedEvents chunk
    state := nextState
    parsedEvents := nextEvents
  let finalEvents ← finalParsedEvents state
  let allParsedEvents := parsedEvents ++ finalEvents
  let message := messageFromStreamingState api provider model timestamp state
  let events :=
    #[LeanAgent.AI.AssistantMessageEvent.start message]
      ++ allParsedEvents.map (parsedEventToAssistantEvent message)
      ++ #[LeanAgent.AI.completionEvent message]
  pure { events := events, finalResult := message }

def parseChatCompletion (raw : String) : Except String LeanAgent.ProviderResponse := do
  let json ← Lean.Json.parse raw
  if (LeanAgent.Json.optVal? json "error").isSome then
    throw (LeanAgent.AI.Util.Diagnostics.providerParseErrorMessage json.compress)
  let choices ← (← json.getObjVal? "choices").getArr?
  let choice ←
    match choices[0]? with
    | some choice => pure choice
    | none => throw "OpenAI response contained no choices"
  let message ← choice.getObjVal? "message"
  let finishReason :=
    match LeanAgent.Json.optVal? choice "finish_reason" with
    | some (Lean.Json.str value) => some value
    | _ => none
  let toolCalls ← parseToolCalls message
  pure
    { content := parseMaybeContent message
      toolCalls := toolCalls
      finishReason := finishReason
      usage := parseUsage? json
    }

def completeWithOptions
    (config : OpenAICompatibleConfig)
    (request : ProviderRequest)
  (options : OpenAICompletionsOptions := {}) : IO LeanAgent.ProviderResponse := do
  let model := modelRef config request "openai-completions" ""
  let payload ←
    applyPayloadHook options model
      (requestToJsonWithOptions request options config.baseUrl config.providerId)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config payload (requestHeaders options) options model)
    options.signal
  match parseChatCompletion raw with
  | .ok response => pure response
  | .error err => throw (IO.userError s!"failed to parse provider response: {err}\n{raw}")

def streamWithOptions
    (config : OpenAICompatibleConfig)
    (request : ProviderRequest)
    (api providerId : String)
    (options : OpenAICompletionsOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  let model := modelRef config request api providerId
  let payload ←
    applyPayloadHook options model
      (requestToStreamingJsonWithOptions request options config.baseUrl providerId)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config payload (requestHeaders options) options model)
    options.signal
  let timestamp ← IO.monoMsNow
  match parseStreamingEventStream api providerId request.model timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse streaming provider response: {err}\n{raw}")

def streamContextWithOptions
    (config : OpenAICompatibleConfig)
    (model : OpenAICompletionsModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAICompletionsOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  let ref := model.toModelRef config.baseUrl
  let payload ←
    applyPayloadHook options ref
      (requestToStreamingJsonWithContextOptions model context options config.baseUrl)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config payload (requestHeaders options) options ref)
    options.signal
  let timestamp ← IO.monoMsNow
  match parseStreamingEventStream model.api model.provider model.id timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse streaming provider response: {err}\n{raw}")

def provider (config : OpenAICompatibleConfig) : LeanAgent.ModelProvider :=
  { complete := fun request => completeWithOptions config request }

end LeanAgent.AI.Api.OpenAICompletions
