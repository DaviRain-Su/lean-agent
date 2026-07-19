import Lean
import LeanAgent.Agent.Types
import LeanAgent.Agent.Harness.Compaction
import LeanAgent.CodingAgent.Messages
import LeanAgent.Agent.Harness.Storage

/-!
# Coding-agent compaction façade (Pi `core/compaction/*` subset)

Reuses harness Compaction + coding-agent Messages summary prefixes.
-/

namespace LeanAgent.CodingAgent.Compaction

open LeanAgent.Agent
open LeanAgent.Agent.Harness.Compaction
open LeanAgent.Agent.Harness.Storage
open LeanAgent.CodingAgent.Messages

structure CompactResult where
  messages : Array LeanAgent.Agent.AgentMessage
  summary : String
  tokensBefore : Nat
  cutIndex : Nat
deriving Inhabited

/-- Offline compact using coding-agent summary formatting. -/
def compact
    (messages : Array LeanAgent.Agent.AgentMessage)
    (summary : String)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) :
    IO CompactResult := do
  let prep := prepareCompaction messages settings
  let ts ← IO.monoMsNow
  let summaryMsg :=
    LeanAgent.CodingAgent.Messages.createCompactionSummaryMessage
      summary prep.tokensBefore ts
  pure
    { messages := #[summaryMsg] ++ prep.keptMessages
      summary := summary
      tokensBefore := prep.tokensBefore
      cutIndex := prep.cutIndex
    }

def shouldCompact
    (messages : Array LeanAgent.Agent.AgentMessage)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) : Bool :=
  LeanAgent.Agent.Harness.Compaction.shouldCompact messages settings

/-- Branch summary using coding-agent message format. -/
def branchSummary
    (tree : SessionTree)
    (leafId : String)
    (summary : String) : IO (LeanAgent.Agent.AgentMessage × Array SessionEntry) := do
  let entries := collectEntriesForBranchSummary tree leafId
  let ts ← IO.monoMsNow
  pure
    ( LeanAgent.CodingAgent.Messages.createBranchSummaryMessage summary leafId ts
    , entries
    )

end LeanAgent.CodingAgent.Compaction
