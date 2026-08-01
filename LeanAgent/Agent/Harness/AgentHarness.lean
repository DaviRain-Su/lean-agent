import Lean
import LeanAgent.Agent.Types
import LeanAgent.Agent.Agent
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Abort
import LeanAgent.Agent.Harness.SystemPrompt
import LeanAgent.Agent.Harness.Storage
import LeanAgent.Agent.Harness.Compaction
import LeanAgent.Agent.Harness.Session
import LeanAgent.Agent.Harness.Messages
import LeanAgent.Models

/-!
# Agent Harness (Pi `harness/agent-harness.ts` subset)

High-level façade over `Agent` with queue management, event subscribers,
stream options, resource map, pending session writes, and session tree
navigation. Mirrors the Pi `AgentHarness` class.

`AgentHarness` is a pure (immutable) value — `create` is a pure function
so existing callers don't need IO.  `AgentHarnessRef` wraps it with
`IO.Ref`-backed mutable state for subscribers, resources, and pending
writes (Pi `handlers`, `resources`, `pendingSessionWrites`).
-/

namespace LeanAgent.Agent.Harness

open LeanAgent.Agent
open LeanAgent.Agent.Harness.SystemPrompt
open LeanAgent.Agent.Harness.Storage
open LeanAgent.Agent.Harness.Session
open LeanAgent.Agent.Harness.Messages
open LeanAgent.Agent.Harness.Compaction
open LeanAgent.AI

/-- Queue snapshot for harness queue_update events (Pi subset). -/
structure QueueSnapshot where
  steering : Array AgentMessage := #[]
  followUp : Array AgentMessage := #[]
  nextTurn : Array AgentMessage := #[]
deriving Inhabited

inductive HarnessEvent where
  | agent (event : AgentEvent)
  | queueUpdate (queue : QueueSnapshot)
  | phase (name : String)

abbrev HarnessEventSink := HarnessEvent → IO Unit

instance : Inhabited HarnessEventSink :=
  ⟨fun _ => pure ()⟩

/-- Pi `AgentHarnessStreamOptions`: curated provider request options. -/
structure HarnessStreamOptions where
  transport : Option Transport := none
  timeoutMs : Option Nat := none
  maxRetries : Option Nat := none
  maxRetryDelayMs : Option Nat := none
  headers : Array (String × Option String) := #[]
  metadata : Option Lean.Json := none
  cacheRetention : Option CacheRetention := none
deriving Inhabited

/-- Pi `AgentHarnessStreamOptionsPatch`: per-request option patch. -/
structure HarnessStreamOptionsPatch where
  transport : Option Transport := none
  timeoutMs : Option Nat := none
  maxRetries : Option Nat := none
  maxRetryDelayMs : Option Nat := none
  headers : Option (Array (String × Option String)) := none
  metadata : Option (Option Lean.Json) := none
  cacheRetention : Option CacheRetention := none
deriving Inhabited

/--
Pi `cloneStreamOptions`: deep-clone stream options (copy headers/metadata).
Lean structures are immutable, so this returns a structurally-identical copy.
-/
def cloneStreamOptions (opts : HarnessStreamOptions) : HarnessStreamOptions :=
  { opts with
    headers := opts.headers.map fun (k, v) => (k, v)
  }

/--
Pi `applyStreamOptionsPatch`: merge a patch into base options.
Override fields only when the patch provides them (Pi `Object.hasOwn` check).
-/
def applyStreamOptionsPatch
    (base : HarnessStreamOptions)
    (patch : Option HarnessStreamOptionsPatch) : HarnessStreamOptions :=
  match patch with
  | none => cloneStreamOptions base
  | some p =>
    let result := cloneStreamOptions base
    let result :=
      if p.transport.isSome then { result with transport := p.transport } else result
    let result :=
      if p.timeoutMs.isSome then { result with timeoutMs := p.timeoutMs } else result
    let result :=
      if p.maxRetries.isSome then { result with maxRetries := p.maxRetries } else result
    let result :=
      if p.maxRetryDelayMs.isSome then { result with maxRetryDelayMs := p.maxRetryDelayMs } else result
    let result :=
      if p.cacheRetention.isSome then { result with cacheRetention := p.cacheRetention } else result
    let result :=
      match p.headers with
      | none => result
      | some newHeaders => { result with headers := newHeaders }
    let result :=
      match p.metadata with
      | none => result
      | some newMeta => { result with metadata := newMeta }
    result

