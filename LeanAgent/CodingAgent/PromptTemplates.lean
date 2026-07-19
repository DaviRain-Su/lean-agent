import Lean
import LeanAgent.CodingAgent.Utils.Frontmatter
import LeanAgent.CodingAgent.Utils.Paths
import LeanAgent.CodingAgent.Config

/-!
# Prompt templates (Pi `packages/coding-agent/src/core/prompt-templates.ts`)

Loads `*.md` prompt templates from global/project/explicit directories and
expands `/name args...` invocations with bash-style argument substitution:

- `$1`, `$2`, …                positional (out-of-range → empty)
- `$@`, `$ARGUMENTS`            all args joined by spaces
- `${N:-default}`               positional with default when missing/empty
- `${@:N}`                      args from Nth onwards
- `${@:N:L}`                    L args starting from Nth

Substitution is single-pass: values are inserted literally (no recursion).
-/

namespace LeanAgent.CodingAgent.PromptTemplates

open LeanAgent.CodingAgent.Utils.Frontmatter
open LeanAgent.CodingAgent.Utils.Paths
open LeanAgent.CodingAgent.Config

/-- Pi `SourceScope`. -/
inductive SourceScope where
  | user | project | temporary
deriving Inhabited, DecidableEq, Repr

def SourceScope.toString : SourceScope → String
  | .user => "user"
  | .project => "project"
  | .temporary => "temporary"

/-- Pi `SourceOrigin`. -/
inductive SourceOrigin where
  | package | topLevel
deriving Inhabited, DecidableEq, Repr

def SourceOrigin.toString : SourceOrigin → String
  | .package => "package"
  | .topLevel => "top-level"

/-- Pi `SourceInfo` (subset of `core/source-info.ts`). -/
structure SourceInfo where
  path : String
  source : String := "local"
  scope : SourceScope := .temporary
  origin : SourceOrigin := .topLevel
  baseDir : Option String := none
deriving Inhabited, Repr

/-- Pi `PromptTemplate`. -/
structure PromptTemplate where
  name : String
  description : String := ""
  argumentHint : Option String := none
  content : String
  sourceInfo : SourceInfo := default
  filePath : String
deriving Inhabited, Repr

/-- Index a list by `Nat` (structurally recursive; total). -/
def nthChar? : List Char → Nat → Option Char
  | [], _ => none
  | c :: _, 0 => some c
  | _ :: rest, n + 1 => nthChar? rest n

-- ============================================================================
-- parseCommandArgs
-- ============================================================================

/-- Pi `parseCommandArgs`: bash-style argument parsing respecting quotes.
Whitespace (space/tab/newline) separates tokens; matched quotes preserve
internal whitespace. Empty quoted tokens are dropped. -/
def parseCommandArgs (argsString : String) : Array String :=
  let commit (current : List Char) (out : Array String) : Array String :=
    if current.isEmpty then out else out.push (String.ofList current.reverse)
  let rec loop
      (cs : List Char) (quote? : Option Char) (current : List Char) (out : Array String) :
      Array String :=
    match cs with
    | [] => commit current out
    | c :: rest =>
        match quote? with
        | some q =>
            if c == q then loop rest none current out
            else loop rest quote? (c :: current) out
        | none =>
            if c == '"' || c == '\'' then
              loop rest (some c) current out
            else if c.isWhitespace then
              loop rest none [] (commit current out)
            else
              loop rest none (c :: current) out
  loop argsString.toList none [] #[]

-- ============================================================================
-- substituteArgs (index-based scanner over List Char)
-- ============================================================================

/-- Maximal ASCII-digit run at index `i`; returns digits + next index. -/
def readDigitsAt (chars : List Char) (i : Nat) : String × Nat :=
  let rec step (cs : List Char) : String × Nat :=
    match cs with
    | c :: rest =>
        if c.isDigit then
          let (s, n) := step rest
          (String.ofList (c :: s.toList), n + 1)
        else ("", 0)
    | [] => ("", 0)
  let (s, n) := step (chars.drop i)
  (s, i + n)

