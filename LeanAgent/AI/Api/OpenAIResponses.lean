import LeanAgent.AI.Api.OpenAIPromptCache
import LeanAgent.AI.Api.GitHubCopilotHeaders
import LeanAgent.AI.Api.OpenAIResponsesShared
import LeanAgent.AI.Api.SimpleOptions
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

namespace LeanAgent.AI.Api.OpenAIResponses

open LeanAgent

structure OpenAIResponsesConfig where
  apiKey : String
  baseUrl : String := "https://api.openai.com/v1"
  headers : Array (String × String) := #[]
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

structure OpenAIResponsesOptions extends LeanAgent.AI.SimpleStreamOptions where
  reasoningEffort : Option LeanAgent.AI.ThinkingLevel := none
  reasoningSummary : Option String := none
  serviceTier : Option String := none

def responsesUrl (baseUrl : String) : String :=
  if baseUrl.endsWith "/responses" then
    baseUrl
  else if baseUrl.endsWith "/" then
    baseUrl ++ "responses"
  else
    baseUrl ++ "/responses"

def cacheRetentionFromEnv? (env : Array (String × String)) : Option LeanAgent.AI.CacheRetention :=
  env.findSome? fun (name, value) =>
    if name == "PI_CACHE_RETENTION" && value == "long" then
      some .long
    else
      none

def resolveCacheRetention (options : OpenAIResponsesOptions) : LeanAgent.AI.CacheRetention :=
  match options.cacheRetention with
  | some retention => retention
  | none => (cacheRetentionFromEnv? options.env).getD .short

def reasoningEffortString : LeanAgent.AI.ThinkingLevel → String
  | .xhigh => "high"
  | level => level.toString

def resolvedMaxTokens?
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAIResponsesOptions) : Option Nat :=
  LeanAgent.AI.Api.SimpleOptions.resolvedMaxTokens? model.contextWindow model.maxTokens context options.toSimpleStreamOptions

def requestOptionFields
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAIResponsesOptions) : List (String × Lean.Json) :=
  let maxTokenFields :=
    match resolvedMaxTokens? model context options with
    | some maxTokens => [("max_output_tokens", LeanAgent.Json.nat maxTokens)]
    | none => []
  let temperatureFields :=
    match options.temperature with
    | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
    | none => []
  let serviceTierFields :=
    match options.serviceTier with
    | some tier => [("service_tier", LeanAgent.Json.str tier)]
    | none => []
  maxTokenFields ++ temperatureFields ++ serviceTierFields

def promptCacheFields (options : OpenAIResponsesOptions) : List (String × Lean.Json) :=
  let retention := resolveCacheRetention options
  if retention == .none then
    []
  else
    let keyFields :=
      match LeanAgent.AI.Api.OpenAIPromptCache.clampKey options.sessionId with
      | some key => [("prompt_cache_key", LeanAgent.Json.str key)]
      | none => []
    let retentionFields :=
      if retention == .long then
        [("prompt_cache_retention", LeanAgent.Json.str "24h")]
      else
        []
    keyFields ++ retentionFields

def reasoningFields
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (options : OpenAIResponsesOptions) : List (String × Lean.Json) :=
  if !model.reasoning then
    []
  else
    let effort? :=
      match options.reasoningEffort with
      | some effort => some effort
      | none => options.reasoning
    match effort?, options.reasoningSummary with
    | none, none =>
        [("reasoning", LeanAgent.Json.obj [("effort", LeanAgent.Json.str "none")])]
    | effort?, summary? =>
        let effort := reasoningEffortString (effort?.getD .medium)
        let summary := summary?.getD "auto"
        [ ("reasoning",
            LeanAgent.Json.obj
              [ ("effort", LeanAgent.Json.str effort)
              , ("summary", LeanAgent.Json.str summary)
              ])
        , ("include", LeanAgent.Json.arr #[LeanAgent.Json.str "reasoning.encrypted_content"])
        ]

def requestToJsonWithOptions
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAIResponsesOptions := {})
    (stream : Bool := false) : Lean.Json :=
  let input := LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesMessages model context
    (options := { syntheticTimestamp := 0 })
  let toolFields :=
    if context.tools.isEmpty then
      []
    else
      [ ("tools",
          LeanAgent.Json.arr
            (LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesTools context.tools))
      ]
  LeanAgent.Json.obj
    ([ ("model", LeanAgent.Json.str model.id)
     , ("input", LeanAgent.Json.arr input)
     , ("stream", LeanAgent.Json.bool stream)
     , ("store", LeanAgent.Json.bool false)
     ] ++ promptCacheFields options
       ++ requestOptionFields model context options
       ++ toolFields
       ++ reasoningFields model options)

