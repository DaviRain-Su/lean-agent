import LeanAgent.AI.Types
import LeanAgent.Core

namespace LeanAgent.AI

def AssistantMessageEvent.final? : AssistantMessageEvent → Option AssistantMessage
  | .done _ message => some message
  | .error _ message => some message
  | _ => none

def AssistantMessageEvent.isComplete (event : AssistantMessageEvent) : Bool :=
  event.final?.isSome

def completionEvent (message : AssistantMessage) : AssistantMessageEvent :=
  match message.stopReason with
  | .error => .error .error message
  | .aborted => .error .aborted message
  | reason => .done reason message

structure AssistantMessageEventStream where
  events : Array AssistantMessageEvent
  finalResult : AssistantMessage
deriving BEq

def AssistantMessageEventStream.result (stream : AssistantMessageEventStream) : AssistantMessage :=
  stream.finalResult

def AssistantMessageEventStream.isComplete (stream : AssistantMessageEventStream) : Bool :=
  match stream.events.back? with
  | some event => event.isComplete
  | none => false

def snapshotWithContent (message : AssistantMessage) (content : Array ContentBlock) : AssistantMessage :=
  { message with content := content }

def emptySnapshot (message : AssistantMessage) : AssistantMessage :=
  snapshotWithContent message #[]

def emptyToolCall (call : ToolCall) : ToolCall :=
  { call with arguments := LeanAgent.Json.obj [] }

def textEvents
    (contentIndex : Nat)
    (content : String)
    (baseContent : Array ContentBlock)
    (message : AssistantMessage) : List AssistantMessageEvent × Array ContentBlock :=
  let startContent := baseContent.push (.text { text := "" })
  let startSnapshot := snapshotWithContent message startContent
  let endContent := baseContent.push (.text { text := content })
  let endSnapshot := snapshotWithContent message endContent
  let delta :=
    if content.isEmpty then
      []
    else
      [.textDelta contentIndex content endSnapshot]
  ([.textStart contentIndex startSnapshot] ++ delta ++ [.textEnd contentIndex content endSnapshot], endContent)

def thinkingEvents
    (contentIndex : Nat)
    (content : String)
    (baseContent : Array ContentBlock)
    (message : AssistantMessage) : List AssistantMessageEvent × Array ContentBlock :=
  let startContent := baseContent.push (.thinking { thinking := "" })
  let startSnapshot := snapshotWithContent message startContent
  let endContent := baseContent.push (.thinking { thinking := content })
  let endSnapshot := snapshotWithContent message endContent
  let delta :=
    if content.isEmpty then
      []
    else
      [.thinkingDelta contentIndex content endSnapshot]
  ([.thinkingStart contentIndex startSnapshot] ++ delta ++ [.thinkingEnd contentIndex content endSnapshot], endContent)

def toolCallEvents
    (contentIndex : Nat)
    (call : ToolCall)
    (baseContent : Array ContentBlock)
    (message : AssistantMessage) : List AssistantMessageEvent × Array ContentBlock :=
  let arguments := call.arguments.compress
  let startContent := baseContent.push (.toolCall (emptyToolCall call))
  let startSnapshot := snapshotWithContent message startContent
  let endContent := baseContent.push (.toolCall call)
  let endSnapshot := snapshotWithContent message endContent
  let delta :=
    if arguments.isEmpty then
      []
    else
      [.toolCallDelta contentIndex arguments startSnapshot]
  ([.toolCallStart contentIndex startSnapshot] ++ delta ++ [.toolCallEnd contentIndex call endSnapshot], endContent)

def blockEvents
    (contentIndex : Nat)
    (block : ContentBlock)
    (baseContent : Array ContentBlock)
    (message : AssistantMessage) : List AssistantMessageEvent × Array ContentBlock :=
  match block with
  | .text content => textEvents contentIndex content.text baseContent message
  | .thinking content => thinkingEvents contentIndex content.thinking baseContent message
  | .toolCall call => toolCallEvents contentIndex call baseContent message
  | .image imageContent => ([], baseContent.push (.image imageContent))

def contentEventsList
    (contentIndex : Nat)
    (content : List ContentBlock)
    (baseContent : Array ContentBlock)
    (message : AssistantMessage) : List AssistantMessageEvent :=
  match content with
  | [] => []
  | block :: rest =>
      let (events, nextContent) := blockEvents contentIndex block baseContent message
      events ++ contentEventsList (contentIndex + 1) rest nextContent message

def contentEvents (message : AssistantMessage) : Array AssistantMessageEvent :=
  (contentEventsList 0 message.content.toList #[] message).toArray

def fromMessage (message : AssistantMessage) : AssistantMessageEventStream :=
  let final := completionEvent message
  { events := #[.start (emptySnapshot message)] ++ contentEvents message ++ #[final]
    finalResult := message
  }

def stopReasonFromLegacyFinish (finishReason : Option String) (hasToolCalls : Bool) : StopReason :=
  match finishReason with
  | some "stop" => .stop
  | some "length" => .length
  | some "tool_calls" => .toolUse
  | some "tool_use" => .toolUse
  | some "error" => .error
  | some "aborted" => .aborted
  | _ => if hasToolCalls then .toolUse else .stop

def usageFromLegacyProviderUsage (usage : LeanAgent.ProviderUsage) : Usage :=
  { input := usage.input
    output := usage.output
    cacheRead := usage.cacheRead
    cacheWrite := usage.cacheWrite
    cacheWrite1h := usage.cacheWrite1h
    reasoning := usage.reasoning
    totalTokens := usage.totalTokens
  }

def fromLegacyProviderResponse
    (api provider model : String)
    (timestamp : Nat)
    (response : LeanAgent.ProviderResponse) : AssistantMessage :=
  let textBlocks :=
    if response.content.isEmpty then
      #[]
    else
      #[text response.content]
  let toolBlocks := response.toolCalls.map (fun call => ContentBlock.toolCall (fromLegacyToolCall call))
  { content := textBlocks ++ toolBlocks
    api := api
    provider := provider
    model := model
    usage := (response.usage.map usageFromLegacyProviderUsage).getD Usage.empty
    stopReason := stopReasonFromLegacyFinish response.finishReason (!response.toolCalls.isEmpty)
    timestamp := timestamp
  }

def streamFromLegacyProviderResponse
    (api provider model : String)
    (timestamp : Nat)
    (response : LeanAgent.ProviderResponse) : AssistantMessageEventStream :=
  fromMessage (fromLegacyProviderResponse api provider model timestamp response)

def streamLegacyProvider
    (provider : LeanAgent.ModelProvider)
    (request : LeanAgent.ProviderRequest)
    (api providerId : String) : IO AssistantMessageEventStream := do
  let response ← provider.complete request
  let timestamp ← IO.monoMsNow
  pure (streamFromLegacyProviderResponse api providerId request.model timestamp response)

def errorStream (message : AssistantMessage) : AssistantMessageEventStream :=
  { events := #[.error .error message], finalResult := message }

end LeanAgent.AI
