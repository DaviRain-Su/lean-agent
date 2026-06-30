import LeanAgent.AI.Api.SimpleOptions
import LeanAgent.AI.Api.TransformMessages
import LeanAgent.AI.Auth
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Abort
import LeanAgent.AI.Util.Diagnostics
import LeanAgent.AI.Util.Headers
import LeanAgent.AI.Util.JsonParse
import LeanAgent.AI.Util.Retry
import LeanAgent.AI.Util.SanitizeUnicode
import LeanAgent.Http
import LeanAgent.Json
import Std.Time

namespace LeanAgent.AI.Api.BedrockConverseStream

open LeanAgent

def api : String := "bedrock-converse-stream"
def defaultRegion : String := "us-east-1"
def defaultBaseUrl : String := "https://bedrock-runtime.us-east-1.amazonaws.com"

def dataRetentionDocsUrl : String :=
  "https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html"

def serviceName : String := "bedrock"

@[extern "lean_agent_sha256_hex"]
opaque sha256Hex (input : @& String) : IO String

@[extern "lean_agent_hmac_sha256_hex"]
opaque hmacSha256Hex (key message : @& String) : IO String

@[extern "lean_agent_hmac_sha256_hex_key_hex"]
opaque hmacSha256HexKeyHex (hexKey message : @& String) : IO String

structure AwsCredentials where
  accessKeyId : String
  secretAccessKey : String
  sessionToken : Option String := none
deriving BEq

structure RequestTimestamp where
  amzDate : String
  dateStamp : String
deriving BEq

inductive ResolvedAuthMode where
  | skip
  | bearer
  | profile
  | sigv4
  | ambientChain
deriving BEq

structure ResolvedAuth where
  mode : ResolvedAuthMode
  credentials : Option AwsCredentials := none
  bearerToken : Option String := none
  profile : Option String := none
  source : Option String := none
deriving BEq

structure PreparedRequest where
  url : String
  requestPath : String
  region : String
  timestamp : RequestTimestamp
  auth : ResolvedAuth
  headers : Array (String × String)
  payload : Lean.Json
deriving BEq

structure BedrockConverseStreamConfig where
  baseUrl : String := defaultBaseUrl
  headers : Array (String × String) := #[]
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

inductive ToolChoice where
  | auto
  | any
  | none
  | tool (name : String)
deriving BEq

inductive BedrockThinkingDisplay where
  | summarized
  | omitted
deriving BEq

def BedrockThinkingDisplay.toString : BedrockThinkingDisplay → String
  | .summarized => "summarized"
  | .omitted => "omitted"

structure BedrockOptions extends LeanAgent.AI.SimpleStreamOptions where
  region : Option String := none
  profile : Option String := none
  toolChoice : Option ToolChoice := none
  interleavedThinking : Option Bool := none
  thinkingDisplay : Option BedrockThinkingDisplay := none
  bearerToken : Option String := none

def optionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) : BedrockOptions :=
  { temperature := options.temperature
    maxTokens := options.maxTokens
    signal := options.signal
    apiKey := options.apiKey
    transport := options.transport
    cacheRetention := options.cacheRetention
    sessionId := options.sessionId
    headers := options.headers
    onPayload := options.onPayload
    onResponse := options.onResponse
    timeoutMs := options.timeoutMs
    websocketConnectTimeoutMs := options.websocketConnectTimeoutMs
    maxRetries := options.maxRetries
    maxRetryDelayMs := options.maxRetryDelayMs
    metadata := options.metadata
    env := options.env
    reasoning := options.reasoning
    thinkingBudgets := options.thinkingBudgets
  }

def trimmedNonEmpty? : Option String → Option String
  | some value =>
      let trimmed := value.trimAscii.toString
      if trimmed.isEmpty then none else some trimmed
  | none => none

def trimTrailingSlash (value : String) : String :=
  if value.endsWith "/" then value.dropEnd 1 |>.toString else value

def timestampAtMs (ms : Nat) : RequestTimestamp :=
  let ts :=
    Std.Time.Timestamp.ofMillisecondsSinceUnixEpoch
      (Std.Time.Millisecond.Offset.ofNat ms)
  let dt := Std.Time.DateTime.ofTimestamp ts .UTC
  { amzDate := Std.Time.DateTime.format dt "uuuuMMdd'T'HHmmss'Z'"
    dateStamp := Std.Time.DateTime.format dt "uuuuMMdd"
  }

def currentTimestamp : IO RequestTimestamp := do
  pure (timestampAtMs (← LeanAgent.AI.Auth.epochMsNow))

def sanitize (text : String) : String :=
  LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates text

def targetModel
    (model : LeanAgent.AI.ModelRef)
    (input : Array String) : LeanAgent.AI.Api.TransformMessages.TargetModel :=
  { id := model.id
    provider := model.provider
    api := model.api
    input := input
  }

def normalizeToolCallId (id : String) : String :=
  LeanAgent.AI.Api.TransformMessages.sanitizeToolCallId id

def createNonBlankTextBlock? (text : String) : Option Lean.Json :=
  let text := sanitize text
  if text.trimAscii.toString.isEmpty then
    none
  else
    some (LeanAgent.Json.obj [("text", LeanAgent.Json.str text)])

def requiredTextBlock (text : String) : Lean.Json :=
  (createNonBlankTextBlock? text).getD
    (LeanAgent.Json.obj [("text", LeanAgent.Json.str "<empty>")])

def imageFormat? (mimeType : String) : Option String :=
  match mimeType.toLower with
  | "image/jpeg" => some "jpeg"
  | "image/jpg" => some "jpeg"
  | "image/png" => some "png"
  | "image/gif" => some "gif"
  | "image/webp" => some "webp"
  | _ => none

def imageBlock (image : LeanAgent.AI.ImageContent) : Lean.Json :=
  match imageFormat? image.mimeType with
  | some format =>
      LeanAgent.Json.obj
        [ ("image",
            LeanAgent.Json.obj
              [ ("format", LeanAgent.Json.str format)
              , ("source", LeanAgent.Json.obj [("bytes", LeanAgent.Json.str image.data)])
              ])
        ]
  | none =>
      LeanAgent.Json.obj
        [("text", LeanAgent.Json.str s!"(image omitted: unsupported MIME type {image.mimeType})")]

def isAnthropicClaudeModel (modelId modelName : String) : Bool :=
  let id := modelId.toLower
  let name := modelName.toLower
  id.contains "anthropic.claude" ||
    id.contains "anthropic/claude" ||
    name.contains "anthropic.claude" ||
    name.contains "anthropic/claude" ||
    name.contains "claude"

def normalizedModelCandidates (modelId modelName : String) : Array String :=
  let normalize (value : String) : String :=
    value.toLower.toList
      |>.map (fun char =>
        if char == ' ' || char == '_' || char == '.' || char == ':' then '-' else char)
      |> String.ofList
  if modelName.trimAscii.toString.isEmpty then
    #[modelId.toLower, normalize modelId]
  else
    #[modelId.toLower, normalize modelId, modelName.toLower, normalize modelName]