def copilotDynamicHeaders
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context) : Array (String × String) :=
  if model.provider == "github-copilot" then
    let hasImages := LeanAgent.AI.Api.GitHubCopilotHeaders.hasCopilotVisionInput context.messages
    LeanAgent.AI.Api.GitHubCopilotHeaders.buildCopilotDynamicHeaders context.messages hasImages
  else
    #[]

def requestHeaders
    (config : OpenAIResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAIResponsesOptions) :
    Array (String × String) :=
  let retention := resolveCacheRetention options
  let sessionHeaders :=
    if retention == .none then
      #[]
    else
      match options.sessionId with
      | some sessionId => #[("session_id", sessionId), ("x-client-request-id", sessionId)]
      | none => #[]
  LeanAgent.AI.Util.Headers.merge
    (LeanAgent.AI.Util.Headers.merge
      (LeanAgent.AI.Util.Headers.merge config.headers (copilotDynamicHeaders model context))
      sessionHeaders)
    (LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers)

def modelRef
    (config : OpenAIResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel) : LeanAgent.AI.ModelRef :=
  { id := model.id
    api := model.api
    provider := model.provider
    baseUrl := some config.baseUrl
  }

def applyPayloadHook
    (options : OpenAIResponsesOptions)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json) : IO Lean.Json := do
  match options.onPayload with
  | none => pure payload
  | some hook =>
      match ← hook payload model with
      | some nextPayload => pure nextPayload
      | none => pure payload

def callResponseHook
    (options : OpenAIResponsesOptions)
    (model : LeanAgent.AI.ModelRef)
    (response : LeanAgent.Http.JsonPostResponse) : IO Unit := do
  match options.onResponse with
  | none => pure ()
  | some hook =>
      hook { status := response.status, headers := response.headers } model