/--
Pi `findDuplicateNames`: return names appearing more than once.
-/
def findDuplicateNames (names : Array String) : Array String :=
  let counts := names.foldl (init := (∅ : Std.HashMap String Nat))
    fun m name => m.insert name (m.getD name 0 + 1)
  counts.fold (init := #[]) fun acc name count =>
    if count > 1 then acc.push name else acc

/--
Pi `createUserMessage`: build a user message with optional image content parts.
-/
def createUserMessage (text : String) (images : Array ImageContent := #[]) : IO AgentMessage := do
  let timestamp ← IO.monoMsNow
  let mut content : Array ContentBlock := #[.text { text := text }]
  for image in images do
    content := content.push (.image image)
  pure (AgentMessage.ofMessage (.user { content := content, timestamp := timestamp }))

/--
Pi `createFailureMessage`: build an assistant message with error text for LLM display.
-/
def createFailureMessage
    (model : LeanAgent.Models.ModelInfo)
    (error : String)
    (aborted : Bool) : IO AgentMessage := do
  let timestamp ← IO.monoMsNow
  let stopReason : StopReason := if aborted then .aborted else .error
  let assistantMsg : AssistantMessage :=
    { content := #[.text { text := "" }]
      api := model.api
      provider := model.provider
      model := model.id
      stopReason := stopReason
      errorMessage := some error
      timestamp := timestamp
    }
  pure (AgentMessage.ofMessage (.assistant assistantMsg))

/-- Pi `PendingSessionWrite`: deferred session entry write descriptor. -/
inductive PendingSessionWrite where
  | message (msg : AgentMessage)
  | modelChange (provider : String) (modelId : String)
  | thinkingLevelChange (level : String)
  | label (targetId : String) (label : Option String)
  | leaf (targetId : Option String)
  | customMessage (customType : String) (content : Array ContentBlock) (display : Bool)
deriving Inhabited

/-- Pi `NavigateTreeResult`: result of navigating the session tree. -/
structure NavigateTreeResult where
  cancelled : Bool := false
  editorText : Option String := none
  branchMessages : Array AgentMessage := #[]
deriving Inhabited

/--
High-level façade over `Agent` (Pi AgentHarness subset): owns an Agent, next-turn
queue, system prompt / tools, and emits queue updates on steer/followUp/nextTurn.

This is the pure (immutable) variant — subscriber registry, resource map, and
pending writes are plain fields.  Use `AgentHarnessRef.createIO` for the
`IO.Ref`-backed mutable variant (Pi `handlers`, `resources`, `pendingSessionWrites`).
-/
structure AgentHarness where
  agent : Agent
  nextTurnQueue : Array AgentMessage := #[]
  listeners : Array (Nat × HarnessEventSink) := #[]
  skills : Array SkillInfo := #[]
  resources : Std.HashMap String Lean.Json := ∅
  pendingWrites : Array PendingSessionWrite := #[]
  streamOptions : HarnessStreamOptions := {}

namespace AgentHarness

/-- Pure constructor — no IO required (backward-compatible with existing callers). -/
def create
    (options : AgentOptions := default)
    (skills : Array SkillInfo := #[]) : AgentHarness :=
  { agent := Agent.create options
    skills := skills
  }

instance : Inhabited AgentHarness := ⟨AgentHarness.create⟩

/-- Subscribe a handler; returns updated harness + listener ID for unsubscribe. -/
def subscribe (h : AgentHarness) (listener : HarnessEventSink) : AgentHarness × Nat :=
  let id := h.listeners.size
  ({ h with listeners := h.listeners.push (id, listener) }, id)

/-- Unsubscribe a handler by listener ID. -/
def unsubscribe (h : AgentHarness) (id : Nat) : AgentHarness :=
  { h with listeners := h.listeners.filter (fun (i, _) => i != id) }

/-- Emit an event to all registered listeners. -/
def emit (h : AgentHarness) (event : HarnessEvent) : IO Unit := do
  for (_, listener) in h.listeners do
    listener event


def queueSnapshot (h : AgentHarness) : QueueSnapshot :=
  { steering := h.agent.steeringQueue.messages
    followUp := h.agent.followUpQueue.messages
    nextTurn := h.nextTurnQueue
  }

def emitQueue (h : AgentHarness) : IO Unit :=
  h.emit (.queueUpdate h.queueSnapshot)

def withAgent (h : AgentHarness) (agent : Agent) : AgentHarness :=
  { h with agent := agent }

def steer (h : AgentHarness) (message : AgentMessage) : IO AgentHarness := do
  let h := h.withAgent (h.agent.steer message)
  h.emitQueue
  pure h

def followUp (h : AgentHarness) (message : AgentMessage) : IO AgentHarness := do
  let h := h.withAgent (h.agent.followUp message)
  h.emitQueue
  pure h

/-- Queue a message for the next user-initiated prompt (Pi nextTurn). -/
def nextTurn (h : AgentHarness) (message : AgentMessage) : IO AgentHarness := do
  let h := { h with nextTurnQueue := h.nextTurnQueue.push message }
  h.emitQueue
  pure h

def clearQueues (h : AgentHarness) : IO AgentHarness := do
  let agent := h.agent.clearAllQueues
  let h := { h with agent := agent, nextTurnQueue := #[] }
  h.emitQueue
  pure h

/-- Abort active agent run and clear steer/follow-up queues. -/
def abort (h : AgentHarness) : IO AgentHarness := do
  h.agent.abort
  let agent := h.agent.clearAllQueues
  let h := { h with agent := agent }
  h.emitQueue
  pure h

def waitForIdle (h : AgentHarness) : IO Unit :=
  h.agent.waitForIdle

/--
Prompt the underlying agent, prepending any nextTurn messages, applying skills
into system prompt when non-empty.
-/
def prompt (h : AgentHarness) (text : String) : IO AgentHarness := do
  let systemPrompt := buildSystemPrompt h.agent.state.systemPrompt h.skills
  let pending := h.nextTurnQueue
  let h := { h with nextTurnQueue := #[] }
  h.emitQueue
  let agent :=
    { h.agent with state := { h.agent.state with systemPrompt := systemPrompt } }
  let user ← Agent.normalizeTextPrompt text #[]
  let agent ← agent.promptMessages (pending.push user)
  pure { h with agent := agent }

def promptWithImages
    (h : AgentHarness)
    (text : String)
    (images : Array LeanAgent.AI.ImageContent) : IO AgentHarness := do
  let systemPrompt := buildSystemPrompt h.agent.state.systemPrompt h.skills
  let pending := h.nextTurnQueue
  let h := { h with nextTurnQueue := #[] }
  h.emitQueue
  let agent :=
    { h.agent with state := { h.agent.state with systemPrompt := systemPrompt } }
  let user ← Agent.normalizeTextPrompt text images
  let agent ← agent.promptMessages (pending.push user)
  pure { h with agent := agent }

def continue_ (h : AgentHarness) : IO AgentHarness := do
  let agent ← h.agent.continue
  pure { h with agent := agent }

/-- Append a message to the agent transcript without starting a turn (Pi `appendMessage`). -/
def appendMessage (h : AgentHarness) (message : AgentMessage) : IO AgentHarness := do
  let agent :=
    { h.agent with
      state :=
        { h.agent.state with
          messages := h.agent.state.messages.push message
        }
    }
  pure { h with agent := agent }

/-- Update the active model on the agent state (Pi `setModel`). -/
def setModel (h : AgentHarness) (model : LeanAgent.Models.ModelInfo) : IO AgentHarness := do
  pure
    { h with
      agent :=
        { h.agent with
          state := { h.agent.state with model := model }
        }
    }

def getModel (h : AgentHarness) : LeanAgent.Models.ModelInfo :=
  h.agent.state.model

/-- Update thinking level (Pi `setThinkingLevel`). -/
def setThinkingLevel
    (h : AgentHarness)
    (level : LeanAgent.AI.ModelThinkingLevel) : IO AgentHarness := do
  pure
    { h with
      agent :=
        { h.agent with
          state := { h.agent.state with thinkingLevel := level }
        }
    }

def getThinkingLevel (h : AgentHarness) : LeanAgent.AI.ModelThinkingLevel :=
  h.agent.state.thinkingLevel

/--
Offline compact with explicit summary text (Pi compact subset without live LLM).
Replaces agent transcript with summary + kept suffix.  Backward-compatible
signature for existing callers.
-/
def compact
    (h : AgentHarness)
    (summary : String)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) :
    IO AgentHarness := do
  h.emit (.phase "compaction")
  let compacted ← LeanAgent.Agent.Harness.Compaction.compactWithSummary h.agent.state.messages summary settings
  let agent :=
    { h.agent with
      state := { h.agent.state with messages := compacted }
    }
  h.emit (.phase "idle")
  pure { h with agent := agent }

/--
Full-pipeline compact: check shouldCompact, select window, build summary
automatically (no explicit summary text required).  Leaves messages
unchanged when compaction is not triggered.
-/
def compactAuto
    (h : AgentHarness)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) :
    IO AgentHarness := do
  h.emit (.phase "compaction")
  let compacted ← LeanAgent.Agent.Harness.Compaction.compact h.agent.state.messages settings
  let agent :=
    { h.agent with
      state := { h.agent.state with messages := compacted }
    }
  h.emit (.phase "idle")
  pure { h with agent := agent }

/-- Persist harness transcript into a SessionTree (memory). -/
def toSessionTree (h : AgentHarness) (sessionId : String) : IO SessionTree := do
  let mut tree := SessionTree.empty sessionId
  for msg in h.agent.state.messages do
    tree ← tree.append msg
  pure tree

/-- Get a resource by key from the resource map (Pi `getResources`). -/
def getResource? (h : AgentHarness) (key : String) : Option Lean.Json :=
  h.resources.get? key

/-- Set a resource by key in the resource map (pure update). -/
def setResource (h : AgentHarness) (key : String) (value : Lean.Json) : AgentHarness :=
  { h with resources := h.resources.insert key value }

/-- Return the array of pending session write descriptors (Pi `pendingSessionWrites`). -/
def getPendingWrites (h : AgentHarness) : Array PendingSessionWrite :=
  h.pendingWrites

/-- Enqueue a pending session write descriptor (pure update). -/
def addPendingWrite (h : AgentHarness) (write : PendingSessionWrite) : AgentHarness :=
  { h with pendingWrites := h.pendingWrites.push write }

/-- Flush (clear) pending session writes, returning the flushed array (Pi `flushPendingSessionWrites`). -/
def flushPendingWrites (h : AgentHarness) : Array PendingSessionWrite × AgentHarness :=
  (h.pendingWrites, { h with pendingWrites := #[] })

/-- Get a copy of the current stream options (Pi `getStreamOptions`). -/
def getStreamOptions (h : AgentHarness) : HarnessStreamOptions :=
  cloneStreamOptions h.streamOptions

/-- Set stream options (Pi `setStreamOptions`). -/
def setStreamOptions (h : AgentHarness) (opts : HarnessStreamOptions) : AgentHarness :=
  { h with streamOptions := cloneStreamOptions opts }

/--
Navigate the session tree to a different leaf (Pi `navigateTree`).
Returns the new branch messages and optional editor text for user-message targets.
This offline variant walks the session storage from the harness agent state.
-/
def navigateTree
    (h : AgentHarness)
    (sessionId : String)
    (targetLeafId : String) : IO NavigateTreeResult := do
  let tree ← h.toSessionTree sessionId
  match tree.entryById? targetLeafId with
  | none => pure { cancelled := true }
  | some targetEntry =>
    let (newLeafId, editorText) :=
      match targetEntry.message with
      | .ofMessage (.user m) =>
        (targetEntry.parentId.getD targetEntry.id, some (LeanAgent.AI.contentPlainText m.content))
      | _ => (targetEntry.id, none)
    let branchMessages :=
      if newLeafId == targetEntry.id then
        tree.messagesOnBranch targetEntry.id
      else
        match targetEntry.parentId with
        | some pid => tree.messagesOnBranch pid
        | none => #[]
    pure { cancelled := false, editorText := editorText, branchMessages := branchMessages }

end AgentHarness

/-!
## IO.Ref-backed harness variant (Pi `handlers`, `resources`, `pendingSessionWrites`)

Wraps `AgentHarness` with `IO.Ref` mutable state so subscribers, resources,
and pending writes can be added/removed during a run without rebuilding the
entire harness value.  The underlying `agent` and `nextTurnQueue` remain
immutable (functional update).
-/

structure AgentHarnessRef where
  harness : AgentHarness
  listenersRef : IO.Ref (Array (Nat × HarnessEventSink))
  resourcesRef : IO.Ref (Std.HashMap String Lean.Json)
  pendingWritesRef : IO.Ref (Array PendingSessionWrite)

namespace AgentHarnessRef

/-- Create an IO.Ref-backed harness (Pi constructor). -/
def createIO
    (options : AgentOptions := default)
    (skills : Array SkillInfo := #[]) : IO AgentHarnessRef := do
  let harness := AgentHarness.create options skills
  let listenersRef ← IO.mkRef (#[] : Array (Nat × HarnessEventSink))
  let resourcesRef ← IO.mkRef (∅ : Std.HashMap String Lean.Json)
  let pendingWritesRef ← IO.mkRef (#[] : Array PendingSessionWrite)
  pure ⟨harness, listenersRef, resourcesRef, pendingWritesRef⟩

/-- Subscribe an event handler; returns the listener ID for unsubscribe (Pi `subscribe`). -/
def subscribe (hr : AgentHarnessRef) (listener : HarnessEventSink) : IO Nat := do
  let listeners ← hr.listenersRef.get
  let id := listeners.size
  hr.listenersRef.set (listeners.push (id, listener))
  pure id

/-- Unsubscribe an event handler by ID (Pi `subscribe` disposer). -/
def unsubscribe (hr : AgentHarnessRef) (id : Nat) : IO Unit :=
  hr.listenersRef.modify fun listeners => listeners.filter (fun (i, _) => i != id)

/-- Emit an event to all IO.Ref-backed subscribers (Pi `emitOwn`). -/
def emit (hr : AgentHarnessRef) (event : HarnessEvent) : IO Unit := do
  let listeners ← hr.listenersRef.get
  for (_, listener) in listeners do
    listener event


def emitQueue (hr : AgentHarnessRef) : IO Unit :=
  hr.emit (.queueUpdate hr.harness.queueSnapshot)

/-- Get a resource from the IO.Ref-backed map (Pi `getResources`). -/
def getResource? (hr : AgentHarnessRef) (key : String) : IO (Option Lean.Json) := do
  let map ← hr.resourcesRef.get
  pure (map.get? key)

/-- Set a resource in the IO.Ref-backed map. -/
def setResource (hr : AgentHarnessRef) (key : String) (value : Lean.Json) : IO Unit :=
  hr.resourcesRef.modify (·.insert key value)

/-- Return pending session write descriptors from the IO.Ref-backed array. -/
def getPendingWrites (hr : AgentHarnessRef) : IO (Array PendingSessionWrite) :=
  hr.pendingWritesRef.get

/-- Enqueue a pending session write descriptor. -/
def addPendingWrite (hr : AgentHarnessRef) (write : PendingSessionWrite) : IO Unit :=
  hr.pendingWritesRef.modify (·.push write)

/-- Flush (clear) pending session writes, returning the flushed array (Pi `flushPendingSessionWrites`). -/
def flushPendingWrites (hr : AgentHarnessRef) : IO (Array PendingSessionWrite) := do
  let writes ← hr.pendingWritesRef.get
  hr.pendingWritesRef.set #[]
  pure writes

/-- Update the underlying harness (functional update). -/
def withHarness (hr : AgentHarnessRef) (h : AgentHarness) : AgentHarnessRef :=
  { hr with harness := h }

def steer (hr : AgentHarnessRef) (message : AgentMessage) : IO AgentHarnessRef := do
  let h := hr.harness.withAgent (hr.harness.agent.steer message)
  let hr := hr.withHarness h
  hr.emitQueue
  pure hr

def followUp (hr : AgentHarnessRef) (message : AgentMessage) : IO AgentHarnessRef := do
  let h := hr.harness.withAgent (hr.harness.agent.followUp message)
  let hr := hr.withHarness h
  hr.emitQueue
  pure hr

def nextTurn (hr : AgentHarnessRef) (message : AgentMessage) : IO AgentHarnessRef := do
  let hr := { hr with harness := { hr.harness with nextTurnQueue := hr.harness.nextTurnQueue.push message } }
  hr.emitQueue
  pure hr

end AgentHarnessRef

end LeanAgent.Agent.Harness