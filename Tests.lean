import LeanAgent

set_option maxRecDepth 2048

open LeanAgent

def fail (message : String) : IO Unit :=
  throw (IO.userError message)

def assertTrue (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else fail message

def headerValue? (headers : Array (String × String)) (name : String) : Option String :=
  headers.findSome? fun (headerName, value) =>
    if headerName == name.toLower then some value else none

def silentSink : EventSink :=
  fun _ => pure ()

def containsToolResult : AgentMessage → Bool
  | .toolResult _ "read" content true => content.contains "hello from lean-agent"
  | _ => false

def fakeProvider : ModelProvider :=
  { complete := fun request => do
      let sawToolResult := request.messages.any containsToolResult
      if sawToolResult then
        pure { content := "done", toolCalls := #[] }
      else
        pure
          { content := ""
            toolCalls :=
              #[ { id := "call-read-1"
                 , name := "read"
                 , arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "fixture.txt")]
                 }
               ]
          }
  }

def testAgentLoopReadsFile : IO Unit := do
  let cwd ← IO.currentDir
  let root := cwd / ".lake" / "lean-agent-test"
  IO.FS.createDirAll root
  IO.FS.writeFile (root / "fixture.txt") "hello from lean-agent\n"
  let messages ← runAgentLoop
    { provider := fakeProvider
      model := "fake"
      system := defaultSystemPrompt
      tools := LeanAgent.CodingTools.defaultTools root
      maxTurns := 4
    }
    #[.user "read the fixture"]
    silentSink
  assertTrue (messages.any containsToolResult) "expected read tool result in transcript"

def testEditTool : IO Unit := do
  let cwd ← IO.currentDir
  let root := cwd / ".lake" / "lean-agent-test-edit"
  IO.FS.createDirAll root
  IO.FS.writeFile (root / "sample.txt") "alpha beta gamma"
  let tool := LeanAgent.CodingTools.makeEditTool root
  let result ← tool.execute
    { id := "edit-1"
      name := "edit"
      arguments :=
        LeanAgent.Json.obj
          [ ("path", LeanAgent.Json.str "sample.txt")
          , ("old", LeanAgent.Json.str "alpha")
          , ("new", LeanAgent.Json.str "omega")
          ]
    }
  let updated ← IO.FS.readFile (root / "sample.txt")
  assertTrue result.ok "edit tool should succeed"
  assertTrue (updated == "omega beta gamma") "edit tool should replace the unique occurrence"

def testEditToolRejectsAmbiguousMatch : IO Unit := do
  let cwd ← IO.currentDir
  let root := cwd / ".lake" / "lean-agent-test-edit-ambiguous"
  IO.FS.createDirAll root
  IO.FS.writeFile (root / "sample.txt") "alpha beta alpha"
  let tool := LeanAgent.CodingTools.makeEditTool root
  let failed ←
    try
      let _ ← tool.execute
        { id := "edit-ambiguous"
          name := "edit"
          arguments :=
            LeanAgent.Json.obj
              [ ("path", LeanAgent.Json.str "sample.txt")
              , ("old", LeanAgent.Json.str "alpha")
              , ("new", LeanAgent.Json.str "omega")
              ]
        }
      pure false
    catch err =>
      assertTrue (err.toString.contains "not unique") "expected ambiguous edit error"
      pure true
  assertTrue failed "ambiguous edit should fail"

def testReadToolRejectsPathEscape : IO Unit :=
  IO.FS.withTempDir fun base => do
    let root := base / "root"
    IO.FS.createDirAll root
    IO.FS.writeFile (base / "outside.txt") "outside"
    let tool := LeanAgent.CodingTools.makeReadTool root
    let failed ←
      try
        let _ ← tool.execute
          { id := "read-escape"
            name := "read"
            arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "../outside.txt")]
          }
        pure false
      catch err =>
        assertTrue (err.toString.contains "escapes working directory") "expected path escape error"
        pure true
    assertTrue failed "path escape should fail"

def testListTool : IO Unit :=
  IO.FS.withTempDir fun root => do
    IO.FS.writeFile (root / "file.txt") "content"
    IO.FS.createDirAll (root / "child")
    let tool := LeanAgent.CodingTools.makeListTool root
    let result ← tool.execute
      { id := "list-1"
        name := "list"
        arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str ".")]
      }
    assertTrue result.ok "list tool should succeed"
    assertTrue (result.content.contains "file.txt") "list should include files"
    assertTrue (result.content.contains "child/") "list should include directories with suffix"

def testBashToolTimeout : IO Unit :=
  IO.FS.withTempDir fun root => do
    let tool := LeanAgent.CodingTools.makeBashTool root
    let result ← tool.execute
      { id := "bash-timeout"
        name := "bash"
        arguments :=
          LeanAgent.Json.obj
            [ ("command", LeanAgent.Json.str "sleep 2")
            , ("timeout_seconds", LeanAgent.Json.nat 1)
            ]
      }
    assertTrue (!result.ok) "timed out bash command should fail"
    assertTrue (result.content.contains "timed out") "timeout result should mention timeout"
    match result.error with
    | some err => assertTrue (err.contains "timed out") "timeout error should mention timeout"
    | none => fail "timeout should set error"

def testProjectCommandExpansion : IO Unit :=
  IO.FS.withTempDir fun root => do
    let commandsDir := root / ".omp" / "commands"
    IO.FS.createDirAll commandsDir
    IO.FS.writeFile (commandsDir / "ship.md")
      (String.intercalate "\n"
        [ "---"
        , "description: Ship a version"
        , "---"
        , "Version: $1"
        , "Tail: $@[2]"
        , "All: $ARGUMENTS"
        ])
    let extensions ← LeanAgent.Project.loadExtensions root
    assertTrue (extensions.commands.any (fun command => command.name == "ship")) "expected project command"
    let expanded := LeanAgent.Project.expandPrompt extensions "/ship \"v 1\" alpha beta"
    assertTrue (expanded.contains "Version: v 1") "expected positional argument expansion"
    assertTrue (expanded.contains "Tail: alpha beta") "expected slice argument expansion"
    assertTrue (expanded.contains "All: \"v 1\" alpha beta") "expected aggregate argument expansion"

def testProjectSkillExpansion : IO Unit :=
  IO.FS.withTempDir fun root => do
    let skillDir := root / ".omp" / "skills" / "compress"
    IO.FS.createDirAll skillDir
    IO.FS.writeFile (skillDir / "SKILL.md")
      (String.intercalate "\n"
        [ "---"
        , "name: compress"
        , "description: Compress prompts"
        , "---"
        , "# Compress"
        , "Remove filler."
        ])
    let extensions ← LeanAgent.Project.loadExtensions root
    assertTrue (extensions.skills.any (fun skill => skill.name == "compress")) "expected project skill"
    let expanded := LeanAgent.Project.expandPrompt extensions "/skill:compress summarize this document"
    assertTrue (expanded.contains "# Skill: compress") "expected skill header"
    assertTrue (expanded.contains "Remove filler.") "expected skill body"
    assertTrue (expanded.contains "summarize this document") "expected skill task"

def testSessionJsonlRoundTrip : IO Unit :=
  IO.FS.withTempDir fun root => do
    let path := root / "session.jsonl"
    LeanAgent.Session.ensureSessionFile path root "fake-model"
    let userMessage := AgentMessage.user "hello"
    let assistantMessage := AgentMessage.assistant "world" #[]
    let store ← LeanAgent.Session.persistMessages
      (some { path := path, lastEntryId := none })
      #[userMessage, assistantMessage]
    let (messages, lastId) ← LeanAgent.Session.loadMessagesWithLastId path
    assertTrue (messages.size == 2) "expected persisted messages"
    assertTrue lastId.isSome "expected last entry id"
    assertTrue store.isSome "expected updated store"
    match messages[0]?, messages[1]? with
    | some (AgentMessage.user "hello"), some (AgentMessage.assistant "world" calls) =>
        assertTrue calls.isEmpty "expected assistant calls to round-trip"
    | _, _ => fail "expected user and assistant messages"
    let content ← IO.FS.readFile path
    assertTrue (content.contains "\"type\":\"session\"") "expected session header"
    assertTrue (content.contains "\"type\":\"message\"") "expected message entries"

def testSessionResourceCleanups : IO Unit := do
  let seen ← IO.mkRef (#[] : Array String)
  let unregisterA ← LeanAgent.AI.SessionResources.registerSessionResourceCleanup fun sessionId =>
    seen.modify (fun entries => entries.push ("a:" ++ sessionId.getD "none"))
  let unregisterB ← LeanAgent.AI.SessionResources.registerSessionResourceCleanup fun sessionId =>
    seen.modify (fun entries => entries.push ("b:" ++ sessionId.getD "none"))
  LeanAgent.AI.SessionResources.cleanupSessionResources (some "s1")
  assertTrue ((← seen.get) == #["a:s1", "b:s1"]) "expected registered cleanups to run in order"
  unregisterA
  seen.set #[]
  LeanAgent.AI.SessionResources.cleanupSessionResources (some "s2")
  assertTrue ((← seen.get) == #["b:s2"]) "expected unregistered cleanup to be skipped"
  unregisterB

def testSessionResourceCleanupAggregatesErrors : IO Unit := do
  let seen ← IO.mkRef (#[] : Array String)
  let unregisterFail ← LeanAgent.AI.SessionResources.registerSessionResourceCleanup fun _ =>
    throw (IO.userError "first cleanup failed")
  let unregisterOk ← LeanAgent.AI.SessionResources.registerSessionResourceCleanup fun sessionId =>
    seen.modify (fun entries => entries.push ("ok:" ++ sessionId.getD "none"))
  let unregisterFailAgain ← LeanAgent.AI.SessionResources.registerSessionResourceCleanup fun _ =>
    throw (IO.userError "second cleanup failed")
  let failed ←
    try
      LeanAgent.AI.SessionResources.cleanupSessionResources none
      pure false
    catch err =>
      let message := err.toString
      assertTrue (message.contains "Failed to cleanup session resources")
        "expected aggregate cleanup failure message"
      assertTrue (message.contains "first cleanup failed") "expected first cleanup error"
      assertTrue (message.contains "second cleanup failed") "expected second cleanup error"
      pure true
  assertTrue failed "expected cleanup aggregate failure"
  assertTrue ((← seen.get) == #["ok:none"]) "expected cleanup after failing callback to still run"
  unregisterFail
  unregisterOk
  unregisterFailAgain

def testOpenAIAssistantOmitsEmptyToolCalls : IO Unit := do
  let json := LeanAgent.OpenAI.messageToJson (AgentMessage.assistant "done" #[])
  assertTrue (LeanAgent.Json.optVal? json "tool_calls" == none) "empty tool_calls should be omitted"

def noopTool : AgentTool :=
  { name := "read"
    description := "Read a file"
    inputSchema := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
    execute := fun call =>
      pure
        { toolCallId := call.id
          name := call.name
          ok := true
          content := ""
        }
  }

def basicProviderRequest (tools : Array AgentTool := #[]) (messages : Array AgentMessage := #[.user "hello"]) :
    ProviderRequest :=
  { model := "model"
    system := "system"
    messages := messages
    tools := tools
  }

def testOpenAICompletionsOmitsEmptyTools : IO Unit := do
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions (basicProviderRequest)
  assertTrue (LeanAgent.Json.optVal? json "tools" == none) "empty tools should be omitted"
  assertTrue (LeanAgent.Json.optVal? json "tool_choice" == none) "tool_choice should be omitted without tools"

def testOpenAICompletionsIncludesToolsWhenPresent : IO Unit := do
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions (basicProviderRequest #[noopTool])
  match LeanAgent.Json.optVal? json "tools" with
  | some value =>
      match value.getArr? with
      | .ok tools => assertTrue (tools.size == 1) "expected one serialized tool"
      | .error _ => fail "expected tools array"
  | none => fail "expected tools field"
  assertTrue (LeanAgent.Json.optVal? json "tool_choice" == some (LeanAgent.Json.str "auto")) "expected auto tool choice"

def testOpenAICompletionsIncludesEmptyToolsForToolHistory : IO Unit := do
  let toolCall : ToolCall :=
    { id := "call-1"
      name := "read"
      arguments := LeanAgent.Json.obj []
    }
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest #[] #[.assistant "" #[toolCall]])
  match LeanAgent.Json.optVal? json "tools" with
  | some value =>
      match value.getArr? with
      | .ok tools => assertTrue tools.isEmpty "expected empty tools array for tool history"
      | .error _ => fail "expected tools array"
  | none => fail "expected tools field for tool history"
  assertTrue (LeanAgent.Json.optVal? json "tool_choice" == some (LeanAgent.Json.str "auto")) "expected tool choice for tool history"

def testOpenAICompletionsSerializesOptions : IO Unit := do
  let options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
    { temperature := some 1.0
      maxTokens := some 123
      reasoningEffort := some .xhigh
      toolChoice := some .required
    }
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions (basicProviderRequest #[noopTool]) options
  assertTrue (LeanAgent.Json.optVal? json "temperature" |>.isSome) "expected temperature"
  assertTrue (LeanAgent.Json.optVal? json "max_tokens" == some (LeanAgent.Json.nat 123)) "expected max_tokens"
  assertTrue
    (LeanAgent.Json.optVal? json "reasoning_effort" == some (LeanAgent.Json.str "high"))
    "expected xhigh to clamp to high"
  assertTrue (LeanAgent.Json.optVal? json "tool_choice" == some (LeanAgent.Json.str "required")) "expected required tool choice"

def testOpenAICompletionsUsesMappedReasoningEffort : IO Unit := do
  let options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
    { reasoningEffort := some .xhigh
      reasoningEffortValue := some "max"
    }
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions (basicProviderRequest) options
  assertTrue
    (LeanAgent.Json.optVal? json "reasoning_effort" == some (LeanAgent.Json.str "max"))
    "expected mapped xhigh reasoning effort"
  let offJson := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest)
    { offReasoningEffortValue := some "none" }
  assertTrue
    (LeanAgent.Json.optVal? offJson "reasoning_effort" == some (LeanAgent.Json.str "none"))
    "expected mapped off reasoning effort"

def testOpenAICompletionsPromptCacheKey : IO Unit := do
  let options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
    { sessionId := some "session-123" }
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest)
    options
    LeanAgent.Models.openAIBaseUrl
  assertTrue
    (LeanAgent.Json.optVal? json "prompt_cache_key" == some (LeanAgent.Json.str "session-123"))
    "expected prompt cache key"
  assertTrue (LeanAgent.Json.optVal? json "prompt_cache_retention" == none) "expected no prompt cache retention"

def testOpenAICompletionsPromptCacheLongRetention : IO Unit := do
  let options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
    { cacheRetention := some .long
      sessionId := some "session-456"
    }
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest)
    options
    LeanAgent.Models.openAIBaseUrl
  assertTrue
    (LeanAgent.Json.optVal? json "prompt_cache_key" == some (LeanAgent.Json.str "session-456"))
    "expected prompt cache key for long retention"
  assertTrue
    (LeanAgent.Json.optVal? json "prompt_cache_retention" == some (LeanAgent.Json.str "24h"))
    "expected 24h prompt cache retention"

def testOpenAICompletionsPromptCacheClampsKey : IO Unit := do
  let longSession := String.ofList (List.replicate 67 'x')
  let expected := String.ofList (List.replicate 64 'x')
  let options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
    { sessionId := some longSession }
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest)
    options
    LeanAgent.Models.openAIBaseUrl
  assertTrue
    (LeanAgent.Json.optVal? json "prompt_cache_key" == some (LeanAgent.Json.str expected))
    "expected clamped prompt cache key"

def testOpenAICompletionsPromptCacheNoneOmitsFields : IO Unit := do
  let options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
    { cacheRetention := some .none
      sessionId := some "session-789"
    }
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest)
    options
    LeanAgent.Models.openAIBaseUrl
  assertTrue (LeanAgent.Json.optVal? json "prompt_cache_key" == none) "expected no prompt cache key"
  assertTrue (LeanAgent.Json.optVal? json "prompt_cache_retention" == none) "expected no prompt cache retention"

def testOpenAICompletionsPromptCacheEnvLongRetention : IO Unit := do
  let options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
    { sessionId := some "session-env"
      env := #[("PI_CACHE_RETENTION", "long")]
    }
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest)
    options
    LeanAgent.Models.openAIBaseUrl
  assertTrue
    (LeanAgent.Json.optVal? json "prompt_cache_key" == some (LeanAgent.Json.str "session-env"))
    "expected env prompt cache key"
  assertTrue
    (LeanAgent.Json.optVal? json "prompt_cache_retention" == some (LeanAgent.Json.str "24h"))
    "expected env 24h prompt cache retention"

def testSSEParsesDataEvents : IO Unit := do
  let raw := ": keepalive\n" ++
    "data: {\"a\":1}\n" ++
    "data: {\"b\":2}\n\n" ++
    "event: ignored\n" ++
    "data: [DONE]\n\n"
  let events := LeanAgent.AI.Util.SSE.parse raw
  assertTrue (events.size == 2) "expected two SSE data events"
  match events[0]?, events[1]? with
  | some first, some second =>
      assertTrue (first.data == "{\"a\":1}\n{\"b\":2}") "expected multiline data join"
      assertTrue (second.data == "[DONE]") "expected DONE data"
  | _, _ => fail "expected SSE events"

def testOpenAICompletionsStreamingPayload : IO Unit := do
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithOptions
    (basicProviderRequest)
    {}
    LeanAgent.Models.openAIBaseUrl
  assertTrue (LeanAgent.Json.optVal? json "stream" == some (LeanAgent.Json.bool true)) "expected stream flag"
  match LeanAgent.Json.optVal? json "stream_options" with
  | some options =>
      assertTrue
        (LeanAgent.Json.optVal? options "include_usage" == some (LeanAgent.Json.bool true))
        "expected streaming usage option"
  | none => fail "expected stream_options"

def testOpenAICompletionsParsesStreamingText : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"id\":\"chatcmpl-1\",\"model\":\"deepseek-v4-flash\",\"choices\":[{\"delta\":{\"content\":\"hel\"},\"finish_reason\":null}]}"
    , ""
    , "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":2}}"
    , ""
    , "data: [DONE]"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAICompletions.parseStreamingEventStream
    "openai-completions" "deepseek" "deepseek-v4-flash" 10 raw with
  | .ok stream =>
      assertTrue stream.isComplete "expected complete stream"
      assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "hello") "expected streamed text"
      assertTrue (stream.result.usage.totalTokens == 5) "expected streamed usage"
      assertTrue
        (stream.events.any fun
          | .textDelta _ "hel" _ => true
          | _ => false)
        "expected first text delta"
      assertTrue
        (stream.events.any fun
          | .textDelta _ "lo" _ => true
          | _ => false)
        "expected second text delta"
  | .error err => fail s!"streaming text parse failed: {err}"

def testOpenAICompletionsParsesStreamingToolCall : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\"}}]},\"finish_reason\":null}]}"
    , ""
    , "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"README.md\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}"
    , ""
    , "data: [DONE]"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAICompletions.parseStreamingEventStream
    "openai-completions" "deepseek" "deepseek-v4-flash" 10 raw with
  | .ok stream =>
      assertTrue (stream.result.stopReason == .toolUse) "expected tool-use stop reason"
      let calls := LeanAgent.AI.contentToolCalls stream.result.content
      assertTrue (calls.size == 1) "expected one streamed tool call"
      match calls[0]? with
      | some call =>
          assertTrue (call.id == "call-1") "expected streamed tool id"
          assertTrue (call.name == "read") "expected streamed tool name"
          assertTrue
            (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected streamed tool args"
      | none => fail "expected tool call"
      assertTrue
        (stream.events.any fun
          | .toolCallDelta _ _ _ => true
          | _ => false)
        "expected tool-call delta"
  | .error err => fail s!"streaming tool parse failed: {err}"

def testOpenAICompletionsParsesStreamingThinking : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"think\"},\"finish_reason\":null}]}"
    , ""
    , "data: {\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":\"stop\"}]}"
    , ""
    , "data: [DONE]"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAICompletions.parseStreamingEventStream
    "openai-completions" "deepseek" "deepseek-v4-flash" 10 raw with
  | .ok stream =>
      assertTrue
        (stream.events.any fun
          | .thinkingDelta _ "think" _ => true
          | _ => false)
        "expected thinking delta"
      assertTrue
        (stream.result.content.any fun
          | .thinking content => content.thinking == "think" && content.thinkingSignature == some "reasoning_content"
          | _ => false)
        "expected thinking block"
  | .error err => fail s!"streaming thinking parse failed: {err}"

def transformTarget : LeanAgent.AI.Api.TransformMessages.TargetModel :=
  { id := "claude-sonnet-4.6"
    provider := "github-copilot"
    api := "anthropic-messages"
    input := #["text"]
  }

def anthropicToolCallId
    (id : String)
    (_target : LeanAgent.AI.Api.TransformMessages.TargetModel)
    (_source : LeanAgent.AI.AssistantMessage) : String :=
  LeanAgent.AI.Api.TransformMessages.sanitizeToolCallId id

def responsesCodexModel : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel :=
  { id := "gpt-5.5"
    provider := "openai-codex"
    api := "openai-responses"
    input := #["text"]
    reasoning := true
    supportsDeveloperRole := true
  }

def azureResponsesModel : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel :=
  { id := "gpt-4o-mini"
    provider := "azure-openai-responses"
    api := "azure-openai-responses"
    input := #["text", "image"]
    contextWindow := 128000
    maxTokens := 16384
  }

def jsonStringField? (json : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? json key with
  | some (.str value) => some value
  | _ => none

def responseItemWithType? (items : Array Lean.Json) (itemType : String) : Option Lean.Json :=
  items.find? fun item => jsonStringField? item "type" == some itemType

def headerValueCaseInsensitive? (headers : Array (String × String)) (name : String) : Option String :=
  headers.findSome? fun (headerName, value) =>
    if headerName.toLower == name.toLower then some value else none

def testTransformMessagesCrossModelHandoff : IO Unit := do
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .thinking { thinking := "private reasoning", thinkingSignature := some "sig" }
         , .thinking { thinking := "encrypted", redacted := true }
         , .text { text := "answer", textSignature := some "text-sig" }
         , .toolCall
            { id := "call_123|fc_123"
              name := "bash"
              arguments := LeanAgent.Json.obj [("command", LeanAgent.Json.str "pwd")]
              thoughtSignature := some "encrypted-tool-thought"
            }
         ]
      api := "openai-responses"
      provider := "github-copilot"
      model := "gpt-5"
      stopReason := .toolUse
      timestamp := 2
    }
  let messages : Array LeanAgent.AI.Message :=
    #[ .user { content := #[LeanAgent.AI.text "run a command"], timestamp := 1 }
     , .assistant assistant
     , .toolResult
        { toolCallId := "call_123|fc_123"
          toolName := "bash"
          content := #[LeanAgent.AI.text "output"]
          isError := false
          timestamp := 3
        }
     ]
  let result := LeanAgent.AI.Api.TransformMessages.transformMessages messages transformTarget
    { normalizeToolCallId? := some anthropicToolCallId }
  assertTrue (result.size == 3) "expected no synthetic result when normalized tool result is present"
  match result[1]? with
  | some (LeanAgent.AI.Message.assistant transformed) =>
      assertTrue
        (transformed.content.any fun
          | .text content => content.text == "private reasoning"
          | _ => false)
        "expected cross-model thinking to become text"
      assertTrue
        (!transformed.content.any fun
          | .thinking _ => true
          | _ => false)
        "expected cross-model thinking blocks to be removed"
      assertTrue
        (transformed.content.any fun
          | .text content => content.text == "answer" && content.textSignature.isNone
          | _ => false)
        "expected cross-model text signatures to be dropped"
      match (LeanAgent.AI.contentToolCalls transformed.content)[0]? with
      | some call =>
          assertTrue (call.id == "call_123_fc_123") "expected normalized tool id"
          assertTrue call.thoughtSignature.isNone "expected foreign thought signature to be removed"
      | none => fail "expected transformed tool call"
  | _ => fail "expected transformed assistant"
  match result[2]? with
  | some (LeanAgent.AI.Message.toolResult toolResult) =>
      assertTrue (toolResult.toolCallId == "call_123_fc_123") "expected tool result id to follow normalized call id"
  | _ => fail "expected transformed tool result"

