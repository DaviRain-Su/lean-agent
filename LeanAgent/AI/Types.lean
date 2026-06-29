import LeanAgent.Core
import LeanAgent.Json

namespace LeanAgent.AI

abbrev Api := String
abbrev ProviderId := String
abbrev ImagesApi := String
abbrev ImagesProviderId := String

inductive ThinkingLevel where
  | minimal
  | low
  | medium
  | high
  | xhigh
deriving BEq

inductive ModelThinkingLevel where
  | off
  | level (level : ThinkingLevel)
deriving BEq

inductive CacheRetention where
  | none
  | short
  | long
deriving BEq

inductive Transport where
  | sse
  | websocket
  | websocketCached
  | auto
deriving BEq

inductive StopReason where
  | stop
  | length
  | toolUse
  | error
  | aborted
deriving BEq

inductive ImagesStopReason where
  | stop
  | error
  | aborted
deriving BEq

def ThinkingLevel.toString : ThinkingLevel → String
  | .minimal => "minimal"
  | .low => "low"
  | .medium => "medium"
  | .high => "high"
  | .xhigh => "xhigh"

def ThinkingLevel.fromString? : String → Option ThinkingLevel
  | "minimal" => some .minimal
  | "low" => some .low
  | "medium" => some .medium
  | "high" => some .high
  | "xhigh" => some .xhigh
  | _ => none

def ModelThinkingLevel.toString : ModelThinkingLevel → String
  | .off => "off"
  | .level value => value.toString

def ModelThinkingLevel.fromString? (value : String) : Option ModelThinkingLevel :=
  if value == "off" then
    some .off
  else
    ThinkingLevel.fromString? value |>.map .level

def CacheRetention.toString : CacheRetention → String
  | .none => "none"
  | .short => "short"
  | .long => "long"

def Transport.toString : Transport → String
  | .sse => "sse"
  | .websocket => "websocket"
  | .websocketCached => "websocket-cached"
  | .auto => "auto"

def StopReason.toString : StopReason → String
  | .stop => "stop"
  | .length => "length"
  | .toolUse => "toolUse"
  | .error => "error"
  | .aborted => "aborted"

def StopReason.fromString? : String → Option StopReason
  | "stop" => some .stop
  | "length" => some .length
  | "toolUse" => some .toolUse
  | "error" => some .error
  | "aborted" => some .aborted
  | _ => none

structure ThinkingBudgets where
  minimal : Option Nat := none
  low : Option Nat := none
  medium : Option Nat := none
  high : Option Nat := none
deriving BEq

structure ProviderResponse where
  status : Nat
  headers : Array (String × String) := #[]
deriving BEq

structure StreamOptions where
  temperature : Option Float := none
  maxTokens : Option Nat := none
  apiKey : Option String := none
  transport : Option Transport := none
  cacheRetention : Option CacheRetention := none
  sessionId : Option String := none
  headers : Array (String × Option String) := #[]
  timeoutMs : Option Nat := none
  websocketConnectTimeoutMs : Option Nat := none
  maxRetries : Option Nat := none
  maxRetryDelayMs : Option Nat := none
  metadata : Option Lean.Json := none
  env : Array (String × String) := #[]
deriving BEq

structure SimpleStreamOptions extends StreamOptions where
  reasoning : Option ThinkingLevel := none
  thinkingBudgets : Option ThinkingBudgets := none
deriving BEq

structure TextSignatureV1 where
  id : String
  phase : Option String := none
deriving BEq

structure TextContent where
  text : String
  textSignature : Option String := none
deriving BEq

structure ThinkingContent where
  thinking : String
  thinkingSignature : Option String := none
  redacted : Bool := false
deriving BEq

structure ImageContent where
  data : String
  mimeType : String
deriving BEq

structure ToolCall where
  id : String
  name : String
  arguments : Lean.Json
  thoughtSignature : Option String := none
deriving BEq

structure DiagnosticErrorInfo where
  name : Option String := none
  message : String
  stack : Option String := none
  code : Option Lean.Json := none
deriving BEq

structure AssistantMessageDiagnostic where
  type : String
  timestamp : Nat
  error : Option DiagnosticErrorInfo := none
  details : Option Lean.Json := none
