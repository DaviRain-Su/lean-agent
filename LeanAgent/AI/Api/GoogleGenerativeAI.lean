import LeanAgent.AI.Api.GoogleShared
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.JsonParse
import LeanAgent.AI.Util.Retry
import LeanAgent.AI.Util.SSE
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.GoogleGenerativeAI

open LeanAgent

def api : String := LeanAgent.AI.Api.GoogleShared.apiGenerativeAI

structure GoogleGenerativeAIConfig where
  apiKey : String
  baseUrl : String := "https://generativelanguage.googleapis.com/v1beta"
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
deriving BEq

structure GoogleGenerativeAIOptions extends LeanAgent.AI.SimpleStreamOptions where
  toolChoice : Option ToolChoice := none
  thinkingEnabled : Option Bool := none
  thinkingBudgetTokens : Option Nat := none
  thinkingLevel : Option String := none

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : GoogleGenerativeAIOptions :=
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
  if value.endsWith "/" then
    value.dropEnd 1 |>.toString
  else
    value

def generateContentUrl (baseUrl modelId : String) : String :=
  trimTrailingSlash baseUrl ++ "/models/" ++ modelId ++ ":generateContent"

def streamGenerateContentUrl (baseUrl modelId : String) : String :=
  trimTrailingSlash baseUrl ++ "/models/" ++ modelId ++ ":streamGenerateContent?alt=sse"

def modelRef (config : GoogleGenerativeAIConfig) (model : LeanAgent.AI.ModelRef) :
    LeanAgent.AI.ModelRef :=
  { model with baseUrl := some config.baseUrl }

def applyPayloadHook
    (options : GoogleGenerativeAIOptions)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json) : IO Lean.Json := do
  match options.onPayload with
  | none => pure payload
  | some hook =>
      match ← hook payload model with
      | some nextPayload => pure nextPayload
      | none => pure payload

def callResponseHook
    (options : GoogleGenerativeAIOptions)
    (model : LeanAgent.AI.ModelRef)
    (response : LeanAgent.Http.JsonPostResponse) : IO Unit := do
  match options.onResponse with
  | none => pure ()
  | some hook =>
      hook { status := response.status, headers := response.headers } model

def systemInstructionFields (context : LeanAgent.AI.Context) : List (String × Lean.Json) :=
  match context.systemPrompt with
  | some prompt =>
      if prompt.trimAscii.toString.isEmpty then
        []
      else
        [ ("systemInstruction",
            LeanAgent.Json.obj
              [ ("parts", LeanAgent.Json.arr #[LeanAgent.AI.Api.GoogleShared.textPart prompt])
              ])
        ]
  | none => []

def ToolChoice.toString : ToolChoice → String
  | .auto => "auto"
  | .none => "none"
  | .any => "any"

def toolConfigFields
    (tools : Array LeanAgent.AI.Tool)
    (options : GoogleGenerativeAIOptions) : List (String × Lean.Json) :=
  if tools.isEmpty then
    []
  else
    match options.toolChoice with
    | none => []
    | some choice =>
        [ ("toolConfig",
            LeanAgent.Json.obj
              [ ("functionCallingConfig",
                  LeanAgent.Json.obj
                    [ ("mode",
                        LeanAgent.Json.str
                          (LeanAgent.AI.Api.GoogleShared.mapToolChoice choice.toString))
                    ])
              ])
        ]

def thinkingConfigFields
    (reasoning : Bool)
    (options : GoogleGenerativeAIOptions) : List (String × Lean.Json) :=
  if !reasoning then
    []
  else
    match options.thinkingEnabled with
    | some true =>
        let base := [("includeThoughts", LeanAgent.Json.bool true)]
        let levelFields := LeanAgent.AI.optStringField "thinkingLevel" options.thinkingLevel
        let budgetFields := LeanAgent.AI.optNatField "thinkingBudget" options.thinkingBudgetTokens
        [("thinkingConfig", LeanAgent.Json.obj (base ++ levelFields ++ budgetFields))]
    | some false =>
        match options.thinkingLevel with
        | some level => [("thinkingConfig", LeanAgent.Json.obj [("thinkingLevel", LeanAgent.Json.str level)])]
        | none => [("thinkingConfig", LeanAgent.Json.obj [("thinkingBudget", LeanAgent.Json.nat 0)])]
    | none => []

def generationConfigFields
    (reasoning : Bool)
    (options : GoogleGenerativeAIOptions) : List (String × Lean.Json) :=
  let fields :=
    (match options.temperature with
      | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
      | none => []) ++
    (match options.maxTokens with
      | some maxTokens => [("maxOutputTokens", LeanAgent.Json.nat maxTokens)]
      | none => []) ++
    thinkingConfigFields reasoning options
  if fields.isEmpty then [] else [("generationConfig", LeanAgent.Json.obj fields)]

def requestToJsonWithOptions
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : GoogleGenerativeAIOptions := {}) : Lean.Json :=
  let toolFields :=
    match LeanAgent.AI.Api.GoogleShared.convertTools context.tools with
    | some tools => [("tools", LeanAgent.Json.arr tools)]
    | none => []
  LeanAgent.Json.obj
    ([ ("contents",
        LeanAgent.Json.arr
          (LeanAgent.AI.Api.GoogleShared.convertMessages model input context))
     ] ++ systemInstructionFields context
       ++ generationConfigFields reasoning options
       ++ toolFields
       ++ toolConfigFields context.tools options)

