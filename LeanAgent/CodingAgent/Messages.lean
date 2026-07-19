import Lean
import LeanAgent.Agent.Types
import LeanAgent.AI.Types

/-!
# Coding-agent custom messages (Pi `packages/coding-agent/src/core/messages.ts` subset)
-/

namespace LeanAgent.CodingAgent.Messages

/-- Pi `COMPACTION_SUMMARY_PREFIX`. -/
def compactionSummaryPrefix : String :=
  "The conversation history before this point was compacted into the following summary:\n\n<summary>\n"

/-- Pi `COMPACTION_SUMMARY_SUFFIX`. -/
def compactionSummarySuffix : String := "\n</summary>"

/-- Pi `BRANCH_SUMMARY_PREFIX`. -/
def branchSummaryPrefix : String :=
  "The following is a summary of a branch that this conversation came back from:\n\n<summary>\n"

/-- Pi `BRANCH_SUMMARY_SUFFIX`. -/
def branchSummarySuffix : String := "</summary>"

structure BashExecutionMessage where
  command : String
  output : String
  exitCode : Option Nat := none
  cancelled : Bool := false
  truncated : Bool := false
  fullOutputPath : Option String := none
  timestamp : Nat := 0
  excludeFromContext : Bool := false
deriving Inhabited

/-- Format bash execution for LLM context (Pi convertBashExecution). -/
def bashExecutionToUserText (m : BashExecutionMessage) : String :=
  let status :=
    if m.cancelled then "cancelled"
    else
      match m.exitCode with
      | some c => s!"exit {c}"
      | none => "exit unknown"
  let trunc := if m.truncated then " (truncated)" else ""
  s!"Bash command: {m.command}\nStatus: {status}{trunc}\nOutput:\n{m.output}"

/-- Convert bash execution into an AgentMessage for transcript (custom type). -/
def bashExecutionToAgentMessage (m : BashExecutionMessage) : LeanAgent.Agent.AgentMessage :=
  LeanAgent.Agent.AgentMessage.custom
    "bashExecution"
    #[.text { text := bashExecutionToUserText m }]
    (!m.excludeFromContext)
    m.timestamp

/-- Pi `createCompactionSummaryMessage` (coding-agent wrapper text). -/
def createCompactionSummaryMessage
    (summary : String)
    (tokensBefore : Nat)
    (timestamp : Nat) : LeanAgent.Agent.AgentMessage :=
  LeanAgent.Agent.AgentMessage.custom
    "compactionSummary"
    #[.text
      { text :=
          compactionSummaryPrefix ++ summary ++ compactionSummarySuffix ++
            s!"\n(tokensBefore={tokensBefore})"
      }]
    true
    timestamp

/-- Pi `createBranchSummaryMessage`. -/
def createBranchSummaryMessage
    (summary : String)
    (fromId : String)
    (timestamp : Nat) : LeanAgent.Agent.AgentMessage :=
  LeanAgent.Agent.AgentMessage.custom
    "branchSummary"
    #[.text
      { text :=
          branchSummaryPrefix ++ summary ++ branchSummarySuffix ++
            s!"\n(fromId={fromId})"
      }]
    true
    timestamp

/-- Pi `createCustomMessage`. -/
def createCustomMessage
    (customType : String)
    (content : String)
    (display : Bool := true)
    (timestamp : Nat := 0) : LeanAgent.Agent.AgentMessage :=
  LeanAgent.Agent.AgentMessage.custom
    customType
    #[.text { text := content }]
    display
    timestamp

/-- Convert coding-agent custom types to LLM-facing AgentMessage text (subset). -/
def convertCustomToLlm (msg : LeanAgent.Agent.AgentMessage) : Option LeanAgent.Agent.AgentMessage :=
  match msg with
  | .custom "bashExecution" content display ts =>
      if display then
        some (.ofMessage (.user { content := content, timestamp := ts }))
      else
        none
  | .custom "compactionSummary" content _ ts =>
      some (.ofMessage (.user { content := content, timestamp := ts }))
  | .custom "branchSummary" content _ ts =>
      some (.ofMessage (.user { content := content, timestamp := ts }))
  | .custom _ content display ts =>
      if display then
        some (.ofMessage (.user { content := content, timestamp := ts }))
      else
        none
  | other => some other

end LeanAgent.CodingAgent.Messages