def testTransformMessagesAddsSyntheticToolResults : IO Unit := do
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall { id := "call_1|fc_1", name := "read", arguments := LeanAgent.Json.obj [] }
         , .toolCall { id := "call_2|fc_2", name := "bash", arguments := LeanAgent.Json.obj [] }
         ]
      api := "openai-responses"
      provider := "github-copilot"
      model := "gpt-5"
      stopReason := .toolUse
      timestamp := 2
    }
  let messages : Array LeanAgent.AI.Message :=
    #[ .user { content := #[LeanAgent.AI.text "run commands"], timestamp := 1 }
     , .assistant assistant
     , .toolResult
        { toolCallId := "call_1|fc_1"
          toolName := "read"
          content := #[LeanAgent.AI.text "done"]
          isError := false
          timestamp := 3
        }
     ]
  let result := LeanAgent.AI.Api.TransformMessages.transformMessages messages transformTarget
    { normalizeToolCallId? := some anthropicToolCallId
      syntheticTimestamp := 999
    }
  let synthetic :=
    result.filter fun message =>
      match message with
      | .toolResult toolResult => toolResult.isError
      | _ => false
  assertTrue (synthetic.size == 1) "expected exactly one synthetic tool result"
  match synthetic[0]? with
  | some (LeanAgent.AI.Message.toolResult toolResult) =>
      assertTrue (toolResult.toolCallId == "call_2_fc_2") "expected synthetic result for missing normalized id"
      assertTrue (toolResult.toolName == "bash") "expected synthetic result tool name"
      assertTrue (toolResult.timestamp == 999) "expected configured synthetic timestamp"
      assertTrue (LeanAgent.AI.contentPlainText toolResult.content == "No result provided")
        "expected synthetic no-result text"
  | _ => fail "expected synthetic tool result"

def testTransformMessagesDowngradesUnsupportedImages : IO Unit := do
  let messages : Array LeanAgent.AI.Message :=
    #[ .user
        { content :=
            #[ LeanAgent.AI.image "a" "image/png"
             , LeanAgent.AI.image "b" "image/png"
             , LeanAgent.AI.text "describe"
             , LeanAgent.AI.image "c" "image/png"
             ]
          timestamp := 1
        }
     , .toolResult
        { toolCallId := "call-1"
          toolName := "read"
          content := #[LeanAgent.AI.image "tool" "image/png"]
          isError := false
          timestamp := 2
        }
     ]
  let result := LeanAgent.AI.Api.TransformMessages.transformMessages messages transformTarget
  match result[0]? with
  | some (LeanAgent.AI.Message.user user) =>
      assertTrue (user.content.size == 3) "expected adjacent user images to coalesce into one placeholder"
      assertTrue
        (LeanAgent.AI.contentPlainText user.content ==
          "(image omitted: model does not support images)\ndescribe\n(image omitted: model does not support images)")
        "expected user image placeholders"
  | _ => fail "expected transformed user message"
  match result[1]? with
  | some (LeanAgent.AI.Message.toolResult toolResult) =>
      assertTrue
        (LeanAgent.AI.contentPlainText toolResult.content ==
          "(tool image omitted: model does not support images)")
        "expected tool image placeholder"
  | _ => fail "expected transformed tool result"

def testTransformMessagesSkipsErroredAssistant : IO Unit := do
  let errored : LeanAgent.AI.AssistantMessage :=
    { content := #[.toolCall { id := "call-error", name := "read", arguments := LeanAgent.Json.obj [] }]
      api := "openai-responses"
      provider := "github-copilot"
      model := "gpt-5"
      stopReason := .error
      errorMessage := some "aborted by provider"
      timestamp := 2
    }
  let result := LeanAgent.AI.Api.TransformMessages.transformMessages
    #[ .user { content := #[LeanAgent.AI.text "read"], timestamp := 1 }
     , .assistant errored
     , .user { content := #[LeanAgent.AI.text "continue"], timestamp := 3 }
     ]
    transformTarget
  assertTrue
    (!result.any fun
      | .assistant _ => true
      | _ => false)
    "expected errored assistant to be skipped"
  assertTrue
    (!result.any fun
      | .toolResult _ => true
      | _ => false)
    "expected skipped errored assistant not to create synthetic results"

def testOpenAIResponsesSharedNormalizesForeignToolCallIds : IO Unit := do
  let rawCallId := "call_4VnzVawQXPB9MgYib7CiQFEY"
  let rawItemId := "I9b95oN1wD/cHXKTw3PpRkL6KkCtzTJhUxMouMWYwHeTo2j3htzfSk7YPx2vifiIM4g3A8XXyOj8q4Bt6SLUG7gqY1E3ELkrkVQNHglRfUmWj84lqxJY+Puieb3VKyX0FB+83TUzn91cDMF"
  let rawToolCallId := rawCallId ++ "|" ++ rawItemId
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall
            { id := rawToolCallId
              name := "edit"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "src/styles/app.css")]
            }
         ]
      api := "openai-responses"
      provider := "github-copilot"
      model := "gpt-5.5"
      stopReason := .toolUse
      timestamp := 2
    }
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "You are concise."
      messages :=
        #[ .user { content := #[LeanAgent.AI.text "Use the tool."], timestamp := 1 }
         , .assistant assistant
         , .toolResult
            { toolCallId := rawToolCallId
              toolName := "edit"
              content := #[LeanAgent.AI.text "ok"]
              isError := false
              timestamp := 3
            }
         ]
    }
  let input := LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesMessages responsesCodexModel context
  match input[0]? with
  | some systemItem =>
      assertTrue (jsonStringField? systemItem "role" == some "developer") "expected developer system role"
      assertTrue (jsonStringField? systemItem "content" == some "You are concise.") "expected system prompt content"
  | none => fail "expected system item"
  let expectedItemId := "fc_" ++ LeanAgent.AI.Util.Hash.shortHash rawItemId
  match responseItemWithType? input "function_call" with
  | some functionCall =>
      assertTrue (jsonStringField? functionCall "call_id" == some rawCallId) "expected normalized call id"
      assertTrue (jsonStringField? functionCall "id" == some expectedItemId) "expected foreign item id hash"
      assertTrue (expectedItemId.length <= 64) "expected bounded item id"
      assertTrue (expectedItemId.startsWith "fc_") "expected fc item id prefix"
  | none => fail "expected function_call item"
  match responseItemWithType? input "function_call_output" with
  | some output =>
      assertTrue (jsonStringField? output "call_id" == some rawCallId) "expected output call id to match call"
      assertTrue (jsonStringField? output "output" == some "ok") "expected text tool output"
  | none => fail "expected function_call_output item"

def testOpenAIResponsesSharedOmitsDifferentModelFcItemId : IO Unit := do
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall
            { id := "call_1|fc_existing"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
            }
         ]
      api := "openai-responses"
      provider := "openai-codex"
      model := "gpt-5.4"
      stopReason := .toolUse
      timestamp := 2
    }
  let context : LeanAgent.AI.Context :=
    { messages :=
        #[ .user { content := #[LeanAgent.AI.text "read"], timestamp := 1 }
         , .assistant assistant
         ]
    }
  let input := LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesMessages responsesCodexModel context
  match responseItemWithType? input "function_call" with
  | some functionCall =>
      assertTrue (jsonStringField? functionCall "call_id" == some "call_1") "expected call id"
      assertTrue (LeanAgent.Json.optVal? functionCall "id" == none) "expected different-model fc item id to be omitted"
  | none => fail "expected function_call item"

def testOpenAIResponsesSharedConvertsTools : IO Unit := do
  let tool : LeanAgent.AI.Tool :=
    { name := "read"
      description := "Read a file"
      parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
    }
  let tools := LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesTools #[tool] (some true)
  match tools[0]? with
  | some encoded =>
      assertTrue (jsonStringField? encoded "type" == some "function") "expected function tool"
      assertTrue (jsonStringField? encoded "name" == some "read") "expected tool name"
      assertTrue (LeanAgent.Json.optVal? encoded "strict" == some (LeanAgent.Json.bool true)) "expected strict flag"
  | none => fail "expected encoded tool"

def testGitHubCopilotDynamicHeaders : IO Unit := do
  let userOnly : Array LeanAgent.AI.Message :=
    #[.user { content := #[LeanAgent.AI.text "hi"], timestamp := 1 }]
  assertTrue
    (LeanAgent.AI.Api.GitHubCopilotHeaders.inferCopilotInitiator userOnly == "user")
    "expected user-initiated Copilot request"
  let toolEnded : Array LeanAgent.AI.Message :=
    userOnly.push
      (.toolResult
        { toolCallId := "call-1"
          toolName := "render"
          content := #[LeanAgent.AI.image "base64" "image/png"]
          isError := false
          timestamp := 2
        })
  assertTrue
    (LeanAgent.AI.Api.GitHubCopilotHeaders.inferCopilotInitiator toolEnded == "agent")
    "expected agent-initiated Copilot request after tool result"
  assertTrue
    (LeanAgent.AI.Api.GitHubCopilotHeaders.hasCopilotVisionInput toolEnded)
    "expected Copilot vision input detection"
  let headers := LeanAgent.AI.Api.GitHubCopilotHeaders.buildCopilotDynamicHeaders toolEnded true
  assertTrue (headerValueCaseInsensitive? headers "X-Initiator" == some "agent") "expected X-Initiator header"
  assertTrue (headerValueCaseInsensitive? headers "Openai-Intent" == some "conversation-edits") "expected Openai-Intent header"
  assertTrue (headerValueCaseInsensitive? headers "Copilot-Vision-Request" == some "true") "expected vision header"

def testOpenAIResponsesRequestPayload : IO Unit := do
  let longSession := String.ofList (List.replicate 67 'x')
  let expectedSession := String.ofList (List.replicate 64 'x')
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "Be concise."
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      tools :=
        #[ { name := "read"
             description := "Read a file"
             parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
           }
         ]
    }
  let payload := LeanAgent.AI.Api.OpenAIResponses.requestToJsonWithOptions
    responsesCodexModel
    context
    { maxTokens := some 123
      temperature := some 0.2
      sessionId := some longSession
      cacheRetention := some .long
      reasoningEffort := some .high
      serviceTier := some "flex"
    }
  assertTrue (jsonStringField? payload "model" == some "gpt-5.5") "expected responses model id"
  assertTrue (LeanAgent.Json.optVal? payload "stream" == some (LeanAgent.Json.bool false)) "expected non-stream request"
  assertTrue (LeanAgent.Json.optVal? payload "store" == some (LeanAgent.Json.bool false)) "expected store=false"
  assertTrue (jsonStringField? payload "prompt_cache_key" == some expectedSession) "expected clamped cache key"
  assertTrue (jsonStringField? payload "prompt_cache_retention" == some "24h") "expected long cache retention"
  assertTrue (LeanAgent.Json.optVal? payload "max_output_tokens" == some (LeanAgent.Json.nat 123))
    "expected max output tokens"
  assertTrue (jsonStringField? payload "service_tier" == some "flex") "expected service tier"
  assertTrue (LeanAgent.Json.optVal? payload "temperature" |>.isSome) "expected temperature"
  match LeanAgent.Json.optVal? payload "reasoning" with
  | some reasoning =>
      assertTrue (jsonStringField? reasoning "effort" == some "high") "expected reasoning effort"
      assertTrue (jsonStringField? reasoning "summary" == some "auto") "expected default reasoning summary"
  | none => fail "expected reasoning object"
  match LeanAgent.Json.optVal? payload "tools" with
  | some tools =>
      match tools.getArr? with
      | .ok arr => assertTrue (arr.size == 1) "expected one responses tool"
      | .error _ => fail "expected tools array"
  | none => fail "expected tools"

def testOpenAIResponsesRequestUsesThinkingLevelMap : IO Unit := do
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "Be concise."
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
    }
  let mappedModel :=
    { responsesCodexModel with
      thinkingLevelMap := #[{ level := .level .xhigh, mapped := some "max" }]
    }
  let mappedPayload := LeanAgent.AI.Api.OpenAIResponses.requestToJsonWithOptions
    mappedModel
    context
    { reasoningEffort := some .xhigh }
  match LeanAgent.Json.optVal? mappedPayload "reasoning" with
  | some reasoning =>
      assertTrue (jsonStringField? reasoning "effort" == some "max") "expected mapped xhigh effort"
      assertTrue (jsonStringField? reasoning "summary" == some "auto") "expected default reasoning summary"
  | none => fail "expected mapped reasoning object"
  let offNullPayload := LeanAgent.AI.Api.OpenAIResponses.requestToJsonWithOptions
    { responsesCodexModel with thinkingLevelMap := #[{ level := .off, mapped := none }] }
    context
    {}
  assertTrue
    (LeanAgent.Json.optVal? offNullPayload "reasoning" == none)
    "expected off=null to suppress reasoning object"
  let offMappedPayload := LeanAgent.AI.Api.OpenAIResponses.requestToJsonWithOptions
    { responsesCodexModel with thinkingLevelMap := #[{ level := .off, mapped := some "none" }] }
    context
    {}
  match LeanAgent.Json.optVal? offMappedPayload "reasoning" with
  | some reasoning =>
      assertTrue (jsonStringField? reasoning "effort" == some "none") "expected mapped off effort"
  | none => fail "expected mapped off reasoning object"
  let copilotPayload := LeanAgent.AI.Api.OpenAIResponses.requestToJsonWithOptions
    { responsesCodexModel with provider := "github-copilot" }
    context
    {}
  assertTrue
    (LeanAgent.Json.optVal? copilotPayload "reasoning" == none)
    "expected GitHub Copilot default request to omit reasoning object"

def testOpenAIResponsesRequestClampsMaxTokens : IO Unit := do
  let model :=
    { responsesCodexModel with
      contextWindow := 5000
      maxTokens := 4000
    }
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "abcd"
      messages := #[.user { content := #[LeanAgent.AI.text "abcd"], timestamp := 1 }]
    }
  let payload := LeanAgent.AI.Api.OpenAIResponses.requestToJsonWithOptions model context {}
  assertTrue
    (LeanAgent.Json.optVal? payload "max_output_tokens" == some (LeanAgent.Json.nat 902))
    "expected Responses max_output_tokens to be context-clamped"

def assertAzureBaseUrl (input expected : String) : IO Unit :=
  match LeanAgent.AI.Api.AzureOpenAIResponses.normalizeAzureBaseUrl input with
  | .ok actual => assertTrue (actual == expected) s!"expected Azure base URL {expected}, got {actual}"
  | .error err => fail s!"expected Azure base URL normalization to succeed: {err}"

def testAzureOpenAIResponsesBaseUrlNormalization : IO Unit := do
  assertAzureBaseUrl
    "https://my-resource.cognitiveservices.azure.com"
    "https://my-resource.cognitiveservices.azure.com/openai/v1"
  assertAzureBaseUrl
    "https://my-resource.ai.azure.com"
    "https://my-resource.ai.azure.com/openai/v1"
  assertAzureBaseUrl
    "https://my-resource.openai.azure.com/openai"
    "https://my-resource.openai.azure.com/openai/v1"
  assertAzureBaseUrl
    "https://my-resource.openai.azure.com/openai/v1"
    "https://my-resource.openai.azure.com/openai/v1"
  assertAzureBaseUrl
    "https://my-resource.services.ai.azure.com/openai/v1/responses"
    "https://my-resource.services.ai.azure.com/openai/v1"
  assertAzureBaseUrl
    "https://my-resource.openai.azure.com/openai?api-version=2024-12-01"
    "https://my-resource.openai.azure.com/openai/v1"
  assertAzureBaseUrl
    "https://my-proxy.example.com/v1?custom=true"
    "https://my-proxy.example.com/v1?custom=true"
  match LeanAgent.AI.Api.AzureOpenAIResponses.normalizeAzureBaseUrl "not-a-url" with
  | .ok _ => fail "expected invalid Azure base URL to fail"
  | .error err =>
      assertTrue (err.contains "Invalid Azure OpenAI base URL") "expected invalid URL message"

def testAzureOpenAIResponsesConfigAndDeployment : IO Unit := do
  let resolved ← LeanAgent.AI.Api.AzureOpenAIResponses.resolveAzureConfig
    { apiKey := "azure-key" }
    { env :=
        #[ ("AZURE_OPENAI_RESOURCE_NAME", "my-resource")
         , ("AZURE_OPENAI_API_VERSION", "2025-01-01")
         ]
    }
  assertTrue
    (resolved.baseUrl == "https://my-resource.openai.azure.com/openai/v1")
    "expected Azure resource-name base URL"
  assertTrue (resolved.apiVersion == "2025-01-01") "expected Azure API version env"
  let deployment ← LeanAgent.AI.Api.AzureOpenAIResponses.resolveDeploymentName
    azureResponsesModel
    { env := #[("AZURE_OPENAI_DEPLOYMENT_NAME_MAP", "gpt-4o-mini=mini-deploy,gpt-5=gpt5-deploy")] }
  assertTrue (deployment == "mini-deploy") "expected deployment-name env map"

def testAzureOpenAIResponsesRequestPayload : IO Unit := do
  let longSession := String.ofList (List.replicate 67 'x')
  let expectedSession := String.ofList (List.replicate 64 'x')
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "Be concise."
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      tools :=
        #[ { name := "read"
             description := "Read a file"
             parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
           }
         ]
    }
  let payload := LeanAgent.AI.Api.AzureOpenAIResponses.requestToJsonWithOptions
    azureResponsesModel
    context
    { maxTokens := some 321
      temperature := some 0.4
      sessionId := some longSession
    }
    "mini-deploy"
    true
  assertTrue (jsonStringField? payload "model" == some "mini-deploy")
    "expected Azure deployment name in model field"
  assertTrue (LeanAgent.Json.optVal? payload "stream" == some (LeanAgent.Json.bool true))
    "expected Azure stream payload"
  assertTrue (LeanAgent.Json.optVal? payload "store" == some (LeanAgent.Json.bool false))
    "expected Azure store=false"
  assertTrue (jsonStringField? payload "prompt_cache_key" == some expectedSession)
    "expected Azure prompt cache key clamp"
  assertTrue (LeanAgent.Json.optVal? payload "prompt_cache_retention" == none)
    "expected Azure payload to omit prompt cache retention"
  assertTrue (LeanAgent.Json.optVal? payload "max_output_tokens" == some (LeanAgent.Json.nat 321))
    "expected Azure max output tokens"
  match LeanAgent.Json.optVal? payload "tools" with
  | some tools =>
      match tools.getArr? with
      | .ok arr => assertTrue (arr.size == 1) "expected one Azure Responses tool"
      | .error _ => fail "expected Azure tools array"
  | none => fail "expected Azure tools"

def testOpenAIResponsesServiceTierCostMultiplier : IO Unit := do
  let usage : LeanAgent.AI.Usage := { input := 1000000, output := 1000000, totalTokens := 2000000 }
  let model :=
    { responsesCodexModel with
      cost := { input := 1.0, output := 2.0 }
    }
  let priority := LeanAgent.AI.Api.OpenAIResponses.applyUsageCost model (some "priority") usage
  assertTrue (priority.cost.input == 2.5) "expected gpt-5.5 priority input multiplier"
  assertTrue (priority.cost.output == 5.0) "expected gpt-5.5 priority output multiplier"
  assertTrue (priority.cost.total == 7.5) "expected gpt-5.5 priority total multiplier"
  let flex := LeanAgent.AI.Api.OpenAIResponses.applyUsageCost { model with id := "gpt-5.4" } (some "flex") usage
  assertTrue (flex.cost.input == 0.5) "expected flex input multiplier"
  assertTrue (flex.cost.output == 1.0) "expected flex output multiplier"
  assertTrue (flex.cost.total == 1.5) "expected flex total multiplier"
  let normal := LeanAgent.AI.Api.OpenAIResponses.applyUsageCost { model with id := "gpt-5.4" } none usage
  assertTrue (normal.cost.input == 1.0) "expected default input cost"
  assertTrue (normal.cost.output == 2.0) "expected default output cost"
  assertTrue (normal.cost.total == 3.0) "expected default total cost"

def testOpenAIResponsesParsesResponse : IO Unit := do
  let raw :=
    "{ \"id\":\"resp_1\", \"status\":\"completed\", \"output\":[" ++
    "{\"type\":\"reasoning\",\"id\":\"rs_1\",\"summary\":[{\"text\":\"think\"}]}," ++
    "{\"type\":\"message\",\"id\":\"msg_1\",\"content\":[{\"type\":\"output_text\",\"text\":\"hello\"}]}," ++
    "{\"type\":\"function_call\",\"call_id\":\"call_1\",\"id\":\"fc_1\",\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"README.md\\\"}\"}" ++
    "], \"usage\":{\"input_tokens\":10,\"output_tokens\":4,\"total_tokens\":14,\"input_tokens_details\":{\"cached_tokens\":2},\"output_tokens_details\":{\"reasoning_tokens\":1}} }"
  match LeanAgent.AI.Api.OpenAIResponses.parseResponse "openai-responses" "openai-codex" "gpt-5.5" 7 raw with
  | .ok response =>
      assertTrue (response.responseId == some "resp_1") "expected response id"
      assertTrue (response.stopReason == .toolUse) "expected tool-use stop reason with function call"
      assertTrue (response.usage.input == 8) "expected cached input subtraction"
      assertTrue (response.usage.cacheRead == 2) "expected cache read tokens"
      assertTrue (response.usage.reasoning == some 1) "expected reasoning tokens"
      assertTrue
        (response.content.any fun
          | .thinking thinking => thinking.thinking == "think" && thinking.thinkingSignature.isSome
          | _ => false)
        "expected reasoning block"
      assertTrue
        (response.content.any fun
          | .text text => text.text == "hello" && text.textSignature.isSome
          | _ => false)
        "expected message text block"
      match LeanAgent.AI.contentToolCalls response.content |>.toList with
      | [call] =>
          assertTrue (call.id == "call_1|fc_1") "expected responses tool call id"
          assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected parsed tool arguments"
      | _ => fail "expected one tool call"
  | .error err => fail s!"expected responses parse success: {err}"

def testOpenAIResponsesParsesStreamingTextAndUsage : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_stream\"}}"
    , ""
    , "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_stream\",\"content\":[]}}"
    , ""
    , "data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"delta\":\"hel\"}"
    , ""
    , "data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"delta\":\"lo\"}"
    , ""
    , "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_stream\",\"content\":[{\"type\":\"output_text\",\"text\":\"hello\"}]}}"
    , ""
    , "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_stream\",\"status\":\"completed\",\"usage\":{\"input_tokens\":20,\"output_tokens\":7,\"total_tokens\":27,\"input_tokens_details\":{\"cached_tokens\":2}}}}"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAIResponses.parseStreamingEventStream
    "openai-responses" "openai" "gpt-5.5" 9 raw with
  | .ok stream =>
      assertTrue stream.isComplete "expected complete responses stream"
      assertTrue (stream.result.responseId == some "resp_stream") "expected streamed response id"
      assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "hello") "expected streamed text"
      assertTrue (stream.result.usage.input == 18) "expected cached input subtraction"
      assertTrue (stream.result.usage.cacheRead == 2) "expected stream cache read"
      assertTrue
        (stream.events.any fun
          | .textDelta _ "hel" _ => true
          | _ => false)
        "expected text delta"
      assertTrue
        (stream.events.any fun
          | .textEnd _ "hello" _ => true
          | _ => false)
        "expected text end"
  | .error err => fail s!"expected responses stream parse success: {err}"

