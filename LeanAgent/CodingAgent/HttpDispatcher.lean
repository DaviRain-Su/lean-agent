import Lean

/-!
# HTTP dispatcher config (Pi `packages/coding-agent/src/core/http-dispatcher.ts`)

Pure configuration for the HTTP idle-timeout: the default timeout, the
selector choices, and `parseHttpIdleTimeoutMs`/`formatHttpIdleTimeoutMs`.
`applyHttpProxySettings` sets `HTTP_PROXY`/`HTTPS_PROXY` env vars when a proxy
is configured.

The runtime `configureHttpDispatcher` installs an `undici.EnvHttpProxyAgent`
as the global dispatcher — that is a Node-only runtime concern and is deferred
(the Lean port configures timeouts through its own `LeanAgent.Http` transport).
-/

namespace LeanAgent.CodingAgent.HttpDispatcher

/-- Pi `DEFAULT_HTTP_IDLE_TIMEOUT_MS` (5 minutes). -/
def defaultHttpIdleTimeoutMs : Nat := 300000

/-- Pi `HTTP_IDLE_TIMEOUT_CHOICES` selector entries. -/
structure HttpIdleTimeoutChoice where
  label : String
  timeoutMs : Nat
deriving Inhabited, BEq, Repr

/-- Pi `HTTP_IDLE_TIMEOUT_CHOICES`. -/
def httpIdleTimeoutChoices : Array HttpIdleTimeoutChoice :=
  #[ { label := "30 sec", timeoutMs := 30000 }
   , { label := "1 min", timeoutMs := 60000 }
   , { label := "2 min", timeoutMs := 120000 }
   , { label := "5 min", timeoutMs := 300000 }
   , { label := "disabled", timeoutMs := 0 }
   ]

/--
Pi `parseHttpIdleTimeoutMs` over a string: "disabled" → 0, empty → none,
all-digits → the parsed Nat, otherwise none (Pi accepts numeric strings by
coercing through `Number(...)`; the Lean port requires clean digits because
`Number("12abc")` yields NaN, which is rejected upstream).
-/
def parseHttpIdleTimeoutMsString (s : String) : Option Nat :=
  let trimmed := s.trimAscii.toString
  let lower := trimmed.toLower
  if lower == "disabled" then some 0
  else if trimmed.isEmpty then none
  else if trimmed.toList.all Char.isDigit then some trimmed.toNat!
  else none

/--
Pi `parseHttpIdleTimeoutMs` over a `Lean.Json` value: a string is parsed via
`parseHttpIdleTimeoutMsString`; a non-negative integer is accepted; otherwise
`none` (Pi rejects NaN/negative/infinite).
-/
def parseHttpIdleTimeoutMs (value : Lean.Json) : Option Nat :=
  match value.getStr? with
  | .ok s => parseHttpIdleTimeoutMsString s
  | .error _ =>
    match value.getNat? with
    | .ok n => some n
    | .error _ => none

/-- Pi `formatHttpIdleTimeoutMs`: label for a known choice, else "<s> sec". -/
def formatHttpIdleTimeoutMs (timeoutMs : Nat) : String :=
  match httpIdleTimeoutChoices.find? (fun c => c.timeoutMs == timeoutMs) with
  | some c => c.label
  | none => s!"{timeoutMs / 1000} sec"

/--
Pi `applyHttpProxySettings`: if `httpProxy` is a non-empty (trimmed) value, set
`HTTP_PROXY`/`HTTPS_PROXY` only when not already set (Pi uses `??=`). The
caller supplies a getter/setter so this stays testable without touching the
real process env.
-/
def applyHttpProxySettings
    (httpProxy : Option String)
    (getEnv : String → IO (Option String))
    (setEnv : String → String → IO Unit) : IO Unit := do
  let proxy := httpProxy.map (·.trimAscii.toString) |>.filter (!·.isEmpty)
  match proxy with
  | none => pure ()
  | some p =>
    if (← getEnv "HTTP_PROXY").isNone then setEnv "HTTP_PROXY" p
    if (← getEnv "HTTPS_PROXY").isNone then setEnv "HTTPS_PROXY" p

end LeanAgent.CodingAgent.HttpDispatcher
