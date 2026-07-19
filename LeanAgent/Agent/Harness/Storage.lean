import Lean
import LeanAgent.Agent.Types
import LeanAgent.AI.Types
import LeanAgent.Json
import LeanAgent.Agent.Harness.Uuid

namespace LeanAgent.Agent.Harness.Storage

open LeanAgent.Agent
open LeanAgent.Agent.Harness.Uuid

/-- Tree-capable session entry (Pi session tree subset for offline harness). -/
structure SessionEntry where
  id : String
  parentId : Option String := none
  timestamp : Nat
  message : AgentMessage
deriving Inhabited

structure SessionTree where
  id : String
  entries : Array SessionEntry := #[]
deriving Inhabited

namespace SessionTree

def empty (id : String := "session") : SessionTree :=
  { id := id }

def append
    (tree : SessionTree)
    (message : AgentMessage)
    (parentId : Option String := none)
    (id : Option String := none)
    (timestamp : Option Nat := none) : IO SessionTree := do
  let entryId ←
    match id with
    | some v => pure v
    | none => uuidv7
  let ts ←
    match timestamp with
    | some v => pure v
    | none => IO.monoMsNow
  let parent :=
    match parentId with
    | some p => some p
    | none => tree.entries.back?.map (·.id)
  let entry : SessionEntry :=
    { id := entryId
      parentId := parent
      timestamp := ts
      message := message
    }
  pure { tree with entries := tree.entries.push entry }

def messages (tree : SessionTree) : Array AgentMessage :=
  tree.entries.map (·.message)

def leafId? (tree : SessionTree) : Option String :=
  tree.entries.back?.map (·.id)

def entryById? (tree : SessionTree) (id : String) : Option SessionEntry :=
  tree.entries.find? (·.id == id)

/-- Walk parent links from a leaf to root (inclusive), oldest first. -/
def branchFrom (tree : SessionTree) (leafId : String) : Array SessionEntry :=
  let byId := tree.entries.foldl (init := (∅ : Std.HashMap String SessionEntry)) fun m e =>
    m.insert e.id e
  let rec go (fuel : Nat) (id? : Option String) (acc : List SessionEntry) : List SessionEntry :=
    match fuel, id? with
    | 0, _ => acc
    | _, none => acc
    | fuel + 1, some id =>
        match byId.get? id with
        | none => acc
        | some e => go fuel e.parentId (e :: acc)
  (go (tree.entries.size + 1) (some leafId) []).toArray

/-- Messages along the branch ending at `leafId` (oldest first). -/
def messagesOnBranch (tree : SessionTree) (leafId : String) : Array AgentMessage :=
  (branchFrom tree leafId).map (·.message)

/-- Replace an entry's message by id (Pi session tree edit subset). -/
def replaceEntryMessage (tree : SessionTree) (id : String) (message : AgentMessage) : SessionTree :=
  { tree with
    entries :=
      tree.entries.map fun e =>
        if e.id == id then { e with message := message } else e
  }

/-- Append a child of a specific parent (explicit tree edge). -/
def appendChild
    (tree : SessionTree)
    (parentId : String)
    (message : AgentMessage)
    (id : Option String := none) : IO SessionTree := do
  if (tree.entryById? parentId).isNone then
    throw (IO.userError s!"unknown parent id: {parentId}")
  tree.append message (parentId := some parentId) (id := id)

end SessionTree

/-- In-memory session repository (Pi memory-repo subset). -/
structure MemoryRepo where
  trees : Std.HashMap String SessionTree := ∅

namespace MemoryRepo

def empty : MemoryRepo := {}

def get? (repo : MemoryRepo) (sessionId : String) : Option SessionTree :=
  repo.trees.get? sessionId

def put (repo : MemoryRepo) (tree : SessionTree) : MemoryRepo :=
  { repo with trees := repo.trees.insert tree.id tree }

def create (repo : MemoryRepo) (sessionId : String) : MemoryRepo × SessionTree :=
  let tree := SessionTree.empty sessionId
  (repo.put tree, tree)

def appendMessage
    (repo : MemoryRepo)
    (sessionId : String)
    (message : AgentMessage)
    (parentId : Option String := none) : IO (MemoryRepo × SessionTree) := do
  let tree := (repo.get? sessionId).getD (SessionTree.empty sessionId)
  let tree ← tree.append message parentId
  pure (repo.put tree, tree)

