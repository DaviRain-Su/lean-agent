import Lean
import LeanAgent.CodingAgent.Utils.Html

/-!
# Syntax highlight renderer (Pi `packages/coding-agent/src/utils/syntax-highlight.ts`)

`renderHighlightedHtml` walks the `<span class="hljs-...">...</span>` HTML that
`highlight.js` emits, decodes HTML entities, and applies a caller-supplied
theme (scope → formatter). Scope resolution mirrors Pi: exact match, then
dot-prefix (`title.function` → `title`), then dash-prefix (`meta-attr` →
`meta`), with the innermost scoped span winning.

The `highlight`/`supportsLanguage` entry points wrap the `highlight.js` npm
dependency, which is not ported; callers feed pre-rendered HTML to
`renderHighlightedHtml`.
-/

namespace LeanAgent.CodingAgent.Utils.SyntaxHighlight

open LeanAgent.CodingAgent.Utils.Html

/-- A highlight formatter maps a text run to its rendered form. -/
abbrev HighlightFormatter := String → String

/-- A theme maps scopes (`keyword`, `string.subst`, `meta-attr`, `default`) to formatters. -/
abbrev HighlightTheme := Array (String × HighlightFormatter)

/-- Look up a formatter for a scope: exact, then dot-prefix (if a `.` is
present), then dash-prefix (if a `-` is present). Dot and dash are tried
independently and sequentially (Pi behavior). -/
def getScopeFormatter (scope : String) (theme : HighlightTheme) : Option HighlightFormatter := Id.run do
  match theme.find? (fun (k, _) => k == scope) with
  | some (_, f) => pure (some f)
  | none =>
    let chars := scope.toList.toArray
    let dotIdx := chars.findIdx? (fun c => c == '.')
    match dotIdx with
    | some i =>
      let scopePrefix := String.ofList (chars.extract 0 i).toList
      match theme.find? (fun (k, _) => k == scopePrefix) with
      | some (_, f) => pure (some f)
      | none =>
        let dashIdx := chars.findIdx? (fun c => c == '-')
        match dashIdx with
        | some j =>
          let scopePrefix2 := String.ofList (chars.extract 0 j).toList
          pure (theme.find? (fun (k, _) => k == scopePrefix2) |>.map (·.2))
        | none => pure none
    | none =>
      let dashIdx := chars.findIdx? (fun c => c == '-')
      match dashIdx with
      | some j =>
        let scopePrefix := String.ofList (chars.extract 0 j).toList
        pure (theme.find? (fun (k, _) => k == scopePrefix) |>.map (·.2))
      | none => pure none

/--
Innermost-scope-wins formatter lookup. Scans `scopes` from innermost
(last) to outermost, returning the first scope with a matching formatter, else
`default`.
-/
def getActiveFormatter (scopes : Array (Option String)) (theme : HighlightTheme) :
    Option HighlightFormatter := Id.run do
  let mut i := scopes.size
  while i > 0 do
    i := i - 1
    match scopes[i]! with
    | some scope =>
      match getScopeFormatter scope theme with
      | some f => return some f
      | none => pure ()
    | none => pure ()
  theme.find? (fun (k, _) => k == "default") |>.map (·.2)

/-- Extract the `hljs-<scope>` class value from a `<span ...>` tag. -/
def getScopeFromSpanTag (tag : String) : Option String := Id.run do
  let chars := tag.toList.toArray
  let size := chars.size
  let mut i := 0
  -- Find `class` followed by optional whitespace, `=`, optional whitespace, then a quote.
  while i + 5 ≤ size do
    if chars[i]! == 'c' && chars[i+1]! == 'l' && chars[i+2]! == 'a' && chars[i+3]! == 's' && chars[i+4]! == 's' then
      let mut j := i + 5
      -- skip whitespace
      while j < size && (chars[j]! == ' ' || chars[j]! == '\t' || chars[j]! == '\n' || chars[j]! == '\r') do j := j + 1
      if j < size && chars[j]! == '=' then
        j := j + 1
        while j < size && (chars[j]! == ' ' || chars[j]! == '\t' || chars[j]! == '\n' || chars[j]! == '\r') do j := j + 1
        if j < size && (chars[j]! == '"' || chars[j]! == '\'') then
          let quote := chars[j]!
          j := j + 1
          let start := j
          while j < size && chars[j]! != quote do j := j + 1
          let classValue := String.ofList (chars.extract start j).toList
          -- Find the first `hljs-` class token.
          for tok in classValue.splitOn " " do
            if tok.startsWith "hljs-" then return some (tok.drop 5 |>.toString)
          return none
      i := j
    else i := i + 1
  none

