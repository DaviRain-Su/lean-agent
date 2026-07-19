import Lean
import LeanAgent.Models.Core
import LeanAgent.AI.Types
import LeanAgent.CodingAgent.Defaults

/-!
# Model resolution, scoping, and initial selection
(Pi `packages/coding-agent/src/core/model-resolver.ts`)

Resolves model patterns (exact / canonical `provider/id` / partial / alias vs
dated), colon-suffixed thinking levels, CLI `--provider`/`--model`/`--thinking`
flags, glob scoping, and initial-model selection priority.

The pure logic operates over `Array ModelInfo`; the registry-dependent entry
points (`resolveModelScope`, `resolveCliModel`, `findInitialModel`,
`restoreModelFromSession`) take a `ModelRegistry` (a record of IO actions) so
offline tests can drive an in-memory mock. `console.warn`/`console.error` side
effects are returned as `warning`/`error` strings instead of printed.

Glob matching (`minimatch` subset) supports `*`, `?`, `[...]`, `[!...]`,
case-insensitive. `findInitialModel` throws `IO.userError` on a CLI provider/model
error (Pi `process.exit(1)`); the CLI caller exits accordingly.
-/

namespace LeanAgent.CodingAgent.ModelResolver

open LeanAgent.Models
open LeanAgent.AI

/-- Pi `defaultModelPerProvider` (known-provider → default model id). -/
def defaultModelPerProvider : Array (String × String) :=
  #[ ("amazon-bedrock", "us.anthropic.claude-opus-4-6-v1")
   , ("ant-ling", "Ring-2.6-1T")
   , ("anthropic", "claude-opus-4-8")
   , ("openai", "gpt-5.5")
   , ("azure-openai-responses", "gpt-5.4")
   , ("openai-codex", "gpt-5.5")
   , ("nvidia", "nvidia/nemotron-3-super-120b-a12b")
   , ("deepseek", "deepseek-v4-pro")
   , ("google", "gemini-3.1-pro-preview")
   , ("google-vertex", "gemini-3.1-pro-preview")
   , ("github-copilot", "gpt-5.4")
   , ("openrouter", "moonshotai/kimi-k2.6")
   , ("vercel-ai-gateway", "zai/glm-5.1")
   , ("xai", "grok-4.20-0309-reasoning")
   , ("groq", "openai/gpt-oss-120b")
   , ("cerebras", "zai-glm-4.7")
   , ("zai", "glm-5.1")
   , ("zai-coding-cn", "glm-5.1")
   , ("mistral", "devstral-medium-latest")
   , ("minimax", "MiniMax-M2.7")
   , ("minimax-cn", "MiniMax-M2.7")
   , ("moonshotai", "kimi-k2.6")
   , ("moonshotai-cn", "kimi-k2.6")
   , ("huggingface", "moonshotai/Kimi-K2.6")
   , ("fireworks", "accounts/fireworks/models/kimi-k2p6")
   , ("together", "moonshotai/Kimi-K2.6")
   , ("opencode", "kimi-k2.6")
   , ("opencode-go", "kimi-k2.6")
   , ("kimi-coding", "kimi-for-coding")
   , ("cloudflare-workers-ai", "@cf/moonshotai/kimi-k2.6")
   , ("cloudflare-ai-gateway", "workers-ai/@cf/moonshotai/kimi-k2.6")
   , ("xiaomi", "mimo-v2.5-pro")
   , ("xiaomi-token-plan-cn", "mimo-v2.5-pro")
   , ("xiaomi-token-plan-ams", "mimo-v2.5-pro")
   , ("xiaomi-token-plan-sgp", "mimo-v2.5-pro")
   ]

/-- Look up the default model id for a provider. -/
def defaultModelId? (provider : String) : Option String :=
  (defaultModelPerProvider.find? (fun p => p.1 == provider)).map (·.2)

/-- Pi `DEFAULT_THINKING_LEVEL` as a `ModelThinkingLevel`. -/
def defaultThinkingLevel : ModelThinkingLevel := .level .medium

