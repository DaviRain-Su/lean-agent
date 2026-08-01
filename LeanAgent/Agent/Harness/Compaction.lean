import Lean
import LeanAgent.Agent.Types
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Estimate
import LeanAgent.Agent.Harness.Storage
import LeanAgent.Agent.Harness.Session
import LeanAgent.Agent.Harness.Messages

/-!
# Harness Compaction (Pi `harness/compaction/compaction.ts` subset)

Offline compaction pipeline: token estimation, threshold check, window
selection, summary building, and session application. Mirrors Pi
`CompactionSettings`, `estimateTokens`, `shouldCompact`, `prepareCompaction`,
and `compact` without the live-LLM summarization path.
-/

namespace LeanAgent.Agent.Harness.Compaction

open LeanAgent.Agent
open LeanAgent.Agent.Harness.Storage
open LeanAgent.Agent.Harness.Session
open LeanAgent.AI

/-- Pi `CompactionSettings`: thresholds and retention settings. -/
structure CompactionSettings where
  /-- Enable automatic compaction decisions (Pi `enabled`). -/
  enabled : Bool := true
  /-- Tokens reserved for summary prompt and output (Pi `reserveTokens`). -/
  reserveTokens : Nat := 16384
  /-- Approximate recent-context tokens to keep after compaction (Pi `keepRecentTokens`). -/
  keepRecentTokens : Nat := 20000
  /-- Maximum messages before compaction triggers (offline heuristic). -/
  maxMessages : Nat := 100
  /-- Maximum estimated tokens before compaction triggers (offline heuristic). -/
  maxTokens : Nat := 100000
  /-- Fraction of maxTokens at which compaction triggers, in thousandths (800 = 80%). -/
  compactionThreshold : Nat := 800

/-- Pi `DEFAULT_COMPACTION_SETTINGS`. -/
def DEFAULT_COMPACTION_SETTINGS : CompactionSettings := {}

/-- Pi `ESTIMATED_IMAGE_CHARS`. -/
def estimatedImageChars : Nat := 4800

/-- Pi `charsPerToken` (character-to-token heuristic divisor). -/
def charsPerToken : Nat := 4

/-- Ceiling division. -/
def ceilDiv (value divisor : Nat) : Nat :=
  if value == 0 then 0
  else (value + divisor - 1) / divisor

/-- Estimate character count of a content block array (Pi `estimateTextAndImageContentChars`). -/
def estimateContentChars (content : Array ContentBlock) : Nat :=
  content.foldl (init := 0) fun acc block =>
    match block with
    | .text t => acc + LeanAgent.AI.Util.Estimate.textChars t.text
    | .thinking t => acc + LeanAgent.AI.Util.Estimate.textChars t.thinking
    | .image _ => acc + estimatedImageChars
    | .toolCall call => acc + LeanAgent.AI.Util.Estimate.textChars call.name
        + LeanAgent.AI.Util.Estimate.textChars call.arguments.compress

/--
Pi `estimateTokens`: estimate token count for a single `AgentMessage`
using a conservative character heuristic (chars / 4).
-/
def estimateTokenCountSingle (message : AgentMessage) : Nat :=
  let chars :=
    match message with
    | .ofMessage (.user m) => estimateContentChars m.content
    | .ofMessage (.assistant m) => estimateContentChars m.content
    | .ofMessage (.toolResult m) => estimateContentChars m.content
    | .custom _ content _ _ => estimateContentChars content
  ceilDiv chars charsPerToken

/--
Estimate total token count for an array of messages (chars/4 heuristic).
This is the offline-friendly version of Pi's `estimateContextTokens`.
-/
def estimateTokenCount (messages : Array AgentMessage) : Nat :=
  messages.foldl (init := 0) fun acc msg =>
    acc + estimateTokenCountSingle msg

/--
Pi `shouldCompact`: return whether context usage exceeds the configured
compaction threshold. Checks both token estimate and message count.
-/
def shouldCompact
    (messages : Array AgentMessage)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) : Bool :=
  if !settings.enabled then false
  else
    let tokens := estimateTokenCount messages
    let tokenThreshold := settings.maxTokens * settings.compactionThreshold / 1000
    tokens >= tokenThreshold || messages.size >= settings.maxMessages