def testOpenAIResponsesParsesStreamingToolCall : IO Unit := do
  let args := "{\"path\":\"README.md\",\"content\":\"updated\"}"
  let raw := String.intercalate "\n"
    [ "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_test\",\"call_id\":\"call_test\",\"name\":\"edit\",\"arguments\":\"\"}}"
    , ""
    , "data: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"delta\":\"{\\\"path\\\":\\\"README.md\\\"\"}"
    , ""
    , "data: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"delta\":\",\\\"content\\\":\\\"updated\\\"}\"}"
    , ""
    , "data: {\"type\":\"response.function_call_arguments.done\",\"output_index\":0,\"arguments\":\"{\\\"path\\\":\\\"README.md\\\",\\\"content\\\":\\\"updated\\\"}\"}"
    , ""
    , "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_test\",\"call_id\":\"call_test\",\"name\":\"edit\",\"arguments\":\"{\\\"path\\\":\\\"README.md\\\",\\\"content\\\":\\\"updated\\\"}\"}}"
    , ""
    , "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_tool\",\"status\":\"completed\"}}"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAIResponses.parseStreamingEventStream
    "openai-responses" "openai" "gpt-5.5" 10 raw with
  | .ok stream =>
      assertTrue (stream.result.stopReason == .toolUse) "expected tool-use stop reason"
      match LeanAgent.AI.contentToolCalls stream.result.content |>.toList with
      | [call] =>
          assertTrue (call.id == "call_test|fc_test") "expected responses tool id"
          assertTrue (call.name == "edit") "expected tool name"
          assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected parsed path"
          assertTrue (LeanAgent.Json.optVal? call.arguments "content" == some (LeanAgent.Json.str "updated"))
            "expected parsed content"
      | _ => fail "expected one streamed tool call"
      assertTrue
        (stream.events.any fun
          | .toolCallDelta _ "{\"path\":\"README.md\"" _ => true
          | _ => false)
        "expected first tool delta"
      assertTrue
        (stream.events.any fun
          | .toolCallEnd _ call _ => call.arguments.compress == (LeanAgent.AI.Api.OpenAIResponses.parseToolArguments args).compress
          | _ => false)
        "expected tool end"
  | .error err => fail s!"expected streaming tool parse success: {err}"

def testOpenAIResponsesStreamingRequiresTerminalEvent : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_early\"}}"
    , ""
    , "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"reasoning\",\"id\":\"rs_early\",\"summary\":[]}}"
    , ""
    , "data: {\"type\":\"response.reasoning_text.delta\",\"output_index\":0,\"delta\":\"partial\"}"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAIResponses.parseStreamingEventStream
    "openai-responses" "openai" "gpt-5.5" 11 raw with
  | .ok _ => fail "expected early EOF streaming parse to fail"
  | .error err =>
      assertTrue
        (err.contains "OpenAI Responses stream ended before a terminal response event")
        "expected terminal event error"

def testDiagnosticsExtractsProviderError : IO Unit := do
  let body := "{\"error\":{\"message\":\"rate limit exceeded\",\"type\":\"rate_limit_error\",\"code\":\"rate_limit\"}}"
  let info := LeanAgent.AI.Util.Diagnostics.providerErrorInfoFromBody body
  assertTrue (info.message == "rate limit exceeded") "expected provider error message"
  assertTrue (info.name == some "rate_limit_error") "expected provider error type"
  assertTrue (info.code == some (LeanAgent.Json.str "rate_limit")) "expected provider error code"
  let rendered := LeanAgent.AI.Util.Diagnostics.providerHttpErrorMessage 429 body
  assertTrue (rendered.contains "provider HTTP 429") "expected provider HTTP status"
  assertTrue (rendered.contains "rate limit exceeded") "expected extracted provider message"
  assertTrue (rendered.contains "type=rate_limit_error") "expected extracted provider type"

def testOpenAICompletionsParsesUsage : IO Unit := do
  let raw :=
    "{\"choices\":[{\"message\":{\"content\":\"done\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":20,\"completion_tokens\":7,\"prompt_tokens_details\":{\"cached_tokens\":5,\"cache_write_tokens\":3},\"completion_tokens_details\":{\"reasoning_tokens\":2}}}"
  match LeanAgent.AI.Api.OpenAICompletions.parseChatCompletion raw with
  | .ok response =>
      match response.usage with
      | some usage =>
          assertTrue (usage.input == 12) "expected uncached input tokens"
          assertTrue (usage.output == 7) "expected output tokens"
          assertTrue (usage.cacheRead == 5) "expected cache-read tokens"
          assertTrue (usage.cacheWrite == 3) "expected cache-write tokens"
          assertTrue (usage.reasoning == some 2) "expected reasoning tokens"
          assertTrue (usage.totalTokens == 27) "expected total tokens"
          let assistant := LeanAgent.AI.fromLegacyProviderResponse "openai-completions" "deepseek" "deepseek-v4-flash" 1 response
          assertTrue (assistant.usage.totalTokens == 27) "expected usage to bridge into assistant message"
      | none => fail "expected usage to parse"
  | .error err => fail s!"expected usage parse success: {err}"

def testShortHashMatchesPi : IO Unit := do
  assertTrue (LeanAgent.AI.Util.Hash.shortHash "" == "k4n83c7h0j2b") "expected empty hash"
  assertTrue (LeanAgent.AI.Util.Hash.shortHash "hello" == "1h6qa0qrowduu") "expected hello hash"
  assertTrue (LeanAgent.AI.Util.Hash.shortHash "README.md" == "gel9t9gqr92v") "expected path hash"
  assertTrue (LeanAgent.AI.Util.Hash.shortHash "fc_call_123" == "1x2drirwxo1zn") "expected call hash"
  assertTrue (LeanAgent.AI.Util.Hash.shortHash "😀" == "13wj7r7usi372") "expected emoji hash"
  assertTrue (LeanAgent.AI.Util.Hash.shortHash "a😀b" == "12yrce3kjl8pw") "expected mixed utf16 hash"

def testEstimateUtilities : IO Unit := do
  let usage : LeanAgent.AI.Usage := { input := 1, output := 2, cacheRead := 3, cacheWrite := 4 }
  assertTrue (LeanAgent.AI.Util.Estimate.calculateContextTokens usage == 10) "expected usage fallback total"
  assertTrue (LeanAgent.AI.Util.Estimate.calculateContextTokens { usage with totalTokens := 42 } == 42)
    "expected reported total tokens"
  assertTrue (LeanAgent.AI.Util.Estimate.estimateTextTokens "hello" == 2) "expected text estimate"
  assertTrue (LeanAgent.AI.Util.Estimate.estimateTextTokens "😀" == 1) "expected utf16 estimate"
  let imageMessage : LeanAgent.AI.Message :=
    .user
      { content := #[LeanAgent.AI.text "abcd", LeanAgent.AI.image "base64" "image/png"]
        timestamp := 1
      }
  assertTrue (LeanAgent.AI.Util.Estimate.estimateMessageTokens imageMessage == 1201)
    "expected image char estimate"

def testEstimateContextUsesRecentAssistantUsage : IO Unit := do
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "ignored when usage exists"
      messages :=
        #[ .user { content := #[LeanAgent.AI.text "old prompt"] , timestamp := 1 }
         , .assistant
              { content := #[LeanAgent.AI.text "answer"]
                api := "openai-completions"
                provider := "deepseek"
                model := "deepseek-v4-flash"
                usage := { totalTokens := 100 }
                stopReason := .stop
                timestamp := 2
              }
         , .user { content := #[LeanAgent.AI.text "abcdef"] , timestamp := 3 }
         ]
    }
  let estimate := LeanAgent.AI.Util.Estimate.estimateContextTokens context
  assertTrue (estimate.tokens == 102) "expected usage plus trailing estimate"
  assertTrue (estimate.usageTokens == 100) "expected usage tokens"
  assertTrue (estimate.trailingTokens == 2) "expected trailing tokens"
  assertTrue (estimate.lastUsageIndex == some 1) "expected assistant usage index"

def testSimpleOptionsAdjustMaxTokensForThinking : IO Unit := do
  assertTrue
    (LeanAgent.AI.Api.SimpleOptions.adjustMaxTokensForThinking none 100000 .medium ==
      ({ maxTokens := 100000, thinkingBudget := 8192 } :
        LeanAgent.AI.Api.SimpleOptions.ThinkingTokenAdjustment))
    "expected implicit cap to use model max and default medium budget"
  assertTrue
    (LeanAgent.AI.Api.SimpleOptions.adjustMaxTokensForThinking (some 2048) 100000 .medium ==
      ({ maxTokens := 10240, thinkingBudget := 8192 } :
        LeanAgent.AI.Api.SimpleOptions.ThinkingTokenAdjustment))
    "expected explicit output cap to reserve thinking budget"
  assertTrue
    (LeanAgent.AI.Api.SimpleOptions.adjustMaxTokensForThinking (some 1) 4000 .high ==
      ({ maxTokens := 4000, thinkingBudget := 2976 } :
        LeanAgent.AI.Api.SimpleOptions.ThinkingTokenAdjustment))
    "expected thinking budget to shrink when max tokens cannot fit it"
  let customBudgets : LeanAgent.AI.ThinkingBudgets := { medium := some 3000 }
  assertTrue
    (LeanAgent.AI.Api.SimpleOptions.adjustMaxTokensForThinking (some 2000) 10000 .medium (some customBudgets) ==
      ({ maxTokens := 5000, thinkingBudget := 3000 } :
        LeanAgent.AI.Api.SimpleOptions.ThinkingTokenAdjustment))
    "expected custom thinking budget"
  assertTrue
    (LeanAgent.AI.Api.SimpleOptions.adjustMaxTokensForThinking none 50000 .xhigh ==
      ({ maxTokens := 50000, thinkingBudget := 16384 } :
        LeanAgent.AI.Api.SimpleOptions.ThinkingTokenAdjustment))
    "expected xhigh reasoning to clamp to high budget"

def testModelsClampMaxTokensToContext : IO Unit := do
  let model : LeanAgent.Models.ModelInfo :=
    { id := "tiny"
      name := "Tiny"
      provider := "test"
      api := "openai-completions"
      baseUrl := "http://example.invalid"
      contextWindow := 5000
      maxTokens := 4000
    }
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "abcd"
      messages := #[.user { content := #[LeanAgent.AI.text "abcd"], timestamp := 1 }]
    }
  assertTrue
    (LeanAgent.Models.clampMaxTokensToContext model context 4000 == 902)
    "expected max tokens to fit context minus estimate and safety"
  assertTrue
    (LeanAgent.Models.clampMaxTokensToContext { model with contextWindow := 0 } context 0 == 1)
    "expected unknown context window to preserve minimum"
  let unknownMax := LeanAgent.Models.clampSimpleOptionsToContext { model with maxTokens := 0 } context {}
  assertTrue unknownMax.maxTokens.isNone "expected unknown model maxTokens to stay unset"
  let defaulted := LeanAgent.Models.clampSimpleOptionsToContext model context {}
  assertTrue (defaulted.maxTokens == some 902) "expected model maxTokens default to be clamped"

def testProviderEnvValueResolution : IO Unit := do
  let ambient : String → IO (Option String) := fun name =>
    pure
      (if name == "API_KEY" then
        some "ambient-secret"
      else if name == "EMPTY" then
        some ""
      else
        none)
  let scopedEnv := #[("API_KEY", "scoped-secret"), ("EMPTY", "scoped-empty")]
  assertTrue
    ((← LeanAgent.AI.Util.ProviderEnv.getProviderEnvValueWith ambient "API_KEY" scopedEnv) == some "scoped-secret")
    "expected scoped env to win"
  assertTrue
    ((← LeanAgent.AI.Util.ProviderEnv.getProviderEnvValueWith ambient "API_KEY") == some "ambient-secret")
    "expected ambient env fallback"
  assertTrue
    ((← LeanAgent.AI.Util.ProviderEnv.getProviderEnvValueWith ambient "EMPTY") == none)
    "expected empty ambient env to be ignored"
  let merged := LeanAgent.AI.Util.ProviderEnv.merge #[("A", "base"), ("B", "base")] #[("B", "override"), ("C", "new")]
  assertTrue (merged == #[("A", "base"), ("B", "override"), ("C", "new")]) "expected env merge override"

def testProxyEnvResolution : IO Unit := do
  let ambient : String → IO (Option String) := fun name =>
    pure
      (if name == "HTTPS_PROXY" then
        some "proxy.local:8443"
      else if name == "ALL_PROXY" then
        some "http://fallback.local:8080"
      else
        none)
  let resolved ← LeanAgent.AI.Util.Proxy.resolveHttpProxyUrlForTargetWith
    ambient "https://api.example.com/v1"
  assertTrue (resolved == some "https://proxy.local:8443") "expected HTTPS proxy with inferred protocol"
  let scopedProxy ← LeanAgent.AI.Util.Proxy.resolveHttpProxyUrlForTargetWith
    ambient "https://api.example.com/v1" #[("https_proxy", "http://scoped.local:9000")]
  assertTrue (scopedProxy == some "http://scoped.local:9000") "expected scoped proxy to win"
  let scopedEmpty ← LeanAgent.AI.Util.Proxy.resolveHttpProxyUrlForTargetWith
    ambient "https://api.example.com/v1" #[("https_proxy", "")]
  assertTrue (scopedEmpty == some "https://proxy.local:8443") "expected empty scoped proxy to fall back"
  let fallback ← LeanAgent.AI.Util.Proxy.resolveHttpProxyUrlForTargetWith
    ambient "ws://socket.example.com"
  assertTrue (fallback == some "http://fallback.local:8080") "expected ALL_PROXY fallback"

def testProxyNoProxyMatching : IO Unit := do
  assertTrue
    (!LeanAgent.AI.Util.Proxy.shouldProxyHostnameWithNoProxy "api.example.com" 443 ".example.com")
    "expected domain suffix no_proxy to bypass"
  assertTrue
    (LeanAgent.AI.Util.Proxy.shouldProxyHostnameWithNoProxy "api.example.com" 443 ".example.com:8443")
    "expected no_proxy port mismatch to allow proxy"
  assertTrue
    (!LeanAgent.AI.Util.Proxy.shouldProxyHostnameWithNoProxy "api.example.com" 8443 ".example.com:8443")
    "expected no_proxy port match to bypass"
  assertTrue
    (!LeanAgent.AI.Util.Proxy.shouldProxyHostnameWithNoProxy "api.example.com" 443 "*")
    "expected wildcard no_proxy to bypass all"

def testProxyRejectsUnsupportedProtocol : IO Unit := do
  let ambient : String → IO (Option String) := fun name =>
    pure (if name == "HTTPS_PROXY" then some "socks5://proxy.local:1080" else none)
  let failed ←
    try
      let _ ← LeanAgent.AI.Util.Proxy.resolveHttpProxyUrlForTargetWith
        ambient "https://api.example.com/v1"
      pure false
    catch err =>
      assertTrue
        (err.toString.contains "Unsupported proxy protocol")
        "expected unsupported proxy protocol error"
      pure true
  assertTrue failed "expected unsupported proxy protocol to fail"

def testHeadersUtilities : IO Unit := do
  let merged := LeanAgent.AI.Util.Headers.merge
    #[("Authorization", "Bearer base"), ("X-Trace", "base")]
    #[("authorization", "Bearer override"), ("X-New", "new")]
  assertTrue (merged == #[("X-Trace", "base"), ("authorization", "Bearer override"), ("X-New", "new")])
    "expected case-insensitive override preserving override name"
  let providerHeaders :=
    LeanAgent.AI.Util.Headers.providerHeadersToArray
      #[("X-A", some "a"), ("X-B", none), ("X-C", some "c")]
  assertTrue (providerHeaders == #[("X-A", "a"), ("X-C", "c")])
    "expected none provider headers to be omitted"
  assertTrue
    (LeanAgent.AI.Util.Headers.providerHeadersToArray? #[("X-B", none)] == none)
    "expected empty provider headers to produce none"

def testJsonParseRepairsMalformedStrings : IO Unit := do
  let raw := "{\"text\":\"hello\nworld\",\"path\":\"abc\\q\"}"
  match LeanAgent.AI.Util.JsonParse.parseJsonWithRepair raw with
  | .ok json =>
      assertTrue
        (LeanAgent.Json.optVal? json "text" == some (LeanAgent.Json.str "hello\nworld"))
        "expected raw newline to be escaped and parsed"
      assertTrue
        (LeanAgent.Json.optVal? json "path" == some (LeanAgent.Json.str "abc\\q"))
        "expected invalid escape to be preserved as a literal backslash"
  | .error err => fail s!"expected repaired JSON parse success: {err}"

def testJsonParseStreamingPartialObject : IO Unit := do
  let parsed := LeanAgent.AI.Util.JsonParse.parseStreamingJson "{\"path\":\"README"
  assertTrue
    (LeanAgent.Json.optVal? parsed "path" == some (LeanAgent.Json.str "README"))
    "expected partial string object to be closed"
  let empty := LeanAgent.AI.Util.JsonParse.parseStreamingJson? none
  assertTrue (empty == LeanAgent.Json.obj []) "expected missing partial JSON to produce empty object"
  match LeanAgent.AI.Api.OpenAICompletions.parseToolArguments "{\"path\":\"abc\\q\"}" with
  | .ok args =>
      assertTrue
        (LeanAgent.Json.optVal? args "path" == some (LeanAgent.Json.str "abc\\q"))
        "expected repaired tool arguments"
  | .error err => fail s!"expected repaired tool arguments: {err}"

def validationToolForValue (schema : Lean.Json) : LeanAgent.AI.Tool :=
  { name := "echo"
    description := "Echo tool"
    parameters :=
      LeanAgent.Json.obj
        [ ("type", LeanAgent.Json.str "object")
        , ("properties", LeanAgent.Json.obj [("value", schema)])
        , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "value"])
        ]
  }

def validationToolCall (value : Lean.Json) : LeanAgent.AI.ToolCall :=
  { id := "tool-1"
    name := "echo"
    arguments := LeanAgent.Json.obj [("value", value)]
  }

def assertValidationValue (schema input expected : Lean.Json) : IO Unit := do
  match LeanAgent.AI.Validation.validateToolArguments
      (validationToolForValue schema)
      (validationToolCall input) with
  | .ok args =>
      assertTrue
        (LeanAgent.Json.optVal? args "value" == some expected)
        s!"expected coerced validation value {expected.compress}, got {args.compress}"
  | .error err => fail s!"expected validation success: {err}"

def assertValidationFails (schema input : Lean.Json) : IO Unit := do
  match LeanAgent.AI.Validation.validateToolArguments
      (validationToolForValue schema)
      (validationToolCall input) with
  | .ok args => fail s!"expected validation failure, got {args.compress}"
  | .error err => assertTrue (err.contains "Validation failed") "expected validation failure message"

def testSchemaStringEnum : IO Unit := do
  let schema := LeanAgent.AI.Schema.stringEnum #["add", "subtract"] (some "operation") (some "add")
  assertTrue (LeanAgent.Json.optVal? schema "type" == some (LeanAgent.Json.str "string"))
    "expected string enum type"
  assertTrue (LeanAgent.Json.optVal? schema "description" == some (LeanAgent.Json.str "operation"))
    "expected string enum description"
  assertTrue
    (LeanAgent.AI.Schema.validateJson schema (LeanAgent.Json.str "add") |>.isOk)
    "expected enum value to validate"
  match LeanAgent.AI.Schema.validateJson schema (LeanAgent.Json.str "multiply") with
  | .ok _ => fail "expected non-enum value to fail"
  | .error _ => pure ()

def testValidationCoercesPlainJsonSchemas : IO Unit := do
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "number")])
    (LeanAgent.Json.str "42") (LeanAgent.Json.nat 42)
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "number")])
    (Lean.Json.bool true) (LeanAgent.Json.nat 1)
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "number")])
    Lean.Json.null (LeanAgent.Json.nat 0)
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "integer")])
    (LeanAgent.Json.str "42") (LeanAgent.Json.nat 42)
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "integer")])
    (LeanAgent.Json.str "-2") (Lean.Json.num (Lean.JsonNumber.fromInt (-2)))
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "boolean")])
    (LeanAgent.Json.str "true") (Lean.Json.bool true)
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "boolean")])
    (LeanAgent.Json.nat 0) (Lean.Json.bool false)
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "string")])
    Lean.Json.null (LeanAgent.Json.str "")
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "string")])
    (Lean.Json.bool true) (LeanAgent.Json.str "true")
  assertValidationValue (LeanAgent.Json.obj [("type", LeanAgent.Json.str "null")])
    (LeanAgent.Json.str "") Lean.Json.null
  assertValidationValue
    (LeanAgent.Json.obj
      [("type", LeanAgent.Json.arr #[LeanAgent.Json.str "number", LeanAgent.Json.str "string"])])
    (LeanAgent.Json.str "1")
    (LeanAgent.Json.str "1")
  assertValidationValue
    (LeanAgent.Json.obj
      [("type", LeanAgent.Json.arr #[LeanAgent.Json.str "boolean", LeanAgent.Json.str "number"])])
    (LeanAgent.Json.str "1")
    (LeanAgent.Json.nat 1)

def testValidationRejectsInvalidCoercions : IO Unit := do
  assertValidationFails (LeanAgent.Json.obj [("type", LeanAgent.Json.str "boolean")])
    (LeanAgent.Json.str "1")
  assertValidationFails (LeanAgent.Json.obj [("type", LeanAgent.Json.str "boolean")])
    (LeanAgent.Json.str "0")
  assertValidationFails (LeanAgent.Json.obj [("type", LeanAgent.Json.str "null")])
    (LeanAgent.Json.str "null")
  assertValidationFails (LeanAgent.Json.obj [("type", LeanAgent.Json.str "integer")])
    (LeanAgent.Json.str "42.1")

def testValidationToolLookupAndRequired : IO Unit := do
  let tool : LeanAgent.AI.Tool :=
    { name := "read"
      description := "Read a file"
      parameters :=
        LeanAgent.Json.obj
          [ ("type", LeanAgent.Json.str "object")
          , ("properties", LeanAgent.Json.obj [("path", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string")])])
          , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "path"])
          , ("additionalProperties", Lean.Json.bool false)
          ]
    }
  let call : LeanAgent.AI.ToolCall :=
    { id := "call-1"
      name := "read"
      arguments := LeanAgent.Json.obj [("path", Lean.Json.null)]
    }
  match LeanAgent.AI.Validation.validateToolCall #[tool] call with
  | .ok args =>
      assertTrue (LeanAgent.Json.optVal? args "path" == some (LeanAgent.Json.str ""))
        "expected tool call path coercion"
  | .error err => fail s!"expected tool validation success: {err}"
  let missing : LeanAgent.AI.ToolCall := { call with arguments := LeanAgent.Json.obj [] }
  match LeanAgent.AI.Validation.validateToolCall #[tool] missing with
  | .ok args => fail s!"expected missing required path to fail: {args.compress}"
  | .error err =>
      assertTrue (err.contains "path") "expected required path in validation error"
  let unknown : LeanAgent.AI.ToolCall := { call with name := "write" }
  match LeanAgent.AI.Validation.validateToolCall #[tool] unknown with
  | .ok _ => fail "expected unknown tool failure"
  | .error err => assertTrue (err.contains "Tool \"write\" not found") "expected unknown tool message"

def testSanitizeUnicodeSurrogates : IO Unit := do
  let text := "Hello 🙈 World"
  assertTrue
    (LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates text == text)
    "expected valid emoji string to be preserved"
  let high := UInt32.ofNat 0xd83d
  let low := UInt32.ofNat 0xde48
  let units :=
    [ UInt32.ofNat (Char.toNat 'A')
    , high
    , UInt32.ofNat (Char.toNat 'B')
    , low
    , high
    , low
    , UInt32.ofNat (Char.toNat 'C')
    ]
  let sanitized := LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogateCodeUnits units
  assertTrue
    (sanitized ==
      [ UInt32.ofNat (Char.toNat 'A')
      , UInt32.ofNat (Char.toNat 'B')
      , high
      , low
      , UInt32.ofNat (Char.toNat 'C')
      ])
    "expected unpaired surrogate code units to be removed and valid pair preserved"

def overflowAssistantMessage
    (stopReason : LeanAgent.AI.StopReason)
    (errorMessage : Option String := none)
    (usage : LeanAgent.AI.Usage := {}) : LeanAgent.AI.AssistantMessage :=
  { content := #[]
    api := "fake"
    provider := "fake"
    model := "fake"
    usage := usage
    stopReason := stopReason
    errorMessage := errorMessage
    timestamp := 0
  }

def testOverflowClassifiesProviderErrors : IO Unit := do
  assertTrue
    (LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "prompt is too long: 213462 tokens > 200000 maximum")))
    "expected Anthropic overflow error"
  assertTrue
    (LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "Input length (265330) exceeds model's maximum context length (262144).")))
    "expected OpenAI-compatible overflow error"
  assertTrue
    (LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "The input token count (1196265) exceeds the maximum number of tokens allowed (1048575)")))
    "expected Gemini overflow error"
  assertTrue
    (!LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "Throttling error: Too many tokens, please wait before trying again.")))
    "expected Bedrock throttling text to be excluded"
  assertTrue
    (!LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "rate limit: too many tokens in flight")))
    "expected rate limits to be excluded"

