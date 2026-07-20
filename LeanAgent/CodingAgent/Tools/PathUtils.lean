import Lean
import LeanAgent.CodingAgent.Utils.Paths

/-!
-- # Tool path utils (Pi `core/tools/path-utils.ts`)

Path resolution helpers for the read/edit tools, ported from Pi's
`core/tools/path-utils.ts`. All variants are offline-testable (no network);
only the host filesystem is touched, mirroring Pi's `accessSync`/`access`.

- `expandPath` — `normalizePath` with `normalizeUnicodeSpaces` + `stripAtPrefix`.
- `resolveToCwd` — `resolvePath` against `cwd` with the same options.
- `pathExists` / `fileExists` — `access(F_OK)` over `System.FilePath`.
- `resolveReadPath` — resolves a user-supplied path to a file that actually
  exists, trying macOS filename fallbacks when the literal path misses:
    1. ` AM.`/` PM.` (case-insensitive) → `<U+202F>AM.` (narrow no-break space;
       macOS screenshot names),
    2. NFD-decomposed variant (macOS stores filenames in NFD),
    3. curly-apostrophe variant — `U+0027` → `U+2019` (macOS screenshot names
       like "Capture d'écran"),
    4. combined NFD + curly quote (French macOS screenshots).
  The first existing variant wins; if none match, the resolved literal is
  returned (matching Pi's fallthrough).

`tryNFDVariant` is a pass-through in this port: full Unicode NFD decomposition
requires an in-tree decomposition table that is deferred. On macOS (APFS/HFS+)
the host filesystem normalizes Unicode itself, so the NFC user input resolves
to the NFD-named file directly; the curly-quote and AM/PM fallbacks are the
substantive portable logic and are fully implemented. `resolveReadPathAsync`
collapses into `resolveReadPath` since Lean IO is already effectful/async.
-/

namespace LeanAgent.CodingAgent.Tools.PathUtils

open System LeanAgent.CodingAgent.Utils.Paths

-- ============================================================================
-- # Constants
-- ============================================================================

/-- Pi `NARROW_NO_BREAK_SPACE` (U+202F), inserted before AM/PM in macOS names. -/
def narrowNoBreakSpace : Char := '\u202F'

/-- Pi right single quotation mark (U+2019), used by macOS in screenshot names. -/
def rightSingleQuote : Char := '\u2019'

-- ============================================================================
-- # macOS filename variant helpers
-- ============================================================================

/--
Replace ` AM.` / ` PM.` (case-insensitive) with `<U+202F>AM.` / `<U+202F>PM.`,
preserving the original letter case of the AM/PM token. Mirrors Pi's
`/ (AM|PM)\./gi` → `${NARROW_NO_BREAK_SPACE}$1.`.

A manual Char-list scanner stands in for the JS regex; the accumulator is
built reversed (head = most recent) and flipped at the end.
-/
def tryMacOSScreenshotPath (filePath : String) : String :=
  let rec go (rest : List Char) (acc : List Char) : List Char :=
    match rest with
    | ' ' :: a :: m :: '.' :: t =>
        let isAM := (a == 'A' || a == 'a') && (m == 'M' || m == 'm')
        let isPM := (a == 'P' || a == 'p') && (m == 'M' || m == 'm')
        if isAM || isPM then
          -- Match: replace the leading space with U+202F, keep AM/PM case + '.'.
          go t ('.' :: m :: a :: narrowNoBreakSpace :: acc)
        else
          -- No match: consume only the space, re-scan from `a`.
          go (a :: m :: '.' :: t) (' ' :: acc)
    | c :: t => go t (c :: acc)
    | [] => acc.reverse
  String.ofList (go filePath.toList [])

/--
NFD-decomposed variant of `filePath`.

Full Unicode NFD decomposition is deferred (no in-tree decomposition table).
On macOS the host filesystem (APFS/HFS+) normalizes Unicode itself, so the
NFC user input resolves to the NFD-named file directly; this pass-through is
a no-op on all platforms. Kept as a hook so callers wiring a decomposition
backend can drive it.
-/
def tryNFDVariant (filePath : String) : String := filePath

/-- Replace straight apostrophe `U+0027` with right single quote `U+2019`. -/
def tryCurlyQuoteVariant (filePath : String) : String :=
  filePath.map fun c => if c == '\'' then rightSingleQuote else c

-- ============================================================================
-- # Existence check
-- ============================================================================

/-- Pi `pathExists` (async `access(F_OK)`); sync `fileExists` collapses to it. -/
def pathExists (filePath : String) : IO Bool :=
  (FilePath.mk filePath).pathExists

-- ============================================================================
-- # expandPath / resolveToCwd
-- ============================================================================

/-- Pi `expandPath`: normalize Unicode spaces + strip leading `@`. -/
def expandPath (filePath : String) : IO String :=
  normalizePath filePath { normalizeUnicodeSpaces := true, stripAtPrefix := true }

/-- Pi `resolveToCwd`: resolve `filePath` against `cwd` (Unicode spaces + `@`). -/
def resolveToCwd (filePath : String) (cwd : String) : IO String :=
  resolvePath filePath cwd { normalizeUnicodeSpaces := true, stripAtPrefix := true }

-- ============================================================================
-- # resolveReadPath
-- ============================================================================

/--
Resolve `filePath` to a path that exists on disk, trying macOS filename
fallbacks (AM/PM narrow-space, NFD, curly quote, NFD+curly) when the literal
resolved path misses. Returns the resolved literal if no variant exists.

Pi `resolveReadPath` (sync) and `resolveReadPathAsync` collapse into one IO
function since Lean IO is already effectful.
-/
def resolveReadPath (filePath : String) (cwd : String) : IO String := do
  let resolved ← resolveToCwd filePath cwd
  if ← pathExists resolved then return resolved

  -- 1. macOS AM/PM narrow no-break space variant.
  let amPmVariant := tryMacOSScreenshotPath resolved
  if amPmVariant != resolved && (← pathExists amPmVariant) then
    return amPmVariant

  -- 2. NFD-decomposed variant (pass-through in this port; FS handles macOS).
  let nfdVariant := tryNFDVariant resolved
  if nfdVariant != resolved && (← pathExists nfdVariant) then
    return nfdVariant

  -- 3. Curly-apostrophe variant.
  let curlyVariant := tryCurlyQuoteVariant resolved
  if curlyVariant != resolved && (← pathExists curlyVariant) then
    return curlyVariant

  -- 4. Combined NFD + curly quote (French macOS screenshots).
  let nfdCurlyVariant := tryCurlyQuoteVariant nfdVariant
  if nfdCurlyVariant != resolved && (← pathExists nfdCurlyVariant) then
    return nfdCurlyVariant

  return resolved

/-- Pi `resolveReadPathAsync`; identical to `resolveReadPath` in Lean IO. -/
def resolveReadPathAsync (filePath : String) (cwd : String) : IO String :=
  resolveReadPath filePath cwd

end LeanAgent.CodingAgent.Tools.PathUtils