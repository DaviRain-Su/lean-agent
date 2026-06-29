import LeanAgent.AI.Api.SimpleOptions
import LeanAgent.AI.Api.TransformMessages
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.JsonParse
import LeanAgent.AI.Util.Retry
import LeanAgent.AI.Util.SSE
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.AnthropicMessages

open LeanAgent

def api : String := "anthropic-messages"
def anthropicVersion : String := "2023-06-01"
def fineGrainedToolStreamingBeta : String := "fine-grained-tool-streaming-2025-05-14"
def interleavedThinkingBeta : String := "interleaved-thinking-2025-05-14"

structure AnthropicMessagesConfig where
  apiKey : String
  baseUrl : String := "https://api.anthropic.com"
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

structure AnthropicMessagesOptions extends LeanAgent.AI.SimpleStreamOptions where
  toolChoice : Option ToolChoice := none
  thinkingEnabled : Option Bool := none
  thinkingBudgetTokens : Option Nat := none
  thinkingEffort : Option String := none
  thinkingDisplay : Option String := none
  supportsTemperature : Bool := true
  sendSessionAffinityHeaders : Bool := false
  supportsLongCacheRetention : Bool := true
  supportsEagerToolInputStreaming : Bool := true
  supportsCacheControlOnTools : Bool := true
  allowEmptySignature : Bool := false
  forceAdaptiveThinking : Bool := false
  interleavedThinking : Bool := true

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : AnthropicMessagesOptions :=
  { temperature := options.temperature
    maxTokens := options.maxTokens
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

def messagesUrl (baseUrl : String) : String :=
  if baseUrl.endsWith "/v1/messages" then
    baseUrl
  else if baseUrl.endsWith "/v1" then
    baseUrl ++ "/messages"
  else if baseUrl.endsWith "/" then
    baseUrl ++ "v1/messages"
  else
    baseUrl ++ "/v1/messages"

def modelRef (config : AnthropicMessagesConfig) (model : LeanAgent.AI.ModelRef) :
    LeanAgent.AI.ModelRef :=
  { model with baseUrl := some config.baseUrl }

def applyPayloadHook
    (options : AnthropicMessagesOptions)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json) : IO Lean.Json := do
  match options.onPayload with
  | none => pure payload
  | some hook =>
      match ← hook payload model with
      | some nextPayload => pure nextPayload
      | none => pure payload

def callResponseHook
    (options : AnthropicMessagesOptions)
    (model : LeanAgent.AI.ModelRef)
    (response : LeanAgent.Http.JsonPostResponse) : IO Unit := do
  match options.onResponse with
  | none => pure ()
  | some hook =>
      hook { status := response.status, headers := response.headers } model

def targetModel (model : LeanAgent.AI.ModelRef) (input : Array String) :
    LeanAgent.AI.Api.TransformMessages.TargetModel :=
  { id := model.id
    provider := model.provider
    api := model.api
    input := input
  }

def normalizeToolCallId
    (id : String)
    (_target : LeanAgent.AI.Api.TransformMessages.TargetModel)
    (_message : LeanAgent.AI.AssistantMessage) : String :=
  LeanAgent.AI.Api.TransformMessages.sanitizeToolCallId id

def jsonObjectUpsert (json : Lean.Json) (key : String) (value : Lean.Json) : Lean.Json :=
  match json with
  | .obj fields =>
      LeanAgent.Json.obj ((fields.toList.filter fun (name, _) => name != key) ++ [(key, value)])
  | _ => json

def cacheControlFields (cacheControl? : Option Lean.Json) : List (String × Lean.Json) :=
  match cacheControl? with
  | some cacheControl => [("cache_control", cacheControl)]
  | none => []

def textBlock (text : String) (cacheControl? : Option Lean.Json := none) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str "text")
     , ("text", LeanAgent.Json.str text)
     ] ++ cacheControlFields cacheControl?)

def imageBlock (image : LeanAgent.AI.ImageContent) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "image")
    , ("source",
        LeanAgent.Json.obj
          [ ("type", LeanAgent.Json.str "base64")
          , ("media_type", LeanAgent.Json.str image.mimeType)
          , ("data", LeanAgent.Json.str image.data)
          ])
    ]

def userContentBlock? : LeanAgent.AI.ContentBlock → Option Lean.Json
  | .text content =>
      if content.text.trimAscii.toString.isEmpty then none else some (textBlock content.text)
  | .image image => some (imageBlock image)
  | .thinking content =>
      if content.thinking.trimAscii.toString.isEmpty then none else some (textBlock content.thinking)
  | .toolCall _ => none

def convertUserContent (content : Array LeanAgent.AI.ContentBlock) : Option Lean.Json :=
  let blocks := content.filterMap userContentBlock?
  if blocks.isEmpty then none else some (LeanAgent.Json.arr blocks)