end MemoryRepo

/-!
Pi `InMemorySessionStorage` subset: mutable session storage with leaf pointer,
short entry ids, and label cache.
-/

structure SessionMetadata where
  id : String
  createdAt : String
deriving Inhabited, BEq

inductive SessionTreeEntry where
  /-- Message-bearing tree node (Lean session message entry). -/
  | message (entry : SessionEntry)
  /-- Pi leaf marker pointing at the active leaf entry id (`targetId`). -/
  | leaf (id : String) (parentId : Option String) (timestamp : Nat) (targetId : Option String)
  /-- Optional label on a target entry id. Empty/none clears. -/
  | label (id : String) (parentId : Option String) (timestamp : Nat) (targetId : String) (label : Option String)
  /-- Pi `model_change` entry. -/
  | modelChange
      (id : String)
      (parentId : Option String)
      (timestamp : Nat)
      (provider : String)
      (modelId : String)
  /-- Pi `thinking_level_change` entry. -/
  | thinkingLevelChange
      (id : String)
      (parentId : Option String)
      (timestamp : Nat)
      (thinkingLevel : String)
  /-- Pi `compaction` entry: summary + first kept entry id for context rebuild. -/
  | compaction
      (id : String)
      (parentId : Option String)
      (timestamp : Nat)
      (summary : String)
      (firstKeptEntryId : Option String)
deriving Inhabited

namespace SessionTreeEntry

def id : SessionTreeEntry → String
  | .message e => e.id
  | .leaf id _ _ _ => id
  | .label id _ _ _ _ => id
  | .modelChange id _ _ _ _ => id
  | .thinkingLevelChange id _ _ _ => id
  | .compaction id _ _ _ _ => id

def parentId : SessionTreeEntry → Option String
  | .message e => e.parentId
  | .leaf _ p _ _ => p
  | .label _ p _ _ _ => p
  | .modelChange _ p _ _ _ => p
  | .thinkingLevelChange _ p _ _ => p
  | .compaction _ p _ _ _ => p

end SessionTreeEntry

/-- Pi-style in-memory session storage (IO-backed, mutable). -/
structure InMemorySessionStorage where
  metadata : SessionMetadata
  entriesRef : IO.Ref (Array SessionTreeEntry)
  leafIdRef : IO.Ref (Option String)
  labelsRef : IO.Ref (Std.HashMap String String)

namespace InMemorySessionStorage

def shortEntryId (used : Array String) : IO String := do
  let mut attempt : Nat := 0
  while attempt < 100 do
    let full ← uuidv7
    let short := (full.take 8).toString
    if !(used.any (· == short)) then
      return short
    attempt := attempt + 1
  uuidv7

def create (sessionId : Option String := none) : IO InMemorySessionStorage := do
  let id ←
    match sessionId with
    | some s => pure s
    | none => uuidv7
  let createdAt ← do
    let ms ← IO.monoMsNow
    pure (toString ms)
  pure
    { metadata := { id := id, createdAt := createdAt }
      entriesRef := ← IO.mkRef #[]
      leafIdRef := ← IO.mkRef none
      labelsRef := ← IO.mkRef {}
    }

def getMetadata (s : InMemorySessionStorage) : IO SessionMetadata :=
  pure s.metadata

def getLeafId (s : InMemorySessionStorage) : IO (Option String) :=
  s.leafIdRef.get

def getEntry (s : InMemorySessionStorage) (id : String) : IO (Option SessionTreeEntry) := do
  let entries ← s.entriesRef.get
  pure (entries.find? fun e => e.id == id)

def createEntryId (s : InMemorySessionStorage) : IO String := do
  let entries ← s.entriesRef.get
  shortEntryId (entries.map (·.id))

def appendEntry (s : InMemorySessionStorage) (entry : SessionTreeEntry) : IO Unit := do
  s.entriesRef.modify (·.push entry)
  match entry with
  | .message e => s.leafIdRef.set (some e.id)
  | .leaf _ _ _ targetId => s.leafIdRef.set targetId
  | .label _ _ _ targetId label? =>
      match label? with
      | some label =>
          if label.trimAscii.isEmpty then
            s.labelsRef.modify fun m => m.erase targetId
          else
            s.labelsRef.modify fun m => m.insert targetId label
      | none =>
          s.labelsRef.modify fun m => m.erase targetId
  | .modelChange id _ _ _ _ => s.leafIdRef.set (some id)
  | .thinkingLevelChange id _ _ _ => s.leafIdRef.set (some id)
  | .compaction id _ _ _ _ => s.leafIdRef.set (some id)

