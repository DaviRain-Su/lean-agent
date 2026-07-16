import Lean
import LeanAgent.Agent.Types
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Estimate
import LeanAgent.Agent.Harness.Storage

namespace LeanAgent.Agent.Harness.Compaction

open LeanAgent.Agent
open LeanAgent.Agent.Harness.Storage

structure CompactionSettings where
  /-- Keep at least this many trailing messages after a cut. -/
  keepLastMessages : Nat := 4
  /-- Soft token budget used by shouldCompact heuristics. -/
  contextTokenBudget : Nat := 32000
deriving Inhabited

def DEFAULT_COMPACTION_SETTINGS : CompactionSettings := {}

/-- Estimate tokens for agent messages via AI estimate helpers on plain text. -/
def estimateMessageTokens (messages : Array AgentMessage) : Nat :=
  messages.foldl (init := 0) fun acc msg =>
    let text :=
      match msg with
      | .ofMessage (.user m) => LeanAgent.AI.contentPlainText m.content
      | .ofMessage (.assistant m) => LeanAgent.AI.contentPlainText m.content
      | .ofMessage (.toolResult m) => LeanAgent.AI.contentPlainText m.content
      | .custom _ content _ _ => LeanAgent.AI.contentPlainText content
    acc + LeanAgent.AI.Util.Estimate.estimateTextTokens text

/-- Find a cut index so the suffix has at least `keepLast` messages (or all). -/
def findCutPoint (messageCount : Nat) (keepLast : Nat) : Nat :=
  if messageCount <= keepLast then 0
  else messageCount - keepLast

/-- Prefer cutting at a turn boundary (user or toolResult after assistant). -/
def findTurnStartIndex (messages : Array AgentMessage) (preferredCut : Nat) : Nat :=
  if preferredCut == 0 || preferredCut >= messages.size then
    preferredCut
  else
    let rec go (fuel : Nat) (i : Nat) : Nat :=
      match fuel with
      | 0 => i
      | fuel + 1 =>
          if i == 0 then 0
          else
            match messages[i]? with
            | some (.ofMessage (.user _)) => i
            | some (.ofMessage (.toolResult _)) => i
            | _ => go fuel (i - 1)
    go (preferredCut + 1) preferredCut

structure PrepareCompactionResult where
  cutIndex : Nat
  keptMessages : Array AgentMessage
  compactedMessages : Array AgentMessage
  tokensBefore : Nat
deriving Inhabited

/-- Prepare a compaction cut without calling an LLM. -/
def prepareCompaction
    (messages : Array AgentMessage)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) : PrepareCompactionResult :=
  let preferred := findCutPoint messages.size settings.keepLastMessages
  let cut := findTurnStartIndex messages preferred
  let compacted := messages.extract 0 cut
  let kept := messages.extract cut messages.size
  { cutIndex := cut
    keptMessages := kept
    compactedMessages := compacted
    tokensBefore := estimateMessageTokens messages
  }

def shouldCompact
    (messages : Array AgentMessage)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) : Bool :=
  estimateMessageTokens messages >= settings.contextTokenBudget

/-- Build a compaction summary AgentMessage (custom type). -/
def createCompactionSummaryMessage (summary : String) (tokensBefore : Nat) (timestamp : Nat) :
    AgentMessage :=
  .custom
    "compactionSummary"
    #[.text { text := summary }]
    true
    timestamp

/-- Offline compact: use provided summary text (caller may generate via mock streamFn). -/
def compact
    (messages : Array AgentMessage)
    (summary : String)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) : IO (Array AgentMessage) := do
  let prep := prepareCompaction messages settings
  let ts ← IO.monoMsNow
  let summaryMsg := createCompactionSummaryMessage summary prep.tokensBefore ts
  pure (#[summaryMsg] ++ prep.keptMessages)

/-- Branch summary custom message. -/
def createBranchSummaryMessage (summary : String) (fromId : String) (timestamp : Nat) : AgentMessage :=
  .custom
    "branchSummary"
    #[.text { text := s!"[from {fromId}] {summary}" }]
    true
    timestamp

/-- Collect entries on a branch for summarization (Pi collectEntriesForBranchSummary subset). -/
def collectEntriesForBranchSummary (tree : SessionTree) (leafId : String) : Array SessionEntry :=
  tree.branchFrom leafId

/-- Offline branch summary: inject summary string without live LLM. -/
def generateBranchSummary
    (tree : SessionTree)
    (leafId : String)
    (summary : String) : IO (AgentMessage × Array SessionEntry) := do
  let entries := collectEntriesForBranchSummary tree leafId
  let ts ← IO.monoMsNow
  pure (createBranchSummaryMessage summary leafId ts, entries)

end LeanAgent.Agent.Harness.Compaction