/-- Read until delimiter `delim`; returns (chars before, index at delim or end). -/
def readUntilAt (chars : List Char) (i : Nat) (delim : Char) : String × Nat :=
  let rec step (cs : List Char) : String × Nat :=
    match cs with
    | c :: rest =>
        if c == delim then ("", 0)
        else
          let (s, n) := step rest
          (String.ofList (c :: s.toList), n + 1)
    | [] => ("", 0)
  let (s, n) := step (chars.drop i)
  (s, i + n)

/-- `true` if `chars[start…]` begins with `s`. -/
def startsWithAt (chars : List Char) (start : Nat) (s : String) : Bool :=
  let rec step (cs : List Char) (ws : List Char) : Bool :=
    match ws with
    | [] => true
    | w :: wrest =>
        match cs with
        | c :: crest => if c == w then step crest wrest else false
        | [] => false
  step (chars.drop start) s.toList

/-- Slice helper: args from 1-based `start`, optionally limited to `len`. -/
def joinArgsFrom (args : Array String) (start : Nat) (len? : Option Nat) : String :=
  -- Pi converts to 0-indexed with `start - 1`, treating 0 as 1 (Nat subtraction
  -- saturates at 0, giving exactly max(0, start-1)).
  let start0 := start - 1
  let available := if start0 ≥ args.size then #[] else args.extract start0 args.size
  let selected :=
    match len? with
    | some len => available.extract 0 (Nat.min len available.size)
    | none => available
  String.intercalate " " selected.toList

/-- `args[index]?` for a 1-based positional; `0` and out-of-range → none. -/
def positionalArg? (args : Array String) (oneBased : Nat) : Option String :=
  if oneBased == 0 then none else args[oneBased - 1]?

/--
Try to consume a placeholder beginning at `i` (where `chars[i] == '$'`).
Returns `(replacement, nextIndex)` with `nextIndex > i`, or `none` to leave
the `$` literal. `readDigitsAt`/`readUntilAt` only ever advance, so every
returned index is `> i`.
-/
def consumeDollar (chars : List Char) (i : Nat) (args : Array String) (allArgs : String) :
    Option (String × Nat) :=
  let next := i + 1
  match nthChar? chars next with
  | some '{' =>
      -- braced: ${@:N[:L]} or ${N:-default}
      let inside := next + 1
      match nthChar? chars inside with
      | some '@' =>
          match nthChar? chars (inside + 1) with
          | some ':' =>
              let (startStr, k) := readDigitsAt chars (inside + 2)
              match nthChar? chars k with
              | some '}' => some (joinArgsFrom args startStr.toNat! none, k + 1)
              | some ':' =>
                  let (lenStr, m) := readDigitsAt chars (k + 1)
                  match nthChar? chars m with
                  | some '}' => some (joinArgsFrom args startStr.toNat! (some lenStr.toNat!), m + 1)
                  | _ => none
              | _ => none
          | _ => none
      | some d =>
          if d.isDigit then
            let (numStr, k) := readDigitsAt chars inside
            match nthChar? chars k, nthChar? chars (k + 1) with
            | some ':', some '-' =>
                let (defaultStr, m) := readUntilAt chars (k + 2) '}'
                match nthChar? chars m with
                | some '}' =>
                    let replacement :=
                      match positionalArg? args numStr.toNat! with
                      | some v => if v.isEmpty then defaultStr else v
                      | none => defaultStr
                    some (replacement, m + 1)
                | _ => none
            | _, _ => none
          else none
      | _ => none
  | some c =>
      if c == 'A' && startsWithAt chars next "ARGUMENTS" then
        some (allArgs, next + "ARGUMENTS".length)
      else if c == '@' then
        some (allArgs, next + 1)
      else if c.isDigit then
        let (numStr, k) := readDigitsAt chars next
        some (positionalArg? args numStr.toNat! |>.getD "", k)
      else none
  | none => none