/-- Pi `isValidThinkingLevel`. -/
def isValidThinkingLevel (level : String) : Bool :=
  (ModelThinkingLevel.fromString? level).isSome

-- ============================================================================
-- String helpers (index-based over List Char)
-- ============================================================================

/-- First index of `c` in `s`, if present. -/
def indexOfChar? (s : String) (c : Char) : Option Nat :=
  s.toList.findIdx? (fun x => x == c)

/-- Last index of `c` in `s`, if present. -/
def lastIndexOfChar? (s : String) (c : Char) : Option Nat :=
  let chars := s.toList
  match chars.reverse.findIdx? (fun x => x == c) with
  | some i => some (chars.length - 1 - i)
  | none => none

/-- Substring `s[start:stop)` (Nat indices over `toList`). -/
def substring (s : String) (start stop : Nat) : String :=
  String.ofList (s.toList.extract start stop)

/-- `a.id == b.id && a.provider == b.provider` (Pi `modelsAreEqual`, non-Option). -/
def modelsEqual (a b : ModelInfo) : Bool := a.id == b.id && a.provider == b.provider

/-- `true` iff `id` ends with `-latest` or has no `-YYYYMMDD` date suffix (Pi `isAlias`). -/
def isAlias (id : String) : Bool :=
  if id.endsWith "-latest" then true
  else
    -- Check for a trailing -DDDDDDDD (8 digits) date suffix.
    let chars := id.toList
    let len := chars.length
    if len < 9 then true
    else
      let tail9 := chars.drop (len - 9)  -- last 9 chars: dash + 8 digits
      match tail9 with
      | '-' :: date => if date.all Char.isDigit then false else true
      | _ => true

-- ============================================================================
-- Matching
-- ============================================================================

/--
Pi `findExactModelReferenceMatch`: bare id or canonical `provider/id`. Bare-id
matches across providers are rejected (ambiguous → none).
-/
def findExactModelReferenceMatch (modelReference : String) (availableModels : Array ModelInfo) :
    Option ModelInfo :=
  let trimmed := modelReference.trim
  if trimmed.isEmpty then none
  else
    let normalized := trimmed.toLower
    let canonicalMatches := availableModels.filter (fun m =>
      (m.provider ++ "/" ++ m.id).toLower == normalized)
    if canonicalMatches.size == 1 then canonicalMatches[0]?
    else if canonicalMatches.size > 1 then none
    else
      match indexOfChar? trimmed '/' with
      | some slashIndex =>
          let provider := (substring trimmed 0 slashIndex).trim
          let modelId := (substring trimmed (slashIndex + 1) trimmed.length).trim
          if !provider.isEmpty && !modelId.isEmpty then
            let providerMatches := availableModels.filter (fun m =>
              m.provider.toLower == provider.toLower && m.id.toLower == modelId.toLower)
            if providerMatches.size == 1 then providerMatches[0]?
            else if providerMatches.size > 1 then none
            else
              let idMatches := availableModels.filter (fun m => m.id.toLower == normalized)
              if idMatches.size == 1 then idMatches[0]? else none
          else
            let idMatches := availableModels.filter (fun m => m.id.toLower == normalized)
            if idMatches.size == 1 then idMatches[0]? else none
      | none =>
          let idMatches := availableModels.filter (fun m => m.id.toLower == normalized)
          if idMatches.size == 1 then idMatches[0]? else none

/-- Pi `tryMatchModel`: exact first, then partial id/name, preferring aliases. -/
def tryMatchModel (modelPattern : String) (availableModels : Array ModelInfo) : Option ModelInfo :=
  match findExactModelReferenceMatch modelPattern availableModels with
  | some m => some m
  | none =>
      let lower := modelPattern.toLower
      let matchesArr := availableModels.filter (fun m =>
        m.id.toLower.contains lower || m.name.toLower.contains lower)
      if matchesArr.isEmpty then none
      else
        let aliases := matchesArr.filter (fun m => isAlias m.id)
        let dated := matchesArr.filter (fun m => !isAlias m.id)
        if !aliases.isEmpty then
          let sorted := aliases.qsort (fun a b => b.id < a.id)
          sorted[0]?
        else
          let sorted := dated.qsort (fun a b => b.id < a.id)
          sorted[0]?

