import LeanAgent.AI.Types
import LeanAgent.AI.EventStream
import LeanAgent.AI.Util.Abort
import LeanAgent.AI.Util.JsonParse
import LeanAgent.Http
import LeanAgent.Json
import LeanAgent.Models

/-!
# Agent proxy stream (Pi `packages/agent/src/proxy.ts`)

Client-side reconstruction of assistant partials from a proxy server's SSE
`data:` lines. The proxy strips `partial` from delta events to save bandwidth;
this module rebuilds the partial and produces `AssistantMessageEvent`s.

Offline tests cover `processProxyEvent` / SSE line parsing. `streamProxyHttp`
uses progressive HTTP + incremental SSE parse (with batch fallback).
-/

namespace LeanAgent.Agent.Proxy

open LeanAgent.AI

/-- Serializable option subset the proxy server accepts (Pi `ProxySerializableStreamOptions`). -/
structure ProxySerializableStreamOptions where
  temperature : Option Float := none
  maxTokens : Option Nat := none
  sessionId : Option String := none
  transport : Option String := none
  maxRetryDelayMs : Option Nat := none

structure ProxyStreamOptions where
  authToken : String
  proxyUrl : String
  temperature : Option Float := none
  maxTokens : Option Nat := none
  sessionId : Option String := none
  transport : Option String := none
  maxRetryDelayMs : Option Nat := none
  signal : Option LeanAgent.AI.Util.Abort.AbortSignal := none

/-- Wire events from the proxy (no `partial` field). -/
inductive ProxyAssistantMessageEvent where
  | start
  | textStart (contentIndex : Nat)
  | textDelta (contentIndex : Nat) (delta : String)
  | textEnd (contentIndex : Nat) (contentSignature : Option String := none)
  | thinkingStart (contentIndex : Nat)
  | thinkingDelta (contentIndex : Nat) (delta : String)
  | thinkingEnd (contentIndex : Nat) (contentSignature : Option String := none)
  | toolCallStart (contentIndex : Nat) (id : String) (toolName : String)
  | toolCallDelta (contentIndex : Nat) (delta : String)
  | toolCallEnd (contentIndex : Nat)
  | done (reason : StopReason) (usage : Usage)
  | error (reason : StopReason) (errorMessage : Option String) (usage : Usage)

def emptyPartial
    (api provider modelId : String)
    (timestamp : Nat := 0) : AssistantMessage :=
  { content := #[]
    api := api
    provider := provider
    model := modelId
    usage := Usage.empty
    stopReason := .stop
    timestamp := timestamp
  }

def setContentAt (content : Array ContentBlock) (idx : Nat) (block : ContentBlock) :
    Array ContentBlock :=
  if h : idx < content.size then
    content.set idx block
  else if idx == content.size then
    content.push block
  else
    Id.run do
      let mut out := content
      while out.size < idx do
        out := out.push (.text { text := "" })
      pure (out.push block)

def getContent? (content : Array ContentBlock) (idx : Nat) : Option ContentBlock :=
  content[idx]?

def stopReasonFromProxy (reason : String) : StopReason :=
  match reason with
  | "stop" => .stop
  | "length" => .length
  | "toolUse" | "tool_use" => .toolUse
  | "aborted" => .aborted
  | "error" => .error
  | _ => .error