def runHttpJson
    (config : OpenAIResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (payload : Lean.Json)
    (options : OpenAIResponsesOptions := {}) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := responsesUrl config.baseUrl
      apiKey := config.apiKey
      headers := requestHeaders config model context options
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

def jsonString? : Lean.Json → Option String
  | .str value => some value
  | _ => none

def optionalStringField (json : Lean.Json) (key : String) : Option String :=
  (LeanAgent.Json.optVal? json key).bind jsonString?

def parseUsage (rawUsage : Lean.Json) : LeanAgent.AI.Usage :=
  let inputTokens :=
    match LeanAgent.Json.optVal? rawUsage "input_tokens" with
    | some value => value.getNat?.toOption.getD 0
    | none => 0
  let outputTokens :=
    match LeanAgent.Json.optVal? rawUsage "output_tokens" with
    | some value => value.getNat?.toOption.getD 0
    | none => 0
  let totalTokens :=
    match LeanAgent.Json.optVal? rawUsage "total_tokens" with
    | some value => value.getNat?.toOption.getD (inputTokens + outputTokens)
    | none => inputTokens + outputTokens
  let cachedTokens :=
    match LeanAgent.Json.optVal? rawUsage "input_tokens_details" with
    | some details =>
        match LeanAgent.Json.optVal? details "cached_tokens" with
        | some value => value.getNat?.toOption.getD 0
        | none => 0
    | none => 0
  let reasoningTokens :=
    match LeanAgent.Json.optVal? rawUsage "output_tokens_details" with
    | some details =>
        match LeanAgent.Json.optVal? details "reasoning_tokens" with
        | some value => some (value.getNat?.toOption.getD 0)
        | none => none
    | none => none
  { input := inputTokens - cachedTokens
    output := outputTokens
    cacheRead := cachedTokens
    cacheWrite := 0
    reasoning := reasoningTokens
    totalTokens := totalTokens
  }

def parseUsage? (json : Lean.Json) : LeanAgent.AI.Usage :=
  match LeanAgent.Json.optVal? json "usage" with
  | some usage => parseUsage usage
  | none => {}

def mapStopReason (status? : Option String) : LeanAgent.AI.StopReason :=
  match status? with
  | some "completed" => .stop
  | some "incomplete" => .length
  | some "failed" => .error
  | some "cancelled" => .error
  | _ => .stop

def outputTextFromContentItem? (item : Lean.Json) : Option String :=
  match optionalStringField item "type" with
  | some "output_text" => optionalStringField item "text"
  | some "refusal" => optionalStringField item "refusal"
  | _ => none

def parseMessageText (item : Lean.Json) : String :=
  match LeanAgent.Json.optVal? item "content" with
  | some content =>
      match content.getArr? with
      | .ok parts =>
          String.intercalate "" (parts.toList.filterMap outputTextFromContentItem?)
      | .error _ => ""
  | none => ""

def parseReasoningText (item : Lean.Json) : String :=
  let textFromArray (key : String) :=
    match LeanAgent.Json.optVal? item key with
    | some value =>
        match value.getArr? with
        | .ok parts =>
            String.intercalate "\n\n"
              (parts.toList.filterMap fun part =>
                optionalStringField part "text")
        | .error _ => ""
    | none => ""
  let summary := textFromArray "summary"
  if summary.isEmpty then textFromArray "content" else summary

def parseToolArguments (raw : String) : Lean.Json :=
  match LeanAgent.AI.Util.JsonParse.parseJsonWithRepair raw with
  | .ok value => value
  | .error _ => LeanAgent.Json.obj []

def parseOutputItem (item : Lean.Json) : Array LeanAgent.AI.ContentBlock :=
  match optionalStringField item "type" with
  | some "message" =>
      let text := parseMessageText item
      if text.isEmpty then
        #[]
      else
        let signature :=
          match optionalStringField item "id" with
          | some id => some (LeanAgent.AI.Api.OpenAIResponsesShared.encodeTextSignatureV1 id)
          | none => none
        #[LeanAgent.AI.ContentBlock.text { text := text, textSignature := signature }]
  | some "function_call" =>
      let callId := optionalStringField item "call_id" |>.getD ""
      let itemId? := optionalStringField item "id"
      let id :=
        match itemId? with
        | some itemId => callId ++ "|" ++ itemId
        | none => callId
      let name := optionalStringField item "name" |>.getD ""
      let rawArgs := optionalStringField item "arguments" |>.getD "{}"
      #[LeanAgent.AI.ContentBlock.toolCall
        { id := id
          name := name
          arguments := parseToolArguments rawArgs
        }]
  | some "reasoning" =>
      let thinking := parseReasoningText item
      #[LeanAgent.AI.ContentBlock.thinking
        { thinking := thinking
          thinkingSignature := some item.compress
        }]
  | _ => #[]

def parseOutputContent (json : Lean.Json) : Array LeanAgent.AI.ContentBlock :=
  match LeanAgent.Json.optVal? json "output" with
  | some output =>
      match output.getArr? with
      | .ok items =>
          items.foldl (fun content item => content ++ parseOutputItem item) #[]
      | .error _ => #[]
  | none => #[]

def parseResponse
    (api provider model : String)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantMessage := do
  let json ← Lean.Json.parse raw
  if (LeanAgent.Json.optVal? json "error").isSome then
    throw (LeanAgent.AI.Util.Diagnostics.providerParseErrorMessage json.compress)
  let mut content := parseOutputContent json
  let mut stopReason := mapStopReason (optionalStringField json "status")
  if (content.any fun
      | .toolCall _ => true
      | _ => false) && stopReason == .stop then
    stopReason := .toolUse
  pure
    { content := content
      api := api
      provider := provider
      model := model
      responseId := optionalStringField json "id"
      usage := parseUsage? json
      stopReason := stopReason
      timestamp := timestamp
    }

inductive ResponsesSlotKind where
  | thinking
  | text
  | toolCall
deriving BEq

structure ResponsesOutputSlot where
  outputIndex : Nat
  kind : ResponsesSlotKind
  contentIndex : Nat
  text : String := ""
  thinkingSignature : Option String := none
  callId : String := ""
  itemId : Option String := none
  name : String := ""
  partialArguments : String := ""
  ended : Bool := false
deriving BEq

structure ResponsesStreamingState where
  slots : Array ResponsesOutputSlot := #[]
  order : Array Nat := #[]
  responseId : Option String := none
  usage : LeanAgent.AI.Usage := {}
  stopReason : LeanAgent.AI.StopReason := .stop
  sawTerminalResponseEvent : Bool := false
