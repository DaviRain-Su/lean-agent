import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Estimate
import LeanAgent.Json
import LeanAgent.Models

namespace LeanAgent.AI.Providers.Faux

def defaultApi : String := "faux"
def defaultProvider : String := "faux"
def defaultModelId : String := "faux-1"
def defaultModelName : String := "Faux Model"
def defaultBaseUrl : String := "http://localhost:0"

def defaultUsage : Usage := {}

structure FauxModelDefinition where
  id : String
  name : Option String := none
  reasoning : Bool := false
  input : Array String := #["text", "image"]
  cost : UsageCost := {}
  contextWindow : Nat := 128000
  maxTokens : Nat := 16384
deriving BEq

structure FauxOptions where
  api : Option String := none
  provider : Option String := none
  models : Array FauxModelDefinition := #[]
deriving BEq

structure FauxState where
  callCount : Nat := 0
deriving Repr, BEq

def fauxText (text : String) : ContentBlock :=
  .text { text := text }

def fauxThinking (thinking : String) : ContentBlock :=
  .thinking { thinking := thinking }

def fauxToolCall (name : String) (arguments : Lean.Json) (id : String := "tool:faux") : ContentBlock :=
  .toolCall { id := id, name := name, arguments := arguments }

def fauxAssistantMessage
    (content : Array ContentBlock)
    (stopReason : StopReason := .stop)
    (errorMessage : Option String := none)
    (responseId : Option String := none)
    (timestamp : Nat := 0) : AssistantMessage :=
  { content := content
    api := defaultApi
    provider := defaultProvider
    model := defaultModelId
    responseId := responseId
    usage := defaultUsage
    stopReason := stopReason
    errorMessage := errorMessage
    timestamp := timestamp
  }

def fauxTextMessage (text : String) : AssistantMessage :=
  fauxAssistantMessage #[fauxText text]

abbrev FauxResponseFactory :=
  Context → SimpleStreamOptions → FauxState → LeanAgent.Models.ModelInfo → IO AssistantMessage

inductive FauxResponseStep where
  | message (message : AssistantMessage)
  | factory (factory : FauxResponseFactory)

def estimateTokens (text : String) : Nat :=
  LeanAgent.AI.Util.Estimate.estimateTextTokens text

def imageText (content : ImageContent) : String :=
  s!"[image:{content.mimeType}:{content.data.length}]"

def blockToText : ContentBlock → String
  | .text content => content.text
  | .thinking content => content.thinking
  | .image content => imageText content
  | .toolCall call => call.name ++ ":" ++ call.arguments.compress

def contentToText (content : Array ContentBlock) : String :=
  String.intercalate "\n" (content.toList.map blockToText)

def toolToJson (tool : Tool) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("name", LeanAgent.Json.str tool.name)
    , ("description", LeanAgent.Json.str tool.description)
    , ("parameters", tool.parameters)
    ]

def messageToText : Message → String
  | .user message => "user:" ++ contentToText message.content
  | .assistant message => "assistant:" ++ contentToText message.content
  | .toolResult message => "toolResult:" ++ String.intercalate "\n" ([message.toolName] ++ message.content.toList.map blockToText)

def serializeContext (context : Context) : String :=
  let systemPart :=
    match context.systemPrompt with
    | some prompt => ["system:" ++ prompt]
    | none => []
  let messageParts := context.messages.toList.map messageToText
  let toolParts :=
    if context.tools.isEmpty then
      []
    else
      ["tools:" ++ (LeanAgent.Json.arr (context.tools.map toolToJson)).compress]
  String.intercalate "\n\n" (systemPart ++ messageParts ++ toolParts)

partial def commonPrefixLengthList : List Char → List Char → Nat
  | a :: restA, b :: restB =>
      if a == b then 1 + commonPrefixLengthList restA restB else 0
  | _, _ => 0

def commonPrefixLength (a b : String) : Nat :=
  commonPrefixLengthList a.toList b.toList