def jsonString? (json : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? json key with
  | some v =>
      match v.getStr? with
      | .ok s => some s
      | .error _ => none
  | none => none

def jsonNat? (json : Lean.Json) (key : String) : Option Nat :=
  match LeanAgent.Json.optVal? json key with
  | some v =>
      match v.getNat? with
      | .ok n => some n
      | .error _ => none
  | none => none

def usageFromJson (json : Lean.Json) : Usage :=
  { input := (jsonNat? json "input").getD 0
    output := (jsonNat? json "output").getD 0
    cacheRead := (jsonNat? json "cacheRead").getD 0
    cacheWrite := (jsonNat? json "cacheWrite").getD 0
    totalTokens := (jsonNat? json "totalTokens").getD 0
  }

def parseProxyEventJson (json : Lean.Json) : Except String ProxyAssistantMessageEvent := do
  let type ← match jsonString? json "type" with
    | some t => pure t
    | none => throw "proxy event missing type"
  let contentIndex := (jsonNat? json "contentIndex").getD 0
  match type with
  | "start" => pure .start
  | "text_start" => pure (.textStart contentIndex)
  | "text_delta" =>
      pure (.textDelta contentIndex ((jsonString? json "delta").getD ""))
  | "text_end" =>
      pure (.textEnd contentIndex (jsonString? json "contentSignature"))
  | "thinking_start" => pure (.thinkingStart contentIndex)
  | "thinking_delta" =>
      pure (.thinkingDelta contentIndex ((jsonString? json "delta").getD ""))
  | "thinking_end" =>
      pure (.thinkingEnd contentIndex (jsonString? json "contentSignature"))
  | "toolcall_start" =>
      pure (.toolCallStart contentIndex ((jsonString? json "id").getD "")
        ((jsonString? json "toolName").getD ""))
  | "toolcall_delta" =>
      pure (.toolCallDelta contentIndex ((jsonString? json "delta").getD ""))
  | "toolcall_end" => pure (.toolCallEnd contentIndex)
  | "done" =>
      let reason := stopReasonFromProxy ((jsonString? json "reason").getD "stop")
      let usage :=
        match LeanAgent.Json.optVal? json "usage" with
        | some u => usageFromJson u
        | none => Usage.empty
      pure (.done reason usage)
  | "error" =>
      let reason := stopReasonFromProxy ((jsonString? json "reason").getD "error")
      let usage :=
        match LeanAgent.Json.optVal? json "usage" with
        | some u => usageFromJson u
        | none => Usage.empty
      pure (.error reason (jsonString? json "errorMessage") usage)
  | other => throw s!"unhandled proxy event type: {other}"

/-- Pi `processProxyEvent`: update message snapshot and emit a client event. -/
def processProxyEvent
    (proxyEvent : ProxyAssistantMessageEvent)
    (msg : AssistantMessage) :
    Except String (Option AssistantMessageEvent × AssistantMessage) := do
  match proxyEvent with
  | .start =>
      pure (some (.start msg), msg)
  | .textStart idx =>
      let msg := { msg with content := setContentAt msg.content idx (.text { text := "" }) }
      pure (some (.textStart idx msg), msg)
  | .textDelta idx delta =>
      match getContent? msg.content idx with
      | some (.text c) =>
          let block := .text { c with text := c.text ++ delta }
          let msg := { msg with content := setContentAt msg.content idx block }
          pure (some (.textDelta idx delta msg), msg)
      | _ => throw "Received text_delta for non-text content"
  | .textEnd idx sig =>
      match getContent? msg.content idx with
      | some (.text c) =>
          let block := .text { c with textSignature := sig }
          let msg := { msg with content := setContentAt msg.content idx block }
          pure (some (.textEnd idx c.text msg), msg)
      | _ => throw "Received text_end for non-text content"
  | .thinkingStart idx =>
      let msg :=
        { msg with content := setContentAt msg.content idx (.thinking { thinking := "" }) }
      pure (some (.thinkingStart idx msg), msg)
  | .thinkingDelta idx delta =>
      match getContent? msg.content idx with
      | some (.thinking c) =>
          let block := .thinking { c with thinking := c.thinking ++ delta }
          let msg := { msg with content := setContentAt msg.content idx block }
          pure (some (.thinkingDelta idx delta msg), msg)
      | _ => throw "Received thinking_delta for non-thinking content"
  | .thinkingEnd idx sig =>
      match getContent? msg.content idx with
      | some (.thinking c) =>
          let block := .thinking { c with thinkingSignature := sig }
          let msg := { msg with content := setContentAt msg.content idx block }
          pure (some (.thinkingEnd idx c.thinking msg), msg)
      | _ => throw "Received thinking_end for non-thinking content"
  | .toolCallStart idx id toolName =>
      let call : LeanAgent.AI.ToolCall :=
        { id := id, name := toolName, arguments := LeanAgent.Json.obj [] }
      let msg := { msg with content := setContentAt msg.content idx (.toolCall call) }
      pure (some (.toolCallStart idx msg), msg)
  | .toolCallDelta idx delta =>
      match getContent? msg.content idx with
      | some (.toolCall call) =>
          let prevBuf := (call.thoughtSignature).getD ""
          let acc := prevBuf ++ delta
          let args := LeanAgent.AI.Util.JsonParse.parseStreamingJson? (some acc)
          let call : LeanAgent.AI.ToolCall :=
            { call with arguments := args, thoughtSignature := some acc }
          let msg := { msg with content := setContentAt msg.content idx (.toolCall call) }
          pure (some (.toolCallDelta idx delta msg), msg)
      | _ => throw "Received toolcall_delta for non-toolCall content"
  | .toolCallEnd idx =>
      match getContent? msg.content idx with
      | some (.toolCall call) =>
          let call : LeanAgent.AI.ToolCall := { call with thoughtSignature := none }
          let msg := { msg with content := setContentAt msg.content idx (.toolCall call) }
          pure (some (.toolCallEnd idx call msg), msg)
      | _ => pure (none, msg)
  | .done reason usage =>
      let msg := { msg with stopReason := reason, usage := usage }
      pure (some (.done reason msg), msg)
  | .error reason errorMessage usage =>
      let msg :=
        { msg with stopReason := reason, errorMessage := errorMessage, usage := usage }
      pure (some (.error reason msg), msg)

def foldProxyEvents
    (events : Array ProxyAssistantMessageEvent)
    (msg0 : AssistantMessage) :
    Except String (Array AssistantMessageEvent × AssistantMessage) := do
  let mut msg := msg0
  let mut out : Array AssistantMessageEvent := #[]
  for ev in events do
    let (maybe, next) ← processProxyEvent ev msg
    msg := next
    match maybe with
    | some e => out := out.push e
    | none => pure ()
  pure (out, msg)

def stripCR (line : String) : String :=
  if line.endsWith "\r" then (line.dropEnd 1).toString else line

/-- Extract complete `data:` JSON payloads from an SSE body. -/
def extractSseDataPayloads (raw : String) : Array String :=
  let normalized := if raw.endsWith "\n" then raw else raw ++ "\n"
  let lines := normalized.splitOn "\n"
  Id.run do
    let mut out : Array String := #[]
    for line0 in lines do
      let line := stripCR line0
      if line.startsWith "data: " then
        let data := (line.drop 6).trimAscii.toString
        if !data.isEmpty then
          out := out.push data
    pure out

def parseProxySseBody (raw : String) : Except String (Array ProxyAssistantMessageEvent) := do
  let lines := extractSseDataPayloads raw
  let mut events : Array ProxyAssistantMessageEvent := #[]
  for line in lines do
    match Lean.Json.parse line with
    | .error err => throw s!"proxy SSE JSON: {err}"
    | .ok json =>
        events := events.push (← parseProxyEventJson json)
  pure events

def buildProxyRequestUrl (proxyUrl : String) : String :=
  let base :=
    if proxyUrl.endsWith "/" then (proxyUrl.dropEnd 1).toString else proxyUrl
  base ++ "/api/stream"

def buildProxySerializableOptions (options : ProxyStreamOptions) : ProxySerializableStreamOptions :=
  { temperature := options.temperature
    maxTokens := options.maxTokens
    sessionId := options.sessionId
    transport := options.transport
    maxRetryDelayMs := options.maxRetryDelayMs
  }

/-- Offline-friendly: process a recorded SSE body into an event stream container. -/
def streamFromSseBody
    (api provider modelId : String)
    (sseBody : String)
    (timestamp : Nat := 0) : Except String AssistantMessageEventStream := do
  let proxyEvents ← parseProxySseBody sseBody
  let msg0 := emptyPartial api provider modelId timestamp
  let (events, msg) ← foldProxyEvents proxyEvents msg0
  pure { events := events, finalResult := msg }

def errorStream
    (api provider modelId : String)
    (reason : StopReason)
    (message : String) : AssistantMessageEventStream :=
  let msg := emptyPartial api provider modelId
  let msg := { msg with stopReason := reason, errorMessage := some message }
  { events := #[if reason == .aborted then .error .aborted msg else .error .error msg]
    finalResult := msg }

/-- Line-oriented proxy SSE feeder (Pi proxy emits one `data:` JSON object per line). -/
structure LineSseParser where
  buf : String := ""

def feedProxyLines (p : LineSseParser) (chunk : String) : LineSseParser × Array String :=
  if chunk.isEmpty then
    (p, #[])
  else
    let combined := p.buf ++ chunk
    let parts := combined.splitOn "\n"
    match parts.reverse with
    | [] => (p, #[])
    | last :: completeRev =>
        let completeLines := completeRev.reverse
        let lineBuf := if combined.endsWith "\n" then "" else last
        let payloads :=
          (completeLines.filterMap fun line0 =>
            let line := stripCR line0
            if line.startsWith "data: " then
              let data := (line.drop 6).trimAscii.toString
              if data.isEmpty then none else some data
            else
              none).toArray
        ({ buf := lineBuf }, payloads)

def finishProxyLines (p : LineSseParser) : Array String :=
  if p.buf.isEmpty then
    #[]
  else
    (feedProxyLines { buf := "" } (p.buf ++ "\n")).2

/--
Live proxy call via progressive HTTP + line-oriented SSE parse.

Applies `processProxyEvent` as each `data:` line completes mid-transfer. On
progressive parse failure, falls back to batch parse of the full body.
-/
def streamProxyHttp
    (model : LeanAgent.Models.ModelInfo)
    (_context : Context)
    (options : ProxyStreamOptions)
    (requestBody : String)
    (sseEventsSeen : Option (IO.Ref Nat) := none) : IO AssistantMessageEventStream := do
  if ← LeanAgent.AI.Util.Abort.isAborted options.signal then
    return errorStream model.api model.provider model.id .aborted "Request aborted by user"
  let url := buildProxyRequestUrl options.proxyUrl
  let msgRef ← IO.mkRef (emptyPartial model.api model.provider model.id)
  let outRef ← IO.mkRef (#[] : Array AssistantMessageEvent)
  let lineRef ← IO.mkRef ({} : LineSseParser)
  let errRef ← IO.mkRef (none : Option String)
  let countRef ← IO.mkRef (0 : Nat)
  let handlePayloads (payloads : Array String) : IO Unit := do
    if (← errRef.get).isSome then
      pure ()
    else
      for data in payloads do
        if (← errRef.get).isSome then
          pure ()
        else
          countRef.modify (· + 1)
          match Lean.Json.parse data with
          | .error err => errRef.set (some s!"proxy SSE JSON: {err}")
          | .ok json =>
              match parseProxyEventJson json with
              | .error err => errRef.set (some err)
              | .ok proxyEv =>
                  match processProxyEvent proxyEv (← msgRef.get) with
                  | .error err => errRef.set (some err)
                  | .ok (maybe, next) =>
                      msgRef.set next
                      match maybe with
                      | some e => outRef.modify (·.push e)
                      | none => pure ()
  try
    let response ← LeanAgent.Http.postJsonResponseProgressive
      { url := url
        apiKey := options.authToken
        signal := options.signal
        headers := #[("content-type", "application/json")]
      }
      requestBody
      fun chunk => do
        if (← errRef.get).isSome then
          pure ()
        else
          let (p, payloads) := feedProxyLines (← lineRef.get) chunk
          lineRef.set p
          handlePayloads payloads
    if (← errRef.get).isNone then
      handlePayloads (finishProxyLines (← lineRef.get))
    match sseEventsSeen with
    | some counter => counter.set (← countRef.get)
    | none => pure ()
    if response.status < 200 || response.status ≥ 300 then
      let errMsg :=
        match Lean.Json.parse response.body with
        | .ok json =>
            match jsonString? json "error" with
            | some e => s!"Proxy error: {e}"
            | none => s!"Proxy error: {response.status}"
        | .error _ => s!"Proxy error: {response.status}"
      return errorStream model.api model.provider model.id .error errMsg
    match ← errRef.get with
    | some _ =>
        match streamFromSseBody model.api model.provider model.id response.body with
        | .ok stream => pure stream
        | .error err => pure (errorStream model.api model.provider model.id .error err)
    | none =>
        pure { events := ← outRef.get, finalResult := ← msgRef.get }
  catch err =>
    if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
      pure (errorStream model.api model.provider model.id .aborted "Request aborted by user")
    else
      pure (errorStream model.api model.provider model.id .error err.toString)

end LeanAgent.Agent.Proxy
