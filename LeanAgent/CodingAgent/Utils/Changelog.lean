import Lean

/-!
# Changelog utilities (Pi `packages/coding-agent/src/utils/changelog.ts`)

- `normalizeChangelogLinks`: rewrite inline markdown links in a changelog body
  to tag-pinned GitHub source URLs (resolve package-relative paths, canonicalize
  legacy `pi-mono` repo URLs, re-pin floating `main`/`master` refs).
- `parseChangelog`: scan a `CHANGELOG.md` for `## [x.y.z]` version headers and
  collect each section's body into a `ChangelogEntry`.
- `compareVersions` / `getNewEntries`: numeric (major, minor, patch) helpers.

Pi uses Node's `path.posix` and `encodeURI`; this module ships in-tree POSIX
path normalization and an `encodeURI`-compatible path encoder.
-/

namespace LeanAgent.CodingAgent.Utils.Changelog

/-- Pi `ChangelogEntry`. -/
structure ChangelogEntry where
  major : Nat
  minor : Nat
  patch : Nat
  content : String := ""
deriving Inhabited, BEq, Repr

/-- Render an entry's `major.minor.patch` version string. -/
def entryVersion (entry : ChangelogEntry) : String :=
  s!"{entry.major}.{entry.minor}.{entry.patch}"

/-- Pi `normalizeTag`: prefix with `v` unless already prefixed. -/
def normalizeTag (version : String) : String :=
  if version.startsWith "v" then version else s!"v{version}"

/-- Constants. -/
def gitHubRepo : String := "earendil-works/pi"
def changelogLinkBasePath : String := "packages/coding-agent"
def legacyRepoPrefixes : Array String :=
  #["https://github.com/badlogic/pi-mono", "https://github.com/earendil-works/pi-mono"]

-- ============================================================================
-- POSIX path normalization (Pi `path.posix.normalize` / `join` subset)
-- ============================================================================

/-- Split a path on `/`, dropping empty segments. -/
def splitPosix (p : String) : Array String :=
  ((p.splitOn "/").filter (fun s => !s.isEmpty)).toArray

/-- Join two POSIX paths and normalize (`.`/`..` resolution). -/
def posixJoinNormalize (base rel : String) : String :=
  let segs := (splitPosix base).toList ++ (splitPosix rel).toList
  let stack := segs.foldl (fun (acc : List String) s =>
    match s with
    | "." => acc
    | ".." => match acc with | _ :: rest => rest | [] => []
    | _ => s :: acc) []
  match stack.reverse with
  | [] => "."
  | parts => String.intercalate "/" parts

-- ============================================================================
-- encodeURI subset (path-safe)
-- ============================================================================

/-- True if `c` is safe to leave unencoded by `encodeURI`. -/
def isEncodeUriSafe (c : Char) : Bool :=
  c.isAlphanum || "-_.!~*'();/?:@&=+$,#".toList.contains c

/-- Hex digit char for 0-15. -/
def hexDigitChar (n : Nat) : Char :=
  if n < 10 then Char.ofNat (n + Char.toNat '0')
  else Char.ofNat (n - 10 + Char.toNat 'A')

/-- Two uppercase hex digits for a byte value 0-255. -/
def byteHex (n : Nat) : String :=
  String.singleton (hexDigitChar (n / 16)) ++ String.singleton (hexDigitChar (n % 16))

/-- Pi `encodeURI` subset: percent-encode bytes outside the safe set. -/
def encodeUri (s : String) : String := Id.run do
  let mut out := ""
  for c in s.toList do
    if isEncodeUriSafe c then out := out ++ String.singleton c
    else
      for b in (String.mk [c]).toUTF8 do
        out := out ++ "%" ++ byteHex b.toNat
  pure out

-- ============================================================================
-- Target normalization (Pi `normalizeChangelogLinkTarget`)
-- ============================================================================