def takeChars (value : String) (count : Nat) : String :=
  String.ofList (value.toList.take count)

def dropChars (value : String) (count : Nat) : String :=
  String.ofList (value.toList.drop count)

def cacheEnabled (options : SimpleStreamOptions) : Bool :=
  match options.sessionId, options.cacheRetention with
  | some _, some .none => false
  | some _, _ => true
  | none, _ => false

def lookupPromptCache (cache : Array (String × String)) (sessionId : String) : Option String :=
  cache.findSome? fun (id, prompt) => if id == sessionId then some prompt else none

def writePromptCache (cache : Array (String × String)) (sessionId prompt : String) : Array (String × String) :=
  (cache.filter fun (id, _) => id != sessionId).push (sessionId, prompt)

def withUsageEstimate
    (message : AssistantMessage)
    (context : Context)
    (options : SimpleStreamOptions)
    (promptCacheRef : IO.Ref (Array (String × String))) : IO AssistantMessage := do
  let promptText := serializeContext context
  let promptTokens := estimateTokens promptText
  let outputTokens := estimateTokens (contentToText message.content)
  let mut input := promptTokens
  let mut cacheRead := 0
  let mut cacheWrite := 0
  if cacheEnabled options then
    match options.sessionId with
    | some sessionId =>
        let cache ← promptCacheRef.get
        match lookupPromptCache cache sessionId with
        | some previousPrompt =>
            let cachedChars := commonPrefixLength previousPrompt promptText
            cacheRead := estimateTokens (takeChars previousPrompt cachedChars)
            cacheWrite := estimateTokens (dropChars promptText cachedChars)
            input := promptTokens - cacheRead
        | none =>
            cacheWrite := promptTokens
        promptCacheRef.set (writePromptCache cache sessionId promptText)
    | none => pure ()
  pure
    { message with
      usage :=
        { input := input
          output := outputTokens
          cacheRead := cacheRead
          cacheWrite := cacheWrite
          totalTokens := input + outputTokens + cacheRead + cacheWrite
        }
    }

def rewriteMessage
    (message : AssistantMessage)
    (api provider modelId : String)
    (timestamp : Nat) : AssistantMessage :=
  { message with
    api := api
    provider := provider
    model := modelId
    timestamp := if message.timestamp == 0 then timestamp else message.timestamp
  }

def errorMessage (message api provider modelId : String) (timestamp : Nat) : AssistantMessage :=
  { content := #[]
    api := api
    provider := provider
    model := modelId
    usage := defaultUsage
    stopReason := .error
    errorMessage := some message
    timestamp := timestamp
  }

