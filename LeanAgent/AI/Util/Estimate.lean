import LeanAgent.AI.Types
import LeanAgent.AI.Util.Hash
import LeanAgent.Json

namespace LeanAgent.AI.Util.Estimate

structure ContextUsageEstimate where
  tokens : Nat
  usageTokens : Nat
  trailingTokens : Nat
  lastUsageIndex : Option Nat
deriving BEq

def charsPerToken : Nat := 4
def estimatedImageChars : Nat := 4800

def calculateContextTokens (usage : Usage) : Nat :=
  if usage.totalTokens > 0 then
    usage.totalTokens
  else
    usage.input + usage.output + usage.cacheRead + usage.cacheWrite

def textChars (text : String) : Nat :=
  LeanAgent.AI.Util.Hash.utf16Units text |>.length

def ceilDiv (value divisor : Nat) : Nat :=
  if value == 0 then
    0
  else
    (value + divisor - 1) / divisor

def estimateTextTokens (text : String) : Nat :=
  ceilDiv (textChars text) charsPerToken

def contentBlockChars : ContentBlock → Nat
  | .text content => textChars content.text
  | .thinking content => textChars content.thinking
  | .image _ => estimatedImageChars
  | .toolCall call => textChars call.name + textChars call.arguments.compress

def estimateContentChars (content : Array ContentBlock) : Nat :=
  content.foldl (fun total block => total + contentBlockChars block) 0

def estimateContentTokens (content : Array ContentBlock) : Nat :=
  ceilDiv (estimateContentChars content) charsPerToken

def estimateMessageTokens : Message → Nat
  | .user message => estimateContentTokens message.content
  | .toolResult message => estimateContentTokens message.content
  | .assistant message => estimateContentTokens message.content

def assistantUsageInfo? (message : Message) : Option Usage :=
  match message with
  | .assistant assistant =>
      if assistant.stopReason == .aborted || assistant.stopReason == .error then
        none
      else if calculateContextTokens assistant.usage > 0 then
        some assistant.usage
      else
        none
  | _ => none

def getLastAssistantUsageInfo? (messages : Array Message) : Option (Usage × Nat) :=
  let rec loop (remaining : List Message) (index : Nat) (last : Option (Usage × Nat)) :
      Option (Usage × Nat) :=
    match remaining with
    | [] => last
    | message :: rest =>
        let next :=
          match assistantUsageInfo? message with
          | some usage => some (usage, index)
          | none => last
        loop rest (index + 1) next
  loop messages.toList 0 none

def estimateMessages (messages : Array Message) : ContextUsageEstimate :=
  match getLastAssistantUsageInfo? messages with
  | some (usage, index) =>
      let usageTokens := calculateContextTokens usage
      let trailing := messages.extract (index + 1) messages.size
      let trailingTokens := trailing.foldl (fun total message => total + estimateMessageTokens message) 0
      { tokens := usageTokens + trailingTokens
        usageTokens := usageTokens
        trailingTokens := trailingTokens
        lastUsageIndex := some index
      }
  | none =>
      let tokens := messages.foldl (fun total message => total + estimateMessageTokens message) 0
      { tokens := tokens
        usageTokens := 0
        trailingTokens := tokens
        lastUsageIndex := none
      }

def toolToJson (tool : Tool) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("name", LeanAgent.Json.str tool.name)
    , ("description", LeanAgent.Json.str tool.description)
    , ("parameters", tool.parameters)
    ]

def estimateToolsTokens (tools : Array Tool) : Nat :=
  if tools.isEmpty then
    0
  else
    estimateTextTokens (LeanAgent.Json.arr (tools.map toolToJson)).compress

def estimateContextTokens (context : Context) : ContextUsageEstimate :=
  let estimate := estimateMessages context.messages
  match estimate.lastUsageIndex with
  | some _ => estimate
  | none =>
      let prefixTokens :=
        (match context.systemPrompt with
          | some prompt => estimateTextTokens prompt
          | none => 0) + estimateToolsTokens context.tools
      { tokens := estimate.tokens + prefixTokens
        usageTokens := estimate.usageTokens
        trailingTokens := estimate.trailingTokens + prefixTokens
        lastUsageIndex := estimate.lastUsageIndex
      }

end LeanAgent.AI.Util.Estimate