deriving BEq

inductive ParsedResponsesStreamEvent where
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

def natFieldD (json : Lean.Json) (key : String) (default : Nat := 0) : Nat :=
  match LeanAgent.Json.optVal? json key with
  | some value => value.getNat?.toOption.getD default
  | none => default

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

def slotIndex? (slots : Array ResponsesOutputSlot) (outputIndex : Nat) : Option Nat :=
  let rec loop (items : List ResponsesOutputSlot) (index : Nat) :=
    match items with
    | [] => none
    | slot :: rest => if slot.outputIndex == outputIndex then some index else loop rest (index + 1)
  loop slots.toList 0

def findSlot? (state : ResponsesStreamingState) (outputIndex : Nat) :
    Option ResponsesOutputSlot :=
  state.slots.find? fun slot => slot.outputIndex == outputIndex

def upsertSlot (state : ResponsesStreamingState) (slot : ResponsesOutputSlot) :
    ResponsesStreamingState :=
  let slots :=
    if state.slots.any fun current => current.outputIndex == slot.outputIndex then
      state.slots.map fun current =>
        if current.outputIndex == slot.outputIndex then slot else current
    else
      state.slots.push slot
  { state with slots := slots }

def toolCallId (callId : String) (itemId : Option String) : String :=
  match itemId with
  | some id => callId ++ "|" ++ id
  | none => callId

def toolCallFromSlot (slot : ResponsesOutputSlot) : LeanAgent.AI.ToolCall :=
  { id := toolCallId slot.callId slot.itemId
    name := slot.name
    arguments := parseToolArguments slot.partialArguments
  }

def contentBlockFromSlot (slot : ResponsesOutputSlot) : LeanAgent.AI.ContentBlock :=
  match slot.kind with
  | .thinking =>
      .thinking
        { thinking := slot.text
          thinkingSignature := slot.thinkingSignature
        }
  | .text =>
      .text
        { text := slot.text
          textSignature := slot.itemId.map LeanAgent.AI.Api.OpenAIResponsesShared.encodeTextSignatureV1
        }
  | .toolCall =>
      .toolCall (toolCallFromSlot slot)

def contentFromStreamingState (state : ResponsesStreamingState) :
    Array LeanAgent.AI.ContentBlock :=
  state.order.filterMap fun outputIndex =>
    (findSlot? state outputIndex).map contentBlockFromSlot

def finalStopReason (state : ResponsesStreamingState) : LeanAgent.AI.StopReason :=
  if state.stopReason == .stop && state.slots.any (fun slot => slot.kind == .toolCall) then
    .toolUse
  else
    state.stopReason

def messageFromStreamingState
    (api provider model : String)
    (timestamp : Nat)
    (state : ResponsesStreamingState) : LeanAgent.AI.AssistantMessage :=
  { content := contentFromStreamingState state
    api := api
    provider := provider
    model := model
    responseId := state.responseId
    usage := state.usage
    stopReason := finalStopReason state
    timestamp := timestamp
  }

def parsedEventToAssistantEvent
    (message : LeanAgent.AI.AssistantMessage) :
    ParsedResponsesStreamEvent → LeanAgent.AI.AssistantMessageEvent
  | .textStart index => .textStart index message
  | .textDelta index delta => .textDelta index delta message
  | .textEnd index content => .textEnd index content message
  | .thinkingStart index => .thinkingStart index message
  | .thinkingDelta index delta => .thinkingDelta index delta message
  | .thinkingEnd index content => .thinkingEnd index content message
  | .toolCallStart index => .toolCallStart index message
  | .toolCallDelta index delta => .toolCallDelta index delta message
  | .toolCallEnd index call => .toolCallEnd index call message

def slotKindFromItem? (item : Lean.Json) : Option ResponsesSlotKind :=
  match optionalStringField item "type" with
  | some "reasoning" => some .thinking
  | some "message" => some .text
  | some "function_call" => some .toolCall
  | _ => none