def toolResultContentBlock? : LeanAgent.AI.ContentBlock → Option Lean.Json
  | .text content =>
      if content.text.trimAscii.toString.isEmpty then none else some (textBlock content.text)
  | .image image => some (imageBlock image)
  | .thinking content =>
      if content.thinking.trimAscii.toString.isEmpty then none else some (textBlock content.thinking)
  | .toolCall call => some (textBlock call.arguments.compress)

def convertToolResultContent (content : Array LeanAgent.AI.ContentBlock) : Lean.Json :=
  let hasImages := content.any fun block =>
    match block with
    | .image _ => true
    | _ => false
  if !hasImages then
    LeanAgent.Json.str (LeanAgent.AI.contentPlainText content)
  else
    let blocks := content.filterMap toolResultContentBlock?
    let hasText := blocks.any fun block =>
      match LeanAgent.Json.optVal? block "type" with
      | some (Lean.Json.str "text") => true
      | _ => false
    let blocks :=
      if hasText then blocks else #[textBlock "(see attached image)"] ++ blocks
    LeanAgent.Json.arr blocks

def thinkingBlock (thinking signature : String) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "thinking")
    , ("thinking", LeanAgent.Json.str thinking)
    , ("signature", LeanAgent.Json.str signature)
    ]

def assistantContentBlock? (allowEmptySignature : Bool) : LeanAgent.AI.ContentBlock → Option Lean.Json
  | .text content =>
      if content.text.trimAscii.toString.isEmpty then none else some (textBlock content.text)
  | .thinking content =>
      if content.redacted then
        content.thinkingSignature.map fun signature =>
          LeanAgent.Json.obj
            [ ("type", LeanAgent.Json.str "redacted_thinking")
            , ("data", LeanAgent.Json.str signature)
            ]
      else if content.thinking.trimAscii.toString.isEmpty then
        none
      else
        match content.thinkingSignature with
        | some signature =>
            if signature.trimAscii.toString.isEmpty then
              if allowEmptySignature then
                some (thinkingBlock content.thinking "")
              else
                some (textBlock content.thinking)
            else
              some (thinkingBlock content.thinking signature)
        | none =>
            if allowEmptySignature then
              some (thinkingBlock content.thinking "")
            else
              some (textBlock content.thinking)
  | .toolCall call =>
      some
        (LeanAgent.Json.obj
          [ ("type", LeanAgent.Json.str "tool_use")
          , ("id", LeanAgent.Json.str call.id)
          , ("name", LeanAgent.Json.str call.name)
          , ("input", call.arguments)
          ])
  | .image _ => none

def convertAssistantContent
    (content : Array LeanAgent.AI.ContentBlock)
    (allowEmptySignature : Bool := false) : Option Lean.Json :=
  let blocks := content.filterMap (assistantContentBlock? allowEmptySignature)
  if blocks.isEmpty then none else some (LeanAgent.Json.arr blocks)

def toolResultBlock (message : LeanAgent.AI.ToolResultMessage) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "tool_result")
    , ("tool_use_id", LeanAgent.Json.str message.toolCallId)
    , ("content", convertToolResultContent message.content)
    , ("is_error", LeanAgent.Json.bool message.isError)
    ]

partial def collectToolResults :
    List LeanAgent.AI.Message → Array Lean.Json → Array Lean.Json × List LeanAgent.AI.Message
  | .toolResult result :: rest, acc => collectToolResults rest (acc.push (toolResultBlock result))
  | rest, acc => (acc, rest)

partial def convertMessagesAux
    (messages : List LeanAgent.AI.Message)
    (allowEmptySignature : Bool := false)
    (acc : Array Lean.Json := #[]) : Array Lean.Json :=
  match messages with
  | [] => acc
  | .user message :: rest =>
      match convertUserContent message.content with
      | some content =>
          convertMessagesAux rest allowEmptySignature
            (acc.push (LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "user")
              , ("content", content)
              ]))
      | none => convertMessagesAux rest allowEmptySignature acc
  | .assistant message :: rest =>
      match convertAssistantContent message.content allowEmptySignature with
      | some content =>
          convertMessagesAux rest allowEmptySignature
            (acc.push (LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "assistant")
              , ("content", content)
              ]))
      | none => convertMessagesAux rest allowEmptySignature acc
  | .toolResult result :: rest =>
      let (toolResults, remaining) := collectToolResults rest #[toolResultBlock result]
      convertMessagesAux remaining allowEmptySignature
        (acc.push (LeanAgent.Json.obj
          [ ("role", LeanAgent.Json.str "user")
          , ("content", LeanAgent.Json.arr toolResults)
          ]))

