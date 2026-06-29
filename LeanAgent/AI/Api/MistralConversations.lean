import LeanAgent.AI.Api.SimpleOptions
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Hash
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.JsonParse
import LeanAgent.AI.Util.Retry
import LeanAgent.AI.Util.SSE
import LeanAgent.AI.Util.SanitizeUnicode
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.MistralConversations

open LeanAgent

def api : String := "mistral-conversations"
def defaultBaseUrl : String := "https://api.mistral.ai"
def mistralToolCallIdLength : Nat := 9

structure MistralConversationsConfig where
  apiKey : String
  baseUrl : String := defaultBaseUrl
  headers : Array (String × String) := #[]
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

inductive ToolChoice where
  | auto
  | none
  | any
  | required
  | function (name : String)
deriving BEq

structure MistralOptions extends LeanAgent.AI.SimpleStreamOptions where
  toolChoice : Option ToolChoice := none
  promptMode : Option String := none
  reasoningEffort : Option String := none

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : MistralOptions :=
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

def trimTrailingSlash (value : String) : String :=
  if value.endsWith "/" then value.dropEnd 1 |>.toString else value

def chatCompletionsUrl (baseUrl : String) : String :=
  if baseUrl.endsWith "/chat/completions" then
    baseUrl
  else if baseUrl.endsWith "/v1" then
    baseUrl ++ "/chat/completions"
  else
    trimTrailingSlash baseUrl ++ "/v1/chat/completions"

def modelRef (config : MistralConversationsConfig) (model : LeanAgent.AI.ModelRef) :
    LeanAgent.AI.ModelRef :=
  { model with baseUrl := some config.baseUrl }

def applyPayloadHook
    (options : MistralOptions)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json) : IO Lean.Json := do
  match options.onPayload with
  | none => pure payload
  | some hook =>
      match ← hook payload model with
      | some nextPayload => pure nextPayload
      | none => pure payload

def callResponseHook
    (options : MistralOptions)
    (model : LeanAgent.AI.ModelRef)
    (response : LeanAgent.Http.JsonPostResponse) : IO Unit := do
  match options.onResponse with
  | none => pure ()
  | some hook =>
      hook { status := response.status, headers := response.headers } model

def sanitize (text : String) : String :=
  LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates text

def isAsciiAlphaNum (char : Char) : Bool :=
  let code := Char.toNat char
  (Char.toNat '0' <= code && code <= Char.toNat '9') ||
    (Char.toNat 'A' <= code && code <= Char.toNat 'Z') ||
    (Char.toNat 'a' <= code && code <= Char.toNat 'z')

def onlyAsciiAlphaNum (value : String) : String :=
  String.ofList (value.toList.filter isAsciiAlphaNum)

def takeString (n : Nat) (value : String) : String :=
  String.ofList (value.toList.take n)

def deriveMistralToolCallId (id : String) (attempt : Nat := 0) : String :=
  let normalized := onlyAsciiAlphaNum id
  if attempt == 0 && normalized.length == mistralToolCallIdLength then
    normalized
  else
    let seedBase := if normalized.isEmpty then id else normalized
    let seed := if attempt == 0 then seedBase else seedBase ++ ":" ++ toString attempt
    takeString mistralToolCallIdLength
      (onlyAsciiAlphaNum (LeanAgent.AI.Util.Hash.shortHash seed))

def normalizeToolCallId (id : String) : String :=
  deriveMistralToolCallId id 0

def textChunk (text : String) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "text")
    , ("text", LeanAgent.Json.str (sanitize text))
    ]

def imageChunk (image : LeanAgent.AI.ImageContent) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "image_url")
    , ("image_url", LeanAgent.Json.str s!"data:{image.mimeType};base64,{image.data}")
    ]

def thinkingChunk (thinking : String) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "thinking")
    , ("thinking",
        LeanAgent.Json.arr
          #[LeanAgent.Json.obj
              [ ("type", LeanAgent.Json.str "text")
              , ("text", LeanAgent.Json.str (sanitize thinking))
              ]])
    ]

