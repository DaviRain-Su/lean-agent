import Lean

/-!
# Fuzzy matching utilities

Port of Pi `packages/tui/src/fuzzy.ts`.
-/

namespace LeanAgent.Tui.Fuzzy

/-- Result of a fuzzy match attempt (Pi `FuzzyMatch`). -/
structure FuzzyMatch where
  isMatch : Bool
  score : Float
deriving Repr, Inhabited

/-- Characters treated as word boundaries for scoring. -/
def isWordBoundaryChar (c : Char) : Bool :=
  c.isWhitespace || c ∈ ['-', '_', '.', '/', ':']

/-- Match query as a subsequence of text, returning a score (lower = better). -/
def fuzzyMatchCore (query : String) (text : String) : FuzzyMatch :=
  if query.isEmpty then
    { isMatch := true, score := 0 }
  else if query.length > text.length then
    { isMatch := false, score := 0 }
  else
    let queryLower := query.toLower
    let textLower := text.toLower
    let queryChars := queryLower.toList
    let textChars := textLower.toList
    let textLen := textChars.length
    let rec loop (qi : List Char) (ti : Nat) (score : Float) (lastMatchIdx : Nat) (consec : Nat)
        : FuzzyMatch :=
      match qi with
      | [] => { isMatch := true, score := score - (if queryLower == textLower then 100 else 0) }
      | qc :: qrest =>
        if ti >= textLen then { isMatch := false, score := 0 }
        else
          let tc := textChars.getD ti qc
          if qc == tc then
            let isBoundary : Bool :=
              ti == 0 || (ti > 0 && isWordBoundaryChar (textChars.getD (ti - 1) ' '))
            let isConsec : Bool := lastMatchIdx + 1 == ti
            let newConsec := if isConsec then consec + 1 else 0
            let consecBonus : Float := if isConsec then -newConsec.toFloat * 5 else 0
            let gapPenalty : Float :=
              if lastMatchIdx > 0 then (ti.toFloat - lastMatchIdx.toFloat - 1) * 2 else 0
            let boundaryBonus : Float := if isBoundary then -10 else 0
            let posPenalty : Float := ti.toFloat * 0.1
            let newScore := score + consecBonus + gapPenalty + boundaryBonus + posPenalty
            loop qrest (ti + 1) newScore ti newConsec
          else
            loop qi (ti + 1) score lastMatchIdx consec
      termination_by (textLen - ti, qi.length)
      decreasing_by
        all_goals simp_wf
        · omega
        · omega
    loop queryChars 0 0 0 0

/-- Try to swap alpha-numeric groups in query (e.g. `abc123` → `123abc`). -/
def trySwapAlphaNumeric (query : String) : Option String :=
  let lower := query.toLower
  let chars := lower.toList
  let rec findSplit (acc : List Char) (rest : List Char) : Option (List Char × List Char) :=
    match rest with
    | [] => none
    | c :: cs =>
      if c.isDigit && !acc.isEmpty && !(acc.getLastD ' ').isDigit then
        some (acc, rest)
      else if c.isAlpha && !acc.isEmpty && !(acc.getLastD ' ').isAlpha then
        some (acc, rest)
      else
        findSplit (acc ++ [c]) cs
  match findSplit [] chars with
  | some (first, second) =>
      let firstAllAlpha := first.all Char.isAlpha
      let firstAllDigit := first.all Char.isDigit
      let secondAllAlpha := second.all Char.isAlpha
      let secondAllDigit := second.all Char.isDigit
      if (firstAllAlpha && secondAllDigit) || (firstAllDigit && secondAllAlpha) then
        some (String.ofList (second ++ first))
      else none
  | none => none

/--
Full fuzzy match with alpha-numeric swap fallback (Pi `fuzzyMatch`).
-/
def fuzzyMatch (query : String) (text : String) : FuzzyMatch :=
  let primary := fuzzyMatchCore query text
  if primary.isMatch then primary
  else
    match trySwapAlphaNumeric query with
    | some swapped =>
        let swappedMatch := fuzzyMatchCore swapped text
        if swappedMatch.isMatch then
          { isMatch := true, score := swappedMatch.score + 5 }
        else primary
    | none => primary

/-- Check if a string contains only whitespace. -/
def allWhitespace (s : String) : Bool :=
  s.isEmpty || s.all (·.isWhitespace)

/--
Filter and sort items by fuzzy match quality (best matches first).
Supports whitespace- and slash-separated tokens: all tokens must match.
(Pi `fuzzyFilter`)
-/
def fuzzyFilter (items : Array String) (query : String) : Array String :=
  if allWhitespace query then items
  else
    let tokens := query.splitOn " "
    let allTokens := (tokens.flatMap (fun t => t.splitOn "/")).filter (!·.isEmpty)
    if allTokens.isEmpty then items
    else
      let results : Array (String × Float) := items.foldl (fun acc item =>
        let allMatch := allTokens.all (fun token => (fuzzyMatch token item).isMatch)
        if allMatch then
          let totalScore := allTokens.foldl (fun s token =>
            let m := fuzzyMatch token item
            if m.isMatch then s + m.score else s) (0 : Float)
          acc.push (item, totalScore)
        else acc) #[]
      let sorted := results.qsort (fun a b => a.2 < b.2)
      sorted.map (·.1)

end LeanAgent.Tui.Fuzzy