def addCacheControlToLastUserBlock (message : Lean.Json) (cacheControl : Lean.Json) : Lean.Json :=
  match LeanAgent.Json.optVal? message "role", LeanAgent.Json.optVal? message "content" with
  | some (Lean.Json.str "user"), some (Lean.Json.arr blocks) =>
      if blocks.isEmpty then
        message
      else
        let updatedBlocks := blocks.mapIdx fun index block =>
          if index + 1 == blocks.size then
            jsonObjectUpsert block "cache_control" cacheControl
          else
            block
        jsonObjectUpsert message "content" (LeanAgent.Json.arr updatedBlocks)
  | some (Lean.Json.str "user"), some (Lean.Json.str content) =>
      jsonObjectUpsert message "content" (LeanAgent.Json.arr #[textBlock content (some cacheControl)])
  | _, _ => message

def addCacheControlToLastUserMessage
    (messages : Array Lean.Json)
    (cacheControl? : Option Lean.Json) : Array Lean.Json :=
  match cacheControl? with
  | none => messages
  | some cacheControl =>
      messages.mapIdx fun index message =>
        if index + 1 == messages.size then
          addCacheControlToLastUserBlock message cacheControl
        else
          message

def convertMessages
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (context : LeanAgent.AI.Context)
    (cacheControl? : Option Lean.Json := none)
    (allowEmptySignature : Bool := false) : Array Lean.Json :=
  let transformed :=
    LeanAgent.AI.Api.TransformMessages.transformMessages
      context.messages
      (targetModel model input)
      { normalizeToolCallId? := some normalizeToolCallId }
  addCacheControlToLastUserMessage
    (convertMessagesAux transformed.toList allowEmptySignature)
    cacheControl?

def systemFields (context : LeanAgent.AI.Context) (cacheControl? : Option Lean.Json := none) : List (String × Lean.Json) :=
  match context.systemPrompt with
  | some prompt =>
      if prompt.trimAscii.toString.isEmpty then
        []
      else
        [("system", LeanAgent.Json.arr #[textBlock prompt cacheControl?])]
  | none => []

def toolToJson
    (tool : LeanAgent.AI.Tool)
    (supportsEagerToolInputStreaming : Bool := true) : Lean.Json :=
  let properties := (LeanAgent.Json.optVal? tool.parameters "properties").getD (LeanAgent.Json.obj [])
  let required := (LeanAgent.Json.optVal? tool.parameters "required").getD (LeanAgent.Json.arr #[])
  LeanAgent.Json.obj
    ([ ("name", LeanAgent.Json.str tool.name)
     , ("description", LeanAgent.Json.str tool.description)
     ] ++
     (if supportsEagerToolInputStreaming then
       [("eager_input_streaming", LeanAgent.Json.bool true)]
     else
       []) ++
     [ ("input_schema",
          LeanAgent.Json.obj
            [ ("type", LeanAgent.Json.str "object")
            , ("properties", properties)
            , ("required", required)
            ])
     ])

def toolFields
    (tools : Array LeanAgent.AI.Tool)
    (cacheControl? : Option Lean.Json := none)
    (supportsEagerToolInputStreaming : Bool := true)
    (supportsCacheControlOnTools : Bool := true) : List (String × Lean.Json) :=
  if tools.isEmpty then
    []
  else
    let toolJson := tools.mapIdx fun index tool =>
      let json := toolToJson tool supportsEagerToolInputStreaming
      match cacheControl? with
      | some cacheControl =>
          if supportsCacheControlOnTools && index + 1 == tools.size then
            jsonObjectUpsert json "cache_control" cacheControl
          else
            json
      | none => json
    [("tools", LeanAgent.Json.arr toolJson)]

def ToolChoice.toJson : ToolChoice → Lean.Json
  | .auto => LeanAgent.Json.obj [("type", LeanAgent.Json.str "auto")]
  | .any => LeanAgent.Json.obj [("type", LeanAgent.Json.str "any")]
  | .none => LeanAgent.Json.obj [("type", LeanAgent.Json.str "none")]
  | .tool name =>
      LeanAgent.Json.obj
        [ ("type", LeanAgent.Json.str "tool")
        , ("name", LeanAgent.Json.str name)
        ]

def toolChoiceFields (options : AnthropicMessagesOptions) : List (String × Lean.Json) :=
  match options.toolChoice with
  | some choice => [("tool_choice", choice.toJson)]
  | none => []

def requestOptionFields
    (modelMaxTokens : Nat)
    (options : AnthropicMessagesOptions) : List (String × Lean.Json) :=
  let maxTokens := options.maxTokens.getD modelMaxTokens
  let maxTokenFields := [("max_tokens", LeanAgent.Json.nat maxTokens)]
  let temperatureFields :=
    match options.temperature with
    | some temperature =>
        if options.thinkingEnabled == some true || !options.supportsTemperature then
          []
        else
          [("temperature", LeanAgent.AI.floatJson temperature)]
    | none => []
  maxTokenFields ++ temperatureFields

def thinkingFields
    (reasoning : Bool)
    (options : AnthropicMessagesOptions) : List (String × Lean.Json) :=
  if !reasoning then
    []
  else
    match options.thinkingEnabled with
    | some true =>
        let display := options.thinkingDisplay.getD "summarized"
        let base :=
          match options.thinkingEffort with
          | some _ =>
              [ ("type", LeanAgent.Json.str "adaptive")
              , ("display", LeanAgent.Json.str display)
              ]
          | none =>
              [ ("type", LeanAgent.Json.str "enabled")
              , ("budget_tokens", LeanAgent.Json.nat (options.thinkingBudgetTokens.getD 1024))
              , ("display", LeanAgent.Json.str display)
              ]
        [("thinking", LeanAgent.Json.obj base)]
    | some false => [("thinking", LeanAgent.Json.obj [("type", LeanAgent.Json.str "disabled")])]
    | none => []

def outputConfigFields
    (reasoning : Bool)
    (options : AnthropicMessagesOptions) : List (String × Lean.Json) :=
  if !reasoning || options.thinkingEnabled != some true then
    []
  else
    match options.thinkingEffort with
    | some effort =>
        [ ("output_config",
            LeanAgent.Json.obj [("effort", LeanAgent.Json.str effort)])
        ]
    | none => []

def metadataFields (metadata? : Option Lean.Json) : List (String × Lean.Json) :=
  match metadata? with
  | none => []
  | some metadata =>
      match LeanAgent.Json.optVal? metadata "user_id" with
      | some (Lean.Json.str userId) =>
          [("metadata", LeanAgent.Json.obj [("user_id", LeanAgent.Json.str userId)])]
      | _ => []

def cacheRetentionFromEnv? (env : Array (String × String)) : Option LeanAgent.AI.CacheRetention :=
  env.findSome? fun (name, value) =>
    if name == "PI_CACHE_RETENTION" && value == "long" then
      some .long
    else
      none

def resolveCacheRetention (options : AnthropicMessagesOptions) : LeanAgent.AI.CacheRetention :=
  match options.cacheRetention with
  | some retention => retention
  | none => (cacheRetentionFromEnv? options.env).getD .short

def cacheControl? (options : AnthropicMessagesOptions) : Option Lean.Json :=
  let retention := resolveCacheRetention options
  if retention == .none then
    none
  else
    let ttlFields :=
      if retention == .long && options.supportsLongCacheRetention then
        [("ttl", LeanAgent.Json.str "1h")]
      else
        []
    some (LeanAgent.Json.obj ([("type", LeanAgent.Json.str "ephemeral")] ++ ttlFields))

def requestToJsonWithOptions
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelMaxTokens : Nat)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : AnthropicMessagesOptions := {})
    (stream : Bool := false) : Lean.Json :=
  let cacheControl := cacheControl? options
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str model.id)
     , ("messages", LeanAgent.Json.arr
          (convertMessages model input context cacheControl options.allowEmptySignature))
     , ("stream", LeanAgent.Json.bool stream)
     ] ++ systemFields context cacheControl
       ++ requestOptionFields modelMaxTokens options
       ++ thinkingFields reasoning options
       ++ outputConfigFields reasoning options
       ++ toolFields
            context.tools
            cacheControl
            options.supportsEagerToolInputStreaming
            options.supportsCacheControlOnTools
       ++ toolChoiceFields options
       ++ metadataFields options.metadata)