-- ============================================================================
-- parseModelPattern
-- ============================================================================

structure ParsedModelResult where
  model : Option ModelInfo := none
  thinkingLevel : Option ModelThinkingLevel := none
  warning : Option String := none
deriving Inhabited

/-- Pi `parseModelPattern` (recursive colon-suffix stripping). -/
partial def parseModelPattern
    (pattern : String) (availableModels : Array ModelInfo)
    (allowInvalidFallback : Bool := true) : ParsedModelResult :=
  match tryMatchModel pattern availableModels with
  | some m => { model := some m, thinkingLevel := none, warning := none }
  | none =>
      match lastIndexOfChar? pattern ':' with
      | none => { model := none, thinkingLevel := none, warning := none }
      | some idx =>
          let pfx := substring pattern 0 idx
          let suffix := substring pattern (idx + 1) pattern.length
          if isValidThinkingLevel suffix then
            match parseModelPattern pfx availableModels allowInvalidFallback with
            | { model := some m, warning := w, .. } =>
                { model := some m
                  thinkingLevel := if w.isSome then none else ModelThinkingLevel.fromString? suffix
                  warning := w }
            | other => other
          else
            if !allowInvalidFallback then
              { model := none, thinkingLevel := none, warning := none }
            else
              match parseModelPattern pfx availableModels allowInvalidFallback with
              | { model := some m, .. } =>
                  { model := some m, thinkingLevel := none
                    warning := some
                      s!"Invalid thinking level \"{suffix}\" in pattern \"{pattern}\". Using default instead." }
              | other => other

-- ============================================================================
-- Glob matcher (minimatch subset)
-- ============================================================================

/-- `true` iff `text` matches `pattern` (`*`, `?`, `[...]`, `[!...]`, nocase). -/
partial def globMatch (text : String) (pattern : String) : Bool :=
  let rec go (t : List Char) (p : List Char) : Bool :=
    match p with
    | [] => t.isEmpty
    | '*' :: rest =>
        -- match zero or more chars (keep `*` while consuming)
        if t.isEmpty then go t rest
        else go t rest || go t.tail ('*' :: rest)
    | '?' :: rest => match t with | _ :: tt => go tt rest | [] => false
    | '[' :: rest =>
        -- char class, optional leading '!'
        let (negated, classRest) := match rest with | '!' :: r => (true, r) | _ => (false, rest)
        let rec readClass (cs : List Char) (acc : List Char) : List Char × List Char :=
          match cs with
          | ']' :: r => (acc.reverse, r)
          | c :: r => readClass r (c :: acc)
          | [] => (acc.reverse, [])
        let (clazz, after) := readClass classRest []
        match t with
        | c :: tt =>
            let inClass := clazz.contains c
            let matched := if negated then !inClass else inClass
            if matched then go tt after else false
        | [] => false
    | c :: rest => match t with | tc :: tt => if tc == c then go tt rest else false | [] => false
  go text.toList pattern.toList

-- ============================================================================
-- Registry + scope resolution
-- ============================================================================

/-- Pi `ModelRegistry` interface (subset used by the resolver). -/
structure ModelRegistry where
  getAll : IO (Array ModelInfo)
  getAvailable : IO (Array ModelInfo)
  find : String → String → IO (Option ModelInfo)
  hasConfiguredAuth : ModelInfo → IO Bool

/-- Pi `ScopedModel`. -/
structure ScopedModel where
  model : ModelInfo
  thinkingLevel : Option ModelThinkingLevel := none