/-- Pi `splitLocalTarget`: `(fragment, pathPart, query)`. Fragment keeps `#`. -/
def splitLocalTarget (target : String) : String × String × String :=
  let hashIdx := target.toList.toArray.findIdx? (fun c => c == '#')
  let (beforeHash, fragment) :=
    match hashIdx with
    | some i => (String.ofList (target.toList.take i), String.ofList (target.toList.drop i))
    | none => (target, "")
  let qIdx := beforeHash.toList.toArray.findIdx? (fun c => c == '?')
  match qIdx with
  | some i => (fragment, String.ofList (beforeHash.toList.take i), String.ofList (beforeHash.toList.drop i))
  | none => (fragment, beforeHash, "")

/-- Replace all `\` with `/`. -/
def normalizePathPart (value : String) : String := value.replace "\\" "/"

/--
Pi `resolveRepositoryPath`: resolve a local path against the changelog base,
POSIX-normalize, reject escapes outside the repo root (`.`/`..`).
-/
def resolveRepositoryPath? (targetPath : String) : Option String :=
  let normalizedTarget := normalizePathPart targetPath
  let hadTrailingSlash := normalizedTarget.endsWith "/"
  let joined :=
    if normalizedTarget.startsWith "/" then
      posixJoinNormalize "" (normalizedTarget.drop 1 |>.toString)
    else
      posixJoinNormalize changelogLinkBasePath normalizedTarget
  if joined == "." || joined.startsWith "../" || joined == ".." then none
  else
    -- Re-attach a trailing slash when the input had one (Pi `path.posix` preserves it).
    let joined := if hadTrailingSlash && !joined.endsWith "/" then joined ++ "/" else joined
    some joined

/-- Pi `isDirectoryTarget`: directory if ends with `/` or basename has no `.`. -/
def isDirectoryTarget (originalPath repositoryPath : String) : Bool :=
  if originalPath.endsWith "/" then true
  else
    let basename := match (repositoryPath.splitOn "/").reverse with
      | b :: _ => b
      | _ => repositoryPath
    !basename.contains '.'

/-- True iff `target` begins with a URL scheme `scheme:`. -/
def hasUrlScheme (target : String) : Bool := Id.run do
  let chars := target.toList.toArray
  if chars.isEmpty || !chars[0]!.isAlpha then pure false
  else
    let mut i := 1
    let mut foundColon := false
    while i < chars.size && !foundColon do
      let c := chars[i]!
      if c == ':' then foundColon := true
      else if c.isAlphanum || c == '+' || c == '-' || c == '.' then i := i + 1
      else break
    pure foundColon

/--
Pi `normalizeChangelogLinkTarget`: canonicalize a single link target to a
tag-pinned GitHub URL where appropriate.
-/
def normalizeChangelogLinkTarget (target tag : String) : String := Id.run do
  let mut canonical := target
  for legacy in legacyRepoPrefixes do
    if canonical.startsWith legacy then
      canonical := s!"https://github.com/{gitHubRepo}{canonical.drop legacy.length |>.toString}"
  let repoUrl := s!"https://github.com/{gitHubRepo}"
  -- Re-pin floating main/master refs on blob/tree routes.
  let pinPairs : Array (String × String) :=
    #[ ("blob", "main"), ("blob", "master"), ("tree", "main"), ("tree", "master") ]
  for (route, branch) in pinPairs do
    let pre := s!"{repoUrl}/{route}/{branch}/"
    if canonical.startsWith pre then
      canonical := s!"{repoUrl}/{route}/{tag}/{canonical.drop pre.length |>.toString}"
  if canonical.startsWith "#" || canonical.startsWith "//" || hasUrlScheme canonical then
    pure canonical
  else
    let (fragment, pathPart, query) := splitLocalTarget canonical
    if pathPart.isEmpty then pure canonical
    else
      match resolveRepositoryPath? pathPart with
      | none => pure canonical
      | some repoPath =>
        let route := if isDirectoryTarget pathPart repoPath then "tree" else "blob"
        pure s!"{repoUrl}/{route}/{tag}/{encodeUri repoPath}{query}{fragment}"

-- ============================================================================
-- Inline markdown link scan (Pi `INLINE_MARKDOWN_LINK_RE`)
-- ============================================================================

structure ScannedLink where
  start : Nat
  stop : Nat
  opening : String
  target : String
  suffix : String
deriving Inhabited

structure ScannedReply where
  link : ScannedLink
  nextFrom : Nat
deriving Inhabited

/-- True iff `i > 0` and the preceding char is a backslash. -/
def escapedAt (chars : Array Char) (i : Nat) : Bool :=
  i > 0 && chars[i - 1]! == '\\'

/-- First index `≥ start` whose char satisfies `p`, or `none`. -/
partial def findIdxFrom? (chars : Array Char) (p : Char → Bool) (start : Nat) : Option Nat :=
  if start ≥ chars.size then none
  else if p chars[start]! then some start
  else findIdxFrom? chars p (start + 1)

/--
Find the next inline markdown link at or after `fromIdx`. Matches Pi
`INLINE_MARKDOWN_LINK_RE`: `!?[label](target suffix?)`.
-/
def nextLinkImpl (source : String) (fromIdx : Nat) : Option ScannedReply := Id.run do
  let chars := source.toList.toArray
  let size := chars.size
  let mut i := fromIdx
  let mut found : Option ScannedReply := none
  while i < size && found.isNone do
    let c := chars[i]!
    let bang := c == '!' && i + 1 < size && chars[i + 1]! == '['
    let plain := c == '['
    if !(bang || plain) || escapedAt chars i then
      i := i + 1
    else
      let bangStart := i
      let bracketPos := if bang then i + 1 else i
      let labelStart := bracketPos + 1
      match findIdxFrom? chars (fun ch => ch == ']' || ch == '\n') labelStart with
      | none => i := i + 1
      | some labelEnd =>
        if labelEnd ≥ size || chars[labelEnd]! != ']' then i := i + 1
        else
          let parenPos := labelEnd + 1
          if parenPos ≥ size || chars[parenPos]! != '(' then i := i + 1
          else
            let targetStart := parenPos + 1
            let targetEnd := (findIdxFrom? chars
              (fun ch => ch == ' ' || ch == ')' || ch == '\t' || ch == '\n') targetStart).getD size
            if targetEnd == targetStart then i := i + 1
            else
              let mut s := targetEnd
              let mut suffixStart := targetEnd
              let mut suffixEnd := targetEnd
              if s < size && (chars[s]! == ' ' || chars[s]! == '\t') then
                suffixStart := s
                suffixEnd := (findIdxFrom? chars (fun ch => ch == ')') s).getD size
                s := suffixEnd
              if s < size && chars[s]! == ')' then
                let stop := s + 1
                let opening := String.ofList (chars.extract bangStart (parenPos + 1)).toList
                let target := String.ofList (chars.extract targetStart targetEnd).toList
                let suffix := String.ofList (chars.extract suffixStart suffixEnd).toList
                found := some
                  { link := { start := bangStart, stop := stop, opening := opening, target := target, suffix := suffix }
                    nextFrom := stop }
              else i := i + 1
  found

/--
Pi `normalizeChangelogLinks`: scan the markdown body and rewrite each inline
link's target. Non-link text is unchanged.
-/
partial def normalizeChangelogLinks (markdown : String) (version : String) : String :=
  go markdown version 0 ""
where
  go (src : String) (ver : String) (fromIdx : Nat) (acc : String) : String :=
    match nextLinkImpl src fromIdx with
    | none =>
      let chars := src.toList.toArray
      acc ++ String.ofList (chars.extract fromIdx chars.size).toList
    | some reply =>
      let link := reply.link
      let chars := src.toList.toArray
      let pre := String.ofList (chars.extract fromIdx link.start).toList
      let normalized := normalizeChangelogLinkTarget link.target ver
      let newAcc := acc ++ pre ++ link.opening ++ normalized ++ link.suffix ++ ")"
      go src ver reply.nextFrom newAcc

-- ============================================================================
-- parseChangelog (Pi `parseChangelog`)
-- ============================================================================

/-- Read 1+ digits starting at `start`; returns (value, nextIndex) or none. -/
def readDigits? (chars : Array Char) (start : Nat) : Option (Nat × Nat) := Id.run do
  let mut j := start
  while j < chars.size && chars[j]!.isDigit do j := j + 1
  if j == start then pure none
  else pure (some ((String.ofList (chars.extract start j).toList).toNat!, j))

/-- Try to parse a `## [x.y.z]` version header into (major, minor, patch). -/
def parseVersionHeader? (line : String) : Option (Nat × Nat × Nat) :=
  if !line.startsWith "## " then none
  else
    let rest := if line.drop 3 |>.toString |>.startsWith "[" then line.drop 4 |>.toString else line.drop 3 |>.toString
    let chars := rest.toList.toArray
    match readDigits? chars 0 with
    | none => none
    | some (major, afterMaj) =>
      if afterMaj ≥ chars.size || chars[afterMaj]! != '.' then none
      else match readDigits? chars (afterMaj + 1) with
      | none => none
      | some (minor, afterMin) =>
        if afterMin ≥ chars.size || chars[afterMin]! != '.' then none
        else match readDigits? chars (afterMin + 1) with
        | none => none
        | some (patch, _) => some (major, minor, patch)