def shouldUseFineGrainedToolStreamingBeta
    (tools : Array LeanAgent.AI.Tool)
    (options : AnthropicMessagesOptions) : Bool :=
  !tools.isEmpty && !options.supportsEagerToolInputStreaming

def betaFeatures
    (tools : Array LeanAgent.AI.Tool)
    (options : AnthropicMessagesOptions) : Array String :=
  let fineGrainedFeatures :=
    if shouldUseFineGrainedToolStreamingBeta tools options then
      #[fineGrainedToolStreamingBeta]
    else
      #[]
  let interleavedFeatures :=
    if options.interleavedThinking && !options.forceAdaptiveThinking then
      #[interleavedThinkingBeta]
    else
      #[]
  fineGrainedFeatures ++ interleavedFeatures

def betaHeaderValue? (features : Array String) : Option String :=
  if features.isEmpty then none else some (String.intercalate "," features.toList)

def requestHeaders
    (config : AnthropicMessagesConfig)
    (options : AnthropicMessagesOptions)
    (tools : Array LeanAgent.AI.Tool := #[]) : Array (String × String) :=
  let features := betaFeatures tools options
  let betaHeader := betaHeaderValue? features
  let authHeaders :=
    if config.apiKey.trimAscii.toString.isEmpty then
      #[]
    else if config.apiKey.contains "sk-ant-oat" then
      let betaSuffix :=
        match betaHeader with
        | some value => "," ++ value
        | none => ""
      #[ ("Authorization", "Bearer " ++ config.apiKey)
       , ("anthropic-beta", "claude-code-20250219,oauth-2025-04-20" ++ betaSuffix)
       , ("user-agent", "claude-cli/2.1.75")
       , ("x-app", "cli")
       ]
    else
      #[("x-api-key", config.apiKey)]
  let betaHeaders :=
    match betaHeader with
    | some value =>
        if config.apiKey.contains "sk-ant-oat" then #[] else #[("anthropic-beta", value)]
    | none => #[]
  let sessionHeaders :=
    if options.sendSessionAffinityHeaders && options.cacheRetention != some .none then
      match options.sessionId with
      | some sessionId => #[("x-session-affinity", sessionId)]
      | none => #[]
    else
      #[]
  LeanAgent.AI.Util.Headers.mergeProvider
    (config.headers ++
      (authHeaders ++
      betaHeaders ++
      sessionHeaders ++
      #[ ("anthropic-version", anthropicVersion)
       , ("accept", "application/json")
       , ("anthropic-dangerous-direct-browser-access", "true")
       ]))
    options.headers