def createSlotFromItem
    (state : ResponsesStreamingState)
    (outputIndex : Nat)
    (item : Lean.Json) :
    ResponsesStreamingState × Option ResponsesOutputSlot × Bool :=
  match findSlot? state outputIndex with
  | some slot => (state, some slot, false)
  | none =>
      match slotKindFromItem? item with
      | none => (state, none, false)
      | some kind =>
          let slot : ResponsesOutputSlot :=
            { outputIndex := outputIndex
              kind := kind
              contentIndex := state.order.size
              callId := optionalStringField item "call_id" |>.getD ""
              itemId := optionalStringField item "id"
              name := optionalStringField item "name" |>.getD ""
              partialArguments := optionalStringField item "arguments" |>.getD ""
            }
          let state := { (upsertSlot state slot) with order := state.order.push outputIndex }
          (state, some slot, true)

def startEventForSlot (slot : ResponsesOutputSlot) : ParsedResponsesStreamEvent :=
  match slot.kind with
  | .thinking => .thinkingStart slot.contentIndex
  | .text => .textStart slot.contentIndex
  | .toolCall => .toolCallStart slot.contentIndex

def ensureSlotFromItem
    (state : ResponsesStreamingState)
    (events : Array ParsedResponsesStreamEvent)
    (outputIndex : Nat)
    (item : Lean.Json) :
    ResponsesStreamingState × Array ParsedResponsesStreamEvent × Option ResponsesOutputSlot :=
  let (state, slot?, created) := createSlotFromItem state outputIndex item
  let events :=
    match slot?, created with
    | some slot, true => events.push (startEventForSlot slot)
    | _, _ => events
  (state, events, slot?)

def updateSlot
    (state : ResponsesStreamingState)
    (slot : ResponsesOutputSlot) : ResponsesStreamingState :=
  upsertSlot state slot

def applyTextDelta
    (state : ResponsesStreamingState)
    (events : Array ParsedResponsesStreamEvent)
    (outputIndex : Nat)
    (delta : String) :
    ResponsesStreamingState × Array ParsedResponsesStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let item := LeanAgent.Json.obj [("type", LeanAgent.Json.str "message")]
    let (state, events, slot?) := ensureSlotFromItem state events outputIndex item
    match slot? with
    | some slot =>
        let slot := { slot with text := slot.text ++ delta }
        (updateSlot state slot, events.push (.textDelta slot.contentIndex delta))
    | none => (state, events)

def applyThinkingDelta
    (state : ResponsesStreamingState)
    (events : Array ParsedResponsesStreamEvent)
    (outputIndex : Nat)
    (delta : String) :
    ResponsesStreamingState × Array ParsedResponsesStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let item := LeanAgent.Json.obj [("type", LeanAgent.Json.str "reasoning")]
    let (state, events, slot?) := ensureSlotFromItem state events outputIndex item
    match slot? with
    | some slot =>
        let slot := { slot with text := slot.text ++ delta }
        (updateSlot state slot, events.push (.thinkingDelta slot.contentIndex delta))
    | none => (state, events)

def applyToolArgumentDelta
    (state : ResponsesStreamingState)
    (events : Array ParsedResponsesStreamEvent)
    (outputIndex : Nat)
    (delta : String) :
    ResponsesStreamingState × Array ParsedResponsesStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let item := LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "function_call")
      , ("call_id", LeanAgent.Json.str "")
      , ("arguments", LeanAgent.Json.str "")
      ]
    let (state, events, slot?) := ensureSlotFromItem state events outputIndex item
    match slot? with
    | some slot =>
        let slot := { slot with partialArguments := slot.partialArguments ++ delta }
        (updateSlot state slot, events.push (.toolCallDelta slot.contentIndex delta))
    | none => (state, events)

def startsWithString (value needle : String) : Bool :=
  value.startsWith needle

def dropPrefixChars (value needle : String) : String :=
  String.ofList (value.toList.drop needle.length)

def applyToolArgumentsDone
    (state : ResponsesStreamingState)
    (events : Array ParsedResponsesStreamEvent)
    (outputIndex : Nat)
    (arguments : String) :
    ResponsesStreamingState × Array ParsedResponsesStreamEvent :=
  let item := LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "function_call")
    , ("call_id", LeanAgent.Json.str "")
    , ("arguments", LeanAgent.Json.str arguments)
    ]
  let (state, events, slot?) := ensureSlotFromItem state events outputIndex item
  match slot? with
  | none => (state, events)
  | some slot =>
      let previous := slot.partialArguments
      let slot := { slot with partialArguments := arguments }
      let events :=
        if startsWithString arguments previous then
          let delta := dropPrefixChars arguments previous
          if delta.isEmpty then events else events.push (.toolCallDelta slot.contentIndex delta)
        else
          events
      (updateSlot state slot, events)

