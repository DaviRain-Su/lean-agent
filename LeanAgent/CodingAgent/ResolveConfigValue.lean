import Lean

/-!
# Resolve config values (Pi `resolve-config-value.ts` offline subset)

Resolves `$VAR` / `${VAR}` templates and detects `!command` shells.
Shell command execution (`!…`) is not run in offline mode; callers treat
command configs as configured but unresolved without a runner.
-/

namespace LeanAgent.CodingAgent.ResolveConfigValue

inductive TemplatePart where
  | literal (value : String)
  | env (name : String)
deriving Repr, BEq, Inhabited

inductive ConfigValueReference where
  | command (config : String)
  | template (parts : Array TemplatePart)
deriving Inhabited

def isEnvVarName (name : String) : Bool :=
  if name.isEmpty then
    false
  else
    let chars := name.toList
    match chars with
    | [] => false
    | c :: rest =>
        let firstOk := c.isAlpha || c == '_'
        firstOk && rest.all fun d => d.isAlphanum || d == '_'

def appendLiteral (parts : Array TemplatePart) (value : String) : Array TemplatePart :=
  if value.isEmpty then
    parts
  else
    match parts.back? with
    | some (.literal prev) => parts.set! (parts.size - 1) (.literal (prev ++ value))
    | _ => parts.push (.literal value)

/-- Pi `parseConfigValueTemplate`. -/
def parseConfigValueTemplate (config : String) : Array TemplatePart :=
  Id.run do
    let mut parts : Array TemplatePart := #[]
    let mut index : Nat := 0
    let chars := config.toList.toArray
    while index < chars.size do
      -- find next $
      let mut dollar : Option Nat := none
      let mut j := index
      while j < chars.size do
        if chars[j]! == '$' then
          dollar := some j
          break
        j := j + 1
      match dollar with
      | none =>
          parts := appendLiteral parts (String.ofList (chars.extract index chars.size).toList)
          break
      | some dollarIndex =>
          parts :=
            appendLiteral parts
              (String.ofList (chars.extract index dollarIndex).toList)
          let nextIdx := dollarIndex + 1
          if nextIdx ≥ chars.size then
            parts := appendLiteral parts "$"
            index := nextIdx
          else
            let nextChar := chars[nextIdx]!
            if nextChar == '$' || nextChar == '!' then
              parts := appendLiteral parts (String.singleton nextChar)
              index := dollarIndex + 2
            else if nextChar == '{' then
              let mut endIndex : Option Nat := none
              let mut k := dollarIndex + 2
              while k < chars.size do
                if chars[k]! == '}' then
                  endIndex := some k
                  break
                k := k + 1
              match endIndex with
              | none =>
                  parts := appendLiteral parts "$"
                  index := dollarIndex + 1
              | some endI =>
                  let name :=
                    String.ofList (chars.extract (dollarIndex + 2) endI).toList
                  if isEnvVarName name then
                    parts := parts.push (.env name)
                  else
                    parts :=
                      appendLiteral parts
                        (String.ofList (chars.extract dollarIndex (endI + 1)).toList)
                  index := endI + 1
            else
              -- bare $NAME
              let mut nameChars : List Char := []
              let mut k := nextIdx
              while k < chars.size do
                let c := chars[k]!
                if c.isAlphanum || c == '_' then
                  nameChars := nameChars ++ [c]
                  k := k + 1
                else
                  break
              if nameChars.isEmpty then
                parts := appendLiteral parts "$"
                index := dollarIndex + 1
              else
                let name := String.ofList nameChars
                if isEnvVarName name then
                  parts := parts.push (.env name)
                else
                  parts := appendLiteral parts ("$" ++ name)
                index := k
    pure parts

def parseConfigValueReference (config : String) : ConfigValueReference :=
  if config.startsWith "!" then
    .command config
  else
    .template (parseConfigValueTemplate config)

def isCommandConfigValue (config : String) : Bool :=
  config.startsWith "!"

def getConfigValueEnvVarName (config : String) : Option String :=
  match parseConfigValueReference config with
  | .command _ => none
  | .template parts =>
      if parts.size == 1 then
        match parts[0]! with
        | .env name => some name
        | _ => none
      else
        none

def getConfigValueEnvVarNames (config : String) : Array String :=
  match parseConfigValueReference config with
  | .command _ => #[]
  | .template parts =>
      parts.foldl (init := #[]) fun acc p =>
        match p with
        | .env name => if acc.contains name then acc else acc.push name
        | _ => acc

/-- Resolve using provided map first, then process environment. -/
def resolveEnvConfigValue
    (name : String)
    (env : List (String × String) := []) : IO (Option String) := do
  match env.find? (fun p => p.1 == name) with
  | some (_, v) => pure (some v)
  | none => IO.getEnv name


def resolveTemplate
    (parts : Array TemplatePart)
    (env : List (String × String) := []) : IO (Option String) := do
  let mut resolved := ""
  for part in parts do
    match part with
    | .literal v => resolved := resolved ++ v
    | .env name =>
        match ← resolveEnvConfigValue name env with
        | none => return none
        | some v => resolved := resolved ++ v
  pure (some resolved)

/--
Pi `resolveConfigValue` offline subset: templates via env; commands return none
(no shell). Use `isCommandConfigValue` to detect shell refs.
-/
def resolveConfigValue
    (config : String)
    (env : List (String × String) := []) : IO (Option String) := do
  match parseConfigValueReference config with
  | .command _ => pure none
  | .template parts => resolveTemplate parts env

def resolveConfigValueOrThrow
    (config : String)
    (description : String)
    (env : List (String × String) := []) : IO String := do
  match ← resolveConfigValue config env with
  | some v => pure v
  | none =>
      throw (IO.userError s!"Missing config value for {description}: {config}")

def isConfigValueConfigured
    (config : String)
    (env : List (String × String) := []) : IO Bool := do
  if isCommandConfigValue config then
    pure true
  else
    pure ((← resolveConfigValue config env).isSome)

def getMissingConfigValueEnvVarNames
    (config : String)
    (env : List (String × String) := []) : IO (Array String) := do
  let names := getConfigValueEnvVarNames config
  let mut missing : Array String := #[]
  for name in names do
    match ← resolveEnvConfigValue name env with
    | none => missing := missing.push name
    | some _ => pure ()
  pure missing

/-- Resolve (Pi subset). -/
def resolve (v : ResolveConfigValue) (s : String) : IO String := pure s

end LeanAgent.CodingAgent.ResolveConfigValue

