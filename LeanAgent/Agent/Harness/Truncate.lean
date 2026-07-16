import Lean

namespace LeanAgent.Agent.Harness.Truncate

/-- Truncate text to at most `maxChars`, appending ellipsis when cut. -/
def truncate (text : String) (maxChars : Nat) : String :=
  if text.length ≤ maxChars then
    text
  else if maxChars == 0 then
    ""
  else if maxChars ≤ 3 then
    text.take maxChars |>.toString
  else
    (text.take (maxChars - 3)).toString ++ "..."

/-- Truncate multi-line shell output keeping head and tail lines. -/
def truncateShellOutput (text : String) (maxLines : Nat := 40) : String :=
  let lines := text.splitOn "\n"
  if lines.length ≤ maxLines then
    text
  else
    let headCount := maxLines / 2
    let tailCount := maxLines - headCount
    let head := lines.take headCount
    let tail := lines.drop (lines.length - tailCount)
    String.intercalate "\n" (head ++ ["..."] ++ tail)

end LeanAgent.Agent.Harness.Truncate
