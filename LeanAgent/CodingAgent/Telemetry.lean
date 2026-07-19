import Lean

/-!
# Install telemetry gating (Pi `packages/coding-agent/src/core/telemetry.ts`)

`PI_TELEMETRY` env override + truthy-flag parsing. The settings-backed default
(`settingsManager.getEnableInstallTelemetry`) lives behind the partial
SettingsManager and is threaded by callers.
-/

namespace LeanAgent.CodingAgent.Telemetry

/-- Pi `isTruthyEnvFlag`: "1" / "true" / "yes" (case-insensitive). -/
def isTruthyEnvFlag (value : Option String) : Bool :=
  match value with
  | none => false
  | some v =>
      let lower := v.toLower
      v == "1" || lower == "true" || lower == "yes"

/--
Pi `isInstallTelemetryEnabled`: env override wins; otherwise falls back to the
settings-backed default. `settingsEnabled` is the caller-resolved default
(Pi: `settingsManager.getEnableInstallTelemetry()`).
-/
def isInstallTelemetryEnabled (settingsEnabled : Bool) (telemetryEnv : Option String) : Bool :=
  match telemetryEnv with
  | some v => isTruthyEnvFlag (some v)
  | none => settingsEnabled

end LeanAgent.CodingAgent.Telemetry