/-- Pi `parseChangelog` over an in-memory body. -/
def parseChangelogContent (content : String) : Array ChangelogEntry := Id.run do
  let lines := content.splitOn "\n"
  let mut entries : Array ChangelogEntry := #[]
  let mut current : List String := []  -- reversed accumulator
  let mut currentVersion : Option (Nat × Nat × Nat) := none
  let mut pending : Option (Nat × Nat × Nat × String) := none
  for line in lines do
    if line.startsWith "## " then
      -- Flush pending.
      match pending with
      | some (maj, min, pat, body) =>
        if !body.isEmpty then
          entries := entries.push
            { major := maj, minor := min, patch := pat, content := body.trimAscii.toString }
      | none => pure ()
      match parseVersionHeader? line with
      | some v =>
        currentVersion := some v
        current := [line]
        pending := none
      | none =>
        currentVersion := none
        current := []
        pending := none
    else match currentVersion with
      | some _ => current := line :: current
      | none => pure ()
    -- Stage current accumulator into pending so flush picks it up at next header/EOF.
    match currentVersion with
    | some (maj, min, pat) =>
      pending := some (maj, min, pat, (String.intercalate "\n" current.reverse))
    | none => pending := none
  -- Flush final pending.
  match pending with
  | some (maj, min, pat, body) =>
    if !body.isEmpty then
      entries := entries.push
        { major := maj, minor := min, patch := pat, content := body.trimAscii.toString }
  | none => pure ()
  pure entries

