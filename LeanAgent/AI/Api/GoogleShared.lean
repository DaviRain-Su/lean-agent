import LeanAgent.AI.Api.TransformMessages
import LeanAgent.AI.Types
import LeanAgent.AI.Util.SanitizeUnicode
import LeanAgent.Json

namespace LeanAgent.AI.Api.GoogleShared

open LeanAgent

def apiGenerativeAI : String := "google-generative-ai"
def apiVertex : String := "google-vertex"

def isThinkingPart (part : Lean.Json) : Bool :=
  match LeanAgent.Json.optVal? part "thought" with
  | some (Lean.Json.bool true) => true
  | _ => false

def retainThoughtSignature (existing incoming : Option String) : Option String :=
  match incoming with
  | some value => if value.isEmpty then existing else some value
  | none => existing

def isBase64Char (char : Char) : Bool :=
  let code := Char.toNat char
  (Char.toNat 'a' <= code && code <= Char.toNat 'z') ||
    (Char.toNat 'A' <= code && code <= Char.toNat 'Z') ||
    (Char.toNat '0' <= code && code <= Char.toNat '9') ||
    char == '+' ||
    char == '/' ||
    char == '='

def isValidThoughtSignature (signature : String) : Bool :=
  !signature.isEmpty &&
    signature.length % 4 == 0 &&
    signature.toList.all isBase64Char

def resolveThoughtSignature
    (isSameProviderAndModel : Bool)
    (signature : Option String) : Option String :=
  match signature with
  | some value =>
      if isSameProviderAndModel && isValidThoughtSignature value then some value else none
  | none => none

def requiresToolCallId (modelId : String) : Bool :=
  modelId.startsWith "claude-" || modelId.startsWith "gpt-oss-"

def getGeminiMajorVersion? (modelId : String) : Option Nat :=
  let marker := "gemini-"
  if !modelId.toLower.startsWith marker then
    none
  else
    let rest := modelId.toLower.drop marker.length |>.toString
    let digits := rest.toList.takeWhile (fun char => char.isDigit)
    if digits.isEmpty then none else String.ofList digits |>.toNat?

def supportsMultimodalFunctionResponse (modelId : String) : Bool :=
  match getGeminiMajorVersion? modelId with
  | some version => version >= 3
  | none => true

def targetModel
    (model : LeanAgent.AI.ModelRef)
    (input : Array String) : LeanAgent.AI.Api.TransformMessages.TargetModel :=
  { id := model.id
    provider := model.provider
    api := model.api
    input := input
  }

def normalizeToolCallId
    (id : String)
    (target : LeanAgent.AI.Api.TransformMessages.TargetModel)
    (_message : LeanAgent.AI.AssistantMessage) : String :=
  if requiresToolCallId target.id then
    LeanAgent.AI.Api.TransformMessages.sanitizeToolCallId id
  else
    id

def textPart (text : String) : Lean.Json :=
  LeanAgent.Json.obj [("text", LeanAgent.Json.str (LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates text))]

def imagePart (image : LeanAgent.AI.ImageContent) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("inlineData",
        LeanAgent.Json.obj
          [ ("mimeType", LeanAgent.Json.str image.mimeType)
          , ("data", LeanAgent.Json.str image.data)
          ])
    ]