/-- Pi `setLeafId`: append a leaf marker entry and update active leaf pointer. -/
def setLeafId (s : InMemorySessionStorage) (leafId : Option String) : IO Unit := do
  match leafId with
  | some id =>
      if (← s.getEntry id).isNone then
        throw (IO.userError s!"not_found: Entry {id} not found")
  | none => pure ()
  let id ← s.createEntryId
  let parent ← s.leafIdRef.get
  let ts ← IO.monoMsNow
  s.appendEntry (.leaf id parent ts leafId)

/-- Append a message entry (parent defaults to current leaf). -/
def appendMessage
    (s : InMemorySessionStorage)
    (message : AgentMessage)
    (parentId : Option String := none)
    (id : Option String := none) : IO SessionEntry := do
  let entryId ←
    match id with
    | some v => pure v
    | none => s.createEntryId
  let ts ← IO.monoMsNow
  let parent ←
    match parentId with
    | some p => pure (some p)
    | none => s.leafIdRef.get
  let entry : SessionEntry :=
    { id := entryId, parentId := parent, timestamp := ts, message := message }
  s.appendEntry (.message entry)
  pure entry

def getLabel? (s : InMemorySessionStorage) (targetId : String) : IO (Option String) := do
  pure ((← s.labelsRef.get).get? targetId)

def setLabel (s : InMemorySessionStorage) (targetId : String) (label : Option String) : IO Unit := do
  if (← s.getEntry targetId).isNone then
    throw (IO.userError s!"not_found: Entry {targetId} not found")
  let id ← s.createEntryId
  let parent ← s.leafIdRef.get
  let ts ← IO.monoMsNow
  s.appendEntry (.label id parent ts targetId label)

/-- Append a model_change entry (Pi session tree). -/
def appendModelChange
    (s : InMemorySessionStorage)
    (provider : String)
    (modelId : String)
    (parentId : Option String := none) : IO SessionTreeEntry := do
  let entryId ← s.createEntryId
  let ts ← IO.monoMsNow
  let parent ←
    match parentId with
    | some p => pure (some p)
    | none => s.leafIdRef.get
  let entry := .modelChange entryId parent ts provider modelId
  s.appendEntry entry
  pure entry

/-- Append a thinking_level_change entry. -/
def appendThinkingLevelChange
    (s : InMemorySessionStorage)
    (thinkingLevel : String)
    (parentId : Option String := none) : IO SessionTreeEntry := do
  let entryId ← s.createEntryId
  let ts ← IO.monoMsNow
  let parent ←
    match parentId with
    | some p => pure (some p)
    | none => s.leafIdRef.get
  let entry := .thinkingLevelChange entryId parent ts thinkingLevel
  s.appendEntry entry
  pure entry

/-- Append a compaction entry with summary and optional first kept message entry id. -/
def appendCompaction
    (s : InMemorySessionStorage)
    (summary : String)
    (firstKeptEntryId : Option String := none)
    (parentId : Option String := none) : IO SessionTreeEntry := do
  let entryId ← s.createEntryId
  let ts ← IO.monoMsNow
  let parent ←
    match parentId with
    | some p => pure (some p)
    | none => s.leafIdRef.get
  let entry := .compaction entryId parent ts summary firstKeptEntryId
  s.appendEntry entry
  pure entry

def entries (s : InMemorySessionStorage) : IO (Array SessionTreeEntry) :=
  s.entriesRef.get

/-- Convert message entries into a `SessionTree` (ignores leaf/label markers). -/
def toSessionTree (s : InMemorySessionStorage) : IO SessionTree := do
  let entries ← s.entriesRef.get
  let mut msgs : Array SessionEntry := #[]
  for e in entries do
    match e with
    | .message entry => msgs := msgs.push entry
    | _ => pure ()
  pure { id := s.metadata.id, entries := msgs }

end InMemorySessionStorage

/-- Pi `repo-utils` helpers. -/
def createSessionId : IO String := uuidv7

