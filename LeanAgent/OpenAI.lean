import Lean
import LeanAgent.Core
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.OpenAI

open LeanAgent

structure OpenAICompatibleConfig where
  apiKey : String
  baseUrl : String := "https://api.openai.com/v1"
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

def chatCompletionsUrl (baseUrl : String) : String :=
  if baseUrl.endsWith "/chat/completions" then
    baseUrl
  else if baseUrl.endsWith "/" then
    baseUrl ++ "chat/completions"
  else
    baseUrl ++ "/chat/completions"

def toolCallToJson (call : ToolCall) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("id", LeanAgent.Json.str call.id)
    , ("type", LeanAgent.Json.str "function")
    , ("function",
        LeanAgent.Json.obj
          [ ("name", LeanAgent.Json.str call.name)
          , ("arguments", LeanAgent.Json.str call.arguments.compress)
          ])
    ]

def messageToJson : AgentMessage → Lean.Json
  | .user content =>
      LeanAgent.Json.obj [("role", LeanAgent.Json.str "user"), ("content", LeanAgent.Json.str content)]
  | .assistant content calls =>
      LeanAgent.Json.obj
        [ ("role", LeanAgent.Json.str "assistant")
        , ("content", if content.isEmpty then LeanAgent.Json.null else LeanAgent.Json.str content)
        , ("tool_calls", LeanAgent.Json.arr (calls.map toolCallToJson))
        ]
  | .toolResult toolCallId _name content _ok =>
      LeanAgent.Json.obj
        [ ("role", LeanAgent.Json.str "tool")
        , ("tool_call_id", LeanAgent.Json.str toolCallId)
        , ("content", LeanAgent.Json.str content)
        ]

def toolToJson (tool : AgentTool) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "function")
    , ("function",
        LeanAgent.Json.obj
          [ ("name", LeanAgent.Json.str tool.name)
          , ("description", LeanAgent.Json.str tool.description)
          , ("parameters", tool.inputSchema)
          ])
    ]

def requestToJson (request : ProviderRequest) : Lean.Json :=
  let messages :=
    #[LeanAgent.Json.obj [("role", LeanAgent.Json.str "system"), ("content", LeanAgent.Json.str request.system)]]
      ++ request.messages.map messageToJson
  LeanAgent.Json.obj
    [ ("model", LeanAgent.Json.str request.model)
    , ("messages", LeanAgent.Json.arr messages)
    , ("tools", LeanAgent.Json.arr (request.tools.map toolToJson))
    , ("tool_choice", LeanAgent.Json.str "auto")
    ]

def runHttpJson (config : OpenAICompatibleConfig) (payload : Lean.Json) : IO String :=
  LeanAgent.Http.postJson
    { url := chatCompletionsUrl config.baseUrl
      apiKey := config.apiKey
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
    }
    payload.compress

def parseMaybeContent (message : Lean.Json) : String :=
  match LeanAgent.Json.optVal? message "content" with
  | some (Lean.Json.str content) => content
  | _ => ""

def parseToolArguments (raw : String) : Except String Lean.Json :=
  if raw.trimAscii.isEmpty then
    pure (LeanAgent.Json.obj [])
  else
    LeanAgent.Json.parseObjectString raw

def parseToolCall (json : Lean.Json) : Except String ToolCall := do
  let id ← (← json.getObjVal? "id").getStr?
  let fn ← json.getObjVal? "function"
  let name ← (← fn.getObjVal? "name").getStr?
  let rawArgs ← (← fn.getObjVal? "arguments").getStr?
  let arguments ← parseToolArguments rawArgs
  pure { id := id, name := name, arguments := arguments }

def parseToolCalls (message : Lean.Json) : Except String (Array ToolCall) := do
  match LeanAgent.Json.optVal? message "tool_calls" with
  | none => pure #[]
  | some Lean.Json.null => pure #[]
  | some value =>
      let rawCalls ← value.getArr?
      let mut calls := #[]
      for rawCall in rawCalls do
        calls := calls.push (← parseToolCall rawCall)
      pure calls

def parseChatCompletion (raw : String) : Except String ProviderResponse := do
  let json ← Lean.Json.parse raw
  if let some err := LeanAgent.Json.optVal? json "error" then
    let message :=
      match LeanAgent.Json.optVal? err "message" with
      | some (Lean.Json.str text) => text
      | _ => err.compress
    throw message
  let choices ← (← json.getObjVal? "choices").getArr?
  let choice ←
    match choices[0]? with
    | some choice => pure choice
    | none => throw "OpenAI response contained no choices"
  let message ← choice.getObjVal? "message"
  let finishReason :=
    match LeanAgent.Json.optVal? choice "finish_reason" with
    | some (Lean.Json.str value) => some value
    | _ => none
  let toolCalls ← parseToolCalls message
  pure
    { content := parseMaybeContent message
      toolCalls := toolCalls
      finishReason := finishReason
    }

def provider (config : OpenAICompatibleConfig) : ModelProvider :=
  { complete := fun request => do
      let payload := requestToJson request
      let raw ← runHttpJson config payload
      match parseChatCompletion raw with
      | .ok response => pure response
      | .error err => throw (IO.userError s!"failed to parse provider response: {err}\n{raw}")
  }

end LeanAgent.OpenAI