deriving BEq

inductive ContentBlock where
  | text (content : TextContent)
  | thinking (content : ThinkingContent)
  | image (content : ImageContent)
  | toolCall (call : ToolCall)
deriving BEq

structure UsageCost where
  input : Float := 0.0
  output : Float := 0.0
  cacheRead : Float := 0.0
  cacheWrite : Float := 0.0
  total : Float := 0.0
deriving Repr, BEq

structure Usage where
  input : Nat := 0
  output : Nat := 0
  cacheRead : Nat := 0
  cacheWrite : Nat := 0
  cacheWrite1h : Option Nat := none
  reasoning : Option Nat := none
  totalTokens : Nat := 0
  cost : UsageCost := {}
deriving BEq

def Usage.empty : Usage := {}

structure UserMessage where
  content : Array ContentBlock
  timestamp : Nat
deriving BEq

structure AssistantMessage where
  content : Array ContentBlock
  api : Api
  provider : ProviderId
  model : String
  responseModel : Option String := none
  responseId : Option String := none
  usage : Usage := Usage.empty
  stopReason : StopReason := .stop
  errorMessage : Option String := none
  diagnostics : Array AssistantMessageDiagnostic := #[]
  timestamp : Nat
deriving BEq

structure ToolResultMessage where
  toolCallId : String
  toolName : String
  content : Array ContentBlock
  details : Option Lean.Json := none
  isError : Bool
  timestamp : Nat
deriving BEq

inductive Message where
  | user (message : UserMessage)
  | assistant (message : AssistantMessage)
  | toolResult (message : ToolResultMessage)
deriving BEq

structure Tool where
  name : String
  description : String
  parameters : Lean.Json
deriving BEq

structure Context where
  systemPrompt : Option String := none
  messages : Array Message := #[]
  tools : Array Tool := #[]
deriving BEq

inductive AssistantMessageEvent where
  | start (snapshot : AssistantMessage)
  | textStart (contentIndex : Nat) (snapshot : AssistantMessage)
  | textDelta (contentIndex : Nat) (delta : String) (snapshot : AssistantMessage)
  | textEnd (contentIndex : Nat) (content : String) (snapshot : AssistantMessage)
  | thinkingStart (contentIndex : Nat) (snapshot : AssistantMessage)
  | thinkingDelta (contentIndex : Nat) (delta : String) (snapshot : AssistantMessage)
  | thinkingEnd (contentIndex : Nat) (content : String) (snapshot : AssistantMessage)
  | toolCallStart (contentIndex : Nat) (snapshot : AssistantMessage)
  | toolCallDelta (contentIndex : Nat) (delta : String) (snapshot : AssistantMessage)
  | toolCallEnd (contentIndex : Nat) (toolCall : ToolCall) (snapshot : AssistantMessage)
  | done (reason : StopReason) (message : AssistantMessage)
  | error (reason : StopReason) (message : AssistantMessage)
deriving BEq

structure ImagesContext where
  input : Array ContentBlock := #[]
deriving BEq

structure AssistantImages where
  api : ImagesApi
  provider : ImagesProviderId
  model : String
  output : Array ContentBlock
  responseId : Option String := none
  usage : Option Usage := none
  stopReason : ImagesStopReason := .stop
  errorMessage : Option String := none
  timestamp : Nat
deriving BEq

def floatJson (value : Float) : Lean.Json :=
  match Lean.JsonNumber.fromFloat? value with
  | .inr number => Lean.Json.num number
  | .inl _ => Lean.Json.null

def optStringField (key : String) : Option String → List (String × Lean.Json)
  | some value => [(key, LeanAgent.Json.str value)]
  | none => []

def optNatField (key : String) : Option Nat → List (String × Lean.Json)
  | some value => [(key, LeanAgent.Json.nat value)]
  | none => []

def optJsonField (key : String) : Option Lean.Json → List (String × Lean.Json)
  | some value => [(key, value)]
  | none => []

def optJsonArrayField (key : String) (items : Array Lean.Json) : List (String × Lean.Json) :=
  if items.isEmpty then
    []
  else
    [(key, LeanAgent.Json.arr items)]

