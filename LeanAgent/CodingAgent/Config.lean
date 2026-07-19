import Lean

/-!
# Coding-agent config paths (Pi `packages/coding-agent/src/config.ts` subset)

Offline path helpers: agent dir, sessions dir, env overrides.
Install-method / Bun-binary detection is Exclusion (Node/Bun runtime).
-/

namespace LeanAgent.CodingAgent.Config

/-- Pi `APP_NAME` default. -/
def appName : String := "pi"

/-- Pi `CONFIG_DIR_NAME` default (`.pi`). -/
def configDirName : String := ".pi"

/-- Pi `ENV_AGENT_DIR` e.g. `PI_CODING_AGENT_DIR`. -/
def envAgentDir : String :=
  (appName.map Char.toUpper) ++ "_CODING_AGENT_DIR"

/-- Pi `ENV_SESSION_DIR`. -/
def envSessionDir : String :=
  (appName.map Char.toUpper) ++ "_CODING_AGENT_SESSION_DIR"

/-- Expand leading `~/` using `$HOME` when present. -/
def expandTildePath (path : String) : IO System.FilePath := do
  if path.startsWith "~/" then
    match ← IO.getEnv "HOME" with
    | some home => pure (System.FilePath.mk (home ++ (path.drop 1).toString))
    | none => pure (System.FilePath.mk path)
  else if path == "~" then
    match ← IO.getEnv "HOME" with
    | some home => pure (System.FilePath.mk home)
    | none => pure (System.FilePath.mk path)
  else
    pure (System.FilePath.mk path)

/--
Pi `getAgentDir`: `$PI_CODING_AGENT_DIR` or `~/.pi/agent`.
`overrideDir` allows offline tests without mutating process env.
-/
def getAgentDir (overrideDir : Option String := none) : IO System.FilePath := do
  match overrideDir with
  | some dir => expandTildePath dir
  | none =>
      match ← IO.getEnv envAgentDir with
      | some dir => expandTildePath dir
      | none =>
          match ← IO.getEnv "HOME" with
          | some home => pure (System.FilePath.mk home / configDirName / "agent")
          | none => pure (System.FilePath.mk configDirName / "agent")

/--
Pi `getSessionsDir`: `$PI_CODING_AGENT_SESSION_DIR` or `<agentDir>/sessions`.
`overrideDir` allows offline tests without mutating process env.
-/
def getSessionsDir (overrideDir : Option String := none) : IO System.FilePath := do
  match overrideDir with
  | some dir => expandTildePath dir
  | none =>
      match ← IO.getEnv envSessionDir with
      | some dir => expandTildePath dir
      | none => pure ((← getAgentDir) / "sessions")

/-- Pi `getDefaultSessionDir(cwd)`: sessions root (cwd encoding is repo-layer). -/
def getDefaultSessionDir (_cwd : System.FilePath) : IO System.FilePath :=
  getSessionsDir

/-- Pi getConfigDir (subset). -/
def getConfigDir (overrideDir : Option String := none) : IO System.FilePath := getAgentDir overrideDir

/-- Pi `getBinDir`: managed binaries directory (`<agentDir>/bin`). -/
def getBinDir (overrideDir : Option String := none) : IO System.FilePath := do
  pure ((← getAgentDir overrideDir) / "bin")

/-- Pi `getToolsDir`: legacy managed binaries directory (`<agentDir>/tools`). -/
def getToolsDir (overrideDir : Option String := none) : IO System.FilePath := do
  pure ((← getAgentDir overrideDir) / "tools")

/-- Pi `getPromptsDir`: prompt templates directory (`<agentDir>/prompts`). -/
def getPromptsDir (overrideDir : Option String := none) : IO System.FilePath := do
  pure ((← getAgentDir overrideDir) / "prompts")

/-- Pi `getDocsPath`: docs directory.
`overridePath` allows offline tests / message formatting without the runtime
package dir (Pi resolves `<packageDir>/docs`; Lean has no runtime package dir). -/
def getDocsPath (overridePath : Option String := none) : IO System.FilePath := do
  match overridePath with
  | some p => pure (System.FilePath.mk p)
  | none =>
      match ← IO.getEnv (appName.toUpper ++ "_DOCS_DIR") with
      | some p => pure (System.FilePath.mk p)
      | none => pure (System.FilePath.mk "docs")

end LeanAgent.CodingAgent.Config