/--
Pi `resolveModelScope`: resolve glob/exact patterns to scoped models.
Returns the scoped models (warnings are dropped; Pi `console.warn`s).
-/
def resolveModelScope (patterns : Array String) (registry : ModelRegistry) :
    IO (Array ScopedModel) := do
  let availableModels ← registry.getAvailable
  let mut scopedModels := #[]
  for pattern in patterns do
    if pattern.contains "*" || pattern.contains "?" || pattern.contains "[" then
      let (globPattern, thinkingLevel) :=
        match lastIndexOfChar? pattern ':' with
        | some idx =>
            let suffix := substring pattern (idx + 1) pattern.length
            if isValidThinkingLevel suffix then
              (substring pattern 0 idx, ModelThinkingLevel.fromString? suffix)
            else (pattern, none)
        | none => (pattern, none)
      let matchingModels := availableModels.filter (fun m =>
        globMatch (m.provider ++ "/" ++ m.id) globPattern || globMatch m.id globPattern)
      for model in matchingModels do
        if !scopedModels.any (fun sm => modelsEqual sm.model model) then
          scopedModels := scopedModels.push { model := model, thinkingLevel := thinkingLevel }
    else
      let result := parseModelPattern pattern availableModels
      match result.model with
      | some model =>
          if !scopedModels.any (fun sm => modelsEqual sm.model model) then
            scopedModels := scopedModels.push { model := model, thinkingLevel := result.thinkingLevel }
      | none => pure ()
  pure scopedModels

-- ============================================================================
-- resolveCliModel
-- ============================================================================

structure ResolveCliModelResult where
  model : Option ModelInfo := none
  thinkingLevel : Option ModelThinkingLevel := none
  warning : Option String := none
  error : Option String := none
deriving Inhabited

/-- Pi `buildFallbackModel`: synthesize a custom model id for a known provider. -/
def buildFallbackModel (provider : String) (modelId : String) (availableModels : Array ModelInfo) :
    Option ModelInfo :=
  let providerModels : Array ModelInfo := availableModels.filter (fun (m : ModelInfo) => m.provider == provider)
  match providerModels[0]? with
  | none => none
  | some base0 =>
      let base :=
        match defaultModelId? provider with
        | some defaultId =>
            match providerModels.find? (fun (m : ModelInfo) => m.id == defaultId) with
            | some b => b
            | none => base0
        | none => base0
      some { base with id := modelId, name := modelId }

