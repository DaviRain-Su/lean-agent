import LeanAgent.AI.Api.SimpleOptions
import LeanAgent.AI.Api.TransformMessages
import LeanAgent.AI.Auth
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.SanitizeUnicode
import LeanAgent.Json

namespace LeanAgent.AI.Api.BedrockConverseStream

open LeanAgent

def api : String := "bedrock-converse-stream"
def defaultRegion : String := "us-east-1"
def defaultBaseUrl : String := "https://bedrock-runtime.us-east-1.amazonaws.com"

def dataRetentionDocsUrl : String :=
  "https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html"

def transportUnavailableMessage : String :=
  "Bedrock Converse Stream transport requires AWS SigV4 signing and AWS event-stream support; Lean runtime transport is not implemented yet."

structure BedrockConverseStreamConfig where
  baseUrl : String := defaultBaseUrl
  headers : Array (String × String) := #[]
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

inductive ToolChoice where
  | auto
  | any
  | none
  | tool (name : String)
deriving BEq

inductive BedrockThinkingDisplay where
  | summarized
  | omitted
deriving BEq

def BedrockThinkingDisplay.toString : BedrockThinkingDisplay → String
  | .summarized => "summarized"
  | .omitted => "omitted"

structure BedrockOptions extends LeanAgent.AI.SimpleStreamOptions where
  region : Option String := none
  profile : Option String := none
  toolChoice : Option ToolChoice := none
  interleavedThinking : Option Bool := none
  thinkingDisplay : Option BedrockThinkingDisplay := none
  bearerToken : Option String := none

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : BedrockOptions :=
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

def sanitize (text : String) : String :=
  LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates text

def targetModel
    (model : LeanAgent.AI.ModelRef)
    (input : Array String) : LeanAgent.AI.Api.TransformMessages.TargetModel :=
  { id := model.id
    provider := model.provider
    api := model.api
    input := input
  }

def normalizeToolCallId (id : String) : String :=
  LeanAgent.AI.Api.TransformMessages.sanitizeToolCallId id

def createNonBlankTextBlock? (text : String) : Option Lean.Json :=
  let text := sanitize text
  if text.trimAscii.toString.isEmpty then
    none
  else
    some (LeanAgent.Json.obj [("text", LeanAgent.Json.str text)])

def requiredTextBlock (text : String) : Lean.Json :=
  (createNonBlankTextBlock? text).getD
    (LeanAgent.Json.obj [("text", LeanAgent.Json.str "<empty>")])

def imageFormat? (mimeType : String) : Option String :=
  match mimeType.toLower with
  | "image/jpeg" => some "jpeg"
  | "image/jpg" => some "jpeg"
  | "image/png" => some "png"
  | "image/gif" => some "gif"
  | "image/webp" => some "webp"
  | _ => none

def imageBlock (image : LeanAgent.AI.ImageContent) : Lean.Json :=
  match imageFormat? image.mimeType with
  | some format =>
      LeanAgent.Json.obj
        [ ("image",
            LeanAgent.Json.obj
              [ ("format", LeanAgent.Json.str format)
              , ("source", LeanAgent.Json.obj [("bytes", LeanAgent.Json.str image.data)])
              ])
        ]
  | none =>
      LeanAgent.Json.obj
        [("text", LeanAgent.Json.str s!"(image omitted: unsupported MIME type {image.mimeType})")]

def isAnthropicClaudeModel (modelId modelName : String) : Bool :=
  let id := modelId.toLower
  let name := modelName.toLower
  id.contains "anthropic.claude" ||
    id.contains "anthropic/claude" ||
    name.contains "anthropic.claude" ||
    name.contains "anthropic/claude" ||
    name.contains "claude"

def normalizedModelCandidates (modelId modelName : String) : Array String :=
  let normalize (value : String) : String :=
    value.toLower.toList
      |>.map (fun char =>
        if char == ' ' || char == '_' || char == '.' || char == ':' then '-' else char)
      |> String.ofList
  if modelName.trimAscii.toString.isEmpty then
    #[modelId.toLower, normalize modelId]
  else
    #[modelId.toLower, normalize modelId, modelName.toLower, normalize modelName]

