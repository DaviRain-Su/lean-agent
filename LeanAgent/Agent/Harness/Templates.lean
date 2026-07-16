import Lean

namespace LeanAgent.Agent.Harness.Templates

structure PromptTemplate where
  name : String
  description : String := ""
  body : String
deriving Inhabited

/-- Expand `$ARGUMENTS` and `$1`.. style placeholders (subset of Pi prompt templates). -/
def expandTemplate (body : String) (args : Array String) : String :=
  Id.run do
    let joined := String.intercalate " " args.toList
    let mut out := body.replace "$ARGUMENTS" joined |>.replace "$@" joined
    let mut i := 0
    while i < args.size do
      out := out.replace s!"${i + 1}" args[i]!
      i := i + 1
    pure out

def formatPromptTemplateInvocation (template : PromptTemplate) (args : Array String) : String :=
  expandTemplate template.body args

end LeanAgent.Agent.Harness.Templates
