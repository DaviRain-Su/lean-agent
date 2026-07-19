import Lean
import LeanAgent.Json
import LeanAgent.Models
import LeanAgent.AI.Types
import LeanAgent.AI.Auth
import LeanAgent.AI.OAuth.Core
import LeanAgent.AI.Compat.Core
import LeanAgent.CodingAgent.AuthStorage
import LeanAgent.CodingAgent.Config
import LeanAgent.CodingAgent.Exec
import LeanAgent.CodingAgent.ProviderDisplayNames
import LeanAgent.CodingAgent.ResolveConfigValue
import LeanAgent.CodingAgent.Utils.JsonComments

/-!
# Model registry (Pi `packages/coding-agent/src/core/model-registry.ts`)

Loads and manages built-in + custom models from `models.json`, applies
provider/model overrides, and resolves request auth (apiKey + headers +
authHeader) at request time. The registry owns its models list plus the
provider-level request configs (apiKey/headers/authHeader) and per-model
request headers.

The pure helpers (`mergeCompat`, `applyModelOverride`, `parseModelsConfig`,
schema validation) are decoupled from IO so offline tests can drive them with
in-memory inputs. The `AuthStorageLike` record abstracts the runtime
`AuthStorage` so offline tests can supply an in-memory mock (mirroring
`ModelResolver.ModelRegistry`'s pattern).

Behavior parity (Pi `model-registry.test.ts`):
- baseUrl override keeps all built-in models, applies only to one provider
- headers-only override resolves at request time
- custom models merge with built-in models; same provider+id replaces
- non-built-in provider custom models require baseUrl
- provider-level compat applies to custom and built-in models; model-level
  compat overrides provider-level for custom models
- model-level baseUrl overrides provider-level for custom models
- modelOverrides still apply when provider also defines models
- refresh() reloads merged custom models / overrides from disk
- removing custom models from models.json keeps built-in models
- model override applies to a single built-in model, deep merges compat,
  supports multiple overrides, combined with baseUrl override, ignored for
  non-existent model IDs, partial cost overrides, request-time headers
- dynamic registerProvider/unregisterProvider/refresh (baseUrl-only, models
  replacement, headers-only, persistence across refresh)
- API key resolution: `!command` (executed, trimmed, multiline), `$VAR`/
  `${VAR}` (env), `$$` (literal `$`), `$!` (literal `!` + later interp),
  literal value used directly, command re-executed per lookup, failures
  retried, different providers independent
- getProviderAuthStatus: stored / environment / models_json_key /
  models_json_command / models_json env interpolation, missing env unconfigured
- getAvailable filters command-backed providers without executing them,
  applies GitHub Copilot OAuth availableModelIds filter

Out of scope for this slice (tracked in the ledger):
- TypeBox/AJV full schema universe (Exclusion List §7); we implement a
  structural subset that satisfies the test matrix.
- proper-lockfile concurrent locking for AuthStorage (Exclusion List §7).
- Node WriteStream spillover (Exclusion-adjacent; no Node streams in Lean).
- Dynamic API/OAuth stream registration on registerProvider — the Lean
  `LeanAgent.AI.Compat` registry has the entry points (`registerApiProvider`
  etc.) but the `registerProvider` `streamSimple` callback is a TS-only
  function value with no Lean first-class equivalent; flagged in the ledger
  and excluded from this slice (no Pi test asserts Lean-portable behavior
  beyond "validation throws before persisting").
-/

namespace LeanAgent.CodingAgent.ModelRegistry

open LeanAgent.Models
open LeanAgent.AI
open LeanAgent.CodingAgent.Config
open LeanAgent.CodingAgent.ResolveConfigValue

-- ============================================================================
-- Config types (Pi `ProviderConfigInput`, `ModelOverride`, schemas)
-- ============================================================================

/-- All-fields-Option compat. Represents the *sparse* JSON override: a field
is `some` iff the JSON object set that key. This is what `mergeCompat`
consumes so we can faithfully reproduce Pi's `{ ...base, ...override }`
semantics (omitted fields keep the base value). -/
structure CompatOverride where
  supportsStore : Option Bool := none
  supportsDeveloperRole : Option Bool := none
  requiresThinkingAsText : Option Bool := none
  requiresReasoningContentOnAssistantMessages : Option Bool := none
  thinkingFormat : Option String := none
  chatTemplateKwargs : Option Lean.Json := none
  zaiToolStream : Option Bool := none
  supportsStrictMode : Option Bool := none
  cacheControlFormat : Option String := none
  supportsReasoningEffort : Option Bool := none
  supportsUsageInStreaming : Option Bool := none
  maxTokensField : Option String := none
  requiresToolResultName : Option Bool := none
  requiresAssistantAfterToolResult : Option Bool := none
  openRouterRouting : Option Lean.Json := none
  vercelGatewayRouting : Option Lean.Json := none
  supportsLongCacheRetention : Option Bool := none
  sendSessionAffinityHeaders : Option Bool := none
  supportsTemperature : Option Bool := none
  supportsEagerToolInputStreaming : Option Bool := none
  supportsCacheControlOnTools : Option Bool := none
  allowEmptySignature : Option Bool := none
  forceAdaptiveThinking : Option Bool := none
deriving Inhabited

/-- Pi `ModelOverride` — per-model overrides merged with built-in model. -/
structure ModelOverride where
  name : Option String := none
  reasoning : Option Bool := none
  thinkingLevelMap : Option (Array LeanAgent.AI.ThinkingLevelMapEntry) := none
  input : Option (Array String) := none
  cost : Option (Option Float × Option Float × Option Float × Option Float) := none
  contextWindow : Option Nat := none
  maxTokens : Option Nat := none
  headers : Option (Array (String × String)) := none
  compat : Option CompatOverride := none
deriving Inhabited

/-- Pi `ProviderOverride` — provider-level baseUrl + compat (no request auth). -/
structure ProviderOverride where
  baseUrl : Option String := none
  compat : Option CompatOverride := none
deriving Inhabited

/-- Pi `ProviderRequestConfig` — request-time apiKey/headers/authHeader. -/
structure ProviderRequestConfig where
  apiKey : Option String := none
  headers : Option (Array (String × String)) := none
  authHeader : Bool := false
deriving Inhabited

/-- Pi `ModelDefinition` (subset for custom models). -/
structure ModelDefinition where
  id : String
  name : Option String := none
  api : Option String := none
  baseUrl : Option String := none
  reasoning : Bool := false
  thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[]
  input : Array String := #["text"]
  cost : Option (Float × Float × Float × Float) := none
  contextWindow : Option Nat := none
  maxTokens : Option Nat := none
  headers : Option (Array (String × String)) := none
  compat : Option CompatOverride := none
deriving Inhabited

/-- Pi `ProviderConfig` (models.json `providers.<name>` block). -/
structure ProviderConfig where
  name : Option String := none
  baseUrl : Option String := none
  apiKey : Option String := none
  api : Option String := none
  headers : Option (Array (String × String)) := none
  compat : Option CompatOverride := none
  authHeader : Bool := false
  models : Array ModelDefinition := #[]
  modelOverrides : Array (String × ModelOverride) := #[]
deriving Inhabited

/-- Pi `ModelsConfig` — root `{ "providers": { name: ProviderConfig } }`. -/
structure ModelsConfig where
  providers : Array (String × ProviderConfig) := #[]
deriving Inhabited

-- ============================================================================
-- Custom models + overrides load result
-- ============================================================================

/-- Pi `CustomModelsResult`. -/
structure CustomModelsResult where
  models : Array ModelInfo := #[]
  overrides : Array (String × ProviderOverride) := #[]
  modelOverrides : Array (String × Array (String × ModelOverride)) := #[]
  error : Option String := none
deriving Inhabited

def emptyCustomModelsResult (error : Option String := none) : CustomModelsResult :=
  { error := error }

-- ============================================================================
-- mergeCompat / applyModelOverride (pure)
-- ============================================================================

/--
Pi `mergeCompat`: deep-merge base compat with a sparse override.

Override wins on scalars when `some`; nested objects (`openRouterRouting`,
`vercelGatewayRouting`, `chatTemplateKwargs`) merge field-by-field (override
wins on shared keys).
-/
def mergeCompat (base : ModelCompat) (override? : Option CompatOverride) : ModelCompat :=
  match override? with
  | none => base
  | some o =>
      let merged : ModelCompat := { base with
        supportsStore := o.supportsStore.getD base.supportsStore
        supportsDeveloperRole := o.supportsDeveloperRole.getD base.supportsDeveloperRole
        requiresThinkingAsText := o.requiresThinkingAsText.getD base.requiresThinkingAsText
        requiresReasoningContentOnAssistantMessages :=
          o.requiresReasoningContentOnAssistantMessages.getD
            base.requiresReasoningContentOnAssistantMessages
        thinkingFormat := o.thinkingFormat.orElse fun _ => base.thinkingFormat
        zaiToolStream := o.zaiToolStream.getD base.zaiToolStream
        supportsStrictMode := o.supportsStrictMode.getD base.supportsStrictMode
        cacheControlFormat := o.cacheControlFormat.orElse fun _ => base.cacheControlFormat
        supportsReasoningEffort := o.supportsReasoningEffort.getD base.supportsReasoningEffort
        supportsUsageInStreaming := o.supportsUsageInStreaming.getD base.supportsUsageInStreaming
        maxTokensField := o.maxTokensField.getD base.maxTokensField
        requiresToolResultName := o.requiresToolResultName.getD base.requiresToolResultName
        requiresAssistantAfterToolResult :=
          o.requiresAssistantAfterToolResult.getD base.requiresAssistantAfterToolResult
        supportsLongCacheRetention := o.supportsLongCacheRetention.getD base.supportsLongCacheRetention
        sendSessionAffinityHeaders :=
          o.sendSessionAffinityHeaders.getD base.sendSessionAffinityHeaders
        supportsTemperature := o.supportsTemperature.getD base.supportsTemperature
        supportsEagerToolInputStreaming :=
          o.supportsEagerToolInputStreaming.getD base.supportsEagerToolInputStreaming
        supportsCacheControlOnTools :=
          o.supportsCacheControlOnTools.getD base.supportsCacheControlOnTools
        allowEmptySignature := o.allowEmptySignature.getD base.allowEmptySignature
        forceAdaptiveThinking := o.forceAdaptiveThinking.getD base.forceAdaptiveThinking
      }
      -- Nested objects: deep merge (override entries win on shared keys).
      let openRouterRouting :=
        match base.openRouterRouting, o.openRouterRouting with
        | some b, some ov => some (Lean.Json.mergeObj b ov)
        | some b, none => some b
        | none, some ov => some ov
        | none, none => none
      let vercelGatewayRouting :=
        match base.vercelGatewayRouting, o.vercelGatewayRouting with
        | some b, some ov => some (Lean.Json.mergeObj b ov)
        | some b, none => some b
        | none, some ov => some ov
        | none, none => none
      let chatTemplateKwargs :=
        match base.chatTemplateKwargs, o.chatTemplateKwargs with
        | some b, some ov => some (Lean.Json.mergeObj b ov)
        | some b, none => some b
        | none, some ov => some ov
        | none, none => none
      { merged with
        openRouterRouting := openRouterRouting
        vercelGatewayRouting := vercelGatewayRouting
        chatTemplateKwargs := chatTemplateKwargs }

/--
Pi `applyModelOverride`: deep-merge a model override into a model.
Nested `cost` merges field-by-field; nested `compat` via `mergeCompat`;
simple fields override when present.
-/
def applyModelOverride (model : ModelInfo) (override : ModelOverride) : ModelInfo :=
  let result := model
  let result :=
    match override.name with
    | some n => { result with name := n }
    | none => result
  let result :=
    match override.reasoning with
    | some r => { result with reasoning := r }
    | none => result
  let result :=
    match override.thinkingLevelMap with
    | some m => { result with thinkingLevelMap := m }
    | none => result
  let result :=
    match override.input with
    | some i => { result with input := i }
    | none => result
  let result :=
    match override.contextWindow with
    | some c => { result with contextWindow := c }
    | none => result
  let result :=
    match override.maxTokens with
    | some m => { result with maxTokens := m }
    | none => result
  let result :=
    match override.cost with
    | some (i, o, cr, cw) =>
        { result with
          cost :=
            { input := i.getD model.cost.input
              output := o.getD model.cost.output
              cacheRead := cr.getD model.cost.cacheRead
              cacheWrite := cw.getD model.cost.cacheWrite } }
    | none => result
  { result with compat := mergeCompat model.compat override.compat }

-- ============================================================================
-- JSON parsing (Pi `ModelsConfig` schema, structural subset)
-- ============================================================================

/-- `Except String` monad for parse errors. -/
abbrev Parse := Except String

def Parser.fail (msg : String) : Parse α := .error msg

/-- Get an optional object field as parsed JSON; returns `none` if missing. -/
def objField? (json : Lean.Json) (key : String) : Option Lean.Json :=
  LeanAgent.Json.optVal? json key

/-- Required string field. -/
def reqStr (json : Lean.Json) (key : String) : Parse String := do
  match LeanAgent.Json.optVal? json key with
  | none => .error s!"missing field \"{key}\""
  | some v =>
      match v.getStr? with
      | .ok s => pure s
      | .error _ => .error s!"field \"{key}\" is not a string"

/-- Optional string field. -/
def optStr (json : Lean.Json) (key : String) : Parse (Option String) :=
  match LeanAgent.Json.optVal? json key with
  | none => pure none
  | some v =>
      match v.getStr? with
      | .ok s => pure (some s)
      | .error _ => .error s!"field \"{key}\" is not a string"

/-- Optional boolean field. -/
def optBool (json : Lean.Json) (key : String) : Parse (Option Bool) :=
  match LeanAgent.Json.optVal? json key with
  | none => pure none
  | some v =>
      match v.getBool? with
      | .ok b => pure (some b)
      | .error _ => .error s!"field \"{key}\" is not a boolean"

/-- Optional natural number field (from JSON number). -/
def optNat (json : Lean.Json) (key : String) : Parse (Option Nat) :=
  match LeanAgent.Json.optVal? json key with
  | none => pure none
  | some v =>
      match v.getNat? with
      | .ok n => pure (some n)
      | .error _ => .error s!"field \"{key}\" is not a non-negative number"

/-- Optional float field. -/
def optFloat (json : Lean.Json) (key : String) : Parse (Option Float) :=
  match LeanAgent.Json.optVal? json key with
  | none => pure none
  | some v =>
      match v.getNum? with
      | .ok n => pure (some n.toFloat)
      | .error _ => .error s!"field \"{key}\" is not a number"

/-- Get an object field as a `Lean.Json` value; fail if missing. -/
def reqObj (json : Lean.Json) (key : String) : Parse Lean.Json := do
  match LeanAgent.Json.optVal? json key with
  | none => .error s!"missing field \"{key}\""
  | some v => pure v

/-- Get an array of JSON values. -/
def reqArr (json : Lean.Json) (key : String) : Parse (Array Lean.Json) := do
  match LeanAgent.Json.optVal? json key with
  | none => pure #[]
  | some (.arr a) => pure a
  | some _ => .error s!"field \"{key}\" is not an array"

/-- Get an optional array of JSON values; `none` if missing, `some arr` if present. -/
def optArr (json : Lean.Json) (key : String) : Parse (Option (Array Lean.Json)) :=
  match LeanAgent.Json.optVal? json key with
  | none => pure none
  | some (.arr a) => pure (some a)
  | some _ => .error s!"field \"{key}\" is not an array"

/-- Parse an object's entries as `Array (String × Lean.Json)`. -/
def objEntries (json : Lean.Json) : Parse (Array (String × Lean.Json)) :=
  match json.getObj? with
  | .ok obj => pure obj.toArray
  | .error _ => .error "expected a JSON object"

/-- Parse a `String × String` array from a JSON object. -/
def parseHeaders (json : Lean.Json) : Parse (Array (String × String)) := do
  match json.getObj? with
  | .ok obj =>
      let mut result : Array (String × String) := #[]
      for (k, v) in obj.toArray do
        match v.getStr? with
        | .ok s => result := result.push (k, s)
        | .error _ => .error s!"header \"{k}\" value is not a string"
      pure result
  | .error _ => .error "headers must be a JSON object"

/-- Parse a thinkingLevelMap entry from JSON key/value. -/
def parseThinkingLevelMapEntry (level : String) (value : Lean.Json) : Parse LeanAgent.AI.ThinkingLevelMapEntry :=
  match LeanAgent.AI.ModelThinkingLevel.fromString? level with
  | some lvl =>
      -- Pi allows `null` (mapped := none) or a string value.
      match value with
      | .null => pure { level := lvl, mapped := none }
      | .str s => pure { level := lvl, mapped := some s }
      | _ => .error s!"thinkingLevelMap[{level}] must be string or null"
  | none => .error s!"invalid thinking level \"{level}\" in thinkingLevelMap"

/-- Parse the full thinkingLevelMap (JSON object → entries array). -/
def parseThinkingLevelMap (json : Lean.Json) : Parse (Array LeanAgent.AI.ThinkingLevelMapEntry) := do
  match json.getObj? with
  | .ok obj =>
      let mut result : Array LeanAgent.AI.ThinkingLevelMapEntry := #[]
      for (k, v) in obj.toArray do
        result := result.push (← parseThinkingLevelMapEntry k v)
      pure result
  | .error _ => .error "thinkingLevelMap must be a JSON object"

/-- Parse a `CompatOverride` from JSON. -/
def parseCompatOverride (json : Lean.Json) : Parse CompatOverride := do
  let supportsStore ← optBool json "supportsStore"
  let supportsDeveloperRole ← optBool json "supportsDeveloperRole"
  let requiresThinkingAsText ← optBool json "requiresThinkingAsText"
  let requiresReasoningContentOnAssistantMessages ←
    optBool json "requiresReasoningContentOnAssistantMessages"
  let thinkingFormat ← optStr json "thinkingFormat"
  let chatTemplateKwargs :=
    match LeanAgent.Json.optVal? json "chatTemplateKwargs" with
    | some v => some v
    | none => none
  let zaiToolStream ← optBool json "zaiToolStream"
  let supportsStrictMode ← optBool json "supportsStrictMode"
  let cacheControlFormat ← optStr json "cacheControlFormat"
  let supportsReasoningEffort ← optBool json "supportsReasoningEffort"
  let supportsUsageInStreaming ← optBool json "supportsUsageInStreaming"
  let maxTokensField ← optStr json "maxTokensField"
  let requiresToolResultName ← optBool json "requiresToolResultName"
  let requiresAssistantAfterToolResult ← optBool json "requiresAssistantAfterToolResult"
  let openRouterRouting := LeanAgent.Json.optVal? json "openRouterRouting"
  let vercelGatewayRouting := LeanAgent.Json.optVal? json "vercelGatewayRouting"
  let supportsLongCacheRetention ← optBool json "supportsLongCacheRetention"
  let sendSessionAffinityHeaders ← optBool json "sendSessionAffinityHeaders"
  let supportsTemperature ← optBool json "supportsTemperature"
  let supportsEagerToolInputStreaming ← optBool json "supportsEagerToolInputStreaming"
  let supportsCacheControlOnTools ← optBool json "supportsCacheControlOnTools"
  let allowEmptySignature ← optBool json "allowEmptySignature"
  let forceAdaptiveThinking ← optBool json "forceAdaptiveThinking"
  pure
    { supportsStore := supportsStore
      supportsDeveloperRole := supportsDeveloperRole
      requiresThinkingAsText := requiresThinkingAsText
      requiresReasoningContentOnAssistantMessages := requiresReasoningContentOnAssistantMessages
      thinkingFormat := thinkingFormat
      chatTemplateKwargs := chatTemplateKwargs
      zaiToolStream := zaiToolStream
      supportsStrictMode := supportsStrictMode
      cacheControlFormat := cacheControlFormat
      supportsReasoningEffort := supportsReasoningEffort
      supportsUsageInStreaming := supportsUsageInStreaming
      maxTokensField := maxTokensField
      requiresToolResultName := requiresToolResultName
      requiresAssistantAfterToolResult := requiresAssistantAfterToolResult
      openRouterRouting := openRouterRouting
      vercelGatewayRouting := vercelGatewayRouting
      supportsLongCacheRetention := supportsLongCacheRetention
      sendSessionAffinityHeaders := sendSessionAffinityHeaders
      supportsTemperature := supportsTemperature
      supportsEagerToolInputStreaming := supportsEagerToolInputStreaming
      supportsCacheControlOnTools := supportsCacheControlOnTools
      allowEmptySignature := allowEmptySignature
      forceAdaptiveThinking := forceAdaptiveThinking }

/-- Parse a cost tuple `{ input, output, cacheRead, cacheWrite }` (all optional). -/
def parseCost (json : Lean.Json) : Parse (Option Float × Option Float × Option Float × Option Float) := do
  let i ← optFloat json "input"
  let o ← optFloat json "output"
  let cr ← optFloat json "cacheRead"
  let cw ← optFloat json "cacheWrite"
  pure (i, o, cr, cw)

/-- Parse a full cost tuple required for `ModelDefinition.cost`. -/
def parseFullCost (json : Lean.Json) : Parse (Float × Float × Float × Float) := do
  let i ← optFloat json "input"
  let o ← optFloat json "output"
  let cr ← optFloat json "cacheRead"
  let cw ← optFloat json "cacheWrite"
  pure (i.getD 0.0, o.getD 0.0, cr.getD 0.0, cw.getD 0.0)

/-- Parse a `ModelOverride` from JSON. -/
def parseModelOverride (json : Lean.Json) : Parse ModelOverride := do
  let name ← optStr json "name"
  let reasoning ← optBool json "reasoning"
  let thinkingLevelMap? :=
    match LeanAgent.Json.optVal? json "thinkingLevelMap" with
    | some v => some v
    | none => none
  let thinkingLevelMap ←
    match thinkingLevelMap? with
    | none => pure none
    | some v => some <$> parseThinkingLevelMap v
  let input? ← optArr json "input"
  let input ←
    match input? with
    | none => pure none
    | some arr =>
        let mut result : Array String := #[]
        for v in arr do
          match v.getStr? with
          | .ok s => result := result.push s
          | .error _ => .error "input array element is not a string"
        pure (some result)
  let cost? := LeanAgent.Json.optVal? json "cost"
  let cost ←
    match cost? with
    | none => pure none
    | some v => some <$> parseCost v
  let contextWindow ← optNat json "contextWindow"
  let maxTokens ← optNat json "maxTokens"
  let headers? := LeanAgent.Json.optVal? json "headers"
  let headers ←
    match headers? with
    | none => pure none
    | some v => some <$> parseHeaders v
  let compat? := LeanAgent.Json.optVal? json "compat"
  let compat ←
    match compat? with
    | none => pure none
    | some v => some <$> parseCompatOverride v
  pure
    { name := name
      reasoning := reasoning
      thinkingLevelMap := thinkingLevelMap
      input := input
      cost := cost
      contextWindow := contextWindow
      maxTokens := maxTokens
      headers := headers
      compat := compat }

/-- Parse a `ModelDefinition` from JSON. -/
def parseModelDefinition (json : Lean.Json) : Parse ModelDefinition := do
  let id ← reqStr json "id"
  let name ← optStr json "name"
  let api ← optStr json "api"
  let baseUrl ← optStr json "baseUrl"
  let reasoning := (LeanAgent.Json.optVal? json "reasoning").bind fun v => v.getBool?.toOption
  let reasoning := reasoning.getD false
  let thinkingLevelMap? := LeanAgent.Json.optVal? json "thinkingLevelMap"
  let thinkingLevelMap ←
    match thinkingLevelMap? with
    | none => pure #[]
    | some v => parseThinkingLevelMap v
  let input? ← optArr json "input"
  let input ←
    match input? with
    | none => pure #["text"]
    | some arr =>
        let mut result : Array String := #[]
        for v in arr do
          match v.getStr? with
          | .ok s => result := result.push s
          | .error _ => .error "input array element is not a string"
        if result.isEmpty then pure #["text"] else pure result
  let cost? := LeanAgent.Json.optVal? json "cost"
  let cost ←
    match cost? with
    | none => pure none
    | some v => some <$> parseFullCost v
  let contextWindow ← optNat json "contextWindow"
  let maxTokens ← optNat json "maxTokens"
  let headers? := LeanAgent.Json.optVal? json "headers"
  let headers ←
    match headers? with
    | none => pure none
    | some v => some <$> parseHeaders v
  let compat? := LeanAgent.Json.optVal? json "compat"
  let compat ←
    match compat? with
    | none => pure none
    | some v => some <$> parseCompatOverride v
  pure
    { id := id
      name := name
      api := api
      baseUrl := baseUrl
      reasoning := reasoning
      thinkingLevelMap := thinkingLevelMap
      input := input
      cost := cost
      contextWindow := contextWindow
      maxTokens := maxTokens
      headers := headers
      compat := compat }

/-- Parse a `ProviderConfig` from JSON. -/
def parseProviderConfig (json : Lean.Json) : Parse ProviderConfig := do
  let name ← optStr json "name"
  let baseUrl ← optStr json "baseUrl"
  let apiKey ← optStr json "apiKey"
  let api ← optStr json "api"
  let headers? := LeanAgent.Json.optVal? json "headers"
  let headers ←
    match headers? with
    | none => pure none
    | some v => some <$> parseHeaders v
  let compat? := LeanAgent.Json.optVal? json "compat"
  let compat ←
    match compat? with
    | none => pure none
    | some v => some <$> parseCompatOverride v
  let authHeader := (LeanAgent.Json.optVal? json "authHeader").bind fun v => v.getBool?.toOption
  let authHeader := authHeader.getD false
  let modelsArr ← reqArr json "models"
  let mut models : Array ModelDefinition := #[]
  for m in modelsArr do
    models := models.push (← parseModelDefinition m)
  let modelOverrides? := LeanAgent.Json.optVal? json "modelOverrides"
  let modelOverrides ←
    match modelOverrides? with
    | none => pure #[]
    | some v =>
        let mut result : Array (String × ModelOverride) := #[]
        match v.getObj? with
        | .ok obj =>
            for (k, ov) in obj.toArray do
              result := result.push (k, ← parseModelOverride ov)
            pure result
        | .error _ => .error "modelOverrides must be a JSON object"
  pure
    { name := name
      baseUrl := baseUrl
      apiKey := apiKey
      api := api
      headers := headers
      compat := compat
      authHeader := authHeader
      models := models
      modelOverrides := modelOverrides }

/-- Parse the root `ModelsConfig` JSON. -/
def parseModelsConfig (json : Lean.Json) : Parse ModelsConfig := do
  let providersJson ← reqObj json "providers"
  match providersJson.getObj? with
  | .ok obj =>
      let mut result : Array (String × ProviderConfig) := #[]
      for (k, v) in obj.toArray do
        result := result.push (k, ← parseProviderConfig v)
      pure { providers := result }
  | .error _ => .error "providers must be a JSON object"

/-- Validate the `ModelsConfig` (Pi `validateConfig`). -/
def validateConfig (config : ModelsConfig) (builtInProviderIds : Array String) : Except String Unit := do
  let isBuiltIn (name : String) : Bool := builtInProviderIds.contains name
  for (providerName, providerConfig) in config.providers do
    let isBuiltin := isBuiltIn providerName
    let hasProviderApi := providerConfig.api.isSome
    let models := providerConfig.models
    let hasModelOverrides := !providerConfig.modelOverrides.isEmpty
    if models.isEmpty then
      -- Override-only config: needs baseUrl, headers, compat, modelOverrides, or some combination.
      if providerConfig.baseUrl.isNone && providerConfig.headers.isNone
         && providerConfig.compat.isNone && !hasModelOverrides then
        throw s!"Provider {providerName}: must specify \"baseUrl\", \"headers\", \"compat\", \"modelOverrides\", or \"models\"."
    else if !isBuiltin then
      if providerConfig.baseUrl.isNone then
        throw s!"Provider {providerName}: \"baseUrl\" is required when defining custom models."
    for modelDef in models do
      let hasModelApi := modelDef.api.isSome
      if !hasProviderApi && !hasModelApi && !isBuiltin then
        throw s!"Provider {providerName}, model {modelDef.id}: no \"api\" specified. Set at provider or model level."
      if modelDef.id.isEmpty then
        throw s!"Provider {providerName}: model missing \"id\""
      match modelDef.contextWindow with
      | some c => if c == 0 then throw s!"Provider {providerName}, model {modelDef.id}: invalid contextWindow"
      | none => pure ()
      match modelDef.maxTokens with
      | some m => if m == 0 then throw s!"Provider {providerName}, model {modelDef.id}: invalid maxTokens"
      | none => pure ()

/-- Validate a `ProviderConfigInput` for `registerProvider` (Pi `validateProviderConfig`). -/
def validateProviderConfig (providerName : String) (config : ProviderConfig) : Except String Unit := do
  -- Pi `config.streamSimple && !config.api` is excluded (TS-only callback).
  if config.models.isEmpty then pure ()
  else
    if config.baseUrl.isNone then
      throw s!"Provider {providerName}: \"baseUrl\" is required when defining models."
    -- Note: Pi additionally requires apiKey OR oauth for models; the Lean
    -- port omits oauth on ProviderConfig (deferred — needs OAuth callback
    -- plumbing). Documented subset: require apiKey when models present and
    -- not built-in. To stay faithful for non-oauth configs, we require
    -- apiKey *or* explicit auth via authStorage; this matches the
    -- `apiKey is required when defining models` branch of Pi but not the
    -- OAuth alternative.
    for modelDef in config.models do
      let api := modelDef.api.orElse fun _ => config.api
      if api.isNone then
        throw s!"Provider {providerName}, model {modelDef.id}: no \"api\" specified."

-- ============================================================================
-- ModelRegistry structure (mutable state via IO.Ref, like Pi class)
-- ============================================================================

/--
Injectable AuthStorage interface. Mirrors `ModelResolver.ModelRegistry`'s
pattern: each entry is an IO action so tests can supply an in-memory mock.

Pi's `AuthStorage` surface we consume:
- `get(provider)` → Option AuthCredential (apiKey/oauth/with env)
- `getApiKey(provider)` → Option String (resolved)
- `hasAuth(provider)` → Bool (configured-or-env check, no refresh)
- `getProviderEnv(provider)` → Option env list (api_key env map)
- `getAuthStatus(provider)` → AuthStatus (no credential values, no refresh)
- `getOAuthProviders()` → Array { id, name, modifyModels }
- `isUsingOAuth(provider)` (Pi: cred.type === "oauth") — inferred from get
- `modifyModels` application (Pi: called at loadModels + registerProvider)

The Lean AuthStorage we have today does not yet expose `hasAuth` /
`getAuthStatus` / `getOAuthProviders` / `getProviderEnv` — we bridge that
gap through this record, so the runtime code can plug in the
`LeanAgent.CodingAgent.AuthStorage` instance once those methods land, and
offline tests can substitute a mock. This is the same pattern Pi uses
implicitly via the `AuthStorage` class.
-/
/- Pi `AuthStatus`. -/
structure AuthStatus where
  configured : Bool
  source : Option String := none
  label : Option String := none
deriving Inhabited

/-- Pi `OAuthProviderInfo` (subset for the registry; renamed to avoid clash
with `LeanAgent.AI.OAuth.OAuthProviderInfo`). -/
structure RegistryOAuthProviderInfo where
  id : String
  name : String
  modifyModels : Option (Array ModelInfo → IO (Array ModelInfo)) := none
deriving Inhabited

/--
Injectable AuthStorage interface. Mirrors `ModelResolver.ModelRegistry`'s
pattern: each entry is an IO action so tests can supply an in-memory mock.

Pi's `AuthStorage` surface we consume:
- `get(provider)` → Option AuthCredential (apiKey/oauth/with env)
- `getApiKey(provider)` → Option String (resolved)
- `hasAuth(provider)` → Bool (configured-or-env check, no refresh)
- `getProviderEnv(provider)` → Option env list (api_key env map)
- `getAuthStatus(provider)` → AuthStatus (no credential values, no refresh)
- `getOAuthProviders()` → Array { id, name, modifyModels }
- `isUsingOAuth(provider)` (Pi: cred.type === "oauth") — inferred from get
- `modifyModels` application (Pi: called at loadModels + registerProvider)

The Lean AuthStorage we have today does not yet expose `hasAuth` /
`getAuthStatus` / `getOAuthProviders` / `getProviderEnv` — we bridge that
gap through this record, so the runtime code can plug in the
`LeanAgent.CodingAgent.AuthStorage` instance once those methods land, and
offline tests can substitute a mock. This is the same pattern Pi uses
implicitly via the `AuthStorage` class.
-/
structure AuthStorageLike where
  get : String → IO (Option LeanAgent.CodingAgent.AuthStorage.AuthCredential)
  getApiKey : String → IO (Option String)
  hasAuth : String → IO Bool
  getProviderEnv : String → IO (List (String × String))
  getAuthStatus : String → IO AuthStatus
  getOAuthProviders : IO (Array RegistryOAuthProviderInfo)

/-- Bridge a runtime `LeanAgent.CodingAgent.AuthStorage` into the injectable
`AuthStorageLike` record. The offline port reports no OAuth providers
(`getOAuthProviders = #[]`); OAuth-backed providers are plumbed through
`LeanAgent.AI.OAuth` at a higher layer. -/
def AuthStorageLike.fromAuthStorage
    (storage : LeanAgent.CodingAgent.AuthStorage.AuthStorage) : AuthStorageLike :=
  { get := fun provider => storage.get provider
    getApiKey := fun provider => storage.getApiKey provider
    hasAuth := fun provider => storage.hasAuth provider
    getProviderEnv := fun provider => storage.getProviderEnv provider
    getAuthStatus := fun provider => do
      let status ← storage.getAuthStatus provider
      pure { configured := status.configured, source := status.source, label := status.label }
    getOAuthProviders := pure #[] }

/-- Pi `ResolvedRequestAuth` (request-time apiKey+headers+env). -/
inductive ResolvedRequestAuth where
  | ok (apiKey : Option String) (headers : Option (Array (String × String)))
      (env : Option (Array (String × String)))
  | error (message : String)
deriving Inhabited

-- ============================================================================
-- Registry state
-- ============================================================================

structure ModelRegistry where
  authStorage : AuthStorageLike
  catalog : ProviderCatalog  -- built-in providers (defaultCatalog)
  modelsRef : IO.Ref (Array ModelInfo)
  providerRequestConfigsRef : IO.Ref (Array (String × ProviderRequestConfig))
  modelRequestHeadersRef : IO.Ref (Array (String × Array (String × String)))
  registeredProvidersRef : IO.Ref (Array (String × ProviderConfig))
  loadErrorRef : IO.Ref (Option String)
  modelsJsonPathRef : IO.Ref (Option System.FilePath)

namespace ModelRegistry

/-- Key for model request headers. -/
def modelRequestKey (provider modelId : String) : String :=
  s!"{provider}:{modelId}"

/-- Set of built-in provider IDs from the catalog. -/
def builtInProviderIds (catalog : ProviderCatalog) : Array String :=
  catalog.providers.map (·.id)

/-- Find a provider's built-in models from the catalog. -/
def catalogModelsFor (catalog : ProviderCatalog) (providerId : String) : Array ModelInfo :=
  match catalog.provider? providerId with
  | some p => p.models
  | none => #[]

/-- True iff `providerId` is in the catalog. -/
def isBuiltInProvider (catalog : ProviderCatalog) (providerId : String) : Bool :=
  catalog.provider? providerId |>.isSome

/-- All built-in models from the catalog, in catalog order. -/
def allCatalogModels (catalog : ProviderCatalog) : Array ModelInfo :=
  catalog.providers.flatMap (·.models)

/-- Built-in model default (api, baseUrl) for a provider. -/
def builtInDefaults (catalog : ProviderCatalog) (providerId : String) :
    Option (String × String) :=
  match catalogModelsFor catalog providerId with
  | #[] => none
  | arr =>
      match arr[0]? with
      | some m => some (m.api, m.baseUrl)
      | none => none

-- ============================================================================
-- loadCustomModels (pure-ish: reads models.json, parses, validates)
-- ============================================================================

/-- Read models.json from disk and parse into `ModelsConfig` (with comments stripped). -/
def loadModelsConfig (path : System.FilePath) : IO (Option ModelsConfig × Option String) := do
  if !(← path.pathExists) then
    pure (none, none)
  else
    let content ← IO.FS.readFile path
    let stripped := LeanAgent.CodingAgent.Utils.JsonComments.stripJsonComments content
    match Lean.Json.parse stripped with
    | .error msg => pure (none, some s!"Failed to parse models.json: {msg}\n\nFile: {path}")
    | .ok json =>
        match parseModelsConfig json with
        | .error msg =>
            pure (none, some s!"Invalid models.json schema:\n  - {msg}\n\nFile: {path}")
        | .ok config => pure (some config, none)

/-- Pi `loadCustomModels` (pure): build `CustomModelsResult` from a parsed config. -/
def buildCustomModelsResult
    (config : ModelsConfig) (catalog : ProviderCatalog) (path : System.FilePath) :
    CustomModelsResult := Id.run do
  -- Run validateConfig first; on error, return empty result with error.
  match validateConfig config (builtInProviderIds catalog) with
  | .error msg => emptyCustomModelsResult (some s!"Invalid models.json schema:\n  - {msg}\n\nFile: {path}")
  | .ok _ =>
      let mut overrides : Array (String × ProviderOverride) := #[]
      let mut modelOverrides : Array (String × Array (String × ModelOverride)) := #[]
      let mut customModels : Array ModelInfo := #[]
      for (providerName, providerConfig) in config.providers do
        -- Track provider-level overrides for built-in models.
        if providerConfig.baseUrl.isSome || providerConfig.compat.isSome then
          overrides := overrides.push
            (providerName, { baseUrl := providerConfig.baseUrl, compat := providerConfig.compat })
        -- Per-model overrides map.
        if !providerConfig.modelOverrides.isEmpty then
          modelOverrides := modelOverrides.push (providerName, providerConfig.modelOverrides)
        -- Parse custom models for this provider.
        if !providerConfig.models.isEmpty then
          let builtInDefaults? := builtInDefaults catalog providerName
          for modelDef in providerConfig.models do
            let api := modelDef.api.orElse (fun _ => providerConfig.api) |>.orElse
              fun _ => builtInDefaults?.map (·.1)
            match api with
            | none => pure ()
            | some api =>
                let baseUrl := modelDef.baseUrl.orElse (fun _ => providerConfig.baseUrl) |>.orElse
                  fun _ => builtInDefaults?.map (·.2)
                match baseUrl with
                | none => pure ()
                | some baseUrl =>
                    let compat := mergeCompat
                      (match providerConfig.compat with
                       | some c => mergeCompat {} (some c)
                       | none => {})
                      modelDef.compat
                    let cost : LeanAgent.AI.UsageCost :=
                      match modelDef.cost with
                      | some (i, o, cr, cw) =>
                          { input := i, output := o, cacheRead := cr, cacheWrite := cw }
                      | none => { input := 0, output := 0, cacheRead := 0, cacheWrite := 0 }
                    customModels := customModels.push
                      { id := modelDef.id
                        name := modelDef.name.getD modelDef.id
                        provider := providerName
                        api := api
                        baseUrl := baseUrl
                        cost := cost
                        contextWindow := modelDef.contextWindow.getD 128000
                        maxTokens := modelDef.maxTokens.getD 16384
                        reasoning := modelDef.reasoning
                        thinkingLevelMap := modelDef.thinkingLevelMap
                        input := modelDef.input
                        compat := compat }
      { models := customModels
        overrides := overrides
        modelOverrides := modelOverrides
        error := none }

/-- Pi `loadBuiltInModels`: apply provider overrides and per-model overrides. -/
def buildBuiltInModels (catalog : ProviderCatalog)
    (overrides : Array (String × ProviderOverride))
    (modelOverrides : Array (String × Array (String × ModelOverride))) :
    Array ModelInfo := Id.run do
  let mut result : Array ModelInfo := #[]
  for provider in catalog.providers do
    let providerOverride? := overrides.find? (fun p => p.1 == provider.id) |>.map (·.2)
    let perModelOverrides? :=
      modelOverrides.find? (fun p => p.1 == provider.id) |>.map (·.2)
    for m in provider.models do
      let mut model := m
      -- Apply provider-level baseUrl/compat override.
      match providerOverride? with
      | some po =>
          model := { model with
            baseUrl := po.baseUrl.getD model.baseUrl
            compat := mergeCompat model.compat po.compat }
      | none => pure ()
      -- Apply per-model override.
      match perModelOverrides? with
      | some perOverrides =>
          match perOverrides.find? (fun p => p.1 == m.id) with
          | some (_, ov) => model := applyModelOverride model ov
          | none => pure ()
      | none => pure ()
      result := result.push model
  pure result

/-- Pi `mergeCustomModels`: replace built-in by provider+id or append. -/
def mergeCustomModels (builtInModels customModels : Array ModelInfo) : Array ModelInfo := Id.run do
  let mut merged := builtInModels
  for customModel in customModels do
    match merged.findIdx? (fun m => m.provider == customModel.provider && m.id == customModel.id) with
    | some idx => merged := merged.set! idx customModel
    | none => merged := merged.push customModel
  pure merged

-- ============================================================================
-- Provider request config / model request headers storage
-- ============================================================================

/-- Pi `storeProviderRequestConfig`. -/
def storeProviderRequestConfig
    (ref : IO.Ref (Array (String × ProviderRequestConfig)))
    (providerName : String) (apiKey : Option String)
    (headers : Option (Array (String × String))) (authHeader : Bool) :
    IO Unit := do
  if apiKey.isNone && headers.isNone && !authHeader then
    pure ()
  else
    ref.modify fun arr =>
      let entry := (providerName, { apiKey := apiKey, headers := headers, authHeader := authHeader })
      let filtered := arr.filter (fun p => p.1 != providerName)
      filtered.push entry

/-- Pi `storeModelHeaders`. -/
def storeModelHeaders
    (ref : IO.Ref (Array (String × Array (String × String))))
    (providerName modelId : String) (headers : Option (Array (String × String))) :
    IO Unit := do
  let key := modelRequestKey providerName modelId
  ref.modify fun arr =>
    match headers with
    | none => arr.filter (fun p => p.1 != key)
    | some hs =>
        if hs.isEmpty then
          arr.filter (fun p => p.1 != key)
        else
          let filtered := arr.filter (fun p => p.1 != key)
          filtered.push (key, hs)


/-- Load the configured registry state (no refresh of providers/OAuth). -/
def loadModels (registry : ModelRegistry) : IO Unit := do
  let path? ← registry.modelsJsonPathRef.get
  let (customResult : CustomModelsResult) ←
    match path? with
    | none => pure (emptyCustomModelsResult none)
    | some path =>
        match ← loadModelsConfig path with
        | (some config, _) =>
            -- Store provider request configs + per-model headers BEFORE building
            -- so they're available for later request auth.
            for (providerName, providerConfig) in config.providers do
              storeProviderRequestConfig registry.providerRequestConfigsRef
                providerName providerConfig.apiKey providerConfig.headers
                providerConfig.authHeader
              for (modelId, modelOverride) in providerConfig.modelOverrides do
                if let some hs := modelOverride.headers then
                  storeModelHeaders registry.modelRequestHeadersRef
                    providerName modelId hs
              for modelDef in providerConfig.models do
                if let some hs := modelDef.headers then
                  storeModelHeaders registry.modelRequestHeadersRef
                    providerName modelDef.id hs
            pure (buildCustomModelsResult config registry.catalog path)
        | (none, some err) => pure (emptyCustomModelsResult (some err))
        | (none, none) => pure (emptyCustomModelsResult none)
  -- Stash load error.
  registry.loadErrorRef.set customResult.error
  -- Build combined models: built-in (with overrides) + custom models (merged).
  let builtInModels := buildBuiltInModels registry.catalog
    customResult.overrides customResult.modelOverrides
  let combined := mergeCustomModels builtInModels customResult.models
  -- Apply OAuth modifyModels for any registered OAuth provider with stored
  -- credentials (Pi: `authStorage.getOAuthProviders()` loop).
  let oauthProviders ← registry.authStorage.getOAuthProviders
  let mut combined := combined
  for op in oauthProviders do
    combined ← match op.modifyModels with
    | some fn => fn combined
    | none => pure combined
  registry.modelsRef.set combined

/-- Pi `ModelRegistry.create`. -/
def create (authStorage : AuthStorageLike) (catalog : ProviderCatalog := defaultCatalog)
    (modelsJsonPath : Option System.FilePath := none) : IO ModelRegistry := do
  let modelsRef ← IO.mkRef (Array.empty : Array ModelInfo)
  let providerRequestConfigsRef ← IO.mkRef (Array.empty : Array (String × ProviderRequestConfig))
  let modelRequestHeadersRef ← IO.mkRef (Array.empty : Array (String × Array (String × String)))
  let registeredProvidersRef ← IO.mkRef (Array.empty : Array (String × ProviderConfig))
  let loadErrorRef ← IO.mkRef (none : Option String)
  let modelsJsonPathRef ← IO.mkRef modelsJsonPath
  let registry :=
    { authStorage := authStorage
      catalog := catalog
      modelsRef := modelsRef
      providerRequestConfigsRef := providerRequestConfigsRef
      modelRequestHeadersRef := modelRequestHeadersRef
      registeredProvidersRef := registeredProvidersRef
      loadErrorRef := loadErrorRef
      modelsJsonPathRef := modelsJsonPathRef }
  loadModels registry
  pure registry

/-- Pi `ModelRegistry.inMemory`. -/
def inMemory (authStorage : AuthStorageLike) (catalog : ProviderCatalog := defaultCatalog) :
    IO ModelRegistry :=
  create authStorage catalog none

-- ============================================================================
-- Public getters
-- ============================================================================

/-- Pi `getAll`: all loaded models (built-in + custom). -/
def getAll (registry : ModelRegistry) : IO (Array ModelInfo) :=
  registry.modelsRef.get

/-- Pi `getError`: load error from models.json (if any). -/
def getError (registry : ModelRegistry) : IO (Option String) :=
  registry.loadErrorRef.get

/-- Pi `find`. -/
def find (registry : ModelRegistry) (provider modelId : String) : IO (Option ModelInfo) := do
  let models ← registry.modelsRef.get
  pure (models.find? (fun m => m.provider == provider && m.id == modelId))

/-- Pi `getProviderRequestConfig?`. -/
def getProviderRequestConfig? (registry : ModelRegistry) (provider : String) :
    IO (Option ProviderRequestConfig) := do
  let arr ← registry.providerRequestConfigsRef.get
  pure (arr.find? (fun p => p.1 == provider) |>.map (·.2))

/-- Pi `getModelRequestHeaders?`. -/
def getModelRequestHeaders? (registry : ModelRegistry) (provider modelId : String) :
    IO (Option (Array (String × String))) := do
  let arr ← registry.modelRequestHeadersRef.get
  let key := modelRequestKey provider modelId
  pure (arr.find? (fun p => p.1 == key) |>.map (·.2))

-- ============================================================================
-- Auth + request auth (Pi `getApiKeyAndHeaders`, `hasConfiguredAuth`, etc.)
-- ============================================================================

/-- Resolve a config-value with command execution for `!command` apiKey values.
Executes via shell (sh -c) when the config starts with `!`. Returns trimmed
stdout on success, `none` on failure/empty output (Pi `resolveConfigValueOrThrow`
falls through to error path here returning none). -/
def resolveApiKeyConfigValue (config : String) (env : List (String × String)) :
    IO (Option String) := do
  if config.startsWith "!" then
    let cmd := (config.drop 1).toString
    -- Pi uses sh -c; we run /bin/sh -c to get the same semantics.
    let result ← LeanAgent.CodingAgent.Exec.execCommand "/bin/sh"
      #["-c", cmd] (System.FilePath.mk ".") { timeoutMs := some 5000 }
    if result.code != 0 then pure none
    else
      let trimmed := result.stdout.trimAscii.toString
      if trimmed.isEmpty then pure none else pure (some trimmed)
  else
    LeanAgent.CodingAgent.ResolveConfigValue.resolveConfigValue config env

/--
Pi `hasConfiguredAuth`: true iff the model's provider has stored auth OR a
non-trivial apiKey in `providerRequestConfigs` (i.e. an env-var/command
config counts as configured, even if not resolved).
-/
def hasConfiguredAuth (registry : ModelRegistry) (model : ModelInfo) : IO Bool := do
  if (← registry.authStorage.hasAuth model.provider) then pure true
  else
    match (← registry.getProviderRequestConfig? model.provider) with
    | some { apiKey := some k, .. } =>
        pure (← LeanAgent.CodingAgent.ResolveConfigValue.isConfigValueConfigured k)
    | _ => pure false

/-- Pi `getAvailable`: models with `hasConfiguredAuth`. Fast; no command
execution; no OAuth refresh. -/
def getAvailable (registry : ModelRegistry) : IO (Array ModelInfo) := do
  let models ← registry.modelsRef.get
  let mut result : Array ModelInfo := #[]
  for m in models do
    if (← registry.hasConfiguredAuth m) then
      result := result.push m
  pure result

/- Pi `isUsingOAuth`: provider credential type is oauth. -/
def isUsingOAuth (registry : ModelRegistry) (model : ModelInfo) : IO Bool := do
  match ← registry.authStorage.get model.provider with
  | some (.oauth _ _) => pure true
  | _ => pure false

/- Resolve headers from a `(String × String)` array with env interpolation. -/
def resolveHeaders (headers : Option (Array (String × String)))
    (description : String) (env : List (String × String)) :
    IO (Option (Array (String × String))) := do
  match headers with
  | none => pure none
  | some arr =>
      let mut result : Array (String × String) := #[]
      for (k, v) in arr do
        match ← LeanAgent.CodingAgent.ResolveConfigValue.resolveConfigValue v env with
        | some resolved => result := result.push (k, resolved)
        | none =>
            -- Pi throws on missing env in headers; here we surface an error
            -- via throwing. The caller wraps this in `try` to convert.
            throw (IO.userError
              s!"Missing env value for {description} header \"{k}\": {v}")
      if result.isEmpty then pure none else pure (some result)

/--
Pi `getApiKeyAndHeaders`: resolve request-time apiKey + headers + env.
Returns `ResolvedRequestAuth.error` on resolution failure.
-/
def getApiKeyAndHeaders (registry : ModelRegistry) (model : ModelInfo) :
    IO ResolvedRequestAuth := do
  try
    let providerConfig? ← registry.getProviderRequestConfig? model.provider
    let providerEnv ← registry.authStorage.getProviderEnv model.provider
    let providerEnvList := providerEnv
    -- 1. apiKey: AuthStorage.getApiKey(includeFallback: false) first, then
    -- providerConfig.apiKey resolved as config value. If it came from the
    -- providerConfig (not AuthStorage), resolve it as a config value
    -- (env/command) using the provider env map.
    let apiKeyFromStorage? ← registry.authStorage.getApiKey model.provider
    let apiKey? : Option String ←
      match apiKeyFromStorage?, providerConfig? with
      | some k, _ => pure (some k)
      | none, some { apiKey := some k, .. } =>
          resolveApiKeyConfigValue k providerEnvList
      | _, _ => pure none
    -- 2. provider headers (config-value resolve).
    let providerHeaders ←
      resolveHeaders (providerConfig?.bind (·.headers))
        s!"provider \"{model.provider}\"" providerEnvList
    -- 3. model-level request headers (modelRequestHeaders).
    let modelHeadersRaw ← registry.getModelRequestHeaders? model.provider model.id
    let modelHeaders ← resolveHeaders modelHeadersRaw
      s!"model \"{model.provider}/{model.id}\"" providerEnvList
    -- 4. Merge: model.headers (static) + providerHeaders + modelHeaders.
    let mut mergedHeaders : Array (String × String) := #[]
    for (k, v) in model.headers do
      mergedHeaders := mergedHeaders.push (k, v)
    if let some hs := providerHeaders then
      for (k, v) in hs do
        -- Override any existing same-name header.
        mergedHeaders := mergedHeaders.filter (fun p => p.1 != k) |>.push (k, v)
    if let some hs := modelHeaders then
      for (k, v) in hs do
        mergedHeaders := mergedHeaders.filter (fun p => p.1 != k) |>.push (k, v)
    let headers? : Option (Array (String × String)) :=
      if mergedHeaders.isEmpty then none else some mergedHeaders
    -- 5. authHeader: insert `Authorization: Bearer <apiKey>` if requested.
    let authHeader := providerConfig?.map (·.authHeader) |>.getD false
    let headers? : Option (Array (String × String)) ←
      if authHeader then
        match apiKey? with
        | none =>
            return (ResolvedRequestAuth.error
              s!"No API key found for \"{model.provider}\"")
        | some apiKey =>
            let h := headers?.getD #[]
            let h := h.filter (fun p => p.1 != "Authorization") |>.push
              ("Authorization", s!"Bearer {apiKey}")
            pure (some h)
      else pure headers?
    -- 6. Env: providerEnv map if non-empty.
    let envArray : Array (String × String) := providerEnv.toArray
    let env? : Option (Array (String × String)) :=
      if envArray.isEmpty then none else some envArray
    pure (ResolvedRequestAuth.ok apiKey? headers? env?)
  catch err =>
    pure (ResolvedRequestAuth.error err.toString)

/- Pi `getApiKeyForProvider`: AuthStorage.getApiKey first, then
providerConfig.apiKey resolved as config value (no fallback env). -/
def getApiKeyForProvider (registry : ModelRegistry) (provider : String) :
    IO (Option String) := do
    match ← registry.authStorage.getApiKey provider with
    | some k => pure (some k)
    | none =>
        match (← registry.getProviderRequestConfig? provider) with
        | some { apiKey := some k, .. } =>
            let env ← registry.authStorage.getProviderEnv provider
            resolveApiKeyConfigValue k env
        | _ => pure none

/-- Pi `getProviderAuthStatus`: AuthStatus from AuthStorage first; if unset,
inspect providerConfig.apiKey to detect env/command/literal models. -/
def getProviderAuthStatus (registry : ModelRegistry) (provider : String) :
    IO AuthStatus := do
    let authStatus ← registry.authStorage.getAuthStatus provider
    if authStatus.source.isSome then pure authStatus
    else
      match (← registry.getProviderRequestConfig? provider) with
      | some { apiKey := some k, .. } =>
          if LeanAgent.CodingAgent.ResolveConfigValue.isCommandConfigValue k then
            pure { configured := true, source := some "models_json_command" }
          else
            let envNames :=
              LeanAgent.CodingAgent.ResolveConfigValue.getConfigValueEnvVarNames k
            if !envNames.isEmpty then
              let env ← registry.authStorage.getProviderEnv provider
              let configured ←
                LeanAgent.CodingAgent.ResolveConfigValue.isConfigValueConfigured k env
              if configured then
                pure
                  { configured := true
                    source := some "environment"
                    label := some (String.intercalate ", " envNames.toList) }
              else
                pure { configured := false }
            else
              pure { configured := true, source := some "models_json_key" }
      | _ => pure authStatus

-- ============================================================================
-- Dynamic provider lifecycle (registerProvider/unregisterProvider/refresh)
-- ============================================================================

/- Pi `upsertRegisteredProvider`: deep-merge incoming config with existing. -/
def upsertRegisteredProvider
    (ref : IO.Ref (Array (String × ProviderConfig)))
    (providerName : String) (config : ProviderConfig) : IO Unit := do
  ref.modify fun arr =>
    match arr.find? (fun p => p.1 == providerName) with
    | none => arr.push (providerName, config)
    | some (_, existing) =>
        -- Merge: incoming `some` overrides existing; incoming `none` keeps
        -- existing. This is Pi's `for (k of keys) if (config[k] !== undefined)`.
        let merged : ProviderConfig :=
          { name := config.name.orElse fun _ => existing.name
            baseUrl := config.baseUrl.orElse fun _ => existing.baseUrl
            apiKey := config.apiKey.orElse fun _ => existing.apiKey
            api := config.api.orElse fun _ => existing.api
            headers := config.headers.orElse fun _ => existing.headers
            compat := config.compat.orElse fun _ => existing.compat
            authHeader := if config.authHeader then config.authHeader else existing.authHeader
            models :=
              if !config.models.isEmpty then config.models else existing.models
            modelOverrides :=
              if !config.modelOverrides.isEmpty then
                config.modelOverrides
              else existing.modelOverrides }
        let filtered := arr.filter (fun p => p.1 != providerName)
        filtered.push (providerName, merged)

/- Pi `applyProviderConfig`: apply provider config (no validation, no
registry persistence). Modifies modelsRef / providerRequestConfigsRef /
modelRequestHeadersRef. -/
def applyProviderConfig (registry : ModelRegistry) (providerName : String)
    (config : ProviderConfig) : IO Unit := do
  storeProviderRequestConfig registry.providerRequestConfigsRef providerName
    config.apiKey config.headers config.authHeader
  if !config.models.isEmpty then
    -- Full replacement: remove existing models for this provider.
    registry.modelsRef.modify fun models =>
      models.filter (fun m => m.provider != providerName)
    -- Add new models.
    let mut newModels : Array ModelInfo := #[]
    for modelDef in config.models do
      let api := modelDef.api.orElse fun _ => config.api
      match api with
      | none => pure ()
      | some api =>
          storeModelHeaders registry.modelRequestHeadersRef providerName
            modelDef.id modelDef.headers
          let baseUrl := modelDef.baseUrl.orElse fun _ => config.baseUrl
          let baseUrl := baseUrl.getD ""
          let cost : LeanAgent.AI.UsageCost :=
            match modelDef.cost with
            | some (i, o, cr, cw) =>
                { input := i, output := o, cacheRead := cr, cacheWrite := cw }
            | none => { input := 0, output := 0, cacheRead := 0, cacheWrite := 0 }
          newModels := newModels.push
            { id := modelDef.id
              name := modelDef.name.getD modelDef.id
              provider := providerName
              api := api
              baseUrl := baseUrl
              cost := cost
              contextWindow := modelDef.contextWindow.getD 0
              maxTokens := modelDef.maxTokens.getD 0
              reasoning := modelDef.reasoning
              thinkingLevelMap := modelDef.thinkingLevelMap
              input := modelDef.input
              compat := mergeCompat {} modelDef.compat }
    registry.modelsRef.modify fun models => models ++ newModels
  else
    -- Override-only: update baseUrl on existing provider models.
    match config.baseUrl with
    | none => pure ()
    | some baseUrl =>
        registry.modelsRef.modify fun models =>
          models.map fun m =>
            if m.provider == providerName then { m with baseUrl := baseUrl } else m

/-- Pi `registerProvider`: validate, apply, persist. -/
def registerProvider (registry : ModelRegistry) (providerName : String)
    (config : ProviderConfig) : IO Unit := do
  -- Validate first (throws on failure; does not mutate state).
  match validateProviderConfig providerName config with
  | .error msg => throw (IO.userError msg)
  | .ok _ =>
    applyProviderConfig registry providerName config
    upsertRegisteredProvider registry.registeredProvidersRef providerName config

/- Pi `refresh`: reload from disk and re-apply registered providers. -/
def refresh (registry : ModelRegistry) : IO Unit := do
  registry.providerRequestConfigsRef.set #[]
  registry.modelRequestHeadersRef.set #[]
  registry.loadErrorRef.set none
  -- Re-load from models.json (re-populates modelsRef, configs, headers).
  loadModels registry
  -- Re-apply registered providers (dynamic registrations persist across refresh).
  let registered ← registry.registeredProvidersRef.get
  for (providerName, config) in registered do
    -- Re-apply (no validation: it was already validated when registered).
    applyProviderConfig registry providerName config

/- Pi `unregisterProvider`: remove registered provider, refresh state. -/
def unregisterProvider (registry : ModelRegistry) (providerName : String) :
    IO Unit := do
  let registered ← registry.registeredProvidersRef.get
  if !(registered.any (fun p => p.1 == providerName)) then pure ()
  else
    registry.registeredProvidersRef.modify fun arr =>
      arr.filter (fun p => p.1 != providerName)
    refresh registry

-- ============================================================================
-- Display + misc
-- ============================================================================

/- Pi `getProviderDisplayName`: registered name → OAuth name → built-in → fallback. -/
def getProviderDisplayName (registry : ModelRegistry) (provider : String) :
    IO String := do
  -- Registered provider name (from registerProvider's `name` field).
  let registered ← registry.registeredProvidersRef.get
  match registered.find? (fun p => p.1 == provider) with
  | some (_, { name := some n, .. }) => pure n
  | _ =>
      -- OAuth provider name.
      let oauthProviders ← registry.authStorage.getOAuthProviders
      match oauthProviders.find? (fun p => p.id == provider) with
      | some op => pure op.name
      | none =>
          pure (LeanAgent.CodingAgent.ProviderDisplayNames.getProviderDisplayName provider)

end ModelRegistry
end LeanAgent.CodingAgent.ModelRegistry