def supportsAdaptiveThinking (modelId modelName : String) : Bool :=
  normalizedModelCandidates modelId modelName |>.any fun candidate =>
    candidate.contains "opus-4-6" ||
      candidate.contains "opus-4-7" ||
      candidate.contains "opus-4-8" ||
      candidate.contains "sonnet-4-6" ||
      candidate.contains "fable-5"

def supportsNativeXhighEffort (modelId modelName : String) : Bool :=
  normalizedModelCandidates modelId modelName |>.any fun candidate =>
    candidate.contains "opus-4-7" ||
      candidate.contains "opus-4-8" ||
      candidate.contains "fable-5"

def thinkingLevelMapped? (level : LeanAgent.AI.ThinkingLevel)
    (map : Array LeanAgent.AI.ThinkingLevelMapEntry) : Option String :=
  map.findSome? fun entry =>
    if entry.level == .level level then entry.mapped else none

def mapThinkingLevelToEffort
    (modelId modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (level : LeanAgent.AI.ThinkingLevel) : String :=
  if level == .xhigh && supportsNativeXhighEffort modelId modelName then
    "xhigh"
  else
    match thinkingLevelMapped? level thinkingLevelMap with
    | some mapped => mapped
    | none =>
        match level with
        | .minimal => "low"
        | .low => "low"
        | .medium => "medium"
        | .high => "high"
        | .xhigh => "high"

def supportsPromptCaching (modelId modelName : String) (env : LeanAgent.AI.Auth.ProviderEnv) : Bool :=
  let candidates := normalizedModelCandidates modelId modelName
  let hasClaude := candidates.any (fun candidate => candidate.contains "claude")
  if !hasClaude then
    LeanAgent.AI.Auth.providerEnvGet? env "AWS_BEDROCK_FORCE_CACHE" == some "1"
  else
    candidates.any (fun candidate =>
      candidate.contains "-4-" ||
        candidate.contains "claude-3-7-sonnet" ||
        candidate.contains "claude-3-5-haiku")

def buildSystemPrompt
    (systemPrompt : Option String)
    (modelId modelName : String)
    (cacheRetention : LeanAgent.AI.CacheRetention)
    (env : LeanAgent.AI.Auth.ProviderEnv) : Option Lean.Json :=
  match systemPrompt with
  | none => none
  | some prompt =>
      let textBlock := LeanAgent.Json.obj [("text", LeanAgent.Json.str (sanitize prompt))]
      let blocks :=
        if cacheRetention != .none && supportsPromptCaching modelId modelName env then
          let cachePointFields :=
            if cacheRetention == .long then
              [ ("type", LeanAgent.Json.str "default")
              , ("ttl", LeanAgent.Json.str "ONE_HOUR")
              ]
            else
              [("type", LeanAgent.Json.str "default")]
          #[ textBlock
           , LeanAgent.Json.obj [("cachePoint", LeanAgent.Json.obj cachePointFields)]
           ]
        else
          #[textBlock]
      some (LeanAgent.Json.arr blocks)

def userContentBlock? (supportsImages : Bool) : LeanAgent.AI.ContentBlock → Option Lean.Json
  | .text content => createNonBlankTextBlock? content.text
  | .image image =>
      if supportsImages then some (imageBlock image) else none
  | .thinking content => createNonBlankTextBlock? content.thinking
  | .toolCall _ => none