def finalizeSlotFromItem
    (state : ResponsesStreamingState)
    (events : Array ParsedResponsesStreamEvent)
    (outputIndex : Nat)
    (item : Lean.Json) :
    ResponsesStreamingState × Array ParsedResponsesStreamEvent :=
  let (state, events, slot?) := ensureSlotFromItem state events outputIndex item
  match slot? with
  | none => (state, events)
  | some slot =>
      match slot.kind with
      | .thinking =>
          let parsedText := parseReasoningText item
          let text := if parsedText.isEmpty then slot.text else parsedText
          let slot := { slot with text := text, thinkingSignature := some item.compress, ended := true }
          (updateSlot state slot, events.push (.thinkingEnd slot.contentIndex text))
      | .text =>
          let parsedText := parseMessageText item
          let text := if parsedText.isEmpty then slot.text else parsedText
          let slot :=
            { slot with
              text := text
              itemId := optionalStringField item "id" <|> slot.itemId
              ended := true
            }
          (updateSlot state slot, events.push (.textEnd slot.contentIndex text))
      | .toolCall =>
          let callId := optionalStringField item "call_id" |>.getD slot.callId
          let itemId := optionalStringField item "id" <|> slot.itemId
          let name := optionalStringField item "name" |>.getD slot.name
          let partialArguments := optionalStringField item "arguments" |>.getD slot.partialArguments
          let slot :=
            { slot with
              callId := callId
              itemId := itemId
              name := name
              partialArguments := partialArguments
              ended := true
            }
          (updateSlot state slot, events.push (.toolCallEnd slot.contentIndex (toolCallFromSlot slot)))

def finalizeOpenSlots
    (state : ResponsesStreamingState)
    (events : Array ParsedResponsesStreamEvent) :
    ResponsesStreamingState × Array ParsedResponsesStreamEvent :=
  Id.run do
    let mut state := state
    let mut events := events
    for outputIndex in state.order do
      match findSlot? state outputIndex with
      | none => pure ()
      | some slot =>
          if slot.ended then
            pure ()
          else
            let slot := { slot with ended := true }
            state := updateSlot state slot
            events :=
              match slot.kind with
              | .thinking => events.push (.thinkingEnd slot.contentIndex slot.text)
              | .text => events.push (.textEnd slot.contentIndex slot.text)
              | .toolCall => events.push (.toolCallEnd slot.contentIndex (toolCallFromSlot slot))
    pure (state, events)

def responseObject? (event : Lean.Json) : Option Lean.Json :=
  optionalObjectField event "response"

def applyTerminalResponse (state : ResponsesStreamingState) (response : Lean.Json) :
    ResponsesStreamingState :=
  { state with
    sawTerminalResponseEvent := true
    responseId := optionalStringField response "id" <|> state.responseId
    usage := parseUsage? response
    stopReason := mapStopReason (optionalStringField response "status")
  }

def providerErrorFromFailedResponse (response : Lean.Json) : String :=
  match optionalObjectField response "error" with
  | some err =>
      let code := optionalStringField err "code" |>.getD "unknown"
      let message := optionalStringField err "message" |>.getD "no message"
      code ++ ": " ++ message
  | none =>
      match optionalObjectField response "incomplete_details" with
      | some details =>
          match optionalStringField details "reason" with
          | some reason => "incomplete: " ++ reason
          | none => "Unknown error (no error details in response)"
      | none => "Unknown error (no error details in response)"

def outputIndexD (event : Lean.Json) : Nat :=
  natFieldD event "output_index" 0

