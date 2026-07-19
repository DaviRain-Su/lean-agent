import Lean

/-!
# Git URL parsing (Pi `packages/coding-agent/src/utils/git.ts`)

Parses git source URLs into a structured `GitSource` (repo / host / path / ref /
pinned). Supports:

- Protocol URLs accepted without a `git:` prefix: `https://`, `http://`,
  `ssh://`, `git://`.
- Shorthand forms accepted only with a `git:` prefix: `git@host:path` (scp-like)
  and `host/path`.

Rejects unsafe install paths (parent traversal, absolute paths, NUL bytes,
backslashes, malformed percent-encoding).

Pi's `hosted-git-info` npm dependency is intentionally not ported; the generic
parser (`parseGenericGitUrl`) produces the same `host`/`path`/`repo` for the
`git-ssh-url.test.ts` matrix. Hosted-canonicalization shortcuts are deferred.
-/

namespace LeanAgent.CodingAgent.Utils.Git

/-- Pi `GitSource`. -/
structure GitSource where
  repo : String
  host : String
  path : String
  ref : Option String := none
  pinned : Bool := false
deriving Inhabited, BEq, Repr

-- ============================================================================
-- Char-array helpers (avoid Lean 4.31 String.Slice return-type churn)
-- ============================================================================

/-- Materialize a string as an `Array Char`. -/
def toArr (s : String) : Array Char := s.toList.toArray

/-- Reconstruct a string from a char sub-range `[start, stop)`. -/
def rangeStr (s : String) (start stop : Nat) : String :=
  String.ofList (toArr s |>.extract start stop |>.toList)

/-- First index of `c` in `s`, or `none`. -/
def idxOf (s : String) (c : Char) : Option Nat :=
  (toArr s).findIdx? (fun x => x == c)

-- ============================================================================
-- Minimal URL parsing
-- ============================================================================

structure ParsedUrl where
  scheme : String
  host : String
  pathname : String
  fragment : Option String := none
deriving Inhabited

def isSchemeChar (c : Char) : Bool :=
  c.isAlphanum || c == '+' || c == '-' || c == '.'

/-- Parse `scheme://rest` returning `(scheme, rest)`, or `none`. -/
def splitScheme (s : String) : Option (String × String) := Id.run do
  let chars := toArr s
  if chars.size < 4 || !(0 < chars.size && chars[0]!.isAlpha) then none
  else
    let mut i := 1
    while i < chars.size && isSchemeChar chars[i]! do i := i + 1
    if i + 2 < chars.size && chars[i]! == ':' && chars[i+1]! == '/' && chars[i+2]! == '/' then
      some (rangeStr s 0 i, rangeStr s (i+3) chars.size)
    else none

/-- Split off a `#fragment` suffix. -/
def splitFragment (s : String) : String × Option String :=
  match idxOf s '#' with
  | some idx => (rangeStr s 0 idx,
                 if rangeStr s (idx+1) s.length |>.isEmpty then none
                 else some (rangeStr s (idx+1) s.length))
  | none => (s, none)

/--
Parse `scheme://[userinfo@]host[:port][/path]` into a `ParsedUrl`. Pathname has
leading slashes stripped. `?query` is dropped. Returns `none` on malformed input.
-/
def parseUrl (url : String) : Option ParsedUrl := do
  let (scheme, rest0) ← splitScheme url
  let rest := match idxOf rest0 '?' with
    | some q => rangeStr rest0 0 q
    | none => rest0
  let (rest, fragment) := splitFragment rest
  let chars := toArr rest
  let slashIdx := chars.findIdx? (fun c => c == '/')
  let (authority, pathWithSlashes) :=
    match slashIdx with
    | some i => (rangeStr rest 0 i, rangeStr rest i chars.size)
    | none => (rest, "")
  -- Strip userinfo.
  let hostport := match idxOf authority '@' with
    | some atIdx => rangeStr authority (atIdx + 1) authority.length
    | none => authority
  -- Strip port (handle IPv6 [...] literal).
  let host :=
    if hostport.startsWith "[" then
      match idxOf hostport ']' with
      | some b => rangeStr hostport 0 (b + 1)
      | none => hostport
    else
      match idxOf hostport ':' with
      | some cIdx => rangeStr hostport 0 cIdx
      | none => hostport
  -- Strip leading slashes.
  let pathChars := toArr pathWithSlashes
  let k := pathChars.findIdx? (fun c => c != '/') |>.getD 0
  let path := String.ofList (pathChars.extract k pathChars.size |>.toList)
  some { scheme := scheme, host := host, pathname := path, fragment := fragment }

