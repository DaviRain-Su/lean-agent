import Lean
import LeanAgent.Json
import LeanAgent.CodingAgent.Utils.JsonComments

/-!
# Keybindings (Pi `packages/coding-agent/src/core/keybindings.ts`)

App-level keybinding registry, the legacy-name → namespaced-id migration, and a
minimal `KeybindingsManager` that loads `keybindings.json`, migrates legacy
keys in memory, and reports the effective (defaults ∪ user) config.

Pi's `KEYBINDINGS` spreads `TUI_KEYBINDINGS` (from `@earendil-works/pi-tui`)
together with the app.* entries; the Lean port models the app.* subset and a
fixed ordering key list. The `KeybindingsManager` here does not extend a TUI
base class (pi-tui is not ported) — it implements the load/migrate/merge
surface the offline tests exercise.
-/

namespace LeanAgent.CodingAgent.Keybindings

open LeanAgent.CodingAgent.Utils.JsonComments

-- ============================================================================
-- App keybinding registry (Pi `KEYBINDINGS` app.* subset)
-- ============================================================================

/-- A keybinding value: a single key id or a list of key ids. -/
inductive KeyBindingValue where
  | single : String → KeyBindingValue
  | list : Array String → KeyBindingValue
deriving Inhabited, BEq, Repr

instance : ToString KeyBindingValue where
  toString
    | .single s => s
    | .list arr => toString arr

/-- Render a value back to JSON. -/
def KeyBindingValue.toJson : KeyBindingValue → Lean.Json
  | .single s => Lean.Json.str s
  | .list arr => Lean.Json.arr (arr.map Lean.Json.str)

/-- Coerce a `Lean.Json` value into a `KeyBindingValue`, or `none`. -/
def KeyBindingValue.fromJson? : Lean.Json → Option KeyBindingValue
  | .str s => some (.single s)
  | .arr arr => Id.run do
    let mut out : Array String := #[]
    let mut ok := true
    for v in arr do
      match v.getStr? with
      | .ok s => out := out.push s
      | .error _ => ok := false
    pure (if ok && !out.isEmpty then some (.list out) else none)
  | _ => none

/-- A registry entry: default keys + human description. -/
structure KeyBindingDef where
  defaultKeys : KeyBindingValue
  description : String
deriving Inhabited

/-- The app.* keybinding defaults (Pi `KEYBINDINGS` app subset). -/
def appKeybindings : Array (String × KeyBindingDef) :=
  #[ ("app.interrupt", { defaultKeys := .single "escape", description := "Cancel or abort" })
   , ("app.clear", { defaultKeys := .single "ctrl+c", description := "Clear editor" })
   , ("app.exit", { defaultKeys := .single "ctrl+d", description := "Exit when editor is empty" })
   , ("app.tools.expand", { defaultKeys := .single "ctrl+o", description := "Toggle tool output" })
   ]

/-- The ordering key list used by `orderKeybindingsConfig` (app.* keys, then
sorted extras). Pi iterates `Object.keys(KEYBINDINGS)`; we use the app.* keys. -/
def keybindingOrder : Array String := appKeybindings.map (·.1)

-- ============================================================================
-- Legacy-name migration (Pi `KEYBINDING_NAME_MIGRATIONS`)
-- ============================================================================