def testOverflowClassifiesContextWindowSignals : IO Unit := do
  assertTrue
    (LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .stop none { input := 99, cacheRead := 2 })
      (some 100))
    "expected silent usage overflow"
  assertTrue
    (!LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .stop none { input := 100 })
      (some 100))
    "expected exact context usage to fit"
  assertTrue
    (LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .length none { input := 98, cacheRead := 1, output := 0 })
      (some 100))
    "expected length stop with full context and zero output"
  assertTrue
    (!LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .length none { input := 99, output := 1 })
      (some 100))
    "expected length stop with output to be non-overflow"

def retryAssistantMessage (errorMessage : Option String) : LeanAgent.AI.AssistantMessage :=
  { content := #[]
    api := "fake"
    provider := "fake"
    model := "fake"
    stopReason := .error
    errorMessage := errorMessage
    timestamp := 0
  }

def testRetryClassifiesAssistantErrors : IO Unit := do
  assertTrue
    (LeanAgent.AI.Util.Retry.isRetryableAssistantError
      (retryAssistantMessage (some "You can retry your request later.")))
    "expected explicit retry guidance to be retryable"
  assertTrue
    (!LeanAgent.AI.Util.Retry.isRetryableAssistantError
      (retryAssistantMessage (some "429 quota exceeded")))
    "expected quota exhaustion to be non-retryable"
  let nonError := { retryAssistantMessage (some "overloaded") with stopReason := .stop }
  assertTrue
    (!LeanAgent.AI.Util.Retry.isRetryableAssistantError nonError)
    "expected non-error assistant message to be non-retryable"

def testRetryWithRetriesSucceedsAfterTransientFailures : IO Unit := do
  let attempts ← IO.mkRef 0
  let value ← LeanAgent.AI.Util.Retry.withRetries
    { maxRetries := 2, maxRetryDelayMs := 0 }
    (do
      let current ← attempts.get
      attempts.set (current + 1)
      if current < 2 then
        throw (IO.userError "provider HTTP 503: service unavailable")
      else
        pure "ok")
  assertTrue (value == "ok") "expected retry result"
  assertTrue ((← attempts.get) == 3) "expected initial attempt plus two retries"

def testRetryWithRetriesStopsOnNonRetryableFailure : IO Unit := do
  let attempts ← IO.mkRef 0
  let failed ←
    try
      LeanAgent.AI.Util.Retry.withRetries (α := Unit)
        { maxRetries := 2, maxRetryDelayMs := 0 }
        (do
          attempts.modify (· + 1)
          throw (IO.userError "provider HTTP 429: quota exceeded"))
      pure false
    catch _ =>
      pure true
  assertTrue failed "expected non-retryable failure"
  assertTrue ((← attempts.get) == 1) "expected no retry for quota exhaustion"

def testModelCatalogDeepSeekDefaults : IO Unit := do
  let catalog := LeanAgent.Models.defaultCatalog
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.deepSeekApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.deepSeekProviderId) "expected DeepSeek provider for DeepSeek API key env"
      assertTrue (provider.defaultModel == LeanAgent.Models.deepSeekDefaultModel) "expected DeepSeek default model"
  | none => fail "expected DeepSeek provider"
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.deepSeekProviderId LeanAgent.Models.deepSeekDefaultModel with
  | some model =>
      assertTrue (model.contextWindow == 1000000) "expected DeepSeek context window"
      assertTrue (model.maxTokens == 384000) "expected DeepSeek max output tokens"
      assertTrue model.reasoning "expected DeepSeek reasoning support"
      assertTrue model.supportsToolCalls "expected DeepSeek tool-call support"
  | none => fail "expected DeepSeek default model in catalog"
  let rendered := LeanAgent.Models.renderCatalog catalog
  assertTrue (rendered.contains "deepseek/deepseek-v4-pro") "expected rendered DeepSeek pro model"

def testOpenAICompatibleProviderFamilyCatalog : IO Unit := do
  let catalog := LeanAgent.Models.defaultCatalog
  let expectedProviders :=
    #[ LeanAgent.Models.deepSeekProviderId
     , LeanAgent.Models.openAIProviderId
     , LeanAgent.Models.openRouterProviderId
     , LeanAgent.Models.groqProviderId
     , LeanAgent.Models.xaiProviderId
     , LeanAgent.Models.cerebrasProviderId
     , LeanAgent.Models.togetherProviderId
     , LeanAgent.Models.fireworksProviderId
     ]
  for providerId in expectedProviders do
    match LeanAgent.Models.ProviderCatalog.provider? catalog providerId with
    | some _ => pure ()
    | none => fail s!"expected provider in catalog: {providerId}"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.groqApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.groqProviderId) "expected Groq provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.groqDefaultModel) "expected Groq default model"
  | none => fail "expected Groq provider by env"
  let rendered := LeanAgent.Models.renderCatalog catalog
  assertTrue (rendered.contains "openrouter/openai/gpt-oss-120b") "expected OpenRouter model"
  assertTrue (rendered.contains "fireworks/accounts/fireworks/models/glm-5p2") "expected Fireworks OpenAI-compatible model"

def testDefaultModelsRegistersOpenAICompatibleFamily : IO Unit := do
  let collection ← LeanAgent.Models.createDefaultModels
  let providers ← collection.getProviders
  assertTrue (providers.size == 8) "expected default provider family"
  match ← collection.getModel? LeanAgent.Models.openRouterProviderId LeanAgent.Models.openRouterDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-completions") "expected OpenRouter OpenAI-compatible API"
      assertTrue model.reasoning "expected OpenRouter reasoning metadata"
  | none => fail "expected OpenRouter model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.fireworksProviderId LeanAgent.Models.fireworksDefaultModel with
  | some model =>
      assertTrue (model.baseUrl == LeanAgent.Models.fireworksBaseUrl) "expected Fireworks OpenAI-compatible base URL"
  | none => fail "expected Fireworks model in default runtime collection"

def fakeAuthContext : LeanAgent.AI.Auth.AuthContext :=
  { env := fun name =>
      pure
        (if name == "FAKE_API_KEY" then
          some "env-secret"
        else
          none)
    fileExists := fun _ => pure false
  }

def fakeProviderAuth : LeanAgent.AI.Auth.ProviderAuth :=
  { apiKey := some (LeanAgent.AI.Auth.envApiKeyAuth "Fake API key" #["FAKE_API_KEY"]) }

def fakeAuthContextWithNow (now : Nat) : LeanAgent.AI.Auth.AuthContext :=
  { fakeAuthContext with nowMs := pure now }

def oauthExtraString? (credential : LeanAgent.AI.Auth.OAuthCredential) (name : String) : Option String :=
  credential.extra.findSome? fun (field, value) =>
    if field == name then value.getStr?.toOption else none

def fakeOAuthAuth (refreshCalls : IO.Ref Nat) : LeanAgent.AI.Auth.OAuthAuth :=
  { name := "Fake OAuth"
    refresh := fun credential => do
      refreshCalls.modify (· + 1)
      pure
        { credential with
          access := "refreshed-token"
          refresh := "refresh-2"
          expires := 2000
        }
    toAuth := fun credential => do
      pure
        { apiKey := some credential.access
          baseUrl := oauthExtraString? credential "baseUrl"
        }
  }

def fakeCloudflareAuthContext : LeanAgent.AI.Auth.AuthContext :=
  { env := fun name =>
      pure
        (if name == "CLOUDFLARE_API_KEY" then
          some "cf-env-key"
        else if name == "CLOUDFLARE_ACCOUNT_ID" then
          some "acct-env"
        else if name == "CLOUDFLARE_GATEWAY_ID" then
          some "gateway-env"
        else
          none)
    fileExists := fun _ => pure false
  }

def testModelsAuthEnvApiKeyResolution : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  match ← LeanAgent.AI.Auth.resolveProviderAuth "fake" fakeProviderAuth store fakeAuthContext with
  | some result =>
      assertTrue (result.auth.apiKey == some "env-secret") "expected env API key"
      assertTrue (result.source == some "FAKE_API_KEY") "expected env key source"
  | none => fail "expected auth result from env"

def testModelsAuthStoredCredentialWins : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let _ ← store.modify "fake" fun _ =>
    pure (some (.apiKey { key := some "stored-secret" }))
  match ← LeanAgent.AI.Auth.resolveProviderAuth "fake" fakeProviderAuth store fakeAuthContext with
  | some result =>
      assertTrue (result.auth.apiKey == some "stored-secret") "expected stored credential to win"
      assertTrue (result.source == some "stored credential") "expected stored credential source"
  | none => fail "expected auth result from stored credential"

def testFileCredentialStoreRoundTrip : IO Unit :=
  IO.FS.withTempDir fun root => do
    let path := root / "state" / "auth.json"
    let store ← LeanAgent.AI.Auth.FileCredentialStore.mk path
    assertTrue ((← store.read "fake").isNone) "expected missing file store read to return none"
    let saved ← store.modify "fake" fun current => do
      assertTrue current.isNone "expected no initial file credential"
      pure
        (some
          (.apiKey
            { key := some "stored-secret"
              env := #[("ACCOUNT_ID", "acct"), ("EMPTY", "")]
            }))
    match saved with
    | some (.apiKey credential) =>
        assertTrue (credential.key == some "stored-secret") "expected saved API key"
        assertTrue
          (LeanAgent.AI.Auth.providerEnvGet? credential.env "ACCOUNT_ID" == some "acct")
          "expected saved credential env"
    | _ => fail "expected saved API-key file credential"
    assertTrue (← path.pathExists) "expected credential file to be created"
    let raw ← IO.FS.readFile path
    assertTrue (raw.contains "api_key") "expected serialized API-key credential type"
    assertTrue (raw.contains "stored-secret") "expected serialized credential key"
    let reloaded ← LeanAgent.AI.Auth.FileCredentialStore.mk path
    match ← reloaded.read "fake" with
    | some (.apiKey credential) =>
        assertTrue (credential.key == some "stored-secret") "expected reloaded API key"
        assertTrue
          (LeanAgent.AI.Auth.providerEnvGet? credential.env "ACCOUNT_ID" == some "acct")
          "expected reloaded credential env"
    | _ => fail "expected reloaded API-key file credential"
    let unchanged ← reloaded.modify "fake" fun current => do
      assertTrue current.isSome "expected current credential in modify callback"
      pure none
    match unchanged with
    | some (.apiKey credential) =>
        assertTrue (credential.key == some "stored-secret") "expected modify none to preserve credential"
    | _ => fail "expected modify none to return current API-key credential"
    reloaded.delete "fake"
    let afterDelete ← LeanAgent.AI.Auth.FileCredentialStore.mk path
    assertTrue ((← afterDelete.read "fake").isNone) "expected deleted file credential"

def testFileCredentialStoreRejectsUnsupportedCredentialType : IO Unit :=
  IO.FS.withTempDir fun root => do
    let path := root / "auth.json"
    IO.FS.writeFile path "{\"fake\":{\"type\":\"saml\",\"access\":\"token\"}}"
    let store ← LeanAgent.AI.Auth.FileCredentialStore.mk path
    let failed ←
      try
        let _ ← store.read "fake"
        pure false
      catch err =>
        assertTrue
          (err.toString.contains "unsupported credential type: saml")
          "expected unsupported credential type error"
        pure true
    assertTrue failed "unsupported credential type should fail"

def testFileCredentialStoreOAuthRoundTrip : IO Unit :=
  IO.FS.withTempDir fun root => do
    let path := root / "auth.json"
    let store ← LeanAgent.AI.Auth.FileCredentialStore.mk path
    let _ ← store.modify "fake" fun _ =>
      pure
        (some
          (.oauth
            { access := "oauth-access"
              refresh := "oauth-refresh"
              expires := 1234
              extra := #[("baseUrl", LeanAgent.Json.str "https://oauth.test")]
            }))
    let raw ← IO.FS.readFile path
    assertTrue (raw.contains "oauth") "expected serialized OAuth credential type"
    assertTrue (raw.contains "baseUrl") "expected serialized OAuth extra field"
    let reloaded ← LeanAgent.AI.Auth.FileCredentialStore.mk path
    match ← reloaded.read "fake" with
    | some (.oauth credential) =>
        assertTrue (credential.access == "oauth-access") "expected reloaded OAuth access token"
        assertTrue (credential.refresh == "oauth-refresh") "expected reloaded OAuth refresh token"
        assertTrue (credential.expires == 1234) "expected reloaded OAuth expiry"
        assertTrue
          (oauthExtraString? credential "baseUrl" == some "https://oauth.test")
          "expected reloaded OAuth extra field"
    | _ => fail "expected reloaded OAuth credential"

def testModelsAuthFileCredentialStore : IO Unit :=
  IO.FS.withTempDir fun root => do
    let store ← LeanAgent.AI.Auth.FileCredentialStore.mk (root / "auth.json")
    let _ ← store.modify "fake" fun _ =>
      pure (some (.apiKey { key := some "file-secret" }))
    match ← LeanAgent.AI.Auth.resolveProviderAuth "fake" fakeProviderAuth store fakeAuthContext with
    | some result =>
        assertTrue (result.auth.apiKey == some "file-secret") "expected file credential to win"
        assertTrue (result.source == some "stored credential") "expected file credential source"
    | none => fail "expected auth result from file credential"

def testModelsAuthOAuthValidCredential : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let _ ← store.modify "fake" fun _ =>
    pure
      (some
        (.oauth
          { access := "oauth-access"
            refresh := "oauth-refresh"
            expires := 2000
            extra := #[("baseUrl", LeanAgent.Json.str "https://oauth.test")]
          }))
  let refreshCalls ← IO.mkRef 0
  let auth := { fakeProviderAuth with oauth := some (fakeOAuthAuth refreshCalls) }
  match ← LeanAgent.AI.Auth.resolveProviderAuth "fake" auth store (fakeAuthContextWithNow 1000) with
  | some result =>
      assertTrue (result.auth.apiKey == some "oauth-access") "expected OAuth access token auth"
      assertTrue (result.auth.baseUrl == some "https://oauth.test") "expected OAuth-derived base URL"
      assertTrue (result.source == some "OAuth") "expected OAuth source"
  | none => fail "expected auth result from OAuth credential"
  assertTrue ((← refreshCalls.get) == 0) "fresh OAuth credential should not refresh"

def testModelsAuthOAuthExpiredCredentialRefreshes : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let _ ← store.modify "fake" fun _ =>
    pure
      (some
        (.oauth
          { access := "expired-token"
            refresh := "refresh-1"
            expires := 999
          }))
  let refreshCalls ← IO.mkRef 0
  let auth := { fakeProviderAuth with oauth := some (fakeOAuthAuth refreshCalls) }
  match ← LeanAgent.AI.Auth.resolveProviderAuth "fake" auth store (fakeAuthContextWithNow 1000) with
  | some result =>
      assertTrue (result.auth.apiKey == some "refreshed-token") "expected refreshed OAuth access token"
      assertTrue (result.source == some "OAuth") "expected OAuth source after refresh"
  | none => fail "expected auth result from refreshed OAuth credential"
  assertTrue ((← refreshCalls.get) == 1) "expired OAuth credential should refresh once"
  match ← store.read "fake" with
  | some (.oauth credential) =>
      assertTrue (credential.access == "refreshed-token") "expected refreshed credential to be persisted"
      assertTrue (credential.expires == 2000) "expected refreshed expiry to be persisted"
  | _ => fail "expected persisted OAuth credential"

def testModelsAuthOAuthCredentialOwnsProvider : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let _ ← store.modify "fake" fun _ =>
    pure
      (some
        (.oauth
          { access := "oauth-access"
            refresh := "oauth-refresh"
            expires := 2000
          }))
  let result ← LeanAgent.AI.Auth.resolveProviderAuth
    "fake"
    fakeProviderAuth
    store
    (fakeAuthContextWithNow 1000)
  assertTrue result.isNone "stored OAuth credential without OAuth handler should not fall back to env"

def fakeOAuthCredential (access refresh : String) (expires : Nat) : LeanAgent.AI.OAuth.OAuthCredentials :=
  { access, refresh, expires }

def fakeOAuthProviderForRegistry
    (id name : String)
    (refreshCalls : IO.Ref Nat)
    (failRefresh : Bool := false) : LeanAgent.AI.OAuth.OAuthProviderInterface :=
  { id := id
    name := name
    login := fun _ => pure (fakeOAuthCredential "login-token" "login-refresh" 5000)
    refreshToken := fun credential => do
      refreshCalls.modify (· + 1)
      if failRefresh then
        throw (IO.userError "refresh failed")
      else
        pure { credential with access := credential.access ++ "-refreshed", expires := 5000 }
    getApiKey := fun credential => "Bearer " ++ credential.access
  }

def testOAuthProviderRegistryCrud : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  let refreshCalls ← IO.mkRef 0
  let provider := fakeOAuthProviderForRegistry "registry-test" "Registry Test" refreshCalls
  LeanAgent.AI.OAuth.registerOAuthProvider provider
  match ← LeanAgent.AI.OAuth.getOAuthProvider? "registry-test" with
  | some found => assertTrue (found.name == "Registry Test") "expected registered OAuth provider"
  | none => fail "expected registered OAuth provider lookup"
  let providers ← LeanAgent.AI.OAuth.getOAuthProviders
  assertTrue (providers.any (fun found => found.id == "registry-test")) "expected provider in registry list"
  let info ← LeanAgent.AI.OAuth.getOAuthProviderInfoList
  assertTrue
    (info.any (fun found =>
      found.id == "registry-test" && found.name == "Registry Test" && found.available))
    "expected provider info list entry"
  LeanAgent.AI.OAuth.unregisterOAuthProvider "registry-test"
  assertTrue ((← LeanAgent.AI.OAuth.getOAuthProvider? "registry-test").isNone)
    "expected unregister to remove custom OAuth provider"
  LeanAgent.AI.OAuth.registerOAuthProvider provider
  LeanAgent.AI.OAuth.resetOAuthProviders
  assertTrue ((← LeanAgent.AI.OAuth.getOAuthProvider? "registry-test").isNone)
    "expected reset to remove custom OAuth provider"

def testOAuthRefreshTokenDispatch : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  let refreshCalls ← IO.mkRef 0
  LeanAgent.AI.OAuth.registerOAuthProvider
    (fakeOAuthProviderForRegistry "refresh-test" "Refresh Test" refreshCalls)
  let refreshed ← LeanAgent.AI.OAuth.refreshOAuthToken
    "refresh-test"
    (fakeOAuthCredential "old-token" "refresh-token" 1)
  assertTrue (refreshed.access == "old-token-refreshed") "expected registry refresh dispatch"
  assertTrue (refreshed.expires == 5000) "expected refreshed expiry"
  assertTrue ((← refreshCalls.get) == 1) "expected one refresh call"
  LeanAgent.AI.OAuth.resetOAuthProviders

def testOAuthGetOAuthApiKey : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  let refreshCalls ← IO.mkRef 0
  LeanAgent.AI.OAuth.registerOAuthProvider
    (fakeOAuthProviderForRegistry "api-key-test" "API Key Test" refreshCalls)
  let missing ← LeanAgent.AI.OAuth.getOAuthApiKey "api-key-test" #[] (pure 1000)
  assertTrue missing.isNone "expected missing OAuth credentials to return none"
  match ← LeanAgent.AI.OAuth.getOAuthApiKey
    "api-key-test"
    #[("api-key-test", fakeOAuthCredential "fresh-token" "refresh-token" 2000)]
    (pure 1000) with
  | some result =>
      assertTrue (result.apiKey == "Bearer fresh-token") "expected fresh OAuth API key"
      assertTrue (result.newCredentials.access == "fresh-token") "expected fresh credentials to be unchanged"
  | none => fail "expected fresh OAuth API key result"
  assertTrue ((← refreshCalls.get) == 0) "fresh OAuth credentials should not refresh"
  match ← LeanAgent.AI.OAuth.getOAuthApiKey
    "api-key-test"
    #[("api-key-test", fakeOAuthCredential "expired-token" "refresh-token" 999)]
    (pure 1000) with
  | some result =>
      assertTrue (result.apiKey == "Bearer expired-token-refreshed") "expected refreshed OAuth API key"
      assertTrue (result.newCredentials.access == "expired-token-refreshed")
        "expected refreshed credentials"
  | none => fail "expected refreshed OAuth API key result"
  assertTrue ((← refreshCalls.get) == 1) "expired OAuth credentials should refresh"
  LeanAgent.AI.OAuth.resetOAuthProviders

def testOAuthGetOAuthApiKeyErrors : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  let unknownFailed ←
    try
      let _ ← LeanAgent.AI.OAuth.getOAuthApiKey
        "unknown-oauth"
        #[("unknown-oauth", fakeOAuthCredential "token" "refresh" 2000)]
        (pure 1000)
      pure false
    catch err =>
      assertTrue (err.toString.contains "Unknown OAuth provider: unknown-oauth")
        "expected unknown OAuth provider error"
      pure true
  assertTrue unknownFailed "unknown OAuth provider should fail"
  let refreshCalls ← IO.mkRef 0
  LeanAgent.AI.OAuth.registerOAuthProvider
    (fakeOAuthProviderForRegistry "failing-oauth" "Failing OAuth" refreshCalls true)
  let refreshFailed ←
    try
      let _ ← LeanAgent.AI.OAuth.getOAuthApiKey
        "failing-oauth"
        #[("failing-oauth", fakeOAuthCredential "expired" "refresh" 999)]
        (pure 1000)
      pure false
    catch err =>
      assertTrue (err.toString.contains "Failed to refresh OAuth token for failing-oauth")
        "expected refresh wrapper error"
      pure true
  assertTrue refreshFailed "failing OAuth refresh should fail"
  assertTrue ((← refreshCalls.get) == 1) "expected failed refresh to be attempted once"
  LeanAgent.AI.OAuth.resetOAuthProviders

def headerValueOpt? (headers : Array (String × Option String)) (name : String) : Option (Option String) :=
  headers.findSome? fun (headerName, value) =>
    if headerName.toLower == name.toLower then some value else none

def headerValueStringCI? (headers : Array (String × String)) (name : String) : Option String :=
  headers.findSome? fun (headerName, value) =>
    if headerName.toLower == name.toLower then some value else none

def testCloudflareWorkersAIAuthResolution : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let auth : LeanAgent.AI.Auth.ProviderAuth :=
    { apiKey := some LeanAgent.AI.Providers.CloudflareAuth.cloudflareWorkersAIAuth }
  match ← LeanAgent.AI.Auth.resolveProviderAuth
    "cloudflare-workers-ai"
    auth
    store
    fakeCloudflareAuthContext
    {}
    (some LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl) with
  | some result =>
      assertTrue (result.auth.apiKey == some "cf-env-key") "expected Cloudflare API key"
      assertTrue
        (result.auth.baseUrl ==
          some "https://api.cloudflare.com/client/v4/accounts/acct-env/ai/v1")
        "expected Workers AI base URL substitution"
      assertTrue (LeanAgent.AI.Auth.providerEnvGet? result.env "CLOUDFLARE_ACCOUNT_ID" == some "acct-env")
        "expected Workers AI account env"
      assertTrue (result.source == some "CLOUDFLARE_API_KEY") "expected Cloudflare env source"
  | none => fail "expected Workers AI Cloudflare auth result"

def testCloudflareAIGatewayAuthResolution : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let auth : LeanAgent.AI.Auth.ProviderAuth :=
    { apiKey := some LeanAgent.AI.Providers.CloudflareAuth.cloudflareAIGatewayAuth }
  match ← LeanAgent.AI.Auth.resolveProviderAuth
    "cloudflare-ai-gateway"
    auth
    store
    fakeCloudflareAuthContext
    {}
    (some LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl) with
  | some result =>
      assertTrue result.auth.apiKey.isNone "expected AI Gateway to avoid default bearer API key"
      assertTrue
        (result.auth.baseUrl ==
          some "https://gateway.ai.cloudflare.com/v1/acct-env/gateway-env/openai")
        "expected AI Gateway base URL substitution"
      assertTrue
        (LeanAgent.AI.Auth.providerEnvGet? result.env "CLOUDFLARE_GATEWAY_ID" == some "gateway-env")
        "expected AI Gateway id env"
      assertTrue
        (headerValueStringCI? result.auth.headers "cf-aig-authorization" == some "Bearer cf-env-key")
        "expected cf-aig authorization header"
      assertTrue (headerValueStringCI? result.auth.headers "Authorization" == some "")
        "expected AI Gateway to suppress inherited bearer auth"
      assertTrue (headerValueStringCI? result.auth.headers "x-api-key" == some "")
        "expected AI Gateway to suppress inherited x-api-key auth"
  | none => fail "expected AI Gateway Cloudflare auth result"

def testCloudflareStoredCredentialResolution : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let _ ← store.modify "cloudflare-workers-ai" fun _ =>
    pure
      (some
        (.apiKey
          { key := some "cf-stored-key"
            env := #[("CLOUDFLARE_ACCOUNT_ID", "acct-stored")]
          }))
  let auth : LeanAgent.AI.Auth.ProviderAuth :=
    { apiKey := some LeanAgent.AI.Providers.CloudflareAuth.cloudflareWorkersAIAuth }
  match ← LeanAgent.AI.Auth.resolveProviderAuth
    "cloudflare-workers-ai"
    auth
    store
    fakeAuthContext
    {}
    (some LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl) with
  | some result =>
      assertTrue (result.auth.apiKey == some "cf-stored-key") "expected stored Cloudflare key"
      assertTrue
        (result.auth.baseUrl ==
          some "https://api.cloudflare.com/client/v4/accounts/acct-stored/ai/v1")
        "expected stored account base URL"
      assertTrue (result.source == some "stored credential") "expected stored Cloudflare source"
  | none => fail "expected stored Cloudflare auth result"

def testEnvApiKeysProviderMap : IO Unit := do
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "github-copilot" == some #["COPILOT_GITHUB_TOKEN"])
    "expected GitHub Copilot env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "zai-coding-cn" == some #["ZAI_CODING_CN_API_KEY"])
    "expected ZAI Coding CN env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "unknown-provider" == none)
    "expected unknown provider to have no env vars"
  let keys ← LeanAgent.AI.EnvApiKeys.findEnvKeys
    "zai-coding-cn"
    #[("ZAI_CODING_CN_API_KEY", "zai-token")]
  assertTrue (keys == some #["ZAI_CODING_CN_API_KEY"]) "expected configured ZAI key"
  let apiKey ← LeanAgent.AI.EnvApiKeys.getEnvApiKey
    "zai-coding-cn"
    #[("ZAI_CODING_CN_API_KEY", "zai-token")]
  assertTrue (apiKey == some "zai-token") "expected configured ZAI API key"
  let missing ← LeanAgent.AI.EnvApiKeys.findEnvKeys "unknown-provider" #[]
  assertTrue (missing == none) "expected stable missing provider result"

def testEnvApiKeysPrefersAnthropicOAuthToken : IO Unit := do
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "anthropic" ==
      some #["ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY"])
    "expected Anthropic OAuth token to be listed first"
  let env :=
    #[ ("ANTHROPIC_API_KEY", "api-token")
     , ("ANTHROPIC_OAUTH_TOKEN", "oauth-token")
     ]
  let keys ← LeanAgent.AI.EnvApiKeys.findEnvKeys "anthropic" env
  assertTrue
    (keys == some #["ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY"])
    "expected Anthropic configured keys in precedence order"
  let apiKey ← LeanAgent.AI.EnvApiKeys.getEnvApiKey "anthropic" env
  assertTrue (apiKey == some "oauth-token") "expected Anthropic OAuth token to win"

def testEnvApiKeysAmbientAuthMarkers : IO Unit := do
  let bedrockProfile ← LeanAgent.AI.EnvApiKeys.getEnvApiKey
    "amazon-bedrock"
    #[("AWS_PROFILE", "default")]
  assertTrue (bedrockProfile == some "<authenticated>") "expected AWS profile ambient marker"
  let bedrockPair ← LeanAgent.AI.EnvApiKeys.getEnvApiKey
    "amazon-bedrock"
    #[ ("AWS_ACCESS_KEY_ID", "access")
     , ("AWS_SECRET_ACCESS_KEY", "secret")
     ]
  assertTrue (bedrockPair == some "<authenticated>") "expected AWS key-pair ambient marker"
  IO.FS.withTempDir fun root => do
    let credentialsPath := root / "application_default_credentials.json"
    IO.FS.writeFile credentialsPath "{}"
    let vertex ← LeanAgent.AI.EnvApiKeys.getEnvApiKey
      "google-vertex"
      #[ ("GOOGLE_APPLICATION_CREDENTIALS", credentialsPath.toString)
       , ("GOOGLE_CLOUD_PROJECT", "lean-agent-test")
       , ("GOOGLE_CLOUD_LOCATION", "us-central1")
       ]
    assertTrue (vertex == some "<authenticated>") "expected Vertex ADC ambient marker"

def fakeRuntimeModel : LeanAgent.Models.ModelInfo :=
  { id := "fake-model"
    name := "Fake Model"
    provider := "fake"
    api := "fake-api"
    baseUrl := "https://fake.test"
  }

def fakeRuntimeStreams (seenApiKey : IO.Ref (Option String)) : LeanAgent.Models.ProviderStreams :=
  { streamSimple := fun model _context options => do
      seenApiKey.set options.apiKey
      let timestamp ← IO.monoMsNow
      let message : LeanAgent.AI.AssistantMessage :=
        { content := #[LeanAgent.AI.text "runtime-ok"]
          api := model.api
          provider := model.provider
          model := model.id
          timestamp := timestamp
        }
      pure (LeanAgent.AI.fromMessage message)
  }

def testModelsCollectionDispatchesWithAuth : IO Unit := do
  let seenApiKey ← IO.mkRef (none : Option String)
  let collection ← LeanAgent.Models.createModels none fakeAuthContext
  let provider ← LeanAgent.Models.createProvider
    { id := "fake"
      name := some "Fake"
      auth := fakeProviderAuth
      models := #[fakeRuntimeModel]
      apis := #[{ api := "fake-api", streams := fakeRuntimeStreams seenApiKey }]
    }
  collection.setProvider provider
  match ← collection.getModel? "fake" "fake-model" with
  | some model => assertTrue (model.id == "fake-model") "expected runtime model lookup"
  | none => fail "expected runtime model lookup"
  let message ← collection.completeSimple
    fakeRuntimeModel
    { systemPrompt := some "system"
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }]
    }
  assertTrue (LeanAgent.AI.contentPlainText message.content == "runtime-ok") "expected runtime stream result"
  assertTrue ((← seenApiKey.get) == some "env-secret") "expected collection to inject auth"

