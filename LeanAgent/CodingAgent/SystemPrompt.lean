import Lean
import LeanAgent.CodingAgent.Config

/-!
# System prompt construction (Pi `packages/coding-agent/src/core/system-prompt.ts`)

Builds the system prompt sent to the LLM at session start. The prompt includes:
- Tool descriptions (one-line snippets per tool)
- Guidelines (auto-generated from available tools + caller-provided)
- Pi documentation paths
- Project context files (AGENTS.md, CLAUDE.md, etc.)
- Available skills
- Current date and working directory

Supports a `customPrompt` mode that replaces the default preamble but still
appends context files, skills, date, and cwd.
-/

namespace LeanAgent.CodingAgent.SystemPrompt

open LeanAgent.CodingAgent.Config

-- ============================================================================
-- Types
-- ============================================================================

/-- Pi `Skill` type (subset used by system prompt). -/
structure Skill where
  name : String
  description : String
  filePath : String
  disableModelInvocation : Bool := false
deriving Inhabited

/-- Pi `BuildSystemPromptOptions`. -/
structure BuildSystemPromptOptions where
  /-- Custom system prompt (replaces default preamble). -/
  customPrompt : Option String := none
  /-- Tools to include in prompt. Default: [read, bash, edit, write]. -/
  selectedTools : Array String := #["read", "bash", "edit", "write"]
  /-- Optional one-line tool snippets keyed by tool name. -/
  toolSnippets : Std.HashMap String String := {}
  /-- Additional guideline bullets appended to the defaults. -/
  promptGuidelines : Array String := #[]
  /-- Text to append to the system prompt (after guidelines, before context). -/
  appendSystemPrompt : Option String := none
  /-- Working directory (shown in prompt). -/
  cwd : String
  /-- Pre-loaded project context files (AGENTS.md, etc.). -/
  contextFiles : Array (String × String) := #[]
  /-- Pre-loaded skills. -/
  skills : Array Skill := #[]
  /-- Override for README path (Pi resolves `<packageDir>/README.md`). -/
  readmePath : Option String := none
  /-- Override for docs path. -/
  docsPath : Option String := none
  /-- Override for examples path. -/
  examplesPath : Option String := none
  /-- Override for today's date (YYYY-MM-DD). Injected for offline tests. -/
  dateOverride : Option String := none
deriving Inhabited

-- ============================================================================
-- Helpers
-- ============================================================================

/-- Escape XML special characters in a string. -/
def escapeXml (value : String) : String :=
  value.replace "&" "&amp;"
    |>.replace "<" "&lt;"
    |>.replace ">" "&gt;"
    |>.replace "\"" "&quot;"
    |>.replace "'" "&apos;"

/-- Pi `formatSkillsForPrompt`: render available skills as an XML block. -/
def formatSkillsForPrompt (skills : Array Skill) : String :=
  let visible := skills.filter (fun s => !s.disableModelInvocation)
  if visible.isEmpty then
    ""
  else
    let header :=
      #["The following skills provide specialized instructions for specific tasks."
        , "Use the read tool to load a skill's file when the task matches its description."
        , "When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands."
        , ""
        , "<available_skills>"
        ]
    let body := Id.run do
      let mut lines : Array String := #[]
      for skill in visible do
        lines :=
          lines
            ++ #["  <skill>"
                , s!"    <name>{escapeXml skill.name}</name>"
                , s!"    <description>{escapeXml skill.description}</description>"
                , s!"    <location>{escapeXml skill.filePath}</location>"
                , "  </skill>"
                ]
      pure lines
    let lines := header ++ body ++ #["</available_skills>"]
    String.intercalate "\n" lines.toList

/-- Get today's date as YYYY-MM-DD (injectable for offline tests). -/
def todayDate (override : Option String := none) : IO String := do
  match override with
  | some d => pure d
  | none => pure "2025-07-19"  -- Placeholder; real implementation needs time library

/-- Normalize backslashes to forward slashes for prompt display. -/
def normalizeCwd (cwd : String) : String :=
  cwd.replace "\\" "/"

-- ============================================================================
-- buildSystemPrompt
-- ============================================================================

/--
Pi `buildSystemPrompt`: construct the full system prompt.

When `customPrompt` is set, it replaces the default preamble. Context files,
skills, date, and cwd are still appended.