/--
Pi `resolveCliModel`: resolve `--provider`/`--model`/`--thinking` flags.
Supports `provider/model` inference, fuzzy matching, custom-id fallback, and
`:thinking` suffix parsing (strict: invalid suffixes stay part of the id).
-/
def resolveCliModel
    (cliProvider? cliModel? cliThinking? : Option String) (registry : ModelRegistry) :
    IO ResolveCliModelResult := do
  match cliModel? with
  | none => return { model := none, thinkingLevel := none, warning := none, error := none }
  | some cliModel =>
    let availableModels ← registry.getAll
    if availableModels.isEmpty then
      return { error := some "No models available. Check your installation or add models to models.json." }
    let providerMap : Std.HashMap String String :=
      availableModels.foldl (fun acc m => acc.insert m.provider.toLower m.provider) {}
    let provider := cliProvider?.bind (fun cp => providerMap.get? cp.toLower)
    if cliProvider?.isSome && provider.isNone then
      let cliProv := cliProvider?.getD ""
      let msg := s!"Unknown provider \"{cliProv}\". Use --list-models to see available providers/models."
      return { error := some msg }
    let mut pattern := cliModel
    let mut inferredProvider := false
    let mut provider' := provider
    if provider'.isNone then
      match indexOfChar? cliModel '/' with
      | some slashIndex =>
          let maybeProvider := substring cliModel 0 slashIndex
          match providerMap.get? maybeProvider.toLower with
          | some canonical =>
              provider' := some canonical
              pattern := substring cliModel (slashIndex + 1) cliModel.length
              inferredProvider := true
          | none => pure ()
      | none => pure ()
    if provider'.isNone then
      let lower := cliModel.toLower
      match availableModels.find? (fun m =>
        m.id.toLower == lower || (m.provider ++ "/" ++ m.id).toLower == lower) with
      | some e => return { model := some e, thinkingLevel := none, warning := none, error := none }
      | none => pure ()
    if cliProvider?.isSome && provider'.isSome then
      let prefixStr := (provider'.getD "") ++ "/"
      if cliModel.toLower.startsWith prefixStr.toLower then
        pattern := substring cliModel prefixStr.length cliModel.length
    let candidates :=
      match provider' with
      | some p => availableModels.filter (fun m => m.provider == p)
      | none => availableModels
    let pmr := parseModelPattern pattern candidates false
    match pmr.model with
    | some model =>
        if inferredProvider then
          let rawExactMatches := availableModels.filter (fun m =>
            m.id.toLower == cliModel.toLower && !modelsEqual m model)
          if !rawExactMatches.isEmpty && !(← registry.hasConfiguredAuth model) then
            let mut authenticatedRawMatches := #[]
            for m in rawExactMatches do
              if (← registry.hasConfiguredAuth m) then authenticatedRawMatches := authenticatedRawMatches.push m
            if authenticatedRawMatches.size == 1 then
              match authenticatedRawMatches[0]? with
              | some m => return { model := some m, thinkingLevel := none, warning := none, error := none }
              | none => pure ()
        return { model := some model, thinkingLevel := pmr.thinkingLevel, warning := pmr.warning, error := none }
    | none =>
        if inferredProvider then
          let lower := cliModel.toLower
          match availableModels.find? (fun m =>
            m.id.toLower == lower || (m.provider ++ "/" ++ m.id).toLower == lower) with
          | some e => return { model := some e, thinkingLevel := none, warning := none, error := none }
          | none =>
              let fallback := parseModelPattern cliModel availableModels false
              match fallback.model with
              | some fm => return { model := some fm, thinkingLevel := fallback.thinkingLevel, warning := fallback.warning, error := none }
              | none => pure ()
        match provider' with
        | some provider =>
            let mut fallbackPattern := pattern
            let mut fallbackThinking : Option ModelThinkingLevel := none
            if cliThinking?.isNone then
              match lastIndexOfChar? pattern ':' with
              | some lastColon =>
                  let suffix := substring pattern (lastColon + 1) pattern.length
                  if isValidThinkingLevel suffix then
                    fallbackPattern := substring pattern 0 lastColon
                    fallbackThinking := ModelThinkingLevel.fromString? suffix
              | none => pure ()
            match buildFallbackModel provider fallbackPattern availableModels with
            | some fallbackModel =>
                let cliThinkingLvl? := cliThinking?.bind ModelThinkingLevel.fromString?
                let requestedThinking := cliThinkingLvl?.orElse (fun _ => fallbackThinking)
                let model :=
                  match requestedThinking with
                  | some (.level _) => { fallbackModel with reasoning := true }
                  | _ => fallbackModel
                let fallbackWarning :=
                  match pmr.warning with
                  | some w => some (w ++ s!" Model \"{fallbackPattern}\" not found for provider \"{provider}\". Using custom model id.")
                  | none => some s!"Model \"{fallbackPattern}\" not found for provider \"{provider}\". Using custom model id."
                return { model := some model, thinkingLevel := fallbackThinking, warning := fallbackWarning, error := none }
            | none => pure ()
        | none => pure ()
        let display := match provider' with
          | some p => s!"{p}/{pattern}"
          | none => cliModel
        let errMsg := s!"Model \"{display}\" not found. Use --list-models to see available models."
        return { model := none, thinkingLevel := none, warning := pmr.warning, error := some errMsg }

-- ============================================================================
-- findInitialModel
-- ============================================================================

/-- Pick the first known-provider default model present in `availableModels`,
else the first available model. Returns `none` only when `availableModels` is empty. -/
def pickDefaultOrFirst (availableModels : Array ModelInfo) : Option ModelInfo :=
  (defaultModelPerProvider.findSome? fun (provider, defaultId) =>
    availableModels.find? (fun (m : ModelInfo) => m.provider == provider && m.id == defaultId))
    |>.orElse (fun _ => availableModels[0]?)

structure InitialModelResult where
  model : Option ModelInfo := none
  thinkingLevel : ModelThinkingLevel := defaultThinkingLevel
  fallbackMessage : Option String := none
deriving Inhabited

/--
Pi `findInitialModel`: priority — CLI args, first scoped model (unless
continuing), saved default, first available (preferring known-provider defaults).
Throws on a CLI provider/model error (Pi `process.exit(1)`).
-/
def findInitialModel
    (cliProvider? cliModel? : Option String) (scopedModels : Array ScopedModel)
    (isContinuing : Bool) (defaultProvider? defaultModelId? : Option String)
    (defaultThinkingLevel? : Option ModelThinkingLevel) (registry : ModelRegistry) :
    IO InitialModelResult := do
  if cliProvider?.isSome && cliModel?.isSome then
    let resolved ← resolveCliModel cliProvider? cliModel? none registry
    if resolved.error.isSome then
      throw (IO.userError (resolved.error.getD ""))
    match resolved.model with
    | some m => return { model := some m, thinkingLevel := defaultThinkingLevel, fallbackMessage := none }
    | none => pure ()
  if !scopedModels.isEmpty && !isContinuing then
    match scopedModels[0]? with
    | some first =>
        let tl := first.thinkingLevel.orElse (fun _ => defaultThinkingLevel?) |>.getD defaultThinkingLevel
        return { model := some first.model, thinkingLevel := tl, fallbackMessage := none }
    | none => pure ()
  if defaultProvider?.isSome && defaultModelId?.isSome then
    match ← registry.find (defaultProvider?.getD "") (defaultModelId?.getD "") with
    | some found =>
        let tl := defaultThinkingLevel?.getD defaultThinkingLevel
        return { model := some found, thinkingLevel := tl, fallbackMessage := none }
    | none => pure ()
  let availableModels ← registry.getAvailable
  if !availableModels.isEmpty then
    match pickDefaultOrFirst availableModels with
    | some m => return { model := some m, thinkingLevel := defaultThinkingLevel, fallbackMessage := none }
    | none => pure ()
  return { model := none, thinkingLevel := defaultThinkingLevel, fallbackMessage := none }

-- ============================================================================
-- restoreModelFromSession
-- ============================================================================

/-- Pi `restoreModelFromSession`: restore a saved model or fall back.
`shouldPrintMessages` is honored (stderr/stdout prints) — kept as a side-effect
no-op here; the fallback message carries the same text. -/
def restoreModelFromSession
    (savedProvider savedModelId : String) (currentModel? : Option ModelInfo)
    (_shouldPrintMessages : Bool) (registry : ModelRegistry) :
    IO (Option ModelInfo × Option String) := do
  let restoredModel? ← registry.find savedProvider savedModelId
  let hasAuth ← match restoredModel? with
    | some m => registry.hasConfiguredAuth m
    | none => pure false
  match restoredModel? with
  | some m =>
      if hasAuth then return (some m, none)
      else
        let reason := "no auth configured"
        match currentModel? with
        | some cm =>
            return (some cm,
              some s!"Could not restore model {savedProvider}/{savedModelId} ({reason}). Using {cm.provider}/{cm.id}.")
        | none =>
            let availableModels ← registry.getAvailable
            match pickDefaultOrFirst availableModels with
            | some fm =>
                return (some fm,
                  some s!"Could not restore model {savedProvider}/{savedModelId} ({reason}). Using {fm.provider}/{fm.id}.")
            | none => return (none, none)
  | none =>
      let reason := "model no longer exists"
      match currentModel? with
      | some cm =>
          return (some cm,
            some s!"Could not restore model {savedProvider}/{savedModelId} ({reason}). Using {cm.provider}/{cm.id}.")
      | none =>
          let availableModels ← registry.getAvailable
          match pickDefaultOrFirst availableModels with
          | some fm =>
              return (some fm,
                some s!"Could not restore model {savedProvider}/{savedModelId} ({reason}). Using {fm.provider}/{fm.id}.")
          | none => return (none, none)

end LeanAgent.CodingAgent.ModelResolver