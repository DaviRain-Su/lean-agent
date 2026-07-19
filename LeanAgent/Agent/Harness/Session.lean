import Lean
import LeanAgent.Agent.Types
import LeanAgent.Agent.Harness.Storage
import LeanAgent.AI.Types

/-!
# Harness Session façade (Pi `packages/agent/src/harness/session/session.ts` subset)

Wraps session storage and builds LLM-facing context from the active branch,
including model/thinking/compaction entry types (Pi `buildSessionContext` subset).
-/

namespace LeanAgent.Agent.Harness.Session

open LeanAgent.Agent
open LeanAgent.Agent.Harness.Storage

structure SessionContext where
  messages : Array AgentMessage := #[]
  thinkingLevel : String := "off"
  modelProvider : Option String := none
  modelId : Option String := none
  activeToolNames : Option (Array String) := none
deriving Inhabited

/--
Pi `buildSessionContext` for message-only path entries (current Lean storage).
Walks branch messages oldest-first into the session context.
-/
def buildSessionContext (pathMessages : Array AgentMessage) : SessionContext :=
  { messages := pathMessages
    thinkingLevel := "off"
    modelProvider := none
    modelId := none
    activeToolNames := none
  }

/--
Walk a path of session tree entries (oldest first) into LLM context.
- message → append to messages
- modelChange / thinkingLevelChange → update context fields
- compaction → replace messages with summary custom message (then continue with later msgs)
- leaf / label → ignored for context
-/
def buildSessionContextFromEntries (path : Array SessionTreeEntry) : SessionContext :=
  let rec step
      (entry : SessionTreeEntry)
      (acc : SessionContext × Array AgentMessage) :
      SessionContext × Array AgentMessage :=
    let (ctx, msgs) := acc
    match entry with
    | .message e =>
        (ctx, msgs.push e.message)
    | .modelChange _ _ _ provider modelId =>
        ({ ctx with modelProvider := some provider, modelId := some modelId }, msgs)
    | .thinkingLevelChange _ _ _ level =>
        ({ ctx with thinkingLevel := level }, msgs)
    | .compaction _ _ ts summary _ =>
        -- Pi compaction replaces prior transcript with a summary marker for the kept window.
        (ctx, #[.custom "compactionSummary" #[.text { text := summary }] true ts])
    | .leaf _ _ _ _ => acc
    | .label _ _ _ _ _ => acc
  let (ctx, msgs) := path.foldl (fun acc e => step e acc) ({}, #[])
  { ctx with messages := msgs }

/-- Pi `Session` façade over `InMemorySessionStorage`. -/
structure Session where
  storage : InMemorySessionStorage

namespace Session

def ofStorage (storage : InMemorySessionStorage) : Session :=
  { storage := storage }

def getMetadata (s : Session) : IO SessionMetadata :=
  InMemorySessionStorage.getMetadata s.storage

def getLeafId (s : Session) : IO (Option String) :=
  InMemorySessionStorage.getLeafId s.storage

def getStorage (s : Session) : InMemorySessionStorage :=
  s.storage

def getLabel? (s : Session) (id : String) : IO (Option String) :=
  InMemorySessionStorage.getLabel? s.storage id

def setLabel (s : Session) (id : String) (label : Option String) : IO Unit :=
  InMemorySessionStorage.setLabel s.storage id label

def appendMessage
    (s : Session)
    (message : AgentMessage)
    (parentId : Option String := none) : IO SessionEntry :=
  InMemorySessionStorage.appendMessage s.storage message (parentId := parentId)

def appendModelChange
    (s : Session)
    (provider : String)
    (modelId : String) : IO SessionTreeEntry :=
  InMemorySessionStorage.appendModelChange s.storage provider modelId

def appendThinkingLevelChange
    (s : Session)
    (thinkingLevel : String) : IO SessionTreeEntry :=
  InMemorySessionStorage.appendThinkingLevelChange s.storage thinkingLevel

def appendCompaction
    (s : Session)
    (summary : String)
    (firstKeptEntryId : Option String := none) : IO SessionTreeEntry :=
  InMemorySessionStorage.appendCompaction s.storage summary firstKeptEntryId

def setLeafId (s : Session) (leafId : Option String) : IO Unit :=
  InMemorySessionStorage.setLeafId s.storage leafId

/-- Branch path of raw entries to root (oldest first), including non-message types. -/
def getBranchEntries (s : Session) (fromId : Option String := none) : IO (Array SessionTreeEntry) := do
  let all ← InMemorySessionStorage.entries s.storage
  let leaf ←
    match fromId with
    | some id => pure (some id)
    | none => InMemorySessionStorage.getLeafId s.storage
  match leaf with
  | none => pure #[]
  | some leafId =>
      let byId :=
        all.foldl (init := (∅ : Std.HashMap String SessionTreeEntry)) fun m e =>
          m.insert e.id e
      let rec go (fuel : Nat) (id? : Option String) (acc : List SessionTreeEntry) :
          List SessionTreeEntry :=
        match fuel, id? with
        | 0, _ => acc
        | _, none => acc
        | fuel + 1, some id =>
            match byId.get? id with
            | none => acc
            | some e => go fuel e.parentId (e :: acc)
      pure (go (all.size + 1) (some leafId) []).toArray

/-- Branch path to root as message entries (oldest first). -/
def getBranchMessages (s : Session) (fromId : Option String := none) : IO (Array AgentMessage) := do
  let path ← s.getBranchEntries fromId
  pure
    (path.filterMap fun e =>
      match e with
      | .message se => some se.message
      | _ => none)

def buildContext (s : Session) (fromId : Option String := none) : IO SessionContext := do
  pure (buildSessionContextFromEntries (← s.getBranchEntries fromId))

end Session

end LeanAgent.Agent.Harness.Session
