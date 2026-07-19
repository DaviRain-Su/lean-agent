import Lean
import LeanAgent.Agent.Types
import LeanAgent.Agent.Harness.Storage
import LeanAgent.Agent.Harness.Session
import LeanAgent.CodingAgent.Config

/-!
# Coding-agent SessionManager (Pi `session-manager.ts` subset)

Durable session list/create/open over harness `JsonlSessionRepo`.
-/

namespace LeanAgent.CodingAgent.SessionManager

open LeanAgent.Agent
open LeanAgent.Agent.Harness.Storage
open LeanAgent.Agent.Harness.Session
open LeanAgent.CodingAgent.Config

/-- Pi `CURRENT_SESSION_VERSION`. -/
def currentSessionVersion : Nat := 3

structure SessionManager where
  repo : JsonlSessionRepo
  cwd : String

namespace SessionManager

/-- Create a session manager rooted at `sessionsRoot` for project `cwd`. -/
def create (cwd : String) (sessionsRoot : System.FilePath) : IO SessionManager := do
  let repo ← JsonlSessionRepo.createRepo sessionsRoot
  pure { repo := repo, cwd := cwd }

/-- Default sessions root from Config (Pi `getDefaultSessionDir`). -/
def createDefault (cwd : String) : IO SessionManager := do
  let root ← getDefaultSessionDir (System.FilePath.mk cwd)
  create cwd root

def createSession
    (sm : SessionManager)
    (id : Option String := none)
    (parentSessionPath : Option String := none) :
    IO (JsonlSessionMetadata × SessionTree) :=
  JsonlSessionRepo.create sm.repo
    { cwd := sm.cwd, id := id, parentSessionPath := parentSessionPath }

def openSession
    (sm : SessionManager)
    (sessMeta : JsonlSessionMetadata) :
    IO (JsonlSessionMetadata × SessionTree) :=
  JsonlSessionRepo.openSession sm.repo sessMeta

def list (sm : SessionManager) : IO (Array JsonlSessionMetadata) :=
  JsonlSessionRepo.list sm.repo (cwd? := some sm.cwd)

def delete (sm : SessionManager) (sessMeta : JsonlSessionMetadata) : IO Unit :=
  JsonlSessionRepo.delete sm.repo sessMeta


/-- Build session context from a loaded tree's full message list (no branch). -/
def buildContextFromTree (tree : SessionTree) : SessionContext :=
  buildSessionContext tree.messages

/-- Append message to a session tree (Pi `appendMessage`). -/
def appendMessage
    (sessMeta : JsonlSessionMetadata)
    (tree : SessionTree)
    (message : LeanAgent.Agent.AgentMessage) : IO SessionTree :=
  JsonlSessionRepo.appendMessage sessMeta tree message