def testModelsCollectionAppliesCloudflareAIGatewayAuth : IO Unit := do
  let seenApiKey ← IO.mkRef (some "unset" : Option String)
  let seenBaseUrl ← IO.mkRef ""
  let seenHeaders ← IO.mkRef (#[] : Array (String × Option String))
  let streams : LeanAgent.Models.ProviderStreams :=
    { streamSimple := fun model _context options => do
        seenApiKey.set options.apiKey
        seenBaseUrl.set model.baseUrl
        seenHeaders.set options.headers
        let timestamp ← IO.monoMsNow
        let message : LeanAgent.AI.AssistantMessage :=
          { content := #[LeanAgent.AI.text "cloudflare-ok"]
            api := model.api
            provider := model.provider
            model := model.id
            timestamp := timestamp
          }
        pure (LeanAgent.AI.fromMessage message)
    }
  let model : LeanAgent.Models.ModelInfo :=
    { id := "gpt-4o-mini"
      name := "Gateway GPT-4o mini"
      provider := "cloudflare-ai-gateway"
      api := "openai-completions"
      baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    }
  let collection ← LeanAgent.Models.createModels none fakeCloudflareAuthContext
  let provider ← LeanAgent.Models.createProvider
    { id := "cloudflare-ai-gateway"
      name := some "Cloudflare AI Gateway"
      auth := { apiKey := some LeanAgent.AI.Providers.CloudflareAuth.cloudflareAIGatewayAuth }
      models := #[model]
      apis := #[{ api := "openai-completions", streams := streams }]
    }
  collection.setProvider provider
  let message ← collection.completeSimple
    model
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }] }
  assertTrue (LeanAgent.AI.contentPlainText message.content == "cloudflare-ok")
    "expected Cloudflare collection dispatch"
  assertTrue ((← seenApiKey.get).isNone) "expected AI Gateway to avoid default api key"
  assertTrue
    ((← seenBaseUrl.get) == "https://gateway.ai.cloudflare.com/v1/acct-env/gateway-env/openai")
    "expected collection to apply Cloudflare base URL"
  let headers ← seenHeaders.get
  assertTrue (headerValueOpt? headers "cf-aig-authorization" == some (some "Bearer cf-env-key"))
    "expected Cloudflare auth header in stream options"
  assertTrue (headerValueOpt? headers "Authorization" == some (some ""))
    "expected Authorization suppression header in stream options"

def testCompatApiRegistryDispatchesAndUnregisters : IO Unit := do
  LeanAgent.AI.Compat.resetApiProviders
  let seenApiKey ← IO.mkRef (none : Option String)
  LeanAgent.AI.Compat.registerApiProvider
    { api := fakeRuntimeModel.api, streams := fakeRuntimeStreams seenApiKey }
    (some "compat-test")
  match ← LeanAgent.AI.Compat.getApiProvider? fakeRuntimeModel.api with
  | some provider => assertTrue (provider.api == fakeRuntimeModel.api) "expected compat provider lookup"
  | none => fail "expected compat provider"
  let message ← LeanAgent.AI.Compat.completeSimple
    fakeRuntimeModel
    { systemPrompt := some "system"
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }]
    }
    { apiKey := some "request-key" }
  assertTrue (LeanAgent.AI.contentPlainText message.content == "runtime-ok") "expected compat dispatch result"
  assertTrue ((← seenApiKey.get) == some "request-key") "expected compat dispatch to pass request api key"
  LeanAgent.AI.Compat.unregisterApiProviders "compat-test"
  assertTrue ((← LeanAgent.AI.Compat.getApiProvider? fakeRuntimeModel.api).isNone)
    "expected compat source unregister"
  LeanAgent.AI.Compat.resetApiProviders

def fakeImagesModel : LeanAgent.AI.ImagesModel :=
  { id := "fake-image-model"
    name := "Fake Image Model"
    provider := "fake-images"
    api := "fake-images-api"
    baseUrl := "https://images.example.test/v1"
    output := #["text", "image"]
  }

