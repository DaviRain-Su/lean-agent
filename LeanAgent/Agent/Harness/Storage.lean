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

end LeanAgent.Agent.Harness.Storage