def optionalStringField (json : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? json key with
  | some (Lean.Json.str value) => some value
  | _ => none

def optionalArrayField (json : Lean.Json) (key : String) : Option (Array Lean.Json) :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getArr? with
      | .ok arr => some arr
      | .error _ => none
  | none => none

def jsonRole? (content : Lean.Json) : Option String :=
  optionalStringField content "role"

def jsonParts? (content : Lean.Json) : Option (Array Lean.Json) :=
  optionalArrayField content "parts"

def hasFunctionResponse (part : Lean.Json) : Bool :=
  (LeanAgent.Json.optVal? part "functionResponse").isSome

def appendPartToLastFunctionResponseUser
    (contents : Array Lean.Json)
    (part : Lean.Json) : Option (Array Lean.Json) :=
  match contents.back? with
  | none => none
  | some last =>
      match jsonRole? last, jsonParts? last with
      | some "user", some parts =>
          if parts.any hasFunctionResponse then
            some
              (contents.pop.push
                (LeanAgent.Json.obj
                  [ ("role", LeanAgent.Json.str "user")
                  , ("parts", LeanAgent.Json.arr (parts.push part))
                  ]))
          else
            none
      | _, _ => none

def assistantContentParts
    (model : LeanAgent.AI.ModelRef)
    (message : LeanAgent.AI.AssistantMessage) : Array Lean.Json :=
  Id.run do
    let isSameProviderAndModel :=
      message.provider == model.provider && message.api == model.api && message.model == model.id
    let mut parts := #[]
    for block in message.content do
      match block with
      | .text content =>
          if !content.text.trimAscii.toString.isEmpty then
            let signature := resolveThoughtSignature isSameProviderAndModel content.textSignature
            let fields := [("text", LeanAgent.Json.str (LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates content.text))]
              ++ LeanAgent.AI.optStringField "thoughtSignature" signature
            parts := parts.push (LeanAgent.Json.obj fields)
      | .thinking content =>
          if content.redacted then
            pure ()
          else if !content.thinking.trimAscii.toString.isEmpty then
            if isSameProviderAndModel then
              let signature := resolveThoughtSignature isSameProviderAndModel content.thinkingSignature
              let fields :=
                [ ("thought", LeanAgent.Json.bool true)
                , ("text", LeanAgent.Json.str (LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates content.thinking))
                ] ++ LeanAgent.AI.optStringField "thoughtSignature" signature
              parts := parts.push (LeanAgent.Json.obj fields)
            else
              parts := parts.push (textPart content.thinking)
      | .toolCall call =>
          let signature := resolveThoughtSignature isSameProviderAndModel call.thoughtSignature
          let functionCallFields :=
            [ ("name", LeanAgent.Json.str call.name)
            , ("args", call.arguments)
            ] ++
            if requiresToolCallId model.id then [("id", LeanAgent.Json.str call.id)] else []
          let fields :=
            [("functionCall", LeanAgent.Json.obj functionCallFields)]
              ++ LeanAgent.AI.optStringField "thoughtSignature" signature
          parts := parts.push (LeanAgent.Json.obj fields)
      | .image _ => pure ()
    pure parts

def userContentParts (content : Array LeanAgent.AI.ContentBlock) : Array Lean.Json :=
  content.filterMap fun block =>
    match block with
    | .text text =>
        if text.text.trimAscii.toString.isEmpty then none else some (textPart text.text)
    | .thinking thinking =>
        if thinking.thinking.trimAscii.toString.isEmpty then none else some (textPart thinking.thinking)
    | .image image => some (imagePart image)
    | .toolCall call => some (textPart call.arguments.compress)

def toolResultText (content : Array LeanAgent.AI.ContentBlock) : String :=
  LeanAgent.AI.contentPlainText content

def toolResultImageParts (content : Array LeanAgent.AI.ContentBlock) : Array Lean.Json :=
  content.filterMap fun block =>
    match block with
    | .image image => some (imagePart image)
    | _ => none

def toolResultPart (model : LeanAgent.AI.ModelRef) (message : LeanAgent.AI.ToolResultMessage) :
    Lean.Json :=
  let text := toolResultText message.content
  let images := toolResultImageParts message.content
  let responseText :=
    if !text.isEmpty then text else if images.isEmpty then "" else "(see attached image)"
  let responseKey := if message.isError then "error" else "output"
  let response := LeanAgent.Json.obj [(responseKey, LeanAgent.Json.str (LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates responseText))]
  let functionResponseFields :=
    [ ("name", LeanAgent.Json.str message.toolName)
    , ("response", response)
    ] ++
    (if !images.isEmpty && supportsMultimodalFunctionResponse model.id then
      [("parts", LeanAgent.Json.arr images)]
    else
      []) ++
    if requiresToolCallId model.id then [("id", LeanAgent.Json.str message.toolCallId)] else []
  LeanAgent.Json.obj [("functionResponse", LeanAgent.Json.obj functionResponseFields)]

def pushToolResultContent
    (model : LeanAgent.AI.ModelRef)
    (contents : Array Lean.Json)
    (message : LeanAgent.AI.ToolResultMessage) : Array Lean.Json :=
  let part := toolResultPart model message
  let contents :=
    match appendPartToLastFunctionResponseUser contents part with
    | some merged => merged
    | none =>
        contents.push
          (LeanAgent.Json.obj
            [ ("role", LeanAgent.Json.str "user")
            , ("parts", LeanAgent.Json.arr #[part])
            ])
  let imageParts := toolResultImageParts message.content
  if !imageParts.isEmpty && !supportsMultimodalFunctionResponse model.id then
    contents.push
      (LeanAgent.Json.obj
        [ ("role", LeanAgent.Json.str "user")
        , ("parts", LeanAgent.Json.arr (#[textPart "Tool result image:"] ++ imageParts))
        ])
  else
    contents

def convertMessagesAux
    (model : LeanAgent.AI.ModelRef)
    (messages : Array LeanAgent.AI.Message) : Array Lean.Json :=
  Id.run do
    let mut contents := #[]
    for msg in messages do
      match msg with
      | .user message =>
          let parts := userContentParts message.content
          if !parts.isEmpty then
            contents := contents.push
              (LeanAgent.Json.obj
                [ ("role", LeanAgent.Json.str "user")
                , ("parts", LeanAgent.Json.arr parts)
                ])
      | .assistant message =>
          let parts := assistantContentParts model message
          if !parts.isEmpty then
            contents := contents.push
              (LeanAgent.Json.obj
                [ ("role", LeanAgent.Json.str "model")
                , ("parts", LeanAgent.Json.arr parts)
                ])
      | .toolResult message =>
          contents := pushToolResultContent model contents message
    pure contents

def convertMessages
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (context : LeanAgent.AI.Context) : Array Lean.Json :=
  let transformed :=
    LeanAgent.AI.Api.TransformMessages.transformMessages
      context.messages
      (targetModel model input)
      { normalizeToolCallId? := some normalizeToolCallId }
  convertMessagesAux model transformed

def schemaMetaDeclarations : List String :=
  [ "$schema"
  , "$id"
  , "$anchor"
  , "$dynamicAnchor"
  , "$vocabulary"
  , "$comment"
  , "$defs"
  , "definitions"
  ]

partial def sanitizeForOpenApi (schema : Lean.Json) : Lean.Json :=
  match schema with
  | Lean.Json.obj fields =>
      let filtered := fields.toList.filter fun (name, _) =>
        !schemaMetaDeclarations.contains name
      let mapped := filtered.map fun (name, value) =>
        (name, sanitizeForOpenApi value)
      LeanAgent.Json.obj mapped
  | Lean.Json.arr items =>
      LeanAgent.Json.arr (items.map sanitizeForOpenApi)
  | _ => schema

def convertTools
    (tools : Array LeanAgent.AI.Tool)
    (useParameters : Bool := false) : Option (Array Lean.Json) :=
  if tools.isEmpty then
    none
  else
    some
      #[ LeanAgent.Json.obj
          [ ("functionDeclarations",
              LeanAgent.Json.arr
                (tools.map fun tool =>
                  let parameterField :=
                    if useParameters then
                      ("parameters", sanitizeForOpenApi tool.parameters)
                    else
                      ("parametersJsonSchema", tool.parameters)
                  LeanAgent.Json.obj
                    [ ("name", LeanAgent.Json.str tool.name)
                    , ("description", LeanAgent.Json.str tool.description)
                    , parameterField
                    ]))
          ]
       ]

def mapToolChoice (choice : String) : String :=
  match choice with
  | "none" => "NONE"
  | "any" => "ANY"
  | _ => "AUTO"

def mapStopReasonString (reason : String) : LeanAgent.AI.StopReason :=
  match reason with
  | "STOP" => .stop
  | "MAX_TOKENS" => .length
  | _ => .error

end LeanAgent.AI.Api.GoogleShared
