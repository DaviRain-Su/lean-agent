import LeanAgent.AI.Types
import LeanAgent.AI.Util.Estimate

namespace LeanAgent.AI.Api.SimpleOptions

def contextSafetyTokens : Nat := 4096
def minMaxTokens : Nat := 1
def minOutputTokens : Nat := 1024

def clampMaxTokensToContext (contextWindow : Nat) (context : LeanAgent.AI.Context) (maxTokens : Nat) : Nat :=
  if contextWindow == 0 then
    Nat.max minMaxTokens maxTokens
  else
    let estimate := LeanAgent.AI.Util.Estimate.estimateContextTokens context
    let reserved := estimate.tokens + contextSafetyTokens
    let available := if contextWindow > reserved then contextWindow - reserved else 0
    Nat.min maxTokens (Nat.max minMaxTokens available)

def resolvedMaxTokens?
    (contextWindow modelMaxTokens : Nat)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions) : Option Nat :=
  match options.maxTokens with
  | some maxTokens => some (clampMaxTokensToContext contextWindow context maxTokens)
  | none =>
      if modelMaxTokens == 0 then
        none
      else
        some (clampMaxTokensToContext contextWindow context modelMaxTokens)

def clampStreamOptionsToContext
    (contextWindow modelMaxTokens : Nat)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions) : LeanAgent.AI.SimpleStreamOptions :=
  { options with maxTokens := resolvedMaxTokens? contextWindow modelMaxTokens context options }

def clampReasoning : LeanAgent.AI.ThinkingLevel → LeanAgent.AI.ThinkingLevel
  | .xhigh => .high
  | level => level

def defaultThinkingBudget : LeanAgent.AI.ThinkingLevel → Nat
  | .minimal => 1024
  | .low => 2048
  | .medium => 8192
  | .high => 16384
  | .xhigh => 16384

def customThinkingBudget? (budgets : LeanAgent.AI.ThinkingBudgets) :
    LeanAgent.AI.ThinkingLevel → Option Nat
  | .minimal => budgets.minimal
  | .low => budgets.low
  | .medium => budgets.medium
  | .high => budgets.high
  | .xhigh => budgets.high

def thinkingBudgetD
    (customBudgets : Option LeanAgent.AI.ThinkingBudgets)
    (level : LeanAgent.AI.ThinkingLevel) : Nat :=
  let level := clampReasoning level
  match customBudgets.bind (fun budgets => customThinkingBudget? budgets level) with
  | some budget => budget
  | none => defaultThinkingBudget level

structure ThinkingTokenAdjustment where
  maxTokens : Nat
  thinkingBudget : Nat
deriving BEq

def adjustMaxTokensForThinking
    (baseMaxTokens : Option Nat)
    (modelMaxTokens : Nat)
    (reasoningLevel : LeanAgent.AI.ThinkingLevel)
    (customBudgets : Option LeanAgent.AI.ThinkingBudgets := none) : ThinkingTokenAdjustment :=
  let thinkingBudget := thinkingBudgetD customBudgets reasoningLevel
  let maxTokens :=
    match baseMaxTokens with
    | none => modelMaxTokens
    | some base => Nat.min (base + thinkingBudget) modelMaxTokens
  let thinkingBudget :=
    if maxTokens <= thinkingBudget then
      maxTokens - minOutputTokens
    else
      thinkingBudget
  { maxTokens := maxTokens, thinkingBudget := thinkingBudget }

end LeanAgent.AI.Api.SimpleOptions
