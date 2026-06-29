import LeanAgent.AI.Api.TransformMessages
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Hash
import LeanAgent.AI.Util.SanitizeUnicode
import LeanAgent.Json

namespace LeanAgent.AI.Api.OpenAIResponsesShared

structure ResponsesModel extends TransformMessages.TargetModel where
  reasoning : Bool := false
  supportsDeveloperRole : Bool := true
deriving BEq

structure ConvertResponsesMessagesOptions where
  includeSystemPrompt : Bool := true
  syntheticTimestamp : Nat := 0
deriving BEq

structure ParsedTextSignature where
  id : String
  phase : Option String := none
deriving BEq

def encodeTextSignatureV1 (id : String) (phase : Option String := none) : String :=
  LeanAgent.Json.obj
    ([ ("v", LeanAgent.Json.nat 1)
     , ("id", LeanAgent.Json.str id)
     ] ++
      match phase with
      | some value => [("phase", LeanAgent.Json.str value)]
      | none => [])
    |>.compress

def allowedOpenAIResponsesToolCallProviders : Array String :=
  #["openai", "openai-codex", "opencode"]

def toTransformTarget (model : ResponsesModel) : TransformMessages.TargetModel :=
  { id := model.id
    provider := model.provider
    api := model.api
    input := model.input
  }

def sanitizeText (value : String) : String :=
  LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates value

def isAsciiAlphaNumOrToolIdChar (char : Char) : Bool :=
  TransformMessages.isAsciiAlphaNumOrToolIdChar char

def takeChars (value : String) (count : Nat) : String :=
  String.ofList (value.toList.take count)

def trimTrailingUnderscores (value : String) : String :=
  String.ofList ((value.toList.reverse.dropWhile (fun char => char == '_')).reverse)

def normalizeIdPart (part : String) : String :=
  part.toList
    |>.map (fun char => if isAsciiAlphaNumOrToolIdChar char then char else '_')
    |> String.ofList
    |> (fun sanitized => takeChars sanitized 64)
    |> trimTrailingUnderscores

def buildForeignResponsesItemId (itemId : String) : String :=
  takeChars ("fc_" ++ LeanAgent.AI.Util.Hash.shortHash itemId) 64

def splitToolCallId (id : String) : String × Option String :=
  match id.splitOn "|" with
  | [] => ("", none)
  | callId :: [] => (callId, none)
  | callId :: itemId :: _ => (callId, some itemId)

def normalizeToolCallId
    (allowedToolCallProviders : Array String)
    (model : ResponsesModel)
    (id : String)
    (_target : TransformMessages.TargetModel)
    (source : AssistantMessage) : String :=
  if !allowedToolCallProviders.contains model.provider then
    normalizeIdPart id
  else if !id.contains "|" then
    normalizeIdPart id
  else
    let (callId, itemId?) := splitToolCallId id
    let normalizedCallId := normalizeIdPart callId
    let isForeignToolCall := source.provider != model.provider || source.api != model.api
    let rawItemId := itemId?.getD ""
    let normalizedItemIdBase :=
      if isForeignToolCall then
        buildForeignResponsesItemId rawItemId
      else
        normalizeIdPart rawItemId
    let normalizedItemId :=
      if normalizedItemIdBase.startsWith "fc_" then
        normalizedItemIdBase
      else
        normalizeIdPart ("fc_" ++ normalizedItemIdBase)
    normalizedCallId ++ "|" ++ normalizedItemId

def optStringField (key : String) : Option String → List (String × Lean.Json)
  | some value => [(key, LeanAgent.Json.str value)]
  | none => []

def jsonString? : Lean.Json → Option String
  | .str value => some value
  | _ => none