/-- Read a CHANGELOG.md from disk and parse entries (empty if missing). -/
def parseChangelog (changelogPath : System.FilePath) : IO (Array ChangelogEntry) := do
  if !(← changelogPath.pathExists) then pure #[]
  else
    try
      let content ← IO.FS.readFile changelogPath
      pure (parseChangelogContent content)
    catch _ => pure #[]

-- ============================================================================
-- compareVersions / getNewEntries
-- ============================================================================

/-- Pi `compareVersions`: -1/0/1 over (major, minor, patch). -/
def compareVersions (v1 v2 : ChangelogEntry) : Int :=
  if v1.major != v2.major then Int.ofNat v1.major - Int.ofNat v2.major
  else if v1.minor != v2.minor then Int.ofNat v1.minor - Int.ofNat v2.minor
  else Int.ofNat v1.patch - Int.ofNat v2.patch

/-- Parse `major.minor.patch` into a `ChangelogEntry` (content empty). -/
def parseVersionEntry (version : String) : ChangelogEntry :=
  let parts := version.splitOn "."
  let nth (i : Nat) : Nat := match parts[i]? with | some s => s.toNat!.toUInt64.toNat | none => 0
  { major := nth 0, minor := nth 1, patch := nth 2, content := "" }

/-- Pi `getNewEntries`: entries strictly newer than `lastVersion`. -/
def getNewEntries (entries : Array ChangelogEntry) (lastVersion : String) : Array ChangelogEntry :=
  let last := parseVersionEntry lastVersion
  entries.filter (fun e => compareVersions e last > 0)

end LeanAgent.CodingAgent.Utils.Changelog