def errorStream (message : AssistantMessage) : AssistantMessageEventStream :=
  { events := #[.error .error message], finalResult := message }

def modelFromDefinition (api providerId : String) (definition : FauxModelDefinition) :
    LeanAgent.Models.ModelInfo :=
  { id := definition.id
    name := definition.name.getD definition.id
    provider := providerId
    api := api
    baseUrl := defaultBaseUrl
    cost := definition.cost
    contextWindow := definition.contextWindow
    maxTokens := definition.maxTokens
    reasoning := definition.reasoning
    input := definition.input
  }

def defaultModelDefinition : FauxModelDefinition :=
  { id := defaultModelId
    name := some defaultModelName
  }

def modelDefinitions (options : FauxOptions) : Array FauxModelDefinition :=
  if options.models.isEmpty then #[defaultModelDefinition] else options.models

structure FauxProviderHandle where
  provider : LeanAgent.Models.Provider
  api : String
  providerId : String
  models : Array LeanAgent.Models.ModelInfo
  stateRef : IO.Ref FauxState
  responsesRef : IO.Ref (Array FauxResponseStep)
  promptCacheRef : IO.Ref (Array (String × String))

def FauxProviderHandle.state (handle : FauxProviderHandle) : IO FauxState :=
  handle.stateRef.get

def FauxProviderHandle.setResponses (handle : FauxProviderHandle) (responses : Array FauxResponseStep) : IO Unit :=
  handle.responsesRef.set responses

def FauxProviderHandle.appendResponses (handle : FauxProviderHandle) (responses : Array FauxResponseStep) : IO Unit :=
  handle.responsesRef.modify fun current => current ++ responses

def FauxProviderHandle.getPendingResponseCount (handle : FauxProviderHandle) : IO Nat := do
  pure (← handle.responsesRef.get).size

def FauxProviderHandle.getModel? (handle : FauxProviderHandle) (modelId : String) :
    Option LeanAgent.Models.ModelInfo :=
  handle.models.find? fun model => model.id == modelId

def FauxProviderHandle.getModel (handle : FauxProviderHandle) : LeanAgent.Models.ModelInfo :=
  handle.models[0]?.getD (modelFromDefinition handle.api handle.providerId defaultModelDefinition)

def popResponse? (responsesRef : IO.Ref (Array FauxResponseStep)) : IO (Option FauxResponseStep) := do
  let responses ← responsesRef.get
  match responses[0]? with
  | none => pure none
  | some response =>
      responsesRef.set (responses.extract 1 responses.size)
      pure (some response)

def createStream
    (api providerId : String)
    (stateRef : IO.Ref FauxState)
    (responsesRef : IO.Ref (Array FauxResponseStep))
    (promptCacheRef : IO.Ref (Array (String × String)))
    (model : LeanAgent.Models.ModelInfo)
    (context : Context)
    (options : SimpleStreamOptions) : IO AssistantMessageEventStream := do
  if ← LeanAgent.AI.Util.Abort.isAborted options.signal then
    let timestamp ← IO.monoMsNow
    pure <| fromMessage
      { content := #[]
        api := api
        provider := providerId
        model := model.id
        usage := defaultUsage
        stopReason := .aborted
        errorMessage := some LeanAgent.AI.Util.Abort.requestAbortedMessage
        timestamp := timestamp
      }
  else
    let step ← popResponse? responsesRef
    let currentState ← stateRef.get
    let nextState := { currentState with callCount := currentState.callCount + 1 }
    stateRef.set nextState
    let timestamp ← IO.monoMsNow
    match step with
    | none =>
        let message ← withUsageEstimate
          (errorMessage "No more faux responses queued" api providerId model.id timestamp)
          context
          options
          promptCacheRef
        pure (errorStream message)
    | some (.message message) =>
        let message := rewriteMessage message api providerId model.id timestamp
        let message ← withUsageEstimate message context options promptCacheRef
        pure (fromMessage message)
    | some (.factory factory) =>
        try
          let resolved ← factory context options nextState model
          let message := rewriteMessage resolved api providerId model.id timestamp
          let message ← withUsageEstimate message context options promptCacheRef
          pure (fromMessage message)
        catch err =>
          let message := errorMessage err.toString api providerId model.id timestamp
          pure (errorStream message)

def fauxProvider (options : FauxOptions := {}) : IO FauxProviderHandle := do
  let api := options.api.getD defaultApi
  let providerId := options.provider.getD defaultProvider
  let models := modelDefinitions options |>.map (modelFromDefinition api providerId)
  let stateRef ← IO.mkRef {}
  let responsesRef ← IO.mkRef #[]
  let promptCacheRef ← IO.mkRef #[]
  let streamSimple := createStream api providerId stateRef responsesRef promptCacheRef
  let provider : LeanAgent.Models.Provider :=
    { id := providerId
      name := providerId
      baseUrl := some defaultBaseUrl
      auth := {}
      getModels := pure models
      streamSimple := streamSimple
    }
  pure
    { provider := provider
      api := api
      providerId := providerId
      models := models
      stateRef := stateRef
      responsesRef := responsesRef
      promptCacheRef := promptCacheRef
    }

end LeanAgent.AI.Providers.Faux
