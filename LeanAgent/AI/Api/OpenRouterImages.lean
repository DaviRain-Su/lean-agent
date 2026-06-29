import Lean
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.Retry
import LeanAgent.AI.Util.SanitizeUnicode
import LeanAgent.Http
import LeanAgent.Json

namespace LeanAgent.AI.Api.OpenRouterImages

open LeanAgent

def api : String := "openrouter-images"
def providerId : String := "openrouter"
def apiKeyEnv : String := "OPENROUTER_API_KEY"
def baseUrl : String := "https://openrouter.ai/api/v1"

structure OpenRouterImagesConfig where
  apiKey : String
  baseUrl : String := OpenRouterImages.baseUrl
  headers : Array (String × String) := #[]
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

def inputContentToJson : LeanAgent.AI.ContentBlock → Option Lean.Json
  | .text content =>
      some
        (LeanAgent.Json.obj
          [ ("type", LeanAgent.Json.str "text")
          , ("text", LeanAgent.Json.str (LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates content.text))
          ])
  | .image content =>
      some
        (LeanAgent.Json.obj
          [ ("type", LeanAgent.Json.str "image_url")
          , ("image_url",
              LeanAgent.Json.obj
                [("url", LeanAgent.Json.str s!"data:{content.mimeType};base64,{content.data}")])
          ])
  | _ => none

def modalities (model : LeanAgent.AI.ImagesModel) : Array Lean.Json :=
  if model.output.contains "text" then
    #[LeanAgent.Json.str "image", LeanAgent.Json.str "text"]
  else
    #[LeanAgent.Json.str "image"]

def requestToJson (model : LeanAgent.AI.ImagesModel) (context : LeanAgent.AI.ImagesContext) :
    Lean.Json :=
  LeanAgent.Json.obj
    [ ("model", LeanAgent.Json.str model.id)
    , ("messages",
        LeanAgent.Json.arr
          #[ LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "user")
              , ("content", LeanAgent.Json.arr (context.input.filterMap inputContentToJson))
              ]
           ])
    , ("stream", LeanAgent.Json.bool false)
    , ("modalities", LeanAgent.Json.arr (modalities model))
    ]

def applyPayloadHook
    (options : LeanAgent.AI.ImagesOptions)
    (model : LeanAgent.AI.ImagesModel)
    (payload : Lean.Json) : IO Lean.Json := do
  match options.onPayload with
  | none => pure payload
  | some hook =>
      match ← hook payload model.toModelRef with
      | some nextPayload => pure nextPayload
      | none => pure payload

def callResponseHook
    (options : LeanAgent.AI.ImagesOptions)
    (model : LeanAgent.AI.ImagesModel)
    (response : LeanAgent.Http.JsonPostResponse) : IO Unit := do
  match options.onResponse with
  | none => pure ()
  | some hook =>
      hook { status := response.status, headers := response.headers } model.toModelRef

def runHttpJson
    (config : OpenRouterImagesConfig)
    (model : LeanAgent.AI.ImagesModel)
    (payload : Lean.Json)
    (options : LeanAgent.AI.ImagesOptions := {}) : IO String := do
  let response ← LeanAgent.Http.postJsonResponse
    { url := chatCompletionsUrl config.baseUrl
      apiKey := config.apiKey
      headers :=
        LeanAgent.AI.Util.Headers.merge
          config.headers
          (LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers)
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
    }
    payload.compress
  callResponseHook options model response
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError (LeanAgent.AI.Util.Diagnostics.providerHttpErrorMessage response.status response.body))
  pure response.body

def natFieldD (json : Lean.Json) (key : String) (default : Nat := 0) : Nat :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getNat? with
      | .ok number => number
      | .error _ => default
  | none => default