def diagnosticErrorInfoToJson (info : DiagnosticErrorInfo) : Lean.Json :=
  LeanAgent.Json.obj
    ([("message", LeanAgent.Json.str info.message)]
      ++ optStringField "name" info.name
      ++ optStringField "stack" info.stack
      ++ optJsonField "code" info.code)

def diagnosticErrorInfoFromJson (json : Lean.Json) : Except String DiagnosticErrorInfo := do
  pure
    { name := (← LeanAgent.Json.optionalString json "name")
      message := (← (← json.getObjVal? "message").getStr?)
      stack := (← LeanAgent.Json.optionalString json "stack")
      code := LeanAgent.Json.optVal? json "code"
    }

def assistantMessageDiagnosticToJson (diagnostic : AssistantMessageDiagnostic) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str diagnostic.type)
     , ("timestamp", LeanAgent.Json.nat diagnostic.timestamp)
     ] ++ optJsonField "error" (diagnostic.error.map diagnosticErrorInfoToJson)
       ++ optJsonField "details" diagnostic.details)

def assistantMessageDiagnosticFromJson (json : Lean.Json) : Except String AssistantMessageDiagnostic := do
  let error ←
    match LeanAgent.Json.optVal? json "error" with
    | none => pure none
    | some value =>
        let parsed ← diagnosticErrorInfoFromJson value
        pure (some parsed)
  pure
    { type := (← (← json.getObjVal? "type").getStr?)
      timestamp := (← (← json.getObjVal? "timestamp").getNat?)
      error := error
      details := LeanAgent.Json.optVal? json "details"
    }

def assistantMessageDiagnosticsFromJson? (json : Lean.Json) :
    Except String (Array AssistantMessageDiagnostic) := do
  match LeanAgent.Json.optVal? json "diagnostics" with
  | none => pure #[]
  | some value => (← value.getArr?).mapM assistantMessageDiagnosticFromJson

def textContentToJson (content : TextContent) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str "text")
     , ("text", LeanAgent.Json.str content.text)
     ] ++ optStringField "textSignature" content.textSignature)

def thinkingContentToJson (content : ThinkingContent) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str "thinking")
     , ("thinking", LeanAgent.Json.str content.thinking)
     , ("redacted", LeanAgent.Json.bool content.redacted)
     ] ++ optStringField "thinkingSignature" content.thinkingSignature)

def imageContentToJson (content : ImageContent) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "image")
    , ("data", LeanAgent.Json.str content.data)
    , ("mimeType", LeanAgent.Json.str content.mimeType)
    ]

def toolCallToJson (call : ToolCall) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str "toolCall")
     , ("id", LeanAgent.Json.str call.id)
     , ("name", LeanAgent.Json.str call.name)
     , ("arguments", call.arguments)
     ] ++ optStringField "thoughtSignature" call.thoughtSignature)

def contentBlockToJson : ContentBlock → Lean.Json
  | .text content => textContentToJson content
  | .thinking content => thinkingContentToJson content
  | .image content => imageContentToJson content
  | .toolCall call => toolCallToJson call

def contentBlockFromJson (json : Lean.Json) : Except String ContentBlock := do
  let contentType ← (← json.getObjVal? "type").getStr?
  match contentType with
  | "text" =>
      pure (.text
        { text := (← (← json.getObjVal? "text").getStr?)
          textSignature := (← LeanAgent.Json.optionalString json "textSignature")
        })
  | "thinking" =>
      pure (.thinking
        { thinking := (← (← json.getObjVal? "thinking").getStr?)
          thinkingSignature := (← LeanAgent.Json.optionalString json "thinkingSignature")
          redacted := (← LeanAgent.Json.optionalBool json "redacted").getD false
        })
  | "image" =>
      pure (.image
        { data := (← (← json.getObjVal? "data").getStr?)
          mimeType := (← (← json.getObjVal? "mimeType").getStr?)
        })
  | "toolCall" =>
      pure (.toolCall
        { id := (← (← json.getObjVal? "id").getStr?)
          name := (← (← json.getObjVal? "name").getStr?)
          arguments := (← json.getObjVal? "arguments")
          thoughtSignature := (← LeanAgent.Json.optionalString json "thoughtSignature")
        })
  | other => throw s!"unknown content block type: {other}"