/-- Pi `KEYBINDING_NAME_MIGRATIONS` — old key name → namespaced id. -/
def keybindingNameMigrations : Array (String × String) :=
  #[ ("cursorUp", "tui.editor.cursorUp")
   , ("cursorDown", "tui.editor.cursorDown")
   , ("cursorLeft", "tui.editor.cursorLeft")
   , ("cursorRight", "tui.editor.cursorRight")
   , ("cursorWordLeft", "tui.editor.cursorWordLeft")
   , ("cursorWordRight", "tui.editor.cursorWordRight")
   , ("cursorLineStart", "tui.editor.cursorLineStart")
   , ("cursorLineEnd", "tui.editor.cursorLineEnd")
   , ("jumpForward", "tui.editor.jumpForward")
   , ("jumpBackward", "tui.editor.jumpBackward")
   , ("pageUp", "tui.editor.pageUp")
   , ("pageDown", "tui.editor.pageDown")
   , ("deleteCharBackward", "tui.editor.deleteCharBackward")
   , ("deleteCharForward", "tui.editor.deleteCharForward")
   , ("deleteWordBackward", "tui.editor.deleteWordBackward")
   , ("deleteWordForward", "tui.editor.deleteWordForward")
   , ("deleteToLineStart", "tui.editor.deleteToLineStart")
   , ("deleteToLineEnd", "tui.editor.deleteToLineEnd")
   , ("yank", "tui.editor.yank")
   , ("yankPop", "tui.editor.yankPop")
   , ("undo", "tui.editor.undo")
   , ("newLine", "tui.input.newLine")
   , ("submit", "tui.input.submit")
   , ("tab", "tui.input.tab")
   , ("copy", "tui.input.copy")
   , ("selectUp", "tui.select.up")
   , ("selectDown", "tui.select.down")
   , ("selectPageUp", "tui.select.pageUp")
   , ("selectPageDown", "tui.select.pageDown")
   , ("selectConfirm", "tui.select.confirm")
   , ("selectCancel", "tui.select.cancel")
   , ("interrupt", "app.interrupt")
   , ("clear", "app.clear")
   , ("exit", "app.exit")
   , ("suspend", "app.suspend")
   , ("cycleThinkingLevel", "app.thinking.cycle")
   , ("cycleModelForward", "app.model.cycleForward")
   , ("cycleModelBackward", "app.model.cycleBackward")
   , ("selectModel", "app.model.select")
   , ("expandTools", "app.tools.expand")
   , ("toggleThinking", "app.thinking.toggle")
   , ("toggleSessionNamedFilter", "app.session.toggleNamedFilter")
   , ("externalEditor", "app.editor.external")
   , ("followUp", "app.message.followUp")
   , ("dequeue", "app.message.dequeue")
   , ("pasteImage", "app.clipboard.pasteImage")
   , ("newSession", "app.session.new")
   , ("tree", "app.session.tree")
   , ("fork", "app.session.fork")
   , ("resume", "app.session.resume")
   , ("treeFoldOrUp", "app.tree.foldOrUp")
   , ("treeUnfoldOrDown", "app.tree.unfoldOrDown")
   , ("treeEditLabel", "app.tree.editLabel")
   , ("treeToggleLabelTimestamp", "app.tree.toggleLabelTimestamp")
   , ("toggleSessionPath", "app.session.togglePath")
   , ("toggleSessionSort", "app.session.toggleSort")
   , ("renameSession", "app.session.rename")
   , ("deleteSession", "app.session.delete")
   , ("deleteSessionNoninvasive", "app.session.deleteNoninvasive")
   ]

/-- Look up the namespaced id for a legacy key name, or `none`. -/
def migrateKeyName? (key : String) : Option String :=
  (keybindingNameMigrations.find? (fun (k, _) => k == key)) |>.map (·.2)

-- ============================================================================
-- Config representation (ordered array of (key, value))
-- ============================================================================

/-- An ordered keybindings config: `Array (key × value)`. Later duplicate keys
win on lookup, but insertion order is preserved for serialization. -/
abbrev KeybindingsConfig := Array (String × KeyBindingValue)

/-- Build a `KeybindingsConfig` from a raw JSON object, validating each value
(Pi `toKeybindingsConfig`). Drops entries whose value is not a string or a
non-empty string array. -/
def toKeybindingsConfig (json : Lean.Json) : KeybindingsConfig := Id.run do
  match json.getObj? with
  | .ok obj =>
    let mut out : KeybindingsConfig := #[]
    for (k, v) in obj.toArray do
      match KeyBindingValue.fromJson? v with
      | some val => out := out.push (k, val)
      | none => pure ()
    pure out
  | .error _ => pure #[]

/-- Pi `orderKeybindingsConfig`: emit registry keys in `keybindingOrder` first,
then the remaining keys sorted alphabetically. -/
def orderKeybindingsConfig (config : KeybindingsConfig) : KeybindingsConfig := Id.run do
  let lookupKey (k : String) : Option KeyBindingValue := config.find? (fun (kk, _) => kk == k) |>.map (·.2)
  let hasKey (k : String) : Bool := (lookupKey k).isSome
  let mut ordered : KeybindingsConfig := #[]
  for k in keybindingOrder do
    if hasKey k then ordered := ordered.push (k, (lookupKey k).getD (.single ""))
  let emitted := ordered.map (·.1)
  let extras := config.filterMap (fun (k, v) =>
    if emitted.contains k then none else some (k, v))
  let extrasSorted := extras.qsort (fun a b => a.1 < b.1)
  for e in extrasSorted do ordered := ordered.push e
  pure ordered

