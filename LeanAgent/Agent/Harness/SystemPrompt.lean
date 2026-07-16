import Lean
import LeanAgent.Project

namespace LeanAgent.Agent.Harness.SystemPrompt

structure SkillInfo where
  name : String
  description : String
  filePath : String
  disableModelInvocation : Bool := false
deriving Inhabited

def escapeXml (value : String) : String :=
  value.replace "&" "&amp;"
    |>.replace "<" "&lt;"
    |>.replace ">" "&gt;"
    |>.replace "\"" "&quot;"
    |>.replace "'" "&apos;"

/-- Pi formatSkillsForSystemPrompt. -/
def formatSkillsForSystemPrompt (skills : Array SkillInfo) : String :=
  let visible := skills.filter (fun s => !s.disableModelInvocation)
  if visible.isEmpty then
    ""
  else
    let header :=
      #["The following skills provide specialized instructions for specific tasks."
        , "Read the full skill file when the task matches its description."
        , "When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands."
        , ""
        , "<available_skills>"
        ]
    let body := Id.run do
      let mut lines : Array String := #[]
      for skill in visible do
        lines :=
          lines
            ++ #["  <skill>"
                , s!"    <name>{escapeXml skill.name}</name>"
                , s!"    <description>{escapeXml skill.description}</description>"
                , s!"    <location>{escapeXml skill.filePath}</location>"
                , "  </skill>"
                ]
      pure lines
    let lines := header ++ body ++ #["</available_skills>"]
    String.intercalate "\n" lines.toList

/-- Build a system prompt from base text plus optional skills block. -/
def buildSystemPrompt (base : String) (skills : Array SkillInfo := #[]) : String :=
  let skillsBlock := formatSkillsForSystemPrompt skills
  if skillsBlock.isEmpty then
    base
  else if base.isEmpty then
    skillsBlock
  else
    base ++ "\n\n" ++ skillsBlock

/-- Map Project OMP skills into harness SkillInfo (shared discovery ownership). -/
def skillInfoFromProject (skill : LeanAgent.Project.Skill) : SkillInfo :=
  { name := skill.name
    description := skill.description
    filePath := skill.path.toString
  }

end LeanAgent.Agent.Harness.SystemPrompt
