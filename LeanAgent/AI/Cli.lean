import LeanAgent.AI.OAuth

/-!
# Pi `packages/ai/src/cli.ts` offline surface

Pi's `pi-ai` CLI supports `list`, `login`, and help for OAuth providers.
Lean ports the non-interactive offline commands `list` / `help` used by
`lean-agent ai …`. Interactive OAuth login remains under Auth/OAuth modules.
-/

namespace LeanAgent.AI.Cli

def usage : String :=
  String.intercalate "\n"
    [ "Usage: lean-agent ai <command> [provider]"
    , ""
    , "Commands:"
    , "  list              List available OAuth providers"
    , "  help              Show this help"
    , "  login [provider]  Login to an OAuth provider (interactive; see OAuth modules)"
    , ""
    , "Examples:"
    , "  lean-agent ai list"
    , "  lean-agent ai help"
    ]

def renderProviderList (providers : Array LeanAgent.AI.OAuth.OAuthProviderInfo) : String :=
  if providers.isEmpty then
    "Available OAuth providers:\n\n(none registered)"
  else
    let lines :=
      providers.map fun p =>
        let avail := if p.available then "" else " (unavailable)"
        s!"  {p.id}  {p.name}{avail}"
    "Available OAuth providers:\n\n" ++ String.intercalate "\n" lines.toList

def listProviders : IO String := do
  -- Ensure built-ins are registered (import LeanAgent.AI.OAuth side effects).
  let providers ← LeanAgent.AI.OAuth.getOAuthProviderInfoList
  pure (renderProviderList providers)

/-- Parse `ai` subcommand args after the leading `ai` token. -/
inductive AiCommand where
  | help
  | list
  | login (providerId : Option String)
  | unknown (token : String)

def parseAiCommand (args : List String) : AiCommand :=
  match args with
  | [] => .help
  | "help" :: _ => .help
  | "--help" :: _ => .help
  | "-h" :: _ => .help
  | "list" :: _ => .list
  | "login" :: [] => .login none
  | "login" :: provider :: _ => .login (some provider)
  | token :: _ => .unknown token

/-- Run the AI CLI; returns process exit code. -/
def runAi (args : List String) : IO UInt32 := do
  match parseAiCommand args with
  | .help =>
      IO.println usage
      pure 0
  | .list =>
      IO.println (← listProviders)
      pure 0
  | .login providerId =>
      IO.eprintln
        (match providerId with
         | some id =>
             s!"lean-agent ai login: interactive OAuth login for '{id}' is available through LeanAgent.AI.OAuth provider modules (not a non-interactive CLI path yet)."
         | none =>
             "lean-agent ai login: specify a provider id, or use LeanAgent.AI.OAuth login APIs interactively.")
      pure 2
  | .unknown token =>
      IO.eprintln s!"Unknown ai command: {token}"
      IO.eprintln usage
      pure 2

end LeanAgent.AI.Cli