def contentArrayToJson (content : Array ContentBlock) : Lean.Json :=
  LeanAgent.Json.arr (content.map contentBlockToJson)

def contentArrayFromJson (json : Lean.Json) : Except String (Array ContentBlock) := do
  (← json.getArr?).mapM contentBlockFromJson

def usageCostToJson (cost : UsageCost) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("input", floatJson cost.input)
    , ("output", floatJson cost.output)
    , ("cacheRead", floatJson cost.cacheRead)
    , ("cacheWrite", floatJson cost.cacheWrite)
    , ("total", floatJson cost.total)
    ]

def requiredFloat (json : Lean.Json) (key : String) : Except String Float := do
  pure (← (← json.getObjVal? key).getNum?).toFloat

def optionalFloat (json : Lean.Json) (key : String) : Except String (Option Float) := do
  match LeanAgent.Json.optVal? json key with
  | none => pure none
  | some value =>
      let number ← value.getNum?
      pure (some number.toFloat)

def usageCostFromJson (json : Lean.Json) : Except String UsageCost := do
  pure
    { input := (← requiredFloat json "input")
      output := (← requiredFloat json "output")
      cacheRead := (← requiredFloat json "cacheRead")
      cacheWrite := (← requiredFloat json "cacheWrite")
      total := (← requiredFloat json "total")
    }

def usageToJson (usage : Usage) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("input", LeanAgent.Json.nat usage.input)
     , ("output", LeanAgent.Json.nat usage.output)
     , ("cacheRead", LeanAgent.Json.nat usage.cacheRead)
     , ("cacheWrite", LeanAgent.Json.nat usage.cacheWrite)
     , ("totalTokens", LeanAgent.Json.nat usage.totalTokens)
     , ("cost", usageCostToJson usage.cost)
     ] ++ optNatField "cacheWrite1h" usage.cacheWrite1h
       ++ optNatField "reasoning" usage.reasoning)

def usageFromJson (json : Lean.Json) : Except String Usage := do
  pure
    { input := (← (← json.getObjVal? "input").getNat?)
      output := (← (← json.getObjVal? "output").getNat?)
      cacheRead := (← (← json.getObjVal? "cacheRead").getNat?)
      cacheWrite := (← (← json.getObjVal? "cacheWrite").getNat?)
      cacheWrite1h := (← LeanAgent.Json.optionalNat json "cacheWrite1h")
      reasoning := (← LeanAgent.Json.optionalNat json "reasoning")
      totalTokens := (← (← json.getObjVal? "totalTokens").getNat?)
      cost := (← usageCostFromJson (← json.getObjVal? "cost"))
    }

def userMessageToJson (message : UserMessage) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("role", LeanAgent.Json.str "user")
    , ("content", contentArrayToJson message.content)
    , ("timestamp", LeanAgent.Json.nat message.timestamp)
    ]

def assistantMessageToJson (message : AssistantMessage) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("role", LeanAgent.Json.str "assistant")
     , ("content", contentArrayToJson message.content)
     , ("api", LeanAgent.Json.str message.api)
     , ("provider", LeanAgent.Json.str message.provider)
     , ("model", LeanAgent.Json.str message.model)
     , ("usage", usageToJson message.usage)
     , ("stopReason", LeanAgent.Json.str message.stopReason.toString)
     , ("timestamp", LeanAgent.Json.nat message.timestamp)
     ] ++ optStringField "responseModel" message.responseModel
       ++ optStringField "responseId" message.responseId
       ++ optStringField "errorMessage" message.errorMessage
       ++ optJsonArrayField "diagnostics" (message.diagnostics.map assistantMessageDiagnosticToJson))

def toolResultMessageToJson (message : ToolResultMessage) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("role", LeanAgent.Json.str "toolResult")
     , ("toolCallId", LeanAgent.Json.str message.toolCallId)
     , ("toolName", LeanAgent.Json.str message.toolName)
     , ("content", contentArrayToJson message.content)
     , ("isError", LeanAgent.Json.bool message.isError)
     , ("timestamp", LeanAgent.Json.nat message.timestamp)
     ] ++ optJsonField "details" message.details)