def runHttpJson
    (config : AnthropicMessagesConfig)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json)
    (options : AnthropicMessagesOptions := {})
    (tools : Array LeanAgent.AI.Tool := #[]) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := messagesUrl config.baseUrl
      apiKey := ""
      headers := requestHeaders config options tools
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
    }
    payload.compress
  callResponseHook options (modelRef config model) response
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError (LeanAgent.AI.Util.Diagnostics.providerHttpErrorMessage response.status response.body))
  pure response.body

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

def parseUsage (rawUsage : Lean.Json) : LeanAgent.AI.Usage :=
  let input := natFieldD rawUsage "input_tokens"
  let output := natFieldD rawUsage "output_tokens"
  let cacheRead := natFieldD rawUsage "cache_read_input_tokens"
  let cacheWrite := natFieldD rawUsage "cache_creation_input_tokens"
  let cacheCreation := objField? rawUsage "cache_creation"
  let outputDetails := objField? rawUsage "output_tokens_details"
  let cacheWrite1h := cacheCreation.map (fun details => natFieldD details "ephemeral_1h_input_tokens")
  let reasoning := outputDetails.map (fun details => natFieldD details "thinking_tokens")
  { input := input
    output := output
    cacheRead := cacheRead
    cacheWrite := cacheWrite
    cacheWrite1h := cacheWrite1h
    reasoning := reasoning
    totalTokens := input + output + cacheRead + cacheWrite
  }

def parseUsage? (json : Lean.Json) : LeanAgent.AI.Usage :=
  match LeanAgent.Json.optVal? json "usage" with
  | some usage => parseUsage usage
  | none => LeanAgent.AI.Usage.empty

def updateUsage (current : LeanAgent.AI.Usage) (rawUsage : Lean.Json) : LeanAgent.AI.Usage :=
  let input := (natField? rawUsage "input_tokens").getD current.input
  let output := (natField? rawUsage "output_tokens").getD current.output
  let cacheRead := (natField? rawUsage "cache_read_input_tokens").getD current.cacheRead
  let cacheWrite := (natField? rawUsage "cache_creation_input_tokens").getD current.cacheWrite
  let cacheWrite1h :=
    match objField? rawUsage "cache_creation" with
    | some details =>
        match natField? details "ephemeral_1h_input_tokens" with
        | some tokens => some tokens
        | none => current.cacheWrite1h
    | none => current.cacheWrite1h
  let reasoning :=
    match objField? rawUsage "output_tokens_details" with
    | some details =>
        match natField? details "thinking_tokens" with
        | some tokens => some tokens
        | none => current.reasoning
    | none => current.reasoning
  { current with
    input := input
    output := output
    cacheRead := cacheRead
    cacheWrite := cacheWrite
    cacheWrite1h := cacheWrite1h
    reasoning := reasoning
    totalTokens := input + output + cacheRead + cacheWrite
  }

def stopReasonFromAnthropic (reason : Option String) : Except String LeanAgent.AI.StopReason :=
  match reason with
  | some "end_turn" => pure .stop
  | some "pause_turn" => pure .stop
  | some "stop_sequence" => pure .stop
  | some "max_tokens" => pure .length
  | some "tool_use" => pure .toolUse
  | some "refusal" => pure .error
  | some "sensitive" => pure .error
  | some other => throw s!"Unhandled Anthropic stop reason: {other}"
  | none => pure .stop

