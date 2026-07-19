import Lean
import LeanAgent.CodingAgent.Telemetry

/-!
# Version check (Pi `packages/coding-agent/src/utils/version-check.ts`)

Semver-based package-version comparison plus the version-check network entry
points. The pure comparison logic (`comparePackageVersions`,
`isNewerPackageVersion`, `parseSemver?`, `compareSemver`) is fully ported and
offline-tested. The network entry points (`getLatestPiRelease`,
`getLatestPiVersion`, `checkForNewPiVersion`) honor the `PI_SKIP_VERSION_CHECK`
and `PI_OFFLINE` env gates and otherwise require an HTTP transport, which is
pluggable via `LatestVersionTransport` so offline tests can substitute a mock.

Pi uses the npm `semver` package's `valid` + `compare`; this module ships a
self-contained semver parser/comparator covering the released-version and
prerelease cases exercised by `version-check.test.ts`.
-/

namespace LeanAgent.CodingAgent.Utils.VersionCheck

-- ============================================================================
-- Semver parsing + comparison (subset of npm `semver`)
-- ============================================================================

/-- A parsed semver: major.minor.patch + optional prerelease identifiers. -/
structure Semver where
  major : Nat
  minor : Nat
  patch : Nat
  /-- Prerelease identifiers (empty for a release). Numeric identifiers are
  stored as their string form; comparison distinguishes numeric vs alphanumeric. -/
  prerelease : Array String := #[]
deriving Inhabited, BEq, Repr

/-- True iff `s` is all ASCII digits. -/
def isAllDigits (s : String) : Bool :=
  s.toList.all fun c => c.isDigit && !s.isEmpty

/-- True iff `c` is an alphanumeric prerelease identifier char [0-9A-Za-z-]. -/
def isPreIdentChar (c : Char) : Bool :=
  c.isAlphanum || c == '-'

/--
Parse a semver string (Pi `semver.valid`, strict subset). Accepts an optional
leading `v`, `MAJOR.MINOR.PATCH`, optional `-prerelease` (dot-separated
`[0-9A-Za-z-]+` identifiers), optional `+build` (ignored). Returns `none` if
the core `MAJOR.MINOR.PATCH` is missing/malformed or a prerelease identifier is
empty/invalid.
-/
def parseSemver? (input : String) : Option Semver :=
  let s0 := input.trimAscii.toString
  let s1 := if s0.startsWith "v" || s0.startsWith "V" then s0.drop 1 |>.toString else s0
  -- Split off build metadata (+).
  let plusIdx := s1.toList.toArray.findIdx? (fun c => c == '+')
  let s2 := match plusIdx with
    | some i => String.ofList (s1.toList.take i)
    | none => s1
  -- Split off prerelease (-).
  let dashIdx := s2.toList.toArray.findIdx? (fun c => c == '-')
  let (core, prerelease?) := match dashIdx with
    | some i => (String.ofList (s2.toList.take i), some (String.ofList (s2.toList.drop (i + 1))))
    | none => (s2, none)
  let coreParts := core.splitOn "."
  if coreParts.length != 3 then none
  else
    match coreParts with
    | [majS, minS, patS] =>
      if !(isAllDigits majS && isAllDigits minS && isAllDigits patS) then none
      else
        let major := majS.toNat!
        let minor := minS.toNat!
        let patch := patS.toNat!
        match prerelease? with
        | none => some ⟨major, minor, patch, #[]⟩
        | some preStr =>
          if preStr.isEmpty then none
          else
            let idents := preStr.splitOn "."
            if idents.any (fun id => id.isEmpty || !(id.toList.all isPreIdentChar)) then none
            else some ⟨major, minor, patch, idents.toArray⟩
    | _ => none

/-- Sign of a `Nat` comparison (-1/0/1). -/
def cmpNat (a b : Nat) : Int :=
  if a < b then -1 else if a > b then 1 else 0

/-- Compare two prerelease identifier strings per semver rules:
numeric < alphanumeric; numeric compared by value; alphanumeric compared lexically. -/
def cmpPreIdent (a b : String) : Int :=
  let aNum := isAllDigits a
  let bNum := isAllDigits b
  if aNum && bNum then
    -- numeric identifiers compared numerically (strip leading zeros for value).
    let av := a.toNat!.toUInt64.toNat
    let bv := b.toNat!.toUInt64.toNat
    cmpNat av bv
  else if aNum && !bNum then -1   -- numeric has lower precedence than alphanumeric
  else if !aNum && bNum then 1
  else
    -- both alphanumeric: lexical ASCII comparison
    if a < b then -1 else if a > b then 1 else 0

/--
Compare two prerelease identifier arrays per semver rules. A version with
prerelease has lower precedence than the same version without (caller handles
that). Among two prereleases: compare identifiers pairwise; if all equal, the
one with fewer identifiers is lower.
-/
def cmpPrerelease (a b : Array String) : Int := Id.run do
  if a.isEmpty && b.isEmpty then pure 0
  else
    let n := min a.size b.size
    let mut i := 0
    let mut result : Int := 0
    while i < n && result == 0 do
      result := cmpPreIdent a[i]! b[i]!
      i := i + 1
    if result != 0 then pure result
    else pure (cmpNat a.size b.size)