def supportsAdaptiveThinking (modelId modelName : String) : Bool :=
  normalizedModelCandidates modelId modelName |>.any fun candidate =>
    candidate.contains "opus-4-6" ||
      candidate.contains "opus-4-7" ||
      candidate.contains "opus-4-8" ||
      candidate.contains "sonnet-4-6" ||
      candidate.contains "fable-5"

def supportsNativeXhighEffort (modelId modelName : String) : Bool :=
  normalizedModelCandidates modelId modelName |>.any fun candidate =>
    candidate.contains "opus-4-7" ||
      candidate.contains "opus-4-8" ||
      candidate.contains "fable-5"

def thinkingLevelMapped? (level : LeanAgent.AI.ThinkingLevel)
    (map : Array LeanAgent.AI.ThinkingLevelMapEntry) : Option String :=
  map.findSome? fun entry =>
    if entry.level == .level level then entry.mapped else none

def mapThinkingLevelToEffort
    (modelId modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (level : LeanAgent.AI.ThinkingLevel) : String :=
  if level == .xhigh && supportsNativeXhighEffort modelId modelName then
    "xhigh"
  else
    match thinkingLevelMapped? level thinkingLevelMap with
    | some mapped => mapped
    | none =>
        match level with
        | .minimal => "low"
        | .low => "low"
        | .medium => "medium"
        | .high => "high"
        | .xhigh => "high"

def supportsPromptCaching (modelId modelName : String) (env : LeanAgent.AI.Auth.ProviderEnv) : Bool :=
  let candidates := normalizedModelCandidates modelId modelName
  let hasClaude := candidates.any (fun candidate => candidate.contains "claude")
  if !hasClaude then
    LeanAgent.AI.Auth.providerEnvGet? env "AWS_BEDROCK_FORCE_CACHE" == some "1"
  else
    candidates.any (fun candidate =>
      candidate.contains "-4-" ||
        candidate.contains "claude-3-7-sonnet" ||
        candidate.contains "claude-3-5-haiku")

def buildSystemPrompt
    (systemPrompt : Option String)
    (modelId modelName : String)
    (cacheRetention : LeanAgent.AI.CacheRetention)
    (env : LeanAgent.AI.Auth.ProviderEnv) : Option Lean.Json :=
  match systemPrompt with
  | none => none
  | some prompt =>
      let textBlock := LeanAgent.Json.obj [("text", LeanAgent.Json.str (sanitize prompt))]
      let blocks :=
        if cacheRetention != .none && supportsPromptCaching modelId modelName env then
          let cachePointFields :=
            if cacheRetention == .long then
              [ ("type", LeanAgent.Json.str "default")
              , ("ttl", LeanAgent.Json.str "ONE_HOUR")
              ]
            else
              [("type", LeanAgent.Json.str "default")]
          #[ textBlock
           , LeanAgent.Json.obj [("cachePoint", LeanAgent.Json.obj cachePointFields)]
           ]
        else
          #[textBlock]
      some (LeanAgent.Json.arr blocks)

def userContentBlock? (supportsImages : Bool) : LeanAgent.AI.ContentBlock → Option Lean.Json
  | .text content => createNonBlankTextBlock? content.text
  | .image image =>
      if supportsImages then some (imageBlock image) else none
  | .thinking content => createNonBlankTextBlock? content.thinking
  | .toolCall _ => none

def assistantContentBlock? (supportsThinkingSignature : Bool) : LeanAgent.AI.ContentBlock → Option Lean.Json
  | .text content => createNonBlankTextBlock? content.text
  | .toolCall call =>
      some
        (LeanAgent.Json.obj
          [ ("toolUse",
              LeanAgent.Json.obj
                [ ("toolUseId", LeanAgent.Json.str call.id)
                , ("name", LeanAgent.Json.str call.name)
                , ("input", call.arguments)
                ])
          ])
  | .thinking content =>
      let thinking := sanitize content.thinking
      if thinking.trimAscii.toString.isEmpty then
        none
      else if supportsThinkingSignature then
        match content.thinkingSignature with
        | some signature =>
            if signature.trimAscii.toString.isEmpty then
              some (LeanAgent.Json.obj [("text", LeanAgent.Json.str thinking)])
            else
              some
                (LeanAgent.Json.obj
                  [ ("reasoningContent",
                      LeanAgent.Json.obj
                        [ ("reasoningText",
                            LeanAgent.Json.obj
                              [ ("text", LeanAgent.Json.str thinking)
                              , ("signature", LeanAgent.Json.str signature)
                              ])
                        ])
                  ])
        | none => some (LeanAgent.Json.obj [("text", LeanAgent.Json.str thinking)])
      else
        some
          (LeanAgent.Json.obj
            [ ("reasoningContent",
                LeanAgent.Json.obj
                  [("reasoningText", LeanAgent.Json.obj [("text", LeanAgent.Json.str thinking)])])
            ])
  | .image _ => none

def convertToolResultContent (supportsImages : Bool) (content : Array LeanAgent.AI.ContentBlock) : Array Lean.Json :=
  let blocks := content.filterMap fun block =>
    match block with
    | .text text => createNonBlankTextBlock? text.text
    | .thinking thinking => createNonBlankTextBlock? thinking.thinking
    | .image image => if supportsImages then some (imageBlock image) else none
    | .toolCall _ => none
  if blocks.isEmpty then
    #[LeanAgent.Json.obj [("text", LeanAgent.Json.str "<empty>")]]
  else
    blocks

def toolResultBlock (supportsImages : Bool) (message : LeanAgent.AI.ToolResultMessage) : Lean.Json :=
  LeanAgent.Json.obj
    [ ("toolResult",
        LeanAgent.Json.obj
          [ ("toolUseId", LeanAgent.Json.str message.toolCallId)
          , ("content", LeanAgent.Json.arr (convertToolResultContent supportsImages message.content))
          , ("status", LeanAgent.Json.str (if message.isError then "error" else "success"))
          ])
    ]

def convertMessagesFromArray
    (messages : Array LeanAgent.AI.Message)
    (supportsImages supportsThinkingSignature : Bool)
    : Array Lean.Json :=
  Id.run do
    let mut acc := #[]
    let mut i := 0
    while h : i < messages.size do
      match messages[i] with
      | .user user =>
          let content := user.content.filterMap (userContentBlock? supportsImages)
          let content := if content.isEmpty then #[requiredTextBlock ""] else content
          acc := acc.push
            (LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "user")
              , ("content", LeanAgent.Json.arr content)
              ])
          i := i + 1
      | .assistant assistant =>
          let content := assistant.content.filterMap (assistantContentBlock? supportsThinkingSignature)
          if !content.isEmpty then
            acc := acc.push
              (LeanAgent.Json.obj
                [ ("role", LeanAgent.Json.str "assistant")
                , ("content", LeanAgent.Json.arr content)
                ])
          i := i + 1
      | .toolResult toolResult =>
          let mut toolResults := #[toolResultBlock supportsImages toolResult]
          let mut j := i + 1
          while h2 : j < messages.size do
            match messages[j] with
            | .toolResult next =>
                toolResults := toolResults.push (toolResultBlock supportsImages next)
                j := j + 1
            | _ => break
          acc := acc.push
            (LeanAgent.Json.obj
              [ ("role", LeanAgent.Json.str "user")
              , ("content", LeanAgent.Json.arr toolResults)
              ])
          i := j
    pure acc

