import Lean
import LeanAgent.Agent.Types
import LeanAgent.Agent.Agent
import LeanAgent.Agent.Harness.AgentHarness
import LeanAgent.Agent.Harness.Compaction
import LeanAgent.AI.Types
import LeanAgent.CodingAgent.Defaults
import LeanAgent.CodingAgent.EventBus
import LeanAgent.CodingAgent.SessionManager
import LeanAgent.CodingTools
import LeanAgent.Models

/-!
# Coding-agent AgentSession (Pi `agent-session.ts` subset)

Offline façade: AgentHarness + optional durable SessionManager + EventBus + tools.
-/

namespace LeanAgent.CodingAgent.AgentSession

open LeanAgent.Agent
open LeanAgent.Agent.Harness
open LeanAgent.CodingAgent.Defaults
open LeanAgent.CodingAgent.EventBus
open LeanAgent.CodingAgent.SessionManager

structure AgentSession where
  harness : AgentHarness
  eventBus : EventBus
  sessionManager : Option SessionManager := none
  sessionMeta : Option LeanAgent.Agent.Harness.Storage.JsonlSessionMetadata := none
  sessionTree : Option LeanAgent.Agent.Harness.Storage.SessionTree := none
  cwd : System.FilePath
  thinkingLevel : LeanAgent.AI.ModelThinkingLevel := .level defaultThinkingLevel

structure CreateOptions where
  cwd : System.FilePath
  agentOptions : AgentOptions
  sessionManager : Option SessionManager := none
  sessionId : Option String := none
  thinkingLevel : LeanAgent.AI.ModelThinkingLevel := .level defaultThinkingLevel
  useDefaultTools : Bool := true

namespace AgentSession

/-- Create an AgentSession with default coding tools and optional durable session. -/
def create (options : CreateOptions) : IO AgentSession := do
  let tools :=
    if options.useDefaultTools then
      LeanAgent.CodingTools.defaultAgentTools options.cwd
    else
      options.agentOptions.initialState.tools
  let agentOpts : AgentOptions :=
    { options.agentOptions with
      initialState :=
        { options.agentOptions.initialState with
          tools := tools
          thinkingLevel := options.thinkingLevel
        }
    }
  let mut harness := AgentHarness.create agentOpts
  harness ← harness.setThinkingLevel options.thinkingLevel
  let bus ← createEventBus
  match options.sessionManager with
  | none =>
      pure
        { harness := harness
          eventBus := bus
          cwd := options.cwd
          thinkingLevel := options.thinkingLevel
        }
  | some sm =>
      let (sessMeta, tree) ← SessionManager.createSession sm options.sessionId
      pure
        { harness := harness
          eventBus := bus
          sessionManager := some sm
          sessionMeta := some sessMeta
          sessionTree := some tree
          cwd := options.cwd
          thinkingLevel := options.thinkingLevel
        }

def subscribe
    (s : AgentSession)
    (channel : String)
    (handler : EventBus.Handler) : IO (IO Unit) :=
  s.eventBus.on channel handler

/-- Prompt the harness and optionally persist the new user/assistant messages. -/
def prompt (s : AgentSession) (text : String) : IO AgentSession := do
  s.eventBus.emit "prompt" (LeanAgent.Json.obj [("text", LeanAgent.Json.str text)])
  let before := s.harness.agent.state.messages.size
  let harness ← s.harness.prompt text
  let afterMsgs := harness.agent.state.messages
  let mut s := { s with harness := harness }
  match s.sessionMeta, s.sessionTree with
  | some sessMeta, some tree =>
      let mut tree := tree
      -- Persist messages newly appended by this prompt turn.
      let mut i := before
      while i < afterMsgs.size do
        tree ← SessionManager.appendMessage sessMeta tree afterMsgs[i]!









        i := i + 1
      s := { s with sessionTree := some tree }
  | _, _ => pure ()
  s.eventBus.emit "prompt_done"
    (LeanAgent.Json.obj
      [ ("messageCount", LeanAgent.Json.nat afterMsgs.size) ])
  pure s

/-- Offline compact (summary text provided; no live LLM). -/
def compact
    (s : AgentSession)
    (summary : String)
    (settings : Compaction.CompactionSettings := Compaction.DEFAULT_COMPACTION_SETTINGS) :
    IO AgentSession := do
  s.eventBus.emit "compact" (LeanAgent.Json.obj [("summary", LeanAgent.Json.str summary)])
  let harness ← s.harness.compact summary settings
  pure { s with harness := harness }

def getMessages (s : AgentSession) : Array LeanAgent.Agent.AgentMessage :=
  s.harness.agent.state.messages

def getThinkingLevel (s : AgentSession) : LeanAgent.AI.ModelThinkingLevel :=
  s.thinkingLevel

def setThinkingLevel
    (s : AgentSession)
    (level : LeanAgent.AI.ModelThinkingLevel) : IO AgentSession := do
  let harness ← s.harness.setThinkingLevel level
  pure { s with harness := harness, thinkingLevel := level }

def getModel (s : AgentSession) : LeanAgent.Models.ModelInfo :=
  s.harness.getModel

def setModel (s : AgentSession) (model : LeanAgent.Models.ModelInfo) : IO AgentSession := do
  let harness ← s.harness.setModel model
  pure { s with harness := harness }

def abort (s : AgentSession) : IO AgentSession := do
  let harness ← s.harness.abort
  pure { s with harness := harness }

def waitForIdle (s : AgentSession) : IO Unit :=
  s.harness.waitForIdle

def executeBash (s : AgentSession) (cmd : String) : IO AgentSession := do
  let tools := s.harness.agent.state.tools
  match tools.find? (fun t => t.name == "bash") with
  | none => pure s
  | some bashTool =>
      let result ← bashTool.execute "bash-1" (LeanAgent.Json.obj [("command", LeanAgent.Json.str cmd)]) none none
      let ts ← IO.monoMsNow
      let msg : LeanAgent.Agent.AgentMessage := .custom "bashExecution" result.content false ts
      let harness ← s.harness.appendMessage msg
      pure { s with harness := harness }


end AgentSession
end LeanAgent.CodingAgent.AgentSession