/-- Pi `findValidCutPoints`: indices where the cut can start (user/assistant/custom messages). -/
partial def findValidCutPoints (messages : Array AgentMessage) : Array Nat :=
  let rec go (i : Nat) (acc : Array Nat) : Array Nat :=
    if i >= messages.size then acc
    else
      let acc' :=
        match messages[i]! with
        | .ofMessage (.user _) => acc.push i
        | .ofMessage (.assistant _) => acc.push i
        | .custom _ _ _ _ => acc.push i
        | _ => acc
      go (i + 1) acc'
  go 0 #[]

/--
Pi `findTurnStartIndex`: find the user-visible message that starts the turn
containing an entry. Walks backwards from the cut point to the nearest
user or custom message.
-/
partial def findTurnStartIndex (messages : Array AgentMessage) (entryIndex : Nat) (startIndex : Nat) : Nat :=
  let rec go (i : Nat) : Nat :=
    if i < startIndex then startIndex
    else if i >= messages.size then startIndex
    else
      match messages[i]? with
      | some (.ofMessage (.user _)) => i
      | some (.custom _ _ _ _) => i
      | _ =>
        if i == 0 then 0 else go (i - 1)
  go entryIndex

/-- Pi `CutPointResult`: the cut point selected for compaction. -/
structure CutPointResult where
  firstKeptEntryIndex : Nat
  turnStartIndex : Nat
  isSplitTurn : Bool
deriving Inhabited

/--
Pi `findCutPoint`: find the compaction cut point that keeps approximately
the requested recent-token budget. Walks backwards accumulating tokens
until the budget is met, then aligns to a valid cut point.
-/
partial def findCutPoint
    (messages : Array AgentMessage)
    (startIndex : Nat)
    (endIndex : Nat)
    (keepRecentTokens : Nat) : CutPointResult :=
  let cutPoints := findValidCutPoints messages
  if cutPoints.isEmpty then
    { firstKeptEntryIndex := startIndex, turnStartIndex := 0, isSplitTurn := false }
  else
    let rec accumulate (i : Nat) (acc : Nat) (cutIdx : Nat) : Nat :=
      if i < startIndex || i >= endIndex then cutIdx
      else
        match messages[i]? with
        | some msg =>
            let newAcc := acc + estimateTokenCountSingle msg
            if newAcc >= keepRecentTokens then
              cutPoints.find? (fun cp => cp >= i) |>.getD cutIdx
            else
              if i == 0 then cutIdx else accumulate (i - 1) newAcc cutIdx
        | none => cutIdx
    let cutIdx := accumulate (endIndex - 1) 0 cutPoints[0]!
    let rec alignBack (idx : Nat) : Nat :=
      if idx <= startIndex then idx
      else
        match messages[idx - 1]? with
        | some (.ofMessage _) => idx
        | some (.custom _ _ _ _) => idx
        | _ => alignBack (idx - 1)
    let cutIdx := alignBack cutIdx
    let isUser :=
      match messages[cutIdx]? with
      | some (.ofMessage (.user _)) => true
      | _ => false
    let turnStart := if isUser then 0 else findTurnStartIndex messages cutIdx startIndex
    { firstKeptEntryIndex := cutIdx
      turnStartIndex := turnStart
      isSplitTurn := !isUser && turnStart != 0
    }

/--
Select the compaction window: returns `(keptMessages, compactedMessages)`
split at the cut point determined by the settings.
-/
def selectCompactionWindow
    (messages : Array AgentMessage)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) :
    Array AgentMessage × Array AgentMessage :=
  let cut := findCutPoint messages 0 messages.size settings.keepRecentTokens
  let compacted := messages.extract 0 cut.firstKeptEntryIndex
  let kept := messages.extract cut.firstKeptEntryIndex messages.size
  (kept, compacted)

/--
Build a compaction summary string from compacted messages.
This is an offline heuristic that serializes message roles and text content
(Pi uses an LLM call via `generateSummary`; this offline version concatenates
the essential text for testing and storage).
-/
def buildCompactionSummary (compactedMessages : Array AgentMessage) : String :=
  if compactedMessages.isEmpty then
    "No prior history."
  else
    let parts := compactedMessages.map fun msg =>
      let role := msg.role
      let text :=
        match msg with
        | .ofMessage (.user m) => LeanAgent.AI.contentPlainText m.content
        | .ofMessage (.assistant m) => LeanAgent.AI.contentPlainText m.content
        | .ofMessage (.toolResult m) => LeanAgent.AI.contentPlainText m.content
        | .custom _ content _ _ => LeanAgent.AI.contentPlainText content
      s!"[{role}] {text}"
    String.intercalate "\n" parts.toList