def parseTextSignature? (signature? : Option String) : Option ParsedTextSignature :=
  match signature? with
  | none => none
  | some signature =>
      if signature.startsWith "{" then
        match Lean.Json.parse signature with
        | .ok parsed =>
            let isV1 :=
              match LeanAgent.Json.optVal? parsed "v" with
              | some value => value.compress == "1"
              | none => false
            match isV1, (LeanAgent.Json.optVal? parsed "id").bind jsonString? with
            | true, some id =>
                let phase :=
                  match (LeanAgent.Json.optVal? parsed "phase").bind jsonString? with
                  | some "commentary" => some "commentary"
                  | some "final_answer" => some "final_answer"
                  | _ => none
                some { id := id, phase := phase }
            | _, _ => some { id := signature }
        | .error _ => some { id := signature }
      else
        some { id := signature }

def textMessageId (msgIndex textBlockIndex : Nat) (signature? : Option String) : String × Option String :=
  let parsed := parseTextSignature? signature?
  let fallback :=
    if textBlockIndex == 0 then
      s!"msg_pi_{msgIndex}"
    else
      s!"msg_pi_{msgIndex}_{textBlockIndex}"
  let id := parsed.map (fun value => value.id) |>.getD fallback
  let id :=
    if id.length > 64 then
      "msg_" ++ LeanAgent.AI.Util.Hash.shortHash id
    else
      id
  let phase := parsed.bind (fun value => value.phase)
  (id, phase)

def inputTextJson (text : String) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "input_text")
    , ("text", LeanAgent.Json.str (sanitizeText text))
    ]

def inputImageJson (image : ImageContent) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "input_image")
    , ("detail", LeanAgent.Json.str "auto")
    , ("image_url", LeanAgent.Json.str s!"data:{image.mimeType};base64,{image.data}")
    ]

def userContentJson (content : Array ContentBlock) : Array Lean.Json :=
  content.filterMap fun block =>
    match block with
    | .text text => some (inputTextJson text.text)
    | .image image => some (inputImageJson image)
    | _ => none

def outputTextJson (text : String) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "output_text")
    , ("text", LeanAgent.Json.str (sanitizeText text))
    , ("annotations", LeanAgent.Json.arr #[])
    ]

def assistantTextItemJson
    (msgIndex textBlockIndex : Nat)
    (text : TextContent) : Lean.Json :=
  let (id, phase) := textMessageId msgIndex textBlockIndex text.textSignature
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str "message")
     , ("role", LeanAgent.Json.str "assistant")
     , ("content", LeanAgent.Json.arr #[outputTextJson text.text])
     , ("status", LeanAgent.Json.str "completed")
     , ("id", LeanAgent.Json.str id)
     ] ++ optStringField "phase" phase)

def assistantToolCallItemJson
    (model : ResponsesModel)
    (assistant : AssistantMessage)
    (call : ToolCall) : Lean.Json :=
  let (callId, itemId?) := splitToolCallId call.id
  let isDifferentModel :=
    assistant.model != model.id &&
      assistant.provider == model.provider &&
      assistant.api == model.api
  let itemId? :=
    match itemId? with
    | some itemId =>
        if isDifferentModel && itemId.startsWith "fc_" then none else some itemId
    | none => none
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str "function_call")
     , ("call_id", LeanAgent.Json.str callId)
     , ("name", LeanAgent.Json.str call.name)
     , ("arguments", LeanAgent.Json.str call.arguments.compress)
     ] ++ optStringField "id" itemId?)

def assistantMessageItems (model : ResponsesModel) (msgIndex : Nat) (assistant : AssistantMessage) :
    Array Lean.Json :=
  Id.run do
    let mut output := #[]
    let mut textBlockIndex := 0
    for block in assistant.content do
      match block with
      | .thinking thinking =>
          match thinking.thinkingSignature with
          | some signature =>
              match Lean.Json.parse signature with
              | .ok reasoningItem => output := output.push reasoningItem
              | .error _ => pure ()
          | none => pure ()
      | .text text =>
          output := output.push (assistantTextItemJson msgIndex textBlockIndex text)
          textBlockIndex := textBlockIndex + 1
      | .toolCall call =>
          output := output.push (assistantToolCallItemJson model assistant call)
      | .image _ => pure ()
    pure output

