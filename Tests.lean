import LeanAgent

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
    testOpenAIAssistantOmitsEmptyToolCalls
    testOpenAICompletionsOmitsEmptyTools
    testOpenAICompletionsIncludesToolsWhenPresent
    testOpenAICompletionsIncludesEmptyToolsForToolHistory
    testOpenAICompletionsSerializesOptions
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
    testDiagnosticsExtractsProviderError
    testOpenAICompletionsParsesUsage
    testShortHashMatchesPi
    testEstimateUtilities
    testEstimateContextUsesRecentAssistantUsage
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
    testModelsCollectionDispatchesWithAuth
    testModelsCalculateCost
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
    testOpenAICompletionsStreamWithOptionsLocal
    testOpenAICompatibleStreamsUsesStreamingRuntime
    testOpenAICompletionsProviderErrorDiagnostics
    IO.println "lean-agent tests passed"
    pure 0
  catch err =>
    IO.eprintln err.toString
    pure 1