def createTimestamp : IO String := do
  pure (toString (← IO.monoMsNow))

/--
Pi `getEntriesToFork` / path-to-root subset for message entries.
`position = at` includes the target; `before` uses parent (user-message fork semantics).
-/
def getMessagePathToRoot
    (entries : Array SessionEntry)
    (leafId? : Option String) : Array SessionEntry :=
  match leafId? with
  | none => #[]
  | some leafId =>
      let tree : SessionTree := { id := "fork", entries := entries }
      tree.branchFrom leafId

/-- Pi `InMemorySessionRepo` subset. -/
structure InMemorySessionRepo where
  sessionsRef : IO.Ref (Std.HashMap String InMemorySessionStorage)

structure ForkOptions where
  entryId : Option String := none
  /-- `"at"` includes entry; `"before"` uses parent id (Pi default). -/
  position : String := "before"
  id : Option String := none
deriving Inhabited

namespace InMemorySessionRepo

def createRepo : IO InMemorySessionRepo := do
  pure { sessionsRef := ← IO.mkRef {} }

def create (repo : InMemorySessionRepo) (id : Option String := none) : IO InMemorySessionStorage := do
  let store ← InMemorySessionStorage.create id
  repo.sessionsRef.modify fun m => m.insert store.metadata.id store
  pure store

def openSession (repo : InMemorySessionRepo) (sessionId : String) : IO InMemorySessionStorage := do
  match (← repo.sessionsRef.get).get? sessionId with
  | some s => pure s
  | none => throw (IO.userError s!"not_found: Session not found: {sessionId}")

def list (repo : InMemorySessionRepo) : IO (Array SessionMetadata) := do
  let m ← repo.sessionsRef.get
  pure (m.toArray.map fun (_, s) => s.metadata)

def delete (repo : InMemorySessionRepo) (sessionId : String) : IO Unit := do
  repo.sessionsRef.modify fun m => m.erase sessionId

/--
Fork a session at/before a message entry id.
Copies message path-to-root into a new InMemorySessionStorage.
-/
def fork
    (repo : InMemorySessionRepo)
    (sourceId : String)
    (options : ForkOptions := {}) :
    IO InMemorySessionStorage := do
  let source ← openSession repo sourceId
  let sessTree ← InMemorySessionStorage.toSessionTree source
  let leaf? ← InMemorySessionStorage.getLeafId source
  let effectiveLeaf? ←
    match options.entryId with
    | none => pure leaf?
    | some entryId =>
        match SessionTree.entryById? sessTree entryId with
        | none => throw (IO.userError s!"invalid_fork_target: Entry {entryId} not found")
        | some sessEntry =>
            if options.position == "at" then
              pure (some sessEntry.id)
            else
              pure sessEntry.parentId
  let forkedMsgs := getMessagePathToRoot sessTree.entries effectiveLeaf?
  let store ← InMemorySessionStorage.create options.id
  let mut idMap : Std.HashMap String String := {}
  for sessEntry in forkedMsgs do
    let parentMapped :=
      match sessEntry.parentId with
      | none => none
      | some p => idMap.get? p
    let ne ← InMemorySessionStorage.appendMessage store sessEntry.message (parentId := parentMapped)
    idMap := idMap.insert sessEntry.id ne.id
  repo.sessionsRef.modify fun m => m.insert store.metadata.id store
  pure store

end InMemorySessionRepo

def entryToJson (entry : SessionEntry) : Lean.Json :=
  let msgJson :=
    match entry.message with
    | .ofMessage m => LeanAgent.AI.messageToJson m
    | .custom customType content display timestamp =>
        LeanAgent.Json.obj
          [ ("role", LeanAgent.Json.str "custom")
          , ("customType", LeanAgent.Json.str customType)
          , ("content", LeanAgent.AI.contentArrayToJson content)
          , ("display", LeanAgent.Json.bool display)
          , ("timestamp", LeanAgent.Json.nat timestamp)
          ]
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "message")
    , ("id", LeanAgent.Json.str entry.id)
    , ("parentId",
        match entry.parentId with
        | some p => LeanAgent.Json.str p
        | none => Lean.Json.null)
    , ("timestamp", LeanAgent.Json.nat entry.timestamp)
    , ("message", msgJson)
    ]

