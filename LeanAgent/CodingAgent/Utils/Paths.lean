import Lean

/-!
# Path helpers (Pi `utils/paths.ts` subset)
-/

namespace LeanAgent.CodingAgent.Utils.Paths

structure PathInputOptions where
  trim : Bool := false
  expandTilde : Bool := true
  homeDir : Option String := none
  stripAtPrefix : Bool := false
deriving Inhabited

/-- True when value is a local path/name (not npm:/git:/http(s):/ssh:). -/
def isLocalPath (value : String) : Bool :=
  let trimmed := value.trimAscii.toString
  !(trimmed.startsWith "npm:" ||
    trimmed.startsWith "git:" ||
    trimmed.startsWith "github:" ||
    trimmed.startsWith "http:" ||
    trimmed.startsWith "https:" ||
    trimmed.startsWith "ssh:")

/-- Pi `normalizePath` subset (tilde expand, @ strip, trim). -/
def normalizePath (input : String) (options : PathInputOptions := {}) : IO String := do
  let mut normalized := if options.trim then input.trimAscii.toString else input
  if options.stripAtPrefix && normalized.startsWith "@" then
    normalized := (normalized.drop 1).toString
  if options.expandTilde then
    let home ←
      match options.homeDir with
      | some h => pure h
      | none =>
          match ← IO.getEnv "HOME" with
          | some h => pure h
          | none => pure ""
    if !home.isEmpty then
      if normalized == "~" then
        return home
      if normalized.startsWith "~/" then
        return home ++ (normalized.drop 1).toString
  pure normalized

/-- Canonicalize if exists; else return path (Pi realpath fallback). -/
def canonicalizePath (path : String) : IO String := do
  let fp := System.FilePath.mk path
  if ← fp.pathExists then
    try
      pure (← IO.FS.realPath fp).toString
    catch _ =>
      pure path
  else
    pure path

end LeanAgent.CodingAgent.Utils.Paths