def requestHeaders
    (config : GoogleGenerativeAIConfig)
    (options : GoogleGenerativeAIOptions) : Array (String × String) :=
  let authHeaders :=
    if config.apiKey.trimAscii.toString.isEmpty then
      #[]
    else
      #[("x-goog-api-key", config.apiKey)]
  LeanAgent.AI.Util.Headers.merge
    (config.headers ++ (authHeaders ++ #[("accept", "application/json")]))
    (LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers)

def runHttpJson
    (config : GoogleGenerativeAIConfig)
    (model : LeanAgent.AI.ModelRef)
    (url : String)
    (payload : Lean.Json)
    (options : GoogleGenerativeAIOptions := {}) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := url
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

def optionalBoolField (json : Lean.Json) (key : String) : Option Bool :=
  match LeanAgent.Json.optVal? json key with
  | some (Lean.Json.bool value) => some value
  | _ => none

def natFieldD (json : Lean.Json) (key : String) (default : Nat := 0) : Nat :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getNat? with
      | .ok number => number
      | .error _ => default
  | none => default

def objectField? (json : Lean.Json) (key : String) : Option Lean.Json :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getObj? with
      | .ok _ => some value
      | .error _ => none
  | none => none

def arrayField? (json : Lean.Json) (key : String) : Option (Array Lean.Json) :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getArr? with
      | .ok arr => some arr
      | .error _ => none
  | none => none

def parseUsage (rawUsage : Lean.Json) : LeanAgent.AI.Usage :=
  let cacheRead := natFieldD rawUsage "cachedContentTokenCount"
  let promptTokens := natFieldD rawUsage "promptTokenCount"
  let candidateTokens := natFieldD rawUsage "candidatesTokenCount"
  let thinkingTokens := natFieldD rawUsage "thoughtsTokenCount"
  let input := promptTokens - cacheRead
  let output := candidateTokens + thinkingTokens
  { input := input
    output := output
    cacheRead := cacheRead
    cacheWrite := 0
    reasoning := some thinkingTokens
    totalTokens := natFieldD rawUsage "totalTokenCount" (input + output + cacheRead)
  }

def parseUsage? (json : Lean.Json) : LeanAgent.AI.Usage :=
  match LeanAgent.Json.optVal? json "usageMetadata" with
  | some usage => parseUsage usage
  | none => LeanAgent.AI.Usage.empty

def parseFunctionArgs (raw : Lean.Json) : Lean.Json :=
  match raw.getObj? with
  | .ok _ => raw
  | .error _ => LeanAgent.Json.obj []

def parseFunctionCall (contentIndex : Nat) (part : Lean.Json) : Except String LeanAgent.AI.ToolCall := do
  let call ← part.getObjVal? "functionCall"
  let name := optionalStringField call "name" |>.getD ""
  let id := optionalStringField call "id" |>.getD s!"{name}_{contentIndex}"
  let arguments := parseFunctionArgs ((LeanAgent.Json.optVal? call "args").getD (LeanAgent.Json.obj []))
  pure
    { id := id
      name := name
      arguments := arguments
      thoughtSignature := optionalStringField part "thoughtSignature"
    }

def parsePart (contentIndex : Nat) (part : Lean.Json) : Except String (Option LeanAgent.AI.ContentBlock) := do
  match LeanAgent.Json.optVal? part "functionCall" with
  | some _ =>
      pure (some (.toolCall (← parseFunctionCall contentIndex part)))
  | none =>
      match optionalStringField part "text" with
      | none => pure none
      | some text =>
          if text.isEmpty then
            pure none
          else if LeanAgent.AI.Api.GoogleShared.isThinkingPart part then
            pure (some (.thinking { thinking := text, thinkingSignature := optionalStringField part "thoughtSignature" }))
          else
            pure (some (.text { text := text, textSignature := optionalStringField part "thoughtSignature" }))

def parseCandidateParts (candidate : Lean.Json) : Except String (Array LeanAgent.AI.ContentBlock) := do
  let content ← candidate.getObjVal? "content"
  let parts := (arrayField? content "parts").getD #[]
  let mut blocks := #[]
  let mut index := 0
  for part in parts do
    match ← parsePart index part with
    | some block =>
        blocks := blocks.push block
        index := index + 1
    | none => pure ()
  pure blocks

def firstCandidate? (json : Lean.Json) : Option Lean.Json :=
  match arrayField? json "candidates" with
  | some candidates => candidates[0]?
  | none => none

def stopReasonFromCandidate (candidate : Lean.Json) (hasToolCalls : Bool) : LeanAgent.AI.StopReason :=
  if hasToolCalls then
    .toolUse
  else
    match optionalStringField candidate "finishReason" with
    | some reason => LeanAgent.AI.Api.GoogleShared.mapStopReasonString reason
    | none => .stop

def parseResponse
    (api provider model : String)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantMessage := do
  let json ← Lean.Json.parse raw
  if (LeanAgent.Json.optVal? json "error").isSome then
    throw (LeanAgent.AI.Util.Diagnostics.providerParseErrorMessage json.compress)
  let candidate ←
    match firstCandidate? json with
    | some candidate => pure candidate
    | none => throw "Google response contained no candidates"
  let content ← parseCandidateParts candidate
  let hasToolCalls := content.any fun
    | .toolCall _ => true
    | _ => false
  let stopReason := stopReasonFromCandidate candidate hasToolCalls
  pure
    { content := content
      api := api
      provider := provider
      model := model
      responseId := optionalStringField json "responseId"
      responseModel := optionalStringField json "modelVersion" |>.filter (fun responseModel => responseModel != model)
      usage := parseUsage? json
      stopReason := stopReason
      errorMessage := if stopReason == .error then some "Google returned an error finish reason" else none
      timestamp := timestamp
    }

inductive StreamingBlockKind where
  | text
  | thinking
deriving BEq

structure CurrentBlock where
  index : Nat
  kind : StreamingBlockKind
deriving BEq

structure StreamingState where
  content : Array LeanAgent.AI.ContentBlock := #[]
  current : Option CurrentBlock := none
  responseId : Option String := none
  responseModel : Option String := none
  usage : LeanAgent.AI.Usage := LeanAgent.AI.Usage.empty
  stopReason : LeanAgent.AI.StopReason := .stop
  toolCounter : Nat := 0
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

def blockText? : LeanAgent.AI.ContentBlock → Option String
  | .text content => some content.text
  | .thinking content => some content.thinking
  | _ => none

def closeCurrentBlock
    (state : StreamingState)
    (events : Array ParsedStreamEvent) : StreamingState × Array ParsedStreamEvent :=
  match state.current with
  | none => (state, events)
  | some current =>
      match state.content[current.index]? with
      | some block =>
          let text := blockText? block |>.getD ""
          let event :=
            match current.kind with
            | .text => ParsedStreamEvent.textEnd current.index text
            | .thinking => ParsedStreamEvent.thinkingEnd current.index text
          ({ state with current := none }, events.push event)
      | none => ({ state with current := none }, events)

def updateTextBlock
    (content : Array LeanAgent.AI.ContentBlock)
    (index : Nat)
    (delta : String)
    (signature : Option String) : Array LeanAgent.AI.ContentBlock :=
  content.mapIdx fun i block =>
    if i != index then
      block
    else
      match block with
      | .text text =>
          .text
            { text := text.text ++ delta
              textSignature := LeanAgent.AI.Api.GoogleShared.retainThoughtSignature text.textSignature signature
            }
      | _ => block

def updateThinkingBlock
    (content : Array LeanAgent.AI.ContentBlock)
    (index : Nat)
    (delta : String)
    (signature : Option String) : Array LeanAgent.AI.ContentBlock :=
  content.mapIdx fun i block =>
    if i != index then
      block
    else
      match block with
      | .thinking thinking =>
          .thinking
            { thinking := thinking.thinking ++ delta
              thinkingSignature :=
                LeanAgent.AI.Api.GoogleShared.retainThoughtSignature thinking.thinkingSignature signature
            }
      | _ => block

def ensureStreamingTextBlock
    (kind : StreamingBlockKind)
    (state : StreamingState)
    (events : Array ParsedStreamEvent) : StreamingState × Array ParsedStreamEvent × Nat :=
  match state.current with
  | some current =>
      if current.kind == kind then
        (state, events, current.index)
      else
        let (state, events) := closeCurrentBlock state events
        let index := state.content.size
        let block :=
          match kind with
          | .text => LeanAgent.AI.ContentBlock.text { text := "" }
          | .thinking => LeanAgent.AI.ContentBlock.thinking { thinking := "" }
        let state := { state with content := state.content.push block, current := some { index := index, kind := kind } }
        let events :=
          match kind with
          | .text => events.push (.textStart index)
          | .thinking => events.push (.thinkingStart index)
        (state, events, index)
  | none =>
      let index := state.content.size
      let block :=
        match kind with
        | .text => LeanAgent.AI.ContentBlock.text { text := "" }
        | .thinking => LeanAgent.AI.ContentBlock.thinking { thinking := "" }
      let state := { state with content := state.content.push block, current := some { index := index, kind := kind } }
      let events :=
        match kind with
        | .text => events.push (.textStart index)
        | .thinking => events.push (.thinkingStart index)
      (state, events, index)

def applyTextPart
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (part : Lean.Json)
    (delta : String) : StreamingState × Array ParsedStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let signature := optionalStringField part "thoughtSignature"
    if LeanAgent.AI.Api.GoogleShared.isThinkingPart part then
      let (state, events, index) := ensureStreamingTextBlock .thinking state events
      let state := { state with content := updateThinkingBlock state.content index delta signature }
      (state, events.push (.thinkingDelta index delta))
    else
      let (state, events, index) := ensureStreamingTextBlock .text state events
      let state := { state with content := updateTextBlock state.content index delta signature }
      (state, events.push (.textDelta index delta))

def toolCallFromStreamingPart (state : StreamingState) (part : Lean.Json) :
    LeanAgent.AI.ToolCall :=
  let call := (LeanAgent.Json.optVal? part "functionCall").getD (LeanAgent.Json.obj [])
  let name := optionalStringField call "name" |>.getD ""
  let id := optionalStringField call "id" |>.getD s!"{name}_{state.toolCounter + 1}"
  let arguments := parseFunctionArgs ((LeanAgent.Json.optVal? call "args").getD (LeanAgent.Json.obj []))
  { id := id
    name := name
    arguments := arguments
    thoughtSignature := optionalStringField part "thoughtSignature"
  }

def applyFunctionCallPart
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (part : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let (state, events) := closeCurrentBlock state events
  let call := toolCallFromStreamingPart state part
  let index := state.content.size
  let endContent := state.content.push (.toolCall call)
  let delta := call.arguments.compress
  let events := events.push (.toolCallStart index)
  let events := if delta.isEmpty then events else events.push (.toolCallDelta index delta)
  let events := events.push (.toolCallEnd index call)
  ({ state with content := endContent, toolCounter := state.toolCounter + 1 }, events)

def applyStreamingPart
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (part : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  match LeanAgent.Json.optVal? part "functionCall" with
  | some _ => applyFunctionCallPart state events part
  | none =>
      match optionalStringField part "text" with
      | some delta => applyTextPart state events part delta
      | none => (state, events)

def applyStreamingCandidate
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (candidate : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  Id.run do
    let mut state := state
    let mut events := events
    match objectField? candidate "content" with
    | some content =>
        for part in (arrayField? content "parts").getD #[] do
          let (nextState, nextEvents) := applyStreamingPart state events part
          state := nextState
          events := nextEvents
    | none => pure ()
    match optionalStringField candidate "finishReason" with
    | some reason =>
        if state.content.any (fun | .toolCall _ => true | _ => false) then
          state := { state with stopReason := .toolUse }
        else
          state := { state with stopReason := LeanAgent.AI.Api.GoogleShared.mapStopReasonString reason }
    | none => pure ()
    pure (state, events)

def applyStreamingChunk
    (model : String)
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (chunk : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let responseId := state.responseId <|> optionalStringField chunk "responseId"
  let responseModel :=
    match state.responseModel, optionalStringField chunk "modelVersion" with
    | some value, _ => some value
    | none, some value => if value.isEmpty || value == model then none else some value
    | none, none => none
  let usage :=
    match LeanAgent.Json.optVal? chunk "usageMetadata" with
    | some usage => parseUsage usage
    | none => state.usage
  let state := { state with responseId := responseId, responseModel := responseModel, usage := usage }
  match firstCandidate? chunk with
  | some candidate => applyStreamingCandidate state events candidate
  | none => (state, events)

def parseStreamingChunks (raw : String) : Except String (Array Lean.Json) := do
  let mut chunks := #[]
  for event in LeanAgent.AI.Util.SSE.parse raw do
    let data := event.data.trimAscii.toString
    if data == "[DONE]" || data.isEmpty then
      pure ()
    else
      let json ← LeanAgent.AI.Util.JsonParse.parseJsonWithRepair data
      if (LeanAgent.Json.optVal? json "error").isSome then
        throw (LeanAgent.AI.Util.Diagnostics.providerParseErrorMessage json.compress)
      chunks := chunks.push json
  pure chunks

def messageFromStreamingState
    (api provider model : String)
    (timestamp : Nat)
    (state : StreamingState) : LeanAgent.AI.AssistantMessage :=
  { content := state.content
    api := api
    provider := provider
    model := model
    responseId := state.responseId
    responseModel := state.responseModel
    usage := state.usage
    stopReason := state.stopReason
    errorMessage :=
      if state.stopReason == .error then some "Google returned an error finish reason" else none
    timestamp := timestamp
  }

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
  let (finalState, finalParsedEvents) := closeCurrentBlock state parsedEvents
  let message := messageFromStreamingState api provider model timestamp finalState
  let events :=
    #[LeanAgent.AI.AssistantMessageEvent.start message]
      ++ finalParsedEvents.map (parsedEventToAssistantEvent message)
      ++ #[LeanAgent.AI.completionEvent message]
  pure { events := events, finalResult := message }

def completeWithOptions
    (config : GoogleGenerativeAIConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : GoogleGenerativeAIOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  LeanAgent.AI.Util.Abort.throwIfAborted options.signal
  let ref := modelRef config model
  let payload ← applyPayloadHook options ref
    (requestToJsonWithOptions ref input reasoning context options)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config ref (generateContentUrl config.baseUrl model.id) payload options)
    options.signal
  let timestamp ← IO.monoMsNow
  match parseResponse model.api model.provider model.id timestamp raw with
  | .ok message => pure message
  | .error err => throw (IO.userError s!"failed to parse Google Generative AI response: {err}\n{raw}")

def completeStreamWithOptions
    (config : GoogleGenerativeAIConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : GoogleGenerativeAIOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  LeanAgent.AI.Util.Abort.throwIfAborted options.signal
  let ref := modelRef config model
  let payload ← applyPayloadHook options ref
    (requestToJsonWithOptions ref input reasoning context options)
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpJson config ref (streamGenerateContentUrl config.baseUrl model.id) payload options)
    options.signal
  let timestamp ← IO.monoMsNow
  match parseStreamingEventStream model.api model.provider model.id timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse Google Generative AI stream: {err}\n{raw}")

end LeanAgent.AI.Api.GoogleGenerativeAI