/-- Pi `substituteArgs`: single-pass placeholder substitution.

`partial` is used only for the variable-jump scanner: `i` strictly increases on
every step (placeholder matches advance by `≥ 1`; literals by `1`) and is
bounded by `chars.length`, so termination on finite input is obvious. -/
partial def substituteArgs (content : String) (args : Array String) : String :=
  let allArgs := String.intercalate " " args.toList
  let chars := content.toList
  let prepend (s : String) (acc : List Char) : List Char :=
    s.toList.foldl (fun a c => c :: a) acc
  let rec go (i : Nat) (acc : List Char) : List Char :=
    match nthChar? chars i with
    | none => acc
    | some '$' =>
        match consumeDollar chars i args allArgs with
        | some (replacement, next) => go next (prepend replacement acc)
        | none => go (i + 1) ('$' :: acc)
    | some c => go (i + 1) (c :: acc)
  String.ofList (go 0 []).reverse

-- ============================================================================
-- expandPromptTemplate
-- ============================================================================

/-- Parse `/name args…` into `(name, argsString)`; returns `none` if malformed. -/
def parseInvocation (afterSlash : String) : Option (String × String) :=
  let chars := afterSlash.toList
  let nameChars := chars.takeWhile (fun c => !c.isWhitespace)
  if nameChars.isEmpty then none
  else
    let name := String.ofList nameChars
    let rest := chars.drop nameChars.length
    if rest.isEmpty then some (name, "")
    else some (name, String.ofList (rest.dropWhile Char.isWhitespace))

/-- Pi `expandPromptTemplate`: expand `/name args…` against loaded templates. -/
def expandPromptTemplate (text : String) (templates : Array PromptTemplate) : String :=
  if !text.startsWith "/" then text
  else
    match parseInvocation (text.drop 1).toString with
    | none => text
    | some (name, argsString) =>
        match templates.find? (fun t => t.name == name) with
        | some template => substituteArgs template.content (parseCommandArgs argsString)
        | none => text

-- ============================================================================
-- Frontmatter scalar parsing (YAML subset: plain / double / single quoted)
-- ============================================================================

/-- Strip surrounding quotes for a YAML scalar value (subset, no full escapes). -/
def unquoteScalar (value : String) : String :=
  let s := value.trimAscii.toString
  let chars := s.toList
  let len := chars.length
  if len ≥ 2 then
    match nthChar? chars 0, nthChar? chars (len - 1) with
    | some '"', some '"' => String.ofList (chars.extract 1 (len - 1))
    | some '\'', some '\'' => (String.ofList (chars.extract 1 (len - 1))).replace "''" "'"
    | _, _ => s
  else s

-- ============================================================================
-- Template loading
-- ============================================================================

/-- Filename without trailing `.md`. -/
def templateNameFromFile (filePath : String) : String :=
  let base :=
    match (filePath.splitOn "/").getLast? with
    | some b => b
    | none => filePath
  if base.endsWith ".md" then (base.dropEnd 3).toString else base

/-- First non-empty body line, truncated to 60 chars with ellipsis. -/
def descriptionFromBody (body : String) : String :=
  match body.splitOn "\n" |>.find? (fun line => !line.trimAscii.isEmpty) with
  | some firstLine =>
      if firstLine.length > 60 then
        (firstLine.take 60).toString ++ "..."
      else firstLine
  | none => ""

/-- Parse a markdown file into a `PromptTemplate` (Pi `loadTemplateFromFile`). -/
def parseTemplate (filePath : String) (content : String) (sourceInfo : SourceInfo) : PromptTemplate :=
  let (pairs, body) := parseSimpleFrontmatter content
  let name := templateNameFromFile filePath
  let description :=
    match pairs.find? (fun p => p.1 == "description") with
    | some (_, v) => unquoteScalar v
    | none => descriptionFromBody body
  let argumentHint :=
    match pairs.find? (fun p => p.1 == "argument-hint") with
    | some (_, v) =>
        let parsed := unquoteScalar v
        if parsed.isEmpty then none else some parsed
    | none => none
  { name := name
    description := description
    argumentHint := argumentHint
    content := body
    sourceInfo := sourceInfo
    filePath := filePath
  }