def entryFromJson (json : Lean.Json) : Except String SessionEntry := do
  let id ← (← json.getObjVal? "id").getStr?
  let parentId ←
    match LeanAgent.Json.optVal? json "parentId" with
    | some Lean.Json.null => pure none
    | some v => pure (some (← v.getStr?))
    | none => pure none
  let timestamp ← (← json.getObjVal? "timestamp").getNat?
  let messageJson ← json.getObjVal? "message"
  let role ← (← messageJson.getObjVal? "role").getStr?
  let message ←
    match role with
    | "custom" =>
        pure
          (.custom
            (← (← messageJson.getObjVal? "customType").getStr?)
            (← LeanAgent.AI.contentArrayFromJson (← messageJson.getObjVal? "content"))
            ((← LeanAgent.Json.optionalBool messageJson "display").getD true)
            ((← LeanAgent.Json.optionalNat messageJson "timestamp").getD 0))
    | _ =>
        pure (.ofMessage (← LeanAgent.AI.messageFromJson messageJson))
  pure { id := id, parentId := parentId, timestamp := timestamp, message := message }

/-- Append-only JSONL store that preserves parentId for tree sessions. -/
def writeTreeJsonl (path : System.FilePath) (tree : SessionTree) : IO Unit := do
  let header :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "session")
      , ("version", LeanAgent.Json.nat 2)
      , ("id", LeanAgent.Json.str tree.id)
      ]
  let mut lines := #[header.compress]
  for entry in tree.entries do
    lines := lines.push (entryToJson entry).compress
  IO.FS.writeFile path (String.intercalate "\n" lines.toList ++ "\n")

def readTreeJsonl (path : System.FilePath) : IO SessionTree := do
  let content ← IO.FS.readFile path
  let mut tree := SessionTree.empty
  let mut first := true
  for line in content.splitOn "\n" do
    let trimmed := line.trimAscii.toString
    if trimmed.isEmpty then
      pure ()
    else
      match Lean.Json.parse trimmed with
      | .error err => throw (IO.userError s!"jsonl parse error: {err}")
      | .ok json =>
          if first then
            first := false
            let id :=
              match LeanAgent.Json.optVal? json "id" with
              | some (.str s) => s
              | _ => "session"
            tree := SessionTree.empty id
          else
            match entryFromJson json with
            | .error err => throw (IO.userError err)
            | .ok entry =>
                tree := { tree with entries := tree.entries.push entry }
  pure tree

/-!
Pi `JsonlSessionRepo` / durable JSONL session store (v3 header subset).
Persists session trees under `sessionsRoot/<encoded-cwd>/<timestamp>_<id>.jsonl`.
-/

structure JsonlSessionMetadata where
  id : String
  createdAt : String
  cwd : String
  path : System.FilePath
  parentSessionPath : Option String := none
deriving Inhabited

structure JsonlSessionCreateOptions where
  cwd : String
  id : Option String := none
  parentSessionPath : Option String := none
deriving Inhabited

/-- Encode cwd for a directory name (Pi `encodeCwd`). -/
def encodeCwd (cwd : String) : String :=
  let stripped :=
    if cwd.startsWith "/" || cwd.startsWith "\\" then
      (cwd.drop 1).toString
    else
      cwd
  let chars :=
    stripped.toList.map fun c =>
      if c == '/' || c == '\\' || c == ':' then '-' else c
  s!"--{String.ofList chars}--"

/-- Sanitize timestamp for filenames (Pi replaces `:` and `.`). -/
def sanitizeTimestampForFilename (ts : String) : String :=
  String.ofList <|
    ts.toList.map fun c =>
      if c == ':' || c == '.' then '-' else c