def assistantContentBlock? (supportsThinkingSignature : Bool) : LeanAgent.AI.ContentBlock → Option Lean.Json
  | .text content => createNonBlankTextBlock? content.text
  | .toolCall call =>
      some
        (LeanAgent.Json.obj
          [ ("toolUse",
              LeanAgent.Json.obj
                [ ("toolUseId", LeanAgent.Json.str call.id)
                , ("name", LeanAgent.Json.str call.name)
                , ("input", call.arguments)
                ])
          ])
  | .thinking content =>
      let thinking := sanitize content.thinking
      if thinking.trimAscii.toString.isEmpty then
        none
      else if supportsThinkingSignature then
        match content.thinkingSignature with
        | some signature =>
            if signature.trimAscii.toString.isEmpty then
              some (LeanAgent.Json.obj [("text", LeanAgent.Json.str thinking)])
            else
              some
                (LeanAgent.Json.obj
                  [ ("reasoningContent",
                      LeanAgent.Json.obj
                        [ ("reasoningText",
                            LeanAgent.Json.obj
                              [ ("text", LeanAgent.Json.str thinking)
                              , ("signature", LeanAgent.Json.str signature)
                              ])
                        ])
                  ])
        | none => some (LeanAgent.Json.obj [("text", LeanAgent.Json.str thinking)])
      else
        some
          (LeanAgent.Json.obj
            [ ("reasoningContent",
                LeanAgent.Json.obj
                  [("reasoningText", LeanAgent.Json.obj [("text", LeanAgent.Json.str thinking)])])
            ])
  | .image _ => none

def convertToolResultContent (supportsImages : Bool) (content : Array LeanAgent.AI.ContentBlock) : Array Lean.Json :=
  let blocks := content.filterMap fun block =>
    match block with
    | .text text => createNonBlankTextBlock? text.text
    | .thinking thinking => createNonBlankTextBlock? thinking.thinking
    | .image image => if supportsImages then some (imageBlock image) else none
    | .toolCall _ => none
  if blocks.isEmpty then
    #[LeanAgent.Json.obj [("text", LeanAgent.Json.str "<empty>")]]
  else
    blocks

def toolResultBlock (supportsImages : Bool) (message : LeanAgent.AI.ToolResultMessage) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("toolResult",
        LeanAgent.Json.obj
          [ ("toolUseId", LeanAgent.Json.str message.toolCallId)
          , ("content", LeanAgent.Json.arr (convertToolResultContent supportsImages message.content))
          , ("status", LeanAgent.Json.str (if message.isError then "error" else "success"))
          ])
    ]

def convertMessagesFromArray
    (messages : Array LeanAgent.AI.Message)
    (supportsImages supportsThinkingSignature : Bool)
    : Array Lean.Json :=
  Id.run do
    let mut acc := #[]
    let mut i := 0
    while h : i < messages.size do
      match messages[i] with
      | .user user =>
          let content := user.content.filterMap (userContentBlock? supportsImages)
          let content := if content.isEmpty then #[requiredTextBlock ""] else content
          acc := acc.push
            (LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "user")
              , ("content", LeanAgent.Json.arr content)
              ])
          i := i + 1
      | .assistant assistant =>
          let content := assistant.content.filterMap (assistantContentBlock? supportsThinkingSignature)
          if !content.isEmpty then
            acc := acc.push
              (LeanAgent.Json.obj
                [ ("role", LeanAgent.Json.str "assistant")
                , ("content", LeanAgent.Json.arr content)
                ])
          i := i + 1
      | .toolResult toolResult =>
          let mut toolResults := #[toolResultBlock supportsImages toolResult]
          let mut j := i + 1
          while h2 : j < messages.size do
            match messages[j] with
            | .toolResult next =>
                toolResults := toolResults.push (toolResultBlock supportsImages next)
                j := j + 1
            | _ => break
          acc := acc.push
            (LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "user")
              , ("content", LeanAgent.Json.arr toolResults)
              ])
          i := j
    pure acc

def convertMessages
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelName : String)
    (context : LeanAgent.AI.Context) : Array Lean.Json :=
  let transformed := LeanAgent.AI.Api.TransformMessages.transformMessages
    context.messages
    (targetModel model input)
    { normalizeToolCallId? := some (fun id _ _ => normalizeToolCallId id) }
  convertMessagesFromArray transformed (input.contains "image")
    (isAnthropicClaudeModel model.id modelName)