def optionalStringField (json : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? json key with
  | some (Lean.Json.str value) => some value
  | _ => none

def parseToolInput (raw : Lean.Json) : Lean.Json :=
  match raw.getObj? with
  | .ok _ => raw
  | .error _ => LeanAgent.Json.obj []

def parseContentBlock (json : Lean.Json) : Except String (Option LeanAgent.AI.ContentBlock) := do
  let contentType ← (← json.getObjVal? "type").getStr?
  match contentType with
  | "text" =>
      pure (some (.text { text := (← (← json.getObjVal? "text").getStr?) }))
  | "thinking" =>
      pure (some (.thinking
        { thinking := (← (← json.getObjVal? "thinking").getStr?)
          thinkingSignature := optionalStringField json "signature"
        }))
  | "redacted_thinking" =>
      pure (some (.thinking
        { thinking := "[Reasoning redacted]"
          thinkingSignature := optionalStringField json "data"
          redacted := true
        }))
  | "tool_use" =>
      pure (some (.toolCall
        { id := (← (← json.getObjVal? "id").getStr?)
          name := (← (← json.getObjVal? "name").getStr?)
          arguments := parseToolInput ((LeanAgent.Json.optVal? json "input").getD (LeanAgent.Json.obj []))
        }))
  | _ => pure none

def parseContent (json : Lean.Json) : Except String (Array LeanAgent.AI.ContentBlock) := do
  let rawBlocks ← (← json.getObjVal? "content").getArr?
  let mut blocks := #[]
  for rawBlock in rawBlocks do
    match ← parseContentBlock rawBlock with
    | some block => blocks := blocks.push block
    | none => pure ()
  pure blocks

inductive StreamingBlockKind where
  | text
  | thinking
  | toolCall
deriving BEq

structure StreamingBlock where
  streamIndex : Nat
  contentIndex : Nat
  kind : StreamingBlockKind
  text : String := ""
  thinkingSignature : Option String := none
  redacted : Bool := false
  id : String := ""
  name : String := ""
  partialArguments : String := ""
  ended : Bool := false
deriving BEq

structure StreamingState where
  blocks : Array StreamingBlock := #[]
  order : Array Nat := #[]
  responseId : Option String := none
  responseModel : Option String := none
  usage : LeanAgent.AI.Usage := LeanAgent.AI.Usage.empty
  stopReason : LeanAgent.AI.StopReason := .stop
  errorMessage : Option String := none
  sawMessageStart : Bool := false
  sawMessageStop : Bool := false
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

def findBlock? (state : StreamingState) (streamIndex : Nat) : Option StreamingBlock :=
  state.blocks.find? fun block => block.streamIndex == streamIndex

def updateBlock (state : StreamingState) (next : StreamingBlock) : StreamingState :=
  { state with
    blocks := state.blocks.map fun block =>
      if block.streamIndex == next.streamIndex then next else block
  }

def pushBlock (state : StreamingState) (block : StreamingBlock) : StreamingState :=
  { state with
    blocks := state.blocks.push block
    order := state.order.push block.streamIndex
  }

def contentBlockKind? (contentBlock : Lean.Json) : Option StreamingBlockKind :=
  match optionalStringField contentBlock "type" with
  | some "text" => some .text
  | some "thinking" => some .thinking
  | some "redacted_thinking" => some .thinking
  | some "tool_use" => some .toolCall
  | _ => none

def blockFromContentBlock (streamIndex contentIndex : Nat) (contentBlock : Lean.Json) :
    Option StreamingBlock :=
  match contentBlockKind? contentBlock with
  | none => none
  | some .text => some { streamIndex := streamIndex, contentIndex := contentIndex, kind := .text }
  | some .thinking =>
      let redacted := optionalStringField contentBlock "type" == some "redacted_thinking"
      let text := if redacted then "[Reasoning redacted]" else ""
      let signature :=
        if redacted then optionalStringField contentBlock "data" else optionalStringField contentBlock "signature"
      some
        { streamIndex := streamIndex
          contentIndex := contentIndex
          kind := .thinking
          text := text
          thinkingSignature := signature
          redacted := redacted
        }
  | some .toolCall =>
      some
        { streamIndex := streamIndex
          contentIndex := contentIndex
          kind := .toolCall
          id := optionalStringField contentBlock "id" |>.getD ""
          name := optionalStringField contentBlock "name" |>.getD ""
        }

def startEventForBlock (block : StreamingBlock) : ParsedStreamEvent :=
  match block.kind with
  | .text => .textStart block.contentIndex
  | .thinking => .thinkingStart block.contentIndex
  | .toolCall => .toolCallStart block.contentIndex

def toolCallFromBlock (block : StreamingBlock) : LeanAgent.AI.ToolCall :=
  { id := block.id
    name := block.name
    arguments := LeanAgent.AI.Util.JsonParse.parseStreamingJson block.partialArguments
  }

def contentBlockFromStreamingBlock (block : StreamingBlock) : Option LeanAgent.AI.ContentBlock :=
  match block.kind with
  | .text => some (.text { text := block.text })
  | .thinking =>
      some (.thinking
        { thinking := block.text
          thinkingSignature := block.thinkingSignature
          redacted := block.redacted
        })
  | .toolCall => some (.toolCall (toolCallFromBlock block))

def contentFromStreamingState (state : StreamingState) : Array LeanAgent.AI.ContentBlock :=
  state.order.filterMap fun streamIndex =>
    match findBlock? state streamIndex with
    | some block => contentBlockFromStreamingBlock block
    | none => none

def messageFromStreamingState
    (api provider model : String)
    (timestamp : Nat)
    (state : StreamingState) : LeanAgent.AI.AssistantMessage :=
  { content := contentFromStreamingState state
    api := api
    provider := provider
    model := model
    responseId := state.responseId
    responseModel := state.responseModel.filter (fun responseModel => responseModel != model)
    usage := state.usage
    stopReason := state.stopReason
    errorMessage := state.errorMessage
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

def fallbackBlock (streamIndex contentIndex : Nat) (kind : StreamingBlockKind) : StreamingBlock :=
  { streamIndex := streamIndex, contentIndex := contentIndex, kind := kind }

def ensureBlock
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (streamIndex : Nat)
    (kind : StreamingBlockKind) :
    StreamingState × Array ParsedStreamEvent × StreamingBlock :=
  match findBlock? state streamIndex with
  | some block => (state, events, block)
  | none =>
      let block := fallbackBlock streamIndex state.order.size kind
      let state := pushBlock state block
      (state, events.push (startEventForBlock block), block)

def applyContentBlockStart
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (event : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  match LeanAgent.Json.optVal? event "content_block" with
  | none => (state, events)
  | some contentBlock =>
      let streamIndex := natFieldD event "index" state.order.size
      match blockFromContentBlock streamIndex state.order.size contentBlock with
      | none => (state, events)
      | some block =>
          match findBlock? state streamIndex with
          | some _ => (state, events)
          | none => (pushBlock state block, events.push (startEventForBlock block))

def applyTextDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (streamIndex : Nat)
    (delta : String) : StreamingState × Array ParsedStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let (state, events, block) := ensureBlock state events streamIndex .text
    let block := { block with text := block.text ++ delta }
    (updateBlock state block, events.push (.textDelta block.contentIndex delta))

def applyThinkingDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (streamIndex : Nat)
    (delta : String) : StreamingState × Array ParsedStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let (state, events, block) := ensureBlock state events streamIndex .thinking
    let block := { block with text := block.text ++ delta }
    (updateBlock state block, events.push (.thinkingDelta block.contentIndex delta))

def applySignatureDelta
    (state : StreamingState)
    (streamIndex : Nat)
    (signature : String) : StreamingState :=
  match findBlock? state streamIndex with
  | none => state
  | some block =>
      if block.kind != .thinking then
        state
      else
        let current := block.thinkingSignature.getD ""
        updateBlock state { block with thinkingSignature := some (current ++ signature) }

def applyToolInputDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (streamIndex : Nat)
    (delta : String) : StreamingState × Array ParsedStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let (state, events, block) := ensureBlock state events streamIndex .toolCall
    let block := { block with partialArguments := block.partialArguments ++ delta }
    (updateBlock state block, events.push (.toolCallDelta block.contentIndex delta))

def applyContentBlockDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (event : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let streamIndex := natFieldD event "index" 0
  match LeanAgent.Json.optVal? event "delta" with
  | none => (state, events)
  | some delta =>
      match optionalStringField delta "type" with
      | some "text_delta" => applyTextDelta state events streamIndex (optionalStringField delta "text" |>.getD "")
      | some "thinking_delta" =>
          applyThinkingDelta state events streamIndex (optionalStringField delta "thinking" |>.getD "")
      | some "input_json_delta" =>
          applyToolInputDelta state events streamIndex (optionalStringField delta "partial_json" |>.getD "")
      | some "signature_delta" =>
          (applySignatureDelta state streamIndex (optionalStringField delta "signature" |>.getD ""), events)
      | _ => (state, events)

def applyContentBlockStop
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (event : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let streamIndex := natFieldD event "index" 0
  match findBlock? state streamIndex with
  | none => (state, events)
  | some block =>
      if block.ended then
        (state, events)
      else
        let block := { block with ended := true }
        let state := updateBlock state block
        let event :=
          match block.kind with
          | .text => ParsedStreamEvent.textEnd block.contentIndex block.text
          | .thinking => ParsedStreamEvent.thinkingEnd block.contentIndex block.text
          | .toolCall => ParsedStreamEvent.toolCallEnd block.contentIndex (toolCallFromBlock block)
        (state, events.push event)

def applyMessageStart (state : StreamingState) (event : Lean.Json) : StreamingState :=
  match LeanAgent.Json.optVal? event "message" with
  | none => { state with sawMessageStart := true }
  | some message =>
      let usage :=
        match LeanAgent.Json.optVal? message "usage" with
        | some usage => updateUsage state.usage usage
        | none => state.usage
      { state with
        sawMessageStart := true
        responseId := optionalStringField message "id" <|> state.responseId
        responseModel := optionalStringField message "model" <|> state.responseModel
        usage := usage
      }

def applyMessageDelta (state : StreamingState) (event : Lean.Json) : Except String StreamingState := do
  let state ←
    match LeanAgent.Json.optVal? event "delta" with
    | none => pure state
    | some delta =>
        match optionalStringField delta "stop_reason" with
        | none => pure state
        | some reason =>
            let stopReason ← stopReasonFromAnthropic (some reason)
            let errorMessage :=
              if stopReason == .error then
                some "Anthropic returned an error stop reason"
              else
                state.errorMessage
            pure { state with stopReason := stopReason, errorMessage := errorMessage }
  match LeanAgent.Json.optVal? event "usage" with
  | some usage => pure { state with usage := updateUsage state.usage usage }
  | none => pure state

def applyStreamEvent
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (event : Lean.Json) : Except String (StreamingState × Array ParsedStreamEvent) := do
  match optionalStringField event "type" with
  | some "message_start" => pure (applyMessageStart state event, events)
  | some "content_block_start" => pure (applyContentBlockStart state events event)
  | some "content_block_delta" => pure (applyContentBlockDelta state events event)
  | some "content_block_stop" => pure (applyContentBlockStop state events event)
  | some "message_delta" => pure (← applyMessageDelta state event, events)
  | some "message_stop" => pure ({ state with sawMessageStop := true }, events)
  | some "error" =>
      let message := optionalStringField event "message" |>.getD event.compress
      throw message
  | _ => pure (state, events)

def parseStreamingEvents (raw : String) : Except String (Array Lean.Json) := do
  let mut chunks := #[]
  for event in LeanAgent.AI.Util.SSE.parse raw do
    let data := event.data.trimAscii.toString
    if data == "[DONE]" || data.isEmpty then
      pure ()
    else
      let json ← LeanAgent.AI.Util.JsonParse.parseJsonWithRepair event.data
      chunks := chunks.push json
  pure chunks

def finalizeOpenBlocks
    (state : StreamingState)
    (events : Array ParsedStreamEvent) : StreamingState × Array ParsedStreamEvent :=
  Id.run do
    let mut state := state
    let mut events := events
    for streamIndex in state.order do
      match findBlock? state streamIndex with
      | none => pure ()
      | some block =>
          if block.ended then
            pure ()
          else
            let (nextState, nextEvents) :=
              applyContentBlockStop state events
                (LeanAgent.Json.obj [("index", LeanAgent.Json.nat streamIndex)])
            state := nextState
            events := nextEvents
    pure (state, events)

def parseStreamingEventStream
    (api provider model : String)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantMessageEventStream := do
  let chunks ← parseStreamingEvents raw
  let mut state : StreamingState := {}
  let mut parsedEvents : Array ParsedStreamEvent := #[]
  for chunk in chunks do
    let (nextState, nextEvents) ← applyStreamEvent state parsedEvents chunk
    state := nextState
    parsedEvents := nextEvents
  if state.sawMessageStart && !state.sawMessageStop then
    throw "Anthropic stream ended before message_stop"
  let (finalState, finalParsedEvents) := finalizeOpenBlocks state parsedEvents
  let message := messageFromStreamingState api provider model timestamp finalState
  let events :=
    #[LeanAgent.AI.AssistantMessageEvent.start message]
      ++ finalParsedEvents.map (parsedEventToAssistantEvent message)
      ++ #[LeanAgent.AI.completionEvent message]
  pure { events := events, finalResult := message }

def parseResponse
    (api provider model : String)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantMessage := do
  let json ← Lean.Json.parse raw
  let stopReason ← stopReasonFromAnthropic (optionalStringField json "stop_reason")
  pure
    { content := (← parseContent json)
      api := api
      provider := provider
      model := model
      responseId := optionalStringField json "id"
      responseModel := optionalStringField json "model" |>.filter (fun responseModel => responseModel != model)
      usage := parseUsage? json
      stopReason := stopReason
      errorMessage :=
        if stopReason == .error then
          some "Anthropic returned an error stop reason"
        else
          none
      timestamp := timestamp
    }

def completeWithOptions
    (config : AnthropicMessagesConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelMaxTokens : Nat)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : AnthropicMessagesOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let ref := modelRef config model
  let payload ← applyPayloadHook options ref
    (requestToJsonWithOptions ref input modelMaxTokens reasoning context options false)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config ref payload options context.tools)
  let timestamp ← IO.monoMsNow
  match parseResponse model.api model.provider model.id timestamp raw with
  | .ok message => pure message
  | .error err => throw (IO.userError s!"failed to parse Anthropic response: {err}\n{raw}")

def completeStreamWithOptions
    (config : AnthropicMessagesConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelMaxTokens : Nat)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : AnthropicMessagesOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  let ref := modelRef config model
  let payload ← applyPayloadHook options ref
    (requestToJsonWithOptions ref input modelMaxTokens reasoning context options true)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config ref payload options context.tools)
  let timestamp ← IO.monoMsNow
  match parseStreamingEventStream model.api model.provider model.id timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse Anthropic streaming response: {err}\n{raw}")

end LeanAgent.AI.Api.AnthropicMessages