def testImagesApiRegistryDispatchesAndUnregisters : IO Unit := do
  LeanAgent.AI.Images.resetImagesApiProviders
  let seenApiKey ← IO.mkRef (none : Option String)
  let seenPrompt ← IO.mkRef ""
  LeanAgent.AI.Images.registerImagesApiProvider
    { api := fakeImagesModel.api
      generateImages := fun model context options => do
        seenApiKey.set options.apiKey
        seenPrompt.set (LeanAgent.AI.contentPlainText context.input)
        let timestamp ← IO.monoMsNow
        pure
          { api := model.api
            provider := model.provider
            model := model.id
            output :=
              #[ LeanAgent.AI.text "image-ready"
               , LeanAgent.AI.image "iVBORw0KGgo=" "image/png"
               ]
            timestamp := timestamp
          }
    }
    (some "images-test")
  match ← LeanAgent.AI.Images.getImagesApiProvider? fakeImagesModel.api with
  | some provider => assertTrue (provider.api == fakeImagesModel.api) "expected image provider lookup"
  | none => fail "expected image provider"
  let result ← LeanAgent.AI.Images.generateImages
    fakeImagesModel
    { input := #[LeanAgent.AI.text "draw a red circle"] }
    { apiKey := some "image-key" }
  assertTrue (LeanAgent.AI.contentPlainText result.output == "image-ready")
    "expected image dispatch text output"
  assertTrue (result.output.size == 2) "expected image dispatch output blocks"
  assertTrue ((← seenApiKey.get) == some "image-key") "expected image options passthrough"
  assertTrue ((← seenPrompt.get) == "draw a red circle") "expected image context passthrough"
  let mismatchFailed ←
    try
      let provider ← LeanAgent.AI.Images.resolveImagesApiProvider fakeImagesModel.api
      let _ ← provider.generateImages { fakeImagesModel with api := "other-images-api" } {} {}
      pure false
    catch err =>
      assertTrue
        (err.toString.contains "Mismatched api: other-images-api expected fake-images-api")
        "expected image api mismatch error"
      pure true
  assertTrue mismatchFailed "mismatched image api should fail"
  LeanAgent.AI.Images.unregisterImagesApiProviders "images-test"
  assertTrue ((← LeanAgent.AI.Images.getImagesApiProvider? fakeImagesModel.api).isNone)
    "expected image source unregister"
  LeanAgent.AI.Images.resetImagesApiProviders

def testImagesApiRegistryMissingProviderReturnsError : IO Unit := do
  LeanAgent.AI.Images.resetImagesApiProviders
  let failed ←
    try
      let _ ← LeanAgent.AI.Images.generateImages
        fakeImagesModel
        { input := #[LeanAgent.AI.text "draw"] }
      pure false
    catch err =>
      assertTrue
        (err.toString.contains "No API provider registered for api: fake-images-api")
        "expected missing image provider error"
      pure true
  assertTrue failed "missing image provider should fail"
  LeanAgent.AI.Images.resetImagesApiProviders

def testImagesBuiltInRegistryRestoresOpenRouter : IO Unit := do
  LeanAgent.AI.Images.resetImagesApiProviders
  assertTrue
    ((← LeanAgent.AI.Images.getImagesApiProvider? LeanAgent.AI.Api.OpenRouterImages.api).isSome)
    "expected reset to restore OpenRouter Images built-in"
  LeanAgent.AI.Images.clearImagesApiProviders
  assertTrue
    ((← LeanAgent.AI.Images.getImagesApiProvider? LeanAgent.AI.Api.OpenRouterImages.api).isNone)
    "expected clear to remove image providers"
  LeanAgent.AI.Images.resetImagesApiProviders
  assertTrue
    ((← LeanAgent.AI.Images.getImagesApiProvider? LeanAgent.AI.Api.OpenRouterImages.api).isSome)
    "expected reset to replay built-in image providers"

def testImageModelCatalogOpenRouter : IO Unit := do
  assertTrue
    (LeanAgent.AI.Images.Models.getImageProviders == #[LeanAgent.AI.Images.Models.openRouterProviderId])
    "expected OpenRouter image provider catalog"
  let models := LeanAgent.AI.Images.Models.getImageModels "openrouter"
  assertTrue (models.size == 37) "expected full OpenRouter image model catalog"
  match LeanAgent.AI.Images.Models.getImageModel? "openrouter" "google/gemini-2.5-flash-image" with
  | some model =>
      assertTrue (model.api == "openrouter-images") "expected OpenRouter Images api"
      assertTrue (model.output == #["image", "text"]) "expected image/text output metadata"
      assertTrue (model.cost.output == 2.5) "expected generated model cost metadata"
  | none => fail "expected Gemini image model"
  match LeanAgent.AI.Images.Models.getImageModel? "openrouter" "openrouter/auto" with
  | some model =>
      assertTrue (model.name == "Auto Router") "expected generated OpenRouter auto name"
      assertTrue (model.output == #["text", "image"]) "expected generated OpenRouter auto output order"
      assertTrue (model.cost.input == -1000000.0) "expected generated OpenRouter auto sentinel cost"
  | none => fail "expected OpenRouter auto image model"
  match LeanAgent.AI.Images.Models.getImageModel? "openrouter" "sourceful/riverflow-v2.5-pro" with
  | some model =>
      assertTrue (model.name == "Sourceful: Riverflow V2.5 Pro") "expected Sourceful generated model"
  | none => fail "expected Sourceful generated image model"
  assertTrue
    ((LeanAgent.AI.Images.Models.getImageModel? "missing" "google/gemini-2.5-flash-image").isNone)
    "expected missing image provider lookup to be empty"

def testImagesCollectionProviderCrudAndRefresh : IO Unit := do
  let collection ← LeanAgent.AI.Images.createImagesModels
  let refreshCount ← IO.mkRef 0
  let provider ← LeanAgent.AI.Images.createImagesProvider
    { id := "fake-images"
      name := some "Fake Images"
      auth := fakeProviderAuth
      models := #[fakeImagesModel]
      refreshModels := some (do
        refreshCount.modify (· + 1)
        pure #[{ fakeImagesModel with id := "refreshed-image-model" }]
      )
      api :=
        { generateImages := fun model _context _options => do
            let timestamp ← IO.monoMsNow
            pure
              { api := model.api
                provider := model.provider
                model := model.id
                output := #[LeanAgent.AI.text "ok"]
                timestamp := timestamp
              }
        }
    }
  collection.setProvider provider
  assertTrue ((← collection.getProviders).size == 1) "expected image provider registration"
  assertTrue ((← collection.getModels).size == 1) "expected image model listing"
  assertTrue ((← collection.getModel? "fake-images" "fake-image-model").isSome)
    "expected image model lookup"
  collection.refresh (some "fake-images")
  assertTrue ((← refreshCount.get) == 1) "expected targeted image refresh"
  assertTrue ((← collection.getModel? "fake-images" "refreshed-image-model").isSome)
    "expected refreshed image model"
  collection.deleteProvider "fake-images"
  assertTrue ((← collection.getProviders).isEmpty) "expected image provider deletion"
  collection.setProvider provider
  collection.clearProviders
  assertTrue ((← collection.getProviders).isEmpty) "expected image provider clear"

def testImagesCollectionAppliesAuthAndOptions : IO Unit := do
  let seenApiKey ← IO.mkRef (none : Option String)
  let seenBaseUrl ← IO.mkRef ""
  let seenHeaders ← IO.mkRef (#[] : Array (String × Option String))
  let seenEnv ← IO.mkRef (#[] : Array (String × String))
  let customAuth : LeanAgent.AI.Auth.ProviderAuth :=
    { apiKey :=
        some
          { name := "Image custom auth"
            resolve := fun _ctx _credential modelBaseUrl => do
              pure
                (some
                  { auth :=
                      { apiKey := some "auth-key"
                        baseUrl := some ((modelBaseUrl.getD "missing-base") ++ "/auth")
                        headers := #[("X-Auth", "yes"), ("X-Trace", "auth")]
                      }
                    env := #[("AUTH_ENV", "auth")]
                    source := some "image-auth"
                  })
          }
    }
  let provider ← LeanAgent.AI.Images.createImagesProvider
    { id := "fake-images"
      name := some "Fake Images"
      auth := customAuth
      models := #[fakeImagesModel]
      api :=
        { generateImages := fun model _context options => do
            seenApiKey.set options.apiKey
            seenBaseUrl.set model.baseUrl
            seenHeaders.set options.headers
            seenEnv.set options.env
            let timestamp ← IO.monoMsNow
            pure
              { api := model.api
                provider := model.provider
                model := model.id
                output := #[LeanAgent.AI.text "image-collection-ok"]
                timestamp := timestamp
              }
        }
    }
  let collection ← LeanAgent.AI.Images.createImagesModels
  collection.setProvider provider
  let result ← collection.generateImages
    fakeImagesModel
    { input := #[LeanAgent.AI.text "draw"] }
    { apiKey := some "request-key"
      headers := #[("X-Trace", some "request"), ("X-Req", some "yes")]
      env := #[("REQ_ENV", "request")]
    }
  assertTrue (LeanAgent.AI.contentPlainText result.output == "image-collection-ok")
    "expected image collection dispatch"
  assertTrue ((← seenApiKey.get) == some "request-key") "expected request API key to win"
  assertTrue ((← seenBaseUrl.get) == fakeImagesModel.baseUrl ++ "/auth") "expected auth base URL override"
  let headers ← seenHeaders.get
  assertTrue (headerValueOpt? headers "X-Auth" == some (some "yes")) "expected inherited auth header"
  assertTrue (headerValueOpt? headers "X-Trace" == some (some "request")) "expected request header override"
  assertTrue (headerValueOpt? headers "X-Req" == some (some "yes")) "expected request header"
  let env ← seenEnv.get
  assertTrue (LeanAgent.AI.Auth.providerEnvGet? env "AUTH_ENV" == some "auth") "expected auth env"
  assertTrue (LeanAgent.AI.Auth.providerEnvGet? env "REQ_ENV" == some "request") "expected request env"

def testImagesCollectionUnknownProviderReturnsError : IO Unit := do
  let collection ← LeanAgent.AI.Images.createImagesModels
  let result ← collection.generateImages fakeImagesModel { input := #[LeanAgent.AI.text "draw"] }
  assertTrue (result.stopReason == .error) "expected unknown image provider error result"
  assertTrue
    (match result.errorMessage with
     | some message => message.contains "Unknown provider: fake-images"
     | none => false)
    "expected unknown provider error message"

def fakeOpenRouterImagesAuthContext : LeanAgent.AI.Auth.AuthContext :=
  { env := fun name =>
      pure
        (if name == LeanAgent.AI.Api.OpenRouterImages.apiKeyEnv then
          some "openrouter-image-key"
        else
          none)
    fileExists := fun _ => pure false
  }

def testOpenRouterImagesProviderFactoryAuthAndModels : IO Unit := do
  let provider ← LeanAgent.AI.Providers.OpenRouterImages.openRouterImagesProvider
  assertTrue (provider.id == "openrouter") "expected OpenRouter image provider id"
  assertTrue (provider.name == "OpenRouter") "expected OpenRouter image provider name"
  assertTrue ((← provider.getModels).size == 37) "expected OpenRouter image provider models"
  let collection ← LeanAgent.AI.Images.createImagesModels none fakeOpenRouterImagesAuthContext
  collection.setProvider provider
  match ← collection.getModel? "openrouter" "openrouter/auto" with
  | some model =>
      match ← collection.getAuth model with
      | some result =>
          assertTrue (result.auth.apiKey == some "openrouter-image-key")
            "expected OpenRouter image env auth"
          assertTrue (result.source == some LeanAgent.AI.Api.OpenRouterImages.apiKeyEnv)
            "expected OpenRouter image env source"
      | none => fail "expected OpenRouter image auth"
  | none => fail "expected OpenRouter auto image model"

def testCompatInjectsEnvApiKeyForKnownProviders : IO Unit := do
  LeanAgent.AI.Compat.resetApiProviders
  let seenApiKey ← IO.mkRef (none : Option String)
  LeanAgent.AI.Compat.registerApiProvider
    { api := "openai-completions", streams := fakeRuntimeStreams seenApiKey }
    (some "compat-openai-override")
  let model :=
    { fakeRuntimeModel with
      id := "compat-openai"
      provider := LeanAgent.Models.openAIProviderId
      api := "openai-completions"
    }
  let _ ← LeanAgent.AI.Compat.completeSimple
    model
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }] }
    { env := #[(LeanAgent.Models.openAIKeyEnv, "env-openai-key")] }
  assertTrue ((← seenApiKey.get) == some "env-openai-key") "expected compat env API key injection"
  LeanAgent.AI.Compat.resetApiProviders

def testCompatInjectsEnvApiKeyForMappedProvidersOutsideCatalog : IO Unit := do
  LeanAgent.AI.Compat.resetApiProviders
  let seenApiKey ← IO.mkRef (none : Option String)
  LeanAgent.AI.Compat.registerApiProvider
    { api := "anthropic-messages", streams := fakeRuntimeStreams seenApiKey }
    (some "compat-anthropic-env")
  let model :=
    { fakeRuntimeModel with
      id := "claude-sonnet"
      provider := "anthropic"
      api := "anthropic-messages"
    }
  let _ ← LeanAgent.AI.Compat.completeSimple
    model
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }] }
    { env := #[("ANTHROPIC_OAUTH_TOKEN", "oauth-token")] }
  assertTrue ((← seenApiKey.get) == some "oauth-token")
    "expected compat env API key injection outside default catalog"
  LeanAgent.AI.Compat.resetApiProviders

def testCompatMissingProviderReturnsError : IO Unit := do
  LeanAgent.AI.Compat.clearApiProviders
  let failed ←
    try
      let _ ← LeanAgent.AI.Compat.completeSimple fakeRuntimeModel {}
      pure false
    catch err =>
      assertTrue (err.toString.contains "No API provider registered") "expected missing compat provider error"
      pure true
  assertTrue failed "expected compat dispatch to fail without provider"
  LeanAgent.AI.Compat.resetApiProviders

def testCompatLegacyAliasesDispatchFixedApi : IO Unit := do
  LeanAgent.AI.Compat.resetApiProviders
  let seenApiKey ← IO.mkRef (none : Option String)
  LeanAgent.AI.Compat.registerApiProvider
    { api := "openai-completions", streams := fakeRuntimeStreams seenApiKey }
    (some "compat-alias-openai")
  let model :=
    { fakeRuntimeModel with
      id := "alias-openai"
      provider := LeanAgent.Models.openAIProviderId
      api := "openai-completions"
    }
  let stream ← LeanAgent.AI.Compat.Aliases.streamSimpleOpenAICompletions
    model
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }] }
    { apiKey := some "alias-key" }
  assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "runtime-ok")
    "expected legacy OpenAI completions alias to dispatch"
  assertTrue ((← seenApiKey.get) == some "alias-key") "expected alias to pass api key"
  LeanAgent.AI.Compat.resetApiProviders

def testCompatLegacyAliasesRejectMismatchedApi : IO Unit := do
  LeanAgent.AI.Compat.resetApiProviders
  let seenApiKey ← IO.mkRef (none : Option String)
  LeanAgent.AI.Compat.registerApiProvider
    { api := "openai-completions", streams := fakeRuntimeStreams seenApiKey }
    (some "compat-alias-openai")
  let failed ←
    try
      let _ ← LeanAgent.AI.Compat.Aliases.streamSimpleOpenAICompletions fakeRuntimeModel {} {}
      pure false
    catch err =>
      assertTrue (err.toString.contains "Mismatched api") "expected fixed alias api mismatch"
      pure true
  assertTrue failed "expected legacy alias to reject mismatched model api"
  LeanAgent.AI.Compat.resetApiProviders

def testCompatLegacyAliasesUseRegistryForNonBuiltins : IO Unit := do
  LeanAgent.AI.Compat.resetApiProviders
  let seenApiKey ← IO.mkRef (none : Option String)
  let model :=
    { fakeRuntimeModel with
      id := "claude"
      provider := "anthropic"
      api := "anthropic-messages"
    }
  let missing ←
    try
      let _ ← LeanAgent.AI.Compat.Aliases.streamSimpleAnthropic model {} {}
      pure false
    catch err =>
      assertTrue (err.toString.contains "No API provider registered") "expected missing Anthropic alias provider"
      pure true
  assertTrue missing "expected missing non-builtin alias provider"
  LeanAgent.AI.Compat.registerApiProvider
    { api := "anthropic-messages", streams := fakeRuntimeStreams seenApiKey }
    (some "compat-alias-anthropic")
  let message ← LeanAgent.AI.Compat.Aliases.streamSimpleAnthropic
    model
    {}
    { apiKey := some "anthropic-key" }
  assertTrue (LeanAgent.AI.contentPlainText message.result.content == "runtime-ok")
    "expected registered Anthropic alias provider"
  assertTrue ((← seenApiKey.get) == some "anthropic-key") "expected Anthropic alias api key"
  LeanAgent.AI.Compat.resetApiProviders

def assertLazyErrorStream
    (stream : LeanAgent.AI.AssistantMessageEventStream)
    (expectedMessage : String) : IO Unit := do
  assertTrue stream.isComplete "expected lazy error stream to complete"
  assertTrue (stream.result.stopReason == .error) "expected lazy setup error stop reason"
  assertTrue (stream.result.errorMessage.any (fun message => message.contains expectedMessage))
    "expected lazy setup error message"
  assertTrue (stream.result.api == fakeRuntimeModel.api) "expected lazy error api"
  assertTrue (stream.result.provider == fakeRuntimeModel.provider) "expected lazy error provider"
  assertTrue (stream.result.model == fakeRuntimeModel.id) "expected lazy error model"
  match stream.events.back? with
  | some (.error .error message) =>
      assertTrue (message.errorMessage.any (fun value => value.contains expectedMessage))
        "expected final lazy error event"
  | _ => fail "expected final lazy error event"

def testModelsCreateProviderMissingApiReturnsLazyErrorStream : IO Unit := do
  let provider ← LeanAgent.Models.createProvider
    { id := "fake"
      name := some "Fake"
      auth := {}
      models := #[fakeRuntimeModel]
      apis := #[]
    }
  let stream ← provider.streamSimple fakeRuntimeModel {} {}
  assertLazyErrorStream stream "has no API implementation"

def testModelsCreateProviderSetupFailureReturnsLazyErrorStream : IO Unit := do
  let streams : LeanAgent.Models.ProviderStreams :=
    { streamSimple := fun _ _ _ => throw (IO.userError "setup failed") }
  let provider ← LeanAgent.Models.createProvider
    { id := "fake"
      name := some "Fake"
      auth := {}
      models := #[fakeRuntimeModel]
      apis := #[{ api := fakeRuntimeModel.api, streams := streams }]
    }
  let stream ← provider.streamSimple fakeRuntimeModel {} {}
  assertLazyErrorStream stream "setup failed"

def testModelsLazyProviderStreamsLoadFailureReturnsErrorStream : IO Unit := do
  let streams := LeanAgent.Models.ProviderStreams.lazy (throw (IO.userError "load failed"))
  let stream ← streams.streamSimple fakeRuntimeModel {} {}
  assertLazyErrorStream stream "load failed"

def testModelsCalculateCost : IO Unit := do
  let model :=
    { fakeRuntimeModel with
      cost :=
        { input := 1.0
          output := 2.0
          cacheRead := 0.5
          cacheWrite := 3.0
        }
    }
  let usage : LeanAgent.AI.Usage :=
    { input := 1000000
      output := 2000000
      cacheRead := 1000000
      cacheWrite := 3000000
      cacheWrite1h := some 1000000
    }
  let cost := LeanAgent.Models.calculateCost model usage
  assertTrue (cost.input == 1.0) "expected input cost"
  assertTrue (cost.output == 4.0) "expected output cost"
  assertTrue (cost.cacheRead == 0.5) "expected cache read cost"
  assertTrue (cost.cacheWrite == 8.0) "expected cache write cost"
  assertTrue (cost.total == 13.5) "expected total cost"

def testModelsThinkingLevelMapSupport : IO Unit := do
  assertTrue
    (LeanAgent.Models.getSupportedThinkingLevels fakeRuntimeModel == #[.off])
    "expected non-reasoning model to support off only"
  let defaultReasoning := { fakeRuntimeModel with reasoning := true }
  assertTrue
    (LeanAgent.Models.getSupportedThinkingLevels defaultReasoning ==
      #[.off, .level .minimal, .level .low, .level .medium, .level .high])
    "expected reasoning model to omit xhigh unless mapped"
  let proModel :=
    { defaultReasoning with
      thinkingLevelMap :=
        #[ { level := .off, mapped := none }
         , { level := .level .minimal, mapped := none }
         , { level := .level .low, mapped := none }
         , { level := .level .xhigh, mapped := some "xhigh" }
         ]
    }
  assertTrue
    (LeanAgent.Models.getSupportedThinkingLevels proModel ==
      #[.level .medium, .level .high, .level .xhigh])
    "expected thinking map to suppress null levels and enable xhigh"
  assertTrue
    (LeanAgent.Models.clampThinkingLevel proModel (.level .low) == .level .medium)
    "expected unsupported low to clamp upward to medium"
  let noXHigh := { defaultReasoning with thinkingLevelMap := #[] }
  assertTrue
    (LeanAgent.Models.clampThinkingLevel noXHigh (.level .xhigh) == .level .high)
    "expected unmapped xhigh to clamp downward to high"
  assertTrue
    (LeanAgent.Models.thinkingLevelMapValue? proModel (.level .xhigh) == some (some "xhigh"))
    "expected mapped xhigh value"
  assertTrue
    (LeanAgent.Models.thinkingLevelMapValue? proModel .off == some none)
    "expected null off mapping"

def testModelsClampSimpleOptionsClampsReasoning : IO Unit := do
  let model :=
    { fakeRuntimeModel with
      reasoning := true
      maxTokens := 1000
      thinkingLevelMap := #[{ level := .level .xhigh, mapped := some "xhigh" }]
    }
  let options := LeanAgent.Models.clampSimpleOptionsToContext model {} { reasoning := some .xhigh }
  assertTrue (options.reasoning == some .xhigh) "expected mapped xhigh to be preserved"
  let noXHigh := { model with thinkingLevelMap := #[] }
  let downgraded := LeanAgent.Models.clampSimpleOptionsToContext noXHigh {} { reasoning := some .xhigh }
  assertTrue (downgraded.reasoning == some .high) "expected unmapped xhigh to downgrade to high"
  let noReasoning := LeanAgent.Models.clampSimpleOptionsToContext fakeRuntimeModel {} { reasoning := some .high }
  assertTrue noReasoning.reasoning.isNone "expected non-reasoning model to disable reasoning"

def fauxContext (text : String := "hi") : LeanAgent.AI.Context :=
  { systemPrompt := some "Be concise."
    messages := #[.user { content := #[LeanAgent.AI.text text], timestamp := 1 }]
  }

def testFauxProviderQueuesResponses : IO Unit := do
  let handle ← LeanAgent.AI.Providers.Faux.fauxProvider
  handle.setResponses
    #[ .message (LeanAgent.AI.Providers.Faux.fauxTextMessage "first")
     , .message (LeanAgent.AI.Providers.Faux.fauxTextMessage "second")
     ]
  let collection ← LeanAgent.Models.createModels
  collection.setProvider handle.provider
  let model := handle.getModel
  let first ← collection.completeSimple model (fauxContext)
  let second ← collection.completeSimple model (fauxContext)
  let exhausted ← collection.completeSimple model (fauxContext)
  assertTrue (LeanAgent.AI.contentPlainText first.content == "first") "expected first faux response"
  assertTrue (LeanAgent.AI.contentPlainText second.content == "second") "expected second faux response"
  assertTrue (exhausted.stopReason == .error) "expected exhausted faux response to error"
  assertTrue (exhausted.errorMessage == some "No more faux responses queued") "expected exhausted error message"
  assertTrue ((← handle.getPendingResponseCount) == 0) "expected empty faux queue"
  assertTrue ((← handle.state).callCount == 3) "expected faux call count"
  assertTrue (first.usage.input > 0) "expected faux input usage"
  assertTrue (first.usage.output > 0) "expected faux output usage"
  assertTrue (first.usage.totalTokens == first.usage.input + first.usage.output) "expected faux total usage"

def testFauxProviderHelperBlocksAndEvents : IO Unit := do
  let handle ← LeanAgent.AI.Providers.Faux.fauxProvider
  let toolArgs := LeanAgent.Json.obj [("text", LeanAgent.Json.str "hi")]
  handle.setResponses
    #[ .message
        (LeanAgent.AI.Providers.Faux.fauxAssistantMessage
          #[ LeanAgent.AI.Providers.Faux.fauxThinking "think"
           , LeanAgent.AI.Providers.Faux.fauxToolCall "echo" toolArgs "tool-1"
           , LeanAgent.AI.Providers.Faux.fauxText "done"
           ]
          .toolUse)
     ]
  let stream ← handle.provider.streamSimple handle.getModel (fauxContext) {}
  let response := stream.result
  assertTrue (response.stopReason == .toolUse) "expected faux tool-use stop"
  assertTrue
    (response.content.any fun
      | .thinking content => content.thinking == "think"
      | _ => false)
    "expected faux thinking block"
  match LeanAgent.AI.contentToolCalls response.content |>.toList with
  | [call] =>
      assertTrue (call.id == "tool-1") "expected faux tool id"
      assertTrue (call.name == "echo") "expected faux tool name"
      assertTrue (call.arguments == toolArgs) "expected faux tool args"
  | _ => fail "expected one faux tool call"
  assertTrue
    (stream.events.any fun
      | .thinkingDelta _ "think" _ => true
      | _ => false)
    "expected faux thinking event"
  assertTrue
    (stream.events.any fun
      | .toolCallEnd _ call _ => call.name == "echo"
      | _ => false)
    "expected faux tool event"

def testFauxProviderModelsFactoriesAndCache : IO Unit := do
  let handle ← LeanAgent.AI.Providers.Faux.fauxProvider
    { api := some "faux:test"
      provider := some "faux-provider"
      models :=
        #[ { id := "faux-fast", reasoning := false }
         , { id := "faux-thinker", reasoning := true }
         ]
    }
  handle.setResponses
    #[ .factory (fun _context _options state model =>
          pure (LeanAgent.AI.Providers.Faux.fauxTextMessage s!"{model.id}:{model.reasoning}:{state.callCount}"))
     , .message (LeanAgent.AI.Providers.Faux.fauxTextMessage "cached")
     ]
  match handle.getModel? "faux-thinker" with
  | some thinker =>
      assertTrue thinker.reasoning "expected faux thinker reasoning model"
      let first ← handle.provider.completeSimple thinker (fauxContext)
        { sessionId := some "session-1", cacheRetention := some .short }
      assertTrue (LeanAgent.AI.contentPlainText first.content == "faux-thinker:true:1")
        "expected model-aware faux factory"
      assertTrue (first.api == "faux:test") "expected faux api rewrite"
      assertTrue (first.provider == "faux-provider") "expected faux provider rewrite"
      assertTrue (first.model == "faux-thinker") "expected faux model rewrite"
      assertTrue (first.usage.cacheWrite > 0) "expected first cached request to write prompt"
      let followupContext : LeanAgent.AI.Context :=
        { systemPrompt := some "Be concise."
          messages :=
            #[ .user { content := #[LeanAgent.AI.text "hi"], timestamp := 1 }
             , .assistant first
             , .user { content := #[LeanAgent.AI.text "follow up"], timestamp := 2 }
             ]
        }
      let second ← handle.provider.completeSimple thinker followupContext
        { sessionId := some "session-1", cacheRetention := some .short }
      assertTrue (LeanAgent.AI.contentPlainText second.content == "cached") "expected queued cached response"
      assertTrue (second.usage.cacheRead > 0) "expected follow-up to read prompt cache"
  | none => fail "expected faux thinker model"

def testAIContentBlockJsonRoundTrip : IO Unit := do
  let block : LeanAgent.AI.ContentBlock :=
    .toolCall
      { id := "call-1"
        name := "read"
        arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
      }
  match LeanAgent.AI.contentBlockFromJson (LeanAgent.AI.contentBlockToJson block) with
  | .ok parsed =>
      match parsed with
      | .toolCall call =>
          assertTrue (call.id == "call-1") "expected tool call id"
          assertTrue (call.name == "read") "expected tool call name"
      | _ => fail "expected tool call block"
  | .error err => fail s!"content block round-trip failed: {err}"

def testAIMessageJsonRoundTrip : IO Unit := do
  let usage : LeanAgent.AI.Usage :=
    { input := 11
      output := 7
      cacheRead := 3
      cacheWrite := 2
      totalTokens := 20
      cost := { input := 0.1, output := 0.2, cacheRead := 0.03, cacheWrite := 0.04, total := 0.37 }
    }
  let diagnostic : LeanAgent.AI.AssistantMessageDiagnostic :=
    { type := "provider_error"
      timestamp := 122
      error :=
        some
          { name := some "RateLimitError"
            message := "rate limit exceeded"
            code := some (LeanAgent.Json.str "rate_limit")
          }
      details := some (LeanAgent.Json.obj [("status", LeanAgent.Json.nat 429)])
    }
  let message : LeanAgent.AI.Message :=
    .assistant
      { content := #[LeanAgent.AI.text "hello", LeanAgent.AI.thinking "scratch"]
        api := "openai-completions"
        provider := "deepseek"
        model := "deepseek-v4-flash"
        usage := usage
        stopReason := .stop
        diagnostics := #[diagnostic]
        timestamp := 123
      }
  match LeanAgent.AI.messageFromJson (LeanAgent.AI.messageToJson message) with
  | .ok (.assistant parsed) =>
      assertTrue (parsed.provider == "deepseek") "expected provider to round-trip"
      assertTrue (parsed.usage.totalTokens == 20) "expected usage to round-trip"
      assertTrue (LeanAgent.AI.contentPlainText parsed.content == "hello\nscratch") "expected text content"
      assertTrue (parsed.diagnostics.size == 1) "expected diagnostics to round-trip"
  | .ok _ => fail "expected assistant message"
  | .error err => fail s!"message round-trip failed: {err}"

def testAIMessageLegacyConversion : IO Unit := do
  let legacy : AgentMessage :=
    .assistant
      "need file"
      #[{ id := "call-read", name := "read", arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")] }]
  let ai := LeanAgent.AI.fromLegacyMessage "openai-completions" "deepseek" "deepseek-v4-flash" 42 legacy
  match ai with
  | .assistant message =>
      assertTrue (message.stopReason == .toolUse) "expected toolUse stop reason for assistant with tool calls"
      assertTrue ((LeanAgent.AI.contentToolCalls message.content).size == 1) "expected one tool call"
  | _ => fail "expected assistant conversion"
  match LeanAgent.AI.toLegacyMessage ai with
  | .assistant content calls =>
      assertTrue (content == "need file") "expected assistant text to convert back"
      assertTrue (calls.size == 1) "expected tool call to convert back"
  | _ => fail "expected legacy assistant"

def testAIEventStreamTextResult : IO Unit := do
  let message : LeanAgent.AI.AssistantMessage :=
    { content := #[LeanAgent.AI.text "hello"]
      api := "openai-completions"
      provider := "deepseek"
      model := "deepseek-v4-flash"
      stopReason := .stop
      timestamp := 1
    }
  let stream := LeanAgent.AI.fromMessage message
  assertTrue stream.isComplete "expected complete stream"
  assertTrue (stream.result == message) "expected result to return final message"
  assertTrue (stream.events.size == 5) "expected start, text start/delta/end, done"
  match stream.events[0]?, stream.events[1]?, stream.events[2]?, stream.events[4]? with
  | some (LeanAgent.AI.AssistantMessageEvent.start _),
    some (LeanAgent.AI.AssistantMessageEvent.textStart 0 _),
    some (LeanAgent.AI.AssistantMessageEvent.textDelta 0 "hello" _),
    some (LeanAgent.AI.AssistantMessageEvent.done LeanAgent.AI.StopReason.stop result) =>
      assertTrue (result == message) "expected done event to contain message"
  | _, _, _, _ => fail "unexpected text event sequence"

def testAIEventStreamPartialSnapshots : IO Unit := do
  let toolArgs := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
  let message : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ LeanAgent.AI.text "hello"
         , LeanAgent.AI.ContentBlock.toolCall
            { id := "call-1", name := "read", arguments := toolArgs }
         ]
      api := "faux"
      provider := "faux"
      model := "faux-1"
      stopReason := .toolUse
      timestamp := 1
    }
  let stream := LeanAgent.AI.fromMessage message
  match stream.events[0]? with
  | some (LeanAgent.AI.AssistantMessageEvent.start snapshot) =>
      assertTrue snapshot.content.isEmpty "expected start snapshot to have empty content"
  | _ => fail "expected start event"
  match stream.events[1]?, stream.events[2]?, stream.events[4]?, stream.events[5]? with
  | some (LeanAgent.AI.AssistantMessageEvent.textStart 0 snapshot),
    some (LeanAgent.AI.AssistantMessageEvent.textDelta 0 "hello" deltaSnapshot),
    some (LeanAgent.AI.AssistantMessageEvent.toolCallStart 1 toolStartSnapshot),
    some (LeanAgent.AI.AssistantMessageEvent.toolCallDelta 1 rawArgs toolDeltaSnapshot) =>
      assertTrue
        (snapshot.content == #[LeanAgent.AI.ContentBlock.text { text := "" }])
        "expected text_start snapshot to contain empty text block"
      assertTrue (LeanAgent.AI.contentPlainText deltaSnapshot.content == "hello")
        "expected text_delta snapshot to contain accumulated text"
      match LeanAgent.AI.contentToolCalls toolStartSnapshot.content |>.toList,
            LeanAgent.AI.contentToolCalls toolDeltaSnapshot.content |>.toList with
      | [startCall], [deltaCall] =>
          assertTrue (startCall.arguments == LeanAgent.Json.obj []) "expected tool start empty args"
          assertTrue (deltaCall.arguments == LeanAgent.Json.obj []) "expected tool delta empty/partial args"
          assertTrue (rawArgs == toolArgs.compress) "expected tool delta payload"
      | _, _ => fail "expected partial tool calls"
  | _, _, _, _ => fail "unexpected partial event snapshots"
  match stream.events[6]? with
  | some (LeanAgent.AI.AssistantMessageEvent.toolCallEnd 1 call snapshot) =>
      assertTrue (call.arguments == toolArgs) "expected final tool args on tool end"
      match LeanAgent.AI.contentToolCalls snapshot.content |>.toList with
      | [snapshotCall] => assertTrue (snapshotCall.arguments == toolArgs) "expected end snapshot final args"
      | _ => fail "expected end snapshot tool call"
  | _ => fail "expected tool call end event"

def testAIEventStreamEmptyContentCompletes : IO Unit := do
  let message : LeanAgent.AI.AssistantMessage :=
    { content := #[]
      api := "faux"
      provider := "faux"
      model := "faux-1"
      stopReason := .stop
      timestamp := 1
    }
  let stream := LeanAgent.AI.fromMessage message
  assertTrue stream.isComplete "expected empty-content stream to complete"
  assertTrue (stream.events.size == 2) "expected start and done events only"
  match stream.events[0]?, stream.events[1]? with
  | some (LeanAgent.AI.AssistantMessageEvent.start snapshot),
    some (LeanAgent.AI.AssistantMessageEvent.done .stop result) =>
      assertTrue snapshot.content.isEmpty "expected empty start snapshot"
      assertTrue (result == message) "expected empty final message"
  | _, _ => fail "unexpected empty-content event sequence"

def testAIEventStreamToolUseResult : IO Unit := do
  let response : ProviderResponse :=
    { content := ""
      toolCalls :=
        #[{ id := "call-1"
            name := "read"
            arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
          }]
      finishReason := some "tool_calls"
    }
  let stream := LeanAgent.AI.streamFromLegacyProviderResponse "openai-completions" "deepseek" "deepseek-v4-flash" 2 response
  let result := stream.result
  assertTrue (result.stopReason == .toolUse) "expected toolUse stop reason"
  assertTrue ((LeanAgent.AI.contentToolCalls result.content).size == 1) "expected tool call in result"
  assertTrue (stream.events.any (fun event =>
    match event with
    | .toolCallStart 0 _ => true
    | _ => false)) "expected tool call start event"
  match stream.events.back? with
  | some (.done .toolUse message) =>
      assertTrue (message == result) "expected done result"
  | _ => fail "expected toolUse done event"