/-- Load a template from disk (Pi `loadTemplateFromFile`); `none` on read error. -/
def loadTemplateFromFile (filePath : System.FilePath) (sourceInfo : SourceInfo) :
    IO (Option PromptTemplate) := do
  try
    let content ← IO.FS.readFile filePath
    pure (some (parseTemplate filePath.toString content sourceInfo))
  catch _ => pure none

/-- Scan a directory (non-recursive) for `*.md` templates (Pi `loadTemplatesFromDir`). -/
def loadTemplatesFromDir
    (dir : System.FilePath) (sourceInfoFor : System.FilePath → SourceInfo) :
    IO (Array PromptTemplate) := do
  let dirExists ← dir.pathExists
  if !dirExists then pure #[]
  else
    try
      let entries ← dir.readDir
      let mut templates := #[]
      for entry in entries do
        let path := entry.path
        -- readDir entries are files or dirs; load only regular .md files
        let isDir ← path.isDir
        if !isDir && path.toString.endsWith ".md" then
          match ← loadTemplateFromFile path (sourceInfoFor path) with
          | some t => templates := templates.push t
          | none => pure ()
      pure templates
    catch _ => pure #[]

/-- Options for `loadPromptTemplates` (Pi `LoadPromptTemplatesOptions`). -/
structure LoadPromptTemplatesOptions where
  cwd : System.FilePath
  agentDir : System.FilePath
  promptPaths : Array System.FilePath := #[]
  includeDefaults : Bool := true

/-- `true` iff `target` is `root` or lives under `root`. -/
def isUnderPath (target : System.FilePath) (root : System.FilePath) : Bool :=
  let t := target.toString
  let r := root.toString
  t == r || t.startsWith (r ++ "/")

/-- Pi `loadPromptTemplates`: global + project + explicit paths. -/
def loadPromptTemplates (options : LoadPromptTemplatesOptions) : IO (Array PromptTemplate) := do
  let resolvedCwd ← normalizePath options.cwd.toString { trim := true }
  let resolvedAgentDir ← normalizePath options.agentDir.toString { trim := true }
  let globalPromptsDir := System.FilePath.mk resolvedAgentDir / "prompts"
  let projectPromptsDir := System.FilePath.mk resolvedCwd / configDirName / "prompts"

  let sourceInfoFor (resolvedPath : System.FilePath) : SourceInfo :=
    if isUnderPath resolvedPath globalPromptsDir then
      { path := resolvedPath.toString, source := "local", scope := .user, baseDir := globalPromptsDir.toString }
    else if isUnderPath resolvedPath projectPromptsDir then
      { path := resolvedPath.toString, source := "local", scope := .project, baseDir := projectPromptsDir.toString }
    else
      { path := resolvedPath.toString, source := "local", baseDir := resolvedPath.toString }

  let mut templates := #[]
  if options.includeDefaults then
    templates := templates ++ (← loadTemplatesFromDir globalPromptsDir sourceInfoFor)
    templates := templates ++ (← loadTemplatesFromDir projectPromptsDir sourceInfoFor)
  for rawPath in options.promptPaths do
    let resolved ← normalizePath rawPath.toString { trim := true }
    let path := System.FilePath.mk resolved
    let pathPresent ← path.pathExists
    if !pathPresent then continue
    let isDir ← path.isDir
    if isDir then
      templates := templates ++ (← loadTemplatesFromDir path sourceInfoFor)
    else if path.toString.endsWith ".md" then
      match ← loadTemplateFromFile path (sourceInfoFor path) with
      | some t => templates := templates.push t
      | none => pure ()
  pure templates

end LeanAgent.CodingAgent.PromptTemplates
