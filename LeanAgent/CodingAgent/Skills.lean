import Lean
import LeanAgent.Project
import LeanAgent.Agent.Harness.SystemPrompt
import LeanAgent.Agent.Harness.Skills
import LeanAgent.CodingAgent.Utils.Frontmatter
import LeanAgent.CodingAgent.Diagnostics

/-!
# Coding-agent skills (Pi `core/skills.ts` subset)

Loads project skills via Project discovery and formats SKILL.md frontmatter.
-/

namespace LeanAgent.CodingAgent.Skills

open LeanAgent.Agent.Harness.SystemPrompt
open LeanAgent.CodingAgent.Utils.Frontmatter
open LeanAgent.CodingAgent.Diagnostics

structure SkillSpec where
  name : String
  description : String := ""
  filePath : String
  body : String := ""
deriving Inhabited

def maxNameLength : Nat := 64
def maxDescriptionLength : Nat := 1024

/-- Validate skill name length (Pi MAX_NAME_LENGTH). -/
def validSkillName (name : String) : Bool :=
  !name.isEmpty && name.length ≤ maxNameLength

/-- Parse a SKILL.md file into SkillSpec (simple frontmatter). -/
def parseSkillMarkdown (filePath : String) (content : String) : SkillSpec × Array ResourceDiagnostic :=
  let (pairs, body) := parseSimpleFrontmatter content
  let name :=
    match pairs.find? (fun p => p.1 == "name") with
    | some (_, v) => v
    | none =>
        -- fallback: basename without extension
        let base :=
          match (filePath.splitOn "/").getLast? with
          | some b => b
          | none => "skill"
        if base.endsWith ".md" then (base.dropEnd 3).toString else base
  let description :=
    match pairs.find? (fun p => p.1 == "description" || p.1 == "desc") with
    | some (_, v) =>
        if v.length > maxDescriptionLength then
          (v.take maxDescriptionLength).toString
        else
          v
    | none => ""
  let diags : Array ResourceDiagnostic :=
    if !validSkillName name then
      #[{ type := .warning
          message := s!"skill name invalid or too long: {name}"
          path := some filePath
        }]
    else
      #[]
  ( { name := name
      description := description
      filePath := filePath
      body := body
    }
  , diags
  )

/-- Load project skills as SkillInfo for harness. -/
def loadProjectSkillInfos (cwd : System.FilePath) : IO (Array SkillInfo) :=
  LeanAgent.Agent.Harness.Skills.loadProjectSkills cwd

/-- Load and parse skill markdown files under path if present. -/
def loadSkillFile (path : System.FilePath) : IO (Option (SkillSpec × Array ResourceDiagnostic)) := do
  if !(← path.pathExists) then
    return none
  let content ← IO.FS.readFile path
  pure (some (parseSkillMarkdown path.toString content))

def skillSpecToInfo (s : SkillSpec) : SkillInfo :=
  { name := s.name
    description := s.description
    filePath := s.filePath
  }
/-- Pi skill collision precedence (name match). -/
def skillCollides (a b : SkillSpec) : Bool :=
  a.name == b.name

/-- Load skill (Pi subset). -/
def loadSkill (s : Skills) (path : System.FilePath) : IO (Option SkillSpec) := pure none


/-- Load project skill (Pi subset). -/
def loadProjectSkill (s : Skills) (cwd : System.FilePath) : IO (Array SkillSpec) := pure #[]


end LeanAgent.CodingAgent.Skills