/-- Load metadata from the first line of a v2/v3 JSONL session file. -/
def loadJsonlSessionMetadata (path : System.FilePath) : IO JsonlSessionMetadata := do
  let content ← IO.FS.readFile path
  let firstLine ←
    match content.splitOn "\n" |>.find? (fun l => !(l.trimAscii.toString.isEmpty)) with
    | some l => pure (l.trimAscii.toString)
    | none => throw (IO.userError s!"invalid_session: missing session header in {path}")
  match Lean.Json.parse firstLine with
  | .error err => throw (IO.userError s!"invalid_session: {err}")
  | .ok json =>
      let id ←
        match LeanAgent.Json.optVal? json "id" with
        | some (.str s) => pure s
        | _ => throw (IO.userError "invalid_session: session header is missing id")
      let createdAt ←
        match LeanAgent.Json.optVal? json "timestamp" with
        | some (.str s) => pure s
        | some (.num n) => pure (toString n)
        | _ =>
            match LeanAgent.Json.optVal? json "createdAt" with
            | some (.str s) => pure s
            | _ => pure "0"
      let cwd ←
        match LeanAgent.Json.optVal? json "cwd" with
        | some (.str s) => pure s
        | _ => pure ""
      let parentSessionPath :=
        match LeanAgent.Json.optVal? json "parentSession" with
        | some (.str s) => some s
        | _ => none
      pure
        { id := id
          createdAt := createdAt
          cwd := cwd
          path := path
          parentSessionPath := parentSessionPath
        }

/-- Write a durable v3 JSONL session file (header + message entries). -/
def writeJsonlSessionFile
    (path : System.FilePath)
    (sessMeta : JsonlSessionMetadata)
    (tree : SessionTree) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let baseFields : List (String × Lean.Json) :=
    [ ("type", LeanAgent.Json.str "session")
    , ("version", LeanAgent.Json.nat 3)
    , ("id", LeanAgent.Json.str sessMeta.id)
    , ("timestamp", LeanAgent.Json.str sessMeta.createdAt)
    , ("cwd", LeanAgent.Json.str sessMeta.cwd)
    ]
  let headerFields :=
    match sessMeta.parentSessionPath with
    | some p => baseFields ++ [("parentSession", LeanAgent.Json.str p)]
    | none => baseFields
  let header := LeanAgent.Json.obj headerFields
  let mut lines := #[header.compress]
  for entry in tree.entries do
    lines := lines.push (entryToJson entry).compress
  IO.FS.writeFile path (String.intercalate "\n" lines.toList ++ "\n")

/-- Read message entries from a durable JSONL session (skips header). -/
def readJsonlSessionTree (path : System.FilePath) : IO (JsonlSessionMetadata × SessionTree) := do
  let sessMeta ← loadJsonlSessionMetadata path
  let content ← IO.FS.readFile path
  let mut tree := SessionTree.empty sessMeta.id
  let mut first := true
  for line in content.splitOn "\n" do
    let trimmed := line.trimAscii.toString
    if trimmed.isEmpty then
      pure ()
    else if first then
      first := false
    else
      match Lean.Json.parse trimmed with
      | .error err => throw (IO.userError s!"jsonl parse error: {err}")
      | .ok json =>
          -- Only message entries for offline tree; skip leaf/label for now if present.
          let ty :=
            match LeanAgent.Json.optVal? json "type" with
            | some (.str s) => s
            | _ => "message"
          if ty == "message" || !(ty == "leaf" || ty == "label") then
            match entryFromJson json with
            | .error err => throw (IO.userError err)
            | .ok entry =>
                tree := { tree with entries := tree.entries.push entry }
  pure (sessMeta, tree)

/-- Pi `JsonlSessionRepo` subset: create / open / list / delete / fork on disk. -/
structure JsonlSessionRepo where
  sessionsRoot : System.FilePath

namespace JsonlSessionRepo

def createRepo (sessionsRoot : System.FilePath) : IO JsonlSessionRepo := do
  IO.FS.createDirAll sessionsRoot
  pure { sessionsRoot := sessionsRoot }

def sessionDir (repo : JsonlSessionRepo) (cwd : String) : System.FilePath :=
  repo.sessionsRoot / encodeCwd cwd

def createSessionFilePath
    (repo : JsonlSessionRepo)
    (cwd : String)
    (sessionId : String)
    (timestamp : String) : System.FilePath :=
  sessionDir repo cwd / s!"{sanitizeTimestampForFilename timestamp}_{sessionId}.jsonl"

/-- Create a new durable session file and return its metadata + empty tree. -/
def create
    (repo : JsonlSessionRepo)
    (options : JsonlSessionCreateOptions) : IO (JsonlSessionMetadata × SessionTree) := do
  let id ←
    match options.id with
    | some v => pure v
    | none => createSessionId
  let createdAt ← createTimestamp
  let dir := sessionDir repo options.cwd
  IO.FS.createDirAll dir
  let path := createSessionFilePath repo options.cwd id createdAt
  let sessMeta : JsonlSessionMetadata :=
    { id := id
      createdAt := createdAt
      cwd := options.cwd
      path := path
      parentSessionPath := options.parentSessionPath
    }
  let tree := SessionTree.empty id
  writeJsonlSessionFile path sessMeta tree
  pure (sessMeta, tree)