/--
Compare two parsed semvers per semver precedence (-1/0/1). Major/minor/patch
numeric; then prerelease (release > prerelease; prerelease compared by rules).
-/
def compareSemver (a b : Semver) : Int :=
  let r := cmpNat a.major b.major
  if r != 0 then r
  else
    let r := cmpNat a.minor b.minor
    if r != 0 then r
    else
      let r := cmpNat a.patch b.patch
      if r != 0 then r
      else
        -- Same core. Release (no prerelease) > prerelease.
        if a.prerelease.isEmpty && b.prerelease.isEmpty then 0
        else if a.prerelease.isEmpty then 1   -- a is release, b is prerelease
        else if b.prerelease.isEmpty then -1  -- a is prerelease, b is release
        else cmpPrerelease a.prerelease b.prerelease

-- ============================================================================
-- Pi `comparePackageVersions` / `isNewerPackageVersion`
-- ============================================================================

/--
Pi `comparePackageVersions`: parse both versions and compare. Returns `none`
if either is not a valid semver.
-/
def comparePackageVersions (leftVersion rightVersion : String) : Option Int :=
  match parseSemver? leftVersion, parseSemver? rightVersion with
  | some l, some r => some (compareSemver l r)
  | _, _ => none

/--
Pi `isNewerPackageVersion`: true if `candidateVersion` > `currentVersion` by
semver. Falls back to a trimmed string inequality when either version is not
parseable as semver.
-/
def isNewerPackageVersion (candidateVersion currentVersion : String) : Bool :=
  match comparePackageVersions candidateVersion currentVersion with
  | some r => r > 0
  | none => candidateVersion.trimAscii.toString != currentVersion.trimAscii.toString

-- ============================================================================
-- Network entry points (env-gated; transport-pluggable)
-- ============================================================================

/-- Pi `LatestPiRelease`. -/
structure LatestPiRelease where
  version : String
  packageName : Option String := none
  note : Option String := none
deriving Inhabited, Repr

/--
Pluggable transport for the latest-version lookup. Returns the raw JSON field
map (`version`/`packageName`/`note`) or `none` on failure. Offline tests
substitute a mock; the runtime wires this to `LeanAgent.Http`.
-/
structure LatestVersionTransport where
  fetch : String → IO (Option Lean.Json)

/-- Pi `LATEST_VERSION_URL`. -/
def latestVersionUrl : String := "https://pi.dev/api/latest-version"

/-- Pi `DEFAULT_VERSION_CHECK_TIMEOUT_MS`. -/
def defaultVersionCheckTimeoutMs : Nat := 10000

/-- True iff version checks are disabled via env (`PI_SKIP_VERSION_CHECK` or `PI_OFFLINE`). -/
def isVersionCheckDisabled : BaseIO Bool := do
  let skip? ← IO.getEnv "PI_SKIP_VERSION_CHECK"
  if LeanAgent.CodingAgent.Telemetry.isTruthyEnvFlag skip? then pure true
  else
    let off? ← IO.getEnv "PI_OFFLINE"
    pure (LeanAgent.CodingAgent.Telemetry.isTruthyEnvFlag off?)

/-- Unset a single environment variable (libuv FFI; Lean 4.31 has no `IO.unsetEnv`). -/
@[extern "lean_uv_os_unsetenv"]
opaque unsetEnvVar : @&String → IO Unit

/-- Test helper: clear the version-check env gates for hermetic offline tests. -/
def unsetVersionCheckEnv : IO Unit := do
  unsetEnvVar "PI_SKIP_VERSION_CHECK"
  unsetEnvVar "PI_OFFLINE"

/--
Pi `getLatestPiRelease`: fetch the latest release descriptor from the version
check API. Returns `none` when disabled via env or when the response is missing
a non-empty `version`. `packageName`/`note` are trimmed when present.
-/
def getLatestPiRelease
    (currentVersion : String) (transport : LatestVersionTransport)
    (timeoutMs : Option Nat := none) : IO (Option LatestPiRelease) := do
  if ← isVersionCheckDisabled then pure none
  else
    let json? ← transport.fetch latestVersionUrl
    match json? with
    | none => pure none
    | some json =>
      match json.getObjVal? "version" with
      | .ok (.str v) =>
        let version := v.trimAscii.toString
        if version.isEmpty then pure none
        else
          let packageName :=
            match json.getObjVal? "packageName" with
            | .ok (.str p) =>
              let t := p.trimAscii.toString
              if t.isEmpty then none else some t
            | _ => none
          let note :=
            match json.getObjVal? "note" with
            | .ok (.str n) =>
              let t := n.trimAscii.toString
              if t.isEmpty then none else some t
            | _ => none
          pure (some { version := version, packageName := packageName, note := note })
      | _ => pure none

/-- Pi `getLatestPiVersion`: the version string from the latest-release lookup. -/
def getLatestPiVersion
    (currentVersion : String) (transport : LatestVersionTransport)
    (timeoutMs : Option Nat := none) : IO (Option String) := do
  match ← getLatestPiRelease currentVersion transport timeoutMs with
  | some r => pure (some r.version)
  | none => pure none

/--
Pi `checkForNewPiVersion`: return the latest release only if it is newer than
`currentVersion`. Swallows fetch errors (returns `none`).
-/
def checkForNewPiVersion
    (currentVersion : String) (transport : LatestVersionTransport) :
    IO (Option LatestPiRelease) := do
  try
    match ← getLatestPiRelease currentVersion transport with
    | some r => if isNewerPackageVersion r.version currentVersion then pure (some r) else pure none
    | none => pure none
  catch _ => pure none

end LeanAgent.CodingAgent.Utils.VersionCheck
