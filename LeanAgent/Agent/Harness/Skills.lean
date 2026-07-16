import Lean
import LeanAgent.Project
import LeanAgent.Agent.Harness.SystemPrompt

namespace LeanAgent.Agent.Harness.Skills

open LeanAgent.Agent.Harness.SystemPrompt
-- skillInfoFromProject lives in SystemPrompt module

/-- Format a skill invocation payload for the agent (path + optional user args). -/
def formatSkillInvocation (skill : SkillInfo) (args : String := "") : String :=
  let base := s!"Use skill `{skill.name}` from {skill.filePath}."
  if args.isEmpty then base else base ++ " Arguments: " ++ args

/-- Load project OMP skills into harness SkillInfo list via Project discovery. -/
def loadProjectSkills (cwd : System.FilePath) : IO (Array SkillInfo) := do
  let extensions ← LeanAgent.Project.loadExtensions cwd
  pure (extensions.skills.map skillInfoFromProject)

end LeanAgent.Agent.Harness.Skills
