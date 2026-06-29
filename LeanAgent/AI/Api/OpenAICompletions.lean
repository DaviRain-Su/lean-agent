import Lean
import LeanAgent.AI.Api.OpenAIPromptCache
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.JsonParse
import LeanAgent.AI.Util.Retry
import LeanAgent.AI.Util.SSE
import LeanAgent.Core
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.OpenAICompletions

open LeanAgent

structure OpenAICompatibleConfig where
  apiKey : String
  baseUrl : String := "https://api.openai.com/v1"
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
  supportsReasoningEffort : Bool := true
  maxTokensField : String := "max_tokens"
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

def messageToJson : AgentMessage → Lean.Json
  | .user content =>
      LeanAgent.Json.obj [("role", LeanAgent.Json.str "user"), ("content", LeanAgent.Json.str content)]
  | .assistant content calls =>
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
        , ("content", LeanAgent.Json.str content)
        ]

def toolToJson (tool : AgentTool) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "function")
    , ("function",
        LeanAgent.Json.obj
          [ ("name", LeanAgent.Json.str tool.name)
          , ("description", LeanAgent.Json.str tool.description)
          , ("parameters", tool.inputSchema)
          ])
    ]

def requestToolFields
    (request : ProviderRequest)
    (options : OpenAICompletionsOptions) : List (String × Lean.Json) :=
  if !request.tools.isEmpty || hasToolHistory request.messages then
    [ ("tools", LeanAgent.Json.arr (request.tools.map toolToJson))
    , ("tool_choice", (options.toolChoice.getD .auto).toJson)
    ]
  else
    []

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

def modelRef
    (config : OpenAICompatibleConfig)
    (request : ProviderRequest)
    (api provider : String) : LeanAgent.AI.ModelRef :=
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
    (baseUrl : String := "") : Lean.Json :=
  let messages :=
    #[LeanAgent.Json.obj [("role", LeanAgent.Json.str "system"), ("content", LeanAgent.Json.str request.system)]]
      ++ request.messages.map messageToJson
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str request.model)
     , ("messages", LeanAgent.Json.arr messages)
     ] ++ requestOptionFields options
       ++ promptCacheFields baseUrl options
       ++ requestToolFields request options)

def requestToJson (request : ProviderRequest) : Lean.Json :=
  requestToJsonWithOptions request

def requestToStreamingJsonWithOptions
    (request : ProviderRequest)
    (options : OpenAICompletionsOptions := {})
    (baseUrl : String := "") : Lean.Json :=
  let messages :=
    #[LeanAgent.Json.obj [("role", LeanAgent.Json.str "system"), ("content", LeanAgent.Json.str request.system)]]
      ++ request.messages.map messageToJson
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str request.model)
     , ("messages", LeanAgent.Json.arr messages)
     , ("stream", LeanAgent.Json.bool true)
     , ("stream_options", LeanAgent.Json.obj [("include_usage", LeanAgent.Json.bool true)])
     ] ++ requestOptionFields options
       ++ promptCacheFields baseUrl options
       ++ requestToolFields request options)

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
deriving BEq

structure StreamingState where
  text : String := ""
  thinking : String := ""
  thinkingSignature : Option String := none
  toolStates : Array StreamingToolState := #[]
  order : Array StreamBlockKey := #[]
  responseId : Option String := none
  responseModel : Option String := none
  usage : Option LeanAgent.ProviderUsage := none
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

def ensureBlock (state : StreamingState) (key : StreamBlockKey) : StreamingState × Nat × Bool :=
  match indexOfBlock? state.order key with
  | some index => (state, index, false)
  | none =>
      let nextIndex := state.order.size
      ({ state with order := state.order.push key }, nextIndex, true)

def findToolState? (states : Array StreamingToolState) (streamIndex : Nat) : Option StreamingToolState :=
  states.find? fun state => state.streamIndex == streamIndex

def upsertToolState (states : Array StreamingToolState) (next : StreamingToolState) :
    Array StreamingToolState :=
  if states.any fun state => state.streamIndex == next.streamIndex then
    states.map fun state => if state.streamIndex == next.streamIndex then next else state
  else
    states.push next

def partialArgumentsJson (raw : String) : Lean.Json :=
  LeanAgent.AI.Util.JsonParse.parseStreamingJson raw

def toolCallFromStatePartial (state : StreamingToolState) : LeanAgent.AI.ToolCall :=
  { id := state.id
    name := state.name
    arguments := partialArgumentsJson state.partialArguments
  }

def toolCallFromState (state : StreamingToolState) : Except String LeanAgent.AI.ToolCall := do
  let arguments ← parseToolArguments state.partialArguments
  pure { id := state.id, name := state.name, arguments := arguments }

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
    usage := (state.usage.map LeanAgent.AI.usageFromLegacyProviderUsage).getD LeanAgent.AI.Usage.empty
    stopReason := LeanAgent.AI.stopReasonFromLegacyFinish state.finishReason (!state.toolStates.isEmpty)
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

def reasoningDelta? (delta : Lean.Json) : Option (String × String) :=
  match optionalStringField delta "reasoning_content" with
  | some value => if value.isEmpty then none else some ("reasoning_content", value)
  | none =>
      match optionalStringField delta "reasoning" with
      | some value => if value.isEmpty then none else some ("reasoning", value)
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

def toolDeltaStreamIndex (toolDelta : Lean.Json) (fallback : Nat) : Nat :=
  natFieldD toolDelta "index" fallback

def applyToolDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (toolDelta : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let streamIndex := toolDeltaStreamIndex toolDelta state.toolStates.size
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
    }
  let state := { state with toolStates := upsertToolState state.toolStates next }
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

def applyStreamingChunk
    (model : String)
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
      let state := { state with responseId := responseId, responseModel := responseModel, usage := usage, finishReason := finishReason }
      match optionalObjectField choice "delta" with
      | none => (state, events)
      | some delta =>
          let (state, events) :=
            match optionalStringField delta "content" with
            | some content => applyTextDelta state events content
            | none => (state, events)
          let (state, events) :=
            match reasoningDelta? delta with
            | some (signature, value) => applyThinkingDelta state events signature value
            | none => (state, events)
          match optionalArrayField delta "tool_calls" with
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
    let (nextState, nextEvents) := applyStreamingChunk model state parsedEvents chunk
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
  let payload ← applyPayloadHook options model (requestToJsonWithOptions request options config.baseUrl)
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
  let payload ← applyPayloadHook options model (requestToStreamingJsonWithOptions request options config.baseUrl)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config payload (requestHeaders options) options model)
    options.signal
  let timestamp ← IO.monoMsNow
  match parseStreamingEventStream api providerId request.model timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse streaming provider response: {err}\n{raw}")

def provider (config : OpenAICompatibleConfig) : LeanAgent.ModelProvider :=
  { complete := fun request => completeWithOptions config request }

end LeanAgent.AI.Api.OpenAICompletions