-- ============================================================================
-- Percent-decoding (Pi `decodeURIComponent`)
-- ============================================================================

def hexDigit? (c : Char) : Option Nat :=
  match c with
  | '0' => some 0 | '1' => some 1 | '2' => some 2 | '3' => some 3
  | '4' => some 4 | '5' => some 5 | '6' => some 6 | '7' => some 7
  | '8' => some 8 | '9' => some 9
  | 'a' => some 10 | 'b' => some 11 | 'c' => some 12 | 'd' => some 13
  | 'e' => some 14 | 'f' => some 15
  | 'A' => some 10 | 'B' => some 11 | 'C' => some 12 | 'D' => some 13
  | 'E' => some 14 | 'F' => some 15
  | _ => none

/--
Percent-decode a string (Pi `decodeURIComponent`). Returns `none` on malformed
input (a `%` not followed by two hex digits). Decoded bytes reassemble as UTF-8.
-/
def decodeURIComponent? (s : String) : Option String := Id.run do
  let chars := toArr s
  let mut outBytes : Array UInt8 := #[]
  let mut i := 0
  let mut ok := true
  while i < chars.size do
    if !ok then break
    let c := chars[i]!
    if c == '%' then
      if i + 2 < chars.size then
        match hexDigit? chars[i+1]!, hexDigit? chars[i+2]! with
        | some hi, some lo =>
          outBytes := outBytes.push ((hi * 16 + lo).toUInt8)
          i := i + 3
        | _, _ => ok := false
      else ok := false
    else if c.toNat ≤ 0x7F then
      outBytes := outBytes.push c.toNat.toUInt8
      i := i + 1
    else
      for b in (String.mk [c]).toUTF8 do outBytes := outBytes.push b
      i := i + 1
  if !ok then none else String.fromUTF8? (ByteArray.mk outBytes)

-- ============================================================================
-- ref splitting (Pi `splitRef`)
-- ============================================================================

structure SplitRef where
  repo : String
  ref : Option String := none
deriving Inhabited

/-- Match `^git@([^:]+):(.+)$` returning (host, rest). -/
def matchScpLike (s : String) : Option (String × String) :=
  if s.startsWith "git@" then
    let rest := rangeStr s 4 s.length
    match idxOf rest ':' with
    | some cIdx =>
        let host := rangeStr rest 0 cIdx
        let pathPart := rangeStr rest (cIdx + 1) rest.length
        if host.isEmpty || pathPart.isEmpty then none else some (host, pathPart)
    | none => none
  else none

/-- Strip an `@ref` from a path: `(repoPath, ref?)`. If ref is empty, returns
`(original, none)`. -/
def splitAtRef (pathWithMaybeRef : String) : String × Option String :=
  match idxOf pathWithMaybeRef '@' with
  | some idx =>
      let repoPath := rangeStr pathWithMaybeRef 0 idx
      let ref := rangeStr pathWithMaybeRef (idx + 1) pathWithMaybeRef.length
      if repoPath.isEmpty || ref.isEmpty then (pathWithMaybeRef, none)
      else (repoPath, some ref)
  | none => (pathWithMaybeRef, none)

/-- Pi `splitRef`: split a URL into `(repo, ref?)`. -/
def splitRef (url : String) : SplitRef :=
  match matchScpLike url with
  | some (host, pathWithMaybeRef) =>
      let (repoPath, ref) := splitAtRef pathWithMaybeRef
      match ref with
      | some r => { repo := s!"git@{host}:{repoPath}", ref := some r }
      | none => { repo := url }
  | none =>
    if url.contains "://" then
      match parseUrl url with
      | some parsed =>
          let (repoPath, ref) := splitAtRef parsed.pathname
          match ref with
          | some r => { repo := s!"{parsed.scheme}://{parsed.host}/{repoPath}", ref := some r }
          | none => { repo := url }
      | none => { repo := url }
    else
      match idxOf url '/' with
      | some slashIdx =>
          let host := rangeStr url 0 slashIdx
          let pathWithMaybeRef := rangeStr url (slashIdx + 1) url.length
          let (repoPath, ref) := splitAtRef pathWithMaybeRef
          match ref with
          | some r => { repo := s!"{host}/{repoPath}", ref := some r }
          | none => { repo := url }
      | none => { repo := url }

