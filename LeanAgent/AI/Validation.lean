import LeanAgent.AI.Schema
import LeanAgent.AI.Types

namespace LeanAgent.AI.Validation

def findTool? (tools : Array Tool) (name : String) : Option Tool :=
  tools.find? fun tool => tool.name == name

def formatIssue (issue : LeanAgent.AI.Schema.ValidationIssue) : String :=
  "  - " ++ issue.path ++ ": " ++ issue.message

def formatIssues (issues : List LeanAgent.AI.Schema.ValidationIssue) : String :=
  match issues with
  | [] => "Unknown validation error"
  | _ => String.intercalate "\n" (issues.map formatIssue)

def validateToolArguments (tool : Tool) (toolCall : ToolCall) : Except String Lean.Json :=
  match LeanAgent.AI.Schema.validateJson tool.parameters toolCall.arguments with
  | .ok args => pure args
  | .error issues =>
      throw
        ("Validation failed for tool \"" ++ toolCall.name ++ "\":\n" ++
          formatIssues issues ++
          "\n\nReceived arguments:\n" ++ toolCall.arguments.compress)

def validateToolCall (tools : Array Tool) (toolCall : ToolCall) : Except String Lean.Json := do
  let tool ←
    match findTool? tools toolCall.name with
    | some tool => pure tool
    | none => throw s!"Tool \"{toolCall.name}\" not found"
  validateToolArguments tool toolCall

end LeanAgent.AI.Validation
