import LeanAgent.AI.Types

namespace LeanAgent.AI.Util.Retry

structure Policy where
  maxRetries : Nat := 0
  maxRetryDelayMs : Nat := 2000
deriving Repr, BEq

def Policy.fromOptions (maxRetries maxRetryDelayMs : Option Nat) : Policy :=
  { maxRetries := maxRetries.getD 0
    maxRetryDelayMs := maxRetryDelayMs.getD 2000
  }

def containsAny (message : String) (patterns : List String) : Bool :=
  let lower := message.toLower
  patterns.any fun pattern => lower.contains pattern

def nonRetryableProviderLimitPatterns : List String :=
  [ "gousagelimiterror"
  , "freeusagelimiterror"
  , "monthly usage limit reached"
  , "available balance"
  , "insufficient_quota"
  , "out of budget"
  , "quota exceeded"
  , "billing"
  ]

def retryableProviderErrorPatterns : List String :=
  [ "overloaded"
  , "rate limit"
  , "ratelimit"
  , "rate-limit"
  , "too many requests"
  , "429"
  , "500"
  , "502"
  , "503"
  , "504"
  , "service unavailable"
  , "service-unavailable"
  , "server error"
  , "server-error"
  , "internal error"
  , "internal-error"
  , "provider returned error"
  , "network error"
  , "connection error"
  , "connection refused"
  , "connection lost"
  , "other side closed"
  , "fetch failed"
  , "upstream connect"
  , "reset before headers"
  , "socket hang up"
  , "timed out"
  , "timedout"
  , "timeout"
  , "terminated"
  , "websocket closed"
  , "websocket error"
  , "ended without"
  , "stream ended before message_stop"
  , "http2 request did not get a response"
  , "retry delay"
  , "you can retry your request"
  , "try your request again"
  , "please retry your request"
  ]

def isRetryableErrorMessage (message : String) : Bool :=
  !containsAny message nonRetryableProviderLimitPatterns &&
    containsAny message retryableProviderErrorPatterns

def isRetryableAssistantError (message : AssistantMessage) : Bool :=
  message.stopReason == .error &&
    match message.errorMessage with
    | some errorMessage => isRetryableErrorMessage errorMessage
    | none => false

def retryDelayMs (policy : Policy) (attempt : Nat) : Nat :=
  min policy.maxRetryDelayMs (250 * attempt)

partial def withRetries {α : Type} (policy : Policy) (action : IO α) : IO α := do
  let rec loop (attempt : Nat) : IO α := do
    try
      action
    catch err =>
      if attempt < policy.maxRetries && isRetryableErrorMessage err.toString then
        let delay := retryDelayMs policy (attempt + 1)
        if delay > 0 then
          IO.sleep (UInt32.ofNat delay)
        loop (attempt + 1)
      else
        throw err
  loop 0

end LeanAgent.AI.Util.Retry
