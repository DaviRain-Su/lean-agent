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

def textEvents (contentIndex : Nat) (content : String) (snapshot : AssistantMessage) : List AssistantMessageEvent :=
  let delta :=
    if content.isEmpty then
      []
    else
      [.textDelta contentIndex content snapshot]
  [.textStart contentIndex snapshot] ++ delta ++ [.textEnd contentIndex content snapshot]

def thinkingEvents (contentIndex : Nat) (content : String) (snapshot : AssistantMessage) : List AssistantMessageEvent :=
  let delta :=
    if content.isEmpty then
      []
    else
      [.thinkingDelta contentIndex content snapshot]
  [.thinkingStart contentIndex snapshot] ++ delta ++ [.thinkingEnd contentIndex content snapshot]

def toolCallEvents (contentIndex : Nat) (call : ToolCall) (snapshot : AssistantMessage) : List AssistantMessageEvent :=
  let arguments := call.arguments.compress
  let delta :=
    if arguments.isEmpty then
      []
    else
      [.toolCallDelta contentIndex arguments snapshot]
  [.toolCallStart contentIndex snapshot] ++ delta ++ [.toolCallEnd contentIndex call snapshot]

def blockEvents (contentIndex : Nat) (block : ContentBlock) (snapshot : AssistantMessage) : List AssistantMessageEvent :=
  match block with
  | .text content => textEvents contentIndex content.text snapshot
  | .thinking content => thinkingEvents contentIndex content.thinking snapshot
  | .toolCall call => toolCallEvents contentIndex call snapshot
  | .image _ => []

def contentEventsList (contentIndex : Nat) (content : List ContentBlock) (snapshot : AssistantMessage) :
    List AssistantMessageEvent :=
  match content with
  | [] => []
  | block :: rest => blockEvents contentIndex block snapshot ++ contentEventsList (contentIndex + 1) rest snapshot

def contentEvents (message : AssistantMessage) : Array AssistantMessageEvent :=
  (contentEventsList 0 message.content.toList message).toArray

def fromMessage (message : AssistantMessage) : AssistantMessageEventStream :=
  let final := completionEvent message
  { events := #[.start message] ++ contentEvents message ++ #[final]
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

end LeanAgent.AI
