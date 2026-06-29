import LeanAgent.AI.Api.SimpleOptions
import LeanAgent.AI.Api.TransformMessages
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.JsonParse
import LeanAgent.AI.Util.Retry
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.AnthropicMessages

open LeanAgent

def api : String := "anthropic-messages"
def anthropicVersion : String := "2023-06-01"

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

def textBlock (text : String) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "text")
    , ("text", LeanAgent.Json.str text)
    ]

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

def assistantContentBlock? : LeanAgent.AI.ContentBlock → Option Lean.Json
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
            some
              (LeanAgent.Json.obj
                [ ("type", LeanAgent.Json.str "thinking")
                , ("thinking", LeanAgent.Json.str content.thinking)
                , ("signature", LeanAgent.Json.str signature)
                ])
        | none => some (textBlock content.thinking)
  | .toolCall call =>
      some
        (LeanAgent.Json.obj
          [ ("type", LeanAgent.Json.str "tool_use")
          , ("id", LeanAgent.Json.str call.id)
          , ("name", LeanAgent.Json.str call.name)
          , ("input", call.arguments)
          ])
  | .image _ => none

def convertAssistantContent (content : Array LeanAgent.AI.ContentBlock) : Option Lean.Json :=
  let blocks := content.filterMap assistantContentBlock?
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
    (acc : Array Lean.Json := #[]) : Array Lean.Json :=
  match messages with
  | [] => acc
  | .user message :: rest =>
      match convertUserContent message.content with
      | some content =>
          convertMessagesAux rest
            (acc.push (LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "user")
              , ("content", content)
              ]))
      | none => convertMessagesAux rest acc
  | .assistant message :: rest =>
      match convertAssistantContent message.content with
      | some content =>
          convertMessagesAux rest
            (acc.push (LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "assistant")
              , ("content", content)
              ]))
      | none => convertMessagesAux rest acc
  | .toolResult result :: rest =>
      let (toolResults, remaining) := collectToolResults rest #[toolResultBlock result]
      convertMessagesAux remaining
        (acc.push (LeanAgent.Json.obj
          [ ("role", LeanAgent.Json.str "user")
          , ("content", LeanAgent.Json.arr toolResults)
          ]))

def convertMessages
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (context : LeanAgent.AI.Context) : Array Lean.Json :=
  let transformed :=
    LeanAgent.AI.Api.TransformMessages.transformMessages
      context.messages
      (targetModel model input)
      { normalizeToolCallId? := some normalizeToolCallId }
  convertMessagesAux transformed.toList

def systemFields (context : LeanAgent.AI.Context) : List (String × Lean.Json) :=
  match context.systemPrompt with
  | some prompt =>
      if prompt.trimAscii.toString.isEmpty then
        []
      else
        [("system", LeanAgent.Json.arr #[textBlock prompt])]
  | none => []

def toolToJson (tool : LeanAgent.AI.Tool) : Lean.Json :=
  let properties := (LeanAgent.Json.optVal? tool.parameters "properties").getD (LeanAgent.Json.obj [])
  let required := (LeanAgent.Json.optVal? tool.parameters "required").getD (LeanAgent.Json.arr #[])
  LeanAgent.Json.obj
    [ ("name", LeanAgent.Json.str tool.name)
    , ("description", LeanAgent.Json.str tool.description)
    , ("input_schema",
        LeanAgent.Json.obj
          [ ("type", LeanAgent.Json.str "object")
          , ("properties", properties)
          , ("required", required)
          ])
    ]

def toolFields (tools : Array LeanAgent.AI.Tool) : List (String × Lean.Json) :=
  if tools.isEmpty then [] else [("tools", LeanAgent.Json.arr (tools.map toolToJson))]

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
    | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
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
          | some effort =>
              [ ("type", LeanAgent.Json.str "adaptive")
              , ("display", LeanAgent.Json.str display)
              , ("effort", LeanAgent.Json.str effort)
              ]
          | none =>
              [ ("type", LeanAgent.Json.str "enabled")
              , ("budget_tokens", LeanAgent.Json.nat (options.thinkingBudgetTokens.getD 1024))
              , ("display", LeanAgent.Json.str display)
              ]
        [("thinking", LeanAgent.Json.obj base)]
    | some false => [("thinking", LeanAgent.Json.obj [("type", LeanAgent.Json.str "disabled")])]
    | none => []

def metadataFields (metadata? : Option Lean.Json) : List (String × Lean.Json) :=
  match metadata? with
  | none => []
  | some metadata =>
      match LeanAgent.Json.optVal? metadata "user_id" with
      | some (Lean.Json.str userId) =>
          [("metadata", LeanAgent.Json.obj [("user_id", LeanAgent.Json.str userId)])]
      | _ => []

def requestToJsonWithOptions
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelMaxTokens : Nat)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : AnthropicMessagesOptions := {})
    (stream : Bool := false) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str model.id)
     , ("messages", LeanAgent.Json.arr (convertMessages model input context))
     , ("stream", LeanAgent.Json.bool stream)
     ] ++ systemFields context
       ++ requestOptionFields modelMaxTokens options
       ++ thinkingFields reasoning options
       ++ toolFields context.tools
       ++ toolChoiceFields options
       ++ metadataFields options.metadata)

def requestHeaders
    (config : AnthropicMessagesConfig)
    (options : AnthropicMessagesOptions) : Array (String × String) :=
  let authHeaders :=
    if config.apiKey.trimAscii.toString.isEmpty then
      #[]
    else if config.apiKey.contains "sk-ant-oat" then
      #[ ("Authorization", "Bearer " ++ config.apiKey)
       , ("anthropic-beta", "claude-code-20250219,oauth-2025-04-20")
       , ("user-agent", "claude-cli/2.1.75")
       , ("x-app", "cli")
       ]
    else
      #[("x-api-key", config.apiKey)]
  LeanAgent.AI.Util.Headers.merge
    (config.headers ++
      (authHeaders ++
      #[ ("anthropic-version", anthropicVersion)
       , ("accept", "application/json")
       , ("anthropic-dangerous-direct-browser-access", "true")
       ]))
    (LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers)

def runHttpJson
    (config : AnthropicMessagesConfig)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json)
    (options : AnthropicMessagesOptions := {}) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := messagesUrl config.baseUrl
      apiKey := ""
      headers := requestHeaders config options
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
    (runHttpJson config ref payload options)
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
  let message ← completeWithOptions config model input modelMaxTokens reasoning context options
  pure (LeanAgent.AI.fromMessage message)

end LeanAgent.AI.Api.AnthropicMessages
