import Lean

/-!
# Slash commands (Pi `packages/coding-agent/src/core/slash-commands.ts`)

Built-in slash command registry. Each command has a name, description, and
source classification (extension, prompt, or skill). The list is used by the
TUI and CLI to display available commands and dispatch `/name` invocations.

Extensions and prompt-template commands are discovered dynamically at runtime;
this module only defines the static built-in set.
-/

namespace LeanAgent.CodingAgent.SlashCommands

-- ============================================================================
-- Types
-- ============================================================================

/-- Pi `SlashCommandSource`. -/
inductive SlashCommandSource where
  | extension
  | prompt
  | skill
deriving Inhabited, BEq, DecidableEq, Repr

def SlashCommandSource.toString : SlashCommandSource → String
  | .extension => "extension"
  | .prompt => "prompt"
  | .skill => "skill"

/-- Pi `SlashCommandInfo`. -/
structure SlashCommandInfo where
  name : String
  description : Option String := none
  source : SlashCommandSource
  sourcePath : Option String := none
deriving Inhabited

/-- Pi `BuiltinSlashCommand`. -/
structure BuiltinSlashCommand where
  name : String
  description : String
deriving Inhabited

-- ============================================================================
-- Built-in commands
-- ============================================================================

/-- Pi `BUILTIN_SLASH_COMMANDS`. -/
def builtinSlashCommands : Array BuiltinSlashCommand :=
  #[
    { name := "settings", description := "Open settings menu" },
    { name := "model", description := "Select model (opens selector UI)" },
    { name := "scoped-models", description := "Enable/disable models for Ctrl+P cycling" },
    { name := "export", description := "Export session (HTML default, or specify path: .html/.jsonl)" },
    { name := "import", description := "Import and resume a session from a JSONL file" },
    { name := "share", description := "Share session as a secret GitHub gist" },
    { name := "copy", description := "Copy last agent message to clipboard" },
    { name := "name", description := "Set session display name" },
    { name := "session", description := "Show session info and stats" },
    { name := "changelog", description := "Show changelog entries" },
    { name := "hotkeys", description := "Show all keyboard shortcuts" },
    { name := "fork", description := "Create a new fork from a previous user message" },
    { name := "clone", description := "Duplicate the current session at the current position" },
    { name := "tree", description := "Navigate session tree (switch branches)" },
    { name := "trust", description := "Save project trust decision for future sessions" },
    { name := "login", description := "Configure provider authentication" },
    { name := "logout", description := "Remove provider authentication" },
    { name := "new", description := "Start a new session" },
    { name := "compact", description := "Manually compact the session context" },
    { name := "resume", description := "Resume a different session" },
    { name := "reload", description := "Reload keybindings, extensions, skills, prompts, and themes" },
    { name := "quit", description := "Quit pi" }
  ]

/-- Look up a built-in command by name. -/
def findBuiltin? (name : String) : Option BuiltinSlashCommand :=
  builtinSlashCommands.find? (fun c => c.name == name)

/-- True iff `name` is a built-in slash command. -/
def isBuiltin (name : String) : Bool :=
  (findBuiltin? name).isSome

/-- All built-in command names. -/
def builtinNames : Array String :=
  builtinSlashCommands.map (·.name)

end LeanAgent.CodingAgent.SlashCommands
