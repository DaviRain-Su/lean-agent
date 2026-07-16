import Lean
import LeanAgent.Agent.Types
import LeanAgent.Agent.Agent
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Abort
import LeanAgent.Agent.Harness.SystemPrompt
import LeanAgent.Agent.Harness.Storage

namespace LeanAgent.Agent.Harness

open LeanAgent.Agent
open LeanAgent.Agent.Harness.SystemPrompt
open LeanAgent.Agent.Harness.Storage

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

/--
High-level façade over `Agent` (Pi AgentHarness subset): owns an Agent, next-turn
queue, system prompt / tools, and emits queue updates on steer/followUp/nextTurn.
-/
structure AgentHarness where
  agent : Agent
  nextTurnQueue : Array AgentMessage := #[]
  listeners : Array HarnessEventSink := #[]
  skills : Array SkillInfo := #[]

namespace AgentHarness

def create
    (options : AgentOptions := default)
    (skills : Array SkillInfo := #[]) : AgentHarness :=
  { agent := Agent.create options
    skills := skills
  }

def subscribe (h : AgentHarness) (listener : HarnessEventSink) : AgentHarness :=
  { h with listeners := h.listeners.push listener }

def emit (h : AgentHarness) (event : HarnessEvent) : IO Unit := do
  for listener in h.listeners do
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

/-- Persist harness transcript into a SessionTree (memory). -/
def toSessionTree (h : AgentHarness) (sessionId : String) : IO SessionTree := do
  let mut tree := SessionTree.empty sessionId
  for msg in h.agent.state.messages do
    tree ← tree.append msg
  pure tree

end AgentHarness

end LeanAgent.Agent.Harness
