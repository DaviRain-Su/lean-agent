import Lean
import LeanAgent.AI.Types
import LeanAgent.Json

namespace LeanAgent.AI.Util.Diagnostics

def formatThrownValue (value : String) : String :=
  value

def formatThrownJsonValue : Lean.Json → String
  | Lean.Json.str value => value
  | value => value.compress

def extractDiagnosticError
    (message : String)
    (name : Option String := none)
    (stack : Option String := none)
    (code : Option Lean.Json := none) : DiagnosticErrorInfo :=
  { name := name
    message := if message.isEmpty then name.getD "Error" else message
    stack := stack
    code := code
  }

def extractThrownJsonError (value : Lean.Json) : DiagnosticErrorInfo :=
  { name := some "ThrownValue"
    message := formatThrownJsonValue value
  }

def createAssistantMessageDiagnostic
    (type : String)
    (errorMessage : String)
    (details : Option Lean.Json := none)
    (timestamp : Nat) : AssistantMessageDiagnostic :=
  { type := type
    timestamp := timestamp
    error := some (extractDiagnosticError errorMessage)
    details := details
  }

def createAssistantMessageDiagnosticFromJsonValue
    (type : String)
    (error : Lean.Json)
    (details : Option Lean.Json := none)
    (timestamp : Nat) : AssistantMessageDiagnostic :=
  { type := type
    timestamp := timestamp
    error := some (extractThrownJsonError error)
    details := details
  }

def appendAssistantMessageDiagnostic
    (message : AssistantMessage)
    (diagnostic : AssistantMessageDiagnostic) : AssistantMessage :=
  { message with diagnostics := message.diagnostics.push diagnostic }

def jsonString? : Lean.Json → Option String
  | Lean.Json.str value => some value
  | _ => none

def diagnosticCode? : Lean.Json → Option Lean.Json
  | Lean.Json.str value => some (LeanAgent.Json.str value)
  | Lean.Json.num value => some (Lean.Json.num value)
  | _ => none

def providerErrorObject (json : Lean.Json) : Lean.Json :=
  match LeanAgent.Json.optVal? json "error" with
  | some value => value
  | none => json

def providerErrorInfoFromJson (json : Lean.Json) : DiagnosticErrorInfo :=
  let err := providerErrorObject json
  let message :=
    match (LeanAgent.Json.optVal? err "message").bind jsonString? with
    | some value => value
    | none => err.compress
  { name := (LeanAgent.Json.optVal? err "type").bind jsonString?
    message := message
    code := (LeanAgent.Json.optVal? err "code").bind diagnosticCode?
  }

def providerErrorInfoFromBody (body : String) : DiagnosticErrorInfo :=
  match Lean.Json.parse body with
  | .ok json => providerErrorInfoFromJson json
  | .error _ => extractDiagnosticError body

def providerHttpErrorMessage (status : Nat) (body : String) : String :=
  let info := providerErrorInfoFromBody body
  let typePart :=
    match info.name with
    | some name => s!" type={name}"
    | none => ""
  let codePart :=
    match info.code with
    | some code => s!" code={code.compress}"
    | none => ""
  s!"provider HTTP {status}: {info.message}{typePart}{codePart}"

def providerParseErrorMessage (body : String) : String :=
  let info := providerErrorInfoFromBody body
  info.message

end LeanAgent.AI.Util.Diagnostics