def contentSupportsImages (input : Array String) : Bool :=
  input.contains "image"

def userContentChunk? (supportsImages : Bool) : LeanAgent.AI.ContentBlock → Option Lean.Json
  | .text content =>
      if content.text.trimAscii.toString.isEmpty then none else some (textChunk content.text)
  | .image image =>
      if supportsImages then some (imageChunk image) else none
  | .thinking content =>
      if content.thinking.trimAscii.toString.isEmpty then none else some (textChunk content.thinking)
  | .toolCall _ => none

def userContentJson (supportsImages : Bool) (content : Array LeanAgent.AI.ContentBlock) :
    Option Lean.Json :=
  let chunks := content.filterMap (userContentChunk? supportsImages)
  if chunks.isEmpty then
    let hadImages := content.any fun block => match block with | .image _ => true | _ => false
    if hadImages && !supportsImages then
      some (LeanAgent.Json.str "(image omitted: model does not support images)")
    else
      none
  else
    some (LeanAgent.Json.arr chunks)

def assistantContentAndToolCalls
    (content : Array LeanAgent.AI.ContentBlock) : Array Lean.Json × Array Lean.Json :=
  Id.run do
    let mut contentParts := #[]
    let mut toolCalls := #[]
    for block in content do
      match block with
      | .text text =>
          if !text.text.trimAscii.toString.isEmpty then
            contentParts := contentParts.push (textChunk text.text)
      | .thinking thinking =>
          if !thinking.thinking.trimAscii.toString.isEmpty then
            contentParts := contentParts.push (thinkingChunk thinking.thinking)
      | .toolCall call =>
          toolCalls := toolCalls.push
            (LeanAgent.Json.obj
              [ ("id", LeanAgent.Json.str (normalizeToolCallId call.id))
              , ("type", LeanAgent.Json.str "function")
              , ("function",
                  LeanAgent.Json.obj
                    [ ("name", LeanAgent.Json.str call.name)
                    , ("arguments", LeanAgent.Json.str call.arguments.compress)
                    ])
              ])
      | .image _ => pure ()
    pure (contentParts, toolCalls)

def toolResultText
    (text : String)
    (hasImages supportsImages isError : Bool) : String :=
  let trimmed := text.trimAscii.toString
  let errorPrefix := if isError then "[tool error] " else ""
  if !trimmed.isEmpty then
    let suffix :=
      if hasImages && !supportsImages then
        "\n[tool image omitted: model does not support images]"
      else
        ""
    errorPrefix ++ trimmed ++ suffix
  else if hasImages then
    if supportsImages then
      if isError then "[tool error] (see attached image)" else "(see attached image)"
    else
      if isError then
        "[tool error] (image omitted: model does not support images)"
      else
        "(image omitted: model does not support images)"
  else if isError then
    "[tool error] (no tool output)"
  else
    "(no tool output)"

def toolResultContent
    (supportsImages : Bool)
    (message : LeanAgent.AI.ToolResultMessage) : Array Lean.Json :=
  Id.run do
    let text := LeanAgent.AI.contentPlainText message.content
    let hasImages := message.content.any fun block => match block with | .image _ => true | _ => false
    let mut content := #[textChunk (toolResultText text hasImages supportsImages message.isError)]
    if supportsImages then
      for block in message.content do
        match block with
        | .image image => content := content.push (imageChunk image)
        | _ => pure ()
    pure content