def optionalStringField (json : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? json key with
  | some (Lean.Json.str value) => some value
  | _ => none

def optionalObjectField (json : Lean.Json) (key : String) : Option Lean.Json :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getObj? with
      | .ok _ => some value
      | .error _ => none
  | none => none

def optionalArrayField (json : Lean.Json) (key : String) : Option (Array Lean.Json) :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getArr? with
      | .ok arr => some arr
      | .error _ => none
  | none => none

def perMillionCost (rate : Float) (tokens : Nat) : Float :=
  (rate / 1000000.0) * Float.ofNat tokens

def parseUsage (rawUsage : Lean.Json) (model : LeanAgent.AI.ImagesModel) : LeanAgent.AI.Usage :=
  let promptTokens := natFieldD rawUsage "prompt_tokens"
  let promptDetails := optionalObjectField rawUsage "prompt_tokens_details"
  let reportedCachedTokens :=
    match promptDetails with
    | some details => natFieldD details "cached_tokens"
    | none => 0
  let cacheWriteTokens :=
    match promptDetails with
    | some details => natFieldD details "cache_write_tokens"
    | none => 0
  let cacheReadTokens :=
    if cacheWriteTokens > 0 then
      reportedCachedTokens - cacheWriteTokens
    else
      reportedCachedTokens
  let inputTokens := promptTokens - cacheReadTokens - cacheWriteTokens
  let outputTokens := natFieldD rawUsage "completion_tokens"
  let inputCost := perMillionCost model.cost.input inputTokens
  let outputCost := perMillionCost model.cost.output outputTokens
  let cacheReadCost := perMillionCost model.cost.cacheRead cacheReadTokens
  let cacheWriteCost := perMillionCost model.cost.cacheWrite cacheWriteTokens
  { input := inputTokens
    output := outputTokens
    cacheRead := cacheReadTokens
    cacheWrite := cacheWriteTokens
    totalTokens := inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    cost :=
      { input := inputCost
        output := outputCost
        cacheRead := cacheReadCost
        cacheWrite := cacheWriteCost
        total := inputCost + outputCost + cacheReadCost + cacheWriteCost
      }
  }

def parseUsage? (json : Lean.Json) (model : LeanAgent.AI.ImagesModel) : Option LeanAgent.AI.Usage :=
  match LeanAgent.Json.optVal? json "usage" with
  | some usage => some (parseUsage usage model)
  | none => none

def splitOnce (value separator : String) : String × Option String :=
  match value.splitOn separator with
  | [] => (value, none)
  | head :: [] => (head, none)
  | head :: rest => (head, some (String.intercalate separator rest))

def imageUrlString? (image : Lean.Json) : Option String :=
  match LeanAgent.Json.optVal? image "image_url" with
  | some (Lean.Json.str value) => some value
  | some obj =>
      match obj.getObj? with
      | .ok _ => optionalStringField obj "url"
      | .error _ => none
  | none => none

def parseDataImage? (imageUrl : String) : Option LeanAgent.AI.ContentBlock :=
  if !imageUrl.startsWith "data:" then
    none
  else
    let withoutPrefix := (imageUrl.drop 5).toString
    let (mimeType, rest?) := splitOnce withoutPrefix ";base64,"
    match rest? with
    | some data =>
        if mimeType.isEmpty || data.isEmpty then
          none
        else
          some (LeanAgent.AI.image data mimeType)
    | none => none

def parseChoiceOutput (choice : Lean.Json) : Array LeanAgent.AI.ContentBlock :=
  let message? := optionalObjectField choice "message"
  match message? with
  | none => #[]
  | some message =>
      let contentBlocks :=
        match optionalStringField message "content" with
        | some content =>
            if content.isEmpty then #[] else #[LeanAgent.AI.text content]
        | none => #[]
      match optionalArrayField message "images" with
      | some images =>
          contentBlocks ++ images.filterMap (fun image => (imageUrlString? image).bind parseDataImage?)
      | none => contentBlocks

def firstChoice? (json : Lean.Json) : Option Lean.Json :=
  match optionalArrayField json "choices" with
  | some choices => choices[0]?
  | none => none

def parseResponse
    (model : LeanAgent.AI.ImagesModel)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantImages := do
  let json ← Lean.Json.parse raw
  let choiceOutput :=
    match firstChoice? json with
    | some choice => parseChoiceOutput choice
    | none => #[]
  pure
    { api := model.api
      provider := model.provider
      model := model.id
      output := choiceOutput
      responseId := optionalStringField json "id"
      usage := parseUsage? json model
      stopReason := .stop
      timestamp := timestamp
    }

def errorImages
    (model : LeanAgent.AI.ImagesModel)
    (timestamp : Nat)
    (message : String)
    (stopReason : LeanAgent.AI.ImagesStopReason := .error) : LeanAgent.AI.AssistantImages :=
  { api := model.api
    provider := model.provider
    model := model.id
    output := #[]
    stopReason := stopReason
    errorMessage := some message
    timestamp := timestamp
  }

def generateImagesWithConfig
    (config : OpenRouterImagesConfig)
    (model : LeanAgent.AI.ImagesModel)
    (context : LeanAgent.AI.ImagesContext)
    (options : LeanAgent.AI.ImagesOptions := {}) : IO LeanAgent.AI.AssistantImages := do
  let timestamp ← IO.monoMsNow
  try
    LeanAgent.AI.Util.Abort.throwIfAborted options.signal
    if config.apiKey.trimAscii.isEmpty then
      throw (IO.userError s!"No API key for provider: {model.provider}")
    let payload ← applyPayloadHook options model (requestToJson model context)
    let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
    let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy (runHttpJson config model payload options) options.signal
    match parseResponse model timestamp raw with
    | .ok images => pure images
    | .error err => throw (IO.userError s!"failed to parse provider response: {err}\n{raw}")
  catch err =>
    if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
      pure (errorImages model timestamp LeanAgent.AI.Util.Abort.requestAbortedMessage .aborted)
    else
      pure (errorImages model timestamp err.toString)

def generateImages
    (model : LeanAgent.AI.ImagesModel)
    (context : LeanAgent.AI.ImagesContext)
    (options : LeanAgent.AI.ImagesOptions := {}) : IO LeanAgent.AI.AssistantImages := do
  generateImagesWithConfig
    { apiKey := options.apiKey.getD ""
      baseUrl := model.baseUrl
      headers := model.headers
      timeoutSeconds := UInt32.ofNat (options.timeoutMs.getD 120000 / 1000)
    }
    model
    context
    options

end LeanAgent.AI.Api.OpenRouterImages
