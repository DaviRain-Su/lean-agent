import Lean

/-!
# Pi User-Agent header (Pi `packages/coding-agent/src/utils/pi-user-agent.ts`)

Formats the `User-Agent` string sent to pi.dev and provider endpoints. The
runtime segment reports the Lean toolchain instead of node/bun (the Pi JS
runtime markers are an Exclusion List §7 detail); the platform/arch segments
are read from `System.Platform`.
-/

namespace LeanAgent.CodingAgent.Utils.PiUserAgent

/-- Runtime segment (Pi reports `node/<v>` or `bun/<v>`). The Lean port reports
the Lean toolchain version, read from `lean_toolchain` at build time. -/
def runtimeSegment : String :=
  s!"lean/{Lean.versionString}"

/-- Platform segment matching Node's `process.platform` values
(`darwin`/`linux`/`win32`). -/
def platformSegment : String :=
  let t := System.Platform.target
  if t.startsWith "x86_64-apple-darwin" || t.startsWith "aarch64-apple-darwin" then "darwin"
  else if t.startsWith "x86_64-unknown-linux" || t.startsWith "aarch64-unknown-linux" then "linux"
  else if t.startsWith "x86_64-pc-windows" || t.startsWith "aarch64-pc-windows" then "win32"
  else "unknown"

/-- Arch segment matching Node's `process.arch` values (`arm64`/`x64`/etc.). -/
def archSegment : String :=
  let t := System.Platform.target
  if t.startsWith "aarch64-" then "arm64"
  else if t.startsWith "x86_64-" then "x64"
  else "unknown"

/--
Pi `getPiUserAgent`: `pi/<version> (<platform>; <runtime>; <arch>)`.
Injectable `platform`/`runtime`/`arch` defaults to the host values for offline
tests.
-/
def getPiUserAgent
    (version : String)
    (platform : String := platformSegment)
    (runtime : String := runtimeSegment)
    (arch : String := archSegment) : String :=
  s!"pi/{version} ({platform}; {runtime}; {arch})"

end LeanAgent.CodingAgent.Utils.PiUserAgent