def convertMessages
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelName : String)
    (context : LeanAgent.AI.Context) : Array Lean.Json :=
  let transformed := LeanAgent.AI.Api.TransformMessages.transformMessages
    context.messages
    (targetModel model input)
    { normalizeToolCallId? := some (fun id _ _ => normalizeToolCallId id) }
  convertMessagesFromArray transformed (input.contains "image")
    (isAnthropicClaudeModel model.id modelName)

def toolChoiceJson? : ToolChoice → Option Lean.Json
  | .auto => some (LeanAgent.Json.obj [("auto", LeanAgent.Json.obj [])])
  | .any => some (LeanAgent.Json.obj [("any", LeanAgent.Json.obj [])])
  | .none => none
  | .tool name => some (LeanAgent.Json.obj [("tool", LeanAgent.Json.obj [("name", LeanAgent.Json.str name)])])

def convertToolConfig (tools : Array LeanAgent.AI.Tool) (toolChoice : Option ToolChoice) : Option Lean.Json :=
  match toolChoice with
  | some .none => none
  | _ =>
      if tools.isEmpty then
        none
      else
        let bedrockTools := tools.map fun tool =>
          LeanAgent.Json.obj
            [ ("toolSpec",
                LeanAgent.Json.obj
                  [ ("name", LeanAgent.Json.str tool.name)
                  , ("description", LeanAgent.Json.str tool.description)
                  , ("inputSchema", LeanAgent.Json.obj [("json", tool.parameters)])
                  ])
            ]
        let fields := [("tools", LeanAgent.Json.arr bedrockTools)]
          ++ (match toolChoice.bind toolChoiceJson? with
              | some choice => [("toolChoice", choice)]
              | none => [])
        some (LeanAgent.Json.obj fields)

def thinkingBudget
    (customBudgets : Option LeanAgent.AI.ThinkingBudgets)
    (level : LeanAgent.AI.ThinkingLevel) : Nat :=
  LeanAgent.AI.Api.SimpleOptions.thinkingBudgetD customBudgets level

def modelArnRegion? (modelId : String) : Option String :=
  match modelId.splitOn ":" with
  | "arn" :: partition :: "bedrock" :: region :: _ =>
      if partition.startsWith "aws" then
        let trimmed := region.trimAscii.toString
        if trimmed.isEmpty then none else some trimmed
      else
        none
  | _ => none

def isGovCloudTarget (model : LeanAgent.AI.ModelRef) (options : BedrockOptions) : Bool :=
  let regionGov :=
    match trimmedNonEmpty? options.region with
    | some region => region.toLower.startsWith "us-gov-"
    | none => false
  let id := model.id.toLower
  regionGov || id.startsWith "us-gov." || id.startsWith "arn:aws-us-gov:"

