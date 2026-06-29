import LeanAgent.AI.Auth

namespace LeanAgent.AI.Util.ProviderEnv

abbrev ProviderEnv := LeanAgent.AI.Auth.ProviderEnv

def normalizeValue? (value : Option String) : Option String :=
  match value with
  | some value =>
      let trimmed := value.trimAscii.toString
      if trimmed.isEmpty then none else some value
  | none => none

def scopedValue? (env : ProviderEnv) (name : String) : Option String :=
  LeanAgent.AI.Auth.providerEnvGet? env name

def merge (base override : ProviderEnv) : ProviderEnv :=
  LeanAgent.AI.Auth.providerEnvMerge base override

def getProviderEnvValueWith
    (ambient : String → IO (Option String))
    (name : String)
    (env : ProviderEnv := #[]) : IO (Option String) := do
  match scopedValue? env name with
  | some value => pure (some value)
  | none => pure (normalizeValue? (← ambient name))

def getProviderEnvValue (name : String) (env : ProviderEnv := #[]) : IO (Option String) :=
  getProviderEnvValueWith (fun key => do pure (← IO.getEnv key)) name env

end LeanAgent.AI.Util.ProviderEnv
