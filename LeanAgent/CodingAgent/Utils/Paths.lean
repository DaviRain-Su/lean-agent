import Lean
import LeanAgent.CodingAgent.Exec

/-!
# Path helpers (Pi `utils/paths.ts`)

Pure, offline-testable path utilities ported from Pi's `utils/paths.ts`:

- `isLocalPath` — true unless the value carries a non-local scheme
  (`npm:` / `git:` / `github:` / `http:` / `https:` / `ssh:`). `file:` URLs are
  local and are intentionally resolved by `resolvePath`.
- `normalizePath` — trim, `@`-strip, Unicode-space normalization, tilde
  expansion (`~` and `~/…`, plus `~\` on Windows), and `file://` URL decoding.
- `canonicalizePath` — `realpath` with raw-path fallback for missing entries.
- `resolvePath` — lexical `.`/`..` resolution against a base directory (Node
  `path.resolve` semantics, no symlink chase — symlinks are handled by
  `canonicalizePath`).
- `getCwdRelativePath` / `formatPathRelativeToCwdOrAbsolute` — path-to-cwd
  relativization with parent-traversal rejection (Pi `..${sep}` rule).
- `markPathIgnoredByCloudSync` — best-effort `xattr`/`setfattr` tagging so
  cloud-sync daemons (Dropbox, iCloud) skip the agent dirs.

`file://` decoding mirrors Node `fileURLToPath`: only `localhost`/empty hosts
are accepted and percent-escapes are UTF-8 decoded; malformed escapes or
invalid UTF-8 raise an IO error, matching Pi `paths.test.ts`.

The Node `child_process` spawn wrappers (`spawnProcess`/`spawnProcessSync`)
used by Pi live in `LeanAgent.CodingAgent.Exec`; `markPathIgnoredByCloudSync`
fires the platform launcher directly.
-/

namespace LeanAgent.CodingAgent.Utils.Paths

open System

-- ============================================================================
-- PathInputOptions
-- ============================================================================

/-- Pi `PathInputOptions`. -/
structure PathInputOptions where
  /-- Trim leading/trailing whitespace before normalization. -/
  trim : Bool := false
  /-- Expand leading `~` to a home directory. Defaults to true. -/
  expandTilde : Bool := true
  /-- Home directory used for `~` expansion. Defaults to `$HOME`. -/
  homeDir : Option String := none
  /-- Strip a leading `@` (used for CLI `@file` paths). -/
  stripAtPrefix : Bool := false
  /-- Normalize Unicode space variants to regular spaces. -/
  normalizeUnicodeSpaces : Bool := false
deriving Inhabited

-- ============================================================================
-- isLocalPath
-- ============================================================================

/-- True when the value is a local path/name (not a remote scheme). `file:` is local. -/
def isLocalPath (value : String) : Bool :=
  let trimmed := value.trimAscii.toString
  !(trimmed.startsWith "npm:" ||
    trimmed.startsWith "git:" ||
    trimmed.startsWith "github:" ||
    trimmed.startsWith "http:" ||
    trimmed.startsWith "https:" ||
    trimmed.startsWith "ssh:")

-- ============================================================================
-- Unicode-space + percent-decode helpers
-- ============================================================================

/-- Pi `UNICODE_SPACES` set: U+00A0, U+2000–U+200A, U+202F, U+205F, U+3000. -/
def isUnicodeSpace (c : Char) : Bool :=
  c.toNat == 0x00A0 ||
  (c.toNat ≥ 0x2000 && c.toNat ≤ 0x200A) ||
  c.toNat == 0x202F ||
  c.toNat == 0x205F ||
  c.toNat == 0x3000

/-- Replace Unicode-space variants with regular spaces (Pi `UNICODE_SPACES`). -/
def normalizeUnicodeSpacesStr (s : String) : String :=
  s.map fun c => if isUnicodeSpace c then ' ' else c

/-- Hex digit value, or none. -/
private def hexVal? (c : Char) : Option Nat :=
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
Percent-decode over a Char list (code points). Multi-byte UTF-8 sequences are
emitted by appending each byte of the code point's UTF-8 encoding. Returns
`none` on a truncated `%` escape, mirroring Node's `URI Malformed` error.
-/
partial def percentDecodeChars (cs : List Char) (acc : ByteArray) : Option ByteArray :=
  match cs with
  | [] => some acc
  | '%' :: h1 :: h2 :: rest =>
      match hexVal? h1, hexVal? h2 with
      | some v1, some v2 =>
        let byte : UInt8 := (v1 * 16 + v2).toUInt8
        percentDecodeChars rest (acc.push byte)
      | _, _ => none
  | '%' :: _ => none  -- truncated escape
  | c :: rest =>
      let enc := (String.ofList [c]).toUTF8
      let rec pump (i : Nat) (acc : ByteArray) : ByteArray :=
        if enc.size ≤ i then acc
        else pump (i + 1) (acc.push (enc.get! i))
      percentDecodeChars rest (pump 0 acc)

/-- UTF-8 decode a `ByteArray`, failing on invalid bytes (Pi malformed-file-URL error). -/
def decodeUtf8OrThrow (label : String) (bytes : ByteArray) : IO String :=
  match String.fromUTF8? bytes with
  | some s => pure s
  | none => throw <| IO.userError s!"{label}: malformed UTF-8"

-- ============================================================================
-- file:// URL decoding (Node `fileURLToPath` subset)
-- ============================================================================

/--
Parse a `file://` URL into the host and the percent-encoded pathname.

`file://host/path` → `(some "host", "/path")`; `file:///path` → `(none, "/path")`.
Returns `none` for inputs that are not `file://` URLs.
-/
def splitFileUrl? (s : String) : Option (Option String × String) :=
  if !s.startsWith "file://" then none
  else
    let after := (s.drop 7).toString
    match after.find? (fun c => c == '/') with
    | some i =>
        let host := after.extract after.startPos i
        let pathname := after.extract i after.endPos
        let host? := if host.isEmpty then none else some host
        some (host?, pathname)
    | none =>
        some (some after, "")

/--
Decode a `file://` URL to a native path (Node `fileURLToPath` subset).

- Accepts empty host or `localhost`; rejects other hosts.
- Percent-decodes the pathname as UTF-8; malformed escapes / invalid UTF-8
  raise `IO.userError`, matching Pi `paths.test.ts` "throws for invalid file URLs".
-/
def fileUrlToPath (url : String) : IO String := do
  match splitFileUrl? url with
  | none => pure url
  | some (host?, pathname) =>
      match host? with
      | some h =>
          if h != "localhost" then
            throw <| IO.userError s!"file URL with non-local host: {h}"
      | none => pure ()
      let bytes ←
        match percentDecodeChars pathname.toList (ByteArray.mk #[]) with
        | some bs => pure bs
        | none => throw <| IO.userError "file URL: malformed percent-encoding"
      decodeUtf8OrThrow "file URL" bytes

-- ============================================================================
-- normalizePath
-- ============================================================================

/-- Pi `normalizePath`. -/
def normalizePath (input : String) (options : PathInputOptions := {}) : IO String := do
  let mut normalized := if options.trim then input.trimAscii.toString else input
  if options.normalizeUnicodeSpaces then
    normalized := normalizeUnicodeSpacesStr normalized
  if options.stripAtPrefix && normalized.startsWith "@" then
    normalized := (normalized.drop 1).toString
  if options.expandTilde then
    let home ←
      match options.homeDir with
      | some h => pure h
      | none =>
          match ← IO.getEnv "HOME" with
          | some h => pure h
          | none => pure ""
    if !home.isEmpty then
      if normalized == "~" then
        return home
      if normalized.startsWith "~/" then
        return home ++ (normalized.drop 1).toString
      if Platform.isWindows && normalized.startsWith "~\\" then
        return home ++ (normalized.drop 1).toString
  if normalized.startsWith "file://" then
    return ← fileUrlToPath normalized
  pure normalized

-- ============================================================================
-- canonicalizePath
-- ============================================================================

/-- Canonicalize if exists; else return path (Pi realpath fallback). -/
def canonicalizePath (path : String) : IO String := do
  let fp := FilePath.mk path
  if ← fp.pathExists then
    try
      pure (← IO.FS.realPath fp).toString
    catch _ =>
      pure path
  else
    pure path

-- ============================================================================
-- Lexical path resolution (Node `path.resolve` / `path.relative`)
-- ============================================================================

/-- Path separator as a `Char` (matches `System.FilePath.pathSeparator`). -/
def pathSep : Char := FilePath.pathSeparator

/-- Split a path into non-empty segments at the platform separator. -/
def splitSegments (p : String) : List String :=
  (p.split pathSep).toList |>.filter (fun sl => !sl.isEmpty) |>.map (·.toString)

/--
Lexically resolve `.` / `..` segments.

If `input` is absolute, the base is ignored and resolution starts at the root.
Otherwise the base segments are prepended. `.` segments are dropped; `..`
pops the last non-root segment. Returns an absolute path when the base or
input is absolute, otherwise a relative path. Matches Node `path.resolve`.
-/
def lexicalResolve (base : String) (input : String) : String :=
  let inputAbs := (FilePath.mk input).isAbsolute
  let baseSegs := splitSegments base
  let inputSegs := splitSegments input
  let startSegs := if inputAbs then inputSegs else baseSegs ++ inputSegs
  let rec fold (segs : List String) (acc : List String) : List String :=
    match segs with
  | [] => acc.reverse
  | "." :: rest => fold rest acc
  | ".." :: rest =>
      match acc with
      | [] => fold rest acc
      | _ :: more => fold rest more
  | s :: rest => fold rest (s :: acc)
  let resolved := fold startSegs []
  let joined := FilePath.pathSeparator.toString.intercalate resolved
  let isAbs := inputAbs || (FilePath.mk base).isAbsolute
  if isAbs then
    FilePath.pathSeparator.toString ++ joined
  else if joined.isEmpty then "."
  else joined

/--
Resolve `input` against `baseDir` (defaults to the current working directory).

Lexical only — symlinks are not chased; use `canonicalizePath` for that.
-/
def resolvePath (input : String) (baseDir : String := "") (options : PathInputOptions := {}) : IO String := do
  let normalizedInput ← normalizePath input options
  let normalizedBase ←
    if baseDir.isEmpty then IO.currentDir.map (·.toString)
    else normalizePath baseDir
  pure (lexicalResolve normalizedBase normalizedInput)

/--
Lexical relative path from `from` to `to` (Node `path.relative`).

Both inputs are assumed already-resolved. Returns `""` when equal.
-/
def relativePath (fromPath : String) (toPath : String) : String :=
  let fromSegs := splitSegments fromPath
  let toSegs := splitSegments toPath
  let rec commonPrefix (a b : List String) (n : Nat) : Nat :=
    match a, b with
    | x :: xs, y :: ys => if x == y then commonPrefix xs ys (n + 1) else n
    | _, _ => n
  let n := commonPrefix fromSegs toSegs 0
  let ups := fromSegs.length - n
  let downs := toSegs.drop n
  let upSegs := List.replicate ups ".."
  let allSegs := upSegs ++ downs
  match allSegs with
  | [] => ""
  | _ => "/".intercalate allSegs

-- ============================================================================
-- getCwdRelativePath / formatPathRelativeToCwdOrAbsolute
-- ============================================================================

/--
Return `filePath` relative to `cwd`, or `none` if it escapes the cwd tree
(parent traversal or absolute divergence). Pi `getCwdRelativePath`.

A leading `..config` (literal directory name starting with two dots but not
`..`) is preserved — the rejection rule is `relative == ".."` or
`relative.startsWith("<..><sep>")`, not a bare `..` prefix.
-/
def getCwdRelativePath (filePath : String) (cwd : String) : IO (Option String) := do
  let resolvedCwd ← resolvePath cwd
  let resolvedPath ← resolvePath filePath resolvedCwd
  let rel := relativePath resolvedCwd resolvedPath
  if rel == "" then pure (some ".")
  else if rel == ".." then pure none
  else if rel.startsWith s!"..{pathSep}" then pure none
  else if (FilePath.mk rel).isAbsolute then pure none
  else pure (some rel)

/--
Format `filePath` relative to `cwd` when inside it, else as an absolute path.
Forward-slash normalizes the output. Pi `formatPathRelativeToCwdOrAbsolute`.
-/
def formatPathRelativeToCwdOrAbsolute (filePath : String) (cwd : String) : IO String := do
  let abs ← resolvePath filePath cwd
  match ← getCwdRelativePath abs cwd with
  | some rel => pure (rel.map fun c => if c == pathSep then '/' else c)
  | none => pure (abs.map fun c => if c == pathSep then '/' else c)

-- ============================================================================
-- markPathIgnoredByCloudSync
-- ============================================================================

/--
Extended filesystem attributes used to hide a path from cloud-sync daemons.

- macOS (Dropbox, iCloud): `com.dropbox.ignored`, `com.apple.fileprovider.ignore#P`
- Linux (Dropbox): `user.com.dropbox.ignored`
- Windows / other: none (best-effort, no portable xattr story).
-/
def cloudSyncAttributes : List String :=
  if Platform.isWindows then []
  else if Platform.isOSX then ["com.dropbox.ignored", "com.apple.fileprovider.ignore#P"]
  else ["user.com.dropbox.ignored"]

/-- Command + attribute pairs to apply for the current platform. -/
def cloudSyncCommands (path : String) : List (String × Array String) :=
  if Platform.isWindows then []
  else if Platform.isOSX then
    cloudSyncAttributes.map fun attr => ("xattr", #["-w", attr, "1", path])
  else
    cloudSyncAttributes.map fun attr => ("setfattr", #["-n", attr, "-v", "1", path])

/--
Best-effort: tag `path` so cloud-sync daemons (Dropbox, iCloud) skip it.

Errors are swallowed — missing `xattr`/`setfattr` or a failing write must never
abort the agent. Mirrors Pi `markPathIgnoredByCloudSync` (fire-and-forget
`spawnProcessSync` with `stdio: ignore`).
-/
def markPathIgnoredByCloudSync (path : String) : IO Unit := do
  for (cmd, args) in cloudSyncCommands path do
    try
      let child ← IO.Process.spawn
        { cmd := cmd, args := args, stdin := .null, stdout := .null, stderr := .null }
      let _ ← child.wait
    catch _ =>
      pure ()  -- best-effort: ignore missing tool / failure

end LeanAgent.CodingAgent.Utils.Paths