def messageToJson? (input : Array String) : LeanAgent.AI.Message → Option Lean.Json
  | .user message =>
      match userContentJson (contentSupportsImages input) message.content with
      | some content =>
          some (LeanAgent.Json.obj
            [ ("role", LeanAgent.Json.str "user")
            , ("content", content)
            ])
      | none => none
  | .assistant message =>
      let (contentParts, toolCalls) := assistantContentAndToolCalls message.content
      if contentParts.isEmpty && toolCalls.isEmpty then
        none
      else
        let fields :=
          [ ("role", LeanAgent.Json.str "assistant") ] ++
          (if contentParts.isEmpty then [] else [("content", LeanAgent.Json.arr contentParts)]) ++
          (if toolCalls.isEmpty then [] else [("tool_calls", LeanAgent.Json.arr toolCalls)])
        some (LeanAgent.Json.obj fields)
  | .toolResult message =>
      some (LeanAgent.Json.obj
        [ ("role", LeanAgent.Json.str "tool")
        , ("tool_call_id", LeanAgent.Json.str (normalizeToolCallId message.toolCallId))
        , ("name", LeanAgent.Json.str message.toolName)
        , ("content", LeanAgent.Json.arr (toolResultContent (contentSupportsImages input) message))
        ])

def messagesToJson (input : Array String) (context : LeanAgent.AI.Context) : Array Lean.Json :=
  let converted := context.messages.filterMap (messageToJson? input)
  match context.systemPrompt with
  | none => converted
  | some prompt =>
      if prompt.trimAscii.toString.isEmpty then
        converted
      else
        #[LeanAgent.Json.obj
            [ ("role", LeanAgent.Json.str "system")
            , ("content", LeanAgent.Json.str (sanitize prompt))
            ]] ++ converted

def toolToJson (tool : LeanAgent.AI.Tool) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "function")
    , ("function",
        LeanAgent.Json.obj
          [ ("name", LeanAgent.Json.str tool.name)
          , ("description", LeanAgent.Json.str tool.description)
          , ("parameters", tool.parameters)
          , ("strict", LeanAgent.Json.bool false)
          ])
    ]

def ToolChoice.toJson : ToolChoice → Lean.Json
  | .auto => LeanAgent.Json.str "auto"
  | .none => LeanAgent.Json.str "none"
  | .any => LeanAgent.Json.str "any"
  | .required => LeanAgent.Json.str "required"
  | .function name =>
      LeanAgent.Json.obj
        [ ("type", LeanAgent.Json.str "function")
        , ("function", LeanAgent.Json.obj [("name", LeanAgent.Json.str name)])
        ]

def usesPromptCaching (options : MistralOptions) : Option String :=
  match options.cacheRetention, options.sessionId with
  | some .none, _ => none
  | _, some sessionId =>
      if sessionId.trimAscii.toString.isEmpty then none else some sessionId
  | _, none => none

def requestToJsonWithOptions
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (context : LeanAgent.AI.Context)
    (options : MistralOptions := {})
    (stream : Bool := true) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str model.id)
     , ("stream", LeanAgent.Json.bool stream)
     , ("messages", LeanAgent.Json.arr (messagesToJson input context))
     ] ++
      (if context.tools.isEmpty then [] else [("tools", LeanAgent.Json.arr (context.tools.map toolToJson))]) ++
      (match options.temperature with
       | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
       | none => []) ++
      LeanAgent.AI.optNatField "max_tokens" options.maxTokens ++
      (match options.toolChoice with
       | some choice => [("tool_choice", choice.toJson)]
       | none => []) ++
      LeanAgent.AI.optStringField "prompt_mode" options.promptMode ++
      LeanAgent.AI.optStringField "reasoning_effort" options.reasoningEffort ++
      LeanAgent.AI.optStringField "prompt_cache_key" (usesPromptCaching options))

def hasHeader (headers : Array (String × String)) (name : String) : Bool :=
  headers.any fun (header, _) => LeanAgent.AI.Util.Headers.nameEq header name

