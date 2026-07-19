import Lean
import LeanAgent.CodingAgent.Config

/-!
# Auth guidance messages (Pi `packages/coding-agent/src/core/auth-guidance.ts`)

User-facing strings shown when no provider/model/API key is configured.
Pure formatters over a docs path so offline tests can drive them without the
runtime package directory.
-/

namespace LeanAgent.CodingAgent.AuthGuidance

open LeanAgent.CodingAgent.Config

/-- Pi `getProviderLoginHelp`: multi-line /login help pointing at provider/model docs. -/
def getProviderLoginHelp (docsPath : System.FilePath) : String :=
  String.intercalate "\n"
    [ "Use /login to log into a provider via OAuth or API key. See:"
    , "  " ++ (docsPath / "providers.md").toString
    , "  " ++ (docsPath / "models.md").toString
    ]

/-- Pi `formatNoModelsAvailableMessage`. -/
def formatNoModelsAvailableMessage (docsPath : System.FilePath) : String :=
  "No models available. " ++ getProviderLoginHelp docsPath

/-- Pi `formatNoModelSelectedMessage`. -/
def formatNoModelSelectedMessage (docsPath : System.FilePath) : String :=
  "No model selected.\n\n" ++ getProviderLoginHelp docsPath ++ "\n\nThen use /model to select a model."

/-- Pi `formatNoApiKeyFoundMessage(provider)`: substitutes "the selected model"
when the provider is unknown. -/
def formatNoApiKeyFoundMessage (docsPath : System.FilePath) (provider : String) : String :=
  let providerDisplay := if provider == "unknown" then "the selected model" else provider
  "No API key found for " ++ providerDisplay ++ ".\n\n" ++ getProviderLoginHelp docsPath

end LeanAgent.CodingAgent.AuthGuidance