def toolChoiceJson? : ToolChoice → Option Lean.Json
  | .auto => some (LeanAgent.Json.obj [("auto", LeanAgent.Json.obj [])])
  | .any => some (LeanAgent.Json.obj [("any", LeanAgent.Json.obj [])])
  | .none => none
  | .tool name => some (LeanAgent.Json.obj [("tool", LeanAgent.Json.obj [("name", LeanAgent.Json.str name)])])

def convertToolConfig (tools : Array LeanAgent.AI.Tool) (toolChoice : Option ToolChoice) : Option Lean.Json :=
  match toolChoice with
  | some .none => none
  | _ =>
      if tools.isEmpty then
        none
      else
        let bedrockTools := tools.map fun tool =>
          LeanAgent.Json.obj
            [ ("toolSpec",
                LeanAgent.Json.obj
                  [ ("name", LeanAgent.Json.str tool.name)
                  , ("description", LeanAgent.Json.str tool.description)
                  , ("inputSchema", LeanAgent.Json.obj [("json", tool.parameters)])
                  ])
            ]
        let fields := [("tools", LeanAgent.Json.arr bedrockTools)]
          ++ (match toolChoice.bind toolChoiceJson? with
              | some choice => [("toolChoice", choice)]
              | none => [])
        some (LeanAgent.Json.obj fields)

def thinkingBudget
    (customBudgets : Option LeanAgent.AI.ThinkingBudgets)
    (level : LeanAgent.AI.ThinkingLevel) : Nat :=
  LeanAgent.AI.Api.SimpleOptions.thinkingBudgetD customBudgets level