/-- True iff `html` at `index` begins a `<span...` open tag. -/
def isSpanOpenTagStart (chars : Array Char) (index : Nat) : Bool :=
  if index + 5 ≤ chars.size then
    let c0 := chars[index]!
    let c1 := chars[index+1]!
    let c2 := chars[index+2]!
    let c3 := chars[index+3]!
    let c4 := chars[index+4]!
    if c0 == '<' && c1 == 's' && c2 == 'p' && c3 == 'a' && c4 == 'n' then
      if index + 5 < chars.size then
        let nextC := chars[index+5]!
        nextC == '>' || nextC == ' ' || nextC == '\t' || nextC == '\n' || nextC == '\r'
      else false
    else false
  else false

/-- Index of `>` at or after `fromIdx`, or `none`. -/
def findCloseAngle? (chars : Array Char) (fromIdx : Nat) : Option Nat := Id.run do
  let mut i := fromIdx
  let mut found : Option Nat := none
  while i < chars.size && found.isNone do
    if chars[i]! == '>' then found := some i
    i := i + 1
  pure found

/-- `</span>` literal. -/
def spanClose : String := "</span>"

/-- True iff `chars` at `index` begins `</span>`. -/
def isSpanCloseStart (chars : Array Char) (index : Nat) : Bool := Id.run do
  if index + spanClose.length ≤ chars.size then
    let target := spanClose.toList.toArray
    let mut ok := true
    let mut k := 0
    while k < target.size && ok do
      if chars[index + k]! != target[k]! then ok := false
      k := k + 1
    pure ok
  else pure false

/--
Pi `renderHighlightedHtml`: walk highlight.js `<span class="hljs-...">` HTML,
decode HTML entities, and apply the theme. Text inside an unscoped or
unmapped span inherits the active (innermost-mapped) formatter.
-/
partial def renderHighlightedHtml (html : String) (theme : HighlightTheme := #[]) : String :=
  go chars 0 "" "" #[]
where
  chars := html.toList.toArray
  go (chars : Array Char) (index : Nat) (output : String) (textBuffer : String)
      (scopes : Array (Option String)) : String :=
    if index ≥ chars.size then
      let output := output ++ flushText textBuffer scopes
      output
    else
      if isSpanOpenTagStart chars index then
        match findCloseAngle? chars (index + 5) with
        | some tagEnd =>
          let output := output ++ flushText textBuffer scopes
          let tag := String.ofList (chars.extract index (tagEnd + 1)).toList
          let scope := getScopeFromSpanTag tag
          go chars (tagEnd + 1) output "" (scopes.push scope)
        | none => stepChar chars index output textBuffer scopes
      else if isSpanCloseStart chars index then
        let output := output ++ flushText textBuffer scopes
        let scopes := if scopes.size > 0 then scopes.pop else scopes
        go chars (index + spanClose.length) output "" scopes
      else if chars[index]! == '&' then
        match decodeHtmlEntityAt html index with
        | some d => go chars (index + d.length) output (textBuffer ++ d.text) scopes
        | none => stepChar chars index output textBuffer scopes
      else stepChar chars index output textBuffer scopes
  stepChar (chars : Array Char) (index : Nat) (output : String) (textBuffer : String)
      (scopes : Array (Option String)) : String :=
    go chars (index + 1) output (textBuffer ++ String.singleton chars[index]!) scopes
  flushText (textBuffer : String) (scopes : Array (Option String)) : String :=
    if textBuffer.isEmpty then ""
    else
      match getActiveFormatter scopes theme with
      | some f => f textBuffer
      | none => textBuffer

end LeanAgent.CodingAgent.Utils.SyntaxHighlight