def buildAdditionalModelRequestFields
    (model : LeanAgent.AI.ModelRef)
    (modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (reasoning : Bool)
    (options : BedrockOptions) : Option Lean.Json :=
  match options.reasoning with
  | none => none
  | some level =>
      if !reasoning || !isAnthropicClaudeModel model.id modelName then
        none
      else
        let displayFields :=
          if isGovCloudTarget model options then
            []
          else
            match options.thinkingDisplay.getD .summarized with
            | display => [("display", LeanAgent.Json.str display.toString)]
        if supportsAdaptiveThinking model.id modelName then
          some
            (LeanAgent.Json.obj
              [ ("thinking",
                  LeanAgent.Json.obj
                    ([("type", LeanAgent.Json.str "adaptive")] ++ displayFields))
              , ("output_config",
                  LeanAgent.Json.obj
                    [ ("effort",
                        LeanAgent.Json.str
                          (mapThinkingLevelToEffort model.id modelName thinkingLevelMap level))
                    ])
              ])
        else
          let resultFields :=
            [ ("thinking",
                LeanAgent.Json.obj
                  ([ ("type", LeanAgent.Json.str "enabled")
                   , ("budget_tokens", LeanAgent.Json.nat (thinkingBudget options.thinkingBudgets level))
                   ] ++ displayFields))
            ]
          let resultFields :=
            if options.interleavedThinking.getD true then
              resultFields ++ [("anthropic_beta", LeanAgent.Json.arr #[LeanAgent.Json.str "interleaved-thinking-2025-05-14"])]
            else
              resultFields
          some (LeanAgent.Json.obj resultFields)

def requestToJsonWithOptions
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : BedrockOptions := {}) : Lean.Json :=
  let cacheRetention := options.cacheRetention.getD .short
  let inferenceFields :=
    (match options.maxTokens with
     | some maxTokens => [("maxTokens", LeanAgent.Json.nat maxTokens)]
     | none => [])
    ++ (match options.temperature with
        | some temperature => [("temperature", LeanAgent.AI.floatJson temperature)]
        | none => [])
  LeanAgent.Json.obj
    ([ ("modelId", LeanAgent.Json.str model.id)
     , ("messages", LeanAgent.Json.arr (convertMessages model input modelName context))
     ] ++ (match buildSystemPrompt context.systemPrompt model.id modelName cacheRetention options.env with
          | some system => [("system", system)]
          | none => [])
       ++ (if inferenceFields.isEmpty then [] else [("inferenceConfig", LeanAgent.Json.obj inferenceFields)])
       ++ (match convertToolConfig context.tools options.toolChoice with
          | some toolConfig => [("toolConfig", toolConfig)]
          | none => [])
       ++ (match buildAdditionalModelRequestFields model modelName thinkingLevelMap reasoning options with
          | some fields => [("additionalModelRequestFields", fields)]
          | none => [])
       ++ (match options.metadata with
          | some metadata => [("requestMetadata", metadata)]
          | none => []))

def applyPayloadHook
    (options : BedrockOptions)
    (model : LeanAgent.AI.ModelRef)
    (payload : Lean.Json) : IO Lean.Json := do
  match options.onPayload with
  | none => pure payload
  | some hook =>
      match ← hook payload model with
      | some nextPayload => pure nextPayload
      | none => pure payload

def mapStopReason : Option String → LeanAgent.AI.StopReason
  | some "END_TURN" => .stop
  | some "STOP_SEQUENCE" => .stop
  | some "MAX_TOKENS" => .length
  | some "MODEL_CONTEXT_WINDOW_EXCEEDED" => .length
  | some "TOOL_USE" => .toolUse
  | _ => .error

def stripStringPrefix? (pfx value : String) : Option String :=
  if value.startsWith pfx then some (value.drop pfx.length |>.toString) else none

def stripStringSuffix? (suffix value : String) : Option String :=
  if value.endsWith suffix then some (value.dropEnd suffix.length |>.toString) else none

def hostFromUrl (url : String) : String :=
  let withoutScheme :=
    match stripStringPrefix? "https://" url with
    | some rest => rest
    | none =>
        match stripStringPrefix? "http://" url with
        | some rest => rest
        | none => url
  (withoutScheme.splitOn "/")[0]?.getD withoutScheme

def standardEndpointRegion? (baseUrl : String) : Option String := do
  let host := (hostFromUrl baseUrl).toLower
  let host ←
    match stripStringPrefix? "bedrock-runtime." host with
    | some rest => some rest
    | none => stripStringPrefix? "bedrock-runtime-fips." host
  match stripStringSuffix? ".amazonaws.com.cn" host with
  | some region => some region
  | none => stripStringSuffix? ".amazonaws.com" host

def shouldUseExplicitEndpoint
    (baseUrl : String)
    (configuredRegion : Option String)
    (hasAmbientProfile : Bool) : Bool :=
  match standardEndpointRegion? baseUrl with
  | none => true
  | some _ => configuredRegion.isNone && !hasAmbientProfile

def envValue? (env : LeanAgent.AI.Auth.ProviderEnv) (name : String) : IO (Option String) := do
  match LeanAgent.AI.Auth.providerEnvGet? env name with
  | some value => pure (some value)
  | none =>
      match ← IO.getEnv name with
      | some value =>
          let trimmed := value.trimAscii.toString
          pure (if trimmed.isEmpty then none else some trimmed)
      | none => pure none

structure AwsIniSection where
  name : String
  fields : Array (String × String) := #[]
deriving BEq

def defaultSharedCredentialsPath : String := "~/.aws/credentials"
def defaultSharedConfigPath : String := "~/.aws/config"

def stripTrailingCR (line : String) : String :=
  match line.toList.reverse with
  | '\r' :: rest => String.ofList rest.reverse
  | _ => line

def parseAwsIniKeyValue? (line : String) : Option (String × String) :=
  match line.splitOn "=" with
  | [] => none
  | _ :: [] => none
  | key :: valueParts =>
      let key := key.trimAscii.toString.toLower
      let value := (String.intercalate "=" valueParts).trimAscii.toString
      if key.isEmpty then none else some (key, value)

def appendAwsIniSection
    (sections : Array AwsIniSection)
    (name? : Option String)
    (fields : Array (String × String)) : Array AwsIniSection :=
  match name? with
  | some name => sections.push { name := name, fields := fields }
  | none => sections

def parseAwsIniSections (text : String) : Array AwsIniSection :=
  Id.run do
    let mut sections : Array AwsIniSection := #[]
    let mut currentName : Option String := none
    let mut currentFields : Array (String × String) := #[]
    for rawLine in text.splitOn "\n" do
      let line := (stripTrailingCR rawLine).trimAscii.toString
      if line.isEmpty || line.startsWith "#" || line.startsWith ";" then
        pure ()
      else if line.startsWith "[" && line.endsWith "]" then
        sections := appendAwsIniSection sections currentName currentFields
        currentName := some ((line.drop 1).dropEnd 1 |>.toString |>.trimAscii.toString)
        currentFields := #[]
      else
        match currentName, parseAwsIniKeyValue? line with
        | some _, some field =>
            currentFields := currentFields.push field
        | _, _ => pure ()
    appendAwsIniSection sections currentName currentFields

def sharedCredentialsFilePath (options : BedrockOptions) : IO String := do
  pure ((← envValue? options.env "AWS_SHARED_CREDENTIALS_FILE").getD defaultSharedCredentialsPath)

def sharedConfigFilePath (options : BedrockOptions) : IO String := do
  pure ((← envValue? options.env "AWS_CONFIG_FILE").getD defaultSharedConfigPath)

def readAwsIniFile? (path : String) : IO (Option (Array AwsIniSection)) := do
  let resolved ← LeanAgent.AI.Auth.expandHomePath path
  if !(← resolved.pathExists) then
    pure none
  else
    pure (some (parseAwsIniSections (← IO.FS.readFile resolved)))

def awsProfileSectionNames (profile : String) : Array String :=
  if profile == "default" then
    #["default"]
  else
    #[profile, s!"profile {profile}"]

def awsIniField?
    (sections : Array AwsIniSection)
    (sectionNames : Array String)
    (key : String) : Option String :=
  sectionNames.findSome? fun sectionName =>
    (sections.findSome? fun sec =>
      if sec.name == sectionName then
        sec.fields.findSome? fun (fieldName, value) =>
          if fieldName == key then some value else none
      else
        none)

structure AwsProfileSettings where
  accessKeyId : Option String := none
  secretAccessKey : Option String := none
  sessionToken : Option String := none
  region : Option String := none
deriving BEq

def awsProfileSettings? (options : BedrockOptions) (profile : String) : IO (Option AwsProfileSettings) := do
  let credentialsSections ← readAwsIniFile? (← sharedCredentialsFilePath options)
  let configSections ← readAwsIniFile? (← sharedConfigFilePath options)
  let credentialNames := #[profile]
  let configNames := awsProfileSectionNames profile
  let accessKeyId :=
    credentialsSections.bind (fun sections => awsIniField? sections credentialNames "aws_access_key_id")
      <|> configSections.bind (fun sections => awsIniField? sections configNames "aws_access_key_id")
  let secretAccessKey :=
    credentialsSections.bind (fun sections => awsIniField? sections credentialNames "aws_secret_access_key")
      <|> configSections.bind (fun sections => awsIniField? sections configNames "aws_secret_access_key")
  let sessionToken :=
    credentialsSections.bind (fun sections => awsIniField? sections credentialNames "aws_session_token")
      <|> configSections.bind (fun sections => awsIniField? sections configNames "aws_session_token")
  let region :=
    configSections.bind (fun sections => awsIniField? sections configNames "region")
      <|> credentialsSections.bind (fun sections => awsIniField? sections credentialNames "region")
  if accessKeyId.isNone && secretAccessKey.isNone && sessionToken.isNone && region.isNone then
    pure none
  else
    pure
      (some
        { accessKeyId := accessKeyId
          secretAccessKey := secretAccessKey
          sessionToken := sessionToken
          region := region
        })

def configuredProfileSource? (options : BedrockOptions) : IO (Option (String × String)) := do
  match trimmedNonEmpty? options.profile with
  | some profile => pure (some ("options.profile", profile))
  | none =>
      match ← envValue? options.env "AWS_PROFILE" with
      | some profile => pure (some ("AWS_PROFILE", profile))
      | none =>
          match ← envValue? options.env "AWS_DEFAULT_PROFILE" with
          | some profile => pure (some ("AWS_DEFAULT_PROFILE", profile))
          | none => pure none

def configuredRegion? (options : BedrockOptions) : IO (Option String) := do
  match options.region with
  | some region => pure (some region)
  | none =>
      match ← envValue? options.env "AWS_REGION" with
      | some region => pure (some region)
      | none => envValue? options.env "AWS_DEFAULT_REGION"

def configuredCredentials? (options : BedrockOptions) : IO (Option AwsCredentials) := do
  match ← envValue? options.env "AWS_ACCESS_KEY_ID", ← envValue? options.env "AWS_SECRET_ACCESS_KEY" with
  | some accessKeyId, some secretAccessKey =>
      pure
        (some
          { accessKeyId
            secretAccessKey
            sessionToken := ← envValue? options.env "AWS_SESSION_TOKEN"
          })
  | _, _ => pure none

def ambientCredentialChainSource? (options : BedrockOptions) : IO (Option String) := do
  match ← envValue? options.env "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" with
  | some _ => pure (some "ECS task role")
  | none =>
      match ← envValue? options.env "AWS_CONTAINER_CREDENTIALS_FULL_URI" with
      | some _ => pure (some "ECS task role")
      | none =>
          match ← envValue? options.env "AWS_WEB_IDENTITY_TOKEN_FILE" with
          | some _ => pure (some "web identity token")
          | none => pure none

def shouldSkipAuth (options : BedrockOptions) : IO Bool := do
  pure ((← envValue? options.env "AWS_BEDROCK_SKIP_AUTH") == some "1")

def resolvedAuth (options : BedrockOptions) : IO ResolvedAuth := do
  if ← shouldSkipAuth options then
    pure { mode := .skip, source := some "AWS_BEDROCK_SKIP_AUTH" }
  else
    match trimmedNonEmpty? options.bearerToken with
    | some token =>
        pure { mode := .bearer, bearerToken := some token, source := some "options.bearerToken" }
    | none =>
        match ← configuredProfileSource? options with
        | some (source, profile) =>
            match ← awsProfileSettings? options profile with
            | some settings =>
                match settings.accessKeyId, settings.secretAccessKey with
                | some accessKeyId, some secretAccessKey =>
                    pure
                      { mode := .sigv4
                        credentials := some
                          { accessKeyId := accessKeyId
                            secretAccessKey := secretAccessKey
                            sessionToken := settings.sessionToken
                          }
                        profile := some profile
                        source := some source
                      }
                | _, _ =>
                    throw
                      (IO.userError
                        s!"Bedrock profile \"{profile}\" was found via {source}, but shared credentials/config files do not contain aws_access_key_id and aws_secret_access_key. SSO, credential_process, and role chaining are not implemented yet.")
            | none =>
                throw
                  (IO.userError
                    s!"Bedrock profile \"{profile}\" was requested via {source}, but no matching shared credentials/config entry was found.")
        | none =>
            match ← envValue? options.env "AWS_BEARER_TOKEN_BEDROCK" with
            | some token =>
                pure { mode := .bearer, bearerToken := some token, source := some "AWS_BEARER_TOKEN_BEDROCK" }
            | none =>
                match ← configuredCredentials? options with
                | some credentials =>
                    pure { mode := .sigv4, credentials := some credentials, source := some "AWS access keys" }
                | none =>
                    match ← ambientCredentialChainSource? options with
                    | some source => pure { mode := .ambientChain, source := some source }
                    | none => pure { mode := .ambientChain }

def resolvedRegion
    (baseUrl modelId : String)
    (_options : BedrockOptions)
    (configuredRegion : Option String)
    (profileRegion : Option String)
    (hasAmbientProfile : Bool) : IO String := do
  match modelArnRegion? modelId with
  | some region => pure region
  | none =>
      match configuredRegion with
      | some region => pure region
      | none =>
          match profileRegion with
          | some region => pure region
          | none =>
              if shouldUseExplicitEndpoint baseUrl configuredRegion hasAmbientProfile then
                pure ((standardEndpointRegion? baseUrl).getD defaultRegion)
              else
                pure defaultRegion

def sdkDefaultBaseUrl (region : String) : String :=
  let suffix :=
    if region.startsWith "cn-" then
      "amazonaws.com.cn"
    else
      "amazonaws.com"
  s!"https://bedrock-runtime.{region}.{suffix}"

def resolvedBaseUrl
    (baseUrl : String)
    (configuredRegion : Option String)
    (hasAmbientProfile : Bool)
    (resolvedRegionValue : String) : String :=
  if shouldUseExplicitEndpoint baseUrl configuredRegion hasAmbientProfile then
    trimTrailingSlash baseUrl
  else
    sdkDefaultBaseUrl resolvedRegionValue

def isReservedHeader (name : String) : Bool :=
  let lower := name.toLower
  lower == "authorization" || lower == "host" || lower.startsWith "x-amz-"

def requestHeaders
    (config : BedrockConverseStreamConfig)
    (options : BedrockOptions) : Array (String × String) :=
  let configHeaders := config.headers.filter fun (name, _) => !isReservedHeader name
  let callerHeaders :=
    LeanAgent.AI.Util.Headers.providerHeadersToArray options.headers
      |>.filter fun (name, _) => !isReservedHeader name
  LeanAgent.AI.Util.Headers.merge configHeaders callerHeaders

def hexDigitUpper (value : Nat) : Char :=
  if value < 10 then
    Char.ofNat ('0'.toNat + value)
  else
    Char.ofNat ('A'.toNat + (value - 10))

def percentEncodeByte (value : Nat) : String :=
  String.ofList
    [ '%'
    , hexDigitUpper ((value / 16) % 16)
    , hexDigitUpper (value % 16)
    ]

def isUnreservedPathChar (char : Char) : Bool :=
  char.isAlphanum || char == '-' || char == '_' || char == '.' || char == '~'

def percentEncodePathSegment (value : String) : String :=
  String.intercalate ""
    (value.toList.map fun char =>
      if isUnreservedPathChar char then
        String.ofList [char]
      else
        percentEncodeByte char.toNat)

def buildRequestPath (modelId : String) : String :=
  s!"/model/{percentEncodePathSegment modelId}/converse-stream"

def normalizeHeaderValue (value : String) : String :=
  let trimmed := value.trimAscii.toString
  let (chars, _) :=
    trimmed.toList.foldl
      (fun (acc, previousWasSpace) char =>
        let isSpace := char == ' ' || char == '\t' || char == '\r' || char == '\n'
        if isSpace then
          if previousWasSpace then
            (acc, true)
          else
            (acc ++ [' '], true)
        else
          (acc ++ [char], false))
      ([], false)
  String.ofList chars

def canonicalHeaderEntries (headers : Array (String × String)) : Array (String × String) :=
  let entries :=
    headers.filterMap fun (name, value) =>
      let normalizedName := name.trimAscii.toString.toLower
      if normalizedName.isEmpty then
        none
      else
        some (normalizedName, normalizeHeaderValue value)
  entries.qsort fun a b => a.fst < b.fst

def canonicalHeadersText (headers : Array (String × String)) : String :=
  String.intercalate ""
    (headers.toList.map fun (name, value) => s!"{name}:{value}\n")

def signedHeadersText (headers : Array (String × String)) : String :=
  String.intercalate ";" (headers.toList.map Prod.fst)

def credentialScope (timestamp : RequestTimestamp) (region : String) : String :=
  s!"{timestamp.dateStamp}/{region}/{serviceName}/aws4_request"

def deriveSigningKeyHex
    (secretAccessKey : String)
    (timestamp : RequestTimestamp)
    (region : String) : IO String := do
  let kDate ← hmacSha256Hex ("AWS4" ++ secretAccessKey) timestamp.dateStamp
  let kRegion ← hmacSha256HexKeyHex kDate region
  let kService ← hmacSha256HexKeyHex kRegion serviceName
  hmacSha256HexKeyHex kService "aws4_request"

def signRequestHeaders
    (endpointBaseUrl requestPath body : String)
    (credentials : AwsCredentials)
    (timestamp : RequestTimestamp)
    (region : String)
    (headers : Array (String × String)) : IO (Array (String × String)) := do
  let host := hostFromUrl endpointBaseUrl
  let bodyHash ← sha256Hex body
  let headers :=
    LeanAgent.AI.Util.Headers.insert
      (LeanAgent.AI.Util.Headers.insert
        (LeanAgent.AI.Util.Headers.insert headers ("host", host))
        ("x-amz-content-sha256", bodyHash))
      ("x-amz-date", timestamp.amzDate)
  let headers :=
    match credentials.sessionToken with
    | some sessionToken =>
        LeanAgent.AI.Util.Headers.insert headers ("x-amz-security-token", sessionToken)
    | none => headers
  let canonical := canonicalHeaderEntries headers
  let signedHeaders := signedHeadersText canonical
  let canonicalRequest :=
    s!"POST\n{requestPath}\n\n{canonicalHeadersText canonical}\n{signedHeaders}\n{bodyHash}"
  let canonicalRequestHash ← sha256Hex canonicalRequest
  let scope := credentialScope timestamp region
  let stringToSign :=
    s!"AWS4-HMAC-SHA256\n{timestamp.amzDate}\n{scope}\n{canonicalRequestHash}"
  let signingKey ← deriveSigningKeyHex credentials.secretAccessKey timestamp region
  let signature ← hmacSha256HexKeyHex signingKey stringToSign
  let authorization :=
    s!"AWS4-HMAC-SHA256 Credential={credentials.accessKeyId}/{scope}, SignedHeaders={signedHeaders}, Signature={signature}"
  pure (LeanAgent.AI.Util.Headers.insert headers ("Authorization", authorization))

def prepareRequestWithTimestamp
    (config : BedrockConverseStreamConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (timestamp : RequestTimestamp)
    (options : BedrockOptions := {}) : IO PreparedRequest := do
  let requestModel : LeanAgent.AI.ModelRef := { model with baseUrl := some config.baseUrl }
  let payload0 := requestToJsonWithOptions requestModel input modelName thinkingLevelMap reasoning context options
  let payload ← applyPayloadHook options requestModel payload0
  let auth ← resolvedAuth options
  let configuredRegion := ← configuredRegion? options
  let hasAmbientProfile := auth.profile.isSome
  let profileRegion ←
    match auth.profile with
    | some profile =>
        match ← awsProfileSettings? options profile with
        | some settings => pure settings.region
        | none => pure none
    | none => pure none
  let region ← resolvedRegion config.baseUrl requestModel.id options configuredRegion profileRegion hasAmbientProfile
  let baseUrl := resolvedBaseUrl config.baseUrl configuredRegion hasAmbientProfile region
  let requestPath := buildRequestPath requestModel.id
  let url := baseUrl ++ requestPath
  let baseHeaders :=
    LeanAgent.AI.Util.Headers.insert (requestHeaders config options) ("Content-Type", "application/json")
  let headers ←
    match auth.mode, auth.credentials, auth.bearerToken with
    | .sigv4, some credentials, _ =>
        signRequestHeaders baseUrl requestPath payload.compress credentials timestamp region baseHeaders
    | .bearer, _, some token =>
        pure (LeanAgent.AI.Util.Headers.insert baseHeaders ("Authorization", "Bearer " ++ token))
    | .profile, _, _ =>
        throw (IO.userError "Bedrock profile auth must resolve to SigV4 credentials before request dispatch")
    | .ambientChain, _, _ =>
        throw
          (IO.userError
            "Bedrock ambient AWS credential-chain dispatch is not implemented yet. Set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY, AWS_PROFILE with shared credentials/config files, or AWS_BEARER_TOKEN_BEDROCK.")
    | _, _, _ => pure baseHeaders
  pure
    { url
      requestPath
      region
      timestamp
      auth
      headers
      payload
    }

def prepareRequestWithOptions
    (config : BedrockConverseStreamConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : BedrockOptions := {}) : IO PreparedRequest := do
  prepareRequestWithTimestamp
    config
    model
    input
    modelName
    thinkingLevelMap
    reasoning
    context
    (← currentTimestamp)
    options

def modelRef (config : BedrockConverseStreamConfig) (model : LeanAgent.AI.ModelRef) :
    LeanAgent.AI.ModelRef :=
  { model with baseUrl := some config.baseUrl }

def callResponseHook
    (options : BedrockOptions)
    (model : LeanAgent.AI.ModelRef)
    (response : LeanAgent.Http.JsonPostResponse) : IO Unit := do
  match options.onResponse with
  | none => pure ()
  | some hook =>
      hook { status := response.status, headers := response.headers } model

def runHttpEventStreamJson
    (config : BedrockConverseStreamConfig)
    (model : LeanAgent.AI.ModelRef)
    (prepared : PreparedRequest)
    (options : BedrockOptions := {}) : IO String := do
  LeanAgent.AI.Util.Abort.throwIfAborted options.signal
  let response ← LeanAgent.Http.requestAwsEventStreamJsonResponse
    { method := "POST"
      url := prepared.url
      body := some prepared.payload.compress
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
      headers := prepared.headers
    }
  callResponseHook options model response
  if response.status < 200 || response.status >= 300 then
    throw (IO.userError (LeanAgent.AI.Util.Diagnostics.providerHttpErrorMessage response.status response.body))
  pure response.body

def jsonString? : Lean.Json → Option String
  | .str value => some value
  | _ => none

def optionalStringField (json : Lean.Json) (key : String) : Option String :=
  (LeanAgent.Json.optVal? json key).bind jsonString?

def optionalObjectField (json : Lean.Json) (key : String) : Option Lean.Json :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getObj? with
      | .ok _ => some value
      | .error _ => none
  | none => none

def natFieldD (json : Lean.Json) (key : String) (default : Nat := 0) : Nat :=
  match LeanAgent.Json.optVal? json key with
  | some value => value.getNat?.toOption.getD default
  | none => default

def parseMetadataUsage (usage : Lean.Json) : LeanAgent.AI.Usage :=
  let input := natFieldD usage "inputTokens"
  let output := natFieldD usage "outputTokens"
  let cacheRead := natFieldD usage "cacheReadInputTokens"
  let cacheWrite := natFieldD usage "cacheWriteInputTokens"
  let totalTokens := natFieldD usage "totalTokens" (input + output)
  { input := input
    output := output
    cacheRead := cacheRead
    cacheWrite := cacheWrite
    totalTokens := totalTokens
  }

def bedrockErrorPrefix (name : String) : String :=
  match name with
  | "internalServerException" => "Internal server error"
  | "modelStreamErrorException" => "Model stream error"
  | "validationException" => "Validation error"
  | "throttlingException" => "Throttling error"
  | "serviceUnavailableException" => "Service unavailable"
  | _ => name

def hasDataRetentionHint (message : String) : Bool :=
  message.toLower.contains "data retention mode"

def formatBedrockStreamError (name : String) (payload : Lean.Json) : String :=
  let errPrefix := bedrockErrorPrefix name;
  let baseMessage :=
    Option.getD
      (optionalStringField payload "message" <|> optionalStringField payload "originalMessage")
      (payload.compress);
  let withPrefix :=
    if errPrefix.isEmpty || errPrefix == name then
      if baseMessage == payload.compress then errPrefix else s!"{errPrefix}: {baseMessage}"
    else
      s!"{errPrefix}: {baseMessage}";
  if hasDataRetentionHint baseMessage then
    withPrefix ++ s!" See {dataRetentionDocsUrl} for supported data retention modes."
  else
    withPrefix

inductive StreamingBlockKind where
  | text
  | thinking
  | toolCall
deriving BEq

structure StreamingBlock where
  streamIndex : Nat
  contentIndex : Nat
  kind : StreamingBlockKind
  text : String := ""
  thinkingSignature : Option String := none
  id : String := ""
  name : String := ""
  partialArguments : String := ""
  ended : Bool := false
deriving BEq

structure StreamingState where
  blocks : Array StreamingBlock := #[]
  order : Array Nat := #[]
  usage : LeanAgent.AI.Usage := LeanAgent.AI.Usage.empty
  stopReason : LeanAgent.AI.StopReason := .stop
  errorMessage : Option String := none
  sawMessageStart : Bool := false
  sawMessageStop : Bool := false
deriving BEq

inductive ParsedStreamEvent where
  | textStart (contentIndex : Nat)
  | textDelta (contentIndex : Nat) (delta : String)
  | textEnd (contentIndex : Nat) (content : String)
  | thinkingStart (contentIndex : Nat)
  | thinkingDelta (contentIndex : Nat) (delta : String)
  | thinkingEnd (contentIndex : Nat) (content : String)
  | toolCallStart (contentIndex : Nat)
  | toolCallDelta (contentIndex : Nat) (delta : String)
  | toolCallEnd (contentIndex : Nat) (call : LeanAgent.AI.ToolCall)
deriving BEq

def findBlock? (state : StreamingState) (streamIndex : Nat) : Option StreamingBlock :=
  state.blocks.find? fun block => block.streamIndex == streamIndex

def updateBlock (state : StreamingState) (next : StreamingBlock) : StreamingState :=
  { state with
    blocks := state.blocks.map fun block =>
      if block.streamIndex == next.streamIndex then next else block
  }

def pushBlock (state : StreamingState) (block : StreamingBlock) : StreamingState :=
  { state with
    blocks := state.blocks.push block
    order := state.order.push block.streamIndex
  }

def startEventForBlock (block : StreamingBlock) : ParsedStreamEvent :=
  match block.kind with
  | .text => .textStart block.contentIndex
  | .thinking => .thinkingStart block.contentIndex
  | .toolCall => .toolCallStart block.contentIndex

def toolCallFromBlock (block : StreamingBlock) : LeanAgent.AI.ToolCall :=
  { id := block.id
    name := block.name
    arguments := LeanAgent.AI.Util.JsonParse.parseStreamingJson block.partialArguments
  }

def contentBlockFromStreamingBlock (block : StreamingBlock) : LeanAgent.AI.ContentBlock :=
  match block.kind with
  | .text => .text { text := block.text }
  | .thinking =>
      .thinking
        { thinking := block.text
          thinkingSignature := block.thinkingSignature
        }
  | .toolCall => .toolCall (toolCallFromBlock block)

def contentFromStreamingState (state : StreamingState) : Array LeanAgent.AI.ContentBlock :=
  state.order.filterMap fun streamIndex =>
    match findBlock? state streamIndex with
    | some block => some (contentBlockFromStreamingBlock block)
    | none => none

def messageFromStreamingState
    (api provider model : String)
    (timestamp : Nat)
    (state : StreamingState) : LeanAgent.AI.AssistantMessage :=
  { content := contentFromStreamingState state
    api := api
    provider := provider
    model := model
    usage := state.usage
    stopReason := state.stopReason
    errorMessage := state.errorMessage
    timestamp := timestamp
  }

def parsedEventToAssistantEvent
    (message : LeanAgent.AI.AssistantMessage) : ParsedStreamEvent → LeanAgent.AI.AssistantMessageEvent
  | .textStart index => .textStart index message
  | .textDelta index delta => .textDelta index delta message
  | .textEnd index content => .textEnd index content message
  | .thinkingStart index => .thinkingStart index message
  | .thinkingDelta index delta => .thinkingDelta index delta message
  | .thinkingEnd index content => .thinkingEnd index content message
  | .toolCallStart index => .toolCallStart index message
  | .toolCallDelta index delta => .toolCallDelta index delta message
  | .toolCallEnd index call => .toolCallEnd index call message

def ensureTextBlock
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (streamIndex : Nat) : StreamingState × Array ParsedStreamEvent × StreamingBlock :=
  match findBlock? state streamIndex with
  | some block => (state, events, block)
  | none =>
      let block : StreamingBlock :=
        { streamIndex := streamIndex
          contentIndex := state.order.size
          kind := .text
        }
      let state := pushBlock state block
      (state, events.push (startEventForBlock block), block)

def ensureThinkingBlock
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (streamIndex : Nat) : StreamingState × Array ParsedStreamEvent × StreamingBlock :=
  match findBlock? state streamIndex with
  | some block => (state, events, block)
  | none =>
      let block : StreamingBlock :=
        { streamIndex := streamIndex
          contentIndex := state.order.size
          kind := .thinking
        }
      let state := pushBlock state block
      (state, events.push (startEventForBlock block), block)

def applyTextDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (streamIndex : Nat)
    (delta : String) : StreamingState × Array ParsedStreamEvent :=
  if delta.isEmpty then
    (state, events)
  else
    let (state, events, block) := ensureTextBlock state events streamIndex
    if block.kind != .text then
      (state, events)
    else
      let block := { block with text := block.text ++ delta }
      (updateBlock state block, events.push (.textDelta block.contentIndex delta))

def applyThinkingSignature
    (state : StreamingState)
    (streamIndex : Nat)
    (signature : String) : StreamingState :=
  if signature.isEmpty then
    state
  else
    match findBlock? state streamIndex with
    | some block =>
        if block.kind != .thinking then
          state
        else
          let current := block.thinkingSignature.getD ""
          updateBlock state { block with thinkingSignature := some (current ++ signature) }
    | none =>
        let (state, _, block) := ensureThinkingBlock state #[] streamIndex
        let current := block.thinkingSignature.getD ""
        updateBlock state { block with thinkingSignature := some (current ++ signature) }

def applyThinkingDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (streamIndex : Nat)
    (delta : String)
    (signature : String := "") : StreamingState × Array ParsedStreamEvent :=
  let (state, events, block) := ensureThinkingBlock state events streamIndex
  if block.kind != .thinking then
    (state, events)
  else
    let block :=
      { block with
        text := block.text ++ delta
        thinkingSignature :=
          if signature.isEmpty then
            block.thinkingSignature
          else
            some (block.thinkingSignature.getD "" ++ signature)
      }
    let state := updateBlock state block
    let events := if delta.isEmpty then events else events.push (.thinkingDelta block.contentIndex delta)
    (state, events)

def applyToolInputDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (streamIndex : Nat)
    (delta : String) : StreamingState × Array ParsedStreamEvent :=
  match findBlock? state streamIndex with
  | some block =>
      if block.kind != .toolCall || delta.isEmpty then
        (state, events)
      else
        let block := { block with partialArguments := block.partialArguments ++ delta }
        (updateBlock state block, events.push (.toolCallDelta block.contentIndex delta))
  | none => (state, events)

def applyContentBlockStart
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (event : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let streamIndex := natFieldD event "contentBlockIndex" state.order.size
  match optionalObjectField event "start" >>= fun start => optionalObjectField start "toolUse" with
  | some toolUse =>
      match findBlock? state streamIndex with
      | some _ => (state, events)
      | none =>
          let block : StreamingBlock :=
            { streamIndex := streamIndex
              contentIndex := state.order.size
              kind := .toolCall
              id := optionalStringField toolUse "toolUseId" |>.getD ""
              name := optionalStringField toolUse "name" |>.getD ""
            }
          let state := pushBlock state block
          (state, events.push (startEventForBlock block))
  | none => (state, events)

def applyContentBlockDelta
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (event : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let streamIndex := natFieldD event "contentBlockIndex" 0
  match optionalObjectField event "delta" with
  | none => (state, events)
  | some delta =>
      let (state, events) :=
        match optionalStringField delta "text" with
        | some text => applyTextDelta state events streamIndex text
        | none => (state, events)
      let (state, events) :=
        match optionalObjectField delta "toolUse" with
        | some toolUse =>
            applyToolInputDelta state events streamIndex (optionalStringField toolUse "input" |>.getD "")
        | none => (state, events)
      match optionalObjectField delta "reasoningContent" with
      | some reasoningContent =>
          let text := optionalStringField reasoningContent "text" |>.getD ""
          let signature := optionalStringField reasoningContent "signature" |>.getD ""
          applyThinkingDelta state events streamIndex text signature
      | none => (state, events)

def applyContentBlockStop
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (event : Lean.Json) : StreamingState × Array ParsedStreamEvent :=
  let streamIndex := natFieldD event "contentBlockIndex" 0
  match findBlock? state streamIndex with
  | none => (state, events)
  | some block =>
      if block.ended then
        (state, events)
      else
        let block := { block with ended := true }
        let state := updateBlock state block
        let event :=
          match block.kind with
          | .text => ParsedStreamEvent.textEnd block.contentIndex block.text
          | .thinking => ParsedStreamEvent.thinkingEnd block.contentIndex block.text
          | .toolCall => ParsedStreamEvent.toolCallEnd block.contentIndex (toolCallFromBlock block)
        (state, events.push event)

def applyMessageStart (state : StreamingState) (event : Lean.Json) : Except String StreamingState := do
  match optionalStringField event "role" with
  | some "assistant" => pure { state with sawMessageStart := true }
  | some role => throw s!"Unexpected assistant message start but got {role} message start instead"
  | none => pure { state with sawMessageStart := true }

def applyMessageStop (state : StreamingState) (event : Lean.Json) : StreamingState :=
  let stopReason := mapStopReason (optionalStringField event "stopReason")
  let errorMessage :=
    if stopReason == .error then
      some "Bedrock returned an error stop reason"
    else
      state.errorMessage
  { state with
    sawMessageStop := true
    stopReason := stopReason
    errorMessage := errorMessage
  }

def applyMetadata (state : StreamingState) (event : Lean.Json) : StreamingState :=
  match optionalObjectField event "usage" with
  | some usage => { state with usage := parseMetadataUsage usage }
  | none => state

def applyStreamItem
    (state : StreamingState)
    (events : Array ParsedStreamEvent)
    (item : Lean.Json) : Except String (StreamingState × Array ParsedStreamEvent) := do
  match optionalObjectField item "messageStart" with
  | some event => pure (← applyMessageStart state event, events)
  | none =>
      match optionalObjectField item "contentBlockStart" with
      | some event => pure (applyContentBlockStart state events event)
      | none =>
          match optionalObjectField item "contentBlockDelta" with
          | some event => pure (applyContentBlockDelta state events event)
          | none =>
              match optionalObjectField item "contentBlockStop" with
              | some event => pure (applyContentBlockStop state events event)
              | none =>
                  match optionalObjectField item "messageStop" with
                  | some event => pure (applyMessageStop state event, events)
                  | none =>
                      match optionalObjectField item "metadata" with
                      | some event => pure (applyMetadata state event, events)
                      | none =>
                          let exceptionNames :=
                            [ "internalServerException"
                            , "modelStreamErrorException"
                            , "validationException"
                            , "throttlingException"
                            , "serviceUnavailableException"
                            ]
                          match exceptionNames.findSome? (fun name =>
                              (optionalObjectField item name).map fun payload => (name, payload)) with
                          | some (name, payload) => throw (formatBedrockStreamError name payload)
                          | none => pure (state, events)

def parseStreamingItems (raw : String) : Except String (Array Lean.Json) := do
  let parsed ← Lean.Json.parse raw
  let items ← parsed.getArr?
  pure items

def parseStreamingEventStream
    (api provider model : String)
    (timestamp : Nat)
    (raw : String) : Except String LeanAgent.AI.AssistantMessageEventStream := do
  let items ← parseStreamingItems raw
  let mut state : StreamingState := {}
  let mut parsedEvents : Array ParsedStreamEvent := #[]
  for item in items do
    let (nextState, nextEvents) ← applyStreamItem state parsedEvents item
    state := nextState
    parsedEvents := nextEvents
  let message := messageFromStreamingState api provider model timestamp state
  let events :=
    #[LeanAgent.AI.AssistantMessageEvent.start message]
      ++ parsedEvents.map (parsedEventToAssistantEvent message)
      ++ #[LeanAgent.AI.completionEvent message]
  pure { events := events, finalResult := message }

def completeStreamWithOptions
    (config : BedrockConverseStreamConfig)
    (model : LeanAgent.AI.ModelRef)
    (input : Array String)
    (modelName : String)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry)
    (reasoning : Bool)
    (context : LeanAgent.AI.Context)
    (options : BedrockOptions := {}) : IO LeanAgent.AI.AssistantMessageEventStream := do
  LeanAgent.AI.Util.Abort.throwIfAborted options.signal
  let requestModel := modelRef config model
  let prepared ← prepareRequestWithOptions
    config
    model
    input
    modelName
    thinkingLevelMap
    reasoning
    context
    options
  let retryPolicy := LeanAgent.AI.Util.Retry.Policy.fromOptions options.maxRetries options.maxRetryDelayMs
  let raw ← LeanAgent.AI.Util.Retry.withRetries retryPolicy
    (runHttpEventStreamJson config requestModel prepared options)
    options.signal
  let timestamp ← IO.monoMsNow
  match parseStreamingEventStream model.api model.provider model.id timestamp raw with
  | .ok stream => pure stream
  | .error err => throw (IO.userError s!"failed to parse Bedrock streaming response: {err}\n{raw}")

end LeanAgent.AI.Api.BedrockConverseStream