-- ============================================================================
-- safety checks (Pi `hasUnsafeGitInstallPart`, `buildGitSource`)
-- ============================================================================

/-- Strip a trailing `.git` suffix. -/
def stripDotGit (s : String) : String :=
  if s.endsWith ".git" then rangeStr s 0 (s.length - 4) else s

/-- Strip leading '/' characters. -/
def stripLeadingSlashes (s : String) : String :=
  let chars := toArr s
  let k := chars.findIdx? (fun c => c != '/') |>.getD 0
  String.ofList (chars.extract k chars.size |>.toList)

/-- Pi `hasUnsafeGitInstallPart`: reject NUL, backslash, leading `/`, parent
traversal (`..` segment). When `allowSlash = false` (host parts), any `/'
rejects. Malformed percent-encoding also rejects. -/
def hasUnsafeGitInstallPart (value : String) (allowSlash : Bool) : Bool :=
  match decodeURIComponent? value with
  | none => true
  | some decoded =>
      let nul := Char.ofNat 0
      [value, decoded].any fun candidate =>
        candidate.contains nul
          || candidate.contains '\\'
          || candidate.startsWith "/"
          || (!allowSlash && candidate.contains '/')
          || (candidate.splitOn "/").contains ".."

/-- Pi `buildGitSource`: validate and assemble a `GitSource`. -/
def buildGitSource (repo host path : String) (ref : Option String) : Option GitSource :=
  if path.startsWith "/" then none
  else
    let normalizedPath := stripLeadingSlashes (stripDotGit path)
    if host.isEmpty || normalizedPath.isEmpty then none
    else if (normalizedPath.splitOn "/").length < 2 then none
    else if hasUnsafeGitInstallPart host false || hasUnsafeGitInstallPart normalizedPath true then none
    else some
      { repo := repo
        host := host
        path := normalizedPath
        ref := ref
        pinned := ref.isSome }

-- ============================================================================
-- parseGenericGitUrl + parseGitUrl
-- ============================================================================

/-- Pi `parseGenericGitUrl`: dispatch scp-like / protocol / shorthand. -/
def parseGenericGitUrl (url : String) : Option GitSource :=
  let split : SplitRef := splitRef url
  let repoWithoutRef := split.repo
  let ref := split.ref
  match matchScpLike repoWithoutRef with
  | some (host, path) => buildGitSource repoWithoutRef host path ref
  | none =>
    if repoWithoutRef.startsWith "https://" || repoWithoutRef.startsWith "http://"
       || repoWithoutRef.startsWith "ssh://" || repoWithoutRef.startsWith "git://" then
      match parseUrl repoWithoutRef with
      | some parsed => buildGitSource repoWithoutRef parsed.host parsed.pathname ref
      | none => none
    else
      match idxOf repoWithoutRef '/' with
      | some slashIdx =>
          let host := rangeStr repoWithoutRef 0 slashIdx
          let path := rangeStr repoWithoutRef (slashIdx + 1) repoWithoutRef.length
          if !(host.contains '.' || host == "localhost") then none
          else buildGitSource (s!"https://{repoWithoutRef}") host path ref
      | none => none

/-- True iff `url` starts with one of the accepted protocol schemes. -/
def hasAcceptedProtocol (url : String) : Bool :=
  let lower := url.toLower
  lower.startsWith "https://" || lower.startsWith "http://"
    || lower.startsWith "ssh://" || lower.startsWith "git://"

/--
Pi `parseGitUrl`: parse a git source into a `GitSource`.

- With a `git:` prefix, accept all historical shorthand forms.
- Without a `git:` prefix, only accept explicit `https?://`, `ssh://`, `git://` URLs.

The Pi `hosted-git-info` shortcut is not ported; we rely on the generic parser.
-/
def parseGitUrl (source : String) : Option GitSource :=
  let trimmed := source.trimAscii.toString
  let hasGitPrefix := trimmed.startsWith "git:"
  let url := if hasGitPrefix then rangeStr trimmed 4 trimmed.length else trimmed
  let url := url.trimAscii.toString
  if !hasGitPrefix && !hasAcceptedProtocol url then none
  else parseGenericGitUrl url

end LeanAgent.CodingAgent.Utils.Git
