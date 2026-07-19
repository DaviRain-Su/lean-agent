import Lean

/-!
# Resource diagnostics (Pi `packages/coding-agent/src/core/diagnostics.ts`)
-/

namespace LeanAgent.CodingAgent.Diagnostics

structure ResourceCollision where
  resourceType : String
  name : String
  winnerPath : String
  loserPath : String
  winnerSource : Option String := none
  loserSource : Option String := none
deriving Inhabited, BEq

inductive DiagnosticType where
  | warning
  | error
  | collision
deriving BEq, Repr, Inhabited

structure ResourceDiagnostic where
  type : DiagnosticType
  message : String
  path : Option String := none
  collision : Option ResourceCollision := none
deriving Inhabited

def formatDiagnostic (d : ResourceDiagnostic) : String :=
  let kind :=
    match d.type with
    | .warning => "warning"
    | .error => "error"
    | .collision => "collision"
  let pathPart :=
    match d.path with
    | some p => s!" ({p})"
    | none => ""
  s!"{kind}: {d.message}{pathPart}"

end LeanAgent.CodingAgent.Diagnostics