def textBlocksPlainText (content : Array ContentBlock) : String :=
  String.intercalate "\n"
    (content.toList.filterMap fun block =>
      match block with
      | .text text => some text.text
      | _ => none)

def hasImages (content : Array ContentBlock) : Bool :=
  content.any fun
    | .image _ => true
    | _ => false

def toolResultOutputJson (model : ResponsesModel) (message : ToolResultMessage) : Lean.Json :=
  let textResult := textBlocksPlainText message.content
  let hasText := !textResult.isEmpty
  if hasImages message.content && model.input.contains "image" then
    Id.run do
      let mut parts := #[]
      if hasText then
        parts := parts.push (inputTextJson textResult)
      for block in message.content do
        match block with
        | .image image => parts := parts.push (inputImageJson image)
        | _ => pure ()
      pure (LeanAgent.Json.arr parts)
  else
    LeanAgent.Json.str (sanitizeText (if hasText then textResult else "(see attached image)"))

def toolResultItemJson (model : ResponsesModel) (message : ToolResultMessage) : Lean.Json :=
  let (callId, _) := splitToolCallId message.toolCallId
  LeanAgent.Json.obj
    [ ("type", LeanAgent.Json.str "function_call_output")
    , ("call_id", LeanAgent.Json.str callId)
    , ("output", toolResultOutputJson model message)
    ]

def systemMessageJson (model : ResponsesModel) (systemPrompt : String) : Lean.Json :=
  let role :=
    if model.reasoning && model.supportsDeveloperRole then
      "developer"
    else
      "system"
  LeanAgent.Json.obj
    [ ("role", LeanAgent.Json.str role)
    , ("content", LeanAgent.Json.str (sanitizeText systemPrompt))
    ]

def convertResponsesMessages
    (model : ResponsesModel)
    (context : Context)
    (allowedToolCallProviders : Array String := allowedOpenAIResponsesToolCallProviders)
    (options : ConvertResponsesMessagesOptions := {}) : Array Lean.Json :=
  Id.run do
    let transformTarget := toTransformTarget model
    let transformedMessages :=
      TransformMessages.transformMessages context.messages transformTarget
        { normalizeToolCallId? := some (normalizeToolCallId allowedToolCallProviders model)
          syntheticTimestamp := options.syntheticTimestamp
        }
    let mut messages := #[]
    if options.includeSystemPrompt then
      match context.systemPrompt with
      | some systemPrompt =>
          messages := messages.push (systemMessageJson model systemPrompt)
      | none => pure ()
    let mut msgIndex := 0
    for message in transformedMessages do
      match message with
      | .user user =>
          let content := userContentJson user.content
          if !content.isEmpty then
            messages := messages.push
              (LeanAgent.Json.obj
                [ ("role", LeanAgent.Json.str "user")
                , ("content", LeanAgent.Json.arr content)
                ])
            msgIndex := msgIndex + 1
      | .assistant assistant =>
          let output := assistantMessageItems model msgIndex assistant
          if !output.isEmpty then
            messages := messages ++ output
            msgIndex := msgIndex + 1
      | .toolResult toolResult =>
          messages := messages.push (toolResultItemJson model toolResult)
          msgIndex := msgIndex + 1
    pure messages

def convertResponsesTool (tool : Tool) (strict : Option Bool := some false) : Lean.Json :=
  LeanAgent.Json.obj
    ([ ("type", LeanAgent.Json.str "function")
     , ("name", LeanAgent.Json.str tool.name)
     , ("description", LeanAgent.Json.str tool.description)
     , ("parameters", tool.parameters)
     ] ++
      match strict with
      | some value => [("strict", LeanAgent.Json.bool value)]
      | none => [])

def convertResponsesTools (tools : Array Tool) (strict : Option Bool := some false) : Array Lean.Json :=
  tools.map (fun tool => convertResponsesTool tool strict)

end LeanAgent.AI.Api.OpenAIResponsesShared