def applyResponseStreamEvent
    (state : ResponsesStreamingState)
    (events : Array ParsedResponsesStreamEvent)
    (event : Lean.Json) : Except String (ResponsesStreamingState × Array ParsedResponsesStreamEvent) := do
  match optionalStringField event "type" with
  | some "response.created" =>
      let responseId :=
        match responseObject? event with
        | some response => optionalStringField response "id" <|> state.responseId
        | none => state.responseId
      pure ({ state with responseId := responseId }, events)
  | some "response.output_item.added" =>
      match optionalObjectField event "item" with
      | some item =>
          let (state, events, _) := ensureSlotFromItem state events (outputIndexD event) item
          pure (state, events)
      | none => pure (state, events)
  | some "response.reasoning_summary_text.delta" =>
      pure (applyThinkingDelta state events (outputIndexD event) (optionalStringField event "delta" |>.getD ""))
  | some "response.reasoning_summary_part.done" =>
      pure (applyThinkingDelta state events (outputIndexD event) "\n\n")
  | some "response.reasoning_text.delta" =>
      pure (applyThinkingDelta state events (outputIndexD event) (optionalStringField event "delta" |>.getD ""))
  | some "response.output_text.delta" =>
      pure (applyTextDelta state events (outputIndexD event) (optionalStringField event "delta" |>.getD ""))
  | some "response.refusal.delta" =>
      pure (applyTextDelta state events (outputIndexD event) (optionalStringField event "delta" |>.getD ""))
  | some "response.function_call_arguments.delta" =>
      pure (applyToolArgumentDelta state events (outputIndexD event) (optionalStringField event "delta" |>.getD ""))
  | some "response.function_call_arguments.done" =>
      pure (applyToolArgumentsDone state events (outputIndexD event) (optionalStringField event "arguments" |>.getD "{}"))
  | some "response.output_item.done" =>
      match optionalObjectField event "item" with
      | some item => pure (finalizeSlotFromItem state events (outputIndexD event) item)
      | none => pure (state, events)
  | some "response.completed" =>
      match responseObject? event with
      | some response => pure (applyTerminalResponse state response, events)
      | none => pure ({ state with sawTerminalResponseEvent := true }, events)
  | some "response.incomplete" =>
      match responseObject? event with
      | some response => pure (applyTerminalResponse state response, events)
      | none => pure ({ state with sawTerminalResponseEvent := true, stopReason := .length }, events)
  | some "response.failed" =>
      match responseObject? event with
      | some response => throw (providerErrorFromFailedResponse response)
      | none => throw "Unknown error (no error details in response)"
  | some "error" =>
      let code := optionalStringField event "code" |>.getD "unknown"
      let message := optionalStringField event "message" |>.getD "Unknown error"
      throw s!"Error Code {code}: {message}"
  | _ => pure (state, events)

def parseStreamingEvents (raw : String) : Except String (Array Lean.Json) := do
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

def parseStreamingEventStream
    (api provider model : String)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantMessageEventStream := do
  let chunks ← parseStreamingEvents raw
  let mut state : ResponsesStreamingState := {}
  let mut parsedEvents : Array ParsedResponsesStreamEvent := #[]
  for chunk in chunks do
    let (nextState, nextEvents) ← applyResponseStreamEvent state parsedEvents chunk
    state := nextState
    parsedEvents := nextEvents
  if !state.sawTerminalResponseEvent then
    throw "OpenAI Responses stream ended before a terminal response event"
  let (finalState, finalParsedEvents) := finalizeOpenSlots state parsedEvents
  let message := messageFromStreamingState api provider model timestamp finalState
  let events :=
    #[LeanAgent.AI.AssistantMessageEvent.start message]
      ++ finalParsedEvents.map (parsedEventToAssistantEvent message)
      ++ #[LeanAgent.AI.completionEvent message]
  pure { events := events, finalResult := message }

def completeWithOptions
    (config : OpenAIResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAIResponsesOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let ref := modelRef config model
  let payload ← applyPayloadHook options ref (requestToJsonWithOptions model context options false)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config model context payload options)
  let timestamp ← IO.monoMsNow
  match parseResponse model.api model.provider model.id timestamp raw with
  | .ok response => pure response
  | .error err => throw (IO.userError s!"failed to parse provider response: {err}\n{raw}")

def completeStreamWithOptions
    (config : OpenAIResponsesConfig)
    (model : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel)
    (context : LeanAgent.AI.Context)
    (options : OpenAIResponsesOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  let ref := modelRef config model
  let payload ← applyPayloadHook options ref (requestToJsonWithOptions model context options true)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config model context payload options)
  let timestamp ← IO.monoMsNow
  match parseStreamingEventStream model.api model.provider model.id timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse streaming provider response: {err}\n{raw}")

end LeanAgent.AI.Api.OpenAIResponses