def streamProvider : ModelProvider :=
  { complete := fun _ => pure { content := "streamed", toolCalls := #[], finishReason := some "stop" } }

def testAIEventStreamLegacyProviderWrapper : IO Unit := do
  let request : ProviderRequest :=
    { model := "fake-model"
      system := "system"
      messages := #[.user "hello"]
      tools := #[]
    }
  let stream ← LeanAgent.AI.streamLegacyProvider streamProvider request "openai-completions" "test-provider"
  assertTrue (stream.result.model == "fake-model") "expected request model on result"
  assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "streamed") "expected provider content"
  assertTrue stream.isComplete "expected wrapper stream to be complete"

def eventBridgeProvider : ModelProvider :=
  { complete := fun _ => pure { content := "bridged", toolCalls := #[], finishReason := some "stop" } }

def testAgentLoopUsesAssistantEventStreamBridge : IO Unit := do
  let events ← IO.mkRef #[]
  let sink : EventSink := fun event => do
    let label :=
      match event with
      | .messageStart "assistant" => some "message_start"
      | .messageDelta "bridged" => some "message_delta"
      | .messageEnd (.assistant "bridged" calls) =>
          if calls.isEmpty then some "message_end" else none
      | _ => none
    match label with
    | some value => events.modify (fun current => current.push value)
    | none => pure ()
  let messages ← runAgentLoop
    { provider := eventBridgeProvider
      model := "fake"
      system := defaultSystemPrompt
      tools := #[]
      maxTurns := 1
    }
    #[.user "hello"]
    sink
  let labels ← events.get
  assertTrue (labels == #["message_start", "message_delta", "message_end"]) "expected assistant stream events"
  match messages.back? with
  | some (.assistant "bridged" calls) => assertTrue calls.isEmpty "expected final assistant message"
  | _ => fail "expected assistant message from stream bridge"

def continueProvider : ModelProvider :=
  { complete := fun _ => pure { content := "continued", toolCalls := #[] } }

def testAgentSessionCreateAndContinue : IO Unit :=
  IO.FS.withTempDir fun root => do
    let path := root / "session.jsonl"
    let config : AgentLoopConfig :=
      { provider := continueProvider
        model := "fake"
        system := defaultSystemPrompt
        tools := #[]
        maxTurns := 1
      }
    let session ← LeanAgent.Session.create config root "fake" (.create path)
    let session := { session with messages := #[AgentMessage.user "continue"] }
    let session ← LeanAgent.Session.continueSession session silentSink
    assertTrue (session.messages.size == 2) "continue should append assistant message"
    let (messages, _) ← LeanAgent.Session.loadMessagesWithLastId path
    assertTrue (messages.size == 1) "continue should persist only new messages"
    match messages[0]? with
    | some (AgentMessage.assistant "continued" _) => pure ()
    | _ => fail "expected persisted assistant continuation"

def testAgentSessionRejectsAssistantContinue : IO Unit := do
  let config : AgentLoopConfig :=
    { provider := continueProvider
      model := "fake"
      system := defaultSystemPrompt
      tools := #[]
      maxTurns := 1
    }
  let session : LeanAgent.Session.AgentSession :=
    { config := config
      messages := #[AgentMessage.assistant "done" #[]]
    }
  let failed ←
    try
      let _ ← LeanAgent.Session.continueSession session silentSink
      pure false
    catch err =>
      assertTrue (err.toString.contains "cannot continue after an assistant message") "expected assistant-final continue error"
      pure true
  assertTrue failed "assistant-final session should not continue"

def testJsonEventShape : IO Unit := do
  let json ← LeanAgent.Session.jsonEvent (.turnStart 3)
  match LeanAgent.Json.optVal? json "type", LeanAgent.Json.optVal? json "turn", LeanAgent.Json.optVal? json "timestamp" with
  | some (Lean.Json.str "turn_start"), some _, some _ => pure ()
  | _, _, _ => fail "expected JSON event fields"

def httpServerScript : String :=
  String.intercalate "\n"
    [ "import json"
    , "import sys"
    , "from http.server import BaseHTTPRequestHandler, HTTPServer"
    , "class Handler(BaseHTTPRequestHandler):"
    , "    retry_count = 0"
    , "    def do_POST(self):"
    , "        length = int(self.headers.get('Content-Length', '0'))"
    , "        body = self.rfile.read(length).decode('utf-8')"
    , "        if self.path == '/retry-openai/chat/completions':"
    , "            Handler.retry_count += 1"
    , "            if Handler.retry_count == 1:"
    , "                payload = json.dumps({'error': {'message': 'service unavailable'}}).encode('utf-8')"
    , "                self.send_response(503)"
    , "            else:"
    , "                payload = json.dumps({'choices': [{'message': {'content': 'retried'}, 'finish_reason': 'stop'}]}).encode('utf-8')"
    , "                self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/diagnostic-openai/chat/completions':"
    , "            payload = json.dumps({'error': {'message': 'rate limit exceeded', 'type': 'rate_limit_error', 'code': 'rate_limit'}}).encode('utf-8')"
    , "            self.send_response(429)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/headers-openai/chat/completions':"
    , "            payload = json.dumps({'choices': [{'message': {'content': self.headers.get('X-Trace') or ''}, 'finish_reason': 'stop'}]}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/payload-hook-openai/chat/completions':"
    , "            request = json.loads(body)"
    , "            payload = json.dumps({'choices': [{'message': {'content': request.get('model') or ''}, 'finish_reason': 'stop'}]}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('X-Hook-Response', 'openai')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/runtime-stream-openai/chat/completions':"
    , "            request = json.loads(body)"
    , "            ok = request.get('stream') is True and request.get('stream_options', {}).get('include_usage') is True"
    , "            text = 'streamed' if ok else 'missing-stream-options'"
    , "            payload = ("
    , "                'data: ' + json.dumps({'choices': [{'delta': {'content': text[:6]}, 'finish_reason': None}]}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'choices': [{'delta': {'content': text[6:]}, 'finish_reason': 'stop'}], 'usage': {'prompt_tokens': 4, 'completion_tokens': 2}}) + '\\n\\n' +"
    , "                'data: [DONE]\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/cloudflare-openai/acct-env/gateway-env/chat/completions':"
    , "            request = json.loads(body)"
    , "            text = '|'.join([self.headers.get('cf-aig-authorization') or '', self.headers.get('Authorization') or '', request.get('model') or ''])"
    , "            payload = ("
    , "                'data: ' + json.dumps({'choices': [{'delta': {'content': text}, 'finish_reason': 'stop'}], 'usage': {'prompt_tokens': 1, 'completion_tokens': 1}}) + '\\n\\n' +"
    , "                'data: [DONE]\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/openrouter-images/chat/completions':"
    , "            request = json.loads(body)"
    , "            content = request.get('messages', [{}])[0].get('content', [])"
    , "            first_type = content[0].get('type') if content else ''"
    , "            second_url = content[1].get('image_url', {}).get('url') if len(content) > 1 else ''"
    , "            text = '|'.join([request.get('model') or '', self.headers.get('Authorization') or '', self.headers.get('X-Trace') or '', ','.join(request.get('modalities') or []), first_type or '', second_url or ''])"
    , "            payload = json.dumps({'id': 'img_resp', 'choices': [{'message': {'content': text, 'images': [{'image_url': 'data:image/png;base64,QUJD'}, {'image_url': {'url': 'data:image/jpeg;base64,REVGRw=='}}, {'image_url': 'https://ignored.example/image.png'}]}}], 'usage': {'prompt_tokens': 10, 'completion_tokens': 3, 'prompt_tokens_details': {'cached_tokens': 4, 'cache_write_tokens': 1}}}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('X-Hook-Response', 'openrouter-images')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/responses-runtime/responses':"
    , "            request = json.loads(body)"
    , "            ok = request.get('model') == 'gpt-5.5' and request.get('stream') is False and request.get('prompt_cache_key') == 'session-123'"
    , "            text = '|'.join(['ok' if ok else 'bad', self.headers.get('session_id') or '', self.headers.get('x-client-request-id') or '', self.headers.get('X-Trace') or ''])"
    , "            payload = json.dumps({'id': 'resp_http', 'status': 'completed', 'output': [{'type': 'message', 'id': 'msg_http', 'content': [{'type': 'output_text', 'text': text}]}], 'usage': {'input_tokens': 6, 'output_tokens': 2, 'total_tokens': 8, 'input_tokens_details': {'cached_tokens': 1}}}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/payload-hook-responses/responses':"
    , "            request = json.loads(body)"
    , "            text = request.get('model') or ''"
    , "            payload = json.dumps({'id': 'resp_hook', 'status': 'completed', 'output': [{'type': 'message', 'id': 'msg_hook', 'content': [{'type': 'output_text', 'text': text}]}]}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('X-Hook-Response', 'responses')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/clamp-openai/chat/completions':"
    , "            request = json.loads(body)"
    , "            text = str(request.get('max_tokens'))"
    , "            payload = ("
    , "                'data: ' + json.dumps({'choices': [{'delta': {'content': text}, 'finish_reason': 'stop'}], 'usage': {'prompt_tokens': 4, 'completion_tokens': 2}}) + '\\n\\n' +"
    , "                'data: [DONE]\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/responses-copilot/responses':"
    , "            request = json.loads(body)"
    , "            text = '|'.join([self.headers.get('X-Initiator') or '', self.headers.get('Openai-Intent') or '', self.headers.get('Copilot-Vision-Request') or '', self.headers.get('session_id') or ''])"
    , "            payload = json.dumps({'id': 'resp_copilot', 'status': 'completed', 'output': [{'type': 'message', 'id': 'msg_copilot', 'content': [{'type': 'output_text', 'text': text}]}]}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/responses-stream/responses':"
    , "            request = json.loads(body)"
    , "            text = 'streamed' if request.get('stream') is True else 'not-streaming'"
    , "            payload = ("
    , "                'data: ' + json.dumps({'type': 'response.output_item.added', 'output_index': 0, 'item': {'type': 'message', 'id': 'msg_stream_http', 'content': []}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.output_text.delta', 'output_index': 0, 'delta': text[:6]}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.output_text.delta', 'output_index': 0, 'delta': text[6:]}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.output_item.done', 'output_index': 0, 'item': {'type': 'message', 'id': 'msg_stream_http', 'content': [{'type': 'output_text', 'text': text}]}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.completed', 'response': {'id': 'resp_stream_http', 'status': 'completed', 'usage': {'input_tokens': 4, 'output_tokens': 2, 'total_tokens': 6}}}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/azure-responses/responses?api-version=2025-01-01':"
    , "            request = json.loads(body)"
    , "            text = '|'.join([request.get('model') or '', str(request.get('stream')), self.headers.get('api-key') or '', self.headers.get('Authorization') or '', self.headers.get('X-Trace') or ''])"
    , "            payload = ("
    , "                'data: ' + json.dumps({'type': 'response.output_item.added', 'output_index': 0, 'item': {'type': 'message', 'id': 'msg_azure_http', 'content': []}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.output_text.delta', 'output_index': 0, 'delta': text}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.output_item.done', 'output_index': 0, 'item': {'type': 'message', 'id': 'msg_azure_http', 'content': [{'type': 'output_text', 'text': text}]}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.completed', 'response': {'id': 'resp_azure_http', 'status': 'completed', 'usage': {'input_tokens': 3, 'output_tokens': 4, 'total_tokens': 7}}}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/large':"
    , "            payload = b'x' * 1024"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/plain')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        payload = json.dumps({"
    , "            'path': self.path,"
    , "            'body': body,"
    , "            'auth': self.headers.get('Authorization'),"
    , "            'ua': self.headers.get('User-Agent'),"
    , "            'x_custom': self.headers.get('X-Custom'),"
    , "        }).encode('utf-8')"
    , "        self.send_response(201)"
    , "        self.send_header('Content-Type', 'application/json')"
    , "        self.send_header('X-Test-Response', 'yes')"
    , "        self.send_header('Content-Length', str(len(payload)))"
    , "        self.end_headers()"
    , "        self.wfile.write(payload)"
    , "    def log_message(self, *args):"
    , "        pass"
    , "HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()"
    ]

def waitForPortScript : String :=
  String.intercalate "\n"
    [ "import socket"
    , "import sys"
    , "sock = socket.socket()"
    , "sock.settimeout(0.2)"
    , "sock.connect(('127.0.0.1', int(sys.argv[1])))"
    , "sock.close()"
    ]

partial def waitForPort (port tries : Nat) : IO Unit := do
  if tries == 0 then
    throw (IO.userError s!"server did not start on port {port}")
  let output ← IO.Process.output
    { cmd := "python3"
      args := #["-c", waitForPortScript, toString port]
      stdin := .null
      stdout := .null
      stderr := .null
    }
  if output.exitCode == 0 then
    pure ()
  else
    IO.sleep 100
    waitForPort port (tries - 1)

def withHttpServer (port : Nat) (action : IO α) : IO α := do
  let child ← IO.Process.spawn
    { cmd := "python3"
      args := #["-c", httpServerScript, toString port]
      stdin := .null
      stdout := .null
      stderr := .inherit
      setsid := true
    }
  try
    waitForPort port 50
    let result ← action
    child.kill
    discard child.wait
    pure result
  catch err =>
    try
      child.kill
    catch _ =>
      pure ()
    try
      discard child.wait
    catch _ =>
      pure ()
    throw err

def localHttpConfig (port : Nat) (path : String) (maxResponseBytes : UInt64 := 4096) :
    LeanAgent.Http.JsonPostConfig :=
  { url := s!"http://127.0.0.1:{port}{path}"
    apiKey := "test-key"
    timeoutSeconds := 5
    connectTimeoutSeconds := 5
    maxResponseBytes := maxResponseBytes
    noProxy := some "*"
    userAgent := "lean-agent-test/0.1.0"
  }

def testHttpEnvelopeParsing : IO Unit := do
  match LeanAgent.Http.parseStatusEnvelope "201\nlegacy body\nsecond line" with
  | .ok response =>
      assertTrue (response.status == 201) "expected legacy status"
      assertTrue response.headers.isEmpty "expected no legacy headers"
      assertTrue (response.body == "legacy body\nsecond line") "expected legacy body"
  | .error err => fail s!"legacy envelope parse failed: {err}"
  let rawHeaders := "HTTP/1.1 202 Accepted\r\nX-Foo: bar\r\nContent-Type: application/json\r\n\r\n"
  let raw := LeanAgent.Http.envelopeMagic ++ "202\n" ++ toString rawHeaders.length ++ "\n" ++ rawHeaders ++ "{\"ok\":true}"
  match LeanAgent.Http.parseStatusEnvelope raw with
  | .ok response =>
      assertTrue (response.status == 202) "expected versioned status"
      assertTrue (headerValue? response.headers "x-foo" == some "bar") "expected parsed header"
      assertTrue (headerValue? response.headers "content-type" == some "application/json") "expected content type header"
      assertTrue (response.body == "{\"ok\":true}") "expected versioned body"
  | .error err => fail s!"versioned envelope parse failed: {err}"

def testHttpClientLocalPost : IO Unit := do
  let port := 18080
  withHttpServer port do
    let response ← LeanAgent.Http.postJsonResponse
      (localHttpConfig port "/ok")
      "{\"ping\":true}"
    assertTrue (response.status == 201) "expected HTTP status 201"
    assertTrue (response.body.contains "\"path\": \"/ok\"") "expected response body to include request path"
    assertTrue (response.body.contains "\"body\": \"{\\\"ping\\\":true}\"") "expected response body to include request payload"
    assertTrue (response.body.contains "\"auth\": \"Bearer test-key\"") "expected authorization header"
    assertTrue (response.body.contains "\"ua\": \"lean-agent-test/0.1.0\"") "expected user agent header"
    assertTrue (headerValue? response.headers "x-test-response" == some "yes") "expected response header"
    assertTrue (headerValue? response.headers "content-type" == some "application/json") "expected content-type header"

def testHttpClientCustomHeaders : IO Unit := do
  let port := 18084
  withHttpServer port do
    let response ← LeanAgent.Http.postJsonResponse
      { (localHttpConfig port "/headers") with
        headers := #[("X-Custom", "custom-value"), ("Authorization", "Bearer override-token")]
      }
      "{\"ping\":true}"
    assertTrue (response.status == 201) "expected HTTP status 201"
    assertTrue (response.body.contains "\"x_custom\": \"custom-value\"") "expected custom header"
    assertTrue (response.body.contains "\"auth\": \"Bearer override-token\"") "expected authorization override"

def testHttpClientResponseLimit : IO Unit := do
  let port := 18081
  withHttpServer port do
    let failed ←
      try
        let _ ← LeanAgent.Http.postJsonResponse
          (localHttpConfig port "/large" 16)
          "{}"
        pure false
      catch err =>
        assertTrue (err.toString.contains "maxResponseBytes") "expected maxResponseBytes error"
        pure true
    assertTrue failed "expected large response to fail"

def testOpenAICompletionsRetriesTransientHttpFailure : IO Unit := do
  let port := 18082
  withHttpServer port do
    let response ← LeanAgent.AI.Api.OpenAICompletions.completeWithOptions
      { apiKey := "test-key"
        baseUrl := s!"http://127.0.0.1:{port}/retry-openai"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      (basicProviderRequest)
      { maxRetries := some 1
        maxRetryDelayMs := some 0
      }
    assertTrue (response.content == "retried") "expected retried provider response"

def testOpenAICompletionsSendsCustomHeaders : IO Unit := do
  let port := 18085
  withHttpServer port do
    let response ← LeanAgent.AI.Api.OpenAICompletions.completeWithOptions
      { apiKey := "test-key"
        baseUrl := s!"http://127.0.0.1:{port}/headers-openai"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      (basicProviderRequest)
      { headers := #[("X-Trace", some "trace-1")] }
    assertTrue (response.content == "trace-1") "expected OpenAI-compatible request header"

def testOpenAICompletionsPayloadAndResponseHooks : IO Unit := do
  let port := 18092
  withHttpServer port do
    let sawPayload ← IO.mkRef false
    let sawResponse ← IO.mkRef false
    let response ← LeanAgent.AI.Api.OpenAICompletions.completeWithOptions
      { apiKey := "test-key"
        baseUrl := s!"http://127.0.0.1:{port}/payload-hook-openai"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      (basicProviderRequest)
      { onPayload := some fun payload model => do
          assertTrue (model.api == "openai-completions") "expected OpenAI-compatible model ref api"
          assertTrue (model.id == basicProviderRequest.model) "expected provider request model ref"
          assertTrue (LeanAgent.Json.optVal? payload "messages").isSome "expected original chat payload"
          sawPayload.set true
          pure (some (LeanAgent.Json.obj [("model", LeanAgent.Json.str "hooked-openai")]))
        onResponse := some fun response model => do
          assertTrue (model.api == "openai-completions") "expected response hook model ref api"
          assertTrue (response.status == 200) "expected response hook status"
          assertTrue (headerValue? response.headers "x-hook-response" == some "openai")
            "expected response hook headers"
          sawResponse.set true
      }
    assertTrue (response.content == "hooked-openai") "expected payload hook to replace OpenAI payload"
    assertTrue (← sawPayload.get) "expected payload hook to run"
    assertTrue (← sawResponse.get) "expected response hook to run"

def testOpenAICompletionsStreamWithOptionsLocal : IO Unit := do
  let port := 18086
  withHttpServer port do
    let stream ← LeanAgent.AI.Api.OpenAICompletions.streamWithOptions
      { apiKey := "test-key"
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      (basicProviderRequest)
      "openai-completions"
      "deepseek"
    assertTrue stream.isComplete "expected completed streaming response"
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "streamed") "expected streamed response text"
    assertTrue (stream.result.usage.totalTokens == 6) "expected streaming usage"

def testOpenAICompatibleStreamsUsesStreamingRuntime : IO Unit := do
  let port := 18087
  withHttpServer port do
    let model := { LeanAgent.Models.deepSeekV4Flash with baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai" }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "system"
        messages :=
          #[.user
              { content := #[LeanAgent.AI.text "hello"]
                timestamp := 1
              }]
      }
    let stream ← LeanAgent.Models.openAICompatibleStreams.streamSimple
      model
      context
      { apiKey := some "test-key" }
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "streamed") "expected runtime streamed text"
    assertTrue (stream.result.api == "openai-completions") "expected runtime api"
    assertTrue (stream.result.provider == LeanAgent.Models.deepSeekProviderId) "expected runtime provider"

def testOpenAICompatibleStreamsApplyModelCost : IO Unit := do
  let port := 18094
  withHttpServer port do
    let model :=
      { LeanAgent.Models.deepSeekV4Flash with
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        cost := { input := 1000000.0, output := 2000000.0, cacheRead := 500000.0, cacheWrite := 3000000.0 }
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
    let stream ← LeanAgent.Models.openAICompatibleStreams.streamSimple
      model
      context
      { apiKey := some "test-key" }
    assertTrue (stream.result.usage.input == 4) "expected OpenAI-compatible input usage"
    assertTrue (stream.result.usage.output == 2) "expected OpenAI-compatible output usage"
    assertTrue (stream.result.usage.cost.input == 4.0) "expected input cost from model rate"
    assertTrue (stream.result.usage.cost.output == 4.0) "expected output cost from model rate"
    assertTrue (stream.result.usage.cost.total == 8.0) "expected total cost from model rates"
    match stream.events.back? with
    | some (.done _ message) =>
        assertTrue (message.usage.cost.total == 8.0) "expected final event cost"
    | _ => fail "expected final done event"

def testOpenAICompatibleStreamsClampMaxTokens : IO Unit := do
  let port := 18091
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "tiny"
        name := "Tiny"
        provider := "test"
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/clamp-openai"
        contextWindow := 5000
        maxTokens := 4000
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "abcd"
        messages := #[.user { content := #[LeanAgent.AI.text "abcd"], timestamp := 1 }]
      }
    let stream ← LeanAgent.Models.openAICompatibleStreams.streamSimple
      model
      context
      { apiKey := some "test-key" }
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "902")
      "expected OpenAI-compatible runtime max_tokens to be context-clamped"

def testCloudflareAIGatewayOpenAICompatibleHeaderAuthLocal : IO Unit := do
  let port := 18096
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-4o-mini"
        name := "Gateway GPT-4o mini"
        provider := "cloudflare-ai-gateway"
        api := "openai-completions"
        baseUrl :=
          s!"http://127.0.0.1:{port}/cloudflare-openai/" ++
            "{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}"
      }
    let collection ← LeanAgent.Models.createModels none fakeCloudflareAuthContext
    let provider ← LeanAgent.Models.createProvider
      { id := "cloudflare-ai-gateway"
        name := some "Cloudflare AI Gateway"
        auth := { apiKey := some LeanAgent.AI.Providers.CloudflareAuth.cloudflareAIGatewayAuth }
        models := #[model]
        apis := #[{ api := "openai-completions", streams := LeanAgent.Models.openAICompatibleStreams }]
      }
    collection.setProvider provider
    let message ← collection.completeSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
    assertTrue
      (LeanAgent.AI.contentPlainText message.content == "Bearer cf-env-key||gpt-4o-mini")
      "expected Cloudflare AI Gateway header-only auth through OpenAI-compatible runtime"

def testOpenRouterImagesRequestPayload : IO Unit := do
  let model :=
    { LeanAgent.AI.Images.Models.gemini25FlashImage with
      id := "image-payload-model"
    }
  let payload := LeanAgent.AI.Api.OpenRouterImages.requestToJson
    model
    { input :=
        #[ LeanAgent.AI.text "draw"
         , LeanAgent.AI.image "QUJD" "image/png"
         ]
    }
  assertTrue ((LeanAgent.Json.optVal? payload "stream") == some (Lean.Json.bool false))
    "expected non-streaming image request"
  match LeanAgent.Json.optVal? payload "modalities" with
  | some modalities =>
      assertTrue (modalities == LeanAgent.Json.arr #[LeanAgent.Json.str "image", LeanAgent.Json.str "text"])
        "expected image/text modalities"
  | none => fail "expected modalities"
  match (payload.getObjVal? "messages").bind Lean.Json.getArr? with
  | .ok messages =>
      match messages[0]? with
      | some first =>
          match (first.getObjVal? "content").bind Lean.Json.getArr? with
          | .ok content =>
              match content[0]?, content[1]? with
              | some textPart, some imagePart =>
                  match textPart.getObjVal? "type" with
                  | .ok (Lean.Json.str "text") => pure ()
                  | _ => fail "expected text input part"
                  match imagePart.getObjVal? "type" with
                  | .ok (Lean.Json.str "image_url") => pure ()
                  | _ => fail "expected image input part"
                  match (imagePart.getObjVal? "image_url").bind (fun imageUrl =>
                      imageUrl.getObjVal? "url" >>= Lean.Json.getStr?) with
                  | .ok imageUrl =>
                      assertTrue (imageUrl == "data:image/png;base64,QUJD") "expected image data URL"
                  | .error err => fail s!"expected image data URL: {err}"
              | _, _ => fail "expected text and image content parts"
          | .error err => fail s!"expected image content array: {err}"
      | none => fail "expected first image message"
  | .error err => fail s!"expected image messages array: {err}"

def countImageBlocks (content : Array LeanAgent.AI.ContentBlock) : Nat :=
  content.foldl
    (fun total block =>
      match block with
      | .image _ => total + 1
      | _ => total)
    0

def testOpenRouterImagesGenerateLocal : IO Unit := do
  let port := 18097
  withHttpServer port do
    LeanAgent.AI.Images.resetImagesApiProviders
    let responseStatus ← IO.mkRef 0
    let responseHeader ← IO.mkRef ""
    let model :=
      { LeanAgent.AI.Images.Models.gemini25FlashImage with
        id := "local-image-model"
        baseUrl := s!"http://127.0.0.1:{port}/openrouter-images"
        cost := { input := 1000000.0, output := 2000000.0, cacheRead := 3000000.0, cacheWrite := 4000000.0 }
      }
    let result ← LeanAgent.AI.Images.generateImages
      model
      { input :=
          #[ LeanAgent.AI.text "draw a diagram"
           , LeanAgent.AI.image "QUJD" "image/png"
           ]
      }
      { apiKey := some "image-key"
        headers := #[("X-Trace", some "image-trace")]
        onResponse := some (fun response _model => do
          responseStatus.set response.status
          responseHeader.set ((headerValue? response.headers "x-hook-response").getD "")
        )
      }
    assertTrue (result.stopReason == .stop) "expected OpenRouter Images success"
    assertTrue (result.responseId == some "img_resp") "expected image response id"
    assertTrue
      (LeanAgent.AI.contentPlainText result.output ==
        "local-image-model|Bearer image-key|image-trace|image,text|text|data:image/png;base64,QUJD")
      "expected OpenRouter Images request fields to reach local server"
    assertTrue (countImageBlocks result.output == 2) "expected data URL images to parse"
    match result.output[1]?, result.output[2]? with
    | some (LeanAgent.AI.ContentBlock.image first), some (LeanAgent.AI.ContentBlock.image second) =>
        assertTrue (first.mimeType == "image/png" && first.data == "QUJD") "expected first parsed image"
        assertTrue (second.mimeType == "image/jpeg" && second.data == "REVGRw==") "expected second parsed image"
    | _, _ => fail "expected parsed image output blocks"
    match result.usage with
    | some usage =>
        assertTrue (usage.input == 6) "expected input tokens after cache adjustment"
        assertTrue (usage.output == 3) "expected output tokens"
        assertTrue (usage.cacheRead == 3) "expected cache read tokens"
        assertTrue (usage.cacheWrite == 1) "expected cache write tokens"
        assertTrue (usage.totalTokens == 13) "expected total image usage tokens"
        assertTrue (usage.cost.total == 25.0) "expected image usage cost"
    | none => fail "expected OpenRouter Images usage"
    assertTrue ((← responseStatus.get) == 200) "expected image response hook status"
    assertTrue ((← responseHeader.get) == "openrouter-images") "expected image response hook headers"

def testOpenRouterImagesMissingApiKeyReturnsError : IO Unit := do
  let result ← LeanAgent.AI.Images.generateImages
    LeanAgent.AI.Images.Models.gemini25FlashImage
    { input := #[LeanAgent.AI.text "draw"] }
  assertTrue (result.stopReason == .error) "expected missing OpenRouter image key error"
  assertTrue
    (match result.errorMessage with
     | some message => message.contains "No API key for provider: openrouter"
     | none => false)
    "expected missing API key error message"

def testOpenAIResponsesDispatchesThroughModelsCollection : IO Unit := do
  let port := 18095
  withHttpServer port do
    let providerId := "responses-test"
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-5.5"
        name := "GPT 5.5"
        provider := providerId
        api := "openai-responses"
        baseUrl := s!"http://127.0.0.1:{port}/responses-stream"
        cost := { input := 1000000.0, output := 2000000.0 }
        contextWindow := 100000
        maxTokens := 4096
        reasoning := true
      }
    let provider ← LeanAgent.Models.createCatalogProvider
      { id := providerId
        name := "Responses Test"
        baseUrl := model.baseUrl
        apiKeyEnv := "RESPONSES_TEST_API_KEY"
        defaultModel := model.id
        models := #[model]
      }
    let collection ← LeanAgent.Models.createModels
    collection.setProvider provider
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
    let stream ← collection.streamSimple
      model
      context
      { apiKey := some "test-key" }
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "streamed")
      "expected Responses model to dispatch through Models collection"
    assertTrue (stream.result.api == "openai-responses") "expected Responses runtime api"
    assertTrue (stream.result.provider == providerId) "expected Responses runtime provider"
    assertTrue (stream.result.usage.input == 4) "expected Responses input usage"
    assertTrue (stream.result.usage.output == 2) "expected Responses output usage"
    assertTrue (stream.result.usage.cost.input == 4.0) "expected Responses model input cost"
    assertTrue (stream.result.usage.cost.output == 4.0) "expected Responses model output cost"
    assertTrue (stream.result.usage.cost.total == 8.0) "expected Responses model total cost"

def testOpenAIResponsesCompleteWithOptionsLocal : IO Unit := do
  let port := 18088
  withHttpServer port do
    let pricedModel :=
      { responsesCodexModel with
        cost := { input := 1000000.0, output := 2000000.0 }
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "system"
        messages :=
          #[.user
              { content := #[LeanAgent.AI.text "hello"]
                timestamp := 1
              }]
      }
    let response ← LeanAgent.AI.Api.OpenAIResponses.completeWithOptions
      { apiKey := "test-key"
        baseUrl := s!"http://127.0.0.1:{port}/responses-runtime"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      pricedModel
      context
      { sessionId := some "session-123"
        cacheRetention := some .short
        headers := #[("X-Trace", some "trace-1")]
        serviceTier := some "priority"
      }
    assertTrue (response.responseId == some "resp_http") "expected responses response id"
    assertTrue (LeanAgent.AI.contentPlainText response.content == "ok|session-123|session-123|trace-1")
      "expected local responses runtime to send cache affinity and custom headers"
    assertTrue (response.usage.input == 5) "expected cached token subtraction"
    assertTrue (response.usage.cacheRead == 1) "expected cache read tokens"
    assertTrue (response.usage.totalTokens == 8) "expected total tokens"
    assertTrue (response.usage.cost.input == 12.5) "expected priority input cost multiplier"
    assertTrue (response.usage.cost.output == 10.0) "expected priority output cost multiplier"
    assertTrue (response.usage.cost.total == 22.5) "expected priority total cost multiplier"

def testOpenAIResponsesPayloadAndResponseHooks : IO Unit := do
  let port := 18093
  withHttpServer port do
    let sawPayload ← IO.mkRef false
    let sawResponse ← IO.mkRef false
    let response ← LeanAgent.AI.Api.OpenAIResponses.completeWithOptions
      { apiKey := "test-key"
        baseUrl := s!"http://127.0.0.1:{port}/payload-hook-responses"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      responsesCodexModel
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { onPayload := some fun payload model => do
          assertTrue (model.api == "openai-responses") "expected Responses model ref api"
          assertTrue (model.id == responsesCodexModel.id) "expected Responses model ref id"
          assertTrue (LeanAgent.Json.optVal? payload "input").isSome "expected original Responses payload"
          sawPayload.set true
          pure
            (some
              (LeanAgent.Json.obj
                [ ("model", LeanAgent.Json.str "hooked-responses")
                , ("input", LeanAgent.Json.arr #[])
                , ("stream", LeanAgent.Json.bool false)
                , ("store", LeanAgent.Json.bool false)
                ]))
        onResponse := some fun response model => do
          assertTrue (model.provider == responsesCodexModel.provider) "expected response hook model provider"
          assertTrue (response.status == 200) "expected response hook status"
          assertTrue (headerValue? response.headers "x-hook-response" == some "responses")
            "expected response hook headers"
          sawResponse.set true
      }
    assertTrue (response.responseId == some "resp_hook") "expected hooked Responses response id"
    assertTrue (LeanAgent.AI.contentPlainText response.content == "hooked-responses")
      "expected payload hook to replace Responses payload"
    assertTrue (← sawPayload.get) "expected payload hook to run"
    assertTrue (← sawResponse.get) "expected response hook to run"

def testOpenAIResponsesSendsCopilotDynamicHeaders : IO Unit := do
  let port := 18090
  withHttpServer port do
    let copilotModel :=
      { responsesCodexModel with
        provider := "github-copilot"
        input := #["text", "image"]
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "system"
        messages :=
          #[.user
              { content :=
                  #[ LeanAgent.AI.text "describe"
                   , LeanAgent.AI.image "base64" "image/png"
                   ]
                timestamp := 1
              }]
      }
    let response ← LeanAgent.AI.Api.OpenAIResponses.completeWithOptions
      { apiKey := "test-key"
        baseUrl := s!"http://127.0.0.1:{port}/responses-copilot"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      copilotModel
      context
      { sessionId := some "session-vision" }
    assertTrue (response.responseId == some "resp_copilot") "expected copilot response id"
    assertTrue
      (LeanAgent.AI.contentPlainText response.content ==
        "user|conversation-edits|true|session-vision")
      "expected Copilot dynamic and session headers"

def testOpenAIResponsesStreamWithOptionsLocal : IO Unit := do
  let port := 18089
  withHttpServer port do
    let pricedModel :=
      { responsesCodexModel with
        id := "gpt-5.4"
        cost := { input := 1000000.0, output := 2000000.0 }
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "system"
        messages :=
          #[.user
              { content := #[LeanAgent.AI.text "hello"]
                timestamp := 1
              }]
      }
    let stream ← LeanAgent.AI.Api.OpenAIResponses.completeStreamWithOptions
      { apiKey := "test-key"
        baseUrl := s!"http://127.0.0.1:{port}/responses-stream"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      pricedModel
      context
      { serviceTier := some "flex" }
    assertTrue stream.isComplete "expected completed responses stream"
    assertTrue (stream.result.responseId == some "resp_stream_http") "expected streamed response id"
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "streamed") "expected streamed response text"
    assertTrue (stream.result.usage.totalTokens == 6) "expected streaming usage"
    assertTrue (stream.result.usage.cost.input == 2.0) "expected flex input cost multiplier"
    assertTrue (stream.result.usage.cost.output == 2.0) "expected flex output cost multiplier"
    assertTrue (stream.result.usage.cost.total == 4.0) "expected flex total cost multiplier"
    assertTrue
      (stream.events.any fun
        | .textDelta _ "stream" _ => true
        | _ => false)
      "expected streamed text delta"

def testAzureOpenAIResponsesStreamWithOptionsLocal : IO Unit := do
  let port := 18094
  withHttpServer port do
    let stream ← LeanAgent.AI.Api.AzureOpenAIResponses.completeStreamWithOptions
      { apiKey := "azure-key"
        baseUrl := s!"http://127.0.0.1:{port}/azure-responses"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      azureResponsesModel
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { azureApiVersion := some "2025-01-01"
        azureDeploymentName := some "mini-deployment"
        headers := #[("X-Trace", some "trace-azure")]
      }
    assertTrue stream.isComplete "expected completed Azure Responses stream"
    assertTrue (stream.result.responseId == some "resp_azure_http") "expected Azure response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content == "mini-deployment|True|azure-key||trace-azure")
      "expected Azure deployment, stream flag, api-key header, no bearer auth, and custom header"

def testCompatAzureOpenAIResponsesBuiltinDispatch : IO Unit := do
  let port := 18095
  withHttpServer port do
    LeanAgent.AI.Compat.resetApiProviders
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-4o-mini"
        name := "Azure GPT-4o mini"
        provider := "azure-openai-responses"
        api := "azure-openai-responses"
        baseUrl := s!"http://127.0.0.1:{port}/azure-responses"
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamSimpleAzureOpenAIResponses
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
      { apiKey := some "azure-key"
        env :=
          #[ ("AZURE_OPENAI_API_VERSION", "2025-01-01")
           , ("AZURE_OPENAI_DEPLOYMENT_NAME_MAP", "gpt-4o-mini=mini-deployment")
           ]
        headers := #[("X-Trace", some "trace-azure")]
      }
    assertTrue stream.isComplete "expected compat Azure built-in stream"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content == "mini-deployment|True|azure-key||trace-azure")
      "expected compat Azure Responses built-in dispatch"
    LeanAgent.AI.Compat.resetApiProviders

def testOpenAICompletionsProviderErrorDiagnostics : IO Unit := do
  let port := 18083
  withHttpServer port do
    let failed ←
      try
        let _ ← LeanAgent.AI.Api.OpenAICompletions.completeWithOptions
          { apiKey := "test-key"
            baseUrl := s!"http://127.0.0.1:{port}/diagnostic-openai"
            timeoutSeconds := 5
            connectTimeoutSeconds := 5
            noProxy := some "*"
            userAgent := "lean-agent-test/0.1.0"
          }
          (basicProviderRequest)
        pure false
      catch err =>
        let message := err.toString
        assertTrue (message.contains "provider HTTP 429") "expected provider status in error"
        assertTrue (message.contains "rate limit exceeded") "expected provider message in error"
        assertTrue (message.contains "type=rate_limit_error") "expected provider type in error"
        pure true
    assertTrue failed "expected provider diagnostic error"

def main : IO UInt32 := do
  try
    testAgentLoopReadsFile
    testEditTool
    testEditToolRejectsAmbiguousMatch
    testReadToolRejectsPathEscape
    testListTool
    testBashToolTimeout
    testProjectCommandExpansion
    testProjectSkillExpansion
    testSessionJsonlRoundTrip
    testSessionResourceCleanups
    testSessionResourceCleanupAggregatesErrors
    testOpenAIAssistantOmitsEmptyToolCalls
    testOpenAICompletionsOmitsEmptyTools
    testOpenAICompletionsIncludesToolsWhenPresent
    testOpenAICompletionsIncludesEmptyToolsForToolHistory
    testOpenAICompletionsSerializesOptions
    testOpenAICompletionsUsesMappedReasoningEffort
    testOpenAICompletionsPromptCacheKey
    testOpenAICompletionsPromptCacheLongRetention
    testOpenAICompletionsPromptCacheClampsKey
    testOpenAICompletionsPromptCacheNoneOmitsFields
    testOpenAICompletionsPromptCacheEnvLongRetention
    testSSEParsesDataEvents
    testOpenAICompletionsStreamingPayload
    testOpenAICompletionsParsesStreamingText
    testOpenAICompletionsParsesStreamingToolCall
    testOpenAICompletionsParsesStreamingThinking
    testTransformMessagesCrossModelHandoff
    testTransformMessagesAddsSyntheticToolResults
    testTransformMessagesDowngradesUnsupportedImages
    testTransformMessagesSkipsErroredAssistant
    testOpenAIResponsesSharedNormalizesForeignToolCallIds
    testOpenAIResponsesSharedOmitsDifferentModelFcItemId
    testOpenAIResponsesSharedConvertsTools
    testGitHubCopilotDynamicHeaders
    testOpenAIResponsesRequestPayload
    testOpenAIResponsesRequestUsesThinkingLevelMap
    testOpenAIResponsesRequestClampsMaxTokens
    testAzureOpenAIResponsesBaseUrlNormalization
    testAzureOpenAIResponsesConfigAndDeployment
    testAzureOpenAIResponsesRequestPayload
    testOpenAIResponsesServiceTierCostMultiplier
    testOpenAIResponsesParsesResponse
    testOpenAIResponsesParsesStreamingTextAndUsage
    testOpenAIResponsesParsesStreamingToolCall
    testOpenAIResponsesStreamingRequiresTerminalEvent
    testDiagnosticsExtractsProviderError
    testOpenAICompletionsParsesUsage
    testShortHashMatchesPi
    testEstimateUtilities
    testEstimateContextUsesRecentAssistantUsage
    testSimpleOptionsAdjustMaxTokensForThinking
    testModelsClampMaxTokensToContext
    testProviderEnvValueResolution
    testProxyEnvResolution
    testProxyNoProxyMatching
    testProxyRejectsUnsupportedProtocol
    testHeadersUtilities
    testJsonParseRepairsMalformedStrings
    testJsonParseStreamingPartialObject
    testSchemaStringEnum
    testValidationCoercesPlainJsonSchemas
    testValidationRejectsInvalidCoercions
    testValidationToolLookupAndRequired
    testSanitizeUnicodeSurrogates
    testOverflowClassifiesProviderErrors
    testOverflowClassifiesContextWindowSignals
    testRetryClassifiesAssistantErrors
    testRetryWithRetriesSucceedsAfterTransientFailures
    testRetryWithRetriesStopsOnNonRetryableFailure
    testModelCatalogDeepSeekDefaults
    testOpenAICompatibleProviderFamilyCatalog
    testDefaultModelsRegistersOpenAICompatibleFamily
    testModelsAuthEnvApiKeyResolution
    testModelsAuthStoredCredentialWins
    testFileCredentialStoreRoundTrip
    testFileCredentialStoreRejectsUnsupportedCredentialType
    testFileCredentialStoreOAuthRoundTrip
    testModelsAuthFileCredentialStore
    testModelsAuthOAuthValidCredential
    testModelsAuthOAuthExpiredCredentialRefreshes
    testModelsAuthOAuthCredentialOwnsProvider
    testOAuthProviderRegistryCrud
    testOAuthRefreshTokenDispatch
    testOAuthGetOAuthApiKey
    testOAuthGetOAuthApiKeyErrors
    testCloudflareWorkersAIAuthResolution
    testCloudflareAIGatewayAuthResolution
    testCloudflareStoredCredentialResolution
    testEnvApiKeysProviderMap
    testEnvApiKeysPrefersAnthropicOAuthToken
    testEnvApiKeysAmbientAuthMarkers
    testModelsCollectionDispatchesWithAuth
    testModelsCollectionAppliesCloudflareAIGatewayAuth
    testCompatApiRegistryDispatchesAndUnregisters
    testImagesApiRegistryDispatchesAndUnregisters
    testImagesApiRegistryMissingProviderReturnsError
    testImagesBuiltInRegistryRestoresOpenRouter
    testImageModelCatalogOpenRouter
    testImagesCollectionProviderCrudAndRefresh
    testImagesCollectionAppliesAuthAndOptions
    testImagesCollectionUnknownProviderReturnsError
    testOpenRouterImagesProviderFactoryAuthAndModels
    testCompatInjectsEnvApiKeyForKnownProviders
    testCompatInjectsEnvApiKeyForMappedProvidersOutsideCatalog
    testCompatMissingProviderReturnsError
    testCompatLegacyAliasesDispatchFixedApi
    testCompatLegacyAliasesRejectMismatchedApi
    testCompatLegacyAliasesUseRegistryForNonBuiltins
    testModelsCreateProviderMissingApiReturnsLazyErrorStream
    testModelsCreateProviderSetupFailureReturnsLazyErrorStream
    testModelsLazyProviderStreamsLoadFailureReturnsErrorStream
    testModelsCalculateCost
    testModelsThinkingLevelMapSupport
    testModelsClampSimpleOptionsClampsReasoning
    testFauxProviderQueuesResponses
    testFauxProviderHelperBlocksAndEvents
    testFauxProviderModelsFactoriesAndCache
    testAIContentBlockJsonRoundTrip
    testAIMessageJsonRoundTrip
    testAIMessageLegacyConversion
    testAIEventStreamTextResult
    testAIEventStreamPartialSnapshots
    testAIEventStreamEmptyContentCompletes
    testAIEventStreamToolUseResult
    testAIEventStreamLegacyProviderWrapper
    testAgentLoopUsesAssistantEventStreamBridge
    testAgentSessionCreateAndContinue
    testAgentSessionRejectsAssistantContinue
    testJsonEventShape
    testHttpEnvelopeParsing
    testHttpClientLocalPost
    testHttpClientCustomHeaders
    testHttpClientResponseLimit
    testOpenAICompletionsRetriesTransientHttpFailure
    testOpenAICompletionsSendsCustomHeaders
    testOpenAICompletionsPayloadAndResponseHooks
    testOpenAICompletionsStreamWithOptionsLocal
    testOpenAICompatibleStreamsUsesStreamingRuntime
    testOpenAICompatibleStreamsApplyModelCost
    testOpenAICompatibleStreamsClampMaxTokens
    testCloudflareAIGatewayOpenAICompatibleHeaderAuthLocal
    testOpenRouterImagesRequestPayload
    testOpenRouterImagesGenerateLocal
    testOpenRouterImagesMissingApiKeyReturnsError
    testOpenAIResponsesDispatchesThroughModelsCollection
    testOpenAIResponsesCompleteWithOptionsLocal
    testOpenAIResponsesPayloadAndResponseHooks
    testOpenAIResponsesSendsCopilotDynamicHeaders
    testOpenAIResponsesStreamWithOptionsLocal
    testAzureOpenAIResponsesStreamWithOptionsLocal
    testCompatAzureOpenAIResponsesBuiltinDispatch
    testOpenAICompletionsProviderErrorDiagnostics
    IO.println "lean-agent tests passed"
    pure 0
  catch err =>
    IO.eprintln err.toString
    pure 1
