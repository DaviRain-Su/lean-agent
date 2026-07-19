import Lean
import LeanAgent.CodingAgent.Config
import LeanAgent.CodingAgent.Exec

/-!
# Tools manager (Pi `packages/coding-agent/src/utils/tools-manager.ts`)

Manages the `fd`/`rg` helper binaries that back the `find`/`grep` tools. This
module ports the pure/config surface: the `ToolConfig` registry with per-platform
asset-name computation, the `PI_OFFLINE` gate, `commandExists` (no-shell probe),
and `getToolPath` (local tools-dir lookup with system-PATH fallback).

The GitHub-release download and tarball/zip extraction paths (`getLatestVersion`,
`downloadFile`, `downloadTool`, `ensureTool`) are deferred: they require an HTTP
transport plus tar/zip extraction (Node streams + `tar`/`unzip`), tracked in the
ledger as an Exclusion List §7-adjacent subset.
-/

namespace LeanAgent.CodingAgent.Utils.ToolsManager

open LeanAgent.CodingAgent.Config

/-- Pi `ToolConfig` (subset; `getAssetName` is the pure per-platform computation). -/
structure ToolConfig where
  name : String
  /-- GitHub repo, e.g. `sharkdp/fd`. -/
  repo : String
  /-- Binary name inside the archive. -/
  binaryName : String
  /-- Alternative system command names to try before downloading. -/
  systemBinaryNames : Array String := #[]
  /-- Tag prefix (`v` for `v1.0.0`, empty for `1.0.0`). -/
  tagPrefix : String
  /-- Compute the release asset name for (version, platform, arch), or `none`. -/
  getAssetName : String → String → String → Option String
deriving Inhabited

/-- Pi platform id (`darwin`/`linux`/`win32`). -/
def platformId : String :=
  let t := System.Platform.target
  if t.startsWith "x86_64-apple-darwin" || t.startsWith "aarch64-apple-darwin" then "darwin"
  else if t.startsWith "x86_64-pc-windows" || t.startsWith "aarch64-pc-windows" then "win32"
  else "linux"

/-- Pi arch id (`arm64`/`x64`). -/
def archId : String :=
  let t := System.Platform.target
  if t.startsWith "aarch64-" then "arm64" else "x64"

/-- Compute the `fd` release asset name (Pi `TOOLS.fd.getAssetName`). -/
def fdAssetName (version plat arch : String) : Option String :=
  let archStr := if arch == "arm64" then "aarch64" else "x86_64"
  match plat with
  | "darwin" => some s!"fd-v{version}-{archStr}-apple-darwin.tar.gz"
  | "linux" => some s!"fd-v{version}-{archStr}-unknown-linux-gnu.tar.gz"
  | "win32" => some s!"fd-v{version}-{archStr}-pc-windows-msvc.zip"
  | _ => none

/-- Compute the `rg` release asset name (Pi `TOOLS.rg.getAssetName`). -/
def rgAssetName (version plat arch : String) : Option String :=
  match plat, arch with
  | "darwin", a => some s!"ripgrep-{version}-{if a == "arm64" then "aarch64" else "x86_64"}-apple-darwin.tar.gz"
  | "linux", "arm64" => some s!"ripgrep-{version}-aarch64-unknown-linux-gnu.tar.gz"
  | "linux", _ => some s!"ripgrep-{version}-x86_64-unknown-linux-musl.tar.gz"
  | "win32", a => some s!"ripgrep-{version}-{if a == "arm64" then "aarch64" else "x86_64"}-pc-windows-msvc.zip"
  | _, _ => none

/-- Pi `TOOLS` registry. -/
def tools : Array (String × ToolConfig) :=
  #[ ("fd", { name := "fd", repo := "sharkdp/fd", binaryName := "fd",
              systemBinaryNames := #["fd", "fdfind"], tagPrefix := "v",
              getAssetName := fdAssetName })
   , ("rg", { name := "ripgrep", repo := "BurntSushi/ripgrep", binaryName := "rg",
              systemBinaryNames := #["rg"], tagPrefix := "",
              getAssetName := rgAssetName })
   ]

/-- Look up a tool config by key. -/
def toolConfig? (tool : String) : Option ToolConfig :=
  (tools.find? (fun (k, _) => k == tool)) |>.map (·.2)

/-- Pi `isOfflineModeEnabled` (`PI_OFFLINE=1`/`true`/`yes`, case-insensitive). -/
def isOfflineModeEnabled : BaseIO Bool := do
  match ← IO.getEnv "PI_OFFLINE" with
  | none => pure false
  | some v =>
    let lower := v.toLower
    pure (v == "1" || lower == "true" || lower == "yes")

/--
Pi `commandExists`: probe whether `cmd` is on PATH by running `<cmd> --version`
(no shell). Returns false if the command is missing (ENOENT) or the spawn fails.
-/
def commandExists (cmd : String) : IO Bool := do
  let result ← LeanAgent.CodingAgent.Exec.execCommand cmd #["--version"]
    (System.FilePath.mk ".") { timeoutMs := some 3000 }
  -- exit code 127 / spawn-failure surfaces as non-zero; missing binary => code != 0.
  pure (result.code == 0)

/-- Pi `getToolPath`: local tools-dir binary if present, else a system PATH
command name if `commandExists`, else `none`. -/
def getToolPath (tool : String) : IO (Option String) := do
  match toolConfig? tool with
  | none => pure none
  | some config =>
    let binDir ← getBinDir
    let ext := if platformId == "win32" then ".exe" else ""
    let localPath := (binDir.toString) ++ "/" ++ config.binaryName ++ ext
    if (← (System.FilePath.mk localPath).pathExists) then pure (some localPath)
    else
      let names := if config.systemBinaryNames.isEmpty then #[config.binaryName] else config.systemBinaryNames
      let mut found : Option String := none
      for name in names do
        if found.isNone then
          if (← commandExists name) then found := some name
      pure found

end LeanAgent.CodingAgent.Utils.ToolsManager