Otherwise, builds the default pi coding-agent prompt with:
- Tool list (only tools with snippets are shown)
- Auto-generated guidelines based on available tools
- Caller-provided guideline bullets
- Pi documentation paths
- Append section
- Project context files
- Skills block (only if `read` tool is available)
- Current date and working directory
-/
def buildSystemPrompt (options : BuildSystemPromptOptions) : IO String := do
  let appendSection :=
    match options.appendSystemPrompt with
    | some s => "\n\n" ++ s
    | none => ""

  let contextFiles := options.contextFiles
  let skills := options.skills

  -- Custom prompt path: use caller's text, append context/skills/date/cwd.
  if let some customPrompt := options.customPrompt then
    let mut prompt := customPrompt
    if appendSection != "" then
      prompt := prompt ++ appendSection
    -- Append project context files.
    if contextFiles.size > 0 then
      prompt := prompt ++ "\n\n<project_context>\n\n"
      prompt := prompt ++ "Project-specific instructions and guidelines:\n\n"
      for (filePath, content) in contextFiles do
        prompt := prompt ++ s!"<project_instructions path=\"{filePath}\">\n{content}\n</project_instructions>\n\n"
      prompt := prompt ++ "</project_context>\n"
    -- Append skills section (only if read tool is available).
    let customPromptHasRead := options.selectedTools.isEmpty || options.selectedTools.contains "read"
    if customPromptHasRead && skills.size > 0 then
      prompt := prompt ++ formatSkillsForPrompt skills
    -- Add date and working directory last.
    let date ← todayDate options.dateOverride
    prompt := prompt ++ s!"\nCurrent date: {date}"
    prompt := prompt ++ s!"\nCurrent working directory: {normalizeCwd options.cwd}"
    return prompt

  -- Default prompt path.
  -- Resolve documentation paths.
  let readmePath ← match options.readmePath with
    | some p => pure p
    | none => pure "/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/README.md"
  let docsPath ← match options.docsPath with
    | some p => pure p
    | none => do pure ((← getDocsPath none).toString)
  let examplesPath ← match options.examplesPath with
    | some p => pure p
    | none => pure "/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/examples"

  -- Build tools list. A tool appears only when the caller provides a snippet.
  let tools :=
    if options.selectedTools.isEmpty then
      #["read", "bash", "edit", "write"]
    else
      options.selectedTools
  let visibleTools := tools.filter (fun name => options.toolSnippets.contains name)
  let toolsList :=
    if visibleTools.isEmpty then
      "(none)"
    else
      String.intercalate "\n" (visibleTools.toList.map fun name =>
        s!"- {name}: {options.toolSnippets.get? name |>.getD ""}")

  -- Build guidelines based on available tools.
  let mut guidelinesList : Array String := #[]
  let mut guidelinesSet : Std.HashSet String := {}

  let hasBash := tools.contains "bash"
  let hasGrep := tools.contains "grep"
  let hasFind := tools.contains "find"
  let hasLs := tools.contains "ls"
  let hasRead := tools.contains "read"

  -- File exploration guidelines.
  if hasBash && !hasGrep && !hasFind && !hasLs then
    if !guidelinesSet.contains "Use bash for file operations like ls, rg, find" then
      guidelinesSet := guidelinesSet.insert "Use bash for file operations like ls, rg, find"
      guidelinesList := guidelinesList.push "Use bash for file operations like ls, rg, find"

  -- Caller-provided guidelines.
  for guideline in options.promptGuidelines do
    let normalized := guideline.trimAscii.toString
    if !normalized.isEmpty && !guidelinesSet.contains normalized then
      guidelinesSet := guidelinesSet.insert normalized
      guidelinesList := guidelinesList.push normalized

  -- Always include these.
  if !guidelinesSet.contains "Be concise in your responses" then
    guidelinesSet := guidelinesSet.insert "Be concise in your responses"
    guidelinesList := guidelinesList.push "Be concise in your responses"
  if !guidelinesSet.contains "Show file paths clearly when working with files" then
    guidelinesSet := guidelinesSet.insert "Show file paths clearly when working with files"
    guidelinesList := guidelinesList.push "Show file paths clearly when working with files"

  let guidelines := String.intercalate "\n" (guidelinesList.toList.map (fun g => s!"- {g}"))

  -- Build the default preamble.
  let mut prompt :=
    s!"You are an expert coding assistant operating inside pi, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files.

Available tools:
{toolsList}

In addition to the tools above, you may have access to other custom tools depending on the project.

Guidelines:
{guidelines}

Pi documentation (read only when the user asks about pi itself, its SDK, extensions, themes, skills, or TUI):
- Main documentation: {readmePath}
- Additional docs: {docsPath}
- Examples: {examplesPath} (extensions, custom tools, SDK)
- When reading pi docs or examples, resolve docs/... under Additional docs and examples/... under Examples, not the current working directory
- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI components (docs/tui.md), keybindings (docs/keybindings.md), SDK integrations (docs/sdk.md), custom providers (docs/custom-provider.md), adding models (docs/models.md), pi packages (docs/packages.md)
- When working on pi topics, read the docs and examples, and follow .md cross-references before implementing
- Always read pi .md files completely and follow links to related docs (e.g., tui.md for TUI API details)"

  if appendSection != "" then
    prompt := prompt ++ appendSection

  -- Append project context files.
  if contextFiles.size > 0 then
    prompt := prompt ++ "\n\n<project_context>\n\n"
    prompt := prompt ++ "Project-specific instructions and guidelines:\n\n"
    for (filePath, content) in contextFiles do
      prompt := prompt ++ s!"<project_instructions path=\"{filePath}\">\n{content}\n</project_instructions>\n\n"
    prompt := prompt ++ "</project_context>\n"

  -- Append skills section (only if read tool is available).
  if hasRead && skills.size > 0 then
    prompt := prompt ++ formatSkillsForPrompt skills

  -- Add date and working directory last.
  let date ← todayDate options.dateOverride
  prompt := prompt ++ s!"\nCurrent date: {date}"
  prompt := prompt ++ s!"\nCurrent working directory: {normalizeCwd options.cwd}"

  return prompt

end LeanAgent.CodingAgent.SystemPrompt