def messageToJson : Message → Lean.Json
  | .user message => userMessageToJson message
  | .assistant message => assistantMessageToJson message
  | .toolResult message => toolResultMessageToJson message

def messageFromJson (json : Lean.Json) : Except String Message := do
  let role ← (← json.getObjVal? "role").getStr?
  match role with
  | "user" =>
      pure (.user
        { content := (← contentArrayFromJson (← json.getObjVal? "content"))
          timestamp := (← (← json.getObjVal? "timestamp").getNat?)
        })
  | "toolResult" =>
      pure (.toolResult
        { toolCallId := (← (← json.getObjVal? "toolCallId").getStr?)
          toolName := (← (← json.getObjVal? "toolName").getStr?)
          content := (← contentArrayFromJson (← json.getObjVal? "content"))
          details := LeanAgent.Json.optVal? json "details"
          isError := (← (← json.getObjVal? "isError").getBool?)
          timestamp := (← (← json.getObjVal? "timestamp").getNat?)
        })
  | "assistant" =>
      let stopReasonValue ← (← json.getObjVal? "stopReason").getStr?
      let stopReason ←
        match StopReason.fromString? stopReasonValue with
        | some value => pure value
        | none => throw s!"unknown stopReason: {stopReasonValue}"
      pure (.assistant
        { content := (← contentArrayFromJson (← json.getObjVal? "content"))
          api := (← (← json.getObjVal? "api").getStr?)
          provider := (← (← json.getObjVal? "provider").getStr?)
          model := (← (← json.getObjVal? "model").getStr?)
          responseModel := (← LeanAgent.Json.optionalString json "responseModel")
          responseId := (← LeanAgent.Json.optionalString json "responseId")
          usage := (← usageFromJson (← json.getObjVal? "usage"))
          stopReason := stopReason
          errorMessage := (← LeanAgent.Json.optionalString json "errorMessage")
          diagnostics := (← assistantMessageDiagnosticsFromJson? json)
          timestamp := (← (← json.getObjVal? "timestamp").getNat?)
        })
  | other => throw s!"unknown message role: {other}"

def text (value : String) : ContentBlock :=
  .text { text := value }

def thinking (value : String) : ContentBlock :=
  .thinking { thinking := value }

def image (data mimeType : String) : ContentBlock :=
  .image { data := data, mimeType := mimeType }

def contentText? : ContentBlock → Option String
  | .text content => some content.text
  | .thinking content => some content.thinking
  | _ => none

def contentPlainText (content : Array ContentBlock) : String :=
  String.intercalate "\n" (content.toList.filterMap contentText?)

def contentToolCalls (content : Array ContentBlock) : Array ToolCall :=
  content.filterMap fun block =>
    match block with
    | .toolCall call => some call
    | _ => none

def fromLegacyToolCall (call : LeanAgent.ToolCall) : ToolCall :=
  { id := call.id, name := call.name, arguments := call.arguments }

def toLegacyToolCall (call : ToolCall) : LeanAgent.ToolCall :=
  { id := call.id, name := call.name, arguments := call.arguments }

def fromLegacyMessage
    (api provider model : String)
    (timestamp : Nat := 0) : LeanAgent.AgentMessage → Message
  | .user content =>
      .user { content := #[text content], timestamp := timestamp }
  | .assistant content calls =>
      let textBlocks := if content.isEmpty then #[] else #[text content]
      let toolBlocks := calls.map (fun call => ContentBlock.toolCall (fromLegacyToolCall call))
      .assistant
        { content := textBlocks ++ toolBlocks
          api := api
          provider := provider
          model := model
          stopReason := if calls.isEmpty then .stop else .toolUse
          timestamp := timestamp
        }
  | .toolResult toolCallId name content ok =>
      .toolResult
        { toolCallId := toolCallId
          toolName := name
          content := #[text content]
          isError := !ok
          timestamp := timestamp
        }

def toLegacyMessage : Message → LeanAgent.AgentMessage
  | .user message => .user (contentPlainText message.content)
  | .assistant message =>
      .assistant
        (contentPlainText message.content)
        (contentToolCalls message.content |>.map toLegacyToolCall)
  | .toolResult message =>
      .toolResult message.toolCallId message.toolName (contentPlainText message.content) (!message.isError)

end LeanAgent.AI
