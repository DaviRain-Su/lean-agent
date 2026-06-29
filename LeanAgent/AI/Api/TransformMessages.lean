import LeanAgent.AI.Types

namespace LeanAgent.AI.Api.TransformMessages

def nonVisionUserImagePlaceholder : String :=
  "(image omitted: model does not support images)"

def nonVisionToolImagePlaceholder : String :=
  "(tool image omitted: model does not support images)"

structure TargetModel where
  id : String
  provider : ProviderId
  api : Api
  input : Array String := #["text"]
deriving BEq

abbrev NormalizeToolCallId :=
  String → TargetModel → AssistantMessage → String

structure TransformOptions where
  normalizeToolCallId? : Option NormalizeToolCallId := none
  syntheticTimestamp : Nat := 0

def supportsImages (model : TargetModel) : Bool :=
  model.input.contains "image"

def sameModel (target : TargetModel) (message : AssistantMessage) : Bool :=
  message.provider == target.provider &&
    message.api == target.api &&
    message.model == target.id

def isAsciiAlphaNumOrToolIdChar (char : Char) : Bool :=
  let code := Char.toNat char
  (Char.toNat 'a' <= code && code <= Char.toNat 'z') ||
    (Char.toNat 'A' <= code && code <= Char.toNat 'Z') ||
    (Char.toNat '0' <= code && code <= Char.toNat '9') ||
    char == '_' ||
    char == '-'

/-- Normalize a tool-call id into the conservative shape accepted by Anthropic. -/
def sanitizeToolCallId (id : String) (maxLength : Nat := 64) : String :=
  id.toList
    |>.map (fun char => if isAsciiAlphaNumOrToolIdChar char then char else '_')
    |>.take maxLength
    |> String.ofList

def replaceImagesWithPlaceholder (content : Array ContentBlock) (placeholder : String) :
    Array ContentBlock :=
  Id.run do
    let mut result := #[]
    let mut previousWasPlaceholder := false
    for block in content do
      match block with
      | .image _ =>
          if !previousWasPlaceholder then
            result := result.push (.text { text := placeholder })
          previousWasPlaceholder := true
      | .text text =>
          result := result.push block
          previousWasPlaceholder := text.text == placeholder
      | _ =>
          result := result.push block
          previousWasPlaceholder := false
    pure result

def downgradeUnsupportedImages (target : TargetModel) (messages : Array Message) : Array Message :=
  if supportsImages target then
    messages
  else
    messages.map fun message =>
      match message with
      | .user user =>
          .user { user with content := replaceImagesWithPlaceholder user.content nonVisionUserImagePlaceholder }
      | .toolResult result =>
          .toolResult { result with content := replaceImagesWithPlaceholder result.content nonVisionToolImagePlaceholder }
      | .assistant _ => message

abbrev ToolCallIdMap := Array (String × String)

def lookupToolCallId? (mapping : ToolCallIdMap) (id : String) : Option String :=
  mapping.findSome? fun (original, normalized) =>
    if original == id then some normalized else none

def addToolCallIdMapping (mapping : ToolCallIdMap) (original normalized : String) : ToolCallIdMap :=
  if original == normalized then
    mapping
  else
    Id.run do
      let mut updated := #[]
      let mut replaced := false
      for pair in mapping do
        if pair.fst == original then
          updated := updated.push (original, normalized)
          replaced := true
        else
          updated := updated.push pair
      if replaced then
        pure updated
      else
        pure (updated.push (original, normalized))

def isBlank (value : String) : Bool :=
  value.trimAscii.toString.isEmpty

def transformThinkingBlock (isSameModel : Bool) (content : ThinkingContent) : Array ContentBlock :=
  if content.redacted then
    if isSameModel then #[.thinking content] else #[]
  else if isSameModel && content.thinkingSignature.isSome then
    #[.thinking content]
  else if isBlank content.thinking then
    #[]
  else if isSameModel then
    #[.thinking content]
  else
    #[.text { text := content.thinking }]

