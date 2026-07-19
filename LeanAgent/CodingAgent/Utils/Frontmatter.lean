import Lean

/-!
# Frontmatter strip/parse (Pi `utils/frontmatter.ts` subset)

YAML body extraction without a full YAML parser: returns raw YAML string + body.
Callers may parse YAML separately when needed.
-/

namespace LeanAgent.CodingAgent.Utils.Frontmatter

structure ParsedFrontmatter where
  yamlString : Option String := none
  body : String
deriving Inhabited

def normalizeNewlines (value : String) : String :=
  (value.replace "\r\n" "\n").replace "\r" "\n"

/-- Extract `---` YAML block if present. -/
def extractFrontmatter (content : String) : ParsedFrontmatter :=
  let normalized := normalizeNewlines content
  if !normalized.startsWith "---" then
    { yamlString := none, body := normalized }
  else
    -- find \n--- after the opening fence
    let rest := (normalized.drop 3).toString
    match rest.splitOn "\n---" with
    | yaml :: bodyParts =>
        let body := String.intercalate "\n---" bodyParts |>.trimAscii.toString
        -- drop leading newline from yaml if present
        let yamlS :=
          if yaml.startsWith "\n" then (yaml.drop 1).toString else yaml
        { yamlString := some yamlS, body := body }
    | [] => { yamlString := none, body := normalized }

/-- Pi `stripFrontmatter`. -/
def stripFrontmatter (content : String) : String :=
  (extractFrontmatter content).body

/-- Strip surrounding single or double quotes from a value. -/
def stripQuotes (s : String) : String :=
  let s := s.trimAscii.toString
  if s.length >= 2 then
    let first := s.get ⟨0⟩
    let last := s.get ⟨s.length - 1⟩
    if (first == '"' && last == '"') || (first == '\'' && last == '\'') then
      (s.drop 1 |>.dropEnd 1).toString
    else
      s
  else
    s

/-- Simple key: value frontmatter lines (no nested YAML). -/
def parseSimpleFrontmatter (content : String) : List (String × String) × String :=
  let extracted := extractFrontmatter content
  match extracted.yamlString with
  | none => ([], extracted.body)
  | some yaml =>
      let pairs :=
        yaml.splitOn "\n" |>.filterMap fun line =>
          let t := line.trimAscii.toString
          if t.isEmpty || t.startsWith "#" then
            none
          else
            match t.splitOn ":" with
            | k :: rest =>
                let key := k.trimAscii.toString
                let val := stripQuotes (String.intercalate ":" rest)
                some (key, val)
            | [] => none
      (pairs, extracted.body)

end LeanAgent.CodingAgent.Utils.Frontmatter