/-- Pi `CompactionResult`: generated compaction data ready to persist. -/
structure CompactionResult where
  /-- Summary text that replaces compacted history in future context. -/
  summary : String
  /-- Messages kept after compaction (recent context). -/
  keptMessages : Array AgentMessage
  /-- Messages that were compacted away. -/
  compactedMessages : Array AgentMessage
  /-- Estimated context tokens before compaction. -/
  tokensBefore : Nat
  /-- Cut index where retained history starts. -/
  cutIndex : Nat
deriving Inhabited

/--
Full compaction pipeline: check shouldCompact, select window, build summary,
return `CompactionResult`. Returns `none` when compaction is not applicable
(messages don't exceed thresholds).
-/
def prepareCompactionAuto
    (messages : Array AgentMessage)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) :
    Option CompactionResult :=
  if !shouldCompact messages settings then none
  else
    let (kept, compacted) := selectCompactionWindow messages settings
    if compacted.isEmpty then none
    else
      let tokensBefore := estimateTokenCount messages
      let summary := buildCompactionSummary compacted
      some
        { summary := summary
          keptMessages := kept
          compactedMessages := compacted
          tokensBefore := tokensBefore
          cutIndex := messages.size - kept.size
        }

/-- Build a compaction summary AgentMessage (custom type). -/
def createCompactionSummaryMessage (summary : String) (tokensBefore : Nat) (timestamp : Nat) :
    AgentMessage :=
  .custom
    "compactionSummary"
    #[.text { text := summary }]
    true
    timestamp

/--
Offline compact: apply compaction to an array of messages using the full
pipeline. Returns the compacted message array (summary + kept suffix),
or the original array if compaction was not triggered.
-/
def compact
    (messages : Array AgentMessage)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) :
    IO (Array AgentMessage) := do
  match prepareCompactionAuto messages settings with
  | none => pure messages
  | some result =>
    let ts ← IO.monoMsNow
    let summaryMsg := createCompactionSummaryMessage result.summary result.tokensBefore ts
    pure (#[summaryMsg] ++ result.keptMessages)

/--
Apply compaction to a `Session`: appends a compaction entry and returns
the updated session + CompactionResult. If compaction is not triggered,
returns the original session unchanged.
-/
def compactSession
    (session : Session)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) :
    IO (Session × Option CompactionResult) := do
  let messages ← session.getBranchMessages
  match prepareCompactionAuto messages settings with
  | none => pure (session, none)
  | some result =>
    let _ ← session.appendCompaction result.summary (some result.summary)
    pure (session, some result)

structure PrepareCompactionResult where
  cutIndex : Nat
  keptMessages : Array AgentMessage
  compactedMessages : Array AgentMessage
  tokensBefore : Nat
deriving Inhabited

/-- Legacy: find a cut index so the suffix has at least `keepLast` messages. -/
def findCutPointSimple (messageCount : Nat) (keepLast : Nat) : Nat :=
  if messageCount <= keepLast then 0
  else messageCount - keepLast

/-- Legacy: prefer cutting at a turn boundary (user or toolResult after assistant). -/
partial def findTurnStartIndexSimple (messages : Array AgentMessage) (preferredCut : Nat) : Nat :=
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

/-- Prepare a compaction cut (message-count-based, backward-compatible). -/
def prepareCompaction
    (messages : Array AgentMessage)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) : PrepareCompactionResult :=
  let preferred := findCutPointSimple messages.size settings.maxMessages
  let cut := findTurnStartIndexSimple messages preferred
  let compacted := messages.extract 0 cut
  let kept := messages.extract cut messages.size
  { cutIndex := cut
    keptMessages := kept
    compactedMessages := compacted
    tokensBefore := estimateTokenCount messages
  }

/-- Backward-compatible compact with explicit summary text (offline test path). -/
def compactWithSummary
    (messages : Array AgentMessage)
    (summary : String)
    (settings : CompactionSettings := DEFAULT_COMPACTION_SETTINGS) :
    IO (Array AgentMessage) := do
  let prep := LeanAgent.Agent.Harness.Compaction.prepareCompaction messages settings
  let tokensBefore := estimateTokenCount messages
  let ts ← IO.monoMsNow
  let summaryMsg := createCompactionSummaryMessage summary tokensBefore ts
  pure (#[summaryMsg] ++ prep.keptMessages)

-- Legacy helpers retained for backward compatibility with existing callers.

/-- Legacy: estimate tokens for agent messages via AI estimate helpers on plain text. -/
def estimateMessageTokens (messages : Array AgentMessage) : Nat :=
  estimateTokenCount messages


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