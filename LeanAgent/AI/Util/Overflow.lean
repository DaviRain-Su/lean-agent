import LeanAgent.AI.Types

namespace LeanAgent.AI.Util.Overflow

def overflowPatterns : List String :=
  [ "prompt is too long"
  , "request_too_large"
  , "input is too long for requested model"
  , "exceeds the context window"
  , "exceeds the maximum context length"
  , "exceeds the model's maximum context length"
  , "exceeds the models maximum context length"
  , "exceeds model's maximum context length"
  , "exceeds models maximum context length"
  , "maximum prompt length is"
  , "reduce the length of the messages"
  , "maximum context length is"
  , "exceeds the maximum allowed input length"
  , "longer than the model's context length"
  , "longer than the models context length"
  , "exceeds the limit of"
  , "exceeds the available context size"
  , "greater than the context length"
  , "context window exceeds limit"
  , "exceeded model token limit"
  , "too large for model with"
  , "maximum context length"
  , "model_context_window_exceeded"
  , "prompt too long; exceeded max context length"
  , "prompt too long; exceeded context length"
  , "context_length_exceeded"
  , "context length exceeded"
  , "too many tokens"
  , "token limit exceeded"
  , "400 status code (no body)"
  , "413 status code (no body)"
  , "400 (no body)"
  , "413 (no body)"
  ]

def nonOverflowPatterns : List String :=
  [ "throttling error:"
  , "service unavailable:"
  , "rate limit"
  , "too many requests"
  ]

def containsAny (message : String) (patterns : List String) : Bool :=
  let lower := message.toLower
  patterns.any fun pattern => lower.contains pattern

def compactOverflowText (value : String) : String :=
  String.ofList <|
    value.toLower.toList.filter fun char =>
      char.isAlphanum

def containsAnyCompact (message : String) (patterns : List String) : Bool :=
  let compactMessage := compactOverflowText message
  patterns.any fun pattern => compactMessage.contains (compactOverflowText pattern)

def looksLikeInputCountOverflow (message : String) : Bool :=
  let lower := message.toLower
  lower.contains "input token count" && lower.contains "exceeds the maximum"

def isOverflowErrorMessage (message : String) : Bool :=
  !(containsAny message nonOverflowPatterns ||
      containsAnyCompact message nonOverflowPatterns) &&
    (containsAny message overflowPatterns ||
      containsAnyCompact message overflowPatterns ||
      looksLikeInputCountOverflow message)

def inputTokens (usage : Usage) : Nat :=
  usage.input + usage.cacheRead

def fillsContextWindow (tokens contextWindow : Nat) : Bool :=
  tokens * 100 >= contextWindow * 99

def isContextOverflow (message : AssistantMessage) (contextWindow : Option Nat := none) : Bool :=
  match message.stopReason, message.errorMessage with
  | .error, some errorMessage =>
      isOverflowErrorMessage errorMessage
  | .stop, _ =>
      match contextWindow with
      | some window => window > 0 && inputTokens message.usage > window
      | none => false
  | .length, _ =>
      match contextWindow with
      | some window =>
          window > 0 && message.usage.output == 0 && fillsContextWindow (inputTokens message.usage) window
      | none => false
  | _, _ => false

def getOverflowPatterns : List String :=
  overflowPatterns

end LeanAgent.AI.Util.Overflow
