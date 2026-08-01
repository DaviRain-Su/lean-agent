import Lean
import LeanAgent.Agent.Types
import LeanAgent.AI.Types

/-!
# Harness Messages (Pi `harness/messages.ts` subset)

Converts `AgentMessage` arrays to LLM-format `Message` arrays. Custom message
types (bashExecution, compactionSummary, branchSummary) are mapped to user
messages with appropriate text content, mirroring Pi `convertToLlm`.
-/

namespace LeanAgent.Agent.Harness.Messages

open LeanAgent.Agent
open LeanAgent.AI

/-- Pi `COMPACTION_SUMMARY_PREFIX`. -/
def compactionSummaryPrefix : String :=
  "The conversation history before this point was compacted into the following summary:\n\n<summary>\n"

/-- Pi `COMPACTION_SUMMARY_SUFFIX`. -/
def compactionSummarySuffix : String :=
  "\n</summary>"

/-- Pi `BRANCH_SUMMARY_PREFIX`. -/
def branchSummaryPrefix : String :=
  "The following is a summary of a branch that this conversation came back from:\n\n<summary>\n"

/-- Pi `BRANCH_SUMMARY_SUFFIX`. -/
def branchSummarySuffix : String :=
  "</summary>"

/-- Pi `bashExecutionToText`: format a bash execution custom message as readable text. -/
def bashExecutionToText (command : String) (output : String) (cancelled : Bool) (exitCode : Option Int) :
    String :=
  let text0 := s!"Ran `{command}`\n"
  let text1 :=
    if !output.isEmpty then
      text0 ++ s!"```\n{output}\n```"
    else
      text0 ++ "(no output)"
  let text2 :=
    if cancelled then
      text1 ++ "\n\n(command cancelled)"
    else
      match exitCode with
      | some code => if code != 0 then text1 ++ s!"\n\nCommand exited with code {code}" else text1
      | none => text1
  text2

/-- Extract text from an AgentMessage's content blocks (helper). -/
private def contentToText (content : Array ContentBlock) : String :=
  String.intercalate "" (content.toList.filterMap fun block =>
    match block with
    | .text t => some t.text
    | _ => none)

/--
Pi `convertToLlm`: convert `AgentMessage` array to LLM-format `Message` array.
Strip custom message types, map user/assistant/toolResult directly, and convert
compactionSummary/branchSummary/custom into user messages with prefixed text.
-/
def convertToLlm (messages : Array AgentMessage) : Array Message :=
  messages.filterMap fun msg =>
    match msg with
    | .ofMessage m => some m
    | .custom customType content _ ts =>
      -- Map custom messages to user messages, matching Pi convertToLlm behavior.
      match customType with
      | "compactionSummary" =>
        let text := contentToText content
        some (.user
          { content := #[.text { text := compactionSummaryPrefix ++ text ++ compactionSummarySuffix }]
            timestamp := ts
          })
      | "branchSummary" =>
        let text := contentToText content
        some (.user
          { content := #[.text { text := branchSummaryPrefix ++ text ++ branchSummarySuffix }]
            timestamp := ts
          })
      | "bashExecution" =>
        -- bashExecution custom messages are mapped to user messages with text content.
        let text := contentToText content
        some (.user
          { content := #[.text { text := text }]
            timestamp := ts
          })
      | _ =>
        -- Other custom types: map to user message (Pi returns user message for "custom" role).
        some (.user
          { content := content
            timestamp := ts
          })

end LeanAgent.Agent.Harness.Messages