def requestHeaders
    (config : MistralConversationsConfig)
    (options : MistralOptions) : Array (String × String) :=
  let authHeaders :=
    if config.apiKey.trimAscii.toString.isEmpty then
      #[]
    else
      #[("Authorization", "Bearer " ++ config.apiKey)]
  let headers := LeanAgent.AI.Util.Headers.merge
    (config.headers ++ authHeaders ++ #[("accept", "application/json")])
    (LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers)
  match usesPromptCaching options with
  | some sessionId =>
      if hasHeader headers "x-affinity" then headers else headers.push ("x-affinity", sessionId)
  | none => headers

def runHttpJson
    (config : MistralConversationsConfig)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json)
    (options : MistralOptions := {}) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := chatCompletionsUrl config.baseUrl
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

def optionalStringField (json : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? json key with
  | some (Lean.Json.str value) => some value
  | _ => none

def optionalStringAny (json : Lean.Json) (keys : List String) : Option String :=
  keys.findSome? (optionalStringField json)

def optionalObjectField (json : Lean.Json) (key : String) : Option Lean.Json :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getObj? with
      | .ok _ => some value
      | .error _ => none
  | none => none

def optionalObjectAny (json : Lean.Json) (keys : List String) : Option Lean.Json :=
  keys.findSome? (optionalObjectField json)

def optionalArrayField (json : Lean.Json) (key : String) : Option (Array Lean.Json) :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getArr? with
      | .ok arr => some arr
      | .error _ => none
  | none => none

def optionalArrayAny (json : Lean.Json) (keys : List String) : Option (Array Lean.Json) :=
  keys.findSome? (optionalArrayField json)

def natFieldD (json : Lean.Json) (key : String) (default : Nat := 0) : Nat :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getNat? with
      | .ok number => number
      | .error _ => default
  | none => default

def natAnyD (json : Lean.Json) (keys : List String) (default : Nat := 0) : Nat :=
  keys.findSome? (fun key =>
    match LeanAgent.Json.optVal? json key with
    | some value =>
        match value.getNat? with
        | .ok number => some number
        | .error _ => none
    | none => none) |>.getD default

def cachedPromptTokens (usage : Lean.Json) (promptTokens : Nat) : Nat :=
  let fromDetails :=
    match optionalObjectAny usage
        ["promptTokensDetails", "prompt_tokens_details", "promptTokenDetails", "prompt_token_details"] with
    | some details => natAnyD details ["cachedTokens", "cached_tokens"] 0
    | none => 0
  let cached :=
    if fromDetails > 0 then
      fromDetails
    else
      natAnyD usage ["numCachedTokens", "num_cached_tokens"] 0
  Nat.min promptTokens cached

def parseUsage (usage : Lean.Json) : LeanAgent.AI.Usage :=
  let promptTokens := natAnyD usage ["promptTokens", "prompt_tokens"] 0
  let cached := cachedPromptTokens usage promptTokens
  let input := promptTokens - cached
  let output := natAnyD usage ["completionTokens", "completion_tokens"] 0
  { input := input
    output := output
    cacheRead := cached
    cacheWrite := 0
    totalTokens := natAnyD usage ["totalTokens", "total_tokens"] (input + output + cached)
  }

def parseUsage? (json : Lean.Json) : Option LeanAgent.AI.Usage :=
  match LeanAgent.Json.optVal? json "usage" with
  | some usage => some (parseUsage usage)
  | none => none

def firstChoice? (json : Lean.Json) : Option Lean.Json :=
  match optionalArrayField json "choices" with
  | some choices => choices[0]?
  | none => none

def stopReasonFromMistral (reason : Option String) (hasToolCalls : Bool) :
    LeanAgent.AI.StopReason :=
  match reason with
  | some "stop" => .stop
  | some "length" => .length
  | some "model_length" => .length
  | some "tool_calls" => .toolUse
  | some "error" => .error
  | _ => if hasToolCalls then .toolUse else .stop

def textFromContentItem (item : Lean.Json) : Option String :=
  match optionalStringField item "type" with
  | some "text" => optionalStringField item "text"
  | some "thinking" =>
      match LeanAgent.Json.optVal? item "thinking" with
      | some (Lean.Json.str value) => some value
      | some value =>
          match value.getArr? with
          | .ok parts =>
              let text := String.intercalate "" (parts.toList.filterMap (fun part => optionalStringField part "text"))
              if text.isEmpty then none else some text
          | .error _ => none
      | none => none
  | _ => none

def contentToBlocks (content : Lean.Json) : Array LeanAgent.AI.ContentBlock :=
  match content with
  | Lean.Json.str value =>
      if value.isEmpty then #[] else #[LeanAgent.AI.ContentBlock.text { text := sanitize value }]
  | _ =>
      match content.getArr? with
      | .ok items =>
          items.filterMap fun item =>
            match optionalStringField item "type" with
            | some "thinking" =>
                (textFromContentItem item).map fun text =>
                  LeanAgent.AI.ContentBlock.thinking { thinking := sanitize text }
            | some "text" =>
                (optionalStringField item "text").map fun text =>
                  LeanAgent.AI.ContentBlock.text { text := sanitize text }
            | _ => none
      | .error _ => #[]

def parseToolArguments (raw : String) : Lean.Json :=
  LeanAgent.AI.Util.JsonParse.parseStreamingJson raw

def jsonAsArgumentsString (json : Lean.Json) : String :=
  match json with
  | Lean.Json.str value => value
  | other => other.compress

def parseToolCall (toolCall : Lean.Json) : Option LeanAgent.AI.ToolCall :=
  let fn := optionalObjectField toolCall "function"
  let name := fn.bind (fun value => optionalStringField value "name")
  match name with
  | none => none
  | some name =>
      let id :=
        match optionalStringField toolCall "id" with
        | some value => if value == "null" || value.isEmpty then deriveMistralToolCallId "toolcall:0" 0 else value
        | none => deriveMistralToolCallId s!"toolcall:{natFieldD toolCall "index" 0}" 0
      let args :=
        match fn.bind (fun value => LeanAgent.Json.optVal? value "arguments") with
        | some rawArgs => parseToolArguments (jsonAsArgumentsString rawArgs)
        | none => LeanAgent.Json.obj []
      some { id := id, name := name, arguments := args }

def parseToolCalls (message : Lean.Json) : Array LeanAgent.AI.ToolCall :=
  match optionalArrayAny message ["tool_calls", "toolCalls"] with
  | some calls => calls.filterMap parseToolCall
  | none => #[]

def parseChatCompletion
    (api provider model : String)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantMessage := do
  let json ← Lean.Json.parse raw
  if (LeanAgent.Json.optVal? json "error").isSome then
    throw (LeanAgent.AI.Util.Diagnostics.providerParseErrorMessage json.compress)
  let choice ←
    match firstChoice? json with
    | some choice => pure choice
    | none => throw "Mistral response contained no choices"
  let message ← choice.getObjVal? "message"
  let finishReason := optionalStringAny choice ["finish_reason", "finishReason"]
  let content :=
    match LeanAgent.Json.optVal? message "content" with
    | some content => contentToBlocks content
    | none => #[]
  let toolCalls := parseToolCalls message
  pure
    { content := content ++ toolCalls.map (fun call => LeanAgent.AI.ContentBlock.toolCall call)
      api := api
      provider := provider
      model := model
      responseId := optionalStringField json "id"
      responseModel :=
        match optionalStringField json "model" with
        | some responseModel => if responseModel == model then none else some responseModel
        | none => none
      usage := (parseUsage? json).getD LeanAgent.AI.Usage.empty
      stopReason := stopReasonFromMistral finishReason (!toolCalls.isEmpty)
      errorMessage := if finishReason == some "error" then some "Mistral returned an error finish reason" else none
      timestamp := timestamp
    }

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
deriving BEq

structure StreamingState where
  text : String := ""
  thinking : String := ""
  toolStates : Array StreamingToolState := #[]
  order : Array StreamBlockKey := #[]
  responseId : Option String := none
  responseModel : Option String := none
  usage : LeanAgent.AI.Usage := LeanAgent.AI.Usage.empty
  finishReason : Option String := none
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

def ensureBlock (state : StreamingState) (key : StreamBlockKey) :
    StreamingState × Nat × Bool :=
  match indexOfBlock? state.order key with
  | some index => (state, index, false)
  | none =>
      let nextIndex := state.order.size
      ({ state with order := state.order.push key }, nextIndex, true)

def findToolState? (states : Array StreamingToolState) (streamIndex : Nat) :
    Option StreamingToolState :=
  states.find? fun state => state.streamIndex == streamIndex

def upsertToolState (states : Array StreamingToolState) (next : StreamingToolState) :
    Array StreamingToolState :=
  if states.any fun state => state.streamIndex == next.streamIndex then
    states.map fun state => if state.streamIndex == next.streamIndex then next else state
  else
    states.push next

def contentFromState (state : StreamingState) : Array LeanAgent.AI.ContentBlock :=
  state.order.filterMap fun key =>
    match key with
    | .text => some (LeanAgent.AI.ContentBlock.text { text := state.text })
    | .thinking => some (LeanAgent.AI.ContentBlock.thinking { thinking := state.thinking })
    | .tool streamIndex =>
        (findToolState? state.toolStates streamIndex).map fun toolState =>
          LeanAgent.AI.ContentBlock.toolCall
            { id := toolState.id
              name := toolState.name
              arguments := parseToolArguments toolState.partialArguments
            }

def messageFromStreamingState
    (api provider model : String)
    (timestamp : Nat)
    (state : StreamingState) : LeanAgent.AI.AssistantMessage :=
  { content := contentFromState state
    api := api
    provider := provider
    model := model
    responseId := state.responseId
    responseModel := state.responseModel
    usage := state.usage
    stopReason := stopReasonFromMistral state.finishReason (!state.toolStates.isEmpty)
    errorMessage := if state.finishReason == some "error" then some "Mistral returned an error finish reason" else none
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

def applyTextDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (delta : String) : StreamingState × Array ParsedStreamEvent :=
  let delta := sanitize delta
  if delta.isEmpty then
    (state, events)
  else
    let (state, index, created) := ensureBlock state .text
    let events := if created then events.push (.textStart index) else events
    ({ state with text := state.text ++ delta }, events.push (.textDelta index delta))

def applyThinkingDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (delta : String) : StreamingState × Array ParsedStreamEvent :=
  let delta := sanitize delta
  if delta.isEmpty then
    (state, events)
  else
    let (state, index, created) := ensureBlock state .thinking
    let events := if created then events.push (.thinkingStart index) else events
    ({ state with thinking := state.thinking ++ delta }, events.push (.thinkingDelta index delta))

def streamIndexForToolDelta (toolDelta : Lean.Json) (fallback : Nat) : Nat :=
  natFieldD toolDelta "index" fallback

def applyToolDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (toolDelta : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let streamIndex := streamIndexForToolDelta toolDelta state.toolStates.size
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
    | some value =>
        if current.id.isEmpty then
          if value == "null" || value.isEmpty then deriveMistralToolCallId s!"toolcall:{streamIndex}" 0 else value
        else
          current.id
    | none =>
        if current.id.isEmpty then deriveMistralToolCallId s!"toolcall:{streamIndex}" 0 else current.id
  let argumentDelta :=
    match fn.bind (fun value => LeanAgent.Json.optVal? value "arguments") with
    | some raw => jsonAsArgumentsString raw
    | none => ""
  let next :=
    { current with
      id := id
      name := name
      partialArguments := current.partialArguments ++ argumentDelta
    }
  let state := { state with toolStates := upsertToolState state.toolStates next }
  let events := if created then events.push (.toolCallStart contentIndex) else events
  let events := if argumentDelta.isEmpty then events else events.push (.toolCallDelta contentIndex argumentDelta)
  (state, events)

def applyContentDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (content : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  match content with
  | Lean.Json.str value => applyTextDelta state events value
  | _ =>
      match content.getArr? with
      | .ok items =>
          Id.run do
            let mut state := state
            let mut events := events
            for item in items do
              match optionalStringField item "type" with
              | some "thinking" =>
                  match textFromContentItem item with
                  | some text =>
                      let (nextState, nextEvents) := applyThinkingDelta state events text
                      state := nextState
                      events := nextEvents
                  | none => pure ()
              | some "text" =>
                  match optionalStringField item "text" with
                  | some text =>
                      let (nextState, nextEvents) := applyTextDelta state events text
                      state := nextState
                      events := nextEvents
                  | none => pure ()
              | _ => pure ()
            pure (state, events)
      | .error _ => (state, events)

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

def applyStreamingChunk
    (model : String)
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (chunk : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let responseId := state.responseId <|> optionalStringField chunk "id"
  let responseModel :=
    match state.responseModel, optionalStringField chunk "model" with
    | some value, _ => some value
    | none, some value => if value.isEmpty || value == model then none else some value
    | none, none => none
  let usage := (parseUsage? chunk).getD state.usage
  match firstChoice? chunk with
  | none => ({ state with responseId := responseId, responseModel := responseModel, usage := usage }, events)
  | some choice =>
      let usage := (parseUsage? choice).getD usage
      let finishReason := optionalStringAny choice ["finish_reason", "finishReason"] <|> state.finishReason
      let state := { state with responseId := responseId, responseModel := responseModel, usage := usage, finishReason := finishReason }
      match optionalObjectField choice "delta" with
      | none => (state, events)
      | some delta =>
          let (state, events) :=
            match LeanAgent.Json.optVal? delta "content" with
            | some content => applyContentDelta state events content
            | none => (state, events)
          match optionalArrayAny delta ["tool_calls", "toolCalls"] with
          | some toolDeltas => applyToolDeltas state events toolDeltas
          | none => (state, events)

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

def finalParsedEvents (state : StreamingState) : Array ParsedStreamEvent :=
  Id.run do
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
              events := events.push (.toolCallEnd index
                { id := toolState.id
                  name := toolState.name
                  arguments := parseToolArguments toolState.partialArguments
                })
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
    let (nextState, nextEvents) := applyStreamingChunk model state parsedEvents chunk
    state := nextState
    parsedEvents := nextEvents
  let allParsedEvents := parsedEvents ++ finalParsedEvents state
  let message := messageFromStreamingState api provider model timestamp state
  let events :=
    #[LeanAgent.AI.AssistantMessageEvent.start message]
      ++ allParsedEvents.map (parsedEventToAssistantEvent message)
      ++ #[LeanAgent.AI.completionEvent message]
  pure { events := events, finalResult := message }

def completeWithOptions
    (config : MistralConversationsConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (context : LeanAgent.AI.Context)
    (options : MistralOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let payload ← applyPayloadHook options (modelRef config model)
    (requestToJsonWithOptions model input context options false)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config model payload options)
    options.signal
  let timestamp ← IO.monoMsNow
  match parseChatCompletion api model.provider model.id timestamp raw with
  | .ok response => pure response
  | .error err => throw (IO.userError s!"failed to parse Mistral response: {err}\n{raw}")

def completeStreamWithOptions
    (config : MistralConversationsConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (context : LeanAgent.AI.Context)
    (options : MistralOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  let payload ← applyPayloadHook options (modelRef config model)
    (requestToJsonWithOptions model input context options true)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config model payload options)
    options.signal
  let timestamp ← IO.monoMsNow
  match parseStreamingEventStream api model.provider model.id timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse Mistral streaming response: {err}\n{raw}")

end LeanAgent.AI.Api.MistralConversations