def buildAdditionalModelRequestFields
    (model : LeanAgent.AI.ModelRef)
    (modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (reasoning : Bool)
    (options : BedrockOptions) : Option Lean.Json :=
  match options.reasoning with
  | none => none
  | some level =>
      if !reasoning || !isAnthropicClaudeModel model.id modelName then
        none
      else
        let displayFields :=
          match options.thinkingDisplay.getD .summarized with
          | display => [("display", LeanAgent.Json.str display.toString)]
        if supportsAdaptiveThinking model.id modelName then
          some
            (LeanAgent.Json.obj
              [ ("thinking",
                  LeanAgent.Json.obj
                    ([("type", LeanAgent.Json.str "adaptive")] ++ displayFields))
              , ("output_config",
                  LeanAgent.Json.obj
                    [ ("effort",
                        LeanAgent.Json.str
                          (mapThinkingLevelToEffort model.id modelName thinkingLevelMap level))
                    ])
              ])
        else
          let resultFields :=
            [ ("thinking",
                LeanAgent.Json.obj
                  ([ ("type", LeanAgent.Json.str "enabled")
                   , ("budget_tokens", LeanAgent.Json.nat (thinkingBudget options.thinkingBudgets level))
                   ] ++ displayFields))
            ]
          let resultFields :=
            if options.interleavedThinking.getD true then
              resultFields ++ [("anthropic_beta", LeanAgent.Json.arr #[LeanAgent.Json.str "interleaved-thinking-2025-05-14"])]
            else
              resultFields
          some (LeanAgent.Json.obj resultFields)

def requestToJsonWithOptions
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : BedrockOptions := {}) : Lean.Json :=
  let cacheRetention := options.cacheRetention.getD .short
  let inferenceFields :=
    (match options.maxTokens with
     | some maxTokens => [("maxTokens", LeanAgent.Json.nat maxTokens)]
     | none => [])
    ++ (match options.temperature with
        | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
        | none => [])
  LeanAgent.Json.obj
    ([ ("modelId", LeanAgent.Json.str model.id)
     , ("messages", LeanAgent.Json.arr (convertMessages model input modelName context))
     ] ++ (match buildSystemPrompt context.systemPrompt model.id modelName cacheRetention options.env with
          | some system => [("system", system)]
          | none => [])
       ++ (if inferenceFields.isEmpty then [] else [("inferenceConfig", LeanAgent.Json.obj inferenceFields)])
       ++ (match convertToolConfig context.tools options.toolChoice with
          | some toolConfig => [("toolConfig", toolConfig)]
          | none => [])
       ++ (match buildAdditionalModelRequestFields model modelName thinkingLevelMap reasoning options with
          | some fields => [("additionalModelRequestFields", fields)]
          | none => [])
       ++ (match options.metadata with
          | some metadata => [("requestMetadata", metadata)]
          | none => []))

def applyPayloadHook
    (options : BedrockOptions)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json) : IO Lean.Json := do
  match options.onPayload with
  | none => pure payload
  | some hook =>
      match ← hook payload model with
      | some nextPayload => pure nextPayload
      | none => pure payload

def mapStopReason : Option String → LeanAgent.AI.StopReason
  | some "END_TURN" => .stop
  | some "STOP_SEQUENCE" => .stop
  | some "MAX_TOKENS" => .length
  | some "MODEL_CONTEXT_WINDOW_EXCEEDED" => .length
  | some "TOOL_USE" => .toolUse
  | _ => .error

def stripStringPrefix? (pfx value : String) : Option String :=
  if value.startsWith pfx then some (value.drop pfx.length |>.toString) else none

def stripStringSuffix? (suffix value : String) : Option String :=
  if value.endsWith suffix then some (value.dropEnd suffix.length |>.toString) else none

def hostFromUrl (url : String) : String :=
  let withoutScheme :=
    match stripStringPrefix? "https://" url with
    | some rest => rest
    | none =>
        match stripStringPrefix? "http://" url with
        | some rest => rest
        | none => url
  (withoutScheme.splitOn "/")[0]?.getD withoutScheme

def standardEndpointRegion? (baseUrl : String) : Option String := do
  let host := (hostFromUrl baseUrl).toLower
  let host ←
    match stripStringPrefix? "bedrock-runtime." host with
    | some rest => some rest
    | none => stripStringPrefix? "bedrock-runtime-fips." host
  match stripStringSuffix? ".amazonaws.com.cn" host with
  | some region => some region
  | none => stripStringSuffix? ".amazonaws.com" host

def shouldUseExplicitEndpoint
    (baseUrl : String)
    (configuredRegion : Option String)
    (hasAmbientProfile : Bool) : Bool :=
  match standardEndpointRegion? baseUrl with
  | none => true
  | some _ => configuredRegion.isNone && !hasAmbientProfile

def envValue? (env : LeanAgent.AI.Auth.ProviderEnv) (name : String) : IO (Option String) := do
  match LeanAgent.AI.Auth.providerEnvGet? env name with
  | some value => pure (some value)
  | none =>
      match ← IO.getEnv name with
      | some value =>
          let trimmed := value.trimAscii.toString
          pure (if trimmed.isEmpty then none else some trimmed)
      | none => pure none

def configuredRegion? (options : BedrockOptions) : IO (Option String) := do
  match options.region with
  | some region => pure (some region)
  | none =>
      match ← envValue? options.env "AWS_REGION" with
      | some region => pure (some region)
      | none => envValue? options.env "AWS_DEFAULT_REGION"

def isReservedHeader (name : String) : Bool :=
  let lower := name.toLower
  lower == "authorization" || lower == "host" || lower.startsWith "x-amz-"

def requestHeaders
    (config : BedrockConverseStreamConfig)
    (options : BedrockOptions) : Array (String × String) :=
  let callerHeaders :=
    LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers
      |>.filter fun (name, _) => !isReservedHeader name
  LeanAgent.AI.Util.Headers.merge config.headers callerHeaders

def modelRef (config : BedrockConverseStreamConfig) (model : LeanAgent.AI.ModelRef) :
    LeanAgent.AI.ModelRef :=
  { model with baseUrl := some config.baseUrl }

def completeStreamWithOptions
    (config : BedrockConverseStreamConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : BedrockOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  let requestModel := modelRef config model
  let payload := requestToJsonWithOptions requestModel input modelName thinkingLevelMap reasoning context options
  let _ ← applyPayloadHook options requestModel payload
  throw (IO.userError transportUnavailableMessage)

end LeanAgent.AI.Api.BedrockConverseStream