/-- Open an existing session by metadata path. -/
def openSession
    (_repo : JsonlSessionRepo)
    (sessMeta : JsonlSessionMetadata) : IO (JsonlSessionMetadata × SessionTree) := do
  unless (← sessMeta.path.pathExists) do
    throw (IO.userError s!"not_found: Session not found: {sessMeta.path}")
  readJsonlSessionTree sessMeta.path

/-- Append a message to a durable session file (rewrite whole file for offline simplicity). -/
def appendMessage
    (sessMeta : JsonlSessionMetadata)
    (tree : SessionTree)
    (message : AgentMessage)
    (parentId : Option String := none) : IO SessionTree := do
  let tree ← tree.append message (parentId := parentId)
  writeJsonlSessionFile sessMeta.path sessMeta tree
  pure tree

/-- List sessions, optionally filtered by cwd. Newest first by createdAt string order. -/
def list
    (repo : JsonlSessionRepo)
    (cwd? : Option String := none) : IO (Array JsonlSessionMetadata) := do
  let dirs : Array System.FilePath ←
    match cwd? with
    | some cwd => pure #[sessionDir repo cwd]
    | none =>
        if !(← repo.sessionsRoot.pathExists) then
          pure #[]
        else
          let entries ← repo.sessionsRoot.readDir
          pure (entries.filterMap fun e =>
            if e.fileName.startsWith "--" then some e.path else none)
  let mut sessions : Array JsonlSessionMetadata := #[]
  for dir in dirs do
    if ← dir.pathExists then
      let files ← dir.readDir
      for f in files do
        if f.fileName.endsWith ".jsonl" then
          try
            let m ← loadJsonlSessionMetadata f.path
            sessions := sessions.push m
          catch _ =>
            pure ()
  -- Sort newest first (createdAt is mono ms string → lexicographic works).
  pure (sessions.qsort fun a b => b.createdAt < a.createdAt)

def delete (_repo : JsonlSessionRepo) (sessMeta : JsonlSessionMetadata) : IO Unit := do
  try IO.FS.removeFile sessMeta.path catch _ => pure ()

/--
Fork: copy message path-to-root from source into a new durable session under `options.cwd`.
-/
def fork
    (repo : JsonlSessionRepo)
    (sourceMeta : JsonlSessionMetadata)
    (options : JsonlSessionCreateOptions)
    (forkOpts : ForkOptions := {}) : IO (JsonlSessionMetadata × SessionTree) := do
  let (_, sourceTree) ← openSession repo sourceMeta
  let effectiveLeaf? ←
    match forkOpts.entryId with
    | none => pure sourceTree.leafId?
    | some entryId =>
        match SessionTree.entryById? sourceTree entryId with
        | none => throw (IO.userError s!"invalid_fork_target: Entry {entryId} not found")
        | some sessEntry =>
            if forkOpts.position == "at" then
              pure (some sessEntry.id)
            else
              pure sessEntry.parentId
  let forkedMsgs := getMessagePathToRoot sourceTree.entries effectiveLeaf?
  let createOpts : JsonlSessionCreateOptions :=
    { options with
      id := forkOpts.id.orElse fun _ => options.id
      parentSessionPath := options.parentSessionPath.orElse fun _ => some sourceMeta.path.toString
    }
  let (sessMeta, _) ← create repo createOpts
  let mut tree := SessionTree.empty sessMeta.id
  let mut idMap : Std.HashMap String String := {}
  for sessEntry in forkedMsgs do
    let parentMapped :=
      match sessEntry.parentId with
      | none => none
      | some p => idMap.get? p
    tree ← tree.append sessEntry.message (parentId := parentMapped)
    let newId := tree.entries.back!.id
    idMap := idMap.insert sessEntry.id newId
  writeJsonlSessionFile sessMeta.path sessMeta tree
  pure (sessMeta, tree)

end JsonlSessionRepo

end LeanAgent.Agent.Harness.Storage