def transformAssistantContent
    (target : TargetModel)
    (options : TransformOptions)
    (message : AssistantMessage)
    (mapping : ToolCallIdMap) :
    Array ContentBlock × ToolCallIdMap :=
  Id.run do
    let isSame := sameModel target message
    let mut content := #[]
    let mut mapping := mapping
    for block in message.content do
      match block with
      | .thinking thinking =>
          content := content ++ transformThinkingBlock isSame thinking
      | .text text =>
          if isSame then
            content := content.push block
          else
            content := content.push (.text { text := text.text })
      | .toolCall call =>
          let withoutForeignSignature :=
            if isSame then call else { call with thoughtSignature := none }
          let normalizedCall ←
            match options.normalizeToolCallId? with
            | none => pure withoutForeignSignature
            | some normalize =>
                if isSame then
                  pure withoutForeignSignature
                else
                  let normalizedId := normalize call.id target message
                  mapping := addToolCallIdMapping mapping call.id normalizedId
                  pure { withoutForeignSignature with id := normalizedId }
          content := content.push (.toolCall normalizedCall)
      | .image _ =>
          content := content.push block
    pure (content, mapping)

def firstPassTransform
    (target : TargetModel)
    (options : TransformOptions)
    (messages : Array Message) : Array Message :=
  Id.run do
    let mut transformed := #[]
    let mut mapping : ToolCallIdMap := #[]
    for message in downgradeUnsupportedImages target messages do
      match message with
      | .toolResult result =>
          match lookupToolCallId? mapping result.toolCallId with
          | some normalized =>
              transformed := transformed.push (.toolResult { result with toolCallId := normalized })
          | none =>
              transformed := transformed.push message
      | .assistant assistant =>
          let (content, nextMapping) := transformAssistantContent target options assistant mapping
          mapping := nextMapping
          transformed := transformed.push (.assistant { assistant with content := content })
      | .user _ =>
          transformed := transformed.push message
    pure transformed

def syntheticToolResult (timestamp : Nat) (call : ToolCall) : Message :=
  .toolResult
    { toolCallId := call.id
      toolName := call.name
      content := #[.text { text := "No result provided" }]
      isError := true
      timestamp := timestamp
    }

def insertSyntheticToolResults
    (timestamp : Nat)
    (result : Array Message)
    (pendingToolCalls : Array ToolCall)
    (existingToolResultIds : Array String) : Array Message :=
  pendingToolCalls.foldl
    (fun acc call =>
      if existingToolResultIds.contains call.id then
        acc
      else
        acc.push (syntheticToolResult timestamp call))
    result

def completeToolFlows (options : TransformOptions) (messages : Array Message) : Array Message :=
  Id.run do
    let mut result := #[]
    let mut pendingToolCalls : Array ToolCall := #[]
    let mut existingToolResultIds : Array String := #[]
    for message in messages do
      match message with
      | .assistant assistant =>
          result := insertSyntheticToolResults options.syntheticTimestamp result pendingToolCalls existingToolResultIds
          pendingToolCalls := #[]
          existingToolResultIds := #[]
          if assistant.stopReason == .error || assistant.stopReason == .aborted then
            continue
          let toolCalls := contentToolCalls assistant.content
          if !toolCalls.isEmpty then
            pendingToolCalls := toolCalls
          result := result.push message
      | .toolResult toolResult =>
          existingToolResultIds := existingToolResultIds.push toolResult.toolCallId
          result := result.push message
      | .user _ =>
          result := insertSyntheticToolResults options.syntheticTimestamp result pendingToolCalls existingToolResultIds
          pendingToolCalls := #[]
          existingToolResultIds := #[]
          result := result.push message
    result := insertSyntheticToolResults options.syntheticTimestamp result pendingToolCalls existingToolResultIds
    pure result

def transformMessages
    (messages : Array Message)
    (target : TargetModel)
    (options : TransformOptions := {}) : Array Message :=
  messages
    |> firstPassTransform target options
    |> completeToolFlows options

end LeanAgent.AI.Api.TransformMessages