/--
Pi `migrateKeybindingsConfig`: rewrite legacy key names to namespaced ids. When
both the legacy name and its namespaced target exist in the raw config, the
namespaced value wins and the legacy entry is dropped. Returns the migrated
config (re-ordered via `orderKeybindingsConfig`) plus a `migrated` flag.
-/
def migrateKeybindingsConfig (rawConfig : Lean.Json) : KeybindingsConfig × Bool := Id.run do
  let entries := match rawConfig.getObj? with
    | .ok obj => obj.toArray
    | .error _ => #[]
  let rawKeys := entries.map (·.1)
  let hasKey (k : String) : Bool := rawKeys.contains k
  let mut config : KeybindingsConfig := #[]
  let mut migrated := false
  for (key, value) in entries do
    match migrateKeyName? key with
    | some nextKey =>
      migrated := true
      if hasKey nextKey then
        pure ()
      else
        config := config.push (nextKey, KeyBindingValue.fromJson? value |>.getD (.single ""))
    | none =>
      config := config.push (key, KeyBindingValue.fromJson? value |>.getD (.single ""))
  pure (orderKeybindingsConfig config, migrated)

-- ============================================================================
-- KeybindingsManager (Pi `KeybindingsManager`, minimal)
-- ============================================================================

structure KeybindingsManager where
  userBindings : KeybindingsConfig
  configPath : Option System.FilePath := none
deriving Inhabited

/-- Pi `loadFromFile`: read + parse + migrate + validate a `keybindings.json`. -/
def KeybindingsManager.loadFromFile (path : System.FilePath) : IO KeybindingsConfig := do
  if !(← path.pathExists) then pure #[]
  else
    try
      let content ← IO.FS.readFile path
      let stripped := stripJsonComments content
      match Lean.Json.parse stripped with
      | .error _ => pure #[]
      | .ok json => pure (migrateKeybindingsConfig json |>.1 |> toKeybindingsConfigAlreadyValid)
    catch _ => pure #[]
  where
    /-- `migrateKeybindingsConfig` already validates values; this is identity. -/
    toKeybindingsConfigAlreadyValid (cfg : KeybindingsConfig) : KeybindingsConfig := cfg

/-- Pi `KeybindingsManager.create`: load `<agentDir>/keybindings.json`. -/
def KeybindingsManager.create (agentDir : System.FilePath) : IO KeybindingsManager := do
  let configPath := agentDir / "keybindings.json"
  let userBindings ← KeybindingsManager.loadFromFile configPath
  pure { userBindings := userBindings, configPath := some configPath }

/-- Reload bindings from the configured path (no-op if unset). -/
def KeybindingsManager.reload (mgr : KeybindingsManager) : IO KeybindingsManager := do
  match mgr.configPath with
  | none => pure mgr
  | some p =>
    let userBindings ← KeybindingsManager.loadFromFile p
    pure { mgr with userBindings := userBindings }

/-- Pi `getUserBindings`. -/
def KeybindingsManager.getUserBindings (mgr : KeybindingsManager) : KeybindingsConfig :=
  mgr.userBindings

/-- Look up a binding value in a config (last write wins). -/
def lookupBinding (config : KeybindingsConfig) (key : String) : Option KeyBindingValue :=
  config.find? (fun (k, _) => k == key) |>.map (·.2)

/--
Pi `getEffectiveConfig` / `getResolvedBindings`: merge the app.* defaults with
the user bindings (user wins), preserving registry order then sorted extras.
-/
def KeybindingsManager.getEffectiveConfig (mgr : KeybindingsManager) : KeybindingsConfig := Id.run do
  -- Start from default keys.
  let defaults : KeybindingsConfig := appKeybindings.map (fun (k, d) => (k, d.defaultKeys))
  -- Overlay user bindings (user wins).
  let mut effective : KeybindingsConfig := #[]
  let seen := (fun (k : String) => defaults.any (fun (kk, _) => kk == k))
  for (k, v) in defaults do
    match lookupBinding mgr.userBindings k with
    | some uv => effective := effective.push (k, uv)
    | none => effective := effective.push (k, v)
  -- Add user keys not in defaults (sorted).
  let extras := mgr.userBindings.filter (fun (k, _) => !seen k)
  let extrasSorted := extras.qsort (fun a b => a.1 < b.1)
  for e in extrasSorted do effective := effective.push e
  pure effective

end LeanAgent.CodingAgent.Keybindings
