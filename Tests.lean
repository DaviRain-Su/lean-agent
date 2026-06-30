import LeanAgent
import LeanAgent.AI

set_option maxRecDepth 2048

open LeanAgent

def fail (message : String) : IO Unit :=
  throw (IO.userError message)

def assertTrue (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else fail message

def waitForSome
    (read : IO (Option α))
    (failure : String)
    (remaining : Nat := 100) : IO α := do
  match remaining with
  | 0 => throw (IO.userError failure)
  | n + 1 =>
      match ← read with
      | some value => pure value
      | none =>
          IO.sleep 10
          waitForSome read failure n

def headerValue? (headers : Array (String × String)) (name : String) : Option String :=
  headers.findSome? fun (headerName, value) =>
    if headerName == name.toLower then some value else none

def jsonStringField? (json : Lean.Json) (key : String) : Option String :=
  match LeanAgent.Json.optVal? json key with
  | some (.str value) => some value
  | _ => none

def jsonArrayField? (json : Lean.Json) (key : String) : Option (Array Lean.Json) :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getArr? with
      | .ok arr => some arr
      | .error _ => none
  | none => none

def jsonObjectField? (json : Lean.Json) (key : String) : Option Lean.Json :=
  match LeanAgent.Json.optVal? json key with
  | some value =>
      match value.getObj? with
      | .ok _ => some value
      | .error _ => none
  | none => none

def silentSink : EventSink :=
  fun _ => pure ()

def silentAgentSink : LeanAgent.Session.RuntimeAgentEventSink :=
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
    let timestamp ← IO.monoMsNow
    let userMsg : LeanAgent.Session.RuntimeAgentMessage :=
      .ofMessage (.user { content := #[.text { text := "hello" }], timestamp := timestamp })
    let assistantMsg : LeanAgent.Session.RuntimeAgentMessage :=
      .ofMessage (.assistant
        { content := #[.text { text := "world" }]
          api := "fake"
          provider := "fake"
          model := "fake-model"
          timestamp := timestamp
        })
    let store ← LeanAgent.Session.persistMessages
      (some { path := path, lastEntryId := none })
      #[userMsg, assistantMsg]
    let modelInfo : LeanAgent.Models.ModelInfo :=
      { id := "fake-model", name := "fake", provider := "fake", api := "fake", baseUrl := "" }
    let (messages, lastId) ← LeanAgent.Session.loadMessagesWithLastId modelInfo path
    assertTrue (messages.size == 2) "expected persisted messages"
    assertTrue lastId.isSome "expected last entry id"
    assertTrue store.isSome "expected updated store"
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

def testOpenAICompletionsCompatSuppressesUnsupportedFields : IO Unit := do
  let options : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
    { maxTokens := some 123
      reasoningEffort := some .high
      maxTokensField := "max_completion_tokens"
      supportsReasoningEffort := false
      supportsLongCacheRetention := false
      cacheRetention := some .long
      sessionId := some "session-compat"
    }
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest)
    options
    "https://opencode.ai/zen/v1"
  assertTrue (LeanAgent.Json.optVal? json "max_tokens" == none)
    "expected compat max_tokens field to be omitted"
  assertTrue
    (LeanAgent.Json.optVal? json "max_completion_tokens" == some (LeanAgent.Json.nat 123))
    "expected compat max_completion_tokens field"
  assertTrue (LeanAgent.Json.optVal? json "reasoning_effort" == none)
    "expected unsupported reasoning effort to be omitted"
  assertTrue (LeanAgent.Json.optVal? json "prompt_cache_key" == none)
    "expected unsupported long-cache key to be omitted"
  assertTrue (LeanAgent.Json.optVal? json "prompt_cache_retention" == none)
    "expected unsupported long-cache retention to be omitted"

def testOpenAICompletionsLegacyDetectsOpenRouterCompat : IO Unit := do
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest)
    { maxTokens := some 123
      reasoningEffort := some .high
    }
    LeanAgent.Models.openRouterBaseUrl
    LeanAgent.Models.openRouterProviderId
  assertTrue (LeanAgent.Json.optVal? json "store" == some (LeanAgent.Json.bool false))
    "expected OpenRouter legacy request to send store=false"
  assertTrue (LeanAgent.Json.optVal? json "max_tokens" == none)
    "expected OpenRouter legacy request to omit max_tokens"
  assertTrue (LeanAgent.Json.optVal? json "max_completion_tokens" == some (LeanAgent.Json.nat 123))
    "expected OpenRouter legacy request to use max_completion_tokens"
  assertTrue ((LeanAgent.Json.optVal? json "reasoning_effort").isNone)
    "expected OpenRouter legacy request to omit top-level reasoning_effort"
  match jsonObjectField? json "reasoning" with
  | some reasoning =>
      assertTrue (jsonStringField? reasoning "effort" == some "high")
        "expected OpenRouter legacy reasoning object"
  | none => fail "expected OpenRouter legacy reasoning object"

def testOpenAICompletionsLegacyDetectsAntLingCompat : IO Unit := do
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
    (basicProviderRequest #[noopTool])
    { maxTokens := some 123
      reasoningEffort := some .high
      cacheRetention := some .long
      sessionId := some "legacy-ant-ling"
    }
    LeanAgent.Models.antLingBaseUrl
    LeanAgent.Models.antLingProviderId
  assertTrue (LeanAgent.Json.optVal? json "max_tokens" == some (LeanAgent.Json.nat 123))
    "expected Ant Ling legacy request to use max_tokens"
  assertTrue ((LeanAgent.Json.optVal? json "max_completion_tokens").isNone)
    "expected Ant Ling legacy request to omit max_completion_tokens"
  assertTrue ((LeanAgent.Json.optVal? json "store").isNone)
    "expected Ant Ling legacy request to omit store"
  assertTrue ((LeanAgent.Json.optVal? json "prompt_cache_key").isNone)
    "expected Ant Ling legacy request to omit prompt cache key"
  assertTrue ((LeanAgent.Json.optVal? json "prompt_cache_retention").isNone)
    "expected Ant Ling legacy request to omit prompt cache retention"
  assertTrue ((LeanAgent.Json.optVal? json "reasoning_effort").isNone)
    "expected Ant Ling legacy request to omit top-level reasoning_effort"
  match jsonObjectField? json "reasoning", jsonArrayField? json "tools" with
  | some reasoning, some tools =>
      assertTrue (jsonStringField? reasoning "effort" == some "high")
        "expected Ant Ling legacy reasoning object"
      match jsonObjectField? tools[0]! "function" with
      | some fn =>
          assertTrue (LeanAgent.Json.optVal? fn "strict" == some (LeanAgent.Json.bool false))
            "expected Ant Ling legacy tools to keep strict=false"
      | none => fail "expected Ant Ling legacy tool function"
  | _, _ => fail "expected Ant Ling legacy reasoning object and tools"

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

def testOpenAIPromptCacheClampHelper : IO Unit := do
  let clamped := LeanAgent.AI.Api.OpenAIPromptCache.clampKey (some "")
  assertTrue (clamped == some "") "expected empty key to stay empty"
  let shortKey := "short-key"
  let clampedShort := LeanAgent.AI.Api.OpenAIPromptCache.clampKey (some shortKey)
  assertTrue (clampedShort == some shortKey) "expected short key unchanged"
  let longKey := String.ofList (List.replicate 100 'x')
  let clampedLong := LeanAgent.AI.Api.OpenAIPromptCache.clampKey (some longKey)
  assertTrue
    (match clampedLong with
     | some key => key.length == 64
     | none => false)
    "expected long key clamped to 64 chars"
  let noneClamped := LeanAgent.AI.Api.OpenAIPromptCache.clampKey none
  assertTrue (noneClamped == none) "expected none key stays none"

def testOpenAICompletionsSessionAffinityHeaders : IO Unit := do
  let headers := LeanAgent.AI.Api.OpenAICompletions.requestHeaders
    { sessionId := some "session-header"
      sendSessionAffinityHeaders := true
    }
  assertTrue (headerValue? headers "session_id" == some "session-header")
    "expected session_id affinity header"
  assertTrue (headerValue? headers "x-client-request-id" == some "session-header")
    "expected x-client-request-id affinity header"
  assertTrue (headerValue? headers "x-session-affinity" == some "session-header")
    "expected x-session-affinity header"
  let overridden := LeanAgent.AI.Api.OpenAICompletions.requestHeaders
    { sessionId := some "session-header"
      sendSessionAffinityHeaders := true
      headers := #[("x-session-affinity", some "caller-session"), ("session_id", none)]
    }
  assertTrue (headerValue? overridden "session_id" == none)
    "expected caller to suppress session_id"
  assertTrue (headerValue? overridden "x-client-request-id" == some "session-header")
    "expected non-overridden request id header"
  assertTrue (headerValue? overridden "x-session-affinity" == some "caller-session")
    "expected caller to override x-session-affinity"
  let disabled := LeanAgent.AI.Api.OpenAICompletions.requestHeaders
    { sessionId := some "session-header" }
  assertTrue (disabled.isEmpty) "expected disabled affinity headers by default"
  let noCache := LeanAgent.AI.Api.OpenAICompletions.requestHeaders
    { sessionId := some "session-header"
      cacheRetention := some .none
      sendSessionAffinityHeaders := true
    }
  assertTrue (noCache.isEmpty) "expected cacheRetention none to omit affinity headers"

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

def testOpenAICompletionsStreamingPayloadCanOmitUsageOption : IO Unit := do
  let json := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithOptions
    (basicProviderRequest)
    { supportsUsageInStreaming := false }
    LeanAgent.Models.openAIBaseUrl
  assertTrue ((LeanAgent.Json.optVal? json "stream_options").isNone)
    "expected compat to omit streaming usage option"

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

def testOpenAICompletionsCoalescesStreamingToolCallsByStableIndex : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"id\":\"chatcmpl-kimi-bad-stream\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"functions.read:0\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}"
    , ""
    , "data: {\"id\":\"chatcmpl-kimi-bad-stream\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"chatcmpl-tool-a\",\"type\":\"function\",\"function\":{\"arguments\":\"{\\\"path\\\":\\\"README\"}}]},\"finish_reason\":null}]}"
    , ""
    , "data: {\"id\":\"chatcmpl-kimi-bad-stream\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"chatcmpl-tool-b\",\"type\":\"function\",\"function\":{\"arguments\":\".md\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"prompt_tokens_details\":{\"cached_tokens\":0},\"completion_tokens_details\":{\"reasoning_tokens\":0}}}"
    , ""
    , "data: [DONE]"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAICompletions.parseStreamingEventStream
    "openai-completions" "openai" "gpt-4o-mini" 10 raw with
  | .ok stream =>
      let toolEventIndexes := stream.events.foldl (init := #[]) fun acc event =>
        match event with
        | .toolCallStart index _ => acc.push index
        | .toolCallDelta index _ _ => acc.push index
        | .toolCallEnd index _ _ => acc.push index
        | _ => acc
      assertTrue (stream.result.stopReason == .toolUse) "expected tool-use stop reason"
      assertTrue (toolEventIndexes.all fun index => index == 0)
        "expected stable index tool deltas to stay on one content index"
      match LeanAgent.AI.contentToolCalls stream.result.content |>.toList with
      | [call] =>
          assertTrue (call.id == "functions.read:0") "expected original tool id to win"
          assertTrue (call.name == "read") "expected original tool name to win"
          assertTrue
            (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected coalesced tool call arguments"
      | _ => fail "expected one coalesced tool call"
  | .error err => fail s!"stable-index streaming tool parse failed: {err}"

def testOpenAICompletionsAccumulatesMixedParallelToolDeltas : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"id\":\"chatcmpl-mixed-deltas\",\"choices\":[{\"delta\":{\"content\":\"answer 1\",\"reasoning_content\":\"think 1\",\"tool_calls\":[{\"index\":0,\"id\":\"tc_read_initial\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"README\"}},{\"index\":1,\"id\":\"tc_grep_initial\",\"type\":\"function\",\"function\":{\"name\":\"grep\",\"arguments\":\"{\\\"pattern\\\":\\\"TODO\"}},{\"id\":\"tc_list_no_index\",\"type\":\"function\",\"function\":{\"name\":\"list\",\"arguments\":\"{\\\"path\\\":\\\"packages\"}},{\"id\":\"tc_write_no_index\",\"type\":\"function\",\"function\":{\"name\":\"write\",\"arguments\":\"{\\\"path\\\":\\\"out\"}}]},\"finish_reason\":null}]}"
    , ""
    , "data: {\"id\":\"chatcmpl-mixed-deltas\",\"choices\":[{\"delta\":{\"content\":\" answer 2\",\"tool_calls\":[{\"index\":1,\"id\":\"tc_grep_changed\",\"type\":\"function\",\"function\":{\"arguments\":\"\\\",\\\"path\\\":\\\"src\"}},{\"id\":\"tc_write_no_index\",\"type\":\"function\",\"function\":{\"arguments\":\".txt\\\",\\\"content\\\":\\\"ok\\\"}\"}},{\"id\":\"tc_list_no_index\",\"type\":\"function\",\"function\":{\"arguments\":\"/ai\\\"}\"}}]},\"finish_reason\":null}]}"
    , ""
    , "data: {\"id\":\"chatcmpl-mixed-deltas\",\"choices\":[{\"delta\":{\"content\":\"\\n\",\"reasoning_content\":\" think 2\",\"tool_calls\":[{\"index\":0,\"id\":\"tc_read_changed\",\"type\":\"function\",\"function\":{\"arguments\":\".md\\\"}\"}},{\"index\":1,\"type\":\"function\",\"function\":{\"arguments\":\"\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":8,\"prompt_tokens_details\":{\"cached_tokens\":0},\"completion_tokens_details\":{\"reasoning_tokens\":2}}}"
    , ""
    , "data: [DONE]"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAICompletions.parseStreamingEventStream
    "openai-completions" "openai" "gpt-4o-mini" 10 raw with
  | .ok stream =>
      let eventTypes := stream.events.foldl (init := #[]) fun acc event =>
        acc.push <|
          match event with
          | .textStart _ _ => "text_start"
          | .textDelta _ _ _ => "text_delta"
          | .textEnd _ _ _ => "text_end"
          | .thinkingStart _ _ => "thinking_start"
          | .thinkingDelta _ _ _ => "thinking_delta"
          | .thinkingEnd _ _ _ => "thinking_end"
          | .toolCallStart _ _ => "toolcall_start"
          | .toolCallDelta _ _ _ => "toolcall_delta"
          | .toolCallEnd _ _ _ => "toolcall_end"
          | .start _ => "start"
          | .done _ _ => "completion"
          | .error _ _ => "error"
      let toolEventsByContentIndex := stream.events.foldl (init := #[]) fun acc event =>
        let pushToolEvent (index : Nat) (label : String) :=
          let existing := acc.findSome? fun (entryIndex, labels) =>
            if entryIndex == index then some labels else none
          let labels := existing.getD #[]
          let next := (labels.push label)
          if acc.any fun (entryIndex, _) => entryIndex == index then
            acc.map fun entry => if entry.fst == index then (index, next) else entry
          else
            acc.push (index, next)
        match event with
        | .toolCallStart index _ =>
            pushToolEvent index "toolcall_start"
        | .toolCallDelta index _ _ =>
            pushToolEvent index "toolcall_delta"
        | .toolCallEnd index _ _ =>
            pushToolEvent index "toolcall_end"
        | _ => acc
      let toolEventsFor (index : Nat) : Array String :=
        (toolEventsByContentIndex.findSome? fun (entryIndex, labels) =>
          if entryIndex == index then some labels else none).getD #[]
      assertTrue (stream.result.stopReason == .toolUse) "expected mixed-delta tool-use stop reason"
      assertTrue ((eventTypes.filter (fun value => value == "text_start")).size == 1) "expected one text start"
      assertTrue ((eventTypes.filter (fun value => value == "text_delta")).size == 3) "expected three text deltas"
      assertTrue ((eventTypes.filter (fun value => value == "thinking_start")).size == 1) "expected one thinking start"
      assertTrue ((eventTypes.filter (fun value => value == "thinking_delta")).size == 2) "expected two thinking deltas"
      assertTrue ((eventTypes.filter (fun value => value == "toolcall_start")).size == 4) "expected four toolcall starts"
      assertTrue ((eventTypes.filter (fun value => value == "toolcall_end")).size == 4) "expected four toolcall ends"
      assertTrue (toolEventsFor 2 == #["toolcall_start", "toolcall_delta", "toolcall_delta", "toolcall_end"])
        "expected read tool call events to stay grouped"
      assertTrue (toolEventsFor 3 == #["toolcall_start", "toolcall_delta", "toolcall_delta", "toolcall_delta", "toolcall_end"])
        "expected grep tool call events to stay grouped"
      assertTrue (toolEventsFor 4 == #["toolcall_start", "toolcall_delta", "toolcall_delta", "toolcall_end"])
        "expected list tool call events to stay grouped"
      assertTrue (toolEventsFor 5 == #["toolcall_start", "toolcall_delta", "toolcall_delta", "toolcall_end"])
        "expected write tool call events to stay grouped"
      assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "answer 1 answer 2\n\nthink 1 think 2")
        "expected mixed deltas to preserve final text and thinking blocks"
      match stream.result.content.toList with
      | [ .text text, .thinking thinking, .toolCall readCall, .toolCall grepCall, .toolCall listCall, .toolCall writeCall ] =>
          assertTrue (text.text == "answer 1 answer 2\n") "expected accumulated text content"
          assertTrue (thinking.thinking == "think 1 think 2") "expected accumulated thinking content"
          assertTrue (thinking.thinkingSignature == some "reasoning_content")
            "expected mixed thinking signature"
          assertTrue (readCall.id == "tc_read_initial") "expected read tool id"
          assertTrue (readCall.name == "read") "expected read tool name"
          assertTrue (grepCall.id == "tc_grep_initial") "expected grep tool id"
          assertTrue (grepCall.name == "grep") "expected grep tool name"
          assertTrue (listCall.id == "tc_list_no_index") "expected list tool id"
          assertTrue (listCall.name == "list") "expected list tool name"
          assertTrue (writeCall.id == "tc_write_no_index") "expected write tool id"
          assertTrue (writeCall.name == "write") "expected write tool name"
          assertTrue (LeanAgent.Json.optVal? readCall.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected read call arguments"
          assertTrue (LeanAgent.Json.optVal? grepCall.arguments "pattern" == some (LeanAgent.Json.str "TODO"))
            "expected grep pattern argument"
          assertTrue (LeanAgent.Json.optVal? grepCall.arguments "path" == some (LeanAgent.Json.str "src"))
            "expected grep path argument"
          assertTrue (LeanAgent.Json.optVal? listCall.arguments "path" == some (LeanAgent.Json.str "packages/ai"))
            "expected list call arguments"
          assertTrue (LeanAgent.Json.optVal? writeCall.arguments "path" == some (LeanAgent.Json.str "out.txt"))
            "expected write path argument"
          assertTrue (LeanAgent.Json.optVal? writeCall.arguments "content" == some (LeanAgent.Json.str "ok"))
            "expected write content argument"
      | _ => fail "expected mixed delta content ordering"
  | .error err => fail s!"mixed-delta streaming parse failed: {err}"

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

def testOpenAICompletionsParsesOpenCodeGoStreamingReasoning : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"choices\":[{\"delta\":{\"reasoning\":\"think\"},\"finish_reason\":null}]}"
    , ""
    , "data: {\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":\"stop\"}]}"
    , ""
    , "data: [DONE]"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAICompletions.parseStreamingEventStream
    "openai-completions" "opencode-go" "kimi-k2.6" 10 raw with
  | .ok stream =>
      assertTrue
        (stream.result.content.any fun
          | .thinking content => content.thinking == "think" && content.thinkingSignature == some "reasoning_content"
          | _ => false)
        "expected OpenCode Go reasoning deltas to normalize to reasoning_content"
  | .error err => fail s!"OpenCode Go streaming reasoning parse failed: {err}"

def testOpenAICompletionsParsesGenericStreamingReasoningField : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"choices\":[{\"delta\":{\"reasoning\":\"think\"},\"finish_reason\":null}]}"
    , ""
    , "data: {\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":\"stop\"}]}"
    , ""
    , "data: [DONE]"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAICompletions.parseStreamingEventStream
    "openai-completions" "openai" "gpt-4o-mini" 10 raw with
  | .ok stream =>
      assertTrue
        (stream.result.content.any fun
          | .thinking content => content.thinking == "think" && content.thinkingSignature == some "reasoning"
          | _ => false)
        "expected generic reasoning deltas to keep the reasoning signature"
  | .error err => fail s!"generic streaming reasoning parse failed: {err}"

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

def fakeOpenAICodexJwt : String :=
  "e30.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdF90ZXN0In19.sig"

def azureResponsesModel : LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel :=
  { id := "gpt-4o-mini"
    provider := "azure-openai-responses"
    api := "azure-openai-responses"
    input := #["text", "image"]
    contextWindow := 128000
    maxTokens := 16384
  }

def jsonNatField? (json : Lean.Json) (key : String) : Option Nat :=
  match LeanAgent.Json.optVal? json key with
  | some value => value.getNat?.toOption
  | none => none

def responseItemWithType? (items : Array Lean.Json) (itemType : String) : Option Lean.Json :=
  items.find? fun item => jsonStringField? item "type" == some itemType

def headerValueCaseInsensitive? (headers : Array (String × String)) (name : String) : Option String :=
  headers.findSome? fun (headerName, value) =>
    if headerName.toLower == name.toLower then some value else none

def diagnosticResponseHeaders? (diagnostic : LeanAgent.AI.AssistantMessageDiagnostic) :
    Option (Array (String × String)) := do
  let details ← diagnostic.details
  let responseHeadersJson ← LeanAgent.Json.optVal? details "responseHeaders"
  let responseHeaders ← match responseHeadersJson.getArr? with
    | .ok headers => some headers
    | .error _ => none
  responseHeaders.mapM fun entry => do
    let name ← jsonStringField? entry "name"
    let value ← jsonStringField? entry "value"
    pure (name, value)

def diagnosticResponseHeaderValueCaseInsensitive?
    (diagnostic : LeanAgent.AI.AssistantMessageDiagnostic)
    (name : String) : Option String := do
  let headers ← diagnosticResponseHeaders? diagnostic
  headerValueCaseInsensitive? headers name

def invokeResponseHookAndRead
    (hook? : Option LeanAgent.AI.ResponseHook) : IO Bool := do
  let saw ← IO.mkRef false
  let model : LeanAgent.AI.ModelRef := { id := "hook-model", api := "openai-responses", provider := "openai" }
  match hook? with
  | some hook =>
      hook { status := 200, headers := #[("x-hook", "present")] } model
      saw.set true
  | none => pure ()
  saw.get

def testOpenAIResponsesOptionsFromSimplePreserveResponseHook : IO Unit := do
  let sawHeader ← IO.mkRef false
  let options : LeanAgent.AI.SimpleStreamOptions :=
    { onResponse := some fun response _model => do
        assertTrue (headerValueCaseInsensitive? response.headers "x-hook" == some "present")
          "expected preserved response hook header"
        sawHeader.set true
      reasoning := some .medium
      maxTokens := some 32
    }
  let model : LeanAgent.Models.ModelInfo :=
    { id := responsesCodexModel.id
      name := "Responses Hook Model"
      provider := responsesCodexModel.provider
      api := responsesCodexModel.api
      baseUrl := "http://127.0.0.1"
      contextWindow := 128000
      maxTokens := 4096
      reasoning := true
    }
  let context : LeanAgent.AI.Context :=
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
  let clamped :=
    LeanAgent.AI.Providers.Streams.clampSimpleOptionsToContext
      model
      context
      options
  let apiOptions := LeanAgent.AI.Api.OpenAIResponses.optionsFromSimple clamped
  let invoked ← invokeResponseHookAndRead apiOptions.onResponse
  assertTrue invoked "expected OpenAI Responses optionsFromSimple to preserve onResponse"
  assertTrue (← sawHeader.get) "expected preserved OpenAI Responses response hook to run"

def testModelsApplyAuthPreservesResponseHook : IO Unit := do
  let sawHeader ← IO.mkRef false
  let collection ← LeanAgent.Models.createModels
  let provider ← LeanAgent.Models.createProvider
    { id := "hook-provider"
      auth := {}
      models := #[]
      apis := #[]
      headers := #[]
    }
  collection.setProvider provider
  let model : LeanAgent.Models.ModelInfo :=
    { id := "hook-model"
      name := "Hook Model"
      provider := provider.id
      api := "openai-responses"
      baseUrl := "http://127.0.0.1"
      contextWindow := 4096
      maxTokens := 512
    }
  let options : LeanAgent.AI.SimpleStreamOptions :=
    { onResponse := some fun response _model => do
        assertTrue (headerValueCaseInsensitive? response.headers "x-hook" == some "present")
          "expected applyAuth-preserved response hook header"
        sawHeader.set true
    }
  let (_requestModel, requestOptions) ← collection.applyAuth provider model options
  let invoked ← invokeResponseHookAndRead requestOptions.onResponse
  assertTrue invoked "expected applyAuth to preserve onResponse"
  assertTrue (← sawHeader.get) "expected applyAuth-preserved response hook to run"

def testModelsWithCapturedResponseHookPreservesOriginalHook : IO Unit := do
  let sawOriginalHook ← IO.mkRef false
  let options : LeanAgent.AI.SimpleStreamOptions :=
    { onResponse := some fun response _model => do
        assertTrue (headerValueCaseInsensitive? response.headers "x-hook" == some "present")
          "expected wrapped response hook header"
        sawOriginalHook.set true
    }
  let (responseRef, wrapped) ← LeanAgent.Models.withCapturedResponseHook options
  let invoked ← invokeResponseHookAndRead wrapped.onResponse
  assertTrue invoked "expected wrapped onResponse hook to exist"
  assertTrue (← sawOriginalHook.get) "expected wrapped onResponse to preserve original hook"
  match ← responseRef.get with
  | some response =>
      assertTrue (response.status == 200) "expected wrapped response hook to capture status"
      assertTrue
        (headerValueCaseInsensitive? response.headers "x-hook" == some "present")
        "expected wrapped response hook to capture headers"
  | none => fail "expected wrapped response hook to capture response"

def testModelsWithCapturedResponseHookCapturesResponseBeforeOriginalHookFailure : IO Unit := do
  let options : LeanAgent.AI.SimpleStreamOptions :=
    { onResponse := some fun _response _model => do
        throw (IO.userError "response hook failed")
    }
  let (responseRef, wrapped) ← LeanAgent.Models.withCapturedResponseHook options
  let model : LeanAgent.AI.ModelRef := { id := "hook-model", api := "openai-responses", provider := "openai" }
  let failed ←
    try
      match wrapped.onResponse with
      | some hook =>
          hook { status := 200, headers := #[("x-hook", "present")] } model
          pure false
      | none => pure false
    catch err =>
      pure (err.toString.contains "response hook failed")
  assertTrue failed "expected wrapped response hook to propagate original failure"
  match ← responseRef.get with
  | some response =>
      assertTrue (response.status == 200) "expected wrapped hook failure path to capture status"
      assertTrue
        (headerValueCaseInsensitive? response.headers "x-hook" == some "present")
        "expected wrapped hook failure path to capture headers"
  | none => fail "expected wrapped hook failure path to capture response"

def testWrappedOpenAIResponsesCompatOptionChainPreservesResponseHook : IO Unit := do
  let sawOriginalHook ← IO.mkRef false
  let baseOptions : LeanAgent.AI.SimpleStreamOptions :=
    { onResponse := some fun response _model => do
        assertTrue (headerValueCaseInsensitive? response.headers "x-hook" == some "present")
          "expected chained response hook header"
        sawOriginalHook.set true
      apiKey := some "test-key"
      reasoning := some .medium
    }
  let model : LeanAgent.Models.ModelInfo :=
    { id := responsesCodexModel.id
      name := "Wrapped Responses Hook Model"
      provider := responsesCodexModel.provider
      api := responsesCodexModel.api
      baseUrl := "http://127.0.0.1"
      contextWindow := 128000
      maxTokens := 4096
      reasoning := true
    }
  let context : LeanAgent.AI.Context :=
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
  let (responseRef, wrappedOptions) ← LeanAgent.Models.withCapturedResponseHook baseOptions
  let clamped :=
    LeanAgent.AI.Providers.Streams.clampSimpleOptionsToContext
      model
      context
      wrappedOptions
  let apiOptions := LeanAgent.AI.Api.OpenAIResponses.optionsFromSimple clamped
  let invoked ← invokeResponseHookAndRead apiOptions.onResponse
  assertTrue invoked "expected wrapped compat option chain to preserve onResponse"
  assertTrue (← sawOriginalHook.get) "expected wrapped compat option chain to run original hook"
  match ← responseRef.get with
  | some response =>
      assertTrue (response.status == 200) "expected wrapped compat option chain to capture status"
      assertTrue
        (headerValueCaseInsensitive? response.headers "x-hook" == some "present")
        "expected wrapped compat option chain to capture headers"
  | none => fail "expected wrapped compat option chain to capture response"

def testBuiltinOpenAIApplyAuthPreservesResponseHook : IO Unit := do
  let sawHeader ← IO.mkRef false
  let collection ← LeanAgent.Models.createModels
  let provider ← LeanAgent.AI.Providers.OpenAI.provider
  collection.setProvider provider
  let model : LeanAgent.Models.ModelInfo :=
    { id := "gpt-5.4"
      name := "GPT 5.4"
      provider := LeanAgent.Models.openAIProviderId
      api := "openai-responses"
      baseUrl := "http://127.0.0.1"
      contextWindow := 100000
      maxTokens := 4096
      reasoning := true
    }
  let options : LeanAgent.AI.SimpleStreamOptions :=
    { apiKey := some "test-key"
      onResponse := some fun response _model => do
        assertTrue (headerValueCaseInsensitive? response.headers "x-hook" == some "present")
          "expected builtin OpenAI applyAuth response hook header"
        sawHeader.set true
    }
  let (_requestModel, requestOptions) ← collection.applyAuth provider model options
  let invoked ← invokeResponseHookAndRead requestOptions.onResponse
  assertTrue invoked "expected builtin OpenAI applyAuth to preserve onResponse"
  assertTrue (← sawHeader.get) "expected builtin OpenAI applyAuth response hook to run"

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

def testOpenAIResponsesSharedGeneratesFallbackMessageIds : IO Unit := do
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .thinking { thinking := "private reasoning" }
         , .text { text := "visible answer" }
         ]
      api := LeanAgent.AI.Api.AnthropicMessages.api
      provider := LeanAgent.Models.anthropicProviderId
      model := "claude-opus-4-8"
      stopReason := .stop
      timestamp := 2
    }
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "You are concise."
      messages :=
        #[ .user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }
         , .assistant assistant
         ]
    }
  let input := LeanAgent.AI.Api.OpenAIResponsesShared.convertResponsesMessages responsesCodexModel context
  let messageIds :=
    input.toList.filterMap fun item =>
      if jsonStringField? item "type" == some "message" then
        jsonStringField? item "id"
      else
        none
  assertTrue (messageIds == ["msg_pi_1", "msg_pi_1_1"])
    s!"expected fallback OpenAI Responses message ids, got {messageIds}"
  assertTrue (messageIds.eraseDups.length == messageIds.length)
    "expected fallback OpenAI Responses message ids to stay unique"

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

def anthropicModelRef : LeanAgent.AI.ModelRef :=
  { id := LeanAgent.Models.anthropicDefaultModel
    api := LeanAgent.AI.Api.AnthropicMessages.api
    provider := LeanAgent.Models.anthropicProviderId
    baseUrl := some LeanAgent.Models.anthropicBaseUrl
  }

def googleModelRef : LeanAgent.AI.ModelRef :=
  { id := LeanAgent.Models.googleDefaultModel
    api := LeanAgent.AI.Api.GoogleGenerativeAI.api
    provider := LeanAgent.Models.googleProviderId
    baseUrl := some LeanAgent.Models.googleBaseUrl
  }

def googleVertexModelRef : LeanAgent.AI.ModelRef :=
  { id := LeanAgent.Models.googleVertexDefaultModel
    api := LeanAgent.AI.Api.GoogleVertex.api
    provider := LeanAgent.Models.googleVertexProviderId
    baseUrl := some LeanAgent.Models.googleVertexBaseUrl
  }

def googleVertexServiceAccountPrivateKey : String :=
  String.intercalate "\n"
    [ "-----BEGIN PRIVATE KEY-----"
    , "MIICeQIBADANBgkqhkiG9w0BAQEFAASCAmMwggJfAgEAAoGBAKO+3IZCNgRIVSjj"
    , "mCy70KrvYytmvz5cKwgnJfD40b60ugOGEn1MVjH2TmT5o7Eo6mkh7hL8vTR4/sc9"
    , "upJkuDsAmCU58Y5XEAL9UzCBKgrW1CnnBkHL9ki3+scvU5V1n0IQR6b6+yEAJeED"
    , "dPitZBO86SOFpYB7PlP7W28uf75DAgMBAAECgYEAjSqai9TBJOgHIv0z0D0LJJLE"
    , "+EHYVja3kovNlfWtPbApPah0gDkzhldGNp9RlAYmMQTjbtMdewNlAvggxNy4RiQG"
    , "N4K/Ag6U0UPi2jgvk6du5xH8ke73TNrc6HH7nz0S4mTs6KcPMXVCjyrvFcXtXFpW"
    , "hTLsQDC50vKlFIZN/cECQQDZzWIbX8k/umWFLadva4XIDLwaEfBSGPTK/d6u7+a5"
    , "wDRSAW7l8tseBpwvEWo/4WxbE54OYX+bbNUcW9MNIj35AkEAwHaBnYQQiKHKYIx8"
    , "27DM+lLc4L9OZaac1A9AsomzcWP+ruPobYOMow0Ix0ZtlStb3HvKw95npoUDpQUf"
    , "kU4dGwJBAKu1GppAKrW+KpkTBAR4PTEYsRbQe6kNmbeK64r5AOoCGH1qOda5XnvO"
    , "dEU7MouIGVe4IIxv2x1acKx5y+p3y2kCQQCOqMjWuweOX26lNj1ukpS9kCJNLUCt"
    , "NFzXCx9Ht64dBKPJewHT+0iJq6WwIFIl2efTfKcFnJtz4PCcpzmI+T+1AkEAyRLr"
    , "CwCVEkPII7ose21UEqjW3og+tb0LvuWp76p7Brl7nUqI2H+PRPX21JAkoogYgzZ4"
    , "MR/bhhwyieF89SILmw=="
    , "-----END PRIVATE KEY-----"
    , ""
    ]

def writeGoogleVertexServiceAccountCredentials
    (path : System.FilePath)
    (tokenUri : String) : IO Unit := do
  IO.FS.writeFile path
    ((LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "service_account")
      , ("client_email", LeanAgent.Json.str "test-service@example.com")
      , ("private_key", LeanAgent.Json.str googleVertexServiceAccountPrivateKey)
      , ("token_uri", LeanAgent.Json.str tokenUri)
      ]).compress)

def writeGoogleVertexAuthorizedUserCredentials
    (path : System.FilePath)
    (tokenUri : String) : IO Unit := do
  IO.FS.writeFile path
    ((LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "authorized_user")
      , ("client_id", LeanAgent.Json.str "test-client-id")
      , ("client_secret", LeanAgent.Json.str "test-client-secret")
      , ("refresh_token", LeanAgent.Json.str "test-refresh-token")
      , ("token_uri", LeanAgent.Json.str tokenUri)
      ]).compress)

def mistralModelRef : LeanAgent.AI.ModelRef :=
  { id := LeanAgent.Models.mistralDefaultModel
    api := LeanAgent.AI.Api.MistralConversations.api
    provider := LeanAgent.Models.mistralProviderId
    baseUrl := some LeanAgent.Models.mistralBaseUrl
  }

def bedrockModelRef : LeanAgent.AI.ModelRef :=
  { id := LeanAgent.Models.amazonBedrockDefaultModel
    api := LeanAgent.AI.Api.BedrockConverseStream.api
    provider := LeanAgent.Models.amazonBedrockProviderId
    baseUrl := some LeanAgent.Models.amazonBedrockBaseUrl
  }

def openAICompletionsContextModel : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsModel :=
  { id := "gpt-4o-mini"
    provider := LeanAgent.Models.openAIProviderId
    api := "openai-completions"
    input := #["text", "image"]
  }

def testOpenAICompletionsContextSerializesUserImages : IO Unit := do
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    openAICompletionsContextModel
    { messages :=
        #[ .user
            { content :=
                #[ LeanAgent.AI.text "describe"
                 , LeanAgent.AI.image "QUJD" "image/png"
                 ]
              timestamp := 1
            }
         ]
    }
  match jsonArrayField? payload "messages" with
  | some messages =>
      match messages[0]? with
      | some user =>
          assertTrue (jsonStringField? user "role" == some "user") "expected user role"
          match jsonArrayField? user "content" with
          | some content =>
              match content[0]?, content[1]? with
              | some textPart, some imagePart =>
                  assertTrue (jsonStringField? textPart "type" == some "text")
                    "expected text content part"
                  assertTrue (jsonStringField? textPart "text" == some "describe")
                    "expected user text"
                  assertTrue (jsonStringField? imagePart "type" == some "image_url")
                    "expected image content part"
                  match jsonObjectField? imagePart "image_url" with
                  | some imageUrl =>
                      assertTrue
                        (jsonStringField? imageUrl "url" == some "data:image/png;base64,QUJD")
                        "expected user image data URL"
                  | none => fail "expected image_url object"
              | _, _ => fail "expected user text and image parts"
          | none => fail "expected user content array"
      | none => fail "expected user message"
  | none => fail "expected OpenAI-compatible messages array"

def testOpenAICompletionsContextBatchesToolResultImages : IO Unit := do
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall
            { id := "tool-1"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "img-1.png")]
            }
         , .toolCall
            { id := "tool-2"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "img-2.png")]
            }
         ]
      api := openAICompletionsContextModel.api
      provider := openAICompletionsContextModel.provider
      model := openAICompletionsContextModel.id
      stopReason := .toolUse
      timestamp := 2
    }
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    openAICompletionsContextModel
    { messages :=
        #[ .user { content := #[LeanAgent.AI.text "Read the images"], timestamp := 1 }
         , .assistant assistant
         , .toolResult
            { toolCallId := "tool-1"
              toolName := "read"
              content :=
                #[ LeanAgent.AI.text "Read image file [image/png]"
                 , LeanAgent.AI.image "ZmFrZQ==" "image/png"
                 ]
              isError := false
              timestamp := 3
            }
         , .toolResult
            { toolCallId := "tool-2"
              toolName := "read"
              content :=
                #[ LeanAgent.AI.text "Read image file [image/png]"
                 , LeanAgent.AI.image "YmFy" "image/png"
                 ]
              isError := false
              timestamp := 4
            }
         ]
    }
  match jsonArrayField? payload "messages" with
  | some messages =>
      let roles :=
        messages.map (fun message => (jsonStringField? message "role").getD "")
      assertTrue (roles == #["user", "assistant", "tool", "tool", "user"])
        "expected grouped tool-result image replay as a trailing user turn"
      match messages[4]? with
      | some imageReplay =>
          match jsonArrayField? imageReplay "content" with
          | some content =>
              assertTrue (content.size == 3) "expected one text marker plus two replayed images"
              assertTrue (jsonStringField? content[0]! "type" == some "text")
                "expected replay marker text block"
              assertTrue (jsonStringField? content[1]! "type" == some "image_url")
                "expected first replay image block"
              assertTrue (jsonStringField? content[2]! "type" == some "image_url")
                "expected second replay image block"
              match jsonObjectField? content[1]! "image_url", jsonObjectField? content[2]! "image_url" with
              | some firstUrl, some secondUrl =>
                  assertTrue
                    (jsonStringField? firstUrl "url" == some "data:image/png;base64,ZmFrZQ==")
                    "expected first replay image data URL"
                  assertTrue
                    (jsonStringField? secondUrl "url" == some "data:image/png;base64,YmFy")
                    "expected second replay image data URL"
              | _, _ => fail "expected replay image_url objects"
          | none => fail "expected replay content array"
      | none => fail "expected trailing replay user message"
  | none => fail "expected OpenAI-compatible messages array"

def testOpenAICompletionsContextRequiresToolResultNameAndBridgeForImageReplay : IO Unit := do
  let model :=
    { openAICompletionsContextModel with
      requiresToolResultName := true
      requiresAssistantAfterToolResult := true
    }
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall
            { id := "tool-1"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "img.png")]
            }
         ]
      api := model.api
      provider := model.provider
      model := model.id
      stopReason := .toolUse
      timestamp := 2
    }
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    model
    { messages :=
        #[ .user { content := #[LeanAgent.AI.text "Read the image"], timestamp := 1 }
         , .assistant assistant
         , .toolResult
            { toolCallId := "tool-1"
              toolName := "read"
              content :=
                #[ LeanAgent.AI.text "Read image file [image/png]"
                 , LeanAgent.AI.image "ZmFrZQ==" "image/png"
                 ]
              isError := false
              timestamp := 3
            }
         ]
    }
  match jsonArrayField? payload "messages" with
  | some messages =>
      let roles := messages.map (fun message => (jsonStringField? message "role").getD "")
      assertTrue (roles == #["user", "assistant", "tool", "assistant", "user"])
        "expected compat bridge before grouped tool-result image replay"
      match messages[1]?, messages[2]?, messages[3]? with
      | some replayedAssistant, some toolResult, some bridge =>
          assertTrue (LeanAgent.Json.optVal? replayedAssistant "content" == some (LeanAgent.Json.str ""))
            "expected compat assistant tool-call replay to use empty-string content"
          assertTrue (jsonStringField? toolResult "name" == some "read")
            "expected compat tool result name field"
          assertTrue (jsonStringField? bridge "content" == some "I have processed the tool results.")
            "expected compat bridge assistant content"
      | _, _, _ => fail "expected compat assistant, tool result, and bridge messages"
  | none => fail "expected OpenAI-compatible messages array"

def testOpenAICompletionsContextAddsBridgeBeforeUserAfterToolResults : IO Unit := do
  let model :=
    { openAICompletionsContextModel with
      requiresAssistantAfterToolResult := true
    }
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall
            { id := "tool-1"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
            }
         ]
      api := model.api
      provider := model.provider
      model := model.id
      stopReason := .toolUse
      timestamp := 2
    }
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    model
    { messages :=
        #[ .user { content := #[LeanAgent.AI.text "Use the read tool"], timestamp := 1 }
         , .assistant assistant
         , .toolResult
            { toolCallId := "tool-1"
              toolName := "read"
              content := #[LeanAgent.AI.text "README contents"]
              isError := false
              timestamp := 3
            }
         , .user { content := #[LeanAgent.AI.text "Summarize it"], timestamp := 4 }
         ]
    }
  match jsonArrayField? payload "messages" with
  | some messages =>
      let roles := messages.map (fun message => (jsonStringField? message "role").getD "")
      assertTrue (roles == #["user", "assistant", "tool", "assistant", "user"])
        "expected compat bridge before user after tool results"
      match messages[3]? with
      | some bridge =>
          assertTrue (jsonStringField? bridge "content" == some "I have processed the tool results.")
            "expected compat bridge assistant content before user follow-up"
      | none => fail "expected compat bridge assistant message"
  | none => fail "expected OpenAI-compatible messages array"

def testOpenAICompletionsContextAddsRoutingPreferences : IO Unit := do
  let openRouterRouting :=
    LeanAgent.Json.obj
      [ ("only", LeanAgent.Json.arr #[LeanAgent.Json.str "anthropic"])
      , ("allow_fallbacks", LeanAgent.Json.bool false)
      ]
  let vercelRouting :=
    LeanAgent.Json.obj
      [ ("only", LeanAgent.Json.arr #[LeanAgent.Json.str "bedrock"])
      , ("order", LeanAgent.Json.arr #[LeanAgent.Json.str "anthropic", LeanAgent.Json.str "openai"])
      ]
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.openRouterProviderId
      openRouterRouting := some openRouterRouting
      vercelGatewayRouting := some vercelRouting
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
  assertTrue (LeanAgent.Json.optVal? payload "provider" == some openRouterRouting)
    "expected OpenRouter routing passthrough"
  match jsonObjectField? payload "providerOptions" >>= fun options => jsonObjectField? options "gateway" with
  | some gateway =>
      assertTrue ((LeanAgent.Json.optVal? gateway "only").isSome)
        "expected Vercel gateway only routing"
      assertTrue ((LeanAgent.Json.optVal? gateway "order").isSome)
        "expected Vercel gateway order routing"
  | none => fail "expected Vercel gateway providerOptions"

def testOpenAICompletionsContextReplaysXiaomiMissingThinkingAsEmptyReasoningContent : IO Unit := do
  match LeanAgent.Models.xiaomiModels.find? (fun model => model.id == "mimo-v2.5-pro") with
  | none => fail "expected Xiaomi MiMo V2.5 Pro model"
  | some modelInfo =>
      let model :=
        LeanAgent.AI.Providers.Streams.openAICompletionsModelFromModelInfo modelInfo
      let options :=
        LeanAgent.AI.Providers.Streams.openAICompletionsOptionsFromSimple
          modelInfo
          { reasoning := some .high }
      let assistant : LeanAgent.AI.AssistantMessage :=
        { content :=
            #[ .toolCall
                { id := "call_1"
                  name := "read"
                  arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
                }
             ]
          api := model.api
          provider := model.provider
          model := model.id
          stopReason := .toolUse
          timestamp := 2
        }
      let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
        model
        { messages :=
            #[ .user { content := #[LeanAgent.AI.text "Read README.md"], timestamp := 1 }
             , .assistant assistant
             , .toolResult
                { toolCallId := "call_1"
                  toolName := "read"
                  content := #[LeanAgent.AI.text "contents"]
                  isError := false
                  timestamp := 3
                }
             ]
        }
        options
        modelInfo.baseUrl
      match jsonArrayField? payload "messages", jsonObjectField? payload "thinking" with
      | some messages, some thinking =>
          match messages[1]? with
          | some replayedAssistant =>
              assertTrue (jsonStringField? replayedAssistant "role" == some "assistant")
                "expected Xiaomi replayed assistant role"
              assertTrue (jsonStringField? replayedAssistant "reasoning_content" == some "")
                "expected Xiaomi replay to add empty reasoning_content"
              assertTrue (jsonStringField? thinking "type" == some "enabled")
                "expected Xiaomi payload to enable thinking"
              assertTrue (jsonStringField? payload "reasoning_effort" == some "high")
                "expected Xiaomi payload to keep reasoning_effort"
          | none => fail "expected Xiaomi replayed assistant message"
      | _, _ => fail "expected Xiaomi OpenAI-compatible messages and thinking payload"

def testOpenAICompletionsContextReplaysThinkingAsText : IO Unit := do
  let model :=
    { openAICompletionsContextModel with
      provider := "repro-provider"
      reasoning := true
      requiresThinkingAsText := true
    }
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .thinking { thinking := "internal reasoning" }
         , .text { text := "visible answer" }
         ]
      api := model.api
      provider := model.provider
      model := model.id
      stopReason := .stop
      timestamp := 2
    }
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    model
    { messages :=
        #[ .user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }
         , .assistant assistant
         ]
    }
  match jsonArrayField? payload "messages" with
  | some messages =>
      match messages[1]? with
      | some replayedAssistant =>
          assertTrue (jsonStringField? replayedAssistant "role" == some "assistant")
            "expected replayed assistant role"
          assertTrue ((LeanAgent.Json.optVal? replayedAssistant "reasoning_content").isNone)
            "expected thinking-as-text replay to omit reasoning_content"
          match jsonArrayField? replayedAssistant "content" with
          | some content =>
              assertTrue (content.size == 2) "expected thinking and text replay blocks"
              assertTrue (jsonStringField? content[0]! "type" == some "text")
                "expected thinking text block"
              assertTrue (jsonStringField? content[0]! "text" == some "internal reasoning")
                "expected replayed thinking text"
              assertTrue (jsonStringField? content[1]! "text" == some "visible answer")
                "expected replayed assistant text"
          | none => fail "expected assistant content array"
      | none => fail "expected replayed assistant message"
  | none => fail "expected OpenAI-compatible messages array"

def testOpenAICompletionsContextAddsAnthropicCacheMarkers : IO Unit := do
  let model :=
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.openRouterProviderId
      id := "anthropic/claude-sonnet-4"
      cacheControlFormat := some "anthropic"
    }
  let tool : LeanAgent.AI.Tool :=
    { name := "read"
      description := "Read a file"
      parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
    }
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    model
    { systemPrompt := some "System prompt"
      messages := #[.user { content := #[LeanAgent.AI.text "Hello"], timestamp := 1 }]
      tools := #[tool]
    }
    { cacheRetention := some .long }
  match jsonArrayField? payload "messages", jsonArrayField? payload "tools" with
  | some messages, some tools =>
      match messages[0]?, messages[messages.size - 1]?, tools[0]? with
      | some instruction, some lastMessage, some lastTool =>
          match jsonArrayField? instruction "content", jsonArrayField? lastMessage "content",
              jsonObjectField? lastTool "cache_control" with
          | some instructionContent, some lastContent, some toolCacheControl =>
              match jsonObjectField? instructionContent[0]! "cache_control",
                  jsonObjectField? lastContent[0]! "cache_control" with
              | some instructionCacheControl, some lastCacheControl =>
                  assertTrue (jsonStringField? instructionCacheControl "type" == some "ephemeral")
                    "expected instruction cache-control type"
                  assertTrue (jsonStringField? instructionCacheControl "ttl" == some "1h")
                    "expected instruction cache-control ttl"
                  assertTrue (jsonStringField? lastCacheControl "type" == some "ephemeral")
                    "expected last message cache-control type"
                  assertTrue (jsonStringField? lastCacheControl "ttl" == some "1h")
                    "expected last message cache-control ttl"
                  assertTrue (jsonStringField? toolCacheControl "type" == some "ephemeral")
                    "expected tool cache-control type"
                  assertTrue (jsonStringField? toolCacheControl "ttl" == some "1h")
                    "expected tool cache-control ttl"
              | _, _ => fail "expected cache_control markers on instruction and last message text"
          | _, _, _ => fail "expected cache markers on messages and tool"
      | _, _, _ => fail "expected instruction message, last conversation message, and last tool"
  | _, _ => fail "expected OpenAI-compatible messages and tools arrays"

def testOpenAICompletionsContextStrictCompat : IO Unit := do
  let tool : LeanAgent.AI.Tool :=
    { name := "read"
      description := "Read a file"
      parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
    }
  let enabledPayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    openAICompletionsContextModel
    { messages := #[.user { content := #[LeanAgent.AI.text "Hello"], timestamp := 1 }]
      tools := #[tool]
    }
  let disabledPayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with supportsStrictMode := false }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hello"], timestamp := 1 }]
      tools := #[tool]
    }
  match jsonArrayField? enabledPayload "tools", jsonArrayField? disabledPayload "tools" with
  | some enabledTools, some disabledTools =>
      match jsonObjectField? enabledTools[0]! "function", jsonObjectField? disabledTools[0]! "function" with
      | some enabledFn, some disabledFn =>
          assertTrue
            (LeanAgent.Json.optVal? enabledFn "strict" == some (LeanAgent.Json.bool false))
            "expected strict=false when compat allows strict mode"
          assertTrue ((LeanAgent.Json.optVal? disabledFn "strict").isNone)
            "expected strict to be omitted when compat disables it"
      | _, _ => fail "expected encoded tool functions"
  | _, _ => fail "expected encoded tools arrays"

def testOpenAICompletionsContextSetsZaiToolStream : IO Unit := do
  let tool : LeanAgent.AI.Tool :=
    { name := "ping"
      description := "Ping tool"
      parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
    }
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.zaiProviderId
      zaiToolStream := true
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hello"], timestamp := 1 }]
      tools := #[tool]
    }
  let withoutTools := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.zaiProviderId
      zaiToolStream := true
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hello"], timestamp := 1 }] }
  assertTrue
    (LeanAgent.Json.optVal? payload "tool_stream" == some (LeanAgent.Json.bool true))
    "expected z.ai tool_stream when tools are present"
  assertTrue ((LeanAgent.Json.optVal? withoutTools "tool_stream").isNone)
    "expected tool_stream omission without tools"

def testOpenAICompletionsParsesReasoningDetailsBeforeToolCall : IO Unit := do
  let reasoningDetail :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "reasoning.encrypted")
      , ("id", LeanAgent.Json.str "call_1")
      , ("data", LeanAgent.Json.str "encrypted-signature")
      ]
  let firstChunk :=
    LeanAgent.Json.obj
      [ ("id", LeanAgent.Json.str "chatcmpl-reasoning")
      , ("model", LeanAgent.Json.str "repro-model")
      , ("choices",
          LeanAgent.Json.arr
            #[LeanAgent.Json.obj
              [ ("index", LeanAgent.Json.nat 0)
              , ("delta",
                  LeanAgent.Json.obj
                    [("reasoning_details", LeanAgent.Json.arr #[reasoningDetail])])
              , ("finish_reason", LeanAgent.Json.null)
              ]])
      ]
  let secondChunk :=
    LeanAgent.Json.obj
      [ ("id", LeanAgent.Json.str "chatcmpl-reasoning")
      , ("model", LeanAgent.Json.str "repro-model")
      , ("choices",
          LeanAgent.Json.arr
            #[LeanAgent.Json.obj
              [ ("index", LeanAgent.Json.nat 0)
              , ("delta",
                  LeanAgent.Json.obj
                    [ ("tool_calls",
                        LeanAgent.Json.arr
                          #[LeanAgent.Json.obj
                            [ ("index", LeanAgent.Json.nat 0)
                            , ("id", LeanAgent.Json.str "call_1")
                            , ("type", LeanAgent.Json.str "function")
                            , ("function",
                                LeanAgent.Json.obj
                                  [ ("name", LeanAgent.Json.str "read")
                                  , ("arguments", LeanAgent.Json.str "{\"path\":\"README.md\"}")
                                  ])
                            ]])
                    ])
              , ("finish_reason", LeanAgent.Json.str "tool_calls")
              ]])
      ]
  let raw :=
    "data: " ++ firstChunk.compress ++ "\n\n" ++
    "data: " ++ secondChunk.compress ++ "\n\n" ++
    "data: [DONE]\n\n"
  match LeanAgent.AI.Api.OpenAICompletions.parseStreamingEventStream
      "openai-completions"
      "openrouter"
      "repro-model"
      7
      raw with
  | .ok stream =>
      assertTrue (stream.result.stopReason == .toolUse) "expected tool-use stop reason"
      match LeanAgent.AI.contentToolCalls stream.result.content |>.toList with
      | [call] =>
          assertTrue (call.id == "call_1") "expected tool-call id"
          assertTrue (call.thoughtSignature == some reasoningDetail.compress)
            "expected reasoning detail to bind to the matching tool call"
      | _ => fail "expected one parsed tool call"
  | .error err => fail s!"expected reasoning-detail parse success: {err}"

def testOpenAICompletionsContextReplaysReasoningDetails : IO Unit := do
  let reasoningDetail :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "reasoning.encrypted")
      , ("id", LeanAgent.Json.str "call_1")
      , ("data", LeanAgent.Json.str "encrypted-signature")
      ]
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall
            { id := "call_1"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
              thoughtSignature := some reasoningDetail.compress
            }
         ]
      api := "openai-completions"
      provider := "openrouter"
      model := "repro-model"
      stopReason := .toolUse
      timestamp := 2
    }
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := "openrouter"
      id := "repro-model"
    }
    { messages :=
        #[ .user { content := #[LeanAgent.AI.text "Use the read tool"], timestamp := 1 }
         , .assistant assistant
         ]
    }
  match jsonArrayField? payload "messages" with
  | some messages =>
      match messages[1]? with
      | some replayedAssistant =>
          match jsonArrayField? replayedAssistant "reasoning_details" with
          | some details =>
              assertTrue (details == #[reasoningDetail])
                "expected reasoning_details replay on assistant tool-call message"
          | none => fail "expected reasoning_details array on replayed assistant message"
      | none => fail "expected replayed assistant message"
  | none => fail "expected OpenAI-compatible messages array"

def testOpenAICompletionsContextUsesOpenRouterReasoningObject : IO Unit := do
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.openRouterProviderId
      id := "deepseek/deepseek-r1"
      reasoning := true
      thinkingFormat := some "openrouter"
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { reasoning := some .high }
  match jsonObjectField? payload "reasoning" with
  | some reasoning =>
      assertTrue (jsonStringField? reasoning "effort" == some "high")
        "expected OpenRouter reasoning object effort"
      assertTrue ((LeanAgent.Json.optVal? payload "reasoning_effort").isNone)
        "expected OpenRouter payload to omit top-level reasoning_effort"
  | none => fail "expected OpenRouter reasoning object"

def testOpenAICompletionsContextUsesDeepSeekThinkingToggle : IO Unit := do
  let enabledPayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.deepSeekProviderId
      id := "deepseek-v4-pro"
      reasoning := true
      supportsDeveloperRole := false
      thinkingFormat := some "deepseek"
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { reasoning := some .high }
  let disabledPayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.deepSeekProviderId
      id := "deepseek-v4-pro"
      reasoning := true
      supportsDeveloperRole := false
      thinkingFormat := some "deepseek"
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { offThinkingEnabled := true }
  match jsonObjectField? enabledPayload "thinking", jsonObjectField? disabledPayload "thinking" with
  | some enabledThinking, some disabledThinking =>
      assertTrue (jsonStringField? enabledThinking "type" == some "enabled")
        "expected DeepSeek thinking enable marker"
      assertTrue (jsonStringField? disabledThinking "type" == some "disabled")
        "expected DeepSeek thinking disable marker"
      assertTrue (LeanAgent.Json.optVal? enabledPayload "reasoning_effort" == some (LeanAgent.Json.str "high"))
        "expected DeepSeek reasoning_effort when thinking is enabled"
      assertTrue ((LeanAgent.Json.optVal? disabledPayload "reasoning_effort").isNone)
        "expected no DeepSeek reasoning_effort when thinking is off"
  | _, _ => fail "expected DeepSeek thinking payload objects"

def testOpenAICompletionsContextUsesQwenThinkingFlags : IO Unit := do
  let qwenPayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := "local-vllm"
      id := "Qwen/Qwen3-Coder"
      reasoning := true
      thinkingFormat := some "qwen"
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { reasoning := some .high }
  let qwenChatTemplatePayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := "local-vllm"
      id := "Qwen/Qwen3-Coder"
      reasoning := true
      thinkingFormat := some "qwen-chat-template"
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { reasoning := some .high }
  assertTrue (LeanAgent.Json.optVal? qwenPayload "enable_thinking" == some (LeanAgent.Json.bool true))
    "expected qwen enable_thinking flag"
  match jsonObjectField? qwenChatTemplatePayload "chat_template_kwargs" with
  | some kwargs =>
      assertTrue (LeanAgent.Json.optVal? kwargs "enable_thinking" == some (LeanAgent.Json.bool true))
        "expected qwen chat-template thinking flag"
      assertTrue (LeanAgent.Json.optVal? kwargs "preserve_thinking" == some (LeanAgent.Json.bool true))
        "expected qwen chat-template preserve_thinking flag"
  | none => fail "expected qwen chat_template_kwargs"

def testOpenAICompletionsContextUsesConfigurableChatTemplateKwargs : IO Unit := do
  let kwargs :=
    LeanAgent.Json.obj
      [ ("thinking", LeanAgent.Json.obj [("$var", LeanAgent.Json.str "thinking.enabled")])
      , ("preserve_thinking", LeanAgent.Json.bool true)
      , ("reasoning_effort",
          LeanAgent.Json.obj
            [ ("$var", LeanAgent.Json.str "thinking.effort")
            , ("omitWhenOff", LeanAgent.Json.bool true)
            ])
      ]
  let enabledPayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := "local-vllm"
      id := "unsloth/gpt-oss-120b-GGUF"
      reasoning := true
      thinkingFormat := some "chat-template"
      chatTemplateKwargs := some kwargs
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { reasoning := some .xhigh
      reasoningEffortValue := some "max"
    }
  let disabledPayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := "local-vllm"
      id := "unsloth/gpt-oss-120b-GGUF"
      reasoning := true
      thinkingFormat := some "chat-template"
      chatTemplateKwargs := some kwargs
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { offReasoningEffortValue := some "none"
      offThinkingEnabled := true
    }
  match jsonObjectField? enabledPayload "chat_template_kwargs", jsonObjectField? disabledPayload "chat_template_kwargs" with
  | some enabledKwargs, some disabledKwargs =>
      assertTrue (LeanAgent.Json.optVal? enabledKwargs "thinking" == some (LeanAgent.Json.bool true))
        "expected configurable chat-template thinking enable"
      assertTrue (LeanAgent.Json.optVal? enabledKwargs "preserve_thinking" == some (LeanAgent.Json.bool true))
        "expected configurable chat-template static kwarg"
      assertTrue (LeanAgent.Json.optVal? enabledKwargs "reasoning_effort" == some (LeanAgent.Json.str "max"))
        "expected configurable chat-template mapped effort"
      assertTrue (LeanAgent.Json.optVal? disabledKwargs "thinking" == some (LeanAgent.Json.bool false))
        "expected configurable chat-template thinking disable"
      assertTrue ((LeanAgent.Json.optVal? disabledKwargs "reasoning_effort").isNone)
        "expected omitWhenOff to remove disabled effort kwarg"
  | _, _ => fail "expected configurable chat_template_kwargs payloads"

def testOpenAICompletionsContextOmitsChatTemplateKwargsForNonReasoningModel : IO Unit := do
  let kwargs :=
    LeanAgent.Json.obj
      [ ("thinking", LeanAgent.Json.obj [("$var", LeanAgent.Json.str "thinking.enabled")])
      , ("preserve_thinking", LeanAgent.Json.bool true)
      ]
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := "local-vllm"
      id := "unsloth/gpt-oss-120b-GGUF"
      reasoning := false
      thinkingFormat := some "chat-template"
      chatTemplateKwargs := some kwargs
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { reasoning := some .high }
  assertTrue ((LeanAgent.Json.optVal? payload "chat_template_kwargs").isNone)
    "expected non-reasoning models to omit chat_template_kwargs"

def testOpenAICompletionsContextUsesAntLingReasoningObject : IO Unit := do
  let payload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.antLingProviderId
      id := "Ring-2.6-1T"
      reasoning := true
      supportsStore := false
      supportsDeveloperRole := false
      thinkingFormat := some "ant-ling"
    }
    { systemPrompt := some "Follow instructions."
      messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }]
    }
    { maxTokens := some 123
      maxTokensField := "max_tokens"
      reasoning := some .high
      reasoningEffortValue := some "high"
      supportsReasoningEffort := false
      cacheRetention := some .long
      supportsLongCacheRetention := false
      sessionId := some "ant-ling-session"
    }
  assertTrue (LeanAgent.Json.optVal? payload "max_tokens" == some (LeanAgent.Json.nat 123))
    "expected Ant Ling max_tokens field"
  assertTrue ((LeanAgent.Json.optVal? payload "store").isNone)
    "expected Ant Ling to omit store"
  assertTrue ((LeanAgent.Json.optVal? payload "prompt_cache_key").isNone)
    "expected Ant Ling to omit prompt cache key"
  match jsonObjectField? payload "reasoning" with
  | some reasoning =>
      assertTrue (jsonStringField? reasoning "effort" == some "high")
        "expected Ant Ling reasoning object"
      assertTrue ((LeanAgent.Json.optVal? payload "reasoning_effort").isNone)
        "expected Ant Ling to omit top-level reasoning_effort"
  | none => fail "expected Ant Ling reasoning object"

def testOpenAICompletionsContextOmitsAntLingReasoningWhenSuppressed : IO Unit := do
  let ringPayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.antLingProviderId
      id := "Ring-2.6-1T"
      reasoning := true
      supportsStore := false
      supportsDeveloperRole := false
      thinkingFormat := some "ant-ling"
      thinkingLevelMap :=
        #[ { level := .off, mapped := none }
         , { level := .level .minimal, mapped := none }
         , { level := .level .low, mapped := none }
         , { level := .level .medium, mapped := none }
         , { level := .level .high, mapped := some "high" }
         ]
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { reasoning := some .medium
      supportsReasoningEffort := false
    }
  let lingPayload := LeanAgent.AI.Api.OpenAICompletions.requestToStreamingJsonWithContextOptions
    { openAICompletionsContextModel with
      provider := LeanAgent.Models.antLingProviderId
      id := "Ling-2.6-flash"
      reasoning := false
      supportsStore := false
      supportsDeveloperRole := false
      thinkingFormat := some "ant-ling"
    }
    { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
    { reasoning := some .high
      supportsReasoningEffort := false
    }
  assertTrue ((LeanAgent.Json.optVal? ringPayload "reasoning").isNone)
    "expected suppressed Ant Ling level to omit reasoning payload"
  assertTrue ((LeanAgent.Json.optVal? lingPayload "reasoning").isNone)
    "expected non-reasoning Ant Ling model to omit reasoning payload"

def testAnthropicMessagesRequestPayload : IO Unit := do
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall
            { id := "call/read|item"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
            }
         ]
      api := "openai-responses"
      provider := "openai"
      model := "gpt-5"
      stopReason := .toolUse
      timestamp := 2
    }
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "Be precise."
      messages :=
        #[ .user
            { content :=
                #[ LeanAgent.AI.text "hello"
                 , LeanAgent.AI.image "aGVsbG8=" "image/png"
                 ]
              timestamp := 1
            }
         , .assistant assistant
         , .toolResult
            { toolCallId := "call/read|item"
              toolName := "read"
              content := #[LeanAgent.AI.text "file contents"]
              isError := false
              timestamp := 3
            }
         ]
      tools :=
        #[ { name := "read"
             description := "Read a file"
             parameters :=
              LeanAgent.Json.obj
                [ ("type", LeanAgent.Json.str "object")
                , ("properties", LeanAgent.Json.obj [("path", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string")])])
                , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "path"])
                ]
           }
         ]
    }
  let payload := LeanAgent.AI.Api.AnthropicMessages.requestToJsonWithOptions
    anthropicModelRef
    #["text", "image"]
    64000
    true
    context
    { maxTokens := some 123
      temperature := some 0.2
      thinkingEnabled := some true
      thinkingBudgetTokens := some 2048
      cacheRetention := some .long
      toolChoice := some .any
      metadata := some (LeanAgent.Json.obj [("user_id", LeanAgent.Json.str "user-1")])
    }
  assertTrue (jsonStringField? payload "model" == some LeanAgent.Models.anthropicDefaultModel)
    "expected Anthropic model id"
  assertTrue (LeanAgent.Json.optVal? payload "stream" == some (LeanAgent.Json.bool false))
    "expected non-stream Anthropic payload"
  assertTrue (LeanAgent.Json.optVal? payload "max_tokens" == some (LeanAgent.Json.nat 123))
    "expected Anthropic max tokens"
  assertTrue (LeanAgent.Json.optVal? payload "temperature" == none)
    "expected Anthropic temperature to be omitted while thinking is enabled"
  match jsonArrayField? payload "system" with
  | some system =>
      match system[0]? with
      | some block =>
          assertTrue (jsonStringField? block "text" == some "Be precise.") "expected system text"
          match jsonObjectField? block "cache_control" with
          | some cacheControl =>
              assertTrue (jsonStringField? cacheControl "type" == some "ephemeral")
                "expected Anthropic system cache control"
              assertTrue (jsonStringField? cacheControl "ttl" == some "1h")
                "expected Anthropic long system cache ttl"
          | none => fail "expected Anthropic system cache_control"
      | none => fail "expected system block"
  | none => fail "expected Anthropic system array"
  match LeanAgent.Json.optVal? payload "thinking" with
  | some thinking =>
      assertTrue (jsonStringField? thinking "type" == some "enabled") "expected enabled thinking"
      assertTrue (LeanAgent.Json.optVal? thinking "budget_tokens" == some (LeanAgent.Json.nat 2048))
        "expected thinking budget"
  | none => fail "expected thinking object"
  assertTrue (LeanAgent.Json.optVal? payload "output_config" == none)
    "expected budget-based Anthropic thinking to omit output_config"
  match jsonArrayField? payload "messages" with
  | some messages =>
      assertTrue (messages.size == 3) "expected user, assistant, tool-result messages"
      match messages[1]? with
      | some assistantMessage =>
          match jsonArrayField? assistantMessage "content" with
          | some content =>
              match content[0]? with
              | some toolUse =>
                  assertTrue (jsonStringField? toolUse "type" == some "tool_use") "expected Anthropic tool_use"
                  assertTrue (jsonStringField? toolUse "id" == some "call_read_item")
                    "expected normalized tool id"
              | none => fail "expected tool_use content"
          | none => fail "expected assistant content"
      | none => fail "expected assistant message"
      match messages[2]? with
      | some toolMessage =>
          match jsonArrayField? toolMessage "content" with
          | some content =>
              match content[0]? with
              | some toolResult =>
                  assertTrue (jsonStringField? toolResult "type" == some "tool_result")
                    "expected Anthropic tool_result"
                  assertTrue (jsonStringField? toolResult "tool_use_id" == some "call_read_item")
                    "expected normalized tool result id"
                  match jsonObjectField? toolResult "cache_control" with
                  | some cacheControl =>
                      assertTrue (jsonStringField? cacheControl "ttl" == some "1h")
                        "expected Anthropic last user block cache ttl"
                  | none => fail "expected Anthropic last user block cache_control"
              | none => fail "expected tool_result content"
          | none => fail "expected tool result content array"
      | none => fail "expected tool result message"
  | none => fail "expected Anthropic messages array"
  match jsonArrayField? payload "tools" with
  | some tools =>
      match tools[0]? with
      | some tool =>
          assertTrue (jsonStringField? tool "name" == some "read") "expected Anthropic tool"
          assertTrue
            (LeanAgent.Json.optVal? tool "eager_input_streaming" == some (LeanAgent.Json.bool true))
            "expected Anthropic tool eager input streaming"
          match jsonObjectField? tool "cache_control" with
          | some cacheControl =>
              assertTrue (jsonStringField? cacheControl "ttl" == some "1h")
                "expected Anthropic tool cache ttl"
          | none => fail "expected Anthropic tool cache_control"
      | none => fail "expected Anthropic tool"
  | none => fail "expected Anthropic tools"
  match LeanAgent.Json.optVal? payload "tool_choice" with
  | some toolChoice => assertTrue (jsonStringField? toolChoice "type" == some "any") "expected tool choice"
  | none => fail "expected Anthropic tool choice"
  match LeanAgent.Json.optVal? payload "metadata" with
  | some metadata => assertTrue (jsonStringField? metadata "user_id" == some "user-1") "expected metadata user_id"
  | none => fail "expected metadata"
  let noCachePayload := LeanAgent.AI.Api.AnthropicMessages.requestToJsonWithOptions
    anthropicModelRef
    #["text", "image"]
    64000
    true
    context
    { cacheRetention := some .none }
  match jsonArrayField? noCachePayload "system" with
  | some system =>
      match system[0]? with
      | some block =>
          assertTrue (jsonObjectField? block "cache_control" == none)
            "expected cacheRetention none to omit Anthropic system cache_control"
      | none => fail "expected no-cache system block"
  | none => fail "expected no-cache system array"

def testAnthropicMessagesCompatOptions : IO Unit := do
  let model : LeanAgent.Models.ModelInfo :=
    { LeanAgent.Models.anthropicSonnet45 with
      compat :=
        { forceAdaptiveThinking := true
          supportsTemperature := false
          sendSessionAffinityHeaders := true
        }
      thinkingLevelMap := #[{ level := .level .xhigh, mapped := some "max" }]
    }
  let options := LeanAgent.AI.Providers.Streams.anthropicMessagesOptionsFromSimple
    model
    {}
    { reasoning := some .xhigh, temperature := some 0.2 }
  assertTrue (options.thinkingEnabled == some true)
    "expected adaptive Anthropic thinking to be enabled"
  assertTrue (options.thinkingEffort == some "max")
    "expected adaptive Anthropic xhigh thinking effort mapping"
  assertTrue (options.thinkingBudgetTokens == none)
    "expected adaptive Anthropic thinking to omit budget tokens"
  assertTrue (!options.supportsTemperature)
    "expected Anthropic compat to disable temperature"
  assertTrue options.sendSessionAffinityHeaders
    "expected Anthropic session affinity compat to map into options"
  assertTrue options.forceAdaptiveThinking
    "expected Anthropic adaptive thinking compat to map into options"
  assertTrue options.interleavedThinking
    "expected Anthropic interleaved thinking beta to default on"
  let payload := LeanAgent.AI.Api.AnthropicMessages.requestToJsonWithOptions
    model.toModelRef
    model.input
    model.maxTokens
    model.reasoning
    {}
    options
  match LeanAgent.Json.optVal? payload "thinking" with
  | some thinking =>
      assertTrue (jsonStringField? thinking "type" == some "adaptive")
        "expected adaptive Anthropic thinking payload"
      assertTrue (jsonStringField? thinking "display" == some "summarized")
        "expected adaptive Anthropic thinking display"
      assertTrue (jsonStringField? thinking "effort" == none)
        "expected adaptive Anthropic effort outside thinking payload"
  | none => fail "expected adaptive Anthropic thinking"
  match jsonObjectField? payload "output_config" with
  | some outputConfig =>
      assertTrue (jsonStringField? outputConfig "effort" == some "max")
        "expected adaptive Anthropic output_config effort"
  | none => fail "expected adaptive Anthropic output_config"
  assertTrue (LeanAgent.Json.optVal? payload "temperature" == none)
    "expected disabled Anthropic temperature support to omit temperature"

def testAnthropicMessagesCompatPayloadOptions : IO Unit := do
  let readTool : LeanAgent.AI.Tool :=
    { name := "read"
      description := "Read a file"
      parameters :=
        LeanAgent.Json.obj
          [ ("type", LeanAgent.Json.str "object")
          , ("properties", LeanAgent.Json.obj [("path", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string")])])
          , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "path"])
          ]
    }
  let toolContext : LeanAgent.AI.Context :=
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      tools := #[readTool]
    }
  let noToolCompatPayload := LeanAgent.AI.Api.AnthropicMessages.requestToJsonWithOptions
    anthropicModelRef
    #["text"]
    64000
    false
    toolContext
    { cacheRetention := some .long
      supportsEagerToolInputStreaming := false
      supportsCacheControlOnTools := false
    }
  match jsonArrayField? noToolCompatPayload "tools" with
  | some tools =>
      match tools[0]? with
      | some tool =>
          assertTrue (LeanAgent.Json.optVal? tool "eager_input_streaming" == none)
            "expected compat to omit Anthropic eager input streaming"
          assertTrue (LeanAgent.Json.optVal? tool "cache_control" == none)
            "expected compat to omit Anthropic tool cache_control"
      | none => fail "expected compat tool"
  | none => fail "expected compat tools"
  let thinkingAssistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .thinking
            { thinking := "draft reasoning"
              thinkingSignature := none
            }
         ]
      api := LeanAgent.AI.Api.AnthropicMessages.api
      provider := LeanAgent.Models.anthropicProviderId
      model := LeanAgent.Models.anthropicDefaultModel
      stopReason := .stop
      timestamp := 2
    }
  let thinkingContext : LeanAgent.AI.Context :=
    { messages :=
        #[ .user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }
         , .assistant thinkingAssistant
         ]
    }
  let defaultPayload := LeanAgent.AI.Api.AnthropicMessages.requestToJsonWithOptions
    anthropicModelRef
    #["text"]
    64000
    true
    thinkingContext
  match jsonArrayField? defaultPayload "messages" with
  | some messages =>
      match messages[1]? with
      | some assistantMessage =>
          match jsonArrayField? assistantMessage "content" with
          | some content =>
              match content[0]? with
              | some block =>
                  assertTrue (jsonStringField? block "type" == some "text")
                    "expected missing Anthropic thinking signature to downgrade to text"
                  assertTrue (jsonStringField? block "text" == some "draft reasoning")
                    "expected downgraded Anthropic thinking text"
              | none => fail "expected default thinking block"
          | none => fail "expected default assistant content"
      | none => fail "expected default assistant message"
  | none => fail "expected default messages"
  let allowPayload := LeanAgent.AI.Api.AnthropicMessages.requestToJsonWithOptions
    anthropicModelRef
    #["text"]
    64000
    true
    thinkingContext
    { allowEmptySignature := true }
  match jsonArrayField? allowPayload "messages" with
  | some messages =>
      match messages[1]? with
      | some assistantMessage =>
          match jsonArrayField? assistantMessage "content" with
          | some content =>
              match content[0]? with
              | some block =>
                  assertTrue (jsonStringField? block "type" == some "thinking")
                    "expected compat to preserve Anthropic thinking block"
                  assertTrue (jsonStringField? block "signature" == some "")
                    "expected compat to replay empty Anthropic signature"
              | none => fail "expected allow-empty thinking block"
          | none => fail "expected allow-empty assistant content"
      | none => fail "expected allow-empty assistant message"
  | none => fail "expected allow-empty messages"

def testAnthropicMessagesHeaders : IO Unit := do
  let readTool : LeanAgent.AI.Tool :=
    { name := "read"
      description := "Read a file"
      parameters :=
        LeanAgent.Json.obj
          [ ("type", LeanAgent.Json.str "object")
          , ("properties", LeanAgent.Json.obj [])
          , ("required", LeanAgent.Json.arr #[])
          ]
    }
  let headers := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key"
      headers := #[("X-Custom", "custom")]
    }
    { headers := #[("x-api-key", some "override-key")] }
  assertTrue (headerValueCaseInsensitive? headers "x-api-key" == some "override-key")
    "expected request header to override Anthropic key header"
  assertTrue (headerValueCaseInsensitive? headers "anthropic-version" == some LeanAgent.AI.Api.AnthropicMessages.anthropicVersion)
    "expected Anthropic version header"
  assertTrue (headerValueCaseInsensitive? headers "X-Custom" == some "custom")
    "expected custom config header"
  assertTrue
    (headerValueCaseInsensitive? headers "anthropic-beta" ==
      some LeanAgent.AI.Api.AnthropicMessages.interleavedThinkingBeta)
    "expected default Anthropic interleaved thinking beta header"
  let noInterleavedHeaders := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key" }
    { interleavedThinking := false }
  assertTrue (headerValueCaseInsensitive? noInterleavedHeaders "anthropic-beta" == none)
    "expected disabled interleaved thinking to omit Anthropic beta header"
  let adaptiveThinkingHeaders := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key" }
    { forceAdaptiveThinking := true }
  assertTrue (headerValueCaseInsensitive? adaptiveThinkingHeaders "anthropic-beta" == none)
    "expected adaptive thinking compat to omit interleaved thinking beta header"
  let headerAuthOnly := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "" }
    { headers := #[("Authorization", some "Bearer external")] }
  assertTrue (headerValueCaseInsensitive? headerAuthOnly "x-api-key" == none)
    "expected empty Anthropic api key to omit x-api-key"
  assertTrue (headerValueCaseInsensitive? headerAuthOnly "authorization" == some "Bearer external")
    "expected caller-owned authorization header"
  let oauthHeaders := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "sk-ant-oat-token" }
    {}
  assertTrue (headerValueCaseInsensitive? oauthHeaders "authorization" == some "Bearer sk-ant-oat-token")
    "expected OAuth token bearer auth"
  assertTrue (headerValueCaseInsensitive? oauthHeaders "x-api-key" == none)
    "expected OAuth token not to use x-api-key"
  assertTrue
    (headerValueCaseInsensitive? oauthHeaders "anthropic-beta" ==
      some ("claude-code-20250219,oauth-2025-04-20," ++
        LeanAgent.AI.Api.AnthropicMessages.interleavedThinkingBeta))
    "expected OAuth beta headers"
  let fineGrainedHeaders := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key" }
    { supportsEagerToolInputStreaming := false
      forceAdaptiveThinking := true
    }
    #[readTool]
  assertTrue
    (headerValueCaseInsensitive? fineGrainedHeaders "anthropic-beta" ==
      some LeanAgent.AI.Api.AnthropicMessages.fineGrainedToolStreamingBeta)
    "expected Anthropic fine-grained tool streaming beta header"
  let combinedBetaHeaders := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key" }
    { supportsEagerToolInputStreaming := false }
    #[readTool]
  assertTrue
    (headerValueCaseInsensitive? combinedBetaHeaders "anthropic-beta" ==
      some (LeanAgent.AI.Api.AnthropicMessages.fineGrainedToolStreamingBeta ++ "," ++
        LeanAgent.AI.Api.AnthropicMessages.interleavedThinkingBeta))
    "expected Anthropic beta header to combine fine-grained and interleaved features"
  let noToolFineGrainedHeaders := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key" }
    { supportsEagerToolInputStreaming := false
      interleavedThinking := false
    }
  assertTrue (headerValueCaseInsensitive? noToolFineGrainedHeaders "anthropic-beta" == none)
    "expected no Anthropic fine-grained beta header without tools"
  let oauthFineGrainedHeaders := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "sk-ant-oat-token" }
    { supportsEagerToolInputStreaming := false
      forceAdaptiveThinking := true
    }
    #[readTool]
  assertTrue
    (headerValueCaseInsensitive? oauthFineGrainedHeaders "anthropic-beta" ==
      some ("claude-code-20250219,oauth-2025-04-20," ++
        LeanAgent.AI.Api.AnthropicMessages.fineGrainedToolStreamingBeta))
    "expected OAuth Anthropic beta header to include fine-grained tool streaming"
  let overriddenBetaHeaders := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key" }
    { supportsEagerToolInputStreaming := false
      headers := #[("anthropic-beta", some "caller-beta")]
    }
    #[readTool]
  assertTrue (headerValueCaseInsensitive? overriddenBetaHeaders "anthropic-beta" == some "caller-beta")
    "expected caller to override Anthropic beta header"
  let affinityHeaders := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key" }
    { sessionId := some "session-anthropic"
      sendSessionAffinityHeaders := true
    }
  assertTrue (headerValueCaseInsensitive? affinityHeaders "x-session-affinity" == some "session-anthropic")
    "expected Anthropic session affinity header"
  let overriddenAffinity := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key" }
    { sessionId := some "session-anthropic"
      sendSessionAffinityHeaders := true
      headers := #[("x-session-affinity", some "caller-session")]
    }
  assertTrue (headerValueCaseInsensitive? overriddenAffinity "x-session-affinity" == some "caller-session")
    "expected caller to override Anthropic session affinity header"
  let disabledAffinity := LeanAgent.AI.Api.AnthropicMessages.requestHeaders
    { apiKey := "anthropic-key" }
    { sessionId := some "session-anthropic"
      cacheRetention := some .none
      sendSessionAffinityHeaders := true
    }
  assertTrue (headerValueCaseInsensitive? disabledAffinity "x-session-affinity" == none)
    "expected cacheRetention none to omit Anthropic session affinity header"

def testAnthropicMessagesParsesResponse : IO Unit := do
  let raw :=
    "{ \"id\":\"msg_1\", \"model\":\"claude-sonnet-4-5\", \"stop_reason\":\"tool_use\", \"content\":[" ++
    "{\"type\":\"thinking\",\"thinking\":\"think\",\"signature\":\"sig\"}," ++
    "{\"type\":\"text\",\"text\":\"hello\"}," ++
    "{\"type\":\"tool_use\",\"id\":\"tool_1\",\"name\":\"read\",\"input\":{\"path\":\"README.md\"}}" ++
    "], \"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"cache_read_input_tokens\":2,\"cache_creation_input_tokens\":3,\"cache_creation\":{\"ephemeral_1h_input_tokens\":1},\"output_tokens_details\":{\"thinking_tokens\":4}} }"
  match LeanAgent.AI.Api.AnthropicMessages.parseResponse
      LeanAgent.AI.Api.AnthropicMessages.api
      LeanAgent.Models.anthropicProviderId
      LeanAgent.Models.anthropicDefaultModel
      7
      raw with
  | .ok response =>
      assertTrue (response.responseId == some "msg_1") "expected Anthropic response id"
      assertTrue (response.stopReason == .toolUse) "expected Anthropic tool-use stop"
      assertTrue (response.usage.input == 10) "expected Anthropic input tokens"
      assertTrue (response.usage.output == 5) "expected Anthropic output tokens"
      assertTrue (response.usage.cacheRead == 2) "expected Anthropic cache read"
      assertTrue (response.usage.cacheWrite == 3) "expected Anthropic cache write"
      assertTrue (response.usage.cacheWrite1h == some 1) "expected Anthropic 1h cache write"
      assertTrue (response.usage.reasoning == some 4) "expected Anthropic thinking tokens"
      assertTrue (response.usage.totalTokens == 20) "expected Anthropic total tokens"
      assertTrue
        (response.content.any fun
          | .thinking thinking => thinking.thinking == "think" && thinking.thinkingSignature == some "sig"
          | _ => false)
        "expected Anthropic thinking block"
      assertTrue
        (response.content.any fun
          | .text text => text.text == "hello"
          | _ => false)
        "expected Anthropic text block"
      match LeanAgent.AI.contentToolCalls response.content |>.toList with
      | [call] =>
          assertTrue (call.id == "tool_1") "expected Anthropic tool id"
          assertTrue (call.name == "read") "expected Anthropic tool name"
          assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected Anthropic tool input"
      | _ => fail "expected one Anthropic tool call"
  | .error err => fail s!"expected Anthropic parse success: {err}"

def testAnthropicMessagesParsesStreamingEvents : IO Unit := do
  let raw := String.intercalate "\n\n"
    [ "event: message_start\n" ++
      "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_stream\",\"model\":\"claude-sonnet-4-5\",\"usage\":{\"input_tokens\":3,\"output_tokens\":0,\"cache_read_input_tokens\":1}}}"
    , "event: content_block_start\n" ++
      "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\",\"signature\":\"\"}}"
    , "event: content_block_delta\n" ++
      "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"plan\"}}"
    , "event: content_block_delta\n" ++
      "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"signature_delta\",\"signature\":\"sig\"}}"
    , "event: content_block_stop\n" ++
      "data: {\"type\":\"content_block_stop\",\"index\":0}"
    , "event: content_block_start\n" ++
      "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}"
    , "event: content_block_delta\n" ++
      "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"text_delta\",\"text\":\"hel\"}}"
    , "event: content_block_delta\n" ++
      "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}"
    , "event: content_block_stop\n" ++
      "data: {\"type\":\"content_block_stop\",\"index\":1}"
    , "event: content_block_start\n" ++
      "data: {\"type\":\"content_block_start\",\"index\":2,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tool_1\",\"name\":\"read\",\"input\":{}}}"
    , "event: content_block_delta\n" ++
      "data: {\"type\":\"content_block_delta\",\"index\":2,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"path\\\":\\\"README.md\\\"}\"}}"
    , "event: content_block_stop\n" ++
      "data: {\"type\":\"content_block_stop\",\"index\":2}"
    , "event: message_delta\n" ++
      "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":5,\"cache_creation_input_tokens\":2,\"output_tokens_details\":{\"thinking_tokens\":1}}}"
    , "event: message_stop\n" ++
      "data: {\"type\":\"message_stop\"}"
    , ""
    ]
  match LeanAgent.AI.Api.AnthropicMessages.parseStreamingEventStream
      LeanAgent.AI.Api.AnthropicMessages.api
      LeanAgent.Models.anthropicProviderId
      LeanAgent.Models.anthropicDefaultModel
      9
      raw with
  | .ok stream =>
      assertTrue stream.isComplete "expected completed Anthropic stream"
      assertTrue (stream.result.responseId == some "msg_stream") "expected streamed Anthropic response id"
      assertTrue (stream.result.responseModel == none) "expected same response model to be omitted"
      assertTrue (stream.result.stopReason == .toolUse) "expected streamed tool-use stop"
      assertTrue (stream.result.usage.input == 3) "expected streamed input tokens"
      assertTrue (stream.result.usage.output == 5) "expected streamed output tokens"
      assertTrue (stream.result.usage.cacheRead == 1) "expected streamed cache read"
      assertTrue (stream.result.usage.cacheWrite == 2) "expected streamed cache write"
      assertTrue (stream.result.usage.reasoning == some 1) "expected streamed thinking tokens"
      assertTrue (stream.result.usage.totalTokens == 11) "expected streamed total tokens"
      assertTrue
        (stream.result.content.any fun
          | .thinking thinking => thinking.thinking == "plan" && thinking.thinkingSignature == some "sig"
          | _ => false)
        "expected streamed thinking block"
      assertTrue
        (LeanAgent.AI.contentPlainText stream.result.content == "plan\nhello")
        "expected streamed text content"
      match LeanAgent.AI.contentToolCalls stream.result.content |>.toList with
      | [call] =>
          assertTrue (call.id == "tool_1") "expected streamed tool id"
          assertTrue (call.name == "read") "expected streamed tool name"
          assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected streamed tool arguments"
      | _ => fail "expected one streamed tool call"
      assertTrue
        (stream.events.any fun
          | .thinkingDelta _ "plan" _ => true
          | _ => false)
        "expected thinking delta event"
      assertTrue
        (stream.events.any fun
          | .textDelta _ "hel" _ => true
          | _ => false)
        "expected text delta event"
      assertTrue
        (stream.events.any fun
          | .toolCallDelta _ "{\"path\":\"README.md\"}" _ => true
          | _ => false)
        "expected tool-call delta event"
  | .error err => fail s!"expected Anthropic streaming parse success: {err}"

def testAnthropicMessagesStreamingRequiresMessageStop : IO Unit := do
  let raw := String.intercalate "\n\n"
    [ "event: message_start\n" ++
      "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_stream\",\"model\":\"claude-sonnet-4-5\",\"usage\":{\"input_tokens\":1}}}"
    , "event: content_block_start\n" ++
      "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}"
    , "event: content_block_delta\n" ++
      "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"partial\"}}"
    , ""
    ]
  match LeanAgent.AI.Api.AnthropicMessages.parseStreamingEventStream
      LeanAgent.AI.Api.AnthropicMessages.api
      LeanAgent.Models.anthropicProviderId
      LeanAgent.Models.anthropicDefaultModel
      9
      raw with
  | .ok _ => fail "expected Anthropic streaming parser to reject missing message_stop"
  | .error err =>
      assertTrue (err.contains "message_stop") "expected missing message_stop error"

def testGoogleGenerativeAIRequestPayload : IO Unit := do
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall
            { id := "call/read|item"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
            }
         ]
      api := LeanAgent.AI.Api.GoogleGenerativeAI.api
      provider := LeanAgent.Models.googleProviderId
      model := LeanAgent.Models.googleDefaultModel
      stopReason := .toolUse
      timestamp := 2
    }
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "Be precise."
      messages :=
        #[ .user
            { content :=
                #[ LeanAgent.AI.text "hello"
                 , LeanAgent.AI.image "aGVsbG8=" "image/png"
                 ]
              timestamp := 1
            }
         , .assistant assistant
         , .toolResult
            { toolCallId := "call/read|item"
              toolName := "read"
              content := #[LeanAgent.AI.text "file contents"]
              isError := false
              timestamp := 3
            }
         ]
      tools :=
        #[ { name := "read"
             description := "Read a file"
             parameters :=
              LeanAgent.Json.obj
                [ ("type", LeanAgent.Json.str "object")
                , ("properties", LeanAgent.Json.obj [("path", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string")])])
                , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "path"])
                ]
           }
         ]
    }
  let payload := LeanAgent.AI.Api.GoogleGenerativeAI.requestToJsonWithOptions
    googleModelRef
    #["text", "image"]
    true
    context
    { maxTokens := some 123
      temperature := some 0.2
      thinkingEnabled := some true
      thinkingBudgetTokens := some 2048
      toolChoice := some .any
    }
  match LeanAgent.Json.optVal? payload "systemInstruction" with
  | some system =>
      match jsonArrayField? system "parts" with
      | some parts =>
          match parts[0]? with
          | some part => assertTrue (jsonStringField? part "text" == some "Be precise.") "expected Google system text"
          | none => fail "expected Google system part"
      | none => fail "expected Google system parts"
  | none => fail "expected Google systemInstruction"
  match LeanAgent.Json.optVal? payload "generationConfig" with
  | some config =>
      assertTrue (LeanAgent.Json.optVal? config "maxOutputTokens" == some (LeanAgent.Json.nat 123))
        "expected Google max output tokens"
      match LeanAgent.Json.optVal? config "thinkingConfig" with
      | some thinking =>
          assertTrue (LeanAgent.Json.optVal? thinking "includeThoughts" == some (Lean.Json.bool true))
            "expected Google includeThoughts"
          assertTrue (LeanAgent.Json.optVal? thinking "thinkingBudget" == some (LeanAgent.Json.nat 2048))
            "expected Google thinking budget"
      | none => fail "expected Google thinkingConfig"
  | none => fail "expected Google generationConfig"
  match jsonArrayField? payload "contents" with
  | some contents =>
      assertTrue (contents.size == 3) "expected Google user, model, function response contents"
      match contents[0]? with
      | some userMessage =>
          assertTrue (jsonStringField? userMessage "role" == some "user") "expected Google user role"
          match jsonArrayField? userMessage "parts" with
          | some parts =>
              match parts[0]?, parts[1]? with
              | some textPart, some imagePart =>
                  assertTrue (jsonStringField? textPart "text" == some "hello") "expected Google user text"
                  assertTrue (LeanAgent.Json.optVal? imagePart "inlineData" |>.isSome) "expected Google inline data"
              | _, _ => fail "expected Google text and image parts"
          | none => fail "expected Google user parts"
      | none => fail "expected Google user content"
      match contents[1]? with
      | some modelMessage =>
          assertTrue (jsonStringField? modelMessage "role" == some "model") "expected Google model role"
          match jsonArrayField? modelMessage "parts" with
          | some parts =>
              match parts[0]? with
              | some part =>
                  match LeanAgent.Json.optVal? part "functionCall" with
                  | some functionCall =>
                      assertTrue (jsonStringField? functionCall "name" == some "read")
                        "expected Google functionCall name"
                      assertTrue (jsonStringField? functionCall "id" == none)
                        "expected Gemini functionCall id to be omitted"
                  | none => fail "expected Google functionCall"
              | none => fail "expected Google model part"
          | none => fail "expected Google model parts"
      | none => fail "expected Google model content"
      match contents[2]? with
      | some toolMessage =>
          match jsonArrayField? toolMessage "parts" with
          | some parts =>
              match parts[0]? with
              | some part =>
                  match LeanAgent.Json.optVal? part "functionResponse" with
                  | some response =>
                      assertTrue (jsonStringField? response "name" == some "read")
                        "expected Google functionResponse name"
                      assertTrue (jsonStringField? response "id" == none)
                        "expected Gemini functionResponse id to be omitted"
                  | none => fail "expected Google functionResponse"
              | none => fail "expected Google tool part"
          | none => fail "expected Google tool parts"
      | none => fail "expected Google tool content"
  | none => fail "expected Google contents"
  match jsonArrayField? payload "tools" with
  | some tools =>
      match tools[0]? with
      | some group =>
          match jsonArrayField? group "functionDeclarations" with
          | some declarations =>
              match declarations[0]? with
              | some tool => assertTrue (jsonStringField? tool "name" == some "read") "expected Google tool name"
              | none => fail "expected Google function declaration"
          | none => fail "expected Google function declarations"
      | none => fail "expected Google tool group"
  | none => fail "expected Google tools"
  match LeanAgent.Json.optVal? payload "toolConfig" with
  | some toolConfig =>
      match LeanAgent.Json.optVal? toolConfig "functionCallingConfig" with
      | some functionCallingConfig =>
          assertTrue (jsonStringField? functionCallingConfig "mode" == some "ANY")
            "expected Google tool choice mode"
      | none => fail "expected Google functionCallingConfig"
  | none => fail "expected Google toolConfig"

def testGoogleSharedConvertToolsSanitizesOpenApiParameters : IO Unit := do
  let parameters := LeanAgent.Json.obj
    [ ("$schema", LeanAgent.Json.str "http://json-schema.org/draft-07/schema#")
    , ("$id", LeanAgent.Json.str "urn:bash-tool")
    , ("$comment", LeanAgent.Json.str "internal note")
    , ("$defs", LeanAgent.Json.obj [("commandDef", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string")])])
    , ("definitions", LeanAgent.Json.obj [("legacyDef", LeanAgent.Json.obj [("type", LeanAgent.Json.str "number")])])
    , ("type", LeanAgent.Json.str "object")
    , ("properties", LeanAgent.Json.obj
        [ ("command", LeanAgent.Json.obj
            [ ("$schema", LeanAgent.Json.str "http://json-schema.org/draft-07/schema#")
            , ("$id", LeanAgent.Json.str "urn:nested")
            , ("$ref", LeanAgent.Json.str "#/$defs/commandDef")
            , ("type", LeanAgent.Json.str "string")
            , ("examples", LeanAgent.Json.arr #[LeanAgent.Json.str "echo hi"])
            ])
        ])
    , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "command"])
    ]
  let tool : LeanAgent.AI.Tool :=
    { name := "bash"
      description := "Run a command"
      parameters := parameters
    }
  match LeanAgent.AI.Api.GoogleShared.convertTools #[tool] true with
  | some groups =>
      match groups[0]? with
      | some group =>
          match jsonArrayField? group "functionDeclarations" with
          | some declarations =>
              match declarations[0]? with
              | some declaration =>
                  assertTrue (LeanAgent.Json.optVal? declaration "parametersJsonSchema" == none)
                    "expected legacy parameters field only"
                  match LeanAgent.Json.optVal? declaration "parameters" with
                  | some sanitized =>
                      assertTrue (LeanAgent.Json.optVal? sanitized "$schema" == none)
                        "expected top-level $schema stripped"
                      assertTrue (LeanAgent.Json.optVal? sanitized "$id" == none)
                        "expected top-level $id stripped"
                      assertTrue (LeanAgent.Json.optVal? sanitized "$comment" == none)
                        "expected top-level $comment stripped"
                      assertTrue (LeanAgent.Json.optVal? sanitized "$defs" == none)
                        "expected top-level $defs stripped"
                      assertTrue (LeanAgent.Json.optVal? sanitized "definitions" == none)
                        "expected legacy definitions stripped"
                      assertTrue (LeanAgent.Json.optVal? sanitized "required" == some (LeanAgent.Json.arr #[LeanAgent.Json.str "command"]))
                        "expected required preserved"
                      match LeanAgent.Json.optVal? sanitized "properties" with
                      | some properties =>
                          match LeanAgent.Json.optVal? properties "command" with
                          | some command =>
                              assertTrue (LeanAgent.Json.optVal? command "$schema" == none)
                                "expected nested $schema stripped"
                              assertTrue (LeanAgent.Json.optVal? command "$id" == none)
                                "expected nested $id stripped"
                              assertTrue (LeanAgent.Json.optVal? command "$ref" == some (LeanAgent.Json.str "#/$defs/commandDef"))
                                "expected nested $ref preserved"
                              assertTrue (LeanAgent.Json.optVal? command "examples" |>.isSome)
                                "expected non-meta examples keyword preserved"
                          | none => fail "expected command property"
                      | _ => fail "expected properties object"
                  | none => fail "expected sanitized parameters"
              | none => fail "expected function declaration"
          | none => fail "expected function declarations"
      | none => fail "expected Google tool group"
  | none => fail "expected converted tools"

  match LeanAgent.AI.Api.GoogleShared.convertTools #[tool] false with
  | some groups =>
      match groups[0]? with
      | some group =>
          match jsonArrayField? group "functionDeclarations" with
          | some declarations =>
              match declarations[0]? with
              | some declaration =>
                  assertTrue (LeanAgent.Json.optVal? declaration "parameters" == none)
                    "expected default parametersJsonSchema field only"
                  assertTrue (LeanAgent.Json.optVal? declaration "parametersJsonSchema" == some parameters)
                    "expected full JSON Schema preserved by default"
              | none => fail "expected default function declaration"
          | none => fail "expected default function declarations"
      | none => fail "expected default Google tool group"
  | none => fail "expected default converted tools"

def makeGoogleSharedModelRef (api provider modelId baseUrl : String) : LeanAgent.AI.ModelRef :=
  { id := modelId
    api := api
    provider := provider
    baseUrl := some baseUrl
  }

def makeGoogleSharedImageRoutingContext
    (assistantApi assistantProvider assistantModel : String) : LeanAgent.AI.Context :=
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .toolCall { id := "call_a", name := "read", arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "a.txt")] }
         , .toolCall { id := "call_img", name := "read", arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "image.png")] }
         , .toolCall { id := "call_b", name := "read", arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "b.txt")] }
         ]
      api := assistantApi
      provider := assistantProvider
      model := assistantModel
      stopReason := .toolUse
      timestamp := 2
    }
  { messages :=
      #[ .user { content := #[LeanAgent.AI.text "read the files"], timestamp := 1 }
       , .assistant assistant
       , .toolResult
          { toolCallId := "call_a"
            toolName := "read"
            content := #[LeanAgent.AI.text "alpha text"]
            isError := false
            timestamp := 3
          }
       , .toolResult
          { toolCallId := "call_img"
            toolName := "read"
            content := #[LeanAgent.AI.image "abc" "image/png"]
            isError := false
            timestamp := 4
          }
       , .toolResult
          { toolCallId := "call_b"
            toolName := "read"
            content := #[LeanAgent.AI.text "beta text"]
            isError := false
            timestamp := 5
          }
       ]
  }

def makeGoogleSharedToolCallContext
    (assistantApi assistantProvider assistantModel : String)
    (thoughtSignature : Option String := none) : LeanAgent.AI.Context :=
  let firstCall : LeanAgent.AI.ToolCall :=
    { id := "call_1"
      name := "bash"
      arguments := LeanAgent.Json.obj [("command", LeanAgent.Json.str "echo hi")]
      thoughtSignature := thoughtSignature
    }
  let secondCall : LeanAgent.AI.ToolCall :=
    { id := "call_2"
      name := "bash"
      arguments := LeanAgent.Json.obj [("command", LeanAgent.Json.str "ls -la")]
    }
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content := #[.toolCall firstCall, .toolCall secondCall]
      api := assistantApi
      provider := assistantProvider
      model := assistantModel
      stopReason := .toolUse
      timestamp := 2
    }
  { messages :=
      #[ .user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }
       , .assistant assistant
       ]
  }

def testGoogleSharedThinkingHelpers : IO Unit := do
  let withThought := LeanAgent.Json.obj
    [ ("thought", LeanAgent.Json.bool true)
    , ("thoughtSignature", LeanAgent.Json.str "opaque-signature")
    ]
  assertTrue (LeanAgent.AI.Api.GoogleShared.isThinkingPart withThought)
    "expected thought=true to mark Google thinking part"

  let signatureOnly := LeanAgent.Json.obj [("thoughtSignature", LeanAgent.Json.str "opaque-signature")]
  assertTrue (!LeanAgent.AI.Api.GoogleShared.isThinkingPart signatureOnly)
    "expected thoughtSignature alone not to mark thinking part"

  let first := LeanAgent.AI.Api.GoogleShared.retainThoughtSignature none (some "sig-1")
  assertTrue (first == some "sig-1") "expected first thought signature retained"
  let second := LeanAgent.AI.Api.GoogleShared.retainThoughtSignature first none
  assertTrue (second == some "sig-1") "expected missing delta to preserve signature"
  let third := LeanAgent.AI.Api.GoogleShared.retainThoughtSignature second (some "")
  assertTrue (third == some "sig-1") "expected empty delta to preserve signature"
  let updated := LeanAgent.AI.Api.GoogleShared.retainThoughtSignature third (some "sig-2")
  assertTrue (updated == some "sig-2") "expected non-empty delta to replace signature"

def testGoogleSharedImageToolResultRouting : IO Unit := do
  let gemini2Model :=
    makeGoogleSharedModelRef
      LeanAgent.AI.Api.GoogleGenerativeAI.api
      LeanAgent.Models.googleProviderId
      "gemini-2.5-flash"
      LeanAgent.Models.googleBaseUrl
  let gemini2Contents := LeanAgent.AI.Api.GoogleShared.convertMessages
    gemini2Model
    #["text", "image"]
    (makeGoogleSharedImageRoutingContext
      LeanAgent.AI.Api.GoogleGenerativeAI.api
      LeanAgent.Models.googleProviderId
      "gemini-2.5-flash")
  assertTrue (gemini2Contents.size == 5) "expected Gemini 2.x image tool results to create an extra user turn"
  match gemini2Contents[2]?, gemini2Contents[3]?, gemini2Contents[4]? with
  | some functionResponsesTurn, some imageTurn, some trailingFunctionResponse =>
      match jsonArrayField? functionResponsesTurn "parts" with
      | some parts =>
          assertTrue (parts.size == 2) "expected first Gemini 2.x tool-result turn to contain two function responses"
          assertTrue (parts.all fun part => (LeanAgent.Json.optVal? part "functionResponse").isSome)
            "expected only function responses before synthetic image turn"
      | none => fail "expected Gemini 2.x function-response parts"
      match jsonArrayField? imageTurn "parts" with
      | some parts =>
          match parts[0]?, parts[1]? with
          | some marker, some image =>
              assertTrue (jsonStringField? marker "text" == some "Tool result image:")
                "expected Gemini 2.x image marker text"
              assertTrue ((LeanAgent.Json.optVal? image "inlineData").isSome)
                "expected Gemini 2.x synthetic image inlineData"
          | _, _ => fail "expected Gemini 2.x image marker and inline image"
      | none => fail "expected Gemini 2.x synthetic image turn"
      match jsonArrayField? trailingFunctionResponse "parts" with
      | some parts =>
          assertTrue (parts.size == 1) "expected trailing Gemini 2.x tool result to stay separate"
          assertTrue ((parts[0]? >>= fun part => LeanAgent.Json.optVal? part "functionResponse").isSome)
            "expected trailing Gemini 2.x turn to contain a function response"
      | none => fail "expected trailing Gemini 2.x function response turn"
  | _, _, _ => fail "expected Gemini 2.x tool-result turns"

  let gemini3Model :=
    makeGoogleSharedModelRef
      LeanAgent.AI.Api.GoogleGenerativeAI.api
      LeanAgent.Models.googleProviderId
      "gemini-3-pro-preview"
      LeanAgent.Models.googleBaseUrl
  let gemini3Contents := LeanAgent.AI.Api.GoogleShared.convertMessages
    gemini3Model
    #["text", "image"]
    (makeGoogleSharedImageRoutingContext
      LeanAgent.AI.Api.GoogleGenerativeAI.api
      LeanAgent.Models.googleProviderId
      "gemini-3-pro-preview")
  assertTrue (gemini3Contents.size == 3) "expected Gemini 3 tool results to stay in one user turn"
  match gemini3Contents[2]? with
  | some toolResultTurn =>
      match jsonArrayField? toolResultTurn "parts" with
      | some parts =>
          assertTrue (parts.size == 3) "expected Gemini 3 tool-result turn to contain all three function responses"
          match parts[1]? >>= fun part => LeanAgent.Json.optVal? part "functionResponse" with
          | some functionResponse =>
              match jsonArrayField? functionResponse "parts" with
              | some nestedParts =>
                  assertTrue (nestedParts.size == 1) "expected nested Gemini 3 image response part"
                  assertTrue ((nestedParts[0]? >>= fun part => LeanAgent.Json.optVal? part "inlineData").isSome)
                    "expected Gemini 3 nested inlineData"
              | none => fail "expected nested Gemini 3 functionResponse parts"
          | none => fail "expected Gemini 3 image functionResponse"
      | none => fail "expected Gemini 3 tool-result parts"
  | none => fail "expected Gemini 3 tool-result turn"

def testGoogleSharedGemini3ToolCallThoughtSignatures : IO Unit := do
  let gemini3Google :=
    makeGoogleSharedModelRef
      LeanAgent.AI.Api.GoogleGenerativeAI.api
      LeanAgent.Models.googleProviderId
      "gemini-3-pro-preview"
      LeanAgent.Models.googleBaseUrl
  let unsignedGoogle := LeanAgent.AI.Api.GoogleShared.convertMessages
    gemini3Google
    #["text"]
    (makeGoogleSharedToolCallContext
      LeanAgent.AI.Api.GoogleGenerativeAI.api
      LeanAgent.Models.googleProviderId
      "other-model")
  match unsignedGoogle.find? fun content => jsonStringField? content "role" == some "model" with
  | some modelTurn =>
      match jsonArrayField? modelTurn "parts" with
      | some parts =>
          let functionCallParts := parts.filter fun part => (LeanAgent.Json.optVal? part "functionCall").isSome
          assertTrue (functionCallParts.size == 2) "expected Google Gemini 3 model turn to keep two function calls"
          assertTrue (functionCallParts.all fun part => LeanAgent.Json.optVal? part "thoughtSignature" == none)
            "expected unsigned Google Gemini 3 tool calls to omit thoughtSignature"
          assertTrue
            (!parts.any fun part =>
              match jsonStringField? part "text" with
              | some text => text.contains "Historical context"
              | none => false)
            "expected unsigned Google Gemini 3 tool calls not to synthesize historical context text"
      | none => fail "expected Google Gemini 3 model parts"
  | none => fail "expected Google Gemini 3 model turn"

  let gemini3Vertex :=
    makeGoogleSharedModelRef
      LeanAgent.AI.Api.GoogleVertex.api
      LeanAgent.Models.googleVertexProviderId
      "gemini-3-pro-preview"
      LeanAgent.Models.googleVertexBaseUrl
  let unsignedVertex := LeanAgent.AI.Api.GoogleShared.convertMessages
    gemini3Vertex
    #["text"]
    (makeGoogleSharedToolCallContext
      LeanAgent.AI.Api.GoogleVertex.api
      LeanAgent.Models.googleVertexProviderId
      "gemini-3-pro-preview")
  match unsignedVertex.find? fun content => jsonStringField? content "role" == some "model" with
  | some modelTurn =>
      match jsonArrayField? modelTurn "parts" with
      | some parts =>
          let functionCallParts := parts.filter fun part => (LeanAgent.Json.optVal? part "functionCall").isSome
          assertTrue (functionCallParts.size == 2) "expected Vertex Gemini 3 model turn to keep two function calls"
          assertTrue (functionCallParts.all fun part => LeanAgent.Json.optVal? part "thoughtSignature" == none)
            "expected unsigned Vertex Gemini 3 tool calls to omit thoughtSignature"
      | none => fail "expected Vertex Gemini 3 model parts"
  | none => fail "expected Vertex Gemini 3 model turn"

  let signedGoogle := LeanAgent.AI.Api.GoogleShared.convertMessages
    gemini3Google
    #["text"]
    (makeGoogleSharedToolCallContext
      LeanAgent.AI.Api.GoogleGenerativeAI.api
      LeanAgent.Models.googleProviderId
      "gemini-3-pro-preview"
      (some "AAAAAAAAAAAAAAAAAAAAAA=="))
  match signedGoogle.find? fun content => jsonStringField? content "role" == some "model" with
  | some modelTurn =>
      match jsonArrayField? modelTurn "parts" with
      | some parts =>
          let functionCallParts := parts.filter fun part => (LeanAgent.Json.optVal? part "functionCall").isSome
          assertTrue (functionCallParts.size == 2) "expected signed Google Gemini 3 model turn to keep two function calls"
          match functionCallParts[0]?, functionCallParts[1]? with
          | some first, some second =>
              assertTrue (jsonStringField? first "thoughtSignature" == some "AAAAAAAAAAAAAAAAAAAAAA==")
                "expected matching Google Gemini 3 tool call to preserve valid thoughtSignature"
              assertTrue (LeanAgent.Json.optVal? second "thoughtSignature" == none)
                "expected unsigned sibling tool call to omit thoughtSignature"
          | _, _ => fail "expected signed Google Gemini 3 function call parts"
      | none => fail "expected signed Google Gemini 3 model parts"
  | none => fail "expected signed Google Gemini 3 model turn"

def testGoogleGenerativeAIParsesResponse : IO Unit := do
  let raw :=
    "{ \"responseId\":\"resp_google\", \"modelVersion\":\"gemini-2.5-flash\", \"candidates\":[{" ++
    "\"content\":{\"parts\":[" ++
    "{\"thought\":true,\"text\":\"think\",\"thoughtSignature\":\"c2ln\"}," ++
    "{\"text\":\"hello\"}," ++
    "{\"functionCall\":{\"name\":\"read\",\"args\":{\"path\":\"README.md\"}}}" ++
    "]},\"finishReason\":\"STOP\"}]," ++
    "\"usageMetadata\":{\"promptTokenCount\":10,\"cachedContentTokenCount\":2,\"candidatesTokenCount\":5,\"thoughtsTokenCount\":3,\"totalTokenCount\":18}}"
  match LeanAgent.AI.Api.GoogleGenerativeAI.parseResponse
      LeanAgent.AI.Api.GoogleGenerativeAI.api
      LeanAgent.Models.googleProviderId
      LeanAgent.Models.googleDefaultModel
      7
      raw with
  | .ok response =>
      assertTrue (response.responseId == some "resp_google") "expected Google response id"
      assertTrue (response.responseModel == none) "expected same Google modelVersion to be omitted"
      assertTrue (response.stopReason == .toolUse) "expected Google tool-use stop"
      assertTrue (response.usage.input == 8) "expected Google cached input subtraction"
      assertTrue (response.usage.output == 8) "expected Google output plus thinking tokens"
      assertTrue (response.usage.cacheRead == 2) "expected Google cache read"
      assertTrue (response.usage.reasoning == some 3) "expected Google thinking tokens"
      assertTrue (response.usage.totalTokens == 18) "expected Google total tokens"
      assertTrue
        (response.content.any fun
          | .thinking thinking => thinking.thinking == "think" && thinking.thinkingSignature == some "c2ln"
          | _ => false)
        "expected Google thinking block"
      assertTrue
        (response.content.any fun
          | .text text => text.text == "hello"
          | _ => false)
        "expected Google text block"
      match LeanAgent.AI.contentToolCalls response.content |>.toList with
      | [call] =>
          assertTrue (call.id == "read_2") "expected generated Google tool id"
          assertTrue (call.name == "read") "expected Google tool name"
          assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected Google tool args"
      | _ => fail "expected one Google tool call"
  | .error err => fail s!"expected Google parse success: {err}"

def testGoogleGenerativeAIParsesStreamingEvents : IO Unit := do
  let raw := String.intercalate "\n\n"
    [ "data: {\"responseId\":\"resp_stream\",\"modelVersion\":\"gemini-2.5-flash\",\"candidates\":[{\"content\":{\"parts\":[{\"thought\":true,\"text\":\"plan\",\"thoughtSignature\":\"c2ln\"}]}}],\"usageMetadata\":{\"promptTokenCount\":4,\"cachedContentTokenCount\":1}}"
    , "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hel\"}]}}]}"
    , "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"lo\"}]}}]}"
    , "data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"read\",\"args\":{\"path\":\"README.md\"}}}],\"role\":\"model\"},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":4,\"cachedContentTokenCount\":1,\"candidatesTokenCount\":2,\"thoughtsTokenCount\":1,\"totalTokenCount\":7}}"
    , ""
    ]
  match LeanAgent.AI.Api.GoogleGenerativeAI.parseStreamingEventStream
      LeanAgent.AI.Api.GoogleGenerativeAI.api
      LeanAgent.Models.googleProviderId
      LeanAgent.Models.googleDefaultModel
      9
      raw with
  | .ok stream =>
      assertTrue stream.isComplete "expected completed Google stream"
      assertTrue (stream.result.responseId == some "resp_stream") "expected streamed Google response id"
      assertTrue (stream.result.responseModel == none) "expected same streamed model to be omitted"
      assertTrue (stream.result.stopReason == .toolUse) "expected streamed Google tool-use stop"
      assertTrue (stream.result.usage.input == 3) "expected streamed Google input"
      assertTrue (stream.result.usage.output == 3) "expected streamed Google output plus thinking"
      assertTrue (stream.result.usage.cacheRead == 1) "expected streamed Google cache read"
      assertTrue (stream.result.usage.reasoning == some 1) "expected streamed Google thinking tokens"
      assertTrue
        (LeanAgent.AI.contentPlainText stream.result.content == "plan\nhello")
        "expected streamed Google text content"
      match LeanAgent.AI.contentToolCalls stream.result.content |>.toList with
      | [call] =>
          assertTrue (call.id == "read_1") "expected streamed generated Google tool id"
          assertTrue (call.name == "read") "expected streamed Google tool name"
          assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected streamed Google tool arguments"
      | _ => fail "expected one streamed Google tool call"
      assertTrue
        (stream.events.any fun
          | .thinkingDelta _ "plan" _ => true
          | _ => false)
        "expected Google thinking delta"
      assertTrue
        (stream.events.any fun
          | .textDelta _ "hel" _ => true
          | _ => false)
        "expected Google text delta"
      assertTrue
        (stream.events.any fun
          | .toolCallEnd _ call _ => call.name == "read"
          | _ => false)
        "expected Google tool-call end"
  | .error err => fail s!"expected Google streaming parse success: {err}"

def testGoogleVertexUrlsAndHeaders : IO Unit := do
  let generatedUrl := LeanAgent.AI.Api.GoogleVertex.streamGenerateContentUrl
    LeanAgent.Models.googleVertexBaseUrl
    "project-1"
    "us-central1"
    LeanAgent.Models.googleVertexDefaultModel
  assertTrue
    (generatedUrl ==
      "https://us-central1-aiplatform.googleapis.com/v1/projects/project-1/locations/us-central1/publishers/google/models/gemini-2.5-flash:streamGenerateContent?alt=sse")
    "expected generated Vertex collection URL"
  let customVersioned := LeanAgent.AI.Api.GoogleVertex.generateContentUrl
    "https://proxy.example.com/v1/projects/project-1/locations/global"
    "ignored-project"
    "ignored-location"
    "gemini-3-flash-preview"
  assertTrue
    (customVersioned ==
      "https://proxy.example.com/v1/projects/project-1/locations/global/publishers/google/models/gemini-3-flash-preview:generateContent")
    "expected custom versioned Vertex collection URL"
  let apiKeyHeaders := LeanAgent.AI.Api.GoogleVertex.requestHeaders
    { apiKey := "AIzaSyExampleRealisticLookingApiKey123456" }
    { headers := #[("X-Trace", some "trace-vertex")] }
  assertTrue
    (headerValueCaseInsensitive? apiKeyHeaders "x-goog-api-key" ==
      some "AIzaSyExampleRealisticLookingApiKey123456")
    "expected Vertex API key header"
  assertTrue (headerValueCaseInsensitive? apiKeyHeaders "X-Trace" == some "trace-vertex")
    "expected Vertex custom header"
  let markerHeaders := LeanAgent.AI.Api.GoogleVertex.requestHeaders
    { apiKey := LeanAgent.AI.Api.GoogleVertex.vertexCredentialsMarker }
    { headers := #[("Authorization", some "Bearer adc-token")] }
  assertTrue (headerValueCaseInsensitive? markerHeaders "x-goog-api-key" == none)
    "expected Vertex ADC marker not to send API key header"
  assertTrue (headerValueCaseInsensitive? markerHeaders "Authorization" == some "Bearer adc-token")
    "expected caller-owned Vertex Authorization header"

def testGoogleVertexAuthResolution : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let auth := LeanAgent.AI.Providers.Catalog.authForProviderInfo LeanAgent.Models.googleVertexProviderInfo
  let keyCtx : LeanAgent.AI.Auth.AuthContext :=
    { env := fun name => pure (if name == LeanAgent.Models.googleVertexApiKeyEnv then some "vertex-key" else none)
      fileExists := fun _ => pure false
    }
  match ← LeanAgent.AI.Auth.resolveProviderAuth
      LeanAgent.Models.googleVertexProviderId
      auth
      store
      keyCtx with
  | some result =>
      assertTrue (result.auth.apiKey == some "vertex-key") "expected Vertex API key auth"
      assertTrue (result.source == some LeanAgent.Models.googleVertexApiKeyEnv)
        "expected Vertex API key env source"
  | none => fail "expected Vertex API key auth result"
  let adcCtx : LeanAgent.AI.Auth.AuthContext :=
    { env := fun name =>
        pure
          (if name == "GOOGLE_CLOUD_PROJECT" then
            some "project-1"
          else if name == "GOOGLE_CLOUD_LOCATION" then
            some "us-central1"
          else
            none)
      fileExists := fun path => pure (path == LeanAgent.AI.Providers.Catalog.googleVertexAdcPath)
    }
  match ← LeanAgent.AI.Auth.resolveProviderAuth
      LeanAgent.Models.googleVertexProviderId
      auth
      store
      adcCtx with
  | some result =>
      assertTrue
        (result.auth.apiKey == some LeanAgent.AI.Api.GoogleVertex.vertexCredentialsMarker)
        "expected Vertex ADC marker auth"
      assertTrue (result.source == some "gcloud application default credentials")
        "expected Vertex ADC source"
  | none => fail "expected Vertex ADC auth result"

def testMistralConversationsRequestPayloadAndHeaders : IO Unit := do
  let normalizedToolId := LeanAgent.AI.Api.MistralConversations.normalizeToolCallId "call/read|item"
  assertTrue (normalizedToolId.length == 9) "expected Mistral tool-call id to be 9 chars"
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .text { text := "prior answer" }
         , .toolCall
            { id := "call/read|item"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
            }
         ]
      api := LeanAgent.AI.Api.MistralConversations.api
      provider := LeanAgent.Models.mistralProviderId
      model := LeanAgent.Models.mistralDefaultModel
      stopReason := .toolUse
      timestamp := 2
    }
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "Be precise."
      messages :=
        #[ .user
            { content :=
                #[ LeanAgent.AI.text "hello"
                 , LeanAgent.AI.image "aGVsbG8=" "image/png"
                 ]
              timestamp := 1
            }
         , .assistant assistant
         , .toolResult
            { toolCallId := "call/read|item"
              toolName := "read"
              content := #[LeanAgent.AI.text "file contents"]
              isError := false
              timestamp := 3
            }
         ]
      tools :=
        #[ { name := "read"
             description := "Read a file"
             parameters :=
              LeanAgent.Json.obj
                [ ("type", LeanAgent.Json.str "object")
                , ("properties", LeanAgent.Json.obj [("path", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string")])])
                , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "path"])
                ]
           }
         ]
    }
  let payload := LeanAgent.AI.Api.MistralConversations.requestToJsonWithOptions
    mistralModelRef
    #["text", "image"]
    context
    { maxTokens := some 123
      temperature := some 0.2
      toolChoice := some (.function "read")
      promptMode := some "reasoning"
      reasoningEffort := some "high"
      sessionId := some "session-123"
    }
  assertTrue (jsonStringField? payload "model" == some LeanAgent.Models.mistralDefaultModel)
    "expected Mistral model id"
  assertTrue (LeanAgent.Json.optVal? payload "stream" == some (LeanAgent.Json.bool true))
    "expected streaming Mistral payload"
  assertTrue (LeanAgent.Json.optVal? payload "max_tokens" == some (LeanAgent.Json.nat 123))
    "expected Mistral max tokens"
  assertTrue (jsonStringField? payload "prompt_mode" == some "reasoning")
    "expected Mistral prompt mode"
  assertTrue (jsonStringField? payload "reasoning_effort" == some "high")
    "expected Mistral reasoning effort"
  assertTrue (jsonStringField? payload "prompt_cache_key" == some "session-123")
    "expected Mistral prompt cache key"
  match jsonArrayField? payload "messages" with
  | some messages =>
      assertTrue (messages.size == 4) "expected system, user, assistant, tool messages"
      match messages[0]? with
      | some systemMessage =>
          assertTrue (jsonStringField? systemMessage "role" == some "system") "expected Mistral system role"
          assertTrue (jsonStringField? systemMessage "content" == some "Be precise.") "expected Mistral system text"
      | none => fail "expected Mistral system message"
      match messages[1]? with
      | some userMessage =>
          assertTrue (jsonStringField? userMessage "role" == some "user") "expected Mistral user role"
          match jsonArrayField? userMessage "content" with
          | some content =>
              match content[0]?, content[1]? with
              | some textPart, some imagePart =>
                  assertTrue (jsonStringField? textPart "type" == some "text") "expected Mistral text chunk"
                  assertTrue (jsonStringField? textPart "text" == some "hello") "expected Mistral text"
                  assertTrue (jsonStringField? imagePart "type" == some "image_url") "expected Mistral image chunk"
                  assertTrue (jsonStringField? imagePart "image_url" == some "data:image/png;base64,aGVsbG8=")
                    "expected Mistral image data URL"
              | _, _ => fail "expected Mistral text and image chunks"
          | none => fail "expected Mistral user content array"
      | none => fail "expected Mistral user message"
      match messages[2]? with
      | some assistantMessage =>
          match jsonArrayField? assistantMessage "tool_calls" with
          | some toolCalls =>
              match toolCalls[0]? with
              | some toolCall =>
                  assertTrue (jsonStringField? toolCall "id" == some normalizedToolId)
                    "expected normalized Mistral assistant tool id"
              | none => fail "expected Mistral assistant tool call"
          | none => fail "expected Mistral assistant tool_calls"
      | none => fail "expected Mistral assistant message"
      match messages[3]? with
      | some toolMessage =>
          assertTrue (jsonStringField? toolMessage "tool_call_id" == some normalizedToolId)
            "expected normalized Mistral tool result id"
      | none => fail "expected Mistral tool message"
  | none => fail "expected Mistral messages"
  match jsonArrayField? payload "tools" with
  | some tools =>
      match tools[0]? with
      | some tool =>
          assertTrue (jsonStringField? tool "type" == some "function") "expected Mistral function tool"
          match LeanAgent.Json.optVal? tool "function" with
          | some fn =>
              assertTrue (jsonStringField? fn "name" == some "read") "expected Mistral function name"
              assertTrue (LeanAgent.Json.optVal? fn "strict" == some (LeanAgent.Json.bool false))
                "expected Mistral strict false"
              assertTrue (LeanAgent.Json.optVal? fn "parameters" |>.isSome)
                "expected Mistral tool parameters"
          | none => fail "expected Mistral function object"
      | none => fail "expected Mistral tool"
  | none => fail "expected Mistral tools"
  match LeanAgent.Json.optVal? payload "tool_choice" with
  | some toolChoice =>
      match LeanAgent.Json.optVal? toolChoice "function" with
      | some fn => assertTrue (jsonStringField? fn "name" == some "read") "expected Mistral tool choice name"
      | none => fail "expected Mistral function tool choice"
  | none => fail "expected Mistral tool_choice"
  let headers := LeanAgent.AI.Api.MistralConversations.requestHeaders
    { apiKey := "mistral-key"
      headers := #[("X-Custom", "custom")]
    }
    { sessionId := some "session-123"
      headers := #[("X-Trace", some "trace-mistral")]
    }
  assertTrue (headerValueCaseInsensitive? headers "authorization" == some "Bearer mistral-key")
    "expected Mistral bearer auth"
  assertTrue (headerValueCaseInsensitive? headers "x-affinity" == some "session-123")
    "expected Mistral x-affinity prompt cache header"
  assertTrue (headerValueCaseInsensitive? headers "X-Custom" == some "custom")
    "expected Mistral custom config header"
  assertTrue (headerValueCaseInsensitive? headers "X-Trace" == some "trace-mistral")
    "expected Mistral request header"
  let overrideHeaders := LeanAgent.AI.Api.MistralConversations.requestHeaders
    { apiKey := "" }
    { sessionId := some "session-123"
      headers := #[("Authorization", some "Bearer external"), ("x-affinity", some "caller-session")]
    }
  assertTrue (headerValueCaseInsensitive? overrideHeaders "authorization" == some "Bearer external")
    "expected caller-owned Mistral authorization"
  assertTrue (headerValueCaseInsensitive? overrideHeaders "x-affinity" == some "caller-session")
    "expected caller-owned x-affinity"

def testMistralToolChoiceOptionVariants : IO Unit := do
  let context : LeanAgent.AI.Context :=
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
  let assertScalarChoice
      (choice : LeanAgent.AI.Api.MistralConversations.ToolChoice)
      (expected : String) : IO Unit := do
    let payload := LeanAgent.AI.Api.MistralConversations.requestToJsonWithOptions
      mistralModelRef
      #["text"]
      context
      { toolChoice := some choice }
    assertTrue (jsonStringField? payload "tool_choice" == some expected)
      s!"expected Mistral scalar tool_choice {expected}"
  assertScalarChoice .auto "auto"
  assertScalarChoice .none "none"
  assertScalarChoice .any "any"
  assertScalarChoice .required "required"

def testMistralReasoningAndPromptCacheOptions : IO Unit := do
  let small2603 ←
    match LeanAgent.Models.mistralModels.find? (fun model => model.id == "mistral-small-2603") with
    | some model => pure model
    | none => throw (IO.userError "expected Mistral Small 4 model")
  let magistral ←
    match LeanAgent.Models.mistralModels.find? (fun model => model.id == "magistral-medium-latest") with
    | some model => pure model
    | none => throw (IO.userError "expected Magistral model")
  let large ←
    match LeanAgent.Models.mistralModels.find? (fun model => model.id == "mistral-large-latest") with
    | some model => pure model
    | none => throw (IO.userError "expected Mistral Large model")
  let smallOptions := LeanAgent.AI.Providers.Streams.mistralOptionsFromSimple
    small2603
    { reasoning := some .medium }
  assertTrue (smallOptions.reasoningEffort == some "high") "expected Mistral Small 4 reasoning effort"
  assertTrue smallOptions.promptMode.isNone "expected no prompt mode for reasoning-effort models"
  let magistralOptions := LeanAgent.AI.Providers.Streams.mistralOptionsFromSimple
    magistral
    { reasoning := some .medium }
  assertTrue (magistralOptions.promptMode == some "reasoning") "expected Magistral prompt mode"
  assertTrue magistralOptions.reasoningEffort.isNone "expected no reasoning effort for Magistral"
  let noReasoning := LeanAgent.AI.Providers.Streams.mistralOptionsFromSimple
    small2603
    {}
  assertTrue noReasoning.reasoningEffort.isNone "expected no Mistral reasoning controls without request"
  assertTrue noReasoning.promptMode.isNone "expected no Mistral prompt mode without request"
  let cachePayload := LeanAgent.AI.Api.MistralConversations.requestToJsonWithOptions
    large.toModelRef
    large.input
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
    { sessionId := some "session-123" }
  assertTrue (jsonStringField? cachePayload "prompt_cache_key" == some "session-123")
    "expected Mistral prompt cache key from session"
  let noCachePayload := LeanAgent.AI.Api.MistralConversations.requestToJsonWithOptions
    large.toModelRef
    large.input
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
    { sessionId := some "session-123"
      cacheRetention := some .none
    }
  assertTrue (jsonStringField? noCachePayload "prompt_cache_key" == none)
    "expected disabled Mistral prompt cache"
  let noCacheHeaders := LeanAgent.AI.Api.MistralConversations.requestHeaders
    { apiKey := "mistral-key" }
    { sessionId := some "session-123"
      cacheRetention := some .none
    }
  assertTrue (headerValueCaseInsensitive? noCacheHeaders "x-affinity" == none)
    "expected disabled Mistral prompt cache affinity header"

def testMistralConversationsParsesResponse : IO Unit := do
  let raw :=
    "{ \"id\":\"chatcmpl_mistral\", \"model\":\"devstral-medium-latest\", \"choices\":[{" ++
    "\"finish_reason\":\"tool_calls\", \"message\":{" ++
    "\"content\":[{\"type\":\"thinking\",\"thinking\":[{\"type\":\"text\",\"text\":\"plan\"}]},{\"type\":\"text\",\"text\":\"hello\"}]," ++
    "\"tool_calls\":[{\"id\":\"abc123def\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"README.md\\\"}\"}}]" ++
    "}}], \"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15,\"prompt_tokens_details\":{\"cached_tokens\":3}} }"
  match LeanAgent.AI.Api.MistralConversations.parseChatCompletion
      LeanAgent.AI.Api.MistralConversations.api
      LeanAgent.Models.mistralProviderId
      LeanAgent.Models.mistralDefaultModel
      7
      raw with
  | .ok response =>
      assertTrue (response.responseId == some "chatcmpl_mistral") "expected Mistral response id"
      assertTrue (response.responseModel == none) "expected same Mistral model to be omitted"
      assertTrue (response.stopReason == .toolUse) "expected Mistral tool-use stop"
      assertTrue (response.usage.input == 7) "expected Mistral cached input subtraction"
      assertTrue (response.usage.output == 5) "expected Mistral output tokens"
      assertTrue (response.usage.cacheRead == 3) "expected Mistral cache read"
      assertTrue (response.usage.totalTokens == 15) "expected Mistral total tokens"
      assertTrue
        (response.content.any fun
          | .thinking thinking => thinking.thinking == "plan"
          | _ => false)
        "expected Mistral thinking block"
      assertTrue
        (response.content.any fun
          | .text text => text.text == "hello"
          | _ => false)
        "expected Mistral text block"
      match LeanAgent.AI.contentToolCalls response.content |>.toList with
      | [call] =>
          assertTrue (call.id == "abc123def") "expected Mistral tool id"
          assertTrue (call.name == "read") "expected Mistral tool name"
          assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected Mistral tool args"
      | _ => fail "expected one Mistral tool call"
  | .error err => fail s!"expected Mistral parse success: {err}"

def testMistralConversationsParsesStreamingEvents : IO Unit := do
  let raw := String.intercalate "\n\n"
    [ "data: {\"id\":\"chatcmpl_stream\",\"model\":\"devstral-medium-latest\",\"choices\":[{\"delta\":{\"content\":[{\"type\":\"thinking\",\"thinking\":[{\"type\":\"text\",\"text\":\"plan\"}]}]},\"finish_reason\":null}],\"usage\":{\"prompt_tokens\":4,\"prompt_tokens_details\":{\"cached_tokens\":1}}}"
    , "data: {\"choices\":[{\"delta\":{\"content\":\"hel\"},\"finish_reason\":null}]}"
    , "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"},\"finish_reason\":null}]}"
    , "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"abc123def\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\"}}]},\"finish_reason\":null}]}"
    , "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"README.md\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}],\"usage\":{\"prompt_tokens\":4,\"completion_tokens\":2,\"total_tokens\":6,\"prompt_tokens_details\":{\"cached_tokens\":1}}}"
    , "data: [DONE]"
    , ""
    ]
  match LeanAgent.AI.Api.MistralConversations.parseStreamingEventStream
      LeanAgent.AI.Api.MistralConversations.api
      LeanAgent.Models.mistralProviderId
      LeanAgent.Models.mistralDefaultModel
      9
      raw with
  | .ok stream =>
      assertTrue stream.isComplete "expected completed Mistral stream"
      assertTrue (stream.result.responseId == some "chatcmpl_stream") "expected streamed Mistral response id"
      assertTrue (stream.result.responseModel == none) "expected same streamed Mistral model to be omitted"
      assertTrue (stream.result.stopReason == .toolUse) "expected streamed Mistral tool-use stop"
      assertTrue (stream.result.usage.input == 3) "expected streamed Mistral input"
      assertTrue (stream.result.usage.output == 2) "expected streamed Mistral output"
      assertTrue (stream.result.usage.cacheRead == 1) "expected streamed Mistral cache read"
      assertTrue (stream.result.usage.totalTokens == 6) "expected streamed Mistral total tokens"
      assertTrue
        (LeanAgent.AI.contentPlainText stream.result.content == "plan\nhello")
        "expected streamed Mistral text content"
      match LeanAgent.AI.contentToolCalls stream.result.content |>.toList with
      | [call] =>
          assertTrue (call.id == "abc123def") "expected streamed Mistral tool id"
          assertTrue (call.name == "read") "expected streamed Mistral tool name"
          assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
            "expected streamed Mistral tool arguments"
      | _ => fail "expected one streamed Mistral tool call"
      assertTrue
        (stream.events.any fun
          | .thinkingDelta _ "plan" _ => true
          | _ => false)
        "expected Mistral thinking delta"
      assertTrue
        (stream.events.any fun
          | .textDelta _ "hel" _ => true
          | _ => false)
        "expected Mistral text delta"
      assertTrue
        (stream.events.any fun
          | .toolCallDelta _ "{\"path\":" _ => true
          | _ => false)
        "expected Mistral tool-call delta"
  | .error err => fail s!"expected Mistral streaming parse success: {err}"

def testBedrockConverseRequestPayload : IO Unit := do
  let assistant : LeanAgent.AI.AssistantMessage :=
    { content :=
        #[ .thinking { thinking := "reasoning", thinkingSignature := some "sig" }
         , .text { text := "plan" }
         , .toolCall
            { id := "call_read_item"
              name := "read"
              arguments := LeanAgent.Json.obj [("path", LeanAgent.Json.str "README.md")]
            }
         ]
      api := LeanAgent.AI.Api.BedrockConverseStream.api
      provider := LeanAgent.Models.amazonBedrockProviderId
      model := LeanAgent.Models.amazonBedrockDefaultModel
      stopReason := .toolUse
      timestamp := 2
    }
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "Be precise."
      messages :=
        #[ .user
            { content := #[LeanAgent.AI.text "hello", LeanAgent.AI.image "aGVsbG8=" "image/png"]
              timestamp := 1
            }
         , .assistant assistant
         , .toolResult
            { toolCallId := "call_read_item"
              toolName := "read"
              content := #[LeanAgent.AI.text "file contents"]
              isError := false
              timestamp := 3
            }
         ]
      tools :=
        #[ { name := "read"
             description := "Read a file"
             parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
           }
         ]
    }
  let payload := LeanAgent.AI.Api.BedrockConverseStream.requestToJsonWithOptions
    bedrockModelRef
    #["text", "image"]
    "Claude Opus 4.6 (US)"
    #[]
    true
    context
    { maxTokens := some 4096
      temperature := some 0.2
      cacheRetention := some .long
      toolChoice := some .any
      reasoning := some .medium
      thinkingDisplay := some .omitted
      metadata := some (LeanAgent.Json.obj [("session", LeanAgent.Json.str "s1")])
    }
  assertTrue
    (jsonStringField? payload "modelId" == some LeanAgent.Models.amazonBedrockDefaultModel)
    "expected Bedrock model id"
  match jsonArrayField? payload "system" with
  | some system =>
      assertTrue (system.size == 2) "expected Bedrock cacheable system prompt"
      match system[0]?, system[1]? with
      | some textBlock, some cacheBlock =>
          assertTrue (jsonStringField? textBlock "text" == some "Be precise.") "expected Bedrock system text"
          match jsonObjectField? cacheBlock "cachePoint" with
          | some cachePoint =>
              assertTrue (jsonStringField? cachePoint "ttl" == some "ONE_HOUR") "expected Bedrock long cache"
          | none => fail "expected Bedrock cache point"
      | _, _ => fail "expected Bedrock system blocks"
  | none => fail "expected Bedrock system array"
  match jsonObjectField? payload "inferenceConfig" with
  | some inference =>
      assertTrue (LeanAgent.Json.optVal? inference "maxTokens" == some (LeanAgent.Json.nat 4096))
        "expected Bedrock max tokens"
      assertTrue (LeanAgent.Json.optVal? inference "temperature" == some (LeanAgent.AI.floatJson 0.2))
        "expected Bedrock temperature"
  | none => fail "expected Bedrock inference config"
  match jsonArrayField? payload "messages" with
  | some messages =>
      assertTrue (messages.size == 3) "expected Bedrock user, assistant, tool-result messages"
      match messages[0]? with
      | some userMessage =>
          match jsonArrayField? userMessage "content" with
          | some content =>
              match content[0]?, content[1]? with
              | some textPart, some imagePart =>
                  assertTrue (jsonStringField? textPart "text" == some "hello") "expected Bedrock text part"
                  match jsonObjectField? imagePart "image" with
                  | some image => assertTrue (jsonStringField? image "format" == some "png") "expected Bedrock image"
                  | none => fail "expected Bedrock image part"
              | _, _ => fail "expected Bedrock text and image"
          | none => fail "expected Bedrock user content"
      | none => fail "expected Bedrock user message"
      match messages[1]? with
      | some assistantMessage =>
          match jsonArrayField? assistantMessage "content" with
          | some content =>
              match content[0]?, content[1]?, content[2]? with
              | some thinkingPart, some textPart, some toolPart =>
                  assertTrue (jsonObjectField? thinkingPart "reasoningContent" |>.isSome)
                    "expected Bedrock reasoning content"
                  assertTrue (jsonStringField? textPart "text" == some "plan") "expected Bedrock assistant text"
                  match jsonObjectField? toolPart "toolUse" with
                  | some toolUse =>
                      assertTrue (jsonStringField? toolUse "toolUseId" == some "call_read_item")
                        "expected normalized Bedrock tool id"
                  | none => fail "expected Bedrock tool use"
              | _, _, _ => fail "expected Bedrock assistant blocks"
          | none => fail "expected Bedrock assistant content"
      | none => fail "expected Bedrock assistant message"
      match messages[2]? with
      | some toolMessage =>
          match jsonArrayField? toolMessage "content" with
          | some content =>
              match content[0]? with
              | some resultPart =>
                  match jsonObjectField? resultPart "toolResult" with
                  | some toolResult =>
                      assertTrue (jsonStringField? toolResult "toolUseId" == some "call_read_item")
                        "expected normalized Bedrock tool result id"
                      assertTrue (jsonStringField? toolResult "status" == some "success")
                        "expected Bedrock tool result status"
                  | none => fail "expected Bedrock tool result"
              | none => fail "expected Bedrock tool result block"
          | none => fail "expected Bedrock tool result content"
      | none => fail "expected Bedrock tool result message"
  | none => fail "expected Bedrock messages"
  match jsonObjectField? payload "toolConfig" with
  | some toolConfig =>
      match jsonObjectField? toolConfig "toolChoice" with
      | some choice => assertTrue (jsonObjectField? choice "any" |>.isSome) "expected Bedrock any tool choice"
      | none => fail "expected Bedrock tool choice"
  | none => fail "expected Bedrock tool config"
  match jsonObjectField? payload "additionalModelRequestFields" with
  | some fields =>
      match jsonObjectField? fields "thinking", jsonObjectField? fields "output_config" with
      | some thinking, some outputConfig =>
          assertTrue (jsonStringField? thinking "type" == some "adaptive") "expected adaptive Bedrock thinking"
          assertTrue (jsonStringField? thinking "display" == some "omitted") "expected Bedrock thinking display"
          assertTrue (jsonStringField? outputConfig "effort" == some "medium") "expected Bedrock effort"
      | _, _ => fail "expected Bedrock thinking output fields"
  | none => fail "expected Bedrock additional request fields"
  match jsonObjectField? payload "requestMetadata" with
  | some metadata => assertTrue (jsonStringField? metadata "session" == some "s1") "expected Bedrock metadata"
  | none => fail "expected Bedrock request metadata"

def testBedrockConverseGovCloudThinkingDisplayOmitted : IO Unit := do
  let model : LeanAgent.AI.ModelRef :=
    { id := "us-gov.anthropic.claude-sonnet-4-5-20250929-v1:0"
      api := LeanAgent.AI.Api.BedrockConverseStream.api
      provider := LeanAgent.Models.amazonBedrockProviderId
      baseUrl := some LeanAgent.Models.amazonBedrockBaseUrl
    }
  let payload := LeanAgent.AI.Api.BedrockConverseStream.requestToJsonWithOptions
    model
    #["text"]
    "Claude Sonnet 4.5 (GovCloud)"
    #[]
    true
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
    { reasoning := some .medium
      thinkingDisplay := some .omitted
      region := some "us-gov-west-1"
    }
  match jsonObjectField? payload "additionalModelRequestFields" with
  | some fields =>
      match jsonObjectField? fields "thinking" with
      | some thinking =>
          assertTrue (LeanAgent.Json.optVal? thinking "display" == none)
            "expected GovCloud Bedrock thinking display to be omitted"
      | none => fail "expected GovCloud Bedrock thinking object"
  | none => fail "expected GovCloud Bedrock additional fields"

def testBedrockConversePreparedRequestSigV4 : IO Unit := do
  let model : LeanAgent.AI.ModelRef :=
    { id := "anthropic.claude-3-7-sonnet-20250219-v1:0"
      api := LeanAgent.AI.Api.BedrockConverseStream.api
      provider := LeanAgent.Models.amazonBedrockProviderId
      baseUrl := some LeanAgent.Models.amazonBedrockBaseUrl
    }
  let prepared ← LeanAgent.AI.Api.BedrockConverseStream.prepareRequestWithTimestamp
    { baseUrl := LeanAgent.Models.amazonBedrockBaseUrl }
    model
    #["text"]
    "Claude 3.7 Sonnet Bedrock Fixture"
    #[]
    true
    { messages :=
        #[.user
            { content := #[LeanAgent.AI.text "Auth surface fixture bedrock-auth-sigv4-session."]
              timestamp := 1
            }]
    }
    { amzDate := "20250115T120000Z", dateStamp := "20250115" }
    { maxTokens := some 32
      region := some "us-east-1"
      env :=
        #[ ("AWS_ACCESS_KEY_ID", "AKIDEXAMPLE")
         , ("AWS_SECRET_ACCESS_KEY", "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY")
         , ("AWS_SESSION_TOKEN", "IQoJb3JpZ2luX2VjEOr//////////wEaCXVzLWVhc3QtMSJHMEUCIQDn")
         ]
    }
  assertTrue (prepared.auth.mode == .sigv4) "expected Bedrock SigV4 auth mode"
  assertTrue (prepared.region == "us-east-1") "expected Bedrock request region"
  assertTrue
    (prepared.requestPath == "/model/anthropic.claude-3-7-sonnet-20250219-v1%3A0/converse-stream")
    "expected Bedrock request path encoding"
  assertTrue
    (prepared.url ==
      "https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-3-7-sonnet-20250219-v1%3A0/converse-stream")
    "expected Bedrock request URL"
  assertTrue (jsonStringField? prepared.payload "modelId" == some model.id)
    "expected prepared Bedrock payload model id"
  assertTrue (headerValueCaseInsensitive? prepared.headers "content-type" == some "application/json")
    "expected Bedrock content type header"
  assertTrue
    (headerValueCaseInsensitive? prepared.headers "host" == some "bedrock-runtime.us-east-1.amazonaws.com")
    "expected Bedrock host header"
  assertTrue
    (headerValueCaseInsensitive? prepared.headers "x-amz-date" == some "20250115T120000Z")
    "expected Bedrock x-amz-date"
  assertTrue
    (headerValueCaseInsensitive? prepared.headers "x-amz-content-sha256" ==
      some "0767c6a798a11c4b4421ee09d6c7cd070a18411039e22e1f06beb05c305d49d0")
    "expected Bedrock payload SHA256"
  assertTrue
    (headerValueCaseInsensitive? prepared.headers "x-amz-security-token" ==
      some "IQoJb3JpZ2luX2VjEOr//////////wEaCXVzLWVhc3QtMSJHMEUCIQDn")
    "expected Bedrock session token header"
  assertTrue
    (headerValueCaseInsensitive? prepared.headers "authorization" ==
      some
        "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20250115/us-east-1/bedrock/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date;x-amz-security-token, Signature=f1b63a6d40b48e8fdb558c9b76d69b24fb8c99cb549e3c54f39bb9f3ed4713ae")
    "expected Bedrock SigV4 authorization header"

def testBedrockConversePreparedRequestAwsProfile : IO Unit := do
  let model : LeanAgent.AI.ModelRef :=
    { id := "anthropic.claude-3-7-sonnet-20250219-v1:0"
      api := LeanAgent.AI.Api.BedrockConverseStream.api
      provider := LeanAgent.Models.amazonBedrockProviderId
      baseUrl := some LeanAgent.Models.amazonBedrockBaseUrl
    }
  IO.FS.withTempDir fun root => do
    let credentialsPath := root / "credentials"
    let configPath := root / "config"
    IO.FS.writeFile credentialsPath (String.intercalate "\n"
      [ "[dev]"
      , "aws_access_key_id = PROFILEKEY"
      , "aws_secret_access_key = PROFILESECRET"
      , "aws_session_token = PROFILETOKEN"
      ])
    IO.FS.writeFile configPath (String.intercalate "\n"
      [ "[profile dev]"
      , "region = us-west-2"
      ])
    let prepared ← LeanAgent.AI.Api.BedrockConverseStream.prepareRequestWithTimestamp
      { baseUrl := LeanAgent.Models.amazonBedrockBaseUrl }
      model
      #["text"]
      "Claude 3.7 Sonnet Bedrock Profile Fixture"
      #[]
      true
      { messages := #[.user { content := #[LeanAgent.AI.text "profile fixture"], timestamp := 1 }] }
      { amzDate := "20250115T120000Z", dateStamp := "20250115" }
      { env :=
          #[ ("AWS_PROFILE", "dev")
           , ("AWS_SHARED_CREDENTIALS_FILE", credentialsPath.toString)
           , ("AWS_CONFIG_FILE", configPath.toString)
           ]
      }
    assertTrue (prepared.auth.mode == .sigv4) "expected Bedrock profile auth to resolve to SigV4"
    assertTrue (prepared.auth.profile == some "dev") "expected Bedrock resolved profile name"
    assertTrue (prepared.auth.source == some "AWS_PROFILE") "expected Bedrock resolved profile source"
    assertTrue (prepared.region == "us-west-2") "expected Bedrock profile region from shared config"
    assertTrue
      (prepared.url ==
        "https://bedrock-runtime.us-west-2.amazonaws.com/model/anthropic.claude-3-7-sonnet-20250219-v1%3A0/converse-stream")
      "expected Bedrock profile URL to use shared-config region"
    assertTrue
      (headerValueCaseInsensitive? prepared.headers "x-amz-security-token" == some "PROFILETOKEN")
      "expected Bedrock profile session token header"
    match headerValueCaseInsensitive? prepared.headers "authorization" with
    | some authorization =>
        assertTrue
          (authorization.contains "Credential=PROFILEKEY/20250115/us-west-2/bedrock/aws4_request")
          "expected Bedrock profile authorization scope"
    | none => fail "expected Bedrock profile authorization header"

def testBedrockConverseProfileWithoutSharedCredentialsFails : IO Unit := do
  let model : LeanAgent.AI.ModelRef :=
    { id := "anthropic.claude-3-7-sonnet-20250219-v1:0"
      api := LeanAgent.AI.Api.BedrockConverseStream.api
      provider := LeanAgent.Models.amazonBedrockProviderId
      baseUrl := some LeanAgent.Models.amazonBedrockBaseUrl
    }
  IO.FS.withTempDir fun root => do
    let credentialsPath := root / "credentials"
    let configPath := root / "config"
    IO.FS.writeFile credentialsPath "[dev]\n"
    IO.FS.writeFile configPath "[profile dev]\nregion = us-west-2\n"
    let failed ←
      try
        let _ ← LeanAgent.AI.Api.BedrockConverseStream.prepareRequestWithTimestamp
          { baseUrl := LeanAgent.Models.amazonBedrockBaseUrl }
          model
          #["text"]
          "Claude 3.7 Sonnet Bedrock Missing Profile Fixture"
          #[]
          true
          { messages := #[.user { content := #[LeanAgent.AI.text "profile failure"], timestamp := 1 }] }
          { amzDate := "20250115T120000Z", dateStamp := "20250115" }
          { env :=
              #[ ("AWS_PROFILE", "dev")
               , ("AWS_SHARED_CREDENTIALS_FILE", credentialsPath.toString)
               , ("AWS_CONFIG_FILE", configPath.toString)
               ]
          }
        pure false
      catch err =>
        pure (err.toString.contains "aws_access_key_id and aws_secret_access_key")
    assertTrue failed "expected unresolved Bedrock profile credentials to fail explicitly"

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

def testOpenAICodexResponsesAuthAndUrlHelpers : IO Unit := do
  match LeanAgent.AI.Api.OpenAICodexResponses.extractAccountId fakeOpenAICodexJwt with
  | .ok accountId => assertTrue (accountId == "acct_test") "expected Codex account id"
  | .error err => fail s!"expected account id: {err}"
  assertTrue
    (LeanAgent.AI.Api.OpenAICodexResponses.codexResponsesUrl
      "https://chatgpt.com/backend-api" ==
        "https://chatgpt.com/backend-api/codex/responses")
    "expected default Codex URL suffix"
  assertTrue
    (LeanAgent.AI.Api.OpenAICodexResponses.codexResponsesUrl
      "https://chatgpt.com/backend-api/codex" ==
        "https://chatgpt.com/backend-api/codex/responses")
    "expected Codex URL from /codex base"
  assertTrue
    (LeanAgent.AI.Api.OpenAICodexResponses.codexResponsesUrl
      "https://chatgpt.com/backend-api/codex/responses" ==
        "https://chatgpt.com/backend-api/codex/responses")
    "expected Codex URL to preserve explicit endpoint"

def testOpenAICodexResponsesRequestPayload : IO Unit := do
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "codex system"
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      tools :=
        #[ { name := "read"
             description := "Read a file"
             parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
           }
         ]
    }
  let model :=
    (LeanAgent.Models.openAICodexModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 272000 128000).toResponsesModel
  let payload := LeanAgent.AI.Api.OpenAICodexResponses.requestToJsonWithOptions
    model
    context
    { sessionId := some "codex-session"
      temperature := some 0.2
      serviceTier := some "priority"
      reasoningEffort := some (.level .minimal)
    }
  assertTrue (jsonStringField? payload "model" == some "gpt-5.5") "expected Codex model id"
  assertTrue (LeanAgent.Json.optVal? payload "store" == some (LeanAgent.Json.bool false)) "expected store=false"
  assertTrue (LeanAgent.Json.optVal? payload "stream" == some (LeanAgent.Json.bool true)) "expected stream=true"
  assertTrue (jsonStringField? payload "instructions" == some "codex system") "expected instructions field"
  assertTrue (jsonStringField? payload "prompt_cache_key" == some "codex-session") "expected prompt cache key"
  assertTrue (jsonStringField? payload "tool_choice" == some "auto") "expected auto tool choice"
  assertTrue
    (LeanAgent.Json.optVal? payload "parallel_tool_calls" == some (LeanAgent.Json.bool true))
    "expected parallel tool calls"
  match LeanAgent.Json.optVal? payload "text" with
  | some text => assertTrue (jsonStringField? text "verbosity" == some "low") "expected low verbosity"
  | none => fail "expected text options"
  match jsonArrayField? payload "include" with
  | some includeItems =>
      assertTrue (includeItems == #[LeanAgent.Json.str "reasoning.encrypted_content"])
        "expected encrypted reasoning include"
  | none => fail "expected include array"
  match LeanAgent.Json.optVal? payload "reasoning" with
  | some reasoning =>
      assertTrue (jsonStringField? reasoning "effort" == some "low") "expected mapped minimal effort"
      assertTrue (jsonStringField? reasoning "summary" == some "auto") "expected default reasoning summary"
  | none => fail "expected Codex reasoning object"
  match jsonArrayField? payload "input" with
  | some input =>
      assertTrue (input.size == 1) "expected system prompt to stay out of Codex input"
  | none => fail "expected Codex input"
  match jsonArrayField? payload "tools" with
  | some tools =>
      match tools[0]? with
      | some tool =>
          assertTrue (LeanAgent.Json.optVal? tool "strict" == none)
            "expected Codex tools to omit strict when Pi passes null"
      | none => fail "expected one Codex tool"
  | none => fail "expected Codex tools"

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

def testOpenAIResponsesStreamingIncompleteTerminalEvent : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"type\":\"response.incomplete\",\"response\":{\"id\":\"resp_incomplete\",\"status\":\"incomplete\",\"usage\":{\"input_tokens\":30,\"output_tokens\":12,\"total_tokens\":42,\"input_tokens_details\":{\"cached_tokens\":5}}}}"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAIResponses.parseStreamingEventStream
    "openai-responses" "openai" "gpt-5.5" 12 raw with
  | .ok stream =>
      assertTrue stream.isComplete "expected incomplete terminal event stream to finalize"
      assertTrue (stream.result.responseId == some "resp_incomplete") "expected incomplete response id"
      assertTrue (stream.result.stopReason == .length) "expected incomplete terminal event to map to length"
      assertTrue (stream.result.usage.input == 25) "expected cached input subtraction for incomplete event"
      assertTrue (stream.result.usage.output == 12) "expected incomplete output usage"
      assertTrue (stream.result.usage.cacheRead == 5) "expected incomplete cache read usage"
      assertTrue (stream.result.usage.totalTokens == 42) "expected incomplete total usage"
  | .error err => fail s!"expected incomplete terminal event parse success: {err}"

def testOpenAIResponsesStreamingFailedTerminalEvent : IO Unit := do
  let raw := String.intercalate "\n"
    [ "data: {\"type\":\"response.failed\",\"response\":{\"id\":\"resp_failed\",\"status\":\"failed\",\"error\":{\"code\":\"server_error\",\"message\":\"boom\"}}}"
    , ""
    ]
  match LeanAgent.AI.Api.OpenAIResponses.parseStreamingEventStream
    "openai-responses" "openai" "gpt-5.5" 13 raw with
  | .ok _ => fail "expected failed terminal event parse to fail"
  | .error err =>
      assertTrue (err.contains "server_error: boom")
        "expected failed terminal event to surface provider error"

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

def testDiagnosticsFormatsThrownJsonValues : IO Unit := do
  assertTrue
    (LeanAgent.AI.Util.Diagnostics.formatThrownJsonValue (LeanAgent.Json.str "plain") == "plain")
    "expected thrown string value to format directly"
  assertTrue
    (LeanAgent.AI.Util.Diagnostics.formatThrownJsonValue (LeanAgent.Json.nat 42) == "42")
    "expected thrown number value to format as JSON"
  let thrownObject := LeanAgent.Json.obj [("message", LeanAgent.Json.str "not an Error instance")]
  let info := LeanAgent.AI.Util.Diagnostics.extractThrownJsonError thrownObject
  assertTrue (info.name == some "ThrownValue") "expected non-error thrown value name"
  assertTrue (info.message == thrownObject.compress) "expected thrown object to use JSON string"
  let diagnostic :=
    LeanAgent.AI.Util.Diagnostics.createAssistantMessageDiagnosticFromJsonValue
      "runtime_error"
      thrownObject
      (some (LeanAgent.Json.obj [("phase", LeanAgent.Json.str "parse")]))
      123
  assertTrue (diagnostic.type == "runtime_error") "expected diagnostic type"
  assertTrue (diagnostic.timestamp == 123) "expected diagnostic timestamp"
  match diagnostic.error with
  | some error =>
      assertTrue (error.name == some "ThrownValue") "expected diagnostic thrown-value name"
      assertTrue (error.message == thrownObject.compress) "expected diagnostic thrown-value message"
  | none => fail "expected diagnostic error"

def testDiagnosticsProviderErrorObjectExtraction : IO Unit := do
  let wrapped := LeanAgent.Json.obj
    [ ("error", LeanAgent.Json.obj [("message", LeanAgent.Json.str "oops")])
    ]
  let err := LeanAgent.AI.Util.Diagnostics.providerErrorObject wrapped
  assertTrue (LeanAgent.Json.optVal? err "message" == some (LeanAgent.Json.str "oops"))
    "expected error object extraction from wrapped body"
  let unwrapped := LeanAgent.Json.obj [("code", LeanAgent.Json.nat 500)]
  let errUnwrapped := LeanAgent.AI.Util.Diagnostics.providerErrorObject unwrapped
  assertTrue (LeanAgent.Json.optVal? errUnwrapped "code" == some (LeanAgent.Json.nat 500))
    "expected fallback to full body when error key missing"

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
    (LeanAgent.AI.Providers.Streams.clampMaxTokensToContext model context 4000 == 902)
    "expected max tokens to fit context minus estimate and safety"
  assertTrue
    (LeanAgent.AI.Providers.Streams.clampMaxTokensToContext { model with contextWindow := 0 } context 0 == 1)
    "expected unknown context window to preserve minimum"
  let unknownMax := LeanAgent.AI.Providers.Streams.clampSimpleOptionsToContext { model with maxTokens := 0 } context {}
  assertTrue unknownMax.maxTokens.isNone "expected unknown model maxTokens to stay unset"
  let defaulted := LeanAgent.AI.Providers.Streams.clampSimpleOptionsToContext model context {}
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
  assertTrue (resolved == some "https://proxy.local:8443/") "expected HTTPS proxy with normalized URL"
  let scopedProxy ← LeanAgent.AI.Util.Proxy.resolveHttpProxyUrlForTargetWith
    ambient "https://api.example.com/v1" #[("https_proxy", "http://scoped.local:9000")]
  assertTrue (scopedProxy == some "http://scoped.local:9000/") "expected scoped proxy to win"
  let scopedEmpty ← LeanAgent.AI.Util.Proxy.resolveHttpProxyUrlForTargetWith
    ambient "https://api.example.com/v1" #[("https_proxy", "")]
  assertTrue (scopedEmpty == some "https://proxy.local:8443/") "expected empty scoped proxy to fall back"
  let fallback ← LeanAgent.AI.Util.Proxy.resolveHttpProxyUrlForTargetWith
    ambient "ws://socket.example.com"
  assertTrue (fallback == some "http://fallback.local:8080/") "expected ALL_PROXY fallback"
  let queryProxy ← LeanAgent.AI.Util.Proxy.resolveHttpProxyUrlForTargetWith
    ambient "https://api.example.com/v1" #[("https_proxy", "http://scoped.local:9000?via=env")]
  assertTrue (queryProxy == some "http://scoped.local:9000/?via=env") "expected URL-style query normalization"

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

def testJsonParseStreamingDropsDanglingSegments : IO Unit := do
  let trailingObjectComma := LeanAgent.AI.Util.JsonParse.parseStreamingJson "{\"path\":\"README.md\","
  assertTrue
    (LeanAgent.Json.optVal? trailingObjectComma "path" == some (LeanAgent.Json.str "README.md"))
    "expected dangling object comma to be dropped"

  let trailingArrayComma := LeanAgent.AI.Util.JsonParse.parseStreamingJson "{\"items\":[1,"
  match jsonArrayField? trailingArrayComma "items" with
  | some items =>
      assertTrue (items.size == 1) "expected dangling array comma to be dropped"
      assertTrue (items[0]? == some (LeanAgent.Json.nat 1)) "expected first array item"
  | none => fail "expected parsed items array"

  let danglingField := LeanAgent.AI.Util.JsonParse.parseStreamingJson "{\"a\":1,\"b\":"
  assertTrue
    (LeanAgent.Json.optVal? danglingField "a" == some (LeanAgent.Json.nat 1))
    "expected complete field before dangling field to survive"
  assertTrue
    (LeanAgent.Json.optVal? danglingField "b" == none)
    "expected dangling field to be omitted"

  let nestedDanglingField := LeanAgent.AI.Util.JsonParse.parseStreamingJson "{\"a\":1,\"b\":{\"c\":"
  assertTrue
    (LeanAgent.Json.optVal? nestedDanglingField "a" == some (LeanAgent.Json.nat 1))
    "expected outer complete field to survive"
  match LeanAgent.Json.optVal? nestedDanglingField "b" with
  | some nested =>
      match nested.getObj? with
      | .ok fields => assertTrue fields.toList.isEmpty "expected nested dangling field to be omitted"
      | .error _ => fail "expected nested object"
  | none => fail "expected nested object field"

def testJsonParseTruncatesPartialLiterals : IO Unit := do
  let partialTrue := LeanAgent.AI.Util.JsonParse.parseStreamingJson "{\"active\":tru"
  assertTrue
    (LeanAgent.Json.optVal? partialTrue "active" == none)
    "expected partial boolean to be truncated away"

  let partialNum := LeanAgent.AI.Util.JsonParse.parseStreamingJson "{\"count\":12."
  assertTrue
    (LeanAgent.Json.optVal? partialNum "count" == none)
    "expected trailing-dot number to be truncated"

  let completeNum := LeanAgent.AI.Util.JsonParse.parseStreamingJson "{\"count\":12"
  assertTrue
    (LeanAgent.Json.optVal? completeNum "count" == some (LeanAgent.Json.nat 12))
    "expected unclosed number to parse"

def testJsonParseTryHarderMultiplePasses : IO Unit := do
  let deep := LeanAgent.AI.Util.JsonParse.parseStreamingJson "{\"a\":{\"b\":{\"c\":\"d"
  match LeanAgent.Json.optVal? deep "a" with
  | some aObj =>
      match LeanAgent.Json.optVal? aObj "b" with
      | some bObj =>
          assertTrue
            (LeanAgent.Json.optVal? bObj "c" == some (LeanAgent.Json.str "d"))
            "expected deeply nested truncated string to parse"
      | none => fail "expected nested b object"
  | none => fail "expected nested a object"

  let bareString := LeanAgent.AI.Util.JsonParse.parseStreamingJson "\"hello"
  assertTrue (bareString == LeanAgent.Json.str "hello") "expected bare string to complete"

  let partialArray := LeanAgent.AI.Util.JsonParse.parseStreamingJson "[1,2,3"
  match partialArray.getArr? with
  | .ok items =>
      assertTrue (items.size == 3) "expected three array items"
      assertTrue (items[0]? == some (LeanAgent.Json.nat 1)) "expected first item"
      assertTrue (items[2]? == some (LeanAgent.Json.nat 3)) "expected third item"
  | .error err => fail s!"expected complete partial array: {err}"

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

def testValidationChecksSchemaBounds : IO Unit := do
  let stringSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "string")
      , ("minLength", LeanAgent.Json.nat 2)
      , ("maxLength", LeanAgent.Json.nat 4)
      ]
  assertValidationValue stringSchema (LeanAgent.Json.str "abc") (LeanAgent.Json.str "abc")
  assertValidationFails stringSchema (LeanAgent.Json.str "a")
  assertValidationFails stringSchema (LeanAgent.Json.str "abcde")

  let identifierPatternSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "string")
      , ("pattern", LeanAgent.Json.str "^[A-Za-z_][A-Za-z0-9_-]*$")
      ]
  assertValidationValue identifierPatternSchema
    (LeanAgent.Json.str "tool_1-alpha")
    (LeanAgent.Json.str "tool_1-alpha")
  assertValidationFails identifierPatternSchema (LeanAgent.Json.str "1tool")
  assertValidationFails identifierPatternSchema (LeanAgent.Json.str "bad space")

  let digitsPatternSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "string")
      , ("pattern", LeanAgent.Json.str "\\d+")
      ]
  assertValidationValue digitsPatternSchema
    (LeanAgent.Json.str "abc123")
    (LeanAgent.Json.str "abc123")
  assertValidationFails digitsPatternSchema (LeanAgent.Json.str "abc")

  let filePatternSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "string")
      , ("pattern", LeanAgent.Json.str "^file-\\d{2,4}\\.json$")
      ]
  assertValidationValue filePatternSchema
    (LeanAgent.Json.str "file-123.json")
    (LeanAgent.Json.str "file-123.json")
  assertValidationFails filePatternSchema (LeanAgent.Json.str "file-1.json")
  assertValidationFails filePatternSchema (LeanAgent.Json.str "file-12345.json")

  let arraySchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "array")
      , ("minItems", LeanAgent.Json.nat 2)
      , ("maxItems", LeanAgent.Json.nat 3)
      , ("items", LeanAgent.Json.obj [("type", LeanAgent.Json.str "integer")])
      ]
  assertValidationValue arraySchema
    (LeanAgent.Json.arr #[LeanAgent.Json.str "1", LeanAgent.Json.nat 2])
    (LeanAgent.Json.arr #[LeanAgent.Json.nat 1, LeanAgent.Json.nat 2])
  assertValidationFails arraySchema (LeanAgent.Json.arr #[LeanAgent.Json.nat 1])
  assertValidationFails arraySchema
    (LeanAgent.Json.arr
      #[LeanAgent.Json.nat 1, LeanAgent.Json.nat 2, LeanAgent.Json.nat 3, LeanAgent.Json.nat 4])

  let numberSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "number")
      , ("minimum", LeanAgent.Json.nat 2)
      , ("maximum", LeanAgent.Json.nat 4)
      ]
  assertValidationValue numberSchema (LeanAgent.Json.str "3") (LeanAgent.Json.nat 3)
  assertValidationFails numberSchema (LeanAgent.Json.nat 1)
  assertValidationFails numberSchema (LeanAgent.Json.nat 5)

  let exclusiveNumberSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "number")
      , ("exclusiveMinimum", LeanAgent.Json.nat 2)
      , ("exclusiveMaximum", LeanAgent.Json.nat 4)
      ]
  assertValidationValue exclusiveNumberSchema (LeanAgent.Json.nat 3) (LeanAgent.Json.nat 3)
  assertValidationFails exclusiveNumberSchema (LeanAgent.Json.nat 2)
  assertValidationFails exclusiveNumberSchema (LeanAgent.Json.nat 4)

  let booleanExclusiveNumberSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "number")
      , ("minimum", LeanAgent.Json.nat 2)
      , ("exclusiveMinimum", Lean.Json.bool true)
      , ("maximum", LeanAgent.Json.nat 4)
      , ("exclusiveMaximum", Lean.Json.bool true)
      ]
  assertValidationValue booleanExclusiveNumberSchema (LeanAgent.Json.nat 3) (LeanAgent.Json.nat 3)
  assertValidationFails booleanExclusiveNumberSchema (LeanAgent.Json.nat 2)
  assertValidationFails booleanExclusiveNumberSchema (LeanAgent.Json.nat 4)

def testValidationChecksSchemaCombinatorsAndConst : IO Unit := do
  let constSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "string")
      , ("const", LeanAgent.Json.str "ok")
      ]
  assertValidationValue constSchema (LeanAgent.Json.str "ok") (LeanAgent.Json.str "ok")
  assertValidationFails constSchema (LeanAgent.Json.str "no")
  assertValidationFails (LeanAgent.Json.obj [("enum", LeanAgent.Json.arr #[])])
    (LeanAgent.Json.str "anything")

  let allOfSchema :=
    LeanAgent.Json.obj
      [ ("allOf"
        , LeanAgent.Json.arr
            #[ LeanAgent.Json.obj [("type", LeanAgent.Json.str "number")]
             , LeanAgent.Json.obj [("minimum", LeanAgent.Json.nat 2)]
             , LeanAgent.Json.obj [("maximum", LeanAgent.Json.nat 4)]
             ])
      ]
  assertValidationValue allOfSchema (LeanAgent.Json.str "3") (LeanAgent.Json.nat 3)
  assertValidationFails allOfSchema (LeanAgent.Json.nat 1)
  assertValidationFails allOfSchema (LeanAgent.Json.nat 5)

  let anyOfSchema :=
    LeanAgent.Json.obj
      [ ("anyOf"
        , LeanAgent.Json.arr
            #[ LeanAgent.Json.obj
                [ ("type", LeanAgent.Json.str "string")
                , ("minLength", LeanAgent.Json.nat 3)
                ]
             , LeanAgent.Json.obj
                [ ("type", LeanAgent.Json.str "number")
                , ("minimum", LeanAgent.Json.nat 10)
                ]
             ])
      ]
  assertValidationValue anyOfSchema (LeanAgent.Json.str "tool") (LeanAgent.Json.str "tool")
  assertValidationValue anyOfSchema (LeanAgent.Json.nat 12) (LeanAgent.Json.nat 12)
  assertValidationFails anyOfSchema (LeanAgent.Json.str "no")
  assertValidationFails anyOfSchema (LeanAgent.Json.nat 4)

  let oneOfSchema :=
    LeanAgent.Json.obj
      [ ("oneOf"
        , LeanAgent.Json.arr
            #[ LeanAgent.Json.obj [("const", LeanAgent.Json.str "left")]
             , LeanAgent.Json.obj [("const", LeanAgent.Json.str "right")]
             ])
      ]
  assertValidationValue oneOfSchema (LeanAgent.Json.str "left") (LeanAgent.Json.str "left")
  assertValidationFails oneOfSchema (LeanAgent.Json.str "missing")
  let ambiguousOneOfSchema :=
    LeanAgent.Json.obj
      [ ("oneOf"
        , LeanAgent.Json.arr
            #[ LeanAgent.Json.obj [("type", LeanAgent.Json.str "string")]
             , LeanAgent.Json.obj [("minLength", LeanAgent.Json.nat 1)]
             ])
      ]
  assertValidationFails ambiguousOneOfSchema (LeanAgent.Json.str "x")

def testValidationChecksObjectAndArrayKeywords : IO Unit := do
  let objectSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "object")
      , ("minProperties", LeanAgent.Json.nat 1)
      , ("maxProperties", LeanAgent.Json.nat 2)
      ]
  assertValidationValue objectSchema
    (LeanAgent.Json.obj [("name", LeanAgent.Json.str "lean")])
    (LeanAgent.Json.obj [("name", LeanAgent.Json.str "lean")])
  assertValidationFails objectSchema (LeanAgent.Json.obj [])
  assertValidationFails objectSchema
    (LeanAgent.Json.obj
      [ ("a", LeanAgent.Json.nat 1)
      , ("b", LeanAgent.Json.nat 2)
      , ("c", LeanAgent.Json.nat 3)
      ])

  let uniqueArraySchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "array")
      , ("uniqueItems", Lean.Json.bool true)
      ]
  assertValidationValue uniqueArraySchema
    (LeanAgent.Json.arr #[LeanAgent.Json.str "a", LeanAgent.Json.str "b"])
    (LeanAgent.Json.arr #[LeanAgent.Json.str "a", LeanAgent.Json.str "b"])
  assertValidationFails uniqueArraySchema
    (LeanAgent.Json.arr #[LeanAgent.Json.str "a", LeanAgent.Json.str "a"])

  let containsSchema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "array")
      , ("contains"
        , LeanAgent.Json.obj
            [ ("type", LeanAgent.Json.str "integer")
            , ("minimum", LeanAgent.Json.nat 2)
            ])
      , ("minContains", LeanAgent.Json.nat 2)
      , ("maxContains", LeanAgent.Json.nat 2)
      ]
  assertValidationValue containsSchema
    (LeanAgent.Json.arr #[LeanAgent.Json.nat 1, LeanAgent.Json.nat 2, LeanAgent.Json.nat 3])
    (LeanAgent.Json.arr #[LeanAgent.Json.nat 1, LeanAgent.Json.nat 2, LeanAgent.Json.nat 3])
  assertValidationFails containsSchema
    (LeanAgent.Json.arr #[LeanAgent.Json.nat 1, LeanAgent.Json.nat 2])
  assertValidationFails containsSchema
    (LeanAgent.Json.arr #[LeanAgent.Json.nat 2, LeanAgent.Json.nat 3, LeanAgent.Json.nat 4])
  assertValidationFails
    (LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "array")
      , ("contains", LeanAgent.Json.obj [("const", LeanAgent.Json.str "hit")])
      ])
    (LeanAgent.Json.arr #[LeanAgent.Json.str "miss"])

  let notSchema :=
    LeanAgent.Json.obj [("not", LeanAgent.Json.obj [("const", LeanAgent.Json.str "forbidden")])]
  assertValidationValue notSchema (LeanAgent.Json.str "ok") (LeanAgent.Json.str "ok")
  assertValidationFails notSchema (LeanAgent.Json.str "forbidden")

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


def testAnthropicMessagesPreserveUnicodePayloads : IO Unit := do
  let raw := "🙈A🙈B"
  let expected := LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates raw
  let textPayload := LeanAgent.AI.Api.AnthropicMessages.textBlock raw
  assertTrue (jsonStringField? textPayload "text" == some expected)
    "expected Anthropic text payload to preserve valid Unicode"
  let thinkingPayload := LeanAgent.AI.Api.AnthropicMessages.thinkingBlock raw "sig"
  assertTrue (jsonStringField? thinkingPayload "thinking" == some expected)
    "expected Anthropic thinking payload to preserve valid Unicode"
  match LeanAgent.AI.Api.AnthropicMessages.convertToolResultContent #[LeanAgent.AI.text raw] with
  | .str value =>
      assertTrue (value == expected)
        "expected Anthropic tool result text to preserve valid Unicode"
  | _ => fail "expected Anthropic tool result content to stay scalar text"

def testOpenAICompletionsPreserveUnicodeInMessages : IO Unit := do
  let raw := "🙈A🙈B"
  let expected := LeanAgent.AI.Util.SanitizeUnicode.sanitizeSurrogates raw
  let userJson := LeanAgent.AI.Api.OpenAICompletions.messageToJson (.user raw)
  assertTrue (jsonStringField? userJson "content" == some expected)
    "expected OpenAI user payload to preserve valid Unicode"
  let assistantJson := LeanAgent.AI.Api.OpenAICompletions.messageToJson (.assistant raw #[])
  assertTrue (jsonStringField? assistantJson "content" == some expected)
    "expected OpenAI assistant payload to preserve valid Unicode"
  let toolJson := LeanAgent.AI.Api.OpenAICompletions.messageToJson (.toolResult "tool-1" "read" raw true)
  assertTrue (jsonStringField? toolJson "content" == some expected)
    "expected OpenAI tool payload to preserve valid Unicode"
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

def testEstimateTextTokensPredictable : IO Unit := do
  let empty := LeanAgent.AI.Util.Estimate.estimateTextTokens ""
  assertTrue (empty == 0) "expected empty string to produce zero tokens"
  let single := LeanAgent.AI.Util.Estimate.estimateTextTokens "hello"
  assertTrue (single > 0) "expected single word to produce positive token count"
  let longer := "The quick brown fox jumps over the lazy dog"
  let estimate := LeanAgent.AI.Util.Estimate.estimateTextTokens longer
  assertTrue (estimate >= 5 && estimate <= 15)
    s!"expected reasonable token estimate for 9-word sentence, got {estimate}"
  let ascii := String.intercalate " " (List.replicate 100 "word")
  let asciiEstimate := LeanAgent.AI.Util.Estimate.estimateTextTokens ascii
  assertTrue (asciiEstimate >= 100) "expected at least 100 tokens for 100 words"

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
    (LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "finish_reason=model-context-window-exceeded")))
    "expected hyphenated model context window exceeded error"
  assertTrue
    (LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "context.length.exceeded by gateway")))
    "expected dotted context length exceeded error"
  assertTrue
    (LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "request-too-large: body exceeds provider size")))
    "expected hyphenated request too large error"
  assertTrue
    (!LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "Throttling error: Too many tokens, please wait before trying again.")))
    "expected Bedrock throttling text to be excluded"
  assertTrue
    (!LeanAgent.AI.Util.Overflow.isContextOverflow
      (overflowAssistantMessage .error (some "Throttling_error: Too many tokens, please wait before trying again.")))
    "expected separator-varied throttling text to be excluded"
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
    (LeanAgent.AI.Util.Retry.isRetryableAssistantError
      (retryAssistantMessage (some "provider_returned_error: upstream failed")))
    "expected underscore-separated provider returned error to be retryable"
  assertTrue
    (LeanAgent.AI.Util.Retry.isRetryableAssistantError
      (retryAssistantMessage (some "service-unavailable from upstream")))
    "expected hyphenated service unavailable to be retryable"
  assertTrue
    (LeanAgent.AI.Util.Retry.isRetryableAssistantError
      (retryAssistantMessage (some "websocket.closed before completion")))
    "expected dotted websocket closed to be retryable"
  assertTrue
    (LeanAgent.AI.Util.Retry.isRetryableAssistantError
      (retryAssistantMessage (some "rate_limit_error from gateway")))
    "expected underscore rate-limit variant to be retryable"
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

def testAbortCombineSignals : IO Unit := do
  let firstAbortRef ← IO.mkRef false
  let secondAbortRef ← IO.mkRef false
  let combined := LeanAgent.AI.Util.Abort.combineAbortSignals
    #[ some { isAborted := firstAbortRef.get }
     , some { isAborted := secondAbortRef.get }
     ]
  assertTrue (!(← LeanAgent.AI.Util.Abort.isAborted combined.signal))
    "expected combined abort signal to start pending"
  secondAbortRef.set true
  assertTrue (← LeanAgent.AI.Util.Abort.isAborted combined.signal)
    "expected combined abort signal to flip when any child aborts"
  combined.cleanup

def testRetryWithRetriesStopsOnAbortSignal : IO Unit := do
  let attempts ← IO.mkRef 0
  let abortedRef ← IO.mkRef false
  let aborted ←
    try
      let _ : String ← LeanAgent.AI.Util.Retry.withRetries
        { maxRetries := 2, maxRetryDelayMs := 250 }
        (do
          attempts.modify (· + 1)
          throw (IO.userError "provider HTTP 503: service unavailable")
          pure "unreachable")
        (some { isAborted := abortedRef.get })
        (fun _ => abortedRef.set true)
      pure false
    catch err =>
      assertTrue (err.toString.contains LeanAgent.AI.Util.Abort.requestAbortedMessage)
        "expected retry abort message"
      pure true
  assertTrue aborted "expected retry loop to abort during retry delay"
  assertTrue ((← attempts.get) == 1) "expected abort to prevent a second retry attempt"

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
     , LeanAgent.Models.openAICodexProviderId
     , LeanAgent.Models.azureOpenAIResponsesProviderId
     , LeanAgent.Models.openRouterProviderId
     , LeanAgent.Models.groqProviderId
     , LeanAgent.Models.xaiProviderId
     , LeanAgent.Models.cerebrasProviderId
     , LeanAgent.Models.togetherProviderId
     , LeanAgent.Models.fireworksProviderId
     , LeanAgent.Models.antLingProviderId
     , LeanAgent.Models.huggingFaceProviderId
     , LeanAgent.Models.moonshotAIProviderId
     , LeanAgent.Models.moonshotAICNProviderId
     , LeanAgent.Models.nvidiaProviderId
     , LeanAgent.Models.xiaomiProviderId
     , LeanAgent.Models.xiaomiTokenPlanAMSProviderId
     , LeanAgent.Models.xiaomiTokenPlanCNProviderId
     , LeanAgent.Models.xiaomiTokenPlanSGPProviderId
     , LeanAgent.Models.zaiProviderId
     , LeanAgent.Models.zaiCodingCNProviderId
     , LeanAgent.Models.anthropicProviderId
     , LeanAgent.Models.kimiCodingProviderId
     , LeanAgent.Models.minimaxProviderId
     , LeanAgent.Models.minimaxCNProviderId
     , LeanAgent.Models.vercelAIGatewayProviderId
     , LeanAgent.Models.opencodeProviderId
     , LeanAgent.Models.opencodeGoProviderId
     , LeanAgent.Models.googleProviderId
     , LeanAgent.Models.googleVertexProviderId
     , LeanAgent.Models.mistralProviderId
     , LeanAgent.Models.amazonBedrockProviderId
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
  match LeanAgent.Models.ProviderCatalog.model?
      catalog
      LeanAgent.Models.openAIProviderId
      LeanAgent.Models.openAIDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-responses") "expected OpenAI Responses API"
      assertTrue (model.baseUrl == LeanAgent.Models.openAIBaseUrl) "expected OpenAI base URL"
      assertTrue (model.contextWindow == 1047576) "expected OpenAI model context metadata"
      assertTrue (model.maxTokens == 32768) "expected OpenAI model output metadata"
      assertTrue (model.input.contains "image") "expected OpenAI image input metadata"
  | none => fail "expected OpenAI default model in catalog"
  let rendered := LeanAgent.Models.renderCatalog catalog
  assertTrue (rendered.contains "openai/gpt-4.1-mini") "expected OpenAI Responses default model"
  assertTrue (rendered.contains "openai/gpt-5.5-pro") "expected generated OpenAI Responses model set"
  assertTrue (rendered.contains "openai-codex/gpt-5.5") "expected OpenAI Codex model"
  assertTrue (rendered.contains "azure-openai-responses/gpt-4o-mini")
    "expected Azure OpenAI Responses model"
  assertTrue (rendered.contains "openrouter/openai/gpt-oss-120b") "expected OpenRouter model"
  assertTrue (rendered.contains "fireworks/accounts/fireworks/models/glm-5p2") "expected Fireworks OpenAI-compatible model"
  assertTrue (rendered.contains "ant-ling/Ring-2.6-1T") "expected Ant Ling model"
  assertTrue (rendered.contains "huggingface/zai-org/GLM-5.2") "expected Hugging Face generated model set"
  assertTrue (rendered.contains "moonshotai/kimi-k2.7-code") "expected Moonshot AI model"
  assertTrue (rendered.contains "moonshotai-cn/kimi-k2.7-code") "expected Moonshot AI CN model"
  assertTrue (rendered.contains "nvidia/z-ai/glm-5.1") "expected NVIDIA model"
  assertTrue (rendered.contains "xiaomi/mimo-v2.5-pro") "expected Xiaomi model"
  assertTrue (rendered.contains "xiaomi-token-plan-ams/mimo-v2.5-pro") "expected Xiaomi Token Plan AMS model"
  assertTrue (rendered.contains "xiaomi-token-plan-cn/mimo-v2.5-pro") "expected Xiaomi Token Plan CN model"
  assertTrue (rendered.contains "xiaomi-token-plan-sgp/mimo-v2.5-pro") "expected Xiaomi Token Plan SGP model"
  assertTrue (rendered.contains "zai/glm-5.2") "expected Z.AI model"
  assertTrue (rendered.contains "zai-coding-cn/glm-5.2") "expected Z.AI Coding CN model"
  assertTrue (rendered.contains "anthropic/claude-sonnet-4-5") "expected Anthropic model"
  assertTrue (rendered.contains "kimi-coding/k2p7") "expected Kimi Coding model"
  assertTrue (rendered.contains "minimax/MiniMax-M2.7") "expected MiniMax model"
  assertTrue (rendered.contains "minimax-cn/MiniMax-M2.7") "expected MiniMax CN model"
  assertTrue (rendered.contains "vercel-ai-gateway/alibaba/qwen-3-14b")
    "expected Vercel AI Gateway default model"
  assertTrue (rendered.contains "vercel-ai-gateway/anthropic/claude-opus-4.7")
    "expected Vercel AI Gateway Anthropic model"
  assertTrue (rendered.contains "opencode/gpt-5")
    "expected OpenCode Responses model"
  assertTrue (rendered.contains "opencode/gemini-3-flash")
    "expected OpenCode Google model"
  assertTrue (rendered.contains "opencode/claude-opus-4-7")
    "expected OpenCode Anthropic model"
  assertTrue (rendered.contains "opencode-go/minimax-m3")
    "expected OpenCode Go Anthropic model"
  assertTrue (rendered.contains "google/gemini-2.5-flash") "expected Google Gemini model"
  assertTrue (rendered.contains "google-vertex/gemini-2.5-flash") "expected Google Vertex model"
  assertTrue (rendered.contains "mistral/devstral-medium-latest") "expected Mistral model"
  assertTrue (rendered.contains "amazon-bedrock/us.anthropic.claude-opus-4-6-v1")
    "expected Amazon Bedrock model"
  assertTrue (LeanAgent.Models.amazonBedrockModels.size == 97) "expected generated Bedrock model catalog"
  assertTrue (LeanAgent.Models.antLingModels.size == 3) "expected generated Ant Ling model catalog"
  assertTrue (LeanAgent.Models.huggingFaceModels.size == 47) "expected generated Hugging Face model catalog"
  assertTrue (LeanAgent.Models.moonshotAIModels.size == 9) "expected generated Moonshot AI model catalog"
  assertTrue (LeanAgent.Models.moonshotAICNModels.size == 9) "expected generated Moonshot AI CN model catalog"
  assertTrue (LeanAgent.Models.nvidiaModels.size == 19) "expected generated NVIDIA model catalog"
  assertTrue
    (LeanAgent.Models.nvidiaModels.all fun model =>
      model.headers.findSome?
        (fun (name, value) =>
          if name.toLower == "nvcf-poll-seconds" then some value else none) == some "3600")
    "expected generated NVIDIA model headers"
  assertTrue (LeanAgent.Models.xiaomiModels.size == 6) "expected generated Xiaomi model catalog"
  assertTrue (LeanAgent.Models.xiaomiTokenPlanAMSModels.size == 5)
    "expected generated Xiaomi Token Plan AMS model catalog"
  assertTrue (LeanAgent.Models.xiaomiTokenPlanCNModels.size == 5)
    "expected generated Xiaomi Token Plan CN model catalog"
  assertTrue (LeanAgent.Models.xiaomiTokenPlanSGPModels.size == 5)
    "expected generated Xiaomi Token Plan SGP model catalog"
  assertTrue (LeanAgent.Models.zaiModels.size == 6) "expected generated Z.AI model catalog"
  assertTrue (LeanAgent.Models.zaiCodingCNModels.size == 6) "expected generated Z.AI Coding CN model catalog"

def testTogetherCatalogReasoningEffortCompat : IO Unit := do
  let catalog := LeanAgent.Models.defaultCatalog
  match LeanAgent.Models.ProviderCatalog.model?
      catalog
      LeanAgent.Models.togetherProviderId
      LeanAgent.Models.togetherDefaultModel with
  | some model =>
      assertTrue model.reasoning "expected Together default model reasoning support"
      assertTrue model.compat.supportsReasoningEffort
        "expected Together GPT OSS compat to support reasoning_effort"
      assertTrue model.compat.supportsReasoningEffortExplicit
        "expected Together GPT OSS reasoning-effort explicit override"
      assertTrue (model.compat.thinkingFormat == some "openai")
        "expected Together GPT OSS compat to use openai reasoning format"
      assertTrue model.compat.maxTokensFieldExplicit
        "expected Together GPT OSS max_tokens explicit override"
      assertTrue (LeanAgent.Models.thinkingLevelMapValue? model .off == some none)
        "expected Together GPT OSS off thinking level to map to omission"
      assertTrue (LeanAgent.Models.thinkingLevelMapValue? model (.level .minimal) == some none)
        "expected Together GPT OSS minimal thinking level to map to omission"
  | none => fail "expected Together default model in catalog"
  let rendered := LeanAgent.Models.renderCatalog catalog
  assertTrue (rendered.contains "together/openai/gpt-oss-20b")
    "expected Together GPT OSS 20B model in catalog"

def testOpenCodeCatalogMaxTokensCompat : IO Unit := do
  let catalog := LeanAgent.Models.defaultCatalog
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.opencodeProviderId "big-pickle" with
  | some model =>
      assertTrue (model.compat.maxTokensField == "max_tokens")
        "expected OpenCode big-pickle max_tokens compat metadata"
      assertTrue model.compat.maxTokensFieldExplicit
        "expected OpenCode big-pickle explicit max_tokens override"
  | none => fail "expected OpenCode big-pickle model"
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.opencodeProviderId "kimi-k2.6" with
  | some model =>
      assertTrue (model.compat.maxTokensField == "max_tokens")
        "expected OpenCode Kimi K2.6 max_tokens compat metadata"
      assertTrue (!model.compat.supportsLongCacheRetention)
        "expected OpenCode Kimi K2.6 long-cache suppression"
  | none => fail "expected OpenCode Kimi K2.6 model"
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.opencodeGoProviderId "glm-5.2" with
  | some model =>
      assertTrue (model.compat.maxTokensField == "max_tokens")
        "expected OpenCode Go GLM-5.2 max_tokens compat metadata"
  | none => fail "expected OpenCode Go GLM-5.2 model"
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.opencodeGoProviderId "qwen3.6-plus" with
  | some model =>
      assertTrue (model.compat.maxTokensField == "max_tokens")
        "expected OpenCode Go Qwen3.6 Plus max_tokens compat metadata"
      assertTrue (model.compat.thinkingFormat == some "qwen")
        "expected OpenCode Go Qwen3.6 Plus qwen thinking compat"
  | none => fail "expected OpenCode Go Qwen3.6 Plus model"
  assertTrue (LeanAgent.Models.kimiCodingModels.size == 3) "expected generated Kimi Coding model catalog"
  assertTrue (LeanAgent.Models.minimaxModels.size == 3) "expected generated MiniMax model catalog"
  assertTrue (LeanAgent.Models.minimaxCNModels.size == 3) "expected generated MiniMax CN model catalog"
  assertTrue (LeanAgent.Models.vercelAIGatewayModels.size == 185)
    "expected generated Vercel AI Gateway model catalog"
  assertTrue (LeanAgent.Models.opencodeModels.size == 45)
    "expected generated OpenCode model catalog"
  assertTrue (LeanAgent.Models.opencodeGoModels.size == 13)
    "expected generated OpenCode Go model catalog"
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.antLingProviderId "Ring-2.6-1T" with
  | some model =>
      assertTrue model.reasoning "expected Ant Ling Ring reasoning metadata"
      assertTrue (!model.compat.supportsStore) "expected Ant Ling store compat metadata"
      assertTrue (!model.compat.supportsReasoningEffort) "expected Ant Ling reasoning-effort compat metadata"
      assertTrue (model.compat.maxTokensField == "max_tokens") "expected Ant Ling max_tokens compat metadata"
      assertTrue (!model.compat.supportsLongCacheRetention) "expected Ant Ling long-cache suppression"
      assertTrue ((LeanAgent.Models.thinkingLevelMapValue? model (.level .xhigh)) == some (some "xhigh"))
        "expected Ant Ling xhigh mapping"
  | none => fail "expected Ant Ling reasoning model"
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.openRouterProviderId "moonshotai/kimi-k2.6" with
  | some model =>
      assertTrue (!model.compat.supportsDeveloperRole)
        "expected OpenRouter Kimi K2.6 developer-role compat metadata"
      assertTrue model.compat.requiresReasoningContentOnAssistantMessages
        "expected OpenRouter Kimi K2.6 reasoning-content compat metadata"
      assertTrue (model.compat.thinkingFormat == some "openrouter")
        "expected OpenRouter Kimi K2.6 thinking format metadata"
  | none => fail "expected OpenRouter Kimi K2.6 model"
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.openRouterProviderId "moonshotai/kimi-k2.7-code" with
  | some model =>
      assertTrue (!model.compat.supportsDeveloperRole)
        "expected OpenRouter Kimi K2.7 Code developer-role compat metadata"
      assertTrue (!model.compat.requiresReasoningContentOnAssistantMessages)
        "expected OpenRouter Kimi K2.7 Code to omit reasoning-content replay requirement"
      assertTrue (model.compat.thinkingFormat == some "openrouter")
        "expected OpenRouter Kimi K2.7 Code thinking format metadata"
      assertTrue (model.maxTokens == 16384)
        "expected OpenRouter Kimi K2.7 Code output limit"
  | none => fail "expected OpenRouter Kimi K2.7 Code model"
  for providerId in
    #[ LeanAgent.Models.xiaomiProviderId
     , LeanAgent.Models.xiaomiTokenPlanAMSProviderId
     , LeanAgent.Models.xiaomiTokenPlanCNProviderId
     , LeanAgent.Models.xiaomiTokenPlanSGPProviderId
     ] do
    match LeanAgent.Models.ProviderCatalog.model? catalog providerId "mimo-v2.5-pro" with
    | some model =>
        assertTrue model.compat.requiresReasoningContentOnAssistantMessages
          "expected Xiaomi MiMo reasoning-content compat metadata"
        assertTrue (model.compat.thinkingFormat == some "deepseek")
          "expected Xiaomi MiMo deepseek thinking compat metadata"
        assertTrue (!model.compat.supportsDeveloperRole)
          "expected Xiaomi MiMo developer-role compat metadata"
    | none => fail s!"expected Xiaomi MiMo model for provider {providerId}"
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.zaiProviderId "glm-5.2" with
  | some model =>
      assertTrue model.compat.supportsReasoningEffort "expected Z.AI GLM-5.2 reasoning-effort compat"
      assertTrue model.compat.supportsReasoningEffortExplicit
        "expected Z.AI GLM-5.2 explicit reasoning-effort override"
      assertTrue model.compat.zaiToolStream "expected Z.AI GLM-5.2 tool-stream compat"
      assertTrue (LeanAgent.Models.thinkingLevelPayloadValueD model (.level .xhigh) "xhigh" == "max")
        "expected Z.AI xhigh mapping"
      assertTrue (!((LeanAgent.Models.getSupportedThinkingLevels model).contains (.level .minimal)))
        "expected Z.AI minimal reasoning to be suppressed"
  | none => fail "expected Z.AI reasoning model"
  match LeanAgent.Models.ProviderCatalog.model? catalog LeanAgent.Models.zaiProviderId "glm-5.1" with
  | some model =>
      assertTrue (!model.compat.supportsReasoningEffort)
        "expected Z.AI GLM-5.1 to disable reasoning_effort"
  | none => fail "expected Z.AI GLM-5.1 model"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.anthropicOAuthTokenEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.anthropicProviderId) "expected Anthropic OAuth token env"
  | none => fail "expected Anthropic OAuth token env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.antLingApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.antLingProviderId) "expected Ant Ling provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.antLingDefaultModel) "expected Ant Ling default model"
  | none => fail "expected Ant Ling provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.moonshotAIApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.moonshotAIProviderId)
        "expected Moonshot AI provider to own shared env lookup"
      assertTrue (provider.defaultModel == LeanAgent.Models.moonshotAIDefaultModel)
        "expected Moonshot AI default model"
  | none => fail "expected Moonshot AI provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.zaiCodingCNApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.zaiCodingCNProviderId) "expected Z.AI Coding CN provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.zaiCodingCNDefaultModel)
        "expected Z.AI Coding CN default model"
  | none => fail "expected Z.AI Coding CN provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.kimiCodingApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.kimiCodingProviderId) "expected Kimi Coding provider by env"
      assertTrue (provider.headers == LeanAgent.Models.kimiCodingHeaders)
        "expected Kimi Coding provider headers"
  | none => fail "expected Kimi Coding provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.minimaxCNApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.minimaxCNProviderId) "expected MiniMax CN provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.minimaxCNDefaultModel)
        "expected MiniMax CN default model"
  | none => fail "expected MiniMax CN provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.vercelAIGatewayApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.vercelAIGatewayProviderId)
        "expected Vercel AI Gateway provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.vercelAIGatewayDefaultModel)
        "expected Vercel AI Gateway default model"
  | none => fail "expected Vercel AI Gateway provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.opencodeApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.opencodeProviderId)
        "expected OpenCode provider by shared env"
      assertTrue (provider.defaultModel == LeanAgent.Models.opencodeDefaultModel)
        "expected OpenCode default model"
  | none => fail "expected OpenCode provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.googleApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.googleProviderId) "expected Google provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.googleDefaultModel) "expected Google default model"
  | none => fail "expected Google provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.googleVertexApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.googleVertexProviderId) "expected Google Vertex provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.googleVertexDefaultModel)
        "expected Google Vertex default model"
  | none => fail "expected Google Vertex provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.azureOpenAIResponsesApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.azureOpenAIResponsesProviderId)
        "expected Azure OpenAI Responses provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.azureOpenAIResponsesDefaultModel)
        "expected Azure OpenAI Responses default model"
  | none => fail "expected Azure OpenAI Responses provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.githubCopilotApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.githubCopilotProviderId)
        "expected GitHub Copilot provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.githubCopilotDefaultModel)
        "expected GitHub Copilot default model"
  | none => fail "expected GitHub Copilot provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog LeanAgent.Models.mistralApiKeyEnv with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.mistralProviderId) "expected Mistral provider by env"
      assertTrue (provider.defaultModel == LeanAgent.Models.mistralDefaultModel)
        "expected Mistral default model"
  | none => fail "expected Mistral provider by env"
  match LeanAgent.Models.ProviderCatalog.providerByApiKeyEnv? catalog "AWS_PROFILE" with
  | some provider =>
      assertTrue (provider.id == LeanAgent.Models.amazonBedrockProviderId) "expected Bedrock provider by AWS env"
      assertTrue (provider.defaultModel == LeanAgent.Models.amazonBedrockDefaultModel)
        "expected Bedrock default model"
  | none => fail "expected Bedrock provider by AWS env"

def testDefaultModelsRegistersOpenAICompatibleFamily : IO Unit := do
  let collection ← LeanAgent.AI.Providers.All.builtinModels
  let providers ← collection.getProviders
  assertTrue (providers.size == 35) "expected default provider family"
  match ← collection.getModel? LeanAgent.Models.openAIProviderId LeanAgent.Models.openAIDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-responses") "expected OpenAI Responses API"
      assertTrue (model.baseUrl == LeanAgent.Models.openAIBaseUrl) "expected OpenAI Responses base URL"
      assertTrue (model.input.contains "image") "expected OpenAI image input metadata"
  | none => fail "expected OpenAI Responses model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.openAICodexProviderId LeanAgent.Models.openAICodexDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.OpenAICodexResponses.api)
        "expected OpenAI Codex Responses API"
      assertTrue (model.baseUrl == LeanAgent.Models.openAICodexBaseUrl)
        "expected OpenAI Codex base URL"
      assertTrue (model.input.contains "image") "expected OpenAI Codex image input metadata"
  | none => fail "expected OpenAI Codex model in default runtime collection"
  match ← collection.getModel?
      LeanAgent.Models.azureOpenAIResponsesProviderId
      LeanAgent.Models.azureOpenAIResponsesDefaultModel with
  | some model =>
      assertTrue (model.api == "azure-openai-responses")
        "expected Azure OpenAI Responses API"
      assertTrue (model.baseUrl == LeanAgent.Models.azureOpenAIResponsesBaseUrl)
        "expected empty Azure base URL for env/resource resolution"
      assertTrue (model.input.contains "image") "expected Azure default model image metadata"
  | none => fail "expected Azure OpenAI Responses model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.openRouterProviderId LeanAgent.Models.openRouterDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-completions") "expected OpenRouter OpenAI-compatible API"
      assertTrue model.reasoning "expected OpenRouter reasoning metadata"
  | none => fail "expected OpenRouter model in default runtime collection"
  match ← collection.getModel?
      LeanAgent.Models.githubCopilotProviderId
      LeanAgent.Models.githubCopilotDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-responses") "expected GitHub Copilot Responses default model"
      assertTrue (model.baseUrl == LeanAgent.Models.githubCopilotBaseUrl)
        "expected GitHub Copilot default base URL"
      assertTrue
        (model.headers.any fun (name, value) =>
          name == "Copilot-Integration-Id" && value == "vscode-chat")
        "expected GitHub Copilot model headers"
  | none => fail "expected GitHub Copilot model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.fireworksProviderId LeanAgent.Models.fireworksDefaultModel with
  | some model =>
      assertTrue (model.baseUrl == LeanAgent.Models.fireworksBaseUrl) "expected Fireworks OpenAI-compatible base URL"
  | none => fail "expected Fireworks model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.huggingFaceProviderId "zai-org/GLM-5.2" with
  | some model =>
      assertTrue (model.api == "openai-completions") "expected Hugging Face OpenAI-compatible API"
      assertTrue (model.baseUrl == LeanAgent.Models.huggingFaceBaseUrl) "expected Hugging Face router base URL"
  | none => fail "expected Hugging Face model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.moonshotAIProviderId "kimi-k2.7-code" with
  | some model =>
      assertTrue (model.compat.thinkingFormat == some "deepseek") "expected Moonshot AI DeepSeek thinking compat"
      assertTrue (model.input.contains "image") "expected Moonshot AI image input metadata"
  | none => fail "expected Moonshot AI model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.nvidiaProviderId LeanAgent.Models.nvidiaDefaultModel with
  | some model =>
      assertTrue (model.baseUrl == LeanAgent.Models.nvidiaBaseUrl) "expected NVIDIA base URL"
      assertTrue (!model.compat.supportsStore) "expected NVIDIA store compat metadata"
      assertTrue
        (model.headers.findSome?
          (fun (name, value) =>
            if name.toLower == "nvcf-poll-seconds" then some value else none) == some "3600")
        "expected NVIDIA model-level poll header"
  | none => fail "expected NVIDIA model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.xiaomiProviderId "mimo-v2.5" with
  | some model =>
      assertTrue model.compat.requiresReasoningContentOnAssistantMessages
        "expected Xiaomi reasoning-content compat metadata"
      assertTrue (model.input.contains "image") "expected Xiaomi image input metadata"
  | none => fail "expected Xiaomi model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.zaiCodingCNProviderId "glm-5.2" with
  | some model =>
      assertTrue (model.compat.thinkingFormat == some "zai") "expected Z.AI Coding CN thinking compat"
      assertTrue model.compat.zaiToolStream "expected Z.AI Coding CN tool-stream compat"
      assertTrue (model.maxTokens == 131072) "expected Z.AI Coding CN max tokens"
  | none => fail "expected Z.AI Coding CN model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.kimiCodingProviderId LeanAgent.Models.kimiCodingDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.AnthropicMessages.api)
        "expected Kimi Coding Anthropic Messages API"
      assertTrue (model.input.contains "image") "expected Kimi Coding image input metadata"
  | none => fail "expected Kimi Coding model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.minimaxProviderId "MiniMax-M3" with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.AnthropicMessages.api)
        "expected MiniMax Anthropic Messages API"
      assertTrue (model.contextWindow == 512000) "expected MiniMax M3 context metadata"
  | none => fail "expected MiniMax model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.vercelAIGatewayProviderId "anthropic/claude-opus-4.7" with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.AnthropicMessages.api)
        "expected Vercel AI Gateway Anthropic Messages API"
      assertTrue model.compat.forceAdaptiveThinking
        "expected Vercel AI Gateway adaptive thinking compat"
      assertTrue (!model.compat.supportsTemperature)
        "expected Vercel AI Gateway temperature compat metadata"
      assertTrue ((LeanAgent.Models.thinkingLevelMapValue? model (.level .xhigh)) == some (some "xhigh"))
        "expected Vercel AI Gateway xhigh mapping"
  | none => fail "expected Vercel AI Gateway model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.opencodeProviderId "gpt-5" with
  | some model =>
      assertTrue (model.api == "openai-responses")
        "expected OpenCode Responses API"
      assertTrue (model.baseUrl == "https://opencode.ai/zen/v1")
        "expected OpenCode Responses base URL"
      assertTrue ((LeanAgent.Models.thinkingLevelMapValue? model .off) == some none)
        "expected OpenCode Responses off reasoning metadata"
  | none => fail "expected OpenCode Responses model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.opencodeProviderId "gemini-3.1-pro" with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.GoogleGenerativeAI.api)
        "expected OpenCode Google Generative AI API"
      assertTrue ((LeanAgent.Models.thinkingLevelMapValue? model (.level .low)) == some (some "LOW"))
        "expected OpenCode Gemini thinking metadata"
  | none => fail "expected OpenCode Gemini model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.opencodeProviderId "grok-build-0.1" with
  | some model =>
      assertTrue (!model.compat.supportsReasoningEffort)
        "expected OpenCode reasoning effort compat metadata"
      assertTrue (model.input.contains "image")
        "expected OpenCode image input metadata"
  | none => fail "expected OpenCode OpenAI-compatible model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.opencodeGoProviderId "minimax-m3" with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.AnthropicMessages.api)
        "expected OpenCode Go Anthropic Messages API"
      assertTrue (model.contextWindow == 512000)
        "expected OpenCode Go MiniMax context metadata"
  | none => fail "expected OpenCode Go Anthropic model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.anthropicProviderId LeanAgent.Models.anthropicDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.AnthropicMessages.api) "expected Anthropic Messages API"
      assertTrue model.reasoning "expected Anthropic reasoning metadata"
  | none => fail "expected Anthropic model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.googleProviderId LeanAgent.Models.googleDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.GoogleGenerativeAI.api) "expected Google Generative AI API"
      assertTrue model.reasoning "expected Google reasoning metadata"
      assertTrue (model.input.contains "image") "expected Google image input metadata"
  | none => fail "expected Google model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.googleVertexProviderId LeanAgent.Models.googleVertexDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.GoogleVertex.api) "expected Google Vertex API"
      assertTrue model.reasoning "expected Google Vertex reasoning metadata"
      assertTrue (model.baseUrl == LeanAgent.Models.googleVertexBaseUrl) "expected Google Vertex placeholder base URL"
  | none => fail "expected Google Vertex model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.mistralProviderId LeanAgent.Models.mistralDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.MistralConversations.api) "expected Mistral Conversations API"
      assertTrue (model.baseUrl == LeanAgent.Models.mistralBaseUrl) "expected Mistral base URL"
      assertTrue (model.maxTokens == 262144) "expected Mistral default max tokens"
  | none => fail "expected Mistral model in default runtime collection"
  match ← collection.getModel? LeanAgent.Models.amazonBedrockProviderId LeanAgent.Models.amazonBedrockDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.BedrockConverseStream.api) "expected Bedrock Converse API"
      assertTrue (model.baseUrl == LeanAgent.Models.amazonBedrockBaseUrl) "expected Bedrock base URL"
      assertTrue (model.maxTokens == 128000) "expected Bedrock default max tokens"
      assertTrue (model.input.contains "image") "expected Bedrock image input metadata"
  | none => fail "expected Bedrock model in default runtime collection"

def assertProviderFactoryMatchesInfo (mkProvider : IO LeanAgent.Models.Provider)
    (info : LeanAgent.Models.ProviderInfo) : IO Unit := do
  let provider ← mkProvider
  assertTrue (provider.id == info.id) s!"expected provider id {info.id}"
  assertTrue (provider.name == info.name) s!"expected provider name {info.name}"
  assertTrue (provider.headers == info.headers) s!"expected provider headers for {info.id}"
  let models ← provider.getModels
  assertTrue (models == info.models) s!"expected provider models for {info.id}"
  match provider.auth.apiKey with
  | some apiKeyAuth =>
      let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
      let ctx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun name =>
            pure (if name == info.apiKeyEnv then some "factory-key" else none)
          fileExists := fun _ => pure false
        }
      match ← LeanAgent.AI.Auth.resolveProviderAuth info.id { apiKey := some apiKeyAuth } store ctx with
      | some result =>
          assertTrue (result.auth.apiKey == some "factory-key") s!"expected auth for {info.id}"
          assertTrue (result.source == some info.apiKeyEnv) s!"expected auth env source for {info.id}"
      | none => fail s!"expected provider auth for {info.id}"
  | none => fail s!"expected api-key auth for {info.id}"

def assertOpenAICodexProviderFactoryMatchesInfo : IO Unit := do
  let provider ← LeanAgent.AI.Providers.OpenAICodex.provider
  let info := LeanAgent.Models.openAICodexProviderInfo
  assertTrue (provider.id == info.id) "expected OpenAI Codex provider id"
  assertTrue (provider.name == info.name) "expected OpenAI Codex provider name"
  let models ← provider.getModels
  assertTrue (models == info.models) "expected OpenAI Codex provider models"
  match provider.auth.oauth with
  | some _oauth =>
      let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
      let _ ← store.modify LeanAgent.Models.openAICodexProviderId fun _ =>
        pure
          (some
            (.oauth
              { access := fakeOpenAICodexJwt
                refresh := "refresh-token"
                expires := 2000
              }))
      let ctx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun _ => pure none
          fileExists := fun _ => pure false
          nowMs := pure 1000
        }
      match ← LeanAgent.AI.Auth.resolveProviderAuth provider.id provider.auth store ctx with
      | some result =>
          assertTrue (result.auth.apiKey == some fakeOpenAICodexJwt)
            "expected OpenAI Codex OAuth access token auth"
          assertTrue (result.source == some "OAuth") "expected OpenAI Codex OAuth source"
      | none => fail "expected OpenAI Codex OAuth auth"
  | none => fail "expected OpenAI Codex OAuth auth handler"

def assertAnthropicProviderFactoryMatchesInfo : IO Unit := do
  let provider ← LeanAgent.AI.Providers.Anthropic.provider
  let info := LeanAgent.Models.anthropicProviderInfo
  assertTrue (provider.id == info.id) "expected Anthropic provider id"
  assertTrue (provider.name == info.name) "expected Anthropic provider name"
  assertTrue (provider.baseUrl == some info.baseUrl) "expected Anthropic provider base URL"
  let models ← provider.getModels
  assertTrue (models == info.models) "expected Anthropic provider models"
  match provider.auth.apiKey with
  | some apiKeyAuth =>
      let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
      let envCtx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun name =>
            pure (if name == LeanAgent.Models.anthropicApiKeyEnv then some "anthropic-api-key" else none)
          fileExists := fun _ => pure false
        }
      match ← LeanAgent.AI.Auth.resolveProviderAuth provider.id { apiKey := some apiKeyAuth } store envCtx with
      | some result =>
          assertTrue (result.auth.apiKey == some "anthropic-api-key")
            "expected Anthropic env API key auth"
          assertTrue (result.source == some LeanAgent.Models.anthropicApiKeyEnv)
            "expected Anthropic env auth source"
      | none => fail "expected Anthropic env auth"
  | none => fail "expected Anthropic API key auth handler"
  match provider.auth.oauth with
  | some oauth =>
      let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
      let _ ← store.modify LeanAgent.Models.anthropicProviderId fun _ =>
        pure
          (some
            (.oauth
              { access := "sk-ant-oat-access-token"
                refresh := "anthropic-refresh-token"
                expires := 2000
              }))
      let ctx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun _ => pure none
          fileExists := fun _ => pure false
          nowMs := pure 1000
        }
      match ← LeanAgent.AI.Auth.resolveProviderAuth provider.id { oauth := some oauth } store ctx with
      | some result =>
          assertTrue (result.auth.apiKey == some "sk-ant-oat-access-token")
            "expected Anthropic OAuth access token auth"
          assertTrue (result.source == some "OAuth") "expected Anthropic OAuth source"
      | none => fail "expected Anthropic OAuth auth"
  | none => fail "expected Anthropic OAuth auth handler"

def assertGitHubCopilotProviderFactoryMatchesInfo : IO Unit := do
  let provider ← LeanAgent.AI.Providers.GitHubCopilot.provider
  let info := LeanAgent.Models.githubCopilotProviderInfo
  assertTrue (provider.id == info.id) "expected GitHub Copilot provider id"
  assertTrue (provider.name == info.name) "expected GitHub Copilot provider name"
  assertTrue (provider.baseUrl == some info.baseUrl) "expected GitHub Copilot provider base URL"
  assertTrue (provider.headers == info.headers) "expected GitHub Copilot provider headers"
  let models ← provider.getModels
  assertTrue (models == info.models) "expected GitHub Copilot provider models"
  match provider.auth.apiKey with
  | some apiKeyAuth =>
      let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
      let envCtx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun name =>
            pure (if name == LeanAgent.Models.githubCopilotApiKeyEnv then some "copilot-env-token" else none)
          fileExists := fun _ => pure false
        }
      match ← LeanAgent.AI.Auth.resolveProviderAuth provider.id { apiKey := some apiKeyAuth } store envCtx with
      | some result =>
          assertTrue (result.auth.apiKey == some "copilot-env-token")
            "expected GitHub Copilot env API key auth"
          assertTrue (result.source == some LeanAgent.Models.githubCopilotApiKeyEnv)
            "expected GitHub Copilot env auth source"
      | none => fail "expected GitHub Copilot env auth"
  | none => fail "expected GitHub Copilot API key auth handler"
  match provider.auth.oauth with
  | some oauth =>
      let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
      let _ ← store.modify LeanAgent.Models.githubCopilotProviderId fun _ =>
        pure
          (some
            (.oauth
              { access := "tid=test;exp=9999999999;proxy-ep=proxy.enterprise.githubcopilot.com;"
                refresh := "ghu_refresh_token"
                expires := 2000
                extra :=
                  #[ ( "availableModelIds"
                     , LeanAgent.Json.arr #[LeanAgent.Json.str LeanAgent.Models.githubCopilotDefaultModel] )
                   ]
              }))
      let ctx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun _ => pure none
          fileExists := fun _ => pure false
          nowMs := pure 1000
        }
      match ← LeanAgent.AI.Auth.resolveProviderAuth provider.id { oauth := some oauth } store ctx with
      | some result =>
          assertTrue
            (result.auth.apiKey ==
              some "tid=test;exp=9999999999;proxy-ep=proxy.enterprise.githubcopilot.com;")
            "expected GitHub Copilot OAuth access token auth"
          assertTrue (result.auth.baseUrl == some "https://api.enterprise.githubcopilot.com")
            "expected GitHub Copilot OAuth base URL rewrite"
          assertTrue
            (result.auth.allowedModelIds == some #[LeanAgent.Models.githubCopilotDefaultModel])
            "expected GitHub Copilot OAuth allowed model ids"
          assertTrue (result.source == some "OAuth") "expected GitHub Copilot OAuth source"
      | none => fail "expected GitHub Copilot OAuth auth"
  | none => fail "expected GitHub Copilot OAuth auth handler"

def testBuiltinModelsGitHubCopilotOAuthFiltersModelList : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let credential : LeanAgent.AI.Auth.OAuthCredential :=
    { access := "tid=test;exp=9999999999;proxy-ep=proxy.enterprise.githubcopilot.com;"
      refresh := "ghu_refresh_token"
      expires := 2000
      extra :=
        #[ ( "availableModelIds"
           , LeanAgent.Json.arr #[LeanAgent.Json.str LeanAgent.Models.githubCopilotDefaultModel] )
         ]
    }
  let _ ← store.modify LeanAgent.Models.githubCopilotProviderId fun _ =>
    pure (some (.oauth credential))
  let collection ← LeanAgent.AI.Providers.All.builtinModels
    (some store)
    { env := fun _ => pure none
      fileExists := fun _ => pure false
      nowMs := pure 1000
    }
  let models ← collection.getModels (some LeanAgent.Models.githubCopilotProviderId)
  let expected := LeanAgent.AI.OAuth.GitHubCopilot.modifyModels LeanAgent.Models.githubCopilotModels credential
  assertTrue (models == expected)
    "expected builtin models collection to apply GitHub Copilot OAuth model filtering"
  assertTrue (models.size == 1)
    "expected GitHub Copilot OAuth availableModelIds to filter the model list"
  match models[0]? with
  | some model =>
      assertTrue (model.id == LeanAgent.Models.githubCopilotDefaultModel)
        "expected GitHub Copilot OAuth filtered default model"
      assertTrue (model.baseUrl == "https://api.enterprise.githubcopilot.com")
        "expected GitHub Copilot OAuth filtered model base URL rewrite"
  | none => fail "expected filtered GitHub Copilot model"

def testDefaultModelsGitHubCopilotOAuthFiltersModelList : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let credential : LeanAgent.AI.Auth.OAuthCredential :=
    { access := "tid=test;exp=9999999999;proxy-ep=proxy.enterprise.githubcopilot.com;"
      refresh := "ghu_refresh_token"
      expires := 2000
      extra :=
        #[ ( "availableModelIds"
           , LeanAgent.Json.arr #[LeanAgent.Json.str LeanAgent.Models.githubCopilotDefaultModel] )
         ]
    }
  let _ ← store.modify LeanAgent.Models.githubCopilotProviderId fun _ =>
    pure (some (.oauth credential))
  let collection ← LeanAgent.AI.Providers.All.builtinModels
    (some store)
    { env := fun _ => pure none
      fileExists := fun _ => pure false
      nowMs := pure 1000
    }
  let models ← collection.getModels (some LeanAgent.Models.githubCopilotProviderId)
  let expected := LeanAgent.AI.OAuth.GitHubCopilot.modifyModels LeanAgent.Models.githubCopilotModels credential
  assertTrue (models == expected)
    "expected default models collection to apply GitHub Copilot OAuth model filtering"
  assertTrue (models.size == 1)
    "expected default models collection to filter GitHub Copilot models by availableModelIds"
  match ← collection.getModel?
      LeanAgent.Models.githubCopilotProviderId
      LeanAgent.Models.githubCopilotDefaultModel with
  | some model =>
      assertTrue (model.baseUrl == "https://api.enterprise.githubcopilot.com")
        "expected default models collection GitHub Copilot model base URL rewrite"
  | none => fail "expected default models collection GitHub Copilot default model"

def assertAmazonBedrockProviderFactoryMatchesInfo : IO Unit := do
  let provider ← LeanAgent.AI.Providers.AmazonBedrock.provider
  let info := LeanAgent.Models.amazonBedrockProviderInfo
  assertTrue (provider.id == info.id) "expected Bedrock provider id"
  assertTrue (provider.name == info.name) "expected Bedrock provider name"
  let models ← provider.getModels
  assertTrue (models == info.models) "expected Bedrock provider models"
  match provider.auth.apiKey with
  | some apiKeyAuth =>
      let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
      let ambientCtx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun name => pure (if name == "AWS_PROFILE" then some "dev" else none)
          fileExists := fun _ => pure false
        }
      match ← LeanAgent.AI.Auth.resolveProviderAuth provider.id { apiKey := some apiKeyAuth } store ambientCtx with
      | some result =>
          assertTrue result.auth.apiKey.isNone "expected ambient Bedrock auth to avoid bearer key"
          assertTrue (result.source == some "AWS_PROFILE") "expected Bedrock AWS_PROFILE source"
      | none => fail "expected Bedrock ambient auth"
      let _ ← store.modify LeanAgent.Models.amazonBedrockProviderId fun _ =>
        pure (some (.apiKey { key := some "bedrock-bearer" }))
      let emptyCtx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun _ => pure none
          fileExists := fun _ => pure false
        }
      match ← LeanAgent.AI.Auth.resolveProviderAuth provider.id { apiKey := some apiKeyAuth } store emptyCtx with
      | some result =>
          assertTrue (result.auth.apiKey == some "bedrock-bearer") "expected stored Bedrock bearer token"
          assertTrue (result.source == some "stored credential") "expected stored Bedrock source"
      | none => fail "expected stored Bedrock auth"
  | none => fail "expected Bedrock API key auth handler"

def testOpenAICompatibleProviderFactoriesMatchCatalog : IO Unit := do
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.DeepSeek.provider LeanAgent.Models.deepSeekProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.OpenAI.provider LeanAgent.Models.openAIProviderInfo
  assertOpenAICodexProviderFactoryMatchesInfo
  assertGitHubCopilotProviderFactoryMatchesInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.AzureOpenAIResponses.provider LeanAgent.Models.azureOpenAIResponsesProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.OpenRouter.provider LeanAgent.Models.openRouterProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.Groq.provider LeanAgent.Models.groqProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.XAI.provider LeanAgent.Models.xaiProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.Cerebras.provider LeanAgent.Models.cerebrasProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.Together.provider LeanAgent.Models.togetherProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.Fireworks.provider LeanAgent.Models.fireworksProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.AntLing.provider LeanAgent.Models.antLingProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.HuggingFace.provider LeanAgent.Models.huggingFaceProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.MoonshotAI.provider LeanAgent.Models.moonshotAIProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.MoonshotAICN.provider LeanAgent.Models.moonshotAICNProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.NVIDIA.provider LeanAgent.Models.nvidiaProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.Xiaomi.provider LeanAgent.Models.xiaomiProviderInfo
  assertProviderFactoryMatchesInfo
    LeanAgent.AI.Providers.XiaomiTokenPlanAMS.provider
    LeanAgent.Models.xiaomiTokenPlanAMSProviderInfo
  assertProviderFactoryMatchesInfo
    LeanAgent.AI.Providers.XiaomiTokenPlanCN.provider
    LeanAgent.Models.xiaomiTokenPlanCNProviderInfo
  assertProviderFactoryMatchesInfo
    LeanAgent.AI.Providers.XiaomiTokenPlanSGP.provider
    LeanAgent.Models.xiaomiTokenPlanSGPProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.ZAI.provider LeanAgent.Models.zaiProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.ZAICodingCN.provider LeanAgent.Models.zaiCodingCNProviderInfo
  assertAnthropicProviderFactoryMatchesInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.KimiCoding.provider LeanAgent.Models.kimiCodingProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.MiniMax.provider LeanAgent.Models.minimaxProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.MiniMaxCN.provider LeanAgent.Models.minimaxCNProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.VercelAIGateway.provider LeanAgent.Models.vercelAIGatewayProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.OpenCode.provider LeanAgent.Models.opencodeProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.OpenCodeGo.provider LeanAgent.Models.opencodeGoProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.Google.provider LeanAgent.Models.googleProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.GoogleVertex.provider LeanAgent.Models.googleVertexProviderInfo
  assertProviderFactoryMatchesInfo LeanAgent.AI.Providers.Mistral.provider LeanAgent.Models.mistralProviderInfo
  assertAmazonBedrockProviderFactoryMatchesInfo

def testLegacySelectionRejectsAnthropicProvider : IO Unit := do
  match ← LeanAgent.Models.resolveSelection { apiKeyEnv := some LeanAgent.Models.anthropicApiKeyEnv } with
  | .ok _ => fail "expected legacy CLI selection to reject Anthropic"
  | .error err =>
      assertTrue (err.contains "legacy CLI path currently supports only openai-completions")
        "expected unsupported provider API error"
  match ← LeanAgent.Models.resolveSelection { apiKeyEnv := some LeanAgent.Models.googleApiKeyEnv } with
  | .ok _ => fail "expected legacy CLI selection to reject Google"
  | .error err =>
      assertTrue (err.contains "legacy CLI path currently supports only openai-completions")
        "expected unsupported Google provider API error"
  match ← LeanAgent.Models.resolveSelection { apiKeyEnv := some LeanAgent.Models.azureOpenAIResponsesApiKeyEnv } with
  | .ok _ => fail "expected legacy CLI selection to reject Azure OpenAI Responses"
  | .error err =>
      assertTrue (err.contains "legacy CLI path currently supports only openai-completions")
        "expected unsupported Azure OpenAI Responses provider API error"
  match ← LeanAgent.Models.resolveSelection { apiKeyEnv := some LeanAgent.Models.googleVertexApiKeyEnv } with
  | .ok _ => fail "expected legacy CLI selection to reject Google Vertex"
  | .error err =>
      assertTrue (err.contains "legacy CLI path currently supports only openai-completions")
        "expected unsupported Google Vertex provider API error"
  match ← LeanAgent.Models.resolveSelection { apiKeyEnv := some LeanAgent.Models.mistralApiKeyEnv } with
  | .ok _ => fail "expected legacy CLI selection to reject Mistral"
  | .error err =>
      assertTrue (err.contains "legacy CLI path currently supports only openai-completions")
        "expected unsupported Mistral provider API error"

def fakeAuthContext : LeanAgent.AI.Auth.AuthContext :=
  { env := fun name =>
      pure
        (if name == "FAKE_API_KEY" then
          some "env-secret"
        else
          none)
    fileExists := fun _ => pure false
  }

def testAuthDefaultContextEnvAndExpandHomePath : IO Unit := do
  let ctx := LeanAgent.AI.Auth.defaultProviderAuthContext
  match ← IO.getEnv "HOME" with
  | some home =>
      let trimmedHome := home.trimAscii.toString
      let envHome ← ctx.env "HOME"
      if trimmedHome.isEmpty then
        assertTrue envHome.isNone "expected empty HOME env to be suppressed"
      else
        assertTrue (envHome == some trimmedHome) "expected default auth context to read trimmed env vars"
      let slashHomePath ← LeanAgent.AI.Auth.expandHomePath "~/test"
      assertTrue (slashHomePath.toString == home ++ "/test")
        "expected expandHomePath to resolve ~/ to HOME dir"
      let bareHomePath ← LeanAgent.AI.Auth.expandHomePath "~test"
      assertTrue (bareHomePath.toString == home ++ "test")
        "expected expandHomePath to match Pi's leading-~ replacement"
  | none =>
      let bareHomePath ← LeanAgent.AI.Auth.expandHomePath "~test"
      assertTrue (bareHomePath.toString == "~test")
        "expected expandHomePath to preserve ~ without HOME"
  let explicitPath ← LeanAgent.AI.Auth.expandHomePath "/tmp/explicit"
  assertTrue (explicitPath.toString == "/tmp/explicit")
    "expected expandHomePath to preserve absolute non-home paths"
  IO.FS.withTempDir fun root => do
    let existing := root / "auth-context.txt"
    IO.FS.writeFile existing "ok"
    assertTrue (← ctx.fileExists existing.toString)
      "expected default auth context to find existing files"
    let missingExists ← ctx.fileExists (root / "missing.txt").toString
    assertTrue (!missingExists)
      "expected default auth context to return false for missing files"

def fakeProviderAuth : LeanAgent.AI.Auth.ProviderAuth :=
  { apiKey := some (LeanAgent.AI.Auth.envApiKeyAuth "Fake API key" #["FAKE_API_KEY"]) }

def fakeAuthContextWithNow (now : Nat) : LeanAgent.AI.Auth.AuthContext :=
  { fakeAuthContext with nowMs := pure now }

def oauthExtraString? (credential : LeanAgent.AI.Auth.OAuthCredential) (name : String) : Option String :=
  credential.extra.findSome? fun (field, value) =>
    if field == name then value.getStr?.toOption else none

def fakeOAuthAuth (refreshCalls : IO.Ref Nat) : LeanAgent.AI.Auth.OAuthAuth :=
  { name := "Fake OAuth"
    login := fun _ =>
      pure
        { access := "oauth-login-token"
          refresh := "oauth-login-refresh"
          expires := 3000
        }
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

def testEnvApiKeyAuthLoginPromptsForSecret : IO Unit := do
  let sawSecretPrompt ← IO.mkRef false
  let sawSignal ← IO.mkRef false
  let auth := LeanAgent.AI.Auth.envApiKeyAuth "Fake API key" #["FAKE_API_KEY"]
  match auth.login with
  | some login =>
      let credential ← login
        { prompt := fun prompt =>
            match prompt with
            | .secret message placeholder signal => do
                sawSecretPrompt.set
                  (message == "Enter Fake API key" && placeholder.isNone)
                sawSignal.set signal.isSome
                pure "typed-secret"
            | _ => throw (IO.userError "expected secret auth prompt")
          notify := fun _ => fail "unexpected auth event during API-key login"
          signal := some { isAborted := pure false }
        }
      assertTrue (credential.key == some "typed-secret")
        "expected envApiKeyAuth login to return prompted key"
      assertTrue (credential.env.isEmpty)
        "expected envApiKeyAuth login to avoid provider env by default"
      assertTrue (← sawSecretPrompt.get)
        "expected envApiKeyAuth login to request a secret prompt"
      assertTrue (← sawSignal.get)
        "expected envApiKeyAuth login to forward the login abort signal"
  | none => fail "expected envApiKeyAuth login handler"

def testLazyOAuthLoadsOnceAndDelegates : IO Unit := do
  let loadCalls ← IO.mkRef 0
  let loginCalls ← IO.mkRef 0
  let refreshCalls ← IO.mkRef 0
  let toAuthCalls ← IO.mkRef 0
  let progressMessages ← IO.mkRef (#[] : Array String)
  let sawPromptSignal ← IO.mkRef false
  let loaded : LeanAgent.AI.Auth.OAuthAuth :=
    { name := "Loaded OAuth"
      login := fun callbacks => do
        loginCalls.modify (· + 1)
        callbacks.notify (.progress "Loaded lazy OAuth login")
        let prompted ← callbacks.prompt (.text "Loaded login prompt" (some "lazy-token") callbacks.signal)
        pure
          { access := prompted
            refresh := "login-refresh"
            expires := 3000
          }
      refresh := fun credential => do
        refreshCalls.modify (· + 1)
        pure { credential with access := credential.access ++ "-refreshed" }
      toAuth := fun credential => do
        toAuthCalls.modify (· + 1)
        pure { apiKey := some credential.access, baseUrl := some "https://lazy-oauth.test" }
    }
  let lazy ← LeanAgent.AI.Auth.lazyOAuth
    { name := "Lazy OAuth"
      load := do
        loadCalls.modify (· + 1)
        pure loaded
    }
  assertTrue (lazy.name == "Lazy OAuth") "expected lazy OAuth wrapper name"
  let refreshed ← lazy.refresh { access := "old-token", refresh := "refresh-token", expires := 1 }
  assertTrue (refreshed.access == "old-token-refreshed") "expected lazy OAuth refresh delegation"
  let auth ← lazy.toAuth refreshed
  assertTrue (auth.apiKey == some "old-token-refreshed") "expected lazy OAuth toAuth delegation"
  assertTrue (auth.baseUrl == some "https://lazy-oauth.test") "expected lazy OAuth auth base URL"
  let credential ← lazy.login
    { prompt := fun prompt =>
        match prompt with
        | .text message placeholder signal => do
            sawPromptSignal.set signal.isSome
            assertTrue (message == "Loaded login prompt")
              "expected lazy OAuth login prompt message"
            assertTrue (placeholder == some "lazy-token")
              "expected lazy OAuth login prompt placeholder"
            pure "login-token"
        | _ => throw (IO.userError "expected text prompt during lazy OAuth login")
      notify := fun event =>
        match event with
        | .progress message =>
            progressMessages.modify (·.push message)
        | _ => fail "unexpected non-progress event during lazy OAuth login"
      signal := some { isAborted := pure false }
    }
  assertTrue (credential.access == "login-token") "expected lazy OAuth login delegation"
  let progress ← progressMessages.get
  assertTrue (progress == #["Loaded lazy OAuth login"])
    "expected lazy OAuth login to forward notifications"
  assertTrue (← sawPromptSignal.get)
    "expected lazy OAuth login to forward the login abort signal"
  assertTrue ((← loadCalls.get) == 1) "expected lazy OAuth to load exactly once"
  assertTrue ((← refreshCalls.get) == 1) "expected lazy OAuth refresh to run once"
  assertTrue ((← toAuthCalls.get) == 1) "expected lazy OAuth toAuth to run once"
  assertTrue ((← loginCalls.get) == 1) "expected lazy OAuth login to run once"

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

def testFileCredentialStoreWaitsForExternalLock : IO Unit :=
  IO.FS.withTempDir fun root => do
    let path := root / "auth.json"
    let lockPath := LeanAgent.AI.Auth.FileCredentialStore.lockPath path
    match lockPath.parent with
    | some parent => IO.FS.createDirAll parent
    | none => pure ()
    let releaseScript := String.intercalate "\n"
      [ "import os"
      , "import sys"
      , "import time"
      , "path = sys.argv[1]"
      , "os.mkdir(path)"
      , "time.sleep(0.35)"
      , "os.rmdir(path)"
      ]
    let child ← IO.Process.spawn
      { cmd := "python3"
        args := #["-c", releaseScript, lockPath.toString]
        stdin := .null
        stdout := .null
        stderr := .inherit
      }
    let store ← LeanAgent.AI.Auth.FileCredentialStore.mk path
    try
      let mut lockReady := false
      for _ in [0:100] do
        if !lockReady then
          if ← lockPath.pathExists then
            lockReady := true
          else
            IO.sleep 10
      if !lockReady then
        throw (IO.userError "external lock helper did not create lock directory")
      let start ← IO.monoMsNow
      let _ ← store.modify "fake" fun _ =>
        pure (some (.apiKey { key := some "locked-secret" }))
      let elapsed := (← IO.monoMsNow) - start
      let exitCode ← child.wait
      assertTrue (exitCode == 0) "expected external lock helper to exit cleanly"
      assertTrue (elapsed >= 250) "expected file credential store to wait for external lock release"
      match ← store.read "fake" with
      | some (.apiKey credential) =>
          assertTrue (credential.key == some "locked-secret") "expected locked write to persist"
      | _ => fail "expected locked file credential write to succeed"
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

def testModelsAuthOAuthConcurrentRefreshesSerialize : IO Unit := do
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
  let oauth : LeanAgent.AI.Auth.OAuthAuth :=
    { name := "Concurrent OAuth"
      login := fun _ => throw (IO.userError "unexpected concurrent OAuth login")
      refresh := fun credential => do
        refreshCalls.modify (· + 1)
        IO.sleep 200
        pure
          { credential with
            access := "concurrent-refreshed-token"
            refresh := "refresh-2"
            expires := 2000
          }
      toAuth := fun credential =>
        pure { apiKey := some credential.access }
    }
  let auth := { fakeProviderAuth with oauth := some oauth }
  let firstTask ←
    IO.asTask
      (LeanAgent.AI.Auth.resolveProviderAuth "fake" auth store (fakeAuthContextWithNow 1000))
  let secondTask ←
    IO.asTask
      (LeanAgent.AI.Auth.resolveProviderAuth "fake" auth store (fakeAuthContextWithNow 1000))
  let first ←
    match ← IO.wait firstTask with
    | .ok result => pure result
    | .error err => throw err
  let second ←
    match ← IO.wait secondTask with
    | .ok result => pure result
    | .error err => throw err
  match first, second with
  | some firstResult, some secondResult =>
      assertTrue (firstResult.auth.apiKey == some "concurrent-refreshed-token")
        "expected first concurrent OAuth request to see the refreshed token"
      assertTrue (secondResult.auth.apiKey == some "concurrent-refreshed-token")
        "expected second concurrent OAuth request to reuse the refreshed token"
  | _, _ => fail "expected concurrent OAuth refreshes to resolve auth"
  assertTrue ((← refreshCalls.get) == 1)
    "expected concurrent OAuth refreshes to serialize to a single refresh"
  match ← store.read "fake" with
  | some (.oauth credential) =>
      assertTrue (credential.access == "concurrent-refreshed-token")
        "expected serialized OAuth refresh to persist the refreshed token"
  | _ => fail "expected serialized concurrent refresh to persist OAuth credential"

def testModelsAuthOAuthRefreshFailureUsesModelsErrorOauth : IO Unit := do
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
  let failingOAuth : LeanAgent.AI.Auth.OAuthAuth :=
    { name := "Failing OAuth"
      login := fun _ => throw (IO.userError "unexpected failing OAuth login")
      refresh := fun _ => do
        refreshCalls.modify (· + 1)
        throw (IO.userError "refresh failed")
      toAuth := fun credential => pure { apiKey := some credential.access }
    }
  let failed ←
    try
      let _ ← LeanAgent.AI.Auth.resolveProviderAuth
        "fake"
        { fakeProviderAuth with oauth := some failingOAuth }
        store
        (fakeAuthContextWithNow 1000)
      pure false
    catch err =>
      assertTrue (err.toString.contains "ModelsError(oauth)")
        "expected typed oauth models error"
      assertTrue (err.toString.contains "OAuth refresh failed for fake")
        "expected refresh failure details"
      pure true
  assertTrue failed "expected OAuth refresh failure to throw"
  assertTrue ((← refreshCalls.get) == 1) "expected one failing OAuth refresh attempt"

def testModelsAuthReadFailureUsesModelsErrorAuth : IO Unit := do
  let store : LeanAgent.AI.Auth.CredentialStore :=
    { read := fun _ => throw (IO.userError "read failed")
      modify := fun _ _ => pure none
      delete := fun _ => pure ()
    }
  let failed ←
    try
      let _ ← LeanAgent.AI.Auth.resolveProviderAuth "fake" fakeProviderAuth store fakeAuthContext
      pure false
    catch err =>
      assertTrue (err.toString.contains "ModelsError(auth)")
        "expected typed auth error for credential store read failure"
      assertTrue (err.toString.contains "Credential store read failed for fake")
        "expected credential store read failure details"
      pure true
  assertTrue failed "expected credential store read failure to throw"

def testModelsAuthApiKeyFailureUsesModelsErrorAuth : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let failingAuth : LeanAgent.AI.Auth.ProviderAuth :=
    { apiKey :=
        some
          { name := "Failing API key"
            resolve := fun _ _ _ => throw (IO.userError "resolve failed")
          }
    }
  let failed ←
    try
      let _ ← LeanAgent.AI.Auth.resolveProviderAuth "fake" failingAuth store fakeAuthContext
      pure false
    catch err =>
      assertTrue (err.toString.contains "ModelsError(auth)")
        "expected typed auth error for API key resolution failure"
      assertTrue (err.toString.contains "API key auth failed for provider fake")
        "expected API key resolution failure details"
      pure true
  assertTrue failed "expected API key resolution failure to throw"

def testModelsAuthOAuthModifyFailureUsesModelsErrorAuth : IO Unit := do
  let store : LeanAgent.AI.Auth.CredentialStore :=
    { read := fun _ =>
        pure
          (some
            (.oauth
              { access := "expired-token"
                refresh := "refresh-1"
                expires := 999
              }))
      modify := fun _ _ => throw (IO.userError "modify failed")
      delete := fun _ => pure ()
    }
  let auth := { fakeProviderAuth with oauth := some (fakeOAuthAuth (← IO.mkRef 0)) }
  let failed ←
    try
      let _ ← LeanAgent.AI.Auth.resolveProviderAuth "fake" auth store (fakeAuthContextWithNow 1000)
      pure false
    catch err =>
      assertTrue (err.toString.contains "ModelsError(auth)")
        "expected typed auth error for credential store modify failure"
      assertTrue (err.toString.contains "Credential store modify failed for fake")
        "expected credential store modify failure details"
      pure true
  assertTrue failed "expected credential store modify failure to throw"

def testModelsAuthOAuthToAuthFailureUsesModelsErrorOauth : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let _ ← store.modify "fake" fun _ =>
    pure
      (some
        (.oauth
          { access := "oauth-access"
            refresh := "oauth-refresh"
            expires := 2000
          }))
  let failingOAuth : LeanAgent.AI.Auth.OAuthAuth :=
    { name := "Failing OAuth toAuth"
      login := fun _ => throw (IO.userError "unexpected failing OAuth login")
      refresh := fun credential => pure credential
      toAuth := fun _ => throw (IO.userError "toAuth failed")
    }
  let failed ←
    try
      let _ ← LeanAgent.AI.Auth.resolveProviderAuth
        "fake"
        { fakeProviderAuth with oauth := some failingOAuth }
        store
        (fakeAuthContextWithNow 1000)
      pure false
    catch err =>
      assertTrue (err.toString.contains "ModelsError(oauth)")
        "expected typed oauth error for toAuth failure"
      assertTrue (err.toString.contains "OAuth auth derivation failed for fake")
        "expected OAuth auth derivation failure details"
      pure true
  assertTrue failed "expected OAuth toAuth failure to throw"

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
    toAuth := fun credential => { apiKey := some ("Bearer " ++ credential.access) }
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
  let builtIns ← LeanAgent.AI.OAuth.getOAuthProviderInfoList
  assertTrue (builtIns.any (·.id == LeanAgent.AI.OAuth.Anthropic.providerId))
    "expected reset to keep Anthropic built-in OAuth provider"
  assertTrue (builtIns.any (·.id == LeanAgent.AI.OAuth.OpenAICodex.providerId))
    "expected reset to keep OpenAI Codex built-in OAuth provider"
  assertTrue (builtIns.any (·.id == LeanAgent.AI.OAuth.GitHubCopilot.providerId))
    "expected reset to keep GitHub Copilot built-in OAuth provider"

def testOAuthProviderRegistryReplacementPreservesOrder : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  let refreshA ← IO.mkRef 0
  let refreshB ← IO.mkRef 0
  let providerA := fakeOAuthProviderForRegistry "registry-order-a" "Registry Order A" refreshA
  let providerB := fakeOAuthProviderForRegistry "registry-order-b" "Registry Order B" refreshB
  let replacementA := fakeOAuthProviderForRegistry "registry-order-a" "Registry Order A Replaced" refreshA
  LeanAgent.AI.OAuth.registerOAuthProvider providerA
  LeanAgent.AI.OAuth.registerOAuthProvider providerB
  LeanAgent.AI.OAuth.registerOAuthProvider replacementA
  let customProviders :=
    (← LeanAgent.AI.OAuth.getOAuthProviders).filter (fun provider =>
      provider.id.startsWith "registry-order-")
  assertTrue ((customProviders.map (·.id)) == #["registry-order-a", "registry-order-b"])
    "expected OAuth provider replacement to preserve registration order"
  match ← LeanAgent.AI.OAuth.getOAuthProvider? "registry-order-a" with
  | some provider =>
      assertTrue (provider.name == "Registry Order A Replaced")
        "expected OAuth registry replacement to update the registered provider"
  | none => fail "expected replaced OAuth provider lookup"
  LeanAgent.AI.OAuth.resetOAuthProviders

def testModelsCollectionAppliesRegisteredOAuthModelHook : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  let refreshCalls ← IO.mkRef 0
  let providerId := "hooked-oauth"
  LeanAgent.AI.OAuth.registerOAuthProvider
    { fakeOAuthProviderForRegistry providerId "Hooked OAuth" refreshCalls with
      modifyModels := some fun models credential =>
        let keepModelId? := oauthExtraString? credential "keepModelId"
        let baseUrl? := oauthExtraString? credential "baseUrl"
        models.filterMap fun model =>
          if model.provider != providerId then
            some model
          else if keepModelId? == some model.id then
            some { model with baseUrl := baseUrl? }
          else
            none
    }
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let _ ← store.modify providerId fun _ =>
    pure
      (some
        (.oauth
          { access := "hook-token"
            refresh := "hook-refresh"
            expires := 2000
            extra :=
              #[ ("keepModelId", LeanAgent.Json.str "hook-model")
               , ("baseUrl", LeanAgent.Json.str "https://hooked-oauth.test")
               ]
          }))
  let provider ← LeanAgent.Models.createProvider
    { id := providerId
      name := some "Hooked OAuth Provider"
      auth := { apiKey := none, oauth := some (fakeOAuthAuth refreshCalls) }
      models :=
        #[ { id := "hook-model"
             name := "Hook Model"
             provider := providerId
             api := "openai-completions"
             baseUrl := "https://original.test"
           }
         , { id := "drop-model"
             name := "Drop Model"
             provider := providerId
             api := "openai-completions"
             baseUrl := "https://original.test"
           }
         ]
      apis := #[{ api := "openai-completions", streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams }]
    }
  let collection ← LeanAgent.Models.createModels (some store) (fakeAuthContextWithNow 1000)
  collection.setProvider provider
  let models ← collection.getModels (some providerId)
  assertTrue (models.size == 1)
    "expected registered OAuth model hook to filter the provider model list"
  match models[0]? with
  | some model =>
      assertTrue (model.id == "hook-model")
        "expected registered OAuth model hook to keep the selected model"
      assertTrue (model.baseUrl == "https://hooked-oauth.test")
        "expected registered OAuth model hook to rewrite the selected model base URL"
  | none => fail "expected hooked OAuth provider model"
  LeanAgent.AI.OAuth.resetOAuthProviders

def testOAuthStandaloneModuleImportBootstrapsBuiltIns : IO Unit := do
  let cwd ← IO.currentDir
  let entry := cwd / "OAuthOnlyImportMain.lean"
  let output ← IO.Process.output
    { cmd := "lake"
      args := #["env", "lean", "--run", entry.toString]
      stdin := .null
      stdout := .piped
      stderr := .piped
    }
  if output.exitCode != 0 then
    fail s!"expected standalone LeanAgent.AI.OAuth import to succeed: {output.stderr}"
  let rendered := output.stdout.trimAscii.toString
  assertTrue (rendered.contains LeanAgent.AI.OAuth.Anthropic.providerId)
    "expected standalone OAuth entrypoint import to include Anthropic built-in"
  assertTrue (rendered.contains LeanAgent.AI.OAuth.GitHubCopilot.providerId)
    "expected standalone OAuth entrypoint import to include GitHub Copilot built-in"
  assertTrue (rendered.contains LeanAgent.AI.OAuth.OpenAICodex.providerId)
    "expected standalone OAuth entrypoint import to include OpenAI Codex built-in"

def testCompatStandaloneModuleImportIncludesLegacyAliases : IO Unit := do
  let cwd ← IO.currentDir
  let entry := cwd / "CompatOnlyImportMain.lean"
  let output ← IO.Process.output
    { cmd := "lake"
      args := #["env", "lean", "--run", entry.toString]
      stdin := .null
      stdout := .piped
      stderr := .piped
    }
  if output.exitCode != 0 then
    fail s!"expected standalone LeanAgent.AI.Compat import to succeed: {output.stderr}"
  let rendered := output.stdout.trimAscii.toString
  assertTrue (rendered.contains "openai-responses")
    "expected standalone Compat entrypoint import to include built-in API providers"

def testAIStandaloneModuleImportIncludesCoreSurface : IO Unit := do
  let cwd ← IO.currentDir
  let entry := cwd / "AIOnlyImportMain.lean"
  let output ← IO.Process.output
    { cmd := "lake"
      args := #["env", "lean", "--run", entry.toString]
      stdin := .null
      stdout := .piped
      stderr := .piped
    }
  if output.exitCode != 0 then
    fail s!"expected standalone LeanAgent.AI import to succeed: {output.stderr}"
  let rendered := output.stdout.trimAscii.toString
  assertTrue (rendered == "ai-import-ok")
    "expected standalone AI barrel import to expose the core public surface"

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
      assertTrue (err.toString.contains "ModelsError(oauth)")
        "expected typed unknown OAuth provider error"
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
      assertTrue (err.toString.contains "ModelsError(oauth)")
        "expected typed refresh wrapper error"
      pure true
  assertTrue refreshFailed "failing OAuth refresh should fail"
  assertTrue ((← refreshCalls.get) == 1) "expected failed refresh to be attempted once"
  LeanAgent.AI.OAuth.resetOAuthProviders

def nextOAuthDeviceCodePoll
    (polls : IO.Ref (List (LeanAgent.AI.OAuth.OAuthDeviceCodePollResult String))) :
    IO (LeanAgent.AI.OAuth.OAuthDeviceCodePollResult String) := do
  match ← polls.get with
  | [] => throw (IO.userError "unexpected extra OAuth device-code poll")
  | result :: rest =>
      polls.set rest
      pure result

def fakeOAuthDeviceCodeSleep (nowRef : IO.Ref Nat) (sleepsRef : IO.Ref (Array Nat)) (ms : Nat) : IO Unit := do
  sleepsRef.modify (·.push ms)
  nowRef.modify (· + ms)

def testOAuthDeviceCodeCompletesAfterPending : IO Unit := do
  let polls ← IO.mkRef
    [ LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.pending
    , LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.complete "device-token"
    ]
  let nowRef ← IO.mkRef 0
  let sleepsRef ← IO.mkRef #[]
  let result ← LeanAgent.AI.OAuth.pollOAuthDeviceCodeFlow
    { poll := nextOAuthDeviceCodePoll polls
      nowMs := nowRef.get
      sleepMs := fakeOAuthDeviceCodeSleep nowRef sleepsRef
    }
  assertTrue (result == "device-token") "expected completed device-code token"
  assertTrue ((← sleepsRef.get) == #[5000]) "expected default 5s device-code polling interval"

def testOAuthDeviceCodeSlowDownIncreasesInterval : IO Unit := do
  let polls ← IO.mkRef
    [ LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.slowDown
    , LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.pending
    , LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.complete "device-token"
    ]
  let nowRef ← IO.mkRef 0
  let sleepsRef ← IO.mkRef #[]
  let result ← LeanAgent.AI.OAuth.pollOAuthDeviceCodeFlow
    { poll := nextOAuthDeviceCodePoll polls
      nowMs := nowRef.get
      sleepMs := fakeOAuthDeviceCodeSleep nowRef sleepsRef
    }
  assertTrue (result == "device-token") "expected completed device-code token after slow_down"
  assertTrue ((← sleepsRef.get) == #[10000, 10000])
    "expected slow_down to add 5s to current and later intervals"

def testOAuthDeviceCodeFailureAndCancellation : IO Unit := do
  let failedPolls ← IO.mkRef [LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.failed "authorization declined"]
  let failed ←
    try
      let _ ← LeanAgent.AI.OAuth.pollOAuthDeviceCodeFlow
        { poll := nextOAuthDeviceCodePoll failedPolls }
      pure false
    catch err =>
      assertTrue (err.toString.contains "authorization declined") "expected device-code failed message"
      pure true
  assertTrue failed "device-code failed poll should throw"
  let cancelPolls ← IO.mkRef [LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.complete "unused"]
  let cancelled ←
    try
      let _ ← LeanAgent.AI.OAuth.pollOAuthDeviceCodeFlow
        { poll := nextOAuthDeviceCodePoll cancelPolls
          isCancelled := pure true
        }
      pure false
    catch err =>
      assertTrue (err.toString.contains LeanAgent.AI.OAuth.cancelMessage)
        "expected device-code cancellation message"
      pure true
  assertTrue cancelled "cancelled device-code flow should throw before polling"

def testOAuthDeviceCodeSignalCancelsInFlightWait : IO Unit := do
  let polls ← IO.mkRef [LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.pending]
  let abortedRef ← IO.mkRef false
  let cancelled ←
    try
      let _ ← LeanAgent.AI.OAuth.pollOAuthDeviceCodeFlow
        { poll := nextOAuthDeviceCodePoll polls
          sleepMs := fun _ => abortedRef.set true
          signal := some { isAborted := abortedRef.get }
        }
      pure false
    catch err =>
      assertTrue (err.toString.contains LeanAgent.AI.OAuth.cancelMessage)
        "expected device-code signal cancellation message"
      pure true
  assertTrue cancelled "expected device-code signal to cancel an in-flight wait"
  assertTrue ((← polls.get) == []) "expected only the initial device-code poll before cancellation"

def testOAuthDeviceCodeTimeouts : IO Unit := do
  let timeoutPolls ← IO.mkRef [LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.pending]
  let nowRef ← IO.mkRef 0
  let sleepsRef ← IO.mkRef #[]
  let timedOut ←
    try
      let _ ← LeanAgent.AI.OAuth.pollOAuthDeviceCodeFlow
        { expiresInSeconds := some 1
          poll := nextOAuthDeviceCodePoll timeoutPolls
          nowMs := nowRef.get
          sleepMs := fakeOAuthDeviceCodeSleep nowRef sleepsRef
        }
      pure false
    catch err =>
      assertTrue (err.toString.contains LeanAgent.AI.OAuth.timeoutMessage)
        "expected device-code timeout message"
      pure true
  assertTrue timedOut "pending device-code flow should time out"
  assertTrue ((← sleepsRef.get) == #[1000]) "expected sleep to be capped by deadline"
  let slowDownPolls ← IO.mkRef [LeanAgent.AI.OAuth.OAuthDeviceCodePollResult.slowDown]
  let slowNowRef ← IO.mkRef 0
  let slowSleepsRef ← IO.mkRef #[]
  let slowTimedOut ←
    try
      let _ ← LeanAgent.AI.OAuth.pollOAuthDeviceCodeFlow
        { expiresInSeconds := some 1
          poll := nextOAuthDeviceCodePoll slowDownPolls
          nowMs := slowNowRef.get
          sleepMs := fakeOAuthDeviceCodeSleep slowNowRef slowSleepsRef
        }
      pure false
    catch err =>
      assertTrue (err.toString.contains "slow_down responses")
        "expected slow_down timeout message"
      pure true
  assertTrue slowTimedOut "slow_down device-code flow should time out with slow_down message"
  assertTrue ((← slowSleepsRef.get) == #[1000]) "expected slow_down sleep to be capped by deadline"

def testOAuthPageHtmlEscapesDynamicContent : IO Unit := do
  let html := LeanAgent.AI.OAuth.oauthErrorHtml
    "Use <code> & \"quoted\" 'input'"
    (some "token=<secret>&state='x'")
  assertTrue (html.contains "<title>Authentication failed</title>") "expected failed auth title"
  assertTrue (html.contains "<h1>Authentication failed</h1>") "expected failed auth heading"
  assertTrue
    (html.contains "Use &lt;code&gt; &amp; &quot;quoted&quot; &#39;input&#39;")
    "expected message HTML escaping"
  assertTrue
    (html.contains "token=&lt;secret&gt;&amp;state=&#39;x&#39;")
    "expected details HTML escaping"
  assertTrue (!html.contains "Use <code> & \"quoted\" 'input'")
    "expected raw message to be absent"

def testOAuthSuccessPageOmitsDetails : IO Unit := do
  let html := LeanAgent.AI.OAuth.oauthSuccessHtml "You can close this tab."
  assertTrue (html.contains "<title>Authentication successful</title>") "expected success auth title"
  assertTrue (html.contains "<h1>Authentication successful</h1>") "expected success auth heading"
  assertTrue (html.contains "<p>You can close this tab.</p>") "expected success message"
  assertTrue (!html.contains "class=\"details\"") "expected details block to be omitted"
  assertTrue (html.contains "class=\"logo\"") "expected Pi OAuth logo container"

def testOAuthPKCEChallengeMatchesRfcVector : IO Unit := do
  let verifier := "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  let challenge ← LeanAgent.AI.OAuth.PKCE.codeChallenge verifier
  assertTrue (challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    "expected RFC 7636 S256 code challenge"
  assertTrue (LeanAgent.AI.OAuth.PKCE.isBase64UrlNoPadding challenge)
    "expected challenge to be base64url without padding"

def testOAuthPKCEGenerateUsesBase64UrlVerifier : IO Unit := do
  let pkce ← LeanAgent.AI.OAuth.PKCE.generatePKCE
  assertTrue (pkce.verifier.length == 43) "expected 32 random bytes to produce 43-char verifier"
  assertTrue (pkce.challenge.length == 43) "expected SHA-256 digest to produce 43-char challenge"
  assertTrue (LeanAgent.AI.OAuth.PKCE.isBase64UrlNoPadding pkce.verifier)
    "expected verifier to be base64url without padding"
  assertTrue (LeanAgent.AI.OAuth.PKCE.isBase64UrlNoPadding pkce.challenge)
    "expected challenge to be base64url without padding"
  let recomputed ← LeanAgent.AI.OAuth.PKCE.codeChallenge pkce.verifier
  assertTrue (recomputed == pkce.challenge) "expected generated challenge to match verifier"

def testGitHubCopilotOAuthDomainAndBaseUrlHelpers : IO Unit := do
  assertTrue
    (LeanAgent.AI.OAuth.GitHubCopilot.normalizeDomain " https://Company.GHE.com/path?q=1 " ==
      some "company.ghe.com")
    "expected GitHub Enterprise URL normalization"
  assertTrue
    (LeanAgent.AI.OAuth.GitHubCopilot.normalizeDomain "company.ghe.com/org" ==
      some "company.ghe.com")
    "expected scheme-less GitHub Enterprise domain normalization"
  assertTrue
    (LeanAgent.AI.OAuth.GitHubCopilot.normalizeDomain "not a domain" == none)
    "expected invalid GitHub Enterprise domain to be rejected"
  let urls := LeanAgent.AI.OAuth.GitHubCopilot.urlsForDomain "github.com"
  assertTrue (urls.deviceCodeUrl == "https://github.com/login/device/code")
    "expected GitHub device-code URL"
  assertTrue (urls.accessTokenUrl == "https://github.com/login/oauth/access_token")
    "expected GitHub access-token URL"
  assertTrue (urls.copilotTokenUrl == "https://api.github.com/copilot_internal/v2/token")
    "expected GitHub Copilot token URL"
  let token := "tid=abc;proxy-ep=proxy.enterprise.githubcopilot.com;exp=123"
  assertTrue
    (LeanAgent.AI.OAuth.GitHubCopilot.baseUrlFromToken? token ==
      some "https://api.enterprise.githubcopilot.com")
    "expected proxy endpoint base URL extraction"
  assertTrue
    (LeanAgent.AI.OAuth.GitHubCopilot.getBaseUrl none (some "company.ghe.com") ==
      "https://copilot-api.company.ghe.com")
    "expected enterprise base URL fallback"
  assertTrue (LeanAgent.AI.OAuth.GitHubCopilot.getBaseUrl == LeanAgent.AI.OAuth.GitHubCopilot.defaultBaseUrl)
    "expected default individual Copilot base URL"

def selectableCopilotModelJson (id : String) (picker : Bool := true)
    (policyState : Option String := none) (toolCalls : Option Bool := none) : Lean.Json :=
  let policyFields :=
    match policyState with
    | some state => [("policy", LeanAgent.Json.obj [("state", LeanAgent.Json.str state)])]
    | none => []
  let supportsFields :=
    match toolCalls with
    | some value =>
        [ ("capabilities",
            LeanAgent.Json.obj
              [ ("supports", LeanAgent.Json.obj [("tool_calls", LeanAgent.Json.bool value)]) ]) ]
    | none => []
  LeanAgent.Json.obj
    ([ ("id", LeanAgent.Json.str id)
     , ("model_picker_enabled", LeanAgent.Json.bool picker)
     ] ++ policyFields ++ supportsFields)

def testGitHubCopilotOAuthParsesAvailableModels : IO Unit := do
  let raw := LeanAgent.Json.obj
    [ ("data",
        LeanAgent.Json.arr
          #[ selectableCopilotModelJson "enabled"
           , selectableCopilotModelJson "missing-supports"
           , selectableCopilotModelJson "disabled-policy" true (some "disabled")
           , selectableCopilotModelJson "disabled-tools" true none (some false)
           , selectableCopilotModelJson "hidden" false
           , LeanAgent.Json.obj [("model_picker_enabled", LeanAgent.Json.bool true)]
           ])]
  match LeanAgent.AI.OAuth.GitHubCopilot.parseAvailableModelIds raw with
  | .ok ids =>
      assertTrue (ids == #["enabled", "missing-supports"]) "expected selectable Copilot model IDs"
  | .error err => fail s!"expected valid Copilot models response: {err}"
  match LeanAgent.AI.OAuth.GitHubCopilot.parseAvailableModelIds (LeanAgent.Json.obj []) with
  | .ok _ => fail "expected invalid Copilot models response to fail"
  | .error err =>
      assertTrue (err.contains "Invalid Copilot models response") "expected invalid response error"

def githubCopilotTestModel (id : String) : LeanAgent.Models.ModelInfo :=
  { LeanAgent.Models.openAIGpt41Mini with
    id := id
    name := id
    provider := LeanAgent.AI.OAuth.GitHubCopilot.providerId
    baseUrl := "https://old-copilot.test"
  }

def testGitHubCopilotOAuthModifiesModelsFromCredential : IO Unit := do
  let models :=
    #[ githubCopilotTestModel "disabled"
     , githubCopilotTestModel "enabled"
     , { LeanAgent.Models.deepSeekV4Flash with id := "other-provider" }
     ]
  let credential : LeanAgent.AI.Auth.OAuthCredential :=
    { access := "tid=abc;proxy-ep=proxy.enterprise.githubcopilot.com;exp=123"
      refresh := "github-access-token"
      expires := 1000
      extra :=
        #[ ( "availableModelIds"
           , LeanAgent.Json.arr #[LeanAgent.Json.str "enabled"] )
         ]
    }
  let modified := LeanAgent.AI.OAuth.GitHubCopilot.modifyModels models credential
  assertTrue (modified.size == 2) "expected unavailable Copilot model to be filtered out"
  match modified.find? (fun model => model.provider == LeanAgent.AI.OAuth.GitHubCopilot.providerId) with
  | some model =>
      assertTrue (model.id == "enabled") "expected only enabled Copilot model"
      assertTrue (model.baseUrl == "https://api.enterprise.githubcopilot.com")
        "expected Copilot token proxy endpoint base URL"
  | none => fail "expected enabled Copilot model"
  assertTrue (modified.any (fun model => model.id == "other-provider"))
    "expected non-Copilot models to be preserved"
  let enterpriseCredential : LeanAgent.AI.Auth.OAuthCredential :=
    { access := "token-without-proxy-endpoint"
      refresh := "github-access-token"
      expires := 1000
      extra := #[("enterpriseUrl", LeanAgent.Json.str "https://enterprise.example/path")]
    }
  let enterpriseModels := LeanAgent.AI.OAuth.GitHubCopilot.modifyModels
    #[githubCopilotTestModel "a", githubCopilotTestModel "b"]
    enterpriseCredential
  assertTrue (enterpriseModels.size == 2) "expected legacy credentials without availability to keep models"
  assertTrue
    (enterpriseModels.all (fun model => model.baseUrl == "https://copilot-api.enterprise.example"))
    "expected enterprise base URL fallback for Copilot models"

def localGitHubCopilotRuntime
    (port : Nat)
    (deviceCodePath : String := "/copilot/device-code")
    (knownModelIds : Array String := #[])
    (onRequest : Option (LeanAgent.Http.RequestConfig → IO Unit) := none) :
    LeanAgent.AI.OAuth.GitHubCopilot.Runtime :=
  { urlsForDomain := fun _ =>
      { deviceCodeUrl := s!"http://127.0.0.1:{port}{deviceCodePath}"
        accessTokenUrl := s!"http://127.0.0.1:{port}/copilot/access-token"
        copilotTokenUrl := s!"http://127.0.0.1:{port}/copilot/token"
      }
    baseUrl := fun _ _ => s!"http://127.0.0.1:{port}/copilot"
    request := fun config => do
      match onRequest with
      | some hook => hook config
      | none => pure ()
      LeanAgent.Http.requestResponse
        { config with
          timeoutSeconds := 5
          connectTimeoutSeconds := 5
          maxResponseBytes := 4096
          noProxy := some "*"
        }
    nowMs := LeanAgent.AI.Auth.epochMsNow
    sleepMs := fun ms => IO.sleep (UInt32.ofNat ms)
    knownModelIds := knownModelIds
  }

def localOpenAICodexRuntime
    (port : Nat)
    (deviceUserCodePath : String := "/codex/deviceauth/usercode")
    (deviceTokenPath : String := "/codex/deviceauth/token")
    (tokenPath : String := "/codex/oauth/token")
    (state : String := "state-123")
    (verifier : String := "browser-verifier")
    (challenge : String := "browser-challenge")
    (originator : String := "lean-agent")
    (onRequest : Option (LeanAgent.Http.RequestConfig → IO Unit) := none) :
    LeanAgent.AI.OAuth.OpenAICodex.Runtime :=
  { urls :=
      { authorizeUrl := s!"http://127.0.0.1:{port}/codex/oauth/authorize"
        tokenUrl := s!"http://127.0.0.1:{port}{tokenPath}"
        redirectUri := "http://localhost:1455/auth/callback"
        deviceUserCodeUrl := s!"http://127.0.0.1:{port}{deviceUserCodePath}"
        deviceTokenUrl := s!"http://127.0.0.1:{port}{deviceTokenPath}"
        deviceVerificationUri := s!"http://127.0.0.1:{port}/codex/device"
        deviceRedirectUri := s!"http://127.0.0.1:{port}/codex/deviceauth/callback"
      }
    request := fun config => do
      match onRequest with
      | some hook => hook config
      | none => pure ()
      LeanAgent.Http.requestResponse
        { config with
          timeoutSeconds := 5
          connectTimeoutSeconds := 5
          maxResponseBytes := 4096
          noProxy := some "*"
        }
    generatePKCE := pure { verifier, challenge }
    generateState := pure state
    nowMs := pure 1000
    sleepMs := fun ms => IO.sleep (UInt32.ofNat ms)
    originator := originator
  }

def localAnthropicRuntime
    (port : Nat)
    (tokenPath : String := "/anthropic/oauth/token")
    (verifier : String := "anthropic-verifier")
    (challenge : String := "anthropic-challenge")
    (onRequest : Option (LeanAgent.Http.RequestConfig → IO Unit) := none) :
    LeanAgent.AI.OAuth.Anthropic.Runtime :=
  { authorizeUrl := s!"http://127.0.0.1:{port}/anthropic/oauth/authorize"
    tokenUrl := s!"http://127.0.0.1:{port}{tokenPath}"
    redirectUri := "http://localhost:53692/callback"
    request := fun config => do
      match onRequest with
      | some hook => hook config
      | none => pure ()
      LeanAgent.Http.requestResponse
        { config with
          timeoutSeconds := 5
          connectTimeoutSeconds := 5
          maxResponseBytes := 4096
          noProxy := some "*"
        }
    generatePKCE := pure { verifier, challenge }
    nowMs := pure 1000
  }

def testAnthropicOAuthRegisterBuiltInProvider : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  LeanAgent.AI.OAuth.Anthropic.registerBuiltIn
  match ← LeanAgent.AI.OAuth.getOAuthProvider? LeanAgent.AI.OAuth.Anthropic.providerId with
  | some provider =>
      assertTrue (provider.id == LeanAgent.AI.OAuth.Anthropic.providerId)
        "expected registered Anthropic OAuth provider id"
      assertTrue (provider.name == LeanAgent.AI.OAuth.Anthropic.name)
        "expected registered Anthropic OAuth provider name"
      assertTrue provider.usesCallbackServer
        "expected Anthropic OAuth provider to enable localhost callback flow"
      let apiKey := provider.getApiKey
        { access := "sk-ant-oat-access-token"
          refresh := "anthropic-refresh-token"
          expires := 2000
        }
      assertTrue (apiKey == "sk-ant-oat-access-token")
        "expected Anthropic OAuth getApiKey"
  | none => fail "expected registered Anthropic OAuth provider"
  LeanAgent.AI.OAuth.resetOAuthProviders

def testOpenAICodexOAuthRegisterBuiltInProvider : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  LeanAgent.AI.OAuth.OpenAICodex.registerBuiltIn
  match ← LeanAgent.AI.OAuth.getOAuthProvider? LeanAgent.AI.OAuth.OpenAICodex.providerId with
  | some provider =>
      assertTrue (provider.id == LeanAgent.AI.OAuth.OpenAICodex.providerId)
        "expected registered OpenAI Codex OAuth provider id"
      assertTrue (provider.name == "ChatGPT Plus/Pro (Codex Subscription)")
        "expected registered OpenAI Codex OAuth provider name"
      assertTrue provider.usesCallbackServer
        "expected OpenAI Codex OAuth provider to enable localhost callback flow"
      let apiKey := provider.getApiKey
        { access := "codex-test-token"
          refresh := "codex-refresh"
          expires := 2000
        }
      assertTrue (apiKey == "codex-test-token") "expected OpenAI Codex OAuth getApiKey"
  | none => fail "expected registered OpenAI Codex OAuth provider"
  LeanAgent.AI.OAuth.resetOAuthProviders

def testGitHubCopilotOAuthRegisterBuiltInProvider : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  LeanAgent.AI.OAuth.GitHubCopilot.registerBuiltIn
  match ← LeanAgent.AI.OAuth.getOAuthProvider? LeanAgent.AI.OAuth.GitHubCopilot.providerId with
  | some provider =>
      assertTrue (provider.id == LeanAgent.AI.OAuth.GitHubCopilot.providerId)
        "expected registered Copilot OAuth provider id"
      assertTrue (provider.name == LeanAgent.AI.OAuth.GitHubCopilot.name)
        "expected registered Copilot provider name"
      assertTrue (!provider.usesCallbackServer)
        "expected Copilot device-code provider not to use callback server"
      let apiKey := provider.getApiKey
        { access := "copilot-test-token"
          refresh := "refresh-x"
          expires := 2000
        }
      assertTrue (apiKey == "copilot-test-token") "expected Copilot OAuth getApiKey"
      pure ()
  | none => fail "expected registered Copilot OAuth provider"
  LeanAgent.AI.OAuth.resetOAuthProviders

def headerValueOpt? (headers : Array (String × Option String)) (name : String) : Option (Option String) :=
  headers.findSome? fun (headerName, value) =>
    if headerName.toLower == name.toLower then some value else none

def headerValueStringCI? (headers : Array (String × String)) (name : String) : Option String :=
  headers.findSome? fun (headerName, value) =>
    if headerName.toLower == name.toLower then some value else none

def testGitHubCopilotHeadersInference : IO Unit := do
  let userMessage :=
    LeanAgent.AI.Message.user
      { content := #[]
        timestamp := 0
      }
  assertTrue
    (LeanAgent.AI.Api.GitHubCopilotHeaders.inferCopilotInitiator #[userMessage] == "user")
    "expected user message to infer user initiator"
  let assistantMessage : LeanAgent.AI.Message :=
    .assistant
      { content := #[]
        api := ""
        provider := ""
        model := ""
        stopReason := .stop
        timestamp := 1
      }
  assertTrue
    (LeanAgent.AI.Api.GitHubCopilotHeaders.inferCopilotInitiator
      #[userMessage, assistantMessage] == "agent")
    "expected assistant last message to infer agent initiator"

  let noImageMessages := #[userMessage]
  assertTrue
    (!LeanAgent.AI.Api.GitHubCopilotHeaders.hasCopilotVisionInput noImageMessages)
    "expected no vision input for text-only messages"

  let imageMessage :=
    LeanAgent.AI.Message.user
      { content := #[LeanAgent.AI.image "AAA" "image/png"]
        timestamp := 0
      }
  assertTrue
    (LeanAgent.AI.Api.GitHubCopilotHeaders.hasCopilotVisionInput #[imageMessage])
    "expected vision input detection for image message"

  let headersNoImage :=
    LeanAgent.AI.Api.GitHubCopilotHeaders.buildCopilotDynamicHeaders #[userMessage] false
  assertTrue
    (headerValueStringCI? headersNoImage "x-initiator" == some "user")
    "expected initiator header"
  assertTrue
    (headerValueStringCI? headersNoImage "openai-intent" == some "conversation-edits")
    "expected intent header"
  assertTrue
    (headerValueStringCI? headersNoImage "copilot-vision-request" == none)
    "expected vision header to be omitted when hasImages is false"

  let headersWithImage :=
    LeanAgent.AI.Api.GitHubCopilotHeaders.buildCopilotDynamicHeaders #[userMessage] true
  assertTrue
    (headerValueStringCI? headersWithImage "copilot-vision-request" == some "true")
    "expected vision header when hasImages is true"

def testCatalogProviderHeadersApplyThroughAuth : IO Unit := do
  let provider ← LeanAgent.AI.Providers.KimiCoding.provider
  let models ← provider.getModels
  match models.find? (fun model => model.id == LeanAgent.Models.kimiCodingDefaultModel) with
  | some model =>
      let ctx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun name =>
            pure (if name == LeanAgent.Models.kimiCodingApiKeyEnv then some "kimi-token" else none)
          fileExists := fun _ => pure false
        }
      let collection ← LeanAgent.Models.createModels none ctx
      let (_requestModel, options) ← collection.applyAuth provider model {}
      assertTrue (options.apiKey == some "kimi-token") "expected Kimi Coding API key auth"
      assertTrue
        (headerValueOpt? options.headers "User-Agent" == some (some "KimiCLI/1.5"))
        "expected Kimi Coding provider header to be inherited"
      let (_requestModel, overrideOptions) ← collection.applyAuth provider model
        { headers := #[("User-Agent", some "caller-agent")] }
      assertTrue
        (headerValueOpt? overrideOptions.headers "User-Agent" == some (some "caller-agent"))
        "expected request header to override provider header"
  | none => fail "expected Kimi Coding default model"
  let nvidiaProvider ← LeanAgent.AI.Providers.NVIDIA.provider
  let nvidiaModels ← nvidiaProvider.getModels
  match nvidiaModels.find? (fun model => model.id == LeanAgent.Models.nvidiaDefaultModel) with
  | some model =>
      let ctx : LeanAgent.AI.Auth.AuthContext :=
        { env := fun name =>
            pure (if name == LeanAgent.Models.nvidiaApiKeyEnv then some "nvidia-token" else none)
          fileExists := fun _ => pure false
        }
      let collection ← LeanAgent.Models.createModels none ctx
      let (_requestModel, options) ← collection.applyAuth nvidiaProvider model {}
      assertTrue (options.apiKey == some "nvidia-token") "expected NVIDIA API key auth"
      assertTrue
        (headerValueOpt? options.headers "NVCF-POLL-SECONDS" == some (some "3600"))
        "expected NVIDIA model header to be inherited"
      let (_requestModel, overrideOptions) ← collection.applyAuth nvidiaProvider model
        { headers := #[("NVCF-POLL-SECONDS", some "120")] }
      assertTrue
        (headerValueOpt? overrideOptions.headers "NVCF-POLL-SECONDS" == some (some "120"))
        "expected request header to override NVIDIA model header"
      let (_requestModel, removedOptions) ← collection.applyAuth nvidiaProvider model
        { headers := #[("NVCF-POLL-SECONDS", none)] }
      assertTrue
        (headerValueOpt? removedOptions.headers "NVCF-POLL-SECONDS" == some none)
        "expected request header removal to override NVIDIA model header"
  | none => fail "expected NVIDIA default model"

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

def testCloudflareProviderFactoriesExposeModelsAndAuth : IO Unit := do
  let workers ← LeanAgent.AI.Providers.CloudflareWorkersAI.provider
  assertTrue (workers.id == "cloudflare-workers-ai") "expected Workers AI provider id"
  assertTrue (workers.name == "Cloudflare Workers AI") "expected Workers AI provider name"
  let workersModels ← workers.getModels
  match workersModels.find? (fun model => model.id == "@cf/openai/gpt-oss-120b") with
  | some model =>
      assertTrue (model.api == "openai-completions") "expected Workers AI OpenAI-compatible API"
      assertTrue (model.baseUrl == LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl)
        "expected Workers AI base URL template"
      assertTrue model.compat.sendSessionAffinityHeaders
        "expected Workers AI session affinity compat"
      assertTrue (!model.compat.supportsLongCacheRetention)
        "expected Workers AI long cache retention compat"
      let collection ← LeanAgent.Models.createModels none fakeCloudflareAuthContext
      let (requestModel, options) ← collection.applyAuth workers model {}
      assertTrue
        (requestModel.baseUrl == "https://api.cloudflare.com/client/v4/accounts/acct-env/ai/v1")
        "expected Workers AI factory auth to resolve account base URL"
      assertTrue (options.apiKey == some "cf-env-key") "expected Workers AI factory auth API key"
  | none => fail "expected Workers AI GPT OSS model"
  let gateway ← LeanAgent.AI.Providers.CloudflareAIGateway.provider
  assertTrue (gateway.id == "cloudflare-ai-gateway") "expected AI Gateway provider id"
  assertTrue (gateway.name == "Cloudflare AI Gateway") "expected AI Gateway provider name"
  let gatewayModels ← gateway.getModels
  assertTrue (gatewayModels.any (fun model => model.api == "openai-responses"))
    "expected AI Gateway Responses models"
  assertTrue (gatewayModels.any (fun model => model.api == "openai-completions"))
    "expected AI Gateway OpenAI-compatible models"
  match gatewayModels.find? (fun model => model.id == "workers-ai/@cf/moonshotai/kimi-k2.6") with
  | some model =>
      assertTrue model.compat.sendSessionAffinityHeaders
        "expected AI Gateway OpenAI-compatible session affinity compat"
      assertTrue (!model.compat.supportsLongCacheRetention)
        "expected AI Gateway OpenAI-compatible long cache retention compat"
  | none => fail "expected AI Gateway OpenAI-compatible Workers AI model"
  match gatewayModels.find? (fun model => model.id == "gpt-4o-mini") with
  | some model =>
      assertTrue (model.baseUrl == LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl)
        "expected AI Gateway OpenAI base URL template"
      let collection ← LeanAgent.Models.createModels none fakeCloudflareAuthContext
      let (requestModel, options) ← collection.applyAuth gateway model {}
      assertTrue
        (requestModel.baseUrl == "https://gateway.ai.cloudflare.com/v1/acct-env/gateway-env/openai")
        "expected AI Gateway factory auth to resolve gateway base URL"
      assertTrue options.apiKey.isNone "expected AI Gateway factory auth to suppress bearer API key"
      assertTrue
        (headerValueOpt? options.headers "cf-aig-authorization" == some (some "Bearer cf-env-key"))
        "expected AI Gateway factory auth header"
      assertTrue (headerValueOpt? options.headers "Authorization" == some (some ""))
        "expected AI Gateway factory auth to suppress Authorization"
  | none => fail "expected AI Gateway GPT-4o mini model"

def testBuiltinProvidersAllAggregatesImplementedProviders : IO Unit := do
  let providerIds := LeanAgent.AI.Providers.All.getBuiltinProviders
  assertTrue (providerIds.contains LeanAgent.Models.deepSeekProviderId)
    "expected all providers to include DeepSeek catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.anthropicProviderId)
    "expected all providers to include Anthropic catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.openAICodexProviderId)
    "expected all providers to include OpenAI Codex catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.githubCopilotProviderId)
    "expected all providers to include GitHub Copilot catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.azureOpenAIResponsesProviderId)
    "expected all providers to include Azure OpenAI Responses catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.googleProviderId)
    "expected all providers to include Google catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.googleVertexProviderId)
    "expected all providers to include Google Vertex catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.mistralProviderId)
    "expected all providers to include Mistral catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.amazonBedrockProviderId)
    "expected all providers to include Amazon Bedrock catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.kimiCodingProviderId)
    "expected all providers to include Kimi Coding catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.minimaxProviderId)
    "expected all providers to include MiniMax catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.minimaxCNProviderId)
    "expected all providers to include MiniMax CN catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.vercelAIGatewayProviderId)
    "expected all providers to include Vercel AI Gateway catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.opencodeProviderId)
    "expected all providers to include OpenCode catalog provider"
  assertTrue (providerIds.contains LeanAgent.Models.opencodeGoProviderId)
    "expected all providers to include OpenCode Go catalog provider"
  let openAICompatibleAdditions :=
    #[ LeanAgent.Models.antLingProviderId
     , LeanAgent.Models.huggingFaceProviderId
     , LeanAgent.Models.moonshotAIProviderId
     , LeanAgent.Models.moonshotAICNProviderId
     , LeanAgent.Models.nvidiaProviderId
     , LeanAgent.Models.xiaomiProviderId
     , LeanAgent.Models.xiaomiTokenPlanAMSProviderId
     , LeanAgent.Models.xiaomiTokenPlanCNProviderId
     , LeanAgent.Models.xiaomiTokenPlanSGPProviderId
     , LeanAgent.Models.zaiProviderId
     , LeanAgent.Models.zaiCodingCNProviderId
     ]
  for providerId in openAICompatibleAdditions do
    assertTrue (providerIds.contains providerId)
      s!"expected all providers to include OpenAI-compatible catalog provider {providerId}"
  assertTrue (providerIds.contains LeanAgent.AI.Providers.CloudflareWorkersAI.providerId)
    "expected all providers to include Cloudflare Workers AI"
  assertTrue (providerIds.contains LeanAgent.AI.Providers.CloudflareAIGateway.providerId)
    "expected all providers to include Cloudflare AI Gateway"
  match LeanAgent.AI.Providers.All.getBuiltinModel
    LeanAgent.Models.deepSeekProviderId
    LeanAgent.Models.deepSeekDefaultModel with
  | some model =>
      assertTrue (model.provider == LeanAgent.Models.deepSeekProviderId)
        "expected TS-style builtin model alias to resolve DeepSeek"
  | none => fail "expected TS-style builtin model alias lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.deepSeekProviderId
    LeanAgent.Models.deepSeekDefaultModel with
  | some model =>
      assertTrue (model.provider == LeanAgent.Models.deepSeekProviderId) "expected DeepSeek builtin model"
  | none => fail "expected DeepSeek builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.anthropicProviderId
    LeanAgent.Models.anthropicDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.AnthropicMessages.api) "expected Anthropic builtin model"
  | none => fail "expected Anthropic builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.azureOpenAIResponsesProviderId
    LeanAgent.Models.azureOpenAIResponsesDefaultModel with
  | some model =>
      assertTrue (model.api == "azure-openai-responses") "expected Azure OpenAI Responses builtin model"
  | none => fail "expected Azure OpenAI Responses builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.openAICodexProviderId
    LeanAgent.Models.openAICodexDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.OpenAICodexResponses.api)
        "expected OpenAI Codex builtin model"
  | none => fail "expected OpenAI Codex builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.githubCopilotProviderId
    LeanAgent.Models.githubCopilotDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-responses") "expected GitHub Copilot builtin model"
  | none => fail "expected GitHub Copilot builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.googleProviderId
    LeanAgent.Models.googleDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.GoogleGenerativeAI.api) "expected Google builtin model"
  | none => fail "expected Google builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.googleVertexProviderId
    LeanAgent.Models.googleVertexDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.GoogleVertex.api) "expected Google Vertex builtin model"
  | none => fail "expected Google Vertex builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.mistralProviderId
    LeanAgent.Models.mistralDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.MistralConversations.api) "expected Mistral builtin model"
  | none => fail "expected Mistral builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.amazonBedrockProviderId
    LeanAgent.Models.amazonBedrockDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.BedrockConverseStream.api) "expected Bedrock builtin model"
  | none => fail "expected Bedrock builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.xiaomiTokenPlanAMSProviderId
    LeanAgent.Models.xiaomiTokenPlanAMSDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-completions") "expected Xiaomi Token Plan AMS builtin model"
  | none => fail "expected Xiaomi Token Plan AMS builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.zaiProviderId
    LeanAgent.Models.zaiDefaultModel with
  | some model =>
      assertTrue (model.provider == LeanAgent.Models.zaiProviderId) "expected Z.AI builtin model"
  | none => fail "expected Z.AI builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.kimiCodingProviderId
    LeanAgent.Models.kimiCodingDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.AnthropicMessages.api) "expected Kimi Coding builtin model"
  | none => fail "expected Kimi Coding builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.minimaxCNProviderId
    LeanAgent.Models.minimaxCNDefaultModel with
  | some model =>
      assertTrue (model.provider == LeanAgent.Models.minimaxCNProviderId) "expected MiniMax CN builtin model"
  | none => fail "expected MiniMax CN builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.vercelAIGatewayProviderId
    LeanAgent.Models.vercelAIGatewayDefaultModel with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.AnthropicMessages.api)
        "expected Vercel AI Gateway builtin model"
  | none => fail "expected Vercel AI Gateway builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.opencodeProviderId
    LeanAgent.Models.opencodeDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-completions") "expected OpenCode builtin model"
  | none => fail "expected OpenCode builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.Models.opencodeGoProviderId
    LeanAgent.Models.opencodeGoDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-completions") "expected OpenCode Go builtin model"
  | none => fail "expected OpenCode Go builtin model lookup"
  match LeanAgent.AI.Providers.All.getBuiltinModel?
    LeanAgent.AI.Providers.CloudflareAIGateway.providerId
    "gpt-4o-mini" with
  | some model =>
      assertTrue (model.api == "openai-responses") "expected Gateway Responses builtin model"
  | none => fail "expected Cloudflare AI Gateway builtin model lookup"
  let collection ← LeanAgent.AI.Providers.All.builtinModels none fakeCloudflareAuthContext
  let providers ← collection.getProviders
  assertTrue (providers.size == 35) "expected implemented builtin text providers"
  match ← collection.getProvider? LeanAgent.AI.Providers.CloudflareWorkersAI.providerId with
  | some _ => pure ()
  | none => fail "expected Workers AI provider in builtin collection"
  match ← collection.getProvider? LeanAgent.Models.githubCopilotProviderId with
  | some _ => pure ()
  | none => fail "expected GitHub Copilot provider in builtin collection"
  match ← collection.getModel?
    LeanAgent.AI.Providers.CloudflareAIGateway.providerId
    "gpt-4o-mini" with
  | some model =>
      assertTrue (model.baseUrl == LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl)
        "expected Gateway model in builtin collection"
  | none => fail "expected Gateway model in builtin collection"
  let imageCollection ← LeanAgent.AI.Providers.All.builtinImagesModels
  let imageProviders ← imageCollection.getProviders
  assertTrue (imageProviders.size == 1) "expected implemented builtin image provider"
  match ← imageCollection.getProvider? LeanAgent.AI.Api.OpenRouterImages.providerId with
  | some _ => pure ()
  | none => fail "expected OpenRouter image provider in builtin image collection"

def testBuiltinModelsCollectionMatchesPiInvariants : IO Unit := do
  let providerIds := LeanAgent.AI.Providers.All.getBuiltinProviders
  assertTrue (providerIds.size == 35) "expected 35 builtin provider ids"
  assertTrue (providerIds.toList.eraseDups.length == providerIds.size)
    "expected builtin provider ids to stay unique"
  assertTrue (providerIds.contains LeanAgent.Models.anthropicProviderId)
    "expected builtin provider ids to include Anthropic"
  let collection ← LeanAgent.AI.Providers.All.builtinModels
  let providers ← collection.getProviders
  assertTrue (providers.size == providerIds.size)
    "expected builtin collection provider count to match builtin provider ids"
  assertTrue (providers.map (·.id) == providerIds)
    "expected builtin collection provider ids to match static builtin provider ids"
  match ← collection.getModel? LeanAgent.Models.anthropicProviderId "claude-haiku-4-5" with
  | some anthropic =>
      assertTrue (anthropic.api == LeanAgent.AI.Api.AnthropicMessages.api)
        "expected Anthropic builtin collection model api"
  | none => fail "expected Anthropic builtin collection model"
  let allModels ← collection.getModels
  assertTrue (allModels.size > 500) "expected builtin collection to expose more than 500 models"
  for provider in providers do
    let models ← collection.getModels (some provider.id)
    assertTrue (!models.isEmpty) s!"expected builtin provider {provider.id} to expose models"
    assertTrue (models.all fun model => model.provider == provider.id)
      s!"expected builtin provider {provider.id} to own its listed models"

def testEnvApiKeysProviderMap : IO Unit := do
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "github-copilot" == some #["COPILOT_GITHUB_TOKEN"])
    "expected GitHub Copilot env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "azure-openai-responses" ==
      some #[LeanAgent.Models.azureOpenAIResponsesApiKeyEnv])
    "expected Azure OpenAI Responses env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "ant-ling" == some #[LeanAgent.Models.antLingApiKeyEnv])
    "expected Ant Ling env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "huggingface" == some #[LeanAgent.Models.huggingFaceApiKeyEnv])
    "expected Hugging Face env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "moonshotai" == some #[LeanAgent.Models.moonshotAIApiKeyEnv])
    "expected Moonshot AI env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "moonshotai-cn" == some #[LeanAgent.Models.moonshotAICNApiKeyEnv])
    "expected Moonshot AI CN env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "nvidia" == some #[LeanAgent.Models.nvidiaApiKeyEnv])
    "expected NVIDIA env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "xiaomi" == some #[LeanAgent.Models.xiaomiApiKeyEnv])
    "expected Xiaomi env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "xiaomi-token-plan-ams" ==
      some #[LeanAgent.Models.xiaomiTokenPlanAMSApiKeyEnv])
    "expected Xiaomi Token Plan AMS env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "xiaomi-token-plan-cn" ==
      some #[LeanAgent.Models.xiaomiTokenPlanCNApiKeyEnv])
    "expected Xiaomi Token Plan CN env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "xiaomi-token-plan-sgp" ==
      some #[LeanAgent.Models.xiaomiTokenPlanSGPApiKeyEnv])
    "expected Xiaomi Token Plan SGP env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "zai" == some #[LeanAgent.Models.zaiApiKeyEnv])
    "expected Z.AI env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "zai-coding-cn" == some #["ZAI_CODING_CN_API_KEY"])
    "expected ZAI Coding CN env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "kimi-coding" == some #[LeanAgent.Models.kimiCodingApiKeyEnv])
    "expected Kimi Coding env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "minimax" == some #[LeanAgent.Models.minimaxApiKeyEnv])
    "expected MiniMax env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "minimax-cn" == some #[LeanAgent.Models.minimaxCNApiKeyEnv])
    "expected MiniMax CN env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "vercel-ai-gateway" == some #[LeanAgent.Models.vercelAIGatewayApiKeyEnv])
    "expected Vercel AI Gateway env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "opencode" == some #[LeanAgent.Models.opencodeApiKeyEnv])
    "expected OpenCode env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "opencode-go" == some #[LeanAgent.Models.opencodeGoApiKeyEnv])
    "expected OpenCode Go env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "google" == some #[LeanAgent.Models.googleApiKeyEnv])
    "expected Google Gemini env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "google-vertex" == some #[LeanAgent.Models.googleVertexApiKeyEnv])
    "expected Google Vertex env var"
  assertTrue
    (LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? "mistral" == some #[LeanAgent.Models.mistralApiKeyEnv])
    "expected Mistral env var"
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
  let moonshotKeys ← LeanAgent.AI.EnvApiKeys.findEnvKeys
    "moonshotai-cn"
    #[("MOONSHOT_API_KEY", "moonshot-token")]
  assertTrue (moonshotKeys == some #[LeanAgent.Models.moonshotAICNApiKeyEnv])
    "expected configured Moonshot AI CN key"
  let xiaomiKey ← LeanAgent.AI.EnvApiKeys.getEnvApiKey
    "xiaomi-token-plan-sgp"
    #[("XIAOMI_TOKEN_PLAN_SGP_API_KEY", "xiaomi-token")]
  assertTrue (xiaomiKey == some "xiaomi-token") "expected configured Xiaomi Token Plan SGP API key"
  let kimiKey ← LeanAgent.AI.EnvApiKeys.getEnvApiKey
    "kimi-coding"
    #[("KIMI_API_KEY", "kimi-token")]
  assertTrue (kimiKey == some "kimi-token") "expected configured Kimi Coding API key"
  let vercelKey ← LeanAgent.AI.EnvApiKeys.getEnvApiKey
    "vercel-ai-gateway"
    #[("AI_GATEWAY_API_KEY", "vercel-token")]
  assertTrue (vercelKey == some "vercel-token") "expected configured Vercel AI Gateway API key"
  let opencodeGoKey ← LeanAgent.AI.EnvApiKeys.getEnvApiKey
    "opencode-go"
    #[("OPENCODE_API_KEY", "opencode-token")]
  assertTrue (opencodeGoKey == some "opencode-token") "expected configured OpenCode Go API key"
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
  let bedrockDefaultProfile ← LeanAgent.AI.EnvApiKeys.getEnvApiKey
    "amazon-bedrock"
    #[("AWS_DEFAULT_PROFILE", "default")]
  assertTrue (bedrockDefaultProfile == some "<authenticated>") "expected AWS default profile ambient marker"
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
  match ← collection.getProvider "fake" with
  | some found => assertTrue (found.id == "fake") "expected runtime provider lookup"
  | none => fail "expected runtime provider lookup"
  match ← collection.getModel? "fake" "fake-model" with
  | some model => assertTrue (model.id == "fake-model") "expected runtime model lookup"
  | none => fail "expected runtime model lookup"
  match ← collection.getModel "fake" "fake-model" with
  | some model => assertTrue (model.id == "fake-model") "expected runtime getModel alias lookup"
  | none => fail "expected runtime getModel alias lookup"
  let message ← collection.completeSimple
    fakeRuntimeModel
    { systemPrompt := some "system"
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }]
    }
  assertTrue (LeanAgent.AI.contentPlainText message.content == "runtime-ok") "expected runtime stream result"
  assertTrue ((← seenApiKey.get) == some "env-secret") "expected collection to inject auth"

def testModelsCollectionGenericStreamAndCompleteDispatchWithAuth : IO Unit := do
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
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "system"
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }]
    }
  let stream ← collection.stream fakeRuntimeModel context {}
  assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "runtime-ok")
    "expected collection generic stream dispatch result"
  assertTrue ((← seenApiKey.get) == some "env-secret")
    "expected collection generic stream to inject auth"
  let message ← collection.complete fakeRuntimeModel context {}
  assertTrue (LeanAgent.AI.contentPlainText message.content == "runtime-ok")
    "expected collection generic complete dispatch result"
  assertTrue ((← seenApiKey.get) == some "env-secret")
    "expected collection generic complete to inject auth"

def testModelsCollectionListingSwallowsProviderSourceFailures : IO Unit := do
  let collection ← LeanAgent.Models.createModels
  let brokenProvider : LeanAgent.Models.Provider :=
    { id := "broken"
      name := "Broken"
      auth := fakeProviderAuth
      getModels := throw (IO.userError "boom")
      streamSimple := fun model _context _options => do
        let timestamp ← IO.monoMsNow
        pure
          (LeanAgent.AI.fromMessage
            { content := #[LeanAgent.AI.text s!"unexpected: {model.id}"]
              api := model.api
              provider := model.provider
              model := model.id
              timestamp := timestamp
            })
    }
  let okProvider ← LeanAgent.Models.createProvider
    { id := "ok"
      name := some "Okay"
      auth := fakeProviderAuth
      models := #[{ fakeRuntimeModel with provider := "ok", id := "m1" }]
      apis := #[{ api := "fake-api", streams := fakeRuntimeStreams (← IO.mkRef none) }]
    }
  collection.setProvider brokenProvider
  collection.setProvider okProvider
  assertTrue ((← collection.getModels).map (·.id) == #["m1"])
    "expected collection-wide listing to swallow broken provider getModels failure"
  assertTrue ((← collection.getModels (some "broken")).isEmpty)
    "expected single-provider listing to swallow broken provider getModels failure"
  match ← collection.getProvider "broken" with
  | some provider =>
      let threw ←
        try
          let _ ← provider.getModels
          pure false
        catch err =>
          assertTrue (err.toString.contains "boom")
            "expected direct provider getModels failure details"
          pure true
      assertTrue threw "expected direct broken provider getModels to still throw"
  | none => fail "expected broken provider lookup"
  match ← collection.getModel "ok" "m1" with
  | some found =>
      assertTrue (LeanAgent.Models.hasApi found "fake-api")
        "expected hasApi to report true for the matching runtime API"
      assertTrue (!(LeanAgent.Models.hasApi found "openai-completions"))
        "expected hasApi to report false for a different runtime API"
  | none => fail "expected surviving provider model lookup"

def testModelsCollectionReplacementPreservesOrder : IO Unit := do
  let collection ← LeanAgent.Models.createModels
  let first ← LeanAgent.Models.createProvider
    { id := "order-a"
      name := some "Order A"
      auth := fakeProviderAuth
      models := #[{ fakeRuntimeModel with provider := "order-a", id := "a1" }]
      apis := #[{ api := "fake-api", streams := fakeRuntimeStreams (← IO.mkRef none) }]
    }
  let second ← LeanAgent.Models.createProvider
    { id := "order-b"
      name := some "Order B"
      auth := fakeProviderAuth
      models := #[{ fakeRuntimeModel with provider := "order-b", id := "b1" }]
      apis := #[{ api := "fake-api", streams := fakeRuntimeStreams (← IO.mkRef none) }]
    }
  let replacement ← LeanAgent.Models.createProvider
    { id := "order-a"
      name := some "Order A Replaced"
      auth := fakeProviderAuth
      models := #[{ fakeRuntimeModel with provider := "order-a", id := "a2" }]
      apis := #[{ api := "fake-api", streams := fakeRuntimeStreams (← IO.mkRef none) }]
    }
  collection.setProvider first
  collection.setProvider second
  collection.setProvider replacement
  let providers ← collection.getProviders
  assertTrue ((providers.map (·.id)) == #["order-a", "order-b"])
    "expected provider replacement to preserve collection order"
  match ← collection.getProvider? "order-a" with
  | some provider =>
      assertTrue (provider.name == "Order A Replaced")
        "expected provider replacement to update the provider entry"
  | none => fail "expected replaced provider lookup"
  assertTrue ((← collection.getModel? "order-a" "a2").isSome)
    "expected replacement provider model to be visible"
  assertTrue ((← collection.getModel? "order-a" "a1").isNone)
    "expected replaced provider model list to be updated"

def testModelsCollectionUnknownProviderReturnsError : IO Unit := do
  let collection ← LeanAgent.Models.createModels
  let result ← collection.completeSimple
    { fakeRuntimeModel with provider := "ghost" }
    { systemPrompt := some "system"
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }]
    }
  assertTrue (result.stopReason == .error) "expected unknown provider error result"
  assertTrue
    (match result.errorMessage with
     | some message => message.contains "Unknown provider: ghost"
     | none => false)
    "expected unknown provider error message"

def testModelsCollectionAuthSetupFailureReturnsErrorStream : IO Unit := do
  let calledRef ← IO.mkRef false
  let failingAuth : LeanAgent.AI.Auth.ProviderAuth :=
    { apiKey := some
        { name := "Failing API key"
          resolve := fun model _ctx _credential => do
            throw (IO.userError s!"failed to resolve auth for {model.provider}")
        } }
  let provider ← LeanAgent.Models.createProvider
    { id := "failing-auth"
      name := some "Failing Auth"
      auth := failingAuth
      models := #[{ fakeRuntimeModel with provider := "failing-auth" }]
      apis :=
        #[{ api := "fake-api"
            streams :=
              { streamSimple := fun model _context _options => do
                  calledRef.set true
                  let timestamp ← IO.monoMsNow
                  pure
                    (LeanAgent.AI.fromMessage
                      { content := #[LeanAgent.AI.text s!"unexpected: {model.id}"]
                        api := model.api
                        provider := model.provider
                        model := model.id
                        timestamp := timestamp
                      })
              } }]
    }
  let collection ← LeanAgent.Models.createModels
  collection.setProvider provider
  let stream ← collection.streamSimple
    { fakeRuntimeModel with provider := "failing-auth" }
    { systemPrompt := some "system"
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }]
    }
  assertTrue (stream.result.stopReason == .error) "expected auth setup failure error stream"
  assertTrue (!(← calledRef.get)) "expected auth setup failure to skip provider dispatch"
  match stream.result.errorMessage with
  | some message =>
      assertTrue (message.contains "ModelsError(auth)")
        "expected typed auth error for setup failure"
      assertTrue (message.contains "API key auth failed for provider failing-auth")
        "expected provider-specific auth failure details"
  | none => fail "expected auth setup failure error message"

def testModelsCreateProviderDynamicRefreshDedupes : IO Unit := do
  let fetches ← IO.mkRef 0
  let provider ← LeanAgent.Models.createProvider
    { id := "dynamic"
      name := some "Dynamic"
      auth := fakeProviderAuth
      models := #[]
      refreshModels := some (do
        fetches.modify (· + 1)
        IO.sleep 10
        pure #[{ fakeRuntimeModel with id := "listed" }]
      )
      apis := #[{ api := "fake-api", streams := fakeRuntimeStreams (← IO.mkRef none) }]
    }
  assertTrue ((← provider.getModels).isEmpty) "expected dynamic provider to start empty"
  let firstTask ←
    IO.asTask do
      match provider.refreshModels with
      | some refresh => refresh
      | none => pure ()
  let secondTask ←
    IO.asTask do
      match provider.refreshModels with
      | some refresh => refresh
      | none => pure ()
  match ← IO.wait firstTask with
  | .ok _ => pure ()
  | .error err => throw err
  match ← IO.wait secondTask with
  | .ok _ => pure ()
  | .error err => throw err
  assertTrue ((← fetches.get) == 1) "expected in-flight provider refresh dedupe"
  assertTrue ((← provider.getModels).map (·.id) == #["listed"]) "expected refreshed provider model list"
  match provider.refreshModels with
  | some refresh => refresh
  | none => fail "expected dynamic refresh hook"
  assertTrue ((← fetches.get) == 2) "expected later provider refresh to fetch again"

def testModelsCollectionRefreshAndFailureSemantics : IO Unit := do
  let collection ← LeanAgent.Models.createModels
  let refreshes ← IO.mkRef 0
  let dynamicProvider ← LeanAgent.Models.createProvider
    { id := "dyn"
      name := some "Dynamic"
      auth := fakeProviderAuth
      models := #[{ fakeRuntimeModel with provider := "dyn", id := "before" }]
      refreshModels := some (do
        refreshes.modify (· + 1)
        pure #[{ fakeRuntimeModel with provider := "dyn", id := "after" }]
      )
      apis := #[{ api := "fake-api", streams := fakeRuntimeStreams (← IO.mkRef none) }]
    }
  let staticProvider ← LeanAgent.Models.createProvider
    { id := "static"
      name := some "Static"
      auth := fakeProviderAuth
      models := #[{ fakeRuntimeModel with provider := "static", id := "s1" }]
      apis := #[{ api := "fake-api", streams := fakeRuntimeStreams (← IO.mkRef none) }]
    }
  let flakyProvider ← LeanAgent.Models.createProvider
    { id := "flaky"
      name := some "Flaky"
      auth := fakeProviderAuth
      refreshModels := some (throw (IO.userError "fetch failed"))
      apis := #[{ api := "fake-api", streams := fakeRuntimeStreams (← IO.mkRef none) }]
    }
  collection.setProvider dynamicProvider
  collection.setProvider staticProvider
  assertTrue ((← collection.getModel? "dyn" "before").isSome) "expected pre-refresh dynamic model"
  collection.refresh (some "dyn")
  assertTrue ((← refreshes.get) == 1) "expected targeted collection refresh"
  assertTrue ((← collection.getModel? "dyn" "after").isSome) "expected refreshed dynamic model"
  assertTrue ((← collection.getModel? "dyn" "before").isNone) "expected old dynamic model removal"
  collection.refresh (some "static")
  collection.refresh
  assertTrue ((← refreshes.get) == 2) "expected refresh-all to re-run dynamic refresh"
  collection.setProvider flakyProvider
  let targetedFailed ←
    try
      collection.refresh (some "flaky")
      pure false
    catch err =>
      assertTrue (err.toString.contains "ModelsError(model_source)")
        "expected targeted refresh failure to wrap as model_source"
      pure true
  assertTrue targetedFailed "expected targeted collection refresh failure"
  collection.refresh

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
  | some provider =>
      assertTrue (provider.api == fakeRuntimeModel.api) "expected compat provider lookup"
      let stream ← provider.streamSimple
        fakeRuntimeModel
        { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }] }
        { apiKey := some "provider-method-key" }
      assertTrue
        (LeanAgent.AI.contentPlainText stream.result.content == "runtime-ok")
        "expected compat provider lookup to expose direct streamSimple"
      assertTrue ((← seenApiKey.get) == some "provider-method-key")
        "expected compat provider direct streamSimple to pass api key"
      let mismatchFailed ←
        try
          let _ ← provider.streamSimple
            { fakeRuntimeModel with api := "other-runtime-api" }
            { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }] }
            {}
          pure false
        catch err =>
          assertTrue
            (err.toString.contains "Mismatched api: other-runtime-api expected fake-api")
            "expected compat provider direct streamSimple api mismatch error"
          pure true
      assertTrue mismatchFailed "expected compat provider direct streamSimple mismatch failure"
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

def testCompatApiRegistryReplacementPreservesOrder : IO Unit := do
  let apiA := "compat-order-a"
  let apiB := "compat-order-b"
  let makeProvider (api label : String) : LeanAgent.AI.Compat.ApiProvider :=
    { api := api
      streams :=
        { streamSimple := fun model _context _options => do
            let timestamp ← IO.monoMsNow
            pure
              (LeanAgent.AI.fromMessage
                { content := #[LeanAgent.AI.text label]
                  api := model.api
                  provider := model.provider
                  model := model.id
                  timestamp := timestamp
                })
        } }
  LeanAgent.AI.Compat.clearApiProviders
  try
    LeanAgent.AI.Compat.registerApiProvider (makeProvider apiA "first") (some "compat-order-source-a")
    LeanAgent.AI.Compat.registerApiProvider (makeProvider apiB "second") (some "compat-order-source-b")
    LeanAgent.AI.Compat.registerApiProvider
      (makeProvider apiA "replaced")
      (some "compat-order-source-a-replaced")
    let providers ← LeanAgent.AI.Compat.getApiProviders
    assertTrue ((providers.map (·.api)) == #[apiA, apiB])
      "expected compat API replacement to preserve registry order"
    match ← LeanAgent.AI.Compat.getApiProvider? apiA with
    | some provider =>
        let stream ← provider.streamSimple
          { fakeRuntimeModel with api := apiA, provider := "compat-order", id := "model-a" }
          { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }] }
          {}
        assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "replaced")
          "expected compat API replacement to update the registered provider"
    | none => fail "expected compat replacement provider lookup"
  finally
    LeanAgent.AI.Compat.resetApiProviders

def testCompatGenericStreamAndCompleteDispatch : IO Unit := do
  LeanAgent.AI.Compat.resetApiProviders
  let seenApiKey ← IO.mkRef (none : Option String)
  LeanAgent.AI.Compat.registerApiProvider
    { api := "openai-completions", streams := fakeRuntimeStreams seenApiKey }
    (some "compat-generic-openai")
  let model :=
    { fakeRuntimeModel with
      id := "compat-openai-generic"
      provider := LeanAgent.Models.openAIProviderId
      api := "openai-completions"
    }
  let context : LeanAgent.AI.Context :=
    { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }] }
  let stream ← LeanAgent.AI.Compat.stream
    model
    context
    { apiKey := some "compat-stream-key" }
  assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "runtime-ok")
    "expected compat generic stream dispatch"
  assertTrue ((← seenApiKey.get) == some "compat-stream-key")
    "expected compat generic stream to pass api key"
  let message ← LeanAgent.AI.Compat.complete
    model
    context
    { apiKey := some "compat-complete-key" }
  assertTrue (LeanAgent.AI.contentPlainText message.content == "runtime-ok")
    "expected compat generic complete dispatch"
  assertTrue ((← seenApiKey.get) == some "compat-complete-key")
    "expected compat generic complete to pass api key"
  LeanAgent.AI.Compat.resetApiProviders

def testBedrockLazyApiOverride : IO Unit := do
  let usedOverride ← IO.mkRef false
  try
    LeanAgent.AI.Api.BedrockConverseStreamLazy.setBedrockProviderModule
      { streamSimple := fun model _context _options => do
          usedOverride.set true
          let message : LeanAgent.AI.AssistantMessage :=
            { content := #[LeanAgent.AI.text "bedrock-override"]
              api := model.api
              provider := model.provider
              model := model.id
              usage := {}
              stopReason := .stop
              timestamp := 0
            }
          pure (LeanAgent.AI.fromMessage message)
      }
    let model : LeanAgent.Models.ModelInfo :=
      { id := "bedrock-override"
        name := "Bedrock Override"
        provider := "bedrock-override"
        api := LeanAgent.AI.Api.BedrockConverseStream.api
        baseUrl := "https://example.test"
        contextWindow := 128000
        maxTokens := 4096
      }
    let stream ← LeanAgent.AI.Api.BedrockConverseStreamLazy.bedrockConverseStreamApi.streamSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 0 }] }
      {}
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "bedrock-override")
      "expected bedrock lazy wrapper override to replace builtin module"
    assertTrue (← usedOverride.get) "expected bedrock lazy wrapper to use registered override"
  finally
    LeanAgent.AI.Api.BedrockConverseStreamLazy.resetBedrockProviderModule

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

def testImagesApiRegistryReplacementPreservesOrder : IO Unit := do
  let apiA := "images-order-a"
  let apiB := "images-order-b"
  let makeProvider (api label : String) : LeanAgent.AI.Images.ImagesApiProvider :=
    { api := api
      generateImages := fun model _context _options => do
        let timestamp ← IO.monoMsNow
        pure
          { api := model.api
            provider := model.provider
            model := model.id
            output := #[LeanAgent.AI.text label]
            timestamp := timestamp
          }
    }
  LeanAgent.AI.Images.clearImagesApiProviders
  try
    LeanAgent.AI.Images.registerImagesApiProvider (makeProvider apiA "first") (some "images-order-source-a")
    LeanAgent.AI.Images.registerImagesApiProvider (makeProvider apiB "second") (some "images-order-source-b")
    LeanAgent.AI.Images.registerImagesApiProvider
      (makeProvider apiA "replaced")
      (some "images-order-source-a-replaced")
    let providers ← LeanAgent.AI.Images.getImagesApiProviders
    assertTrue ((providers.map (·.api)) == #[apiA, apiB])
      "expected image API replacement to preserve registry order"
    match ← LeanAgent.AI.Images.getImagesApiProvider? apiA with
    | some provider =>
        let result ← provider.generateImages
          { fakeImagesModel with api := apiA, provider := "images-order", id := "image-a" }
          { input := #[LeanAgent.AI.text "draw"] }
          {}
        assertTrue (LeanAgent.AI.contentPlainText result.output == "replaced")
          "expected image API replacement to update the registered provider"
    | none => fail "expected image API replacement provider lookup"
  finally
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

def testCompatImageEntrypointsDispatchAndCatalog : IO Unit := do
  LeanAgent.AI.Compat.resetImagesApiProviders
  let seenPrompt ← IO.mkRef ""
  LeanAgent.AI.Compat.registerImagesApiProvider
    { api := fakeImagesModel.api
      generateImages := fun model context options => do
        seenPrompt.set (LeanAgent.AI.contentPlainText context.input)
        let timestamp ← IO.monoMsNow
        pure
          { api := model.api
            provider := model.provider
            model := model.id
            output :=
              #[ LeanAgent.AI.text ((options.apiKey.getD "missing-key") ++ ":compat-image")
               , LeanAgent.AI.image "QUJD" "image/png"
               ]
            timestamp := timestamp
          }
    }
    (some "compat-images-test")
  match ← LeanAgent.AI.Compat.getImagesApiProvider? fakeImagesModel.api with
  | some provider => assertTrue (provider.api == fakeImagesModel.api) "expected compat image provider lookup"
  | none => fail "expected compat image provider"
  let result ← LeanAgent.AI.Compat.generateImages
    fakeImagesModel
    { input := #[LeanAgent.AI.text "draw via compat"] }
    { apiKey := some "compat-key" }
  assertTrue (LeanAgent.AI.contentPlainText result.output == "compat-key:compat-image")
    "expected compat image generation output"
  assertTrue (result.output.size == 2) "expected compat image output blocks"
  assertTrue ((← seenPrompt.get) == "draw via compat") "expected compat image context passthrough"
  assertTrue
    (LeanAgent.AI.Compat.getImageProviders.contains LeanAgent.AI.Images.Models.openRouterProviderId)
    "expected compat image provider catalog passthrough"
  match LeanAgent.AI.Compat.getImageModel?
      LeanAgent.AI.Images.Models.openRouterProviderId
      "google/gemini-2.5-flash-image" with
  | some model =>
      assertTrue (model.api == LeanAgent.AI.Api.OpenRouterImages.api)
        "expected compat image model api"
      assertTrue (model.output == #["image", "text"]) "expected compat image model metadata"
  | none => fail "expected compat image model lookup"
  match LeanAgent.AI.Compat.getImageModel
      LeanAgent.AI.Images.Models.openRouterProviderId
      "openrouter/auto" with
  | some imageModel =>
      assertTrue (imageModel.name == "Auto Router") "expected compat image getImageModel"
  | none => fail "expected compat image getImageModel"
  LeanAgent.AI.Compat.unregisterImagesApiProviders "compat-images-test"
  assertTrue ((← LeanAgent.AI.Compat.getImagesApiProvider? fakeImagesModel.api).isNone)
    "expected compat image unregister"
  assertTrue
    ((LeanAgent.AI.Compat.getImageModel "missing-images" "missing-model").isNone)
    "expected compat missing image model lookup to return none"
  LeanAgent.AI.Compat.resetImagesApiProviders

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
        IO.sleep 10
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
  match ← collection.getProvider "fake-images" with
  | some found => assertTrue (found.id == "fake-images") "expected image provider lookup"
  | none => fail "expected image provider lookup"
  assertTrue ((← collection.getModels).size == 1) "expected image model listing"
  assertTrue ((← collection.getModel? "fake-images" "fake-image-model").isSome)
    "expected image model lookup"
  assertTrue ((← collection.getModel "fake-images" "fake-image-model").isSome)
    "expected image getModel alias lookup"
  let firstTask ← IO.asTask (collection.refresh (some "fake-images"))
  let secondTask ← IO.asTask (collection.refresh (some "fake-images"))
  match ← IO.wait firstTask with
  | .ok _ => pure ()
  | .error err => throw err
  match ← IO.wait secondTask with
  | .ok _ => pure ()
  | .error err => throw err
  assertTrue ((← refreshCount.get) == 1) "expected in-flight image refresh dedupe"
  assertTrue ((← collection.getModel? "fake-images" "refreshed-image-model").isSome)
    "expected refreshed image model"
  collection.refresh
  assertTrue ((← refreshCount.get) == 2) "expected refresh-all to re-run image refresh"
  let flakyProvider ← LeanAgent.AI.Images.createImagesProvider
    { id := "flaky-images"
      name := some "Flaky Images"
      auth := fakeProviderAuth
      refreshModels := some (throw (IO.userError "fetch failed"))
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
  collection.setProvider flakyProvider
  let imageTargetedFailed ←
    try
      collection.refresh (some "flaky-images")
      pure false
    catch err =>
      assertTrue (err.toString.contains "ModelsError(model_source)")
        "expected targeted image refresh failure to wrap as model_source"
      pure true
  assertTrue imageTargetedFailed "expected targeted image refresh failure"
  collection.refresh
  collection.deleteProvider "fake-images"
  collection.deleteProvider "flaky-images"
  assertTrue ((← collection.getProviders).isEmpty) "expected image provider deletion"
  collection.setProvider provider
  collection.clearProviders
  assertTrue ((← collection.getProviders).isEmpty) "expected image provider clear"

def testImagesCollectionReplacementPreservesOrder : IO Unit := do
  let collection ← LeanAgent.AI.Images.createImagesModels
  let first ← LeanAgent.AI.Images.createImagesProvider
    { id := "image-order-a"
      name := some "Image Order A"
      auth := fakeProviderAuth
      models := #[{ fakeImagesModel with provider := "image-order-a", id := "image-a1" }]
      api :=
        { generateImages := fun model _context _options => do
            let timestamp ← IO.monoMsNow
            pure
              { api := model.api
                provider := model.provider
                model := model.id
                output := #[LeanAgent.AI.text "first"]
                timestamp := timestamp
              }
        }
    }
  let second ← LeanAgent.AI.Images.createImagesProvider
    { id := "image-order-b"
      name := some "Image Order B"
      auth := fakeProviderAuth
      models := #[{ fakeImagesModel with provider := "image-order-b", id := "image-b1" }]
      api :=
        { generateImages := fun model _context _options => do
            let timestamp ← IO.monoMsNow
            pure
              { api := model.api
                provider := model.provider
                model := model.id
                output := #[LeanAgent.AI.text "second"]
                timestamp := timestamp
              }
        }
    }
  let replacement ← LeanAgent.AI.Images.createImagesProvider
    { id := "image-order-a"
      name := some "Image Order A Replaced"
      auth := fakeProviderAuth
      models := #[{ fakeImagesModel with provider := "image-order-a", id := "image-a2" }]
      api :=
        { generateImages := fun model _context _options => do
            let timestamp ← IO.monoMsNow
            pure
              { api := model.api
                provider := model.provider
                model := model.id
                output := #[LeanAgent.AI.text "replacement"]
                timestamp := timestamp
              }
        }
    }
  collection.setProvider first
  collection.setProvider second
  collection.setProvider replacement
  let providers ← collection.getProviders
  assertTrue ((providers.map (·.id)) == #["image-order-a", "image-order-b"])
    "expected image provider replacement to preserve collection order"
  match ← collection.getProvider? "image-order-a" with
  | some provider =>
      assertTrue (provider.name == "Image Order A Replaced")
        "expected image provider replacement to update the provider entry"
  | none => fail "expected replaced image provider lookup"
  assertTrue ((← collection.getModel? "image-order-a" "image-a2").isSome)
    "expected replacement image provider model to be visible"
  assertTrue ((← collection.getModel? "image-order-a" "image-a1").isNone)
    "expected replaced image provider model list to be updated"

def testImagesCollectionAppliesAuthAndOptions : IO Unit := do
  let seenApiKey ← IO.mkRef (none : Option String)
  let seenBaseUrl ← IO.mkRef ""
  let seenHeaders ← IO.mkRef (#[] : Array (String × Option String))
  let seenEnv ← IO.mkRef (#[] : Array (String × String))
  let customAuth : LeanAgent.AI.Auth.ProviderAuth :=
    { apiKey :=
        some
          { name := "Image custom auth"
            resolve := fun model _ctx _credential => do
              pure
                (some
                  { auth :=
                      { apiKey := some "auth-key"
                        baseUrl := some ((model.baseUrl.getD "missing-base") ++ "/auth")
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

def testImagesCollectionAppliesOAuthAuth : IO Unit := do
  let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let _ ← store.modify "fake-images" fun _ =>
    pure
      (some
        (.oauth
          { access := "image-oauth-token"
            refresh := "image-refresh"
            expires := 2000
            extra := #[("baseUrl", LeanAgent.Json.str "https://image-oauth.test")]
          }))
  let refreshCalls ← IO.mkRef 0
  let oauthAuth : LeanAgent.AI.Auth.OAuthAuth :=
    { name := "Image OAuth"
      login := fun _ => throw (IO.userError "unexpected image OAuth login")
      refresh := fun credential => do
        refreshCalls.modify (· + 1)
        pure { credential with access := credential.access ++ "-refreshed", expires := 5000 }
      toAuth := fun credential => do
        pure
          { apiKey := some credential.access
            baseUrl := oauthExtraString? credential "baseUrl"
          }
    }
  let provider ← LeanAgent.AI.Images.createImagesProvider
    { id := "fake-images"
      name := some "Fake Images OAuth"
      auth := { apiKey := none, oauth := some oauthAuth }
      models := #[fakeImagesModel]
      api :=
        { generateImages := fun _model _context _options => do
            let timestamp ← IO.monoMsNow
            pure
              { api := fakeImagesModel.api
                provider := fakeImagesModel.provider
                model := fakeImagesModel.id
                output := #[LeanAgent.AI.text "oauth-image-result"]
                timestamp := timestamp
              }
        }
    }
  let collection :=
    { (← LeanAgent.AI.Images.createImagesModels (some store) (fakeAuthContextWithNow 1000)) with
      providersRef := ← IO.mkRef #[provider]
    }
  match ← collection.getAuth fakeImagesModel with
  | some result =>
      assertTrue (result.auth.apiKey == some "image-oauth-token") "expected image OAuth access token"
      assertTrue (result.auth.baseUrl == some "https://image-oauth.test") "expected image OAuth base URL"
      assertTrue (result.source == some "OAuth") "expected image OAuth source"
  | none => fail "expected image OAuth auth result"
  assertTrue ((← refreshCalls.get) == 0) "fresh image OAuth credential should not refresh"

  let _ ← store.modify "fake-images" fun _ =>
    pure
      (some
        (.oauth
          { access := "expired-image-token"
            refresh := "image-refresh-1"
            expires := 999
          }))
  let collectionExpired :=
    { (← LeanAgent.AI.Images.createImagesModels (some store) (fakeAuthContextWithNow 1000)) with
      providersRef := ← IO.mkRef
        #[{ provider with auth := { apiKey := none, oauth := some oauthAuth } }]
    }
  match ← collectionExpired.getAuth fakeImagesModel with
  | some result =>
      assertTrue (result.auth.apiKey == some "expired-image-token-refreshed")
        "expected refreshed image OAuth access token"
      assertTrue (result.source == some "OAuth") "expected refreshed image OAuth source"
  | none => fail "expected refreshed image OAuth auth result"
  assertTrue ((← refreshCalls.get) == 1) "expired image OAuth credential should refresh once"

def testImagesCollectionUnknownProviderReturnsError : IO Unit := do
  let collection ← LeanAgent.AI.Images.createImagesModels
  let result ← collection.generateImages fakeImagesModel { input := #[LeanAgent.AI.text "draw"] }
  assertTrue (result.stopReason == .error) "expected unknown image provider error result"
  assertTrue
    (match result.errorMessage with
     | some message => message.contains "Unknown provider: fake-images"
     | none => false)
    "expected unknown provider error message"


def testImagesCollectionAbortSignalReturnsAborted : IO Unit := do
  let calledRef ← IO.mkRef false
  let provider ← LeanAgent.AI.Images.createImagesProvider
    { id := "fake-images"
      name := some "Fake Images"
      auth := fakeProviderAuth
      models := #[fakeImagesModel]
      api :=
        { generateImages := fun model _context _options => do
            calledRef.set true
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
  let signalRef ← IO.mkRef true
  let signal : LeanAgent.AI.Util.Abort.AbortSignal := { isAborted := signalRef.get }
  let result ← collection.generateImages
    fakeImagesModel
    { input := #[LeanAgent.AI.text "draw"] }
    { signal := some signal }
  assertTrue (result.stopReason == .aborted) "expected image collection abort result"
  assertTrue (result.errorMessage == some LeanAgent.AI.Util.Abort.requestAbortedMessage)
    "expected image collection abort message"
  assertTrue (!(← calledRef.get)) "expected image provider not to run after abort"

def testOpenRouterImagesAbortSignalReturnsAborted : IO Unit := do
  let signalRef ← IO.mkRef true
  let signal : LeanAgent.AI.Util.Abort.AbortSignal := { isAborted := signalRef.get }
  let model : LeanAgent.AI.ImagesModel :=
    { fakeImagesModel with
      api := LeanAgent.AI.Api.OpenRouterImages.api
      provider := LeanAgent.AI.Api.OpenRouterImages.providerId
      baseUrl := LeanAgent.AI.Api.OpenRouterImages.baseUrl
    }
  let result ← LeanAgent.AI.Api.OpenRouterImages.generateImagesWithConfig
    { apiKey := "ignored-key" }
    model
    { input := #[LeanAgent.AI.text "draw"] }
    { signal := some signal }
  assertTrue (result.stopReason == .aborted) "expected OpenRouter image abort result"
  assertTrue (result.errorMessage == some LeanAgent.AI.Util.Abort.requestAbortedMessage)
    "expected OpenRouter image abort message"
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

def testBuiltinImagesModelsMatchesPiInvariants : IO Unit := do
  let collection ← LeanAgent.AI.Providers.All.builtinImagesModels none fakeOpenRouterImagesAuthContext
  let providers ← collection.getProviders
  assertTrue (providers.map (·.id) == #[LeanAgent.AI.Api.OpenRouterImages.providerId])
    "expected builtin image collection to expose only OpenRouter"
  let models ← collection.getModels (some LeanAgent.AI.Api.OpenRouterImages.providerId)
  assertTrue (!models.isEmpty) "expected builtin image collection to expose OpenRouter models"
  assertTrue (models.all fun model =>
      model.provider == LeanAgent.AI.Api.OpenRouterImages.providerId &&
      model.api == LeanAgent.AI.Api.OpenRouterImages.api)
    "expected builtin image collection models to belong to OpenRouter Images"
  match models[0]? with
  | some model =>
      match ← collection.getAuth model with
      | some result =>
          assertTrue (result.auth.apiKey == some "openrouter-image-key")
            "expected builtin image collection to resolve OpenRouter env auth"
          assertTrue (result.source == some LeanAgent.AI.Api.OpenRouterImages.apiKeyEnv)
            "expected builtin image collection to report OpenRouter env source"
      | none => fail "expected builtin image collection auth result"
  | none => fail "expected builtin image collection first model"

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
  LeanAgent.AI.Compat.clearApiProviders
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
  assertTrue missing "expected missing alias provider after clearing compat registry"
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

def testModelsCreateProviderSetupFailurePropagatesProviderError : IO Unit := do
  let streams : LeanAgent.Models.ProviderStreams :=
    { streamSimple := fun _ _ _ => throw (IO.userError "setup failed") }
  let provider ← LeanAgent.Models.createProvider
    { id := "fake"
      name := some "Fake"
      auth := {}
      models := #[fakeRuntimeModel]
      apis := #[{ api := fakeRuntimeModel.api, streams := streams }]
    }
  let failed ←
    try
      let _ ← provider.streamSimple fakeRuntimeModel {} {}
      pure false
    catch err =>
      pure (err.toString.contains "setup failed")
  assertTrue failed "expected provider setup failure to propagate"

def testModelsLazyProviderStreamsLoadFailureReturnsErrorStream : IO Unit := do
  let streams := LeanAgent.Models.ProviderStreams.lazy (throw (IO.userError "load failed"))
  let stream ← streams.streamSimple fakeRuntimeModel {} {}
  assertLazyErrorStream stream "load failed"

def testApiLazyApiLoadFailureReturnsErrorStream : IO Unit := do
  let streams := LeanAgent.AI.Api.Lazy.lazyApi (throw (IO.userError "api load failed"))
  let stream ← streams.streamSimple fakeRuntimeModel {} {}
  assertLazyErrorStream stream "api load failed"

def testImagesLazyProviderLoadFailureReturnsErrorResult : IO Unit := do
  let provider := LeanAgent.AI.Images.ProviderImages.lazy (throw (IO.userError "image load failed"))
  let result ← provider.generateImages fakeImagesModel { input := #[LeanAgent.AI.text "draw"] } {}
  assertTrue (result.stopReason == .error) "expected image lazy provider error result"
  assertTrue (result.errorMessage.any (fun message => message.contains "image load failed"))
    "expected image lazy provider error message"
  assertTrue (result.api == fakeImagesModel.api) "expected image lazy provider api"
  assertTrue (result.provider == fakeImagesModel.provider) "expected image lazy provider provider"
  assertTrue (result.model == fakeImagesModel.id) "expected image lazy provider model"

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
  let options := LeanAgent.AI.Providers.Streams.clampSimpleOptionsToContext model {} { reasoning := some .xhigh }
  assertTrue (options.reasoning == some .xhigh) "expected mapped xhigh to be preserved"
  let noXHigh := { model with thinkingLevelMap := #[] }
  let downgraded := LeanAgent.AI.Providers.Streams.clampSimpleOptionsToContext noXHigh {} { reasoning := some .xhigh }
  assertTrue (downgraded.reasoning == some .high) "expected unmapped xhigh to downgrade to high"
  let noReasoning := LeanAgent.AI.Providers.Streams.clampSimpleOptionsToContext fakeRuntimeModel {} { reasoning := some .high }
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

def testFauxProviderAbortSignalReturnsAborted : IO Unit := do
  let handle ← LeanAgent.AI.Providers.Faux.fauxProvider
  handle.setResponses #[.message (LeanAgent.AI.Providers.Faux.fauxTextMessage "first")]
  let signalRef ← IO.mkRef true
  let signal : LeanAgent.AI.Util.Abort.AbortSignal := { isAborted := signalRef.get }
  let collection ← LeanAgent.Models.createModels
  collection.setProvider handle.provider
  let collectionResult ← collection.completeSimple handle.getModel (fauxContext)
    { signal := some signal }
  assertTrue (collectionResult.stopReason == .aborted)
    "expected collection abort to return aborted stop reason"
  assertTrue (collectionResult.errorMessage == some LeanAgent.AI.Util.Abort.requestAbortedMessage)
    "expected collection abort message"
  assertTrue ((← handle.getPendingResponseCount) == 1)
    "expected collection abort to leave queued faux responses untouched"
  assertTrue ((← handle.state).callCount == 0)
    "expected collection abort before faux provider dispatch"
  let directResult ← handle.provider.completeSimple handle.getModel (fauxContext)
    { signal := some signal }
  assertTrue (directResult.stopReason == .aborted)
    "expected direct faux provider abort stop reason"
  assertTrue (directResult.errorMessage == some LeanAgent.AI.Util.Abort.requestAbortedMessage)
    "expected direct faux provider abort message"
  assertTrue ((← handle.getPendingResponseCount) == 1)
    "expected direct faux provider abort to leave queue untouched"
  assertTrue ((← handle.state).callCount == 0)
    "expected direct faux provider abort before state advances"

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

def testCompatRegisterFauxProviderDispatchesAndUnregisters : IO Unit := do
  LeanAgent.AI.Compat.resetApiProviders
  let registration ← LeanAgent.AI.Compat.registerFauxProvider
    { api := some "faux:compat"
      provider := some "faux-compat-provider"
      models := #[{ id := "faux-compat-model", reasoning := true }]
    }
  registration.setResponses
    #[ .message (LeanAgent.AI.Providers.Faux.fauxTextMessage "compat-response") ]
  match ← LeanAgent.AI.Compat.getApiProvider? registration.api with
  | some provider => assertTrue (provider.api == "faux:compat") "expected compat faux api registration"
  | none => fail "expected compat faux provider registration"
  let model := registration.getModel
  assertTrue (model.id == "faux-compat-model") "expected compat faux model"
  let stream ← LeanAgent.AI.Compat.streamSimpleWithApi registration.api model (fauxContext "compat")
    { sessionId := some "compat-session" }
  assertTrue
    (LeanAgent.AI.contentPlainText stream.result.content == "compat-response")
    "expected registered faux provider response"
  assertTrue (stream.result.api == "faux:compat") "expected faux response api rewrite"
  assertTrue (stream.result.provider == "faux-compat-provider") "expected faux response provider rewrite"
  assertTrue (stream.result.model == "faux-compat-model") "expected faux response model rewrite"
  assertTrue ((← registration.getPendingResponseCount) == 0) "expected compat faux queue to be exhausted"
  assertTrue ((← registration.state).callCount == 1) "expected compat faux call count"
  registration.unregister
  assertTrue ((← LeanAgent.AI.Compat.getApiProvider? registration.api).isNone)
    "expected compat faux unregister to remove provider"
  let failed ←
    try
      let _ ← LeanAgent.AI.Compat.streamSimpleWithApi registration.api model (fauxContext) {}
      pure false
    catch err =>
      assertTrue (err.toString.contains "No API provider registered") "expected unregistered faux provider error"
      pure true
  assertTrue failed "expected unregistered faux provider dispatch to fail"
  LeanAgent.AI.Compat.resetApiProviders

def testCompatStaticCatalogPassthroughs : IO Unit := do
  let providers := LeanAgent.AI.Compat.getProviders
  assertTrue (providers.contains LeanAgent.Models.deepSeekProviderId)
    "expected compat providers passthrough to include DeepSeek"
  assertTrue (providers.contains LeanAgent.AI.Providers.CloudflareAIGateway.providerId)
    "expected compat providers passthrough to include Cloudflare AI Gateway"
  let deepSeekModels := LeanAgent.AI.Compat.getModels LeanAgent.Models.deepSeekProviderId
  assertTrue (deepSeekModels.any (fun model => model.id == LeanAgent.Models.deepSeekDefaultModel))
    "expected compat models passthrough to include DeepSeek default"
  match LeanAgent.AI.Compat.getModel?
      LeanAgent.Models.deepSeekProviderId
      LeanAgent.Models.deepSeekDefaultModel with
  | some model =>
      assertTrue (model.api == "openai-completions") "expected compat model passthrough api"
      assertTrue model.reasoning "expected compat model passthrough metadata"
  | none => fail "expected compat getModel? passthrough"
  match LeanAgent.AI.Compat.getModel
      LeanAgent.Models.openAIProviderId
      LeanAgent.Models.openAIDefaultModel with
  | some model =>
      assertTrue (model.provider == LeanAgent.Models.openAIProviderId)
        "expected compat getModel result"
  | none => fail "expected compat getModel result"
  assertTrue
    ((LeanAgent.AI.Compat.getModel "missing-provider" "missing-model").isNone)
    "expected compat getModel missing model lookup to return none"

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
def testAgentSessionCreateAndContinue : IO Unit :=
  IO.FS.withTempDir fun root => do
    let path := root / "session.jsonl"
    let modelInfo : LeanAgent.Models.ModelInfo :=
      { id := "fake", name := "fake", provider := "fake", api := "fake", baseUrl := "" }
    let config : LeanAgent.Session.RuntimeAgentLoopConfig :=
      { model := modelInfo
        convertToLlm := LeanAgent.Agent.defaultConvertToLlm
      }
    let session ← LeanAgent.Session.create config root "fake" (.create path)
    let session ← LeanAgent.Session.prompt session "continue" silentAgentSink
    assertTrue (session.messages.size >= 1) "prompt should produce messages"
    let (messages, _) ← LeanAgent.Session.loadMessagesWithLastId modelInfo path
    assertTrue (messages.size >= 1) "should persist messages"

def testAgentSessionRejectsAssistantContinue : IO Unit := do
  let modelInfo : LeanAgent.Models.ModelInfo :=
    { id := "fake", name := "fake", provider := "fake", api := "fake", baseUrl := "" }
  let timestamp ← IO.monoMsNow
  let agent := LeanAgent.Agent.Agent.create
    { initialState :=
        { systemPrompt := ""
          model := modelInfo
          messages :=
            #[.ofMessage (.assistant
              { content := #[.text { text := "done" }]
                api := "fake"
                provider := "fake"
                model := "fake"
                timestamp := timestamp
              })]
        }
    }
  let session : LeanAgent.Session.AgentSession := { agent := agent }
  let failed ←
    try
      let _ ← LeanAgent.Session.continueSession session silentAgentSink
      pure false
    catch err =>
      assertTrue (err.toString.contains "cannot continue after an assistant message") "expected assistant-final continue error"
      pure true
  assertTrue failed "assistant-final session should not continue"

def testJsonEventShape : IO Unit := do
  let json ← LeanAgent.Session.jsonEvent .turnStart
  match LeanAgent.Json.optVal? json "type", LeanAgent.Json.optVal? json "timestamp" with
  | some (Lean.Json.str "turn_start"), some _ => pure ()
  | _, _ => fail "expected JSON event fields"
def httpServerScript : String :=
  String.intercalate "\n"
    [ "import json"
    , "import base64"
    , "import struct"
    , "import sys"
    , "import zlib"
    , "from urllib.parse import parse_qs"
    , "from http.server import BaseHTTPRequestHandler, HTTPServer"
    , "def _aws_eventstream_header(name, value):"
    , "    name_bytes = name.encode('utf-8')"
    , "    value_bytes = value.encode('utf-8')"
    , "    return bytes([len(name_bytes)]) + name_bytes + bytes([7]) + len(value_bytes).to_bytes(2, 'big') + value_bytes"
    , "def _aws_eventstream_frame(kind, payload, message_type='event'):"
    , "    headers = [_aws_eventstream_header(':message-type', message_type)]"
    , "    if message_type == 'event':"
    , "        headers.append(_aws_eventstream_header(':event-type', kind))"
    , "    else:"
    , "        headers.append(_aws_eventstream_header(':exception-type', kind))"
    , "    headers.append(_aws_eventstream_header(':content-type', 'application/json'))"
    , "    header_bytes = b''.join(headers)"
    , "    payload_bytes = json.dumps(payload, separators=(',', ':')).encode('utf-8')"
    , "    total_len = 16 + len(header_bytes) + len(payload_bytes)"
    , "    prelude = struct.pack('>II', total_len, len(header_bytes))"
    , "    prelude_crc = struct.pack('>I', zlib.crc32(prelude) & 0xffffffff)"
    , "    without_crc = prelude + prelude_crc + header_bytes + payload_bytes"
    , "    message_crc = struct.pack('>I', zlib.crc32(without_crc) & 0xffffffff)"
    , "    return without_crc + message_crc"
    , "class Handler(BaseHTTPRequestHandler):"
    , "    retry_count = 0"
    , "    def do_GET(self):"
    , "        if self.path == '/copilot/token':"
    , "            auth = self.headers.get('Authorization') or ''"
    , "            if auth in ['Bearer ghu_refresh_token', 'Bearer github-access-token']:"
    , "                payload = json.dumps({'token': 'tid=test;exp=9999999999;proxy-ep=proxy.individual.githubcopilot.com;', 'expires_at': 9999999999}).encode('utf-8')"
    , "                self.send_response(200)"
    , "            else:"
    , "                payload = json.dumps({'error': 'unauthorized'}).encode('utf-8')"
    , "                self.send_response(401)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/copilot/models':"
    , "            auth = self.headers.get('Authorization') or ''"
    , "            if auth == 'Bearer tid=test;exp=9999999999;proxy-ep=proxy.individual.githubcopilot.com;':"
    , "                payload = json.dumps({'data': [{'id': 'gpt-4.1', 'model_picker_enabled': True, 'capabilities': {'supports': {'tool_calls': True}}}, {'id': 'claude-opus-4.7', 'model_picker_enabled': True, 'policy': {'state': 'disabled'}, 'capabilities': {'supports': {'tool_calls': True}}}, {'id': 'gpt-5.4-nano', 'model_picker_enabled': False, 'capabilities': {'supports': {'tool_calls': True}}}]}).encode('utf-8')"
    , "                self.send_response(200)"
    , "            else:"
    , "                payload = json.dumps({'data': []}).encode('utf-8')"
    , "                self.send_response(401)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        payload = json.dumps({'method': 'GET', 'path': self.path, 'auth': self.headers.get('Authorization'), 'ua': self.headers.get('User-Agent'), 'x_custom': self.headers.get('X-Custom')}).encode('utf-8')"
    , "        self.send_response(200)"
    , "        self.send_header('Content-Type', 'application/json')"
    , "        self.send_header('Content-Length', str(len(payload)))"
    , "        self.end_headers()"
    , "        self.wfile.write(payload)"
    , "    def do_POST(self):"
    , "        length = int(self.headers.get('Content-Length', '0'))"
    , "        body = self.rfile.read(length).decode('utf-8')"
    , "        if self.path == '/copilot/device-code':"
    , "            ok = 'client_id=' in body and 'scope=read%3Auser' in body"
    , "            payload = json.dumps({'device_code': 'device-code', 'user_code': 'ABCD-EFGH', 'verification_uri': 'https://github.com/login/device', 'interval': 1, 'expires_in': 900} if ok else {'error': 'bad_request'}).encode('utf-8')"
    , "            self.send_response(200 if ok else 400)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/copilot/device-code-invalid-uri':"
    , "            payload = json.dumps({'device_code': 'device-code', 'user_code': 'ABCD-EFGH', 'verification_uri': '$(id>/tmp/pwned)', 'interval': 1, 'expires_in': 900}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/copilot/device-code-escaped-uri':"
    , "            payload = json.dumps({'device_code': 'device-code', 'user_code': 'ABCD-EFGH', 'verification_uri': 'https://github.com/login/\\u001b]8;;evil', 'interval': 1, 'expires_in': 900}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/copilot/access-token':"
    , "            ok = 'client_id=' in body and 'device_code=device-code' in body and 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code' in body"
    , "            payload = json.dumps({'access_token': 'ghu_refresh_token'} if ok else {'error': 'bad_request'}).encode('utf-8')"
    , "            self.send_response(200 if ok else 400)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path.startswith('/copilot/models/') and self.path.endswith('/policy'):"
    , "            payload = b''"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Length', '0')"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/codex/deviceauth/usercode':"
    , "            request = json.loads(body or '{}')"
    , "            ok = request.get('client_id') == 'app_EMoamEEZ73f0CkXaXp7hrann'"
    , "            payload = json.dumps({'device_auth_id': 'device-auth-id', 'user_code': 'ABCD-1234', 'interval': '1'} if ok else {'error': 'bad_request'}).encode('utf-8')"
    , "            self.send_response(200 if ok else 400)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/codex/deviceauth/usercode-404':"
    , "            payload = json.dumps({'error': 'not_found'}).encode('utf-8')"
    , "            self.send_response(404)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/codex/deviceauth/token':"
    , "            request = json.loads(body or '{}')"
    , "            ok = request.get('device_auth_id') == 'device-auth-id' and request.get('user_code') == 'ABCD-1234'"
    , "            payload = json.dumps({'authorization_code': 'oauth-device-code', 'code_verifier': 'device-code-verifier'} if ok else {'error': 'bad_request'}).encode('utf-8')"
    , "            self.send_response(200 if ok else 400)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/codex/oauth/token':"
    , "            params = parse_qs(body, keep_blank_values=True)"
    , "            grant_type = (params.get('grant_type') or [''])[0]"
    , "            if grant_type == 'authorization_code':"
    , "                code = (params.get('code') or [''])[0]"
    , "                verifier = (params.get('code_verifier') or [''])[0]"
    , "                if code == 'oauth-browser-code' and verifier == 'browser-verifier':"
    , "                    payload = json.dumps({'access_token': 'e30.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdF90ZXN0In19.sig', 'refresh_token': 'codex-browser-refresh', 'expires_in': 3600}).encode('utf-8')"
    , "                    self.send_response(200)"
    , "                elif code == 'oauth-device-code' and verifier == 'device-code-verifier':"
    , "                    payload = json.dumps({'access_token': 'e30.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdF90ZXN0In19.sig', 'refresh_token': 'codex-device-refresh', 'expires_in': 3600}).encode('utf-8')"
    , "                    self.send_response(200)"
    , "                else:"
    , "                    payload = json.dumps({'error': 'invalid_grant'}).encode('utf-8')"
    , "                    self.send_response(400)"
    , "            elif grant_type == 'refresh_token':"
    , "                refresh_token = (params.get('refresh_token') or [''])[0]"
    , "                if refresh_token == 'codex-refresh-token':"
    , "                    payload = json.dumps({'access_token': 'e30.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdF90ZXN0In19.sig', 'refresh_token': 'codex-refresh-2', 'expires_in': 1800}).encode('utf-8')"
    , "                    self.send_response(200)"
    , "                else:"
    , "                    payload = json.dumps({'error': {'message': 'bad refresh token'}}).encode('utf-8')"
    , "                    self.send_response(401)"
    , "            else:"
    , "                payload = json.dumps({'error': 'unsupported_grant_type'}).encode('utf-8')"
    , "                self.send_response(400)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/anthropic/oauth/token':"
    , "            request = json.loads(body or '{}')"
    , "            grant_type = request.get('grant_type')"
    , "            if grant_type == 'authorization_code':"
    , "                if request.get('code') == 'manual-anthropic-code' and request.get('code_verifier') == 'anthropic-verifier':"
    , "                    payload = json.dumps({'access_token': 'sk-ant-oat-access-token', 'refresh_token': 'anthropic-browser-refresh', 'expires_in': 3600}).encode('utf-8')"
    , "                    self.send_response(200)"
    , "                else:"
    , "                    payload = json.dumps({'error': 'invalid_grant'}).encode('utf-8')"
    , "                    self.send_response(400)"
    , "            elif grant_type == 'refresh_token':"
    , "                if request.get('refresh_token') == 'anthropic-refresh-token':"
    , "                    payload = json.dumps({'access_token': 'sk-ant-oat-refreshed-token', 'refresh_token': 'anthropic-refresh-2', 'expires_in': 1800}).encode('utf-8')"
    , "                    self.send_response(200)"
    , "                else:"
    , "                    payload = json.dumps({'error': {'message': 'bad anthropic refresh token'}}).encode('utf-8')"
    , "                    self.send_response(401)"
    , "            else:"
    , "                payload = json.dumps({'error': 'unsupported_grant_type'}).encode('utf-8')"
    , "                self.send_response(400)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
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
    , "            self.send_header('X-Diagnostic-Trace', 'rate-limit-route')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/headers-openai/chat/completions':"
    , "            text = '|'.join([self.headers.get('X-Trace') or '', self.headers.get('session_id') or '', self.headers.get('x-client-request-id') or '', self.headers.get('x-session-affinity') or ''])"
    , "            payload = json.dumps({'choices': [{'message': {'content': text}, 'finish_reason': 'stop'}]}).encode('utf-8')"
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
    , "        if self.path == '/response-model-openai/chat/completions':"
    , "            request = json.loads(body)"
    , "            requested = request.get('model') or ''"
    , "            if requested == 'openrouter/auto':"
    , "                first_model = 'anthropic/claude-opus-4.8'"
    , "                second_model = 'anthropic/claude-opus-4.8'"
    , "            elif requested == 'openrouter/same':"
    , "                first_model = requested"
    , "                second_model = requested"
    , "            else:"
    , "                first_model = None"
    , "                second_model = ''"
    , "            first_chunk = {'id': 'chatcmpl_response_model', 'choices': [{'delta': {'content': 'hi'}, 'finish_reason': None}]}"
    , "            second_chunk = {'id': 'chatcmpl_response_model', 'choices': [{'delta': {'content': '!'}, 'finish_reason': 'stop'}], 'usage': {'prompt_tokens': 1, 'completion_tokens': 2}}"
    , "            if first_model is not None:"
    , "                first_chunk['model'] = first_model"
    , "            if second_model is not None:"
    , "                second_chunk['model'] = second_model"
    , "            payload = ("
    , "                'data: ' + json.dumps(first_chunk) + '\\n\\n' +"
    , "                'data: ' + json.dumps(second_chunk) + '\\n\\n' +"
    , "                'data: [DONE]\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/finish-reason-openai/chat/completions':"
    , "            request = json.loads(body)"
    , "            requested = request.get('model') or ''"
    , "            if requested == 'openrouter/network-error':"
    , "                chunks = ["
    , "                    {'id': 'chatcmpl-finish-error', 'choices': [{'delta': {'content': 'partial'}, 'finish_reason': None}]},"
    , "                    {'id': 'chatcmpl-finish-error', 'choices': [{'delta': {}, 'finish_reason': 'network_error'}], 'usage': {'prompt_tokens': 1, 'completion_tokens': 1, 'prompt_tokens_details': {'cached_tokens': 0}, 'completion_tokens_details': {'reasoning_tokens': 0}}},"
    , "                ]"
    , "            elif requested == 'openrouter/null-chunks':"
    , "                chunks = ["
    , "                    None,"
    , "                    {'id': 'chatcmpl-null-chunks', 'choices': [{'delta': {'content': 'OK'}, 'finish_reason': None}]},"
    , "                    {'id': 'chatcmpl-null-chunks', 'choices': [{'delta': {}, 'finish_reason': 'stop'}], 'usage': {'prompt_tokens': 3, 'completion_tokens': 1, 'prompt_tokens_details': {'cached_tokens': 0}, 'completion_tokens_details': {'reasoning_tokens': 0}}},"
    , "                ]"
    , "            else:"
    , "                chunks = ["
    , "                    {'id': 'chatcmpl-missing-finish', 'choices': [{'delta': {'content': 'partial'}, 'finish_reason': None}]},"
    , "                    {'id': 'chatcmpl-missing-finish', 'choices': [{'delta': {'content': ' answer'}, 'finish_reason': None}]},"
    , "                ]"
    , "            payload = (''.join(['data: ' + json.dumps(chunk) + '\\n\\n' for chunk in chunks]) + 'data: [DONE]\\n\\n').encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/openai-typed/chat/completions':"
    , "            request = json.loads(body)"
    , "            tool_choice = request.get('tool_choice')"
    , "            if isinstance(tool_choice, dict):"
    , "                tool_choice_text = tool_choice.get('function', {}).get('name') or ''"
    , "            else:"
    , "                tool_choice_text = tool_choice or ''"
    , "            text = '|'.join([request.get('model') or '', str(request.get('stream')), str((request.get('stream_options') or {}).get('include_usage')), str(request.get('max_completion_tokens') or ''), str(request.get('max_tokens') or ''), request.get('reasoning_effort') or '', request.get('prompt_cache_key') or '', request.get('prompt_cache_retention') or '', tool_choice_text, self.headers.get('Authorization') or '', self.headers.get('session_id') or '', self.headers.get('x-session-affinity') or '', self.headers.get('X-Trace') or ''])"
    , "            payload = ("
    , "                'data: ' + json.dumps({'id': 'chatcmpl_openai_typed_http', 'model': request.get('model') or '', 'choices': [{'delta': {'content': text[:32]}, 'finish_reason': None}], 'usage': {'prompt_tokens': 5, 'prompt_tokens_details': {'cached_tokens': 2}}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'choices': [{'delta': {'content': text[32:]}, 'finish_reason': 'stop'}], 'usage': {'prompt_tokens': 5, 'completion_tokens': 3, 'total_tokens': 8, 'prompt_tokens_details': {'cached_tokens': 2}}}) + '\\n\\n' +"
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
    , "            text = str(request.get('max_tokens') or request.get('max_completion_tokens'))"
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
    , "        if self.path == '/codex-provider/codex/responses':"
    , "            request = json.loads(body)"
    , "            text_options = request.get('text') or {}"
    , "            reasoning = request.get('reasoning') or {}"
    , "            include = request.get('include') or []"
    , "            ok = ("
    , "                request.get('model') == 'gpt-5.5' and"
    , "                request.get('store') is False and"
    , "                request.get('stream') is True and"
    , "                request.get('instructions') == 'codex system' and"
    , "                text_options.get('verbosity') == 'low' and"
    , "                include == ['reasoning.encrypted_content'] and"
    , "                request.get('prompt_cache_key') == 'codex-session' and"
    , "                request.get('tool_choice') == 'auto' and"
    , "                request.get('parallel_tool_calls') is True and"
    , "                reasoning.get('effort') == 'low' and"
    , "                self.headers.get('chatgpt-account-id') == 'acct_test' and"
    , "                self.headers.get('originator') == 'pi' and"
    , "                self.headers.get('OpenAI-Beta') == 'responses=experimental' and"
    , "                self.headers.get('session-id') == 'codex-session' and"
    , "                self.headers.get('x-client-request-id') == 'codex-session' and"
    , "                self.headers.get('Accept') == 'text/event-stream'"
    , "            )"
    , "            text = 'codex-ok' if ok else 'codex-bad'"
    , "            payload = ("
    , "                'data: ' + json.dumps({'type': 'response.output_item.added', 'output_index': 0, 'item': {'type': 'message', 'id': 'msg_codex_http', 'content': []}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.output_text.delta', 'output_index': 0, 'delta': text}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.output_item.done', 'output_index': 0, 'item': {'type': 'message', 'id': 'msg_codex_http', 'content': [{'type': 'output_text', 'text': text}]}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.done', 'response': {'id': 'resp_codex_http', 'status': 'completed', 'usage': {'input_tokens': 4, 'output_tokens': 2, 'total_tokens': 6}}}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('X-Hook-Response', 'codex')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/codex-provider-rate-limit/codex/responses':"
    , "            payload = json.dumps({'error': {'message': 'rate limit exceeded', 'type': 'rate_limit_error', 'code': 'rate_limit'}}).encode('utf-8')"
    , "            self.send_response(429)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('X-Diagnostic-Trace', 'codex-rate-limit-route')"
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
    , "        if self.path == '/responses-stream-early-eof/responses':"
    , "            payload = ("
    , "                'data: ' + json.dumps({'type': 'response.created', 'response': {'id': 'resp_stream_early_http'}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.output_item.added', 'output_index': 0, 'item': {'type': 'reasoning', 'id': 'rs_stream_early_http', 'summary': []}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'type': 'response.reasoning_text.delta', 'output_index': 0, 'delta': 'partial reasoning before eof'}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('X-Diagnostic-Trace', 'early-eof-route')"
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
    , "            self.send_header('X-Hook-Response', 'azure-responses')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/google-stream/models/gemini-2.5-flash:streamGenerateContent?alt=sse':"
    , "            request = json.loads(body)"
    , "            contents = request.get('contents') or []"
    , "            first_parts = contents[0].get('parts') if contents else []"
    , "            first_text = first_parts[0].get('text') if first_parts else ''"
    , "            text = '|'.join([first_text or '', str('generationConfig' in request), self.headers.get('x-goog-api-key') or '', self.headers.get('X-Trace') or ''])"
    , "            payload = ("
    , "                'data: ' + json.dumps({'responseId': 'resp_google_http', 'modelVersion': 'gemini-2.5-flash', 'candidates': [{'content': {'parts': [{'text': text[:10]}]}}], 'usageMetadata': {'promptTokenCount': 4, 'cachedContentTokenCount': 1}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'candidates': [{'content': {'parts': [{'text': text[10:]}]}, 'finishReason': 'STOP'}], 'usageMetadata': {'promptTokenCount': 4, 'cachedContentTokenCount': 1, 'candidatesTokenCount': 2, 'thoughtsTokenCount': 0, 'totalTokenCount': 6}}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('X-Hook-Response', 'google')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/google-typed/models/gemini-2.5-flash:streamGenerateContent?alt=sse':"
    , "            request = json.loads(body)"
    , "            generation = request.get('generationConfig') or {}"
    , "            thinking = generation.get('thinkingConfig') or {}"
    , "            tool_config = request.get('toolConfig') or {}"
    , "            function_calling = tool_config.get('functionCallingConfig') or {}"
    , "            text = '|'.join([str(thinking.get('includeThoughts') or ''), str(thinking.get('thinkingBudget') or ''), thinking.get('thinkingLevel') or '', function_calling.get('mode') or '', self.headers.get('x-goog-api-key') or '', self.headers.get('X-Trace') or ''])"
    , "            payload = ("
    , "                'data: ' + json.dumps({'responseId': 'resp_google_typed_http', 'modelVersion': 'gemini-2.5-flash', 'candidates': [{'content': {'parts': [{'text': text[:14]}]}}], 'usageMetadata': {'promptTokenCount': 4, 'cachedContentTokenCount': 1}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'candidates': [{'content': {'parts': [{'text': text[14:]}]}, 'finishReason': 'STOP'}], 'usageMetadata': {'promptTokenCount': 4, 'cachedContentTokenCount': 1, 'candidatesTokenCount': 2, 'thoughtsTokenCount': 3, 'totalTokenCount': 9}}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/google-oauth-service-account':"
    , "            params = parse_qs(body)"
    , "            assertion = (params.get('assertion') or [''])[0]"
    , "            parts = assertion.split('.')"
    , "            if (params.get('grant_type') or [''])[0] != 'urn:ietf:params:oauth:grant-type:jwt-bearer' or len(parts) != 3:"
    , "                payload = json.dumps({'error': 'invalid_request', 'body': body}).encode('utf-8')"
    , "                self.send_response(400)"
    , "                self.send_header('Content-Type', 'application/json')"
    , "                self.send_header('Content-Length', str(len(payload)))"
    , "                self.end_headers()"
    , "                self.wfile.write(payload)"
    , "                return"
    , "            def _b64json(segment):"
    , "                segment += '=' * ((4 - len(segment) % 4) % 4)"
    , "                return json.loads(base64.urlsafe_b64decode(segment.encode('utf-8')).decode('utf-8'))"
    , "            header = _b64json(parts[0])"
    , "            claims = _b64json(parts[1])"
    , "            expected_aud = 'http://127.0.0.1:%s/google-oauth-service-account' % sys.argv[1]"
    , "            valid = header.get('alg') == 'RS256' and header.get('typ') == 'JWT' and claims.get('iss') == 'test-service@example.com' and claims.get('sub') == 'test-service@example.com' and claims.get('scope') == 'https://www.googleapis.com/auth/cloud-platform' and claims.get('aud') == expected_aud and isinstance(claims.get('iat'), int) and isinstance(claims.get('exp'), int) and claims.get('exp', 0) > claims.get('iat', 0)"
    , "            if not valid:"
    , "                payload = json.dumps({'error': 'invalid_assertion', 'header': header, 'claims': claims}).encode('utf-8')"
    , "                self.send_response(400)"
    , "                self.send_header('Content-Type', 'application/json')"
    , "                self.send_header('Content-Length', str(len(payload)))"
    , "                self.end_headers()"
    , "                self.wfile.write(payload)"
    , "                return"
    , "            payload = json.dumps({'access_token': 'adc-service-token', 'expires_in': 3600}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/google-oauth-authorized-user':"
    , "            params = parse_qs(body)"
    , "            valid = (params.get('grant_type') or [''])[0] == 'refresh_token' and (params.get('refresh_token') or [''])[0] == 'test-refresh-token' and (params.get('client_id') or [''])[0] == 'test-client-id' and (params.get('client_secret') or [''])[0] == 'test-client-secret'"
    , "            if not valid:"
    , "                payload = json.dumps({'error': 'invalid_request', 'body': body}).encode('utf-8')"
    , "                self.send_response(400)"
    , "                self.send_header('Content-Type', 'application/json')"
    , "                self.send_header('Content-Length', str(len(payload)))"
    , "                self.end_headers()"
    , "                self.wfile.write(payload)"
    , "                return"
    , "            payload = json.dumps({'access_token': 'adc-authorized-user-token', 'expires_in': 3600}).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/json')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/vertex/v1/projects/project-1/locations/us-central1/publishers/google/models/gemini-2.5-flash:streamGenerateContent?alt=sse':"
    , "            request = json.loads(body)"
    , "            contents = request.get('contents') or []"
    , "            first_parts = contents[0].get('parts') if contents else []"
    , "            first_text = first_parts[0].get('text') if first_parts else ''"
    , "            text = '|'.join([first_text or '', self.headers.get('Authorization') or '', self.headers.get('x-goog-api-key') or '', self.headers.get('X-Trace') or ''])"
    , "            payload = ("
    , "                'data: ' + json.dumps({'responseId': 'resp_vertex_http', 'modelVersion': 'gemini-2.5-flash', 'candidates': [{'content': {'parts': [{'text': text[:12]}]}}], 'usageMetadata': {'promptTokenCount': 5, 'cachedContentTokenCount': 2}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'candidates': [{'content': {'parts': [{'text': text[12:]}]}, 'finishReason': 'STOP'}], 'usageMetadata': {'promptTokenCount': 5, 'cachedContentTokenCount': 2, 'candidatesTokenCount': 3, 'thoughtsTokenCount': 0, 'totalTokenCount': 8}}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('X-Hook-Response', 'vertex')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/vertex-typed/v1/projects/project-typed/locations/europe-west4/publishers/google/models/gemini-2.5-flash:streamGenerateContent?alt=sse':"
    , "            request = json.loads(body)"
    , "            generation = request.get('generationConfig') or {}"
    , "            thinking = generation.get('thinkingConfig') or {}"
    , "            tool_config = request.get('toolConfig') or {}"
    , "            function_calling = tool_config.get('functionCallingConfig') or {}"
    , "            text = '|'.join([str(thinking.get('includeThoughts') or ''), str(thinking.get('thinkingBudget') or ''), thinking.get('thinkingLevel') or '', function_calling.get('mode') or '', self.headers.get('Authorization') or '', self.headers.get('x-goog-api-key') or '', self.headers.get('X-Trace') or ''])"
    , "            payload = ("
    , "                'data: ' + json.dumps({'responseId': 'resp_vertex_typed_http', 'modelVersion': 'gemini-2.5-flash', 'candidates': [{'content': {'parts': [{'text': text[:16]}]}}], 'usageMetadata': {'promptTokenCount': 5, 'cachedContentTokenCount': 2}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'candidates': [{'content': {'parts': [{'text': text[16:]}]}, 'finishReason': 'STOP'}], 'usageMetadata': {'promptTokenCount': 5, 'cachedContentTokenCount': 2, 'candidatesTokenCount': 3, 'thoughtsTokenCount': 5, 'totalTokenCount': 13}}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/anthropic-stream/v1/messages':"
    , "            request = json.loads(body)"
    , "            text = '|'.join([request.get('model') or '', str(request.get('stream')), self.headers.get('x-api-key') or '', self.headers.get('anthropic-version') or '', self.headers.get('X-Trace') or '', self.headers.get('x-session-affinity') or ''])"
    , "            payload = ("
    , "                'event: message_start\\n' +"
    , "                'data: ' + json.dumps({'type': 'message_start', 'message': {'id': 'msg_anthropic_http', 'model': request.get('model') or '', 'usage': {'input_tokens': 4}}}) + '\\n\\n' +"
    , "                'event: content_block_start\\n' +"
    , "                'data: ' + json.dumps({'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}}) + '\\n\\n' +"
    , "                'event: content_block_delta\\n' +"
    , "                'data: ' + json.dumps({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': text}}) + '\\n\\n' +"
    , "                'event: content_block_stop\\n' +"
    , "                'data: ' + json.dumps({'type': 'content_block_stop', 'index': 0}) + '\\n\\n' +"
    , "                'event: message_delta\\n' +"
    , "                'data: ' + json.dumps({'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}, 'usage': {'output_tokens': 2}}) + '\\n\\n' +"
    , "                'event: message_stop\\n' +"
    , "                'data: ' + json.dumps({'type': 'message_stop'}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('X-Hook-Response', 'anthropic')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/anthropic-typed/v1/messages':"
    , "            request = json.loads(body)"
    , "            thinking = request.get('thinking') or {}"
    , "            tool_choice = request.get('tool_choice') or {}"
    , "            text = '|'.join([request.get('model') or '', str(request.get('stream')), self.headers.get('x-api-key') or '', thinking.get('type') or '', str(thinking.get('budget_tokens') or ''), thinking.get('display') or '', tool_choice.get('type') or '', self.headers.get('X-Trace') or ''])"
    , "            payload = ("
    , "                'event: message_start\\n' +"
    , "                'data: ' + json.dumps({'type': 'message_start', 'message': {'id': 'msg_anthropic_typed_http', 'model': request.get('model') or '', 'usage': {'input_tokens': 4}}}) + '\\n\\n' +"
    , "                'event: content_block_start\\n' +"
    , "                'data: ' + json.dumps({'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}}) + '\\n\\n' +"
    , "                'event: content_block_delta\\n' +"
    , "                'data: ' + json.dumps({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': text}}) + '\\n\\n' +"
    , "                'event: content_block_stop\\n' +"
    , "                'data: ' + json.dumps({'type': 'content_block_stop', 'index': 0}) + '\\n\\n' +"
    , "                'event: message_delta\\n' +"
    , "                'data: ' + json.dumps({'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}, 'usage': {'output_tokens': 2}}) + '\\n\\n' +"
    , "                'event: message_stop\\n' +"
    , "                'data: ' + json.dumps({'type': 'message_stop'}) + '\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path == '/mistral/v1/chat/completions':"
    , "            request = json.loads(body)"
    , "            messages = request.get('messages') or []"
    , "            first = messages[0] if messages else {}"
    , "            content = first.get('content') or ''"
    , "            if isinstance(content, list):"
    , "                first_text = content[0].get('text') if content else ''"
    , "            else:"
    , "                first_text = content"
    , "            text = '|'.join([request.get('model') or '', str(request.get('stream')), self.headers.get('Authorization') or '', self.headers.get('x-affinity') or '', request.get('prompt_cache_key') or '', request.get('reasoning_effort') or '', request.get('prompt_mode') or '', self.headers.get('X-Trace') or '', first_text or ''])"
    , "            payload = ("
    , "                'data: ' + json.dumps({'id': 'chatcmpl_mistral_http', 'model': request.get('model') or '', 'choices': [{'delta': {'content': text[:24]}, 'finish_reason': None}], 'usage': {'prompt_tokens': 5, 'prompt_tokens_details': {'cached_tokens': 2}}}) + '\\n\\n' +"
    , "                'data: ' + json.dumps({'choices': [{'delta': {'content': text[24:]}, 'finish_reason': 'stop'}], 'usage': {'prompt_tokens': 5, 'completion_tokens': 3, 'total_tokens': 8, 'prompt_tokens_details': {'cached_tokens': 2}}}) + '\\n\\n' +"
    , "                'data: [DONE]\\n\\n'"
    , "            ).encode('utf-8')"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'text/event-stream')"
    , "            self.send_header('X-Hook-Response', 'mistral')"
    , "            self.send_header('Content-Length', str(len(payload)))"
    , "            self.end_headers()"
    , "            self.wfile.write(payload)"
    , "            return"
    , "        if self.path.startswith('/bedrock/model/') and self.path.endswith('/converse-stream'):"
    , "            request = json.loads(body or '{}')"
    , "            text = '|'.join([request.get('modelId') or '', self.headers.get('Authorization') or '', self.headers.get('X-Trace') or ''])"
    , "            midpoint = len(text) // 2"
    , "            payload = b''.join(["
    , "                _aws_eventstream_frame('messageStart', {'role': 'assistant'}),"
    , "                _aws_eventstream_frame('contentBlockDelta', {'contentBlockIndex': 0, 'delta': {'reasoningContent': {'text': 'plan', 'signature': 'sig-bedrock'}}}),"
    , "                _aws_eventstream_frame('contentBlockStop', {'contentBlockIndex': 0}),"
    , "                _aws_eventstream_frame('contentBlockDelta', {'contentBlockIndex': 1, 'delta': {'text': text[:midpoint]}}),"
    , "                _aws_eventstream_frame('contentBlockDelta', {'contentBlockIndex': 1, 'delta': {'text': text[midpoint:]}}),"
    , "                _aws_eventstream_frame('contentBlockStop', {'contentBlockIndex': 1}),"
    , "                _aws_eventstream_frame('contentBlockStart', {'contentBlockIndex': 2, 'start': {'toolUse': {'toolUseId': 'tool_bedrock', 'name': 'read'}}}),"
    , "                _aws_eventstream_frame('contentBlockDelta', {'contentBlockIndex': 2, 'delta': {'toolUse': {'input': '{\"path\":\"README.md\"}'}}}),"
    , "                _aws_eventstream_frame('contentBlockStop', {'contentBlockIndex': 2}),"
    , "                _aws_eventstream_frame('messageStop', {'stopReason': 'TOOL_USE'}),"
    , "                _aws_eventstream_frame('metadata', {'usage': {'inputTokens': 4, 'outputTokens': 5, 'cacheReadInputTokens': 1, 'cacheWriteInputTokens': 2, 'totalTokens': 12}}),"
    , "            ])"
    , "            self.send_response(200)"
    , "            self.send_header('Content-Type', 'application/vnd.amazon.eventstream')"
    , "            self.send_header('x-amzn-requestid', 'bedrock-http-test')"
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

def localRequestConfig (port : Nat) (path : String) : LeanAgent.Http.RequestConfig :=
  { url := s!"http://127.0.0.1:{port}{path}"
    timeoutSeconds := 5
    connectTimeoutSeconds := 5
    maxResponseBytes := 4096
    noProxy := some "*"
    userAgent := "lean-agent-test/0.1.0"
  }

def testBedrockConverseHelpersAndTransportBoundary : IO Unit := do
  assertTrue (LeanAgent.AI.Api.BedrockConverseStream.mapStopReason (some "END_TURN") == .stop)
    "expected Bedrock END_TURN stop"
  assertTrue (LeanAgent.AI.Api.BedrockConverseStream.mapStopReason (some "MAX_TOKENS") == .length)
    "expected Bedrock MAX_TOKENS length"
  assertTrue (LeanAgent.AI.Api.BedrockConverseStream.mapStopReason (some "TOOL_USE") == .toolUse)
    "expected Bedrock TOOL_USE"
  assertTrue (LeanAgent.AI.Api.BedrockConverseStream.mapStopReason (some "OTHER") == .error)
    "expected Bedrock unknown stop reason error"
  assertTrue
    (LeanAgent.AI.Api.BedrockConverseStream.standardEndpointRegion?
      "https://bedrock-runtime.us-west-2.amazonaws.com" == some "us-west-2")
    "expected Bedrock endpoint region"
  assertTrue
    (LeanAgent.AI.Api.BedrockConverseStream.standardEndpointRegion?
      "https://custom-bedrock.example.com" == none)
    "expected custom Bedrock endpoint to have no standard region"
  assertTrue
    (LeanAgent.AI.Api.BedrockConverseStream.shouldUseExplicitEndpoint
      "https://bedrock-runtime.us-east-1.amazonaws.com" none false)
    "expected standard endpoint to be explicit without configured region/profile"
  assertTrue
    (!LeanAgent.AI.Api.BedrockConverseStream.shouldUseExplicitEndpoint
      "https://bedrock-runtime.us-east-1.amazonaws.com" (some "us-west-2") false)
    "expected configured region to avoid explicit endpoint"
  assertTrue
    (LeanAgent.AI.Api.BedrockConverseStream.modelArnRegion?
      "arn:aws-us-gov:bedrock:us-gov-west-1:123456789012:inference-profile/global.anthropic.claude-opus-4-7-v1" ==
        some "us-gov-west-1")
    "expected Bedrock ARN region extraction"
  let headers := LeanAgent.AI.Api.BedrockConverseStream.requestHeaders
    { headers := #[("X-Config", "yes")] }
    { headers :=
        #[ ("Authorization", some "bad")
         , ("x-amz-date", some "bad")
         , ("X-Trace", some "trace-1")
         ]
    }
  assertTrue (headerValueCaseInsensitive? headers "X-Config" == some "yes")
    "expected Bedrock config header"
  assertTrue (headerValueCaseInsensitive? headers "X-Trace" == some "trace-1")
    "expected Bedrock custom header"
  assertTrue (headerValueCaseInsensitive? headers "Authorization" == none)
    "expected Bedrock reserved auth header to be filtered"
  let port := 18117
  let sawPayload ← IO.mkRef false
  let sawResponse ← IO.mkRef false
  withHttpServer port do
    let baseUrl := s!"http://127.0.0.1:{port}/bedrock"
    let model : LeanAgent.AI.ModelRef :=
      { id := "anthropic.claude-3-7-sonnet-20250219-v1:0"
        api := LeanAgent.AI.Api.BedrockConverseStream.api
        provider := LeanAgent.Models.amazonBedrockProviderId
        baseUrl := some baseUrl
      }
    let expectedText := String.intercalate "|" [model.id, "Bearer bedrock-test-token", "bedrock-trace"]
    let stream ← LeanAgent.AI.Api.BedrockConverseStream.completeStreamWithOptions
      { baseUrl := baseUrl
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        maxResponseBytes := 4096
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      model
      #["text", "image"]
      "Claude Opus 4.6 (US)"
      #[]
      true
      { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
      { bearerToken := some "bedrock-test-token"
        headers := #[("X-Trace", some "bedrock-trace")]
        onPayload := some (fun payload ref => do
          sawPayload.set true
          assertTrue (ref.api == LeanAgent.AI.Api.BedrockConverseStream.api)
            "expected Bedrock payload hook api"
          assertTrue (jsonStringField? payload "modelId" == some model.id)
            "expected Bedrock payload hook model id"
          pure none)
        onResponse := some (fun response _ => do
          sawResponse.set true
          assertTrue (response.status == 200) "expected Bedrock HTTP 200"
          assertTrue
            (headerValueCaseInsensitive? response.headers "x-amzn-requestid" == some "bedrock-http-test")
            "expected Bedrock request id header"
        )
      }
    assertTrue stream.isComplete "expected completed Bedrock stream"
    assertTrue (stream.result.stopReason == .toolUse) "expected Bedrock tool-use stop"
    assertTrue (stream.result.usage.input == 4) "expected Bedrock input tokens"
    assertTrue (stream.result.usage.output == 5) "expected Bedrock output tokens"
    assertTrue (stream.result.usage.cacheRead == 1) "expected Bedrock cache read"
    assertTrue (stream.result.usage.cacheWrite == 2) "expected Bedrock cache write"
    assertTrue (stream.result.usage.totalTokens == 12) "expected Bedrock total tokens"
    assertTrue
      (stream.result.content.any fun
        | .thinking thinking => thinking.thinking == "plan" && thinking.thinkingSignature == some "sig-bedrock"
        | _ => false)
      "expected Bedrock thinking block"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content == s!"plan\n{expectedText}")
      "expected Bedrock plain-text content"
    match LeanAgent.AI.contentToolCalls stream.result.content |>.toList with
    | [call] =>
        assertTrue (call.id == "tool_bedrock") "expected Bedrock tool id"
        assertTrue (call.name == "read") "expected Bedrock tool name"
        assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
          "expected Bedrock tool arguments"
    | _ => fail "expected one Bedrock tool call"
    assertTrue
      (stream.events.any fun
        | .thinkingDelta _ "plan" _ => true
        | _ => false)
      "expected Bedrock thinking delta event"
    assertTrue
      (stream.events.any fun
        | .textDelta _ delta _ => !delta.isEmpty && expectedText.contains delta
        | _ => false)
      "expected Bedrock text delta events"
    assertTrue
      (stream.events.any fun
        | .toolCallDelta _ delta _ => delta == "{\"path\":\"README.md\"}"
        | _ => false)
      "expected Bedrock tool delta event"
    assertTrue (← sawPayload.get) "expected Bedrock payload hook before runtime"
    assertTrue (← sawResponse.get) "expected Bedrock response hook"

def testCompatBedrockTypedLegacyAliasBoundary : IO Unit := do
  let sawPayload ← IO.mkRef false
  let sawResponse ← IO.mkRef false
  let tool : LeanAgent.AI.Tool :=
    { name := "read"
      description := "Read a file"
      parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
    }
  let port := 18118
  let model : LeanAgent.Models.ModelInfo :=
    { id := LeanAgent.Models.amazonBedrockDefaultModel
      name := "Claude Opus 4.6 (US)"
      provider := LeanAgent.Models.amazonBedrockProviderId
      api := LeanAgent.AI.Api.BedrockConverseStream.api
      baseUrl := s!"http://127.0.0.1:{port}/bedrock"
      contextWindow := 200000
      maxTokens := 64000
      reasoning := true
      thinkingLevelMap := #[{ level := .level .xhigh, mapped := some "max" }]
      input := #["text", "image"]
    }
  withHttpServer port do
    let expectedText :=
      String.intercalate "|" [model.id, "Bearer bedrock-bearer", "typed-bedrock-trace"]
    let stream ← LeanAgent.AI.Compat.Aliases.streamBedrockConverseStream
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
        tools := #[tool]
      }
      { bearerToken := some "bedrock-bearer"
        region := some "us-west-2"
        profile := some "dev"
        maxTokens := some 123
        toolChoice := some (.tool "read")
        reasoning := some .xhigh
        thinkingDisplay := some .summarized
        headers := #[("X-Trace", some "typed-bedrock-trace")]
        metadata := some (LeanAgent.Json.obj [("session", LeanAgent.Json.str "typed-bedrock")])
        onPayload := some (fun payload ref => do
          sawPayload.set true
          assertTrue (ref.api == LeanAgent.AI.Api.BedrockConverseStream.api)
            "expected typed Bedrock payload hook model api"
          assertTrue (jsonStringField? payload "modelId" == some LeanAgent.Models.amazonBedrockDefaultModel)
            "expected typed Bedrock model id"
          match jsonObjectField? payload "inferenceConfig" with
          | some inference =>
              assertTrue (LeanAgent.Json.optVal? inference "maxTokens" == some (LeanAgent.Json.nat 123))
                "expected typed Bedrock max tokens"
          | none => fail "expected typed Bedrock inference config"
          match jsonObjectField? payload "toolConfig" with
          | some toolConfig =>
              match jsonObjectField? toolConfig "toolChoice" with
              | some choice =>
                  match jsonObjectField? choice "tool" with
                  | some selected =>
                      assertTrue (jsonStringField? selected "name" == some "read")
                        "expected typed Bedrock specific tool choice"
                  | none => fail "expected typed Bedrock tool choice object"
              | none => fail "expected typed Bedrock tool choice"
          | none => fail "expected typed Bedrock tool config"
          match jsonObjectField? payload "additionalModelRequestFields" with
          | some fields =>
              match jsonObjectField? fields "thinking", jsonObjectField? fields "output_config" with
              | some thinking, some outputConfig =>
                  assertTrue (jsonStringField? thinking "display" == some "summarized")
                    "expected typed Bedrock thinking display"
                  assertTrue (jsonStringField? outputConfig "effort" == some "max")
                    "expected typed Bedrock xhigh effort mapping"
              | _, _ => fail "expected typed Bedrock thinking fields"
          | none => fail "expected typed Bedrock additional request fields"
          match jsonObjectField? payload "requestMetadata" with
          | some metadata =>
              assertTrue (jsonStringField? metadata "session" == some "typed-bedrock")
                "expected typed Bedrock metadata"
          | none => fail "expected typed Bedrock request metadata"
          pure none)
        onResponse := some (fun response _ => do
          sawResponse.set true
          assertTrue (response.status == 200) "expected typed Bedrock HTTP 200"
        )
      }
    assertTrue stream.isComplete "expected typed Bedrock alias stream to complete"
    assertTrue (stream.result.stopReason == .toolUse) "expected typed Bedrock alias tool-use stop"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content == s!"plan\n{expectedText}")
      "expected typed Bedrock alias streamed text"
    match LeanAgent.AI.contentToolCalls stream.result.content |>.toList with
    | [call] =>
        assertTrue (call.name == "read") "expected typed Bedrock alias tool name"
        assertTrue (LeanAgent.Json.optVal? call.arguments "path" == some (LeanAgent.Json.str "README.md"))
          "expected typed Bedrock alias tool arguments"
    | _ => fail "expected one typed Bedrock alias tool call"
    assertTrue (← sawPayload.get) "expected typed Bedrock alias payload hook"
    assertTrue (← sawResponse.get) "expected typed Bedrock alias response hook"

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

def testHttpClientGenericRequest : IO Unit := do
  let port := 18113
  withHttpServer port do
    let getResponse ← LeanAgent.Http.requestResponse
      { (localRequestConfig port "/generic-get?x=1") with
        method := "GET"
        authorization := some "Bearer generic-token"
        headers := #[("X-Custom", "generic-value")]
      }
    assertTrue (getResponse.status == 200) "expected generic GET status"
    assertTrue (getResponse.body.contains "\"method\": \"GET\"") "expected generic GET method echo"
    assertTrue (getResponse.body.contains "\"path\": \"/generic-get?x=1\"") "expected generic GET path"
    assertTrue (getResponse.body.contains "\"auth\": \"Bearer generic-token\"") "expected generic GET auth"
    assertTrue (getResponse.body.contains "\"x_custom\": \"generic-value\"") "expected generic GET custom header"
    let postResponse ← LeanAgent.Http.requestResponse
      { (localRequestConfig port "/generic-form") with
        method := "POST"
        authorization := some "Bearer raw-form-token"
        body := some "client_id=test&scope=read%3Auser"
        headers :=
          #[ ("Content-Type", "application/x-www-form-urlencoded")
           , ("Accept", "application/json")
           ]
      }
    assertTrue (postResponse.status == 201) "expected generic POST status"
    assertTrue (postResponse.body.contains "\"body\": \"client_id=test&scope=read%3Auser\"")
      "expected generic POST raw body"
    assertTrue (postResponse.body.contains "\"auth\": \"Bearer raw-form-token\"")
      "expected generic POST raw authorization"

def testAnthropicOAuthRefreshExchangesToken : IO Unit := do
  let port := 18118
  withHttpServer port do
    let seenBodies ← IO.mkRef (#[] : Array String)
    let runtime :=
      localAnthropicRuntime
        port
        "/anthropic/oauth/token"
        "anthropic-verifier"
        "anthropic-challenge"
        (some fun config => do
          if config.url.endsWith "/anthropic/oauth/token" then
            match config.body with
            | some body => seenBodies.modify (·.push body)
            | none => pure ()
          else
            pure ())
    let credential ← LeanAgent.AI.OAuth.Anthropic.refreshAnthropicTokenWith
      runtime
      "anthropic-refresh-token"
    assertTrue (credential.access == "sk-ant-oat-refreshed-token")
      "expected refreshed Anthropic access token"
    assertTrue (credential.refresh == "anthropic-refresh-2")
      "expected refreshed Anthropic refresh token"
    assertTrue (credential.expires == 1501000)
      "expected refreshed Anthropic expiry from runtime clock with skew"
    let bodies ← seenBodies.get
    assertTrue (bodies.any (·.contains "\"grant_type\":\"refresh_token\""))
      "expected refresh grant JSON request body"
    assertTrue (bodies.any (·.contains "\"refresh_token\":\"anthropic-refresh-token\""))
      "expected refresh token in Anthropic request body"
    assertTrue (!bodies.any (·.contains "\"scope\""))
      "expected Anthropic refresh request to omit scope"

def testAnthropicOAuthBrowserLoginUsesManualCode : IO Unit := do
  let port := 18117
  withHttpServer port do
    let seenAuth ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthAuthInfo)
    let seenTokenBodies ← IO.mkRef (#[] : Array String)
    let runtime :=
      localAnthropicRuntime
        port
        "/anthropic/oauth/token"
        "anthropic-verifier"
        "anthropic-challenge"
        (some fun config => do
          if config.url.endsWith "/anthropic/oauth/token" then
            match config.body with
            | some body => seenTokenBodies.modify (·.push body)
            | none => pure ()
          else
            pure ())
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun info => seenAuth.set (some info)
        onDeviceCode := fun _ => fail "unexpected device code callback"
        onPrompt := fun _ => throw (IO.userError "unexpected prompt fallback")
        onManualCodeInput := some (fun _ =>
          pure "http://localhost:53692/callback?code=manual-anthropic-code&state=anthropic-verifier")
        onSelect := fun _ => pure none
      }
    let credential ← LeanAgent.AI.OAuth.Anthropic.loginAnthropicWith runtime callbacks
    assertTrue (credential.access == "sk-ant-oat-access-token")
      "expected browser login to exchange Anthropic access token"
    assertTrue (credential.refresh == "anthropic-browser-refresh")
      "expected browser login Anthropic refresh token"
    assertTrue (credential.expires == 3301000)
      "expected browser login Anthropic expiry from runtime clock with skew"
    match ← seenAuth.get with
    | some info =>
        assertTrue (info.url.contains "response_type=code")
          "expected Anthropic auth response type"
        assertTrue
          (info.url.contains "redirect_uri=http%3A%2F%2Flocalhost%3A53692%2Fcallback")
          "expected Anthropic auth redirect URI"
        assertTrue (info.url.contains "state=anthropic-verifier")
          "expected Anthropic auth state"
        assertTrue (info.url.contains "code_challenge=anthropic-challenge")
          "expected Anthropic auth code challenge"
        assertTrue
          (info.instructions ==
            some "Complete login in your browser. If the browser is on another machine, paste the final redirect URL here.")
          "expected Anthropic auth instructions"
    | none => fail "expected Anthropic auth callback"
    let tokenBodies ← seenTokenBodies.get
    assertTrue (tokenBodies.size == 1) "expected one Anthropic authorization code exchange"
    assertTrue (tokenBodies.any (·.contains "\"grant_type\":\"authorization_code\""))
      "expected authorization_code grant request"
    assertTrue (tokenBodies.any (·.contains "\"code\":\"manual-anthropic-code\""))
      "expected Anthropic authorization code in request"
    assertTrue
      (tokenBodies.any (·.contains "\"redirect_uri\":\"http://localhost:53692/callback\""))
      "expected Anthropic redirect URI in token request"

def testAnthropicOAuthBrowserLoginUsesLocalCallback : IO Unit := do
  let port := 18115
  withHttpServer port do
    let callbackPort := 19692
    let seenAuth ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthAuthInfo)
    let seenTokenBodies ← IO.mkRef (#[] : Array String)
    let runtime :=
      { (localAnthropicRuntime
            port
            "/anthropic/oauth/token"
            "anthropic-verifier"
            "anthropic-challenge"
            (some fun config => do
              if config.url.endsWith "/anthropic/oauth/token" then
                match config.body with
                | some body => seenTokenBodies.modify (·.push body)
                | none => pure ()
              else
                pure ())) with
        redirectUri := s!"http://localhost:{callbackPort}/callback"
      }
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun info => seenAuth.set (some info)
        onDeviceCode := fun _ => fail "unexpected device code callback"
        onPrompt := fun _ => throw (IO.userError "unexpected prompt fallback")
        onManualCodeInput := some (fun _ => do
          IO.sleep 300
          pure "")
        onSelect := fun _ => pure none
      }
    let loginTask ← IO.asTask (LeanAgent.AI.OAuth.Anthropic.loginAnthropicWith runtime callbacks)
    let info ← waitForSome seenAuth.get "expected Anthropic auth callback"
    assertTrue
      (info.instructions ==
        some "Complete login in your browser. If the browser is on another machine, paste the final redirect URL here.")
      "expected Anthropic auth instructions"
    let callbackResponse ← LeanAgent.Http.requestResponse
      { (localRequestConfig callbackPort "/callback?code=manual-anthropic-code&state=anthropic-verifier") with
        method := "GET"
      }
    assertTrue (callbackResponse.status == 200) "expected Anthropic localhost callback success status"
    assertTrue
      (callbackResponse.body.contains "Anthropic authentication completed. You can close this window.")
      "expected Anthropic localhost callback success page"
    let credential ←
      match ← IO.wait loginTask with
      | .ok credential => pure credential
      | .error err => throw err
    assertTrue (credential.access == "sk-ant-oat-access-token")
      "expected localhost callback Anthropic access token"
    assertTrue (credential.refresh == "anthropic-browser-refresh")
      "expected localhost callback Anthropic refresh token"
    let tokenBodies ← seenTokenBodies.get
    assertTrue (tokenBodies.size == 1) "expected one Anthropic localhost callback exchange"
    assertTrue (tokenBodies.any (·.contains "\"code\":\"manual-anthropic-code\""))
      "expected Anthropic localhost callback authorization code"
    assertTrue
      (tokenBodies.any (·.contains s!"\"redirect_uri\":\"http://localhost:{callbackPort}/callback\""))
      "expected Anthropic localhost callback redirect URI in token request"

def testAnthropicOAuthLocalCallbackAbortsManualCodePrompt : IO Unit := do
  let port := 18124
  withHttpServer port do
    let callbackPort := 19693
    let seenAuth ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthAuthInfo)
    let manualPromptAborted ← IO.mkRef false
    let sawManualSignal ← IO.mkRef false
    let runtime :=
      { (localAnthropicRuntime port) with
        redirectUri := s!"http://localhost:{callbackPort}/callback"
      }
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun info => seenAuth.set (some info)
        onDeviceCode := fun _ => fail "unexpected device code callback"
        onPrompt := fun _ => throw (IO.userError "unexpected prompt fallback")
        onManualCodeInput := some (fun prompt => do
          sawManualSignal.set prompt.signal.isSome
          match prompt.signal with
          | some signal =>
              try
                LeanAgent.AI.Util.Abort.sleep
                  (fun ms => IO.sleep (UInt32.ofNat ms))
                  5000
                  (some signal)
                  10
                  (some LeanAgent.AI.OAuth.cancelMessage)
                pure ""
              catch err =>
                if err.toString.contains LeanAgent.AI.OAuth.cancelMessage then
                  manualPromptAborted.set true
                throw err
          | none =>
              throw (IO.userError "expected manual-code prompt abort signal"))
        onSelect := fun _ => pure none
      }
    let loginTask ← IO.asTask (LeanAgent.AI.OAuth.Anthropic.loginAnthropicWith runtime callbacks)
    let _ ← waitForSome seenAuth.get "expected Anthropic auth callback before callback-server test"
    let callbackResponse ← LeanAgent.Http.requestResponse
      { (localRequestConfig callbackPort "/callback?code=manual-anthropic-code&state=anthropic-verifier") with
        method := "GET"
      }
    assertTrue (callbackResponse.status == 200) "expected Anthropic localhost callback success status"
    let _ ←
      match ← IO.wait loginTask with
      | .ok credential => pure credential
      | .error err => throw err
    assertTrue (← sawManualSignal.get) "expected Anthropic manual-code prompt to receive abort signal"
    let _ ← waitForSome
      (do
        if ← manualPromptAborted.get then
          pure (some ())
        else
          pure none)
      "expected Anthropic manual-code prompt to abort after callback login settles"
    pure ()

def testAnthropicOAuthBrowserLoginRejectsStateMismatch : IO Unit := do
  let port := 18116
  withHttpServer port do
    let seenTokenBodies ← IO.mkRef (#[] : Array String)
    let runtime :=
      localAnthropicRuntime
        port
        "/anthropic/oauth/token"
        "anthropic-verifier"
        "anthropic-challenge"
        (some fun config => do
          if config.url.endsWith "/anthropic/oauth/token" then
            match config.body with
            | some body => seenTokenBodies.modify (·.push body)
            | none => pure ()
          else
            pure ())
    let failed ←
      try
        let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
          { onAuth := fun _ => pure ()
            onDeviceCode := fun _ => fail "unexpected device code callback"
            onPrompt := fun _ => throw (IO.userError "unexpected prompt fallback")
            onManualCodeInput := some (fun _ =>
              pure "http://localhost:53692/callback?code=manual-anthropic-code&state=wrong-state")
            onSelect := fun _ => pure none
          }
        let _ ← LeanAgent.AI.OAuth.Anthropic.loginAnthropicWith runtime callbacks
        pure false
      catch err =>
        assertTrue (err.toString.contains "OAuth state mismatch")
          "expected Anthropic browser login state mismatch rejection"
        pure true
    assertTrue failed "expected Anthropic browser login with mismatched state to fail"
    assertTrue ((← seenTokenBodies.get).isEmpty)
      "expected Anthropic state mismatch to stop before token exchange"

def testOpenAICodexOAuthRefreshExchangesToken : IO Unit := do
  let port := 18119
  withHttpServer port do
    let seenBodies ← IO.mkRef (#[] : Array String)
    let runtime :=
      localOpenAICodexRuntime
        port
        "/codex/deviceauth/usercode"
        "/codex/deviceauth/token"
        "/codex/oauth/token"
        "state-123"
        "browser-verifier"
        "browser-challenge"
        "lean-agent"
        (some fun config => do
          if config.url.endsWith "/codex/oauth/token" then
            match config.body with
            | some body => seenBodies.modify (·.push body)
            | none => pure ()
          else
            pure ())
    let credential ← LeanAgent.AI.OAuth.OpenAICodex.refreshOpenAICodexTokenWith
      runtime
      "codex-refresh-token"
    assertTrue (credential.access == fakeOpenAICodexJwt)
      "expected refreshed OpenAI Codex access token"
    assertTrue (credential.refresh == "codex-refresh-2")
      "expected refreshed OpenAI Codex refresh token"
    assertTrue (credential.expires == 1800000 + 1000)
      "expected refreshed OpenAI Codex expiry from runtime clock"
    let bodies ← seenBodies.get
    assertTrue (bodies.any (·.contains "grant_type=refresh_token"))
      "expected refresh grant request body"
    assertTrue (bodies.any (·.contains "refresh_token=codex-refresh-token"))
      "expected refresh token in request body"

def testOpenAICodexOAuthBrowserLoginUsesManualCode : IO Unit := do
  let port := 18120
  withHttpServer port do
    let seenAuth ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthAuthInfo)
    let seenTokenBodies ← IO.mkRef (#[] : Array String)
    let runtime :=
      localOpenAICodexRuntime
        port
        "/codex/deviceauth/usercode"
        "/codex/deviceauth/token"
        "/codex/oauth/token"
        "state-123"
        "browser-verifier"
        "browser-challenge"
        "lean-agent"
        (some fun config => do
          if config.url.endsWith "/codex/oauth/token" then
            match config.body with
            | some body => seenTokenBodies.modify (·.push body)
            | none => pure ()
          else
            pure ())
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun info => seenAuth.set (some info)
        onDeviceCode := fun _ => fail "unexpected device code callback"
        onPrompt := fun _ => throw (IO.userError "unexpected prompt fallback")
        onManualCodeInput := some (fun _ =>
          pure "http://localhost:1455/auth/callback?code=oauth-browser-code&state=state-123")
        onSelect := fun _ => pure (some LeanAgent.AI.OAuth.OpenAICodex.browserLoginMethod)
      }
    let credential ← LeanAgent.AI.OAuth.OpenAICodex.loginOpenAICodexWith
      runtime
      callbacks
    assertTrue (credential.access == fakeOpenAICodexJwt)
      "expected browser login to exchange OpenAI Codex access token"
    assertTrue (credential.refresh == "codex-browser-refresh")
      "expected browser login refresh token"
    assertTrue (credential.expires == 3600000 + 1000)
      "expected browser login expiry from runtime clock"
    match ← seenAuth.get with
    | some info =>
        assertTrue (info.url.contains "response_type=code")
          "expected browser auth response type"
        assertTrue (info.url.contains "code_challenge=browser-challenge")
          "expected browser auth code challenge"
        assertTrue (info.url.contains "state=state-123")
          "expected browser auth state"
        assertTrue (info.url.contains "originator=lean-agent")
          "expected browser auth originator"
        assertTrue
          (info.instructions == some "A browser window should open. Complete login to finish.")
          "expected browser auth instructions"
    | none => fail "expected browser auth callback"
    let tokenBodies ← seenTokenBodies.get
    assertTrue (tokenBodies.size == 1) "expected one authorization code exchange"
    assertTrue (tokenBodies.any (·.contains "grant_type=authorization_code"))
      "expected authorization_code grant request"
    assertTrue (tokenBodies.any (·.contains "code=oauth-browser-code"))
      "expected browser authorization code in request"
    assertTrue (tokenBodies.any (·.contains "code_verifier=browser-verifier"))
      "expected browser code verifier in request"

def testOpenAICodexOAuthBrowserLoginUsesLocalCallback : IO Unit := do
  let port := 18114
  withHttpServer port do
    let callbackPort := 21455
    let seenAuth ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthAuthInfo)
    let seenTokenBodies ← IO.mkRef (#[] : Array String)
    let runtime :=
      { (localOpenAICodexRuntime
            port
            "/codex/deviceauth/usercode"
            "/codex/deviceauth/token"
            "/codex/oauth/token"
            "state-123"
            "browser-verifier"
            "browser-challenge"
            "lean-agent"
            (some fun config => do
              if config.url.endsWith "/codex/oauth/token" then
                match config.body with
                | some body => seenTokenBodies.modify (·.push body)
                | none => pure ()
              else
                pure ())) with
        urls := { (localOpenAICodexRuntime port).urls with redirectUri := s!"http://localhost:{callbackPort}/auth/callback" }
      }
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun info => seenAuth.set (some info)
        onDeviceCode := fun _ => fail "unexpected device code callback"
        onPrompt := fun _ => throw (IO.userError "unexpected prompt fallback")
        onManualCodeInput := some (fun _ => do
          IO.sleep 300
          pure "")
        onSelect := fun _ => pure (some LeanAgent.AI.OAuth.OpenAICodex.browserLoginMethod)
      }
    let loginTask ← IO.asTask (LeanAgent.AI.OAuth.OpenAICodex.loginOpenAICodexWith runtime callbacks)
    let info ← waitForSome seenAuth.get "expected OpenAI Codex auth callback"
    assertTrue
      (info.instructions == some "A browser window should open. Complete login to finish.")
      "expected OpenAI Codex auth instructions"
    let callbackResponse ← LeanAgent.Http.requestResponse
      { (localRequestConfig callbackPort "/auth/callback?code=oauth-browser-code&state=state-123") with
        method := "GET"
      }
    assertTrue (callbackResponse.status == 200) "expected OpenAI Codex localhost callback success status"
    assertTrue
      (callbackResponse.body.contains "OpenAI authentication completed. You can close this window.")
      "expected OpenAI Codex localhost callback success page"
    let credential ←
      match ← IO.wait loginTask with
      | .ok credential => pure credential
      | .error err => throw err
    assertTrue (credential.access == fakeOpenAICodexJwt)
      "expected localhost callback OpenAI Codex access token"
    assertTrue (credential.refresh == "codex-browser-refresh")
      "expected localhost callback OpenAI Codex refresh token"
    let tokenBodies ← seenTokenBodies.get
    assertTrue (tokenBodies.size == 1) "expected one OpenAI Codex localhost callback exchange"
    assertTrue (tokenBodies.any (·.contains "code=oauth-browser-code"))
      "expected OpenAI Codex localhost callback authorization code"
    assertTrue
      (tokenBodies.any (·.contains s!"redirect_uri=http%3A%2F%2Flocalhost%3A{callbackPort}%2Fauth%2Fcallback"))
      "expected OpenAI Codex localhost callback redirect URI in token request"

def testOpenAICodexOAuthLocalCallbackAbortsManualCodePrompt : IO Unit := do
  let port := 18125
  withHttpServer port do
    let callbackPort := 21456
    let seenAuth ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthAuthInfo)
    let manualPromptAborted ← IO.mkRef false
    let sawManualSignal ← IO.mkRef false
    let baseRuntime := localOpenAICodexRuntime port
    let runtime :=
      { baseRuntime with
        urls := { baseRuntime.urls with redirectUri := s!"http://localhost:{callbackPort}/auth/callback" }
      }
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun info => seenAuth.set (some info)
        onDeviceCode := fun _ => fail "unexpected device code callback"
        onPrompt := fun _ => throw (IO.userError "unexpected prompt fallback")
        onManualCodeInput := some (fun prompt => do
          sawManualSignal.set prompt.signal.isSome
          match prompt.signal with
          | some signal =>
              try
                LeanAgent.AI.Util.Abort.sleep
                  (fun ms => IO.sleep (UInt32.ofNat ms))
                  5000
                  (some signal)
                  10
                  (some LeanAgent.AI.OAuth.cancelMessage)
                pure ""
              catch err =>
                if err.toString.contains LeanAgent.AI.OAuth.cancelMessage then
                  manualPromptAborted.set true
                throw err
          | none =>
              throw (IO.userError "expected manual-code prompt abort signal"))
        onSelect := fun _ => pure (some LeanAgent.AI.OAuth.OpenAICodex.browserLoginMethod)
      }
    let loginTask ← IO.asTask (LeanAgent.AI.OAuth.OpenAICodex.loginOpenAICodexWith runtime callbacks)
    let _ ← waitForSome seenAuth.get "expected OpenAI Codex auth callback before callback-server test"
    let callbackResponse ← LeanAgent.Http.requestResponse
      { (localRequestConfig callbackPort "/auth/callback?code=oauth-browser-code&state=state-123") with
        method := "GET"
      }
    assertTrue (callbackResponse.status == 200) "expected OpenAI Codex localhost callback success status"
    let _ ←
      match ← IO.wait loginTask with
      | .ok credential => pure credential
      | .error err => throw err
    assertTrue (← sawManualSignal.get) "expected OpenAI Codex manual-code prompt to receive abort signal"
    let _ ← waitForSome
      (do
        if ← manualPromptAborted.get then
          pure (some ())
        else
          pure none)
      "expected OpenAI Codex manual-code prompt to abort after callback login settles"
    pure ()

def testOpenAICodexOAuthBrowserLoginRejectsStateMismatch : IO Unit := do
  let port := 18121
  withHttpServer port do
    let seenTokenBodies ← IO.mkRef (#[] : Array String)
    let runtime :=
      localOpenAICodexRuntime
        port
        "/codex/deviceauth/usercode"
        "/codex/deviceauth/token"
        "/codex/oauth/token"
        "state-123"
        "browser-verifier"
        "browser-challenge"
        "lean-agent"
        (some fun config => do
          if config.url.endsWith "/codex/oauth/token" then
            match config.body with
            | some body => seenTokenBodies.modify (·.push body)
            | none => pure ()
          else
            pure ())
    let failed ←
      try
        let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
          { onAuth := fun _ => pure ()
            onDeviceCode := fun _ => fail "unexpected device code callback"
            onPrompt := fun _ => throw (IO.userError "unexpected prompt fallback")
            onManualCodeInput := some (fun _ =>
              pure "http://localhost:1455/auth/callback?code=oauth-browser-code&state=wrong-state")
            onSelect := fun _ => pure (some LeanAgent.AI.OAuth.OpenAICodex.browserLoginMethod)
          }
        let _ ← LeanAgent.AI.OAuth.OpenAICodex.loginOpenAICodexWith runtime callbacks
        pure false
      catch err =>
        assertTrue (err.toString.contains "State mismatch")
          "expected browser login state mismatch rejection"
        pure true
    assertTrue failed "expected browser login with mismatched state to fail"
    assertTrue ((← seenTokenBodies.get).isEmpty)
      "expected state mismatch to stop before token exchange"

def testOpenAICodexOAuthProviderDeviceCodeLogin : IO Unit := do
  let port := 18122
  withHttpServer port do
    let seenDeviceCode ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthDeviceCodeInfo)
    let seenTokenBodies ← IO.mkRef (#[] : Array String)
    let runtime :=
      localOpenAICodexRuntime
        port
        "/codex/deviceauth/usercode"
        "/codex/deviceauth/token"
        "/codex/oauth/token"
        "state-123"
        "browser-verifier"
        "browser-challenge"
        "lean-agent"
        (some fun config => do
          if config.url.endsWith "/codex/oauth/token" then
            match config.body with
            | some body => seenTokenBodies.modify (·.push body)
            | none => pure ()
          else
            pure ())
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun _ => fail "unexpected browser auth callback"
        onDeviceCode := fun info => seenDeviceCode.set (some info)
        onPrompt := fun _ => throw (IO.userError "unexpected prompt during device-code login")
        onSelect := fun _ => pure (some LeanAgent.AI.OAuth.OpenAICodex.deviceCodeLoginMethod)
      }
    let credential ← (LeanAgent.AI.OAuth.OpenAICodex.oauthProviderWith runtime).login callbacks
    match ← seenDeviceCode.get with
    | some info =>
        assertTrue (info.userCode == "ABCD-1234")
          "expected OpenAI Codex device user code"
        assertTrue (info.verificationUri == s!"http://127.0.0.1:{port}/codex/device")
          "expected OpenAI Codex device verification URI"
        assertTrue (info.intervalSeconds == some 1)
          "expected OpenAI Codex device polling interval"
        assertTrue (info.expiresInSeconds == some (15 * 60))
          "expected OpenAI Codex device timeout"
    | none => fail "expected OpenAI Codex device code callback"
    assertTrue (credential.access == fakeOpenAICodexJwt)
      "expected device-code login to exchange OpenAI Codex access token"
    assertTrue (credential.refresh == "codex-device-refresh")
      "expected device-code login refresh token"
    let tokenBodies ← seenTokenBodies.get
    assertTrue (tokenBodies.size == 1) "expected one device authorization exchange"
    assertTrue (tokenBodies.any (·.contains "code=oauth-device-code"))
      "expected device authorization code in request"
    assertTrue (tokenBodies.any (·.contains "code_verifier=device-code-verifier"))
      "expected device code verifier in request"

def testOpenAICodexOAuthDeviceCodeStart404UsesHelpfulError : IO Unit := do
  let port := 18123
  withHttpServer port do
    let failed ←
      try
        let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
          { onAuth := fun _ => fail "unexpected browser auth callback"
            onDeviceCode := fun _ => fail "unexpected device code callback"
            onPrompt := fun _ => throw (IO.userError "unexpected prompt")
            onSelect := fun _ => pure (some LeanAgent.AI.OAuth.OpenAICodex.deviceCodeLoginMethod)
          }
        let _ ← LeanAgent.AI.OAuth.OpenAICodex.loginOpenAICodexWith
          (localOpenAICodexRuntime port "/codex/deviceauth/usercode-404")
          callbacks
        pure false
      catch err =>
        assertTrue
          (err.toString.contains
            "OpenAI Codex device code login is not enabled for this server")
          "expected OpenAI Codex 404 device-code hint"
        pure true
    assertTrue failed "expected OpenAI Codex device-code 404 to fail with hint"

def testOpenAICodexOAuthDeviceCodeLoginRespectsAbortSignal : IO Unit := do
  let port := 18126
  withHttpServer port do
    let seenDeviceCode ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthDeviceCodeInfo)
    let abortedRef ← IO.mkRef false
    let baseRuntime := localOpenAICodexRuntime port
    let runtime :=
      { baseRuntime with
        request := fun config => do
          if config.url.endsWith "/codex/deviceauth/token" then
            pure { status := 403, headers := #[], body := "{\"error\":\"deviceauth_authorization_pending\"}" }
          else
            baseRuntime.request config
        sleepMs := fun _ => abortedRef.set true
      }
    let failed ←
      try
        let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
          { onAuth := fun _ => fail "unexpected browser auth callback"
            onDeviceCode := fun info => seenDeviceCode.set (some info)
            onPrompt := fun _ => throw (IO.userError "unexpected prompt during device-code login")
            onSelect := fun _ => pure (some LeanAgent.AI.OAuth.OpenAICodex.deviceCodeLoginMethod)
            signal := some { isAborted := abortedRef.get }
          }
        let _ ← LeanAgent.AI.OAuth.OpenAICodex.loginOpenAICodexWith runtime callbacks
        pure false
      catch err =>
        assertTrue (err.toString.contains LeanAgent.AI.OAuth.cancelMessage)
          "expected OpenAI Codex device-code login cancellation message"
        pure true
    assertTrue failed "expected OpenAI Codex device-code login to honor abort signal"
    match ← seenDeviceCode.get with
    | some info =>
        assertTrue (info.userCode == "ABCD-1234")
          "expected OpenAI Codex aborting device-code login to still surface device code"
    | none => fail "expected OpenAI Codex aborting device-code login to report device code"

def testGitHubCopilotOAuthRefreshFetchesAvailableModels : IO Unit := do
  let port := 18114
  withHttpServer port do
    let credential ← LeanAgent.AI.OAuth.GitHubCopilot.refreshGitHubCopilotTokenWith
      (localGitHubCopilotRuntime port)
      "ghu_refresh_token"
    assertTrue
      (credential.access == "tid=test;exp=9999999999;proxy-ep=proxy.individual.githubcopilot.com;")
      "expected refreshed Copilot access token"
    assertTrue (credential.refresh == "ghu_refresh_token") "expected Copilot refresh token preservation"
    match LeanAgent.AI.OAuth.GitHubCopilot.extraStringArray? credential "availableModelIds" with
    | some ids => assertTrue (ids == #["gpt-4.1"]) "expected filtered selectable Copilot models"
    | none => fail "expected available Copilot model ids"

def testGitHubCopilotOAuthLoginReportsDeviceCode : IO Unit := do
  let port := 18115
  withHttpServer port do
    let seenDeviceCode ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthDeviceCodeInfo)
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun _ => pure ()
        onDeviceCode := fun info => seenDeviceCode.set (some info)
        onPrompt := fun _ => pure ""
        onSelect := fun _ => pure none
      }
    let credential ← LeanAgent.AI.OAuth.GitHubCopilot.loginGitHubCopilotWith
      (localGitHubCopilotRuntime port)
      callbacks
    match ← seenDeviceCode.get with
    | some info =>
        assertTrue (info.userCode == "ABCD-EFGH") "expected Copilot device user code"
        assertTrue (info.verificationUri == "https://github.com/login/device")
          "expected normalized Copilot verification URI"
        assertTrue (info.intervalSeconds == some 1) "expected device polling interval"
        assertTrue (info.expiresInSeconds == some 900) "expected device code expiration"
    | none => fail "expected device code callback"
    assertTrue
      (credential.access == "tid=test;exp=9999999999;proxy-ep=proxy.individual.githubcopilot.com;")
      "expected login to exchange Copilot access token"
    assertTrue (credential.refresh == "ghu_refresh_token") "expected login to keep GitHub refresh token"
    match LeanAgent.AI.OAuth.GitHubCopilot.extraStringArray? credential "availableModelIds" with
    | some ids => assertTrue (ids == #["gpt-4.1"]) "expected login to attach available Copilot models"
    | none => fail "expected login available Copilot model ids"

def testGitHubCopilotOAuthLoginRespectsAbortSignal : IO Unit := do
  let port := 18127
  withHttpServer port do
    let seenDeviceCode ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthDeviceCodeInfo)
    let abortedRef ← IO.mkRef false
    let baseRuntime := localGitHubCopilotRuntime port
    let runtime :=
      { baseRuntime with
        request := fun config => do
          if config.url.endsWith "/copilot/access-token" then
            pure { status := 200, headers := #[], body := "{\"error\":\"authorization_pending\"}" }
          else
            baseRuntime.request config
        sleepMs := fun _ => abortedRef.set true
      }
    let failed ←
      try
        let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
          { onAuth := fun _ => pure ()
            onDeviceCode := fun info => seenDeviceCode.set (some info)
            onPrompt := fun _ => pure ""
            onSelect := fun _ => pure none
            signal := some { isAborted := abortedRef.get }
          }
        let _ ← LeanAgent.AI.OAuth.GitHubCopilot.loginGitHubCopilotWith runtime callbacks
        pure false
      catch err =>
        assertTrue (err.toString.contains LeanAgent.AI.OAuth.cancelMessage)
          "expected GitHub Copilot device-code login cancellation message"
        pure true
    assertTrue failed "expected GitHub Copilot login to honor abort signal"
    match ← seenDeviceCode.get with
    | some info =>
        assertTrue (info.userCode == "ABCD-EFGH")
          "expected GitHub Copilot aborting login to still surface device code"
    | none => fail "expected GitHub Copilot aborting login to report device code"

def testGitHubCopilotOAuthRejectsUntrustedVerificationUri : IO Unit := do
  let port := 18116
  withHttpServer port do
    let failed ←
      try
        let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
          { onAuth := fun _ => pure ()
            onDeviceCode := fun _ => fail "unexpected device code callback"
            onPrompt := fun _ => pure ""
            onSelect := fun _ => pure none
          }
        let _ ← LeanAgent.AI.OAuth.GitHubCopilot.loginGitHubCopilotWith
          (localGitHubCopilotRuntime port "/copilot/device-code-invalid-uri")
          callbacks
        pure false
      catch err =>
        assertTrue (err.toString.contains "Untrusted verification_uri")
          "expected invalid verification URI rejection"
        pure true
    assertTrue failed "expected invalid verification URI to fail"

def testGitHubCopilotOAuthNormalizesVerificationUri : IO Unit := do
  let port := 18117
  withHttpServer port do
    let seenDeviceCode ← IO.mkRef (none : Option LeanAgent.AI.OAuth.OAuthDeviceCodeInfo)
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun _ => pure ()
        onDeviceCode := fun info => seenDeviceCode.set (some info)
        onPrompt := fun _ => pure ""
        onSelect := fun _ => pure none
      }
    let _ ← LeanAgent.AI.OAuth.GitHubCopilot.loginGitHubCopilotWith
      (localGitHubCopilotRuntime port "/copilot/device-code-escaped-uri")
      callbacks
    match ← seenDeviceCode.get with
    | some info =>
        assertTrue (info.verificationUri == "https://github.com/login/%1B]8;;evil")
          "expected escaped verification URI normalization"
    | none => fail "expected normalized device code callback"

def testGitHubCopilotOAuthLoginEnablesKnownModels : IO Unit := do
  assertTrue
    (LeanAgent.AI.OAuth.GitHubCopilot.defaultRuntime.knownModelIds ==
      LeanAgent.Models.githubCopilotModels.map (·.id))
    "expected default Copilot runtime known models to come from checked-in catalog"
  let port := 18118
  withHttpServer port do
    let seenPolicyUrls ← IO.mkRef (#[] : Array String)
    let progressMessages ← IO.mkRef (#[] : Array String)
    let callbacks : LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
      { onAuth := fun _ => pure ()
        onDeviceCode := fun _ => pure ()
        onPrompt := fun _ => pure ""
        onProgress := some fun message =>
          progressMessages.modify (·.push message)
        onSelect := fun _ => pure none
      }
    let _ ← LeanAgent.AI.OAuth.GitHubCopilot.loginGitHubCopilotWith
      (localGitHubCopilotRuntime
        port
        "/copilot/device-code"
        #["gpt-4.1", "claude-opus-4.7"]
        (some fun config => do
          if config.url.endsWith "/policy" then
            seenPolicyUrls.modify (·.push config.url)
          else
            pure ()))
      callbacks
    let policyUrls ← seenPolicyUrls.get
    assertTrue (policyUrls.size == 2) "expected Copilot login to enable configured known models"
    assertTrue (policyUrls.any (·.endsWith "/models/gpt-4.1/policy"))
      "expected Copilot login to enable GPT-4.1 policy"
    assertTrue (policyUrls.any (·.endsWith "/models/claude-opus-4.7/policy"))
      "expected Copilot login to enable Claude Opus 4.7 policy"
    let progress ← progressMessages.get
    assertTrue (progress.contains "Enabling models...")
      "expected Copilot login progress banner before model enablement"
    assertTrue (progress.any (·.contains "Enabled GitHub Copilot model gpt-4.1: true"))
      "expected Copilot login progress for GPT-4.1 enablement"
    assertTrue (progress.any (·.contains "Enabled GitHub Copilot model claude-opus-4.7: true"))
      "expected Copilot login progress for Claude Opus 4.7 enablement"

def testAuthOAuthBridgeAnthropicBrowserLogin : IO Unit := do
  let port := 18128
  withHttpServer port do
    let seenAuth ← IO.mkRef (none : Option (String × Option String))
    let seenManualPrompt ← IO.mkRef false
    let sawManualSignal ← IO.mkRef false
    let progressMessages ← IO.mkRef (#[] : Array String)
    let runtime := localAnthropicRuntime port
    let credential ←
      LeanAgent.AI.Auth.OAuthBridge.loginWithOAuthProvider
        (LeanAgent.AI.OAuth.Anthropic.oauthProviderWith runtime)
        { prompt := fun prompt =>
            match prompt with
            | .manualCode message placeholder signal => do
                seenManualPrompt.set
                  (message == "Complete login in your browser, or paste the authorization code / redirect URL here:" &&
                    placeholder == some runtime.redirectUri)
                sawManualSignal.set signal.isSome
                pure
                  s!"{runtime.redirectUri}?code=manual-anthropic-code&state=anthropic-verifier"
            | _ => throw (IO.userError "expected Anthropic auth bridge manual-code prompt")
          notify := fun event =>
            match event with
            | .authUrl url instructions =>
                seenAuth.set (some (url, instructions))
            | .progress message =>
                progressMessages.modify (·.push message)
            | .deviceCode _ _ _ _ =>
                fail "unexpected device-code event for Anthropic browser login"
          signal := some { isAborted := pure false }
        }
    assertTrue (credential.access == "sk-ant-oat-access-token")
      "expected Anthropic auth bridge browser login access token"
    assertTrue (credential.refresh == "anthropic-browser-refresh")
      "expected Anthropic auth bridge browser login refresh token"
    match ← seenAuth.get with
    | some (url, instructions) =>
        assertTrue (url.contains "response_type=code")
          "expected Anthropic auth bridge auth URL"
        assertTrue (url.contains "state=anthropic-verifier")
          "expected Anthropic auth bridge state"
        assertTrue
          (instructions ==
            some "Complete login in your browser. If the browser is on another machine, paste the final redirect URL here.")
          "expected Anthropic auth bridge instructions"
    | none => fail "expected Anthropic auth bridge auth-url notification"
    assertTrue (← seenManualPrompt.get)
      "expected Anthropic auth bridge to surface a manual-code prompt"
    assertTrue (← sawManualSignal.get)
      "expected Anthropic auth bridge to preserve manual-code abort signal"
    let progress ← progressMessages.get
    assertTrue (progress == #["Exchanging authorization code for tokens..."])
      "expected Anthropic auth bridge progress notification"

def testAuthOAuthBridgeOpenAICodexDeviceCodeLogin : IO Unit := do
  let port := 18129
  withHttpServer port do
    let seenDeviceCode ← IO.mkRef (none : Option (String × String × Option Nat × Option Nat))
    let sawSelectSignal ← IO.mkRef false
    let runtime := localOpenAICodexRuntime port
    let credential ←
      LeanAgent.AI.Auth.OAuthBridge.loginWithOAuthProvider
        (LeanAgent.AI.OAuth.OpenAICodex.oauthProviderWith runtime)
        { prompt := fun prompt =>
            match prompt with
            | .select message options signal => do
                sawSelectSignal.set signal.isSome
                assertTrue (message == "Select OpenAI Codex login method:")
                  "expected OpenAI Codex auth bridge select prompt"
                assertTrue
                  (options.map (·.id) ==
                    #[LeanAgent.AI.OAuth.OpenAICodex.browserLoginMethod,
                      LeanAgent.AI.OAuth.OpenAICodex.deviceCodeLoginMethod])
                  "expected OpenAI Codex auth bridge login options"
                pure LeanAgent.AI.OAuth.OpenAICodex.deviceCodeLoginMethod
            | _ => throw (IO.userError "expected OpenAI Codex auth bridge select prompt")
          notify := fun event =>
            match event with
            | .deviceCode userCode verificationUri intervalSeconds expiresInSeconds =>
                seenDeviceCode.set (some (userCode, verificationUri, intervalSeconds, expiresInSeconds))
            | .progress _ => pure ()
            | .authUrl _ _ =>
                fail "unexpected auth-url event for OpenAI Codex device-code login"
          signal := some { isAborted := pure false }
        }
    assertTrue (credential.access == fakeOpenAICodexJwt)
      "expected OpenAI Codex auth bridge device-code access token"
    assertTrue (credential.refresh == "codex-device-refresh")
      "expected OpenAI Codex auth bridge device-code refresh token"
    match ← seenDeviceCode.get with
    | some (userCode, verificationUri, intervalSeconds, expiresInSeconds) =>
        assertTrue (userCode == "ABCD-1234")
          "expected OpenAI Codex auth bridge device user code"
        assertTrue (verificationUri == s!"http://127.0.0.1:{port}/codex/device")
          "expected OpenAI Codex auth bridge verification URI"
        assertTrue (intervalSeconds == some 1)
          "expected OpenAI Codex auth bridge device polling interval"
        assertTrue (expiresInSeconds == some (15 * 60))
          "expected OpenAI Codex auth bridge device-code expiration"
    | none => fail "expected OpenAI Codex auth bridge device-code notification"
    assertTrue (← sawSelectSignal.get)
      "expected OpenAI Codex auth bridge to forward the login abort signal to select prompts"

def testAuthOAuthBridgeGitHubCopilotLogin : IO Unit := do
  let port := 18130
  withHttpServer port do
    let seenDeviceCode ← IO.mkRef (none : Option (String × String × Option Nat × Option Nat))
    let sawTextPrompt ← IO.mkRef false
    let sawPromptSignal ← IO.mkRef false
    let runtime := localGitHubCopilotRuntime port
    let credential ←
      LeanAgent.AI.Auth.OAuthBridge.loginWithOAuthProvider
        (LeanAgent.AI.OAuth.GitHubCopilot.oauthProviderWith runtime)
        { prompt := fun prompt =>
            match prompt with
            | .text message placeholder signal => do
                sawTextPrompt.set
                  (message == "GitHub Enterprise URL/domain (blank for github.com)" &&
                    placeholder == some "company.ghe.com")
                sawPromptSignal.set signal.isSome
                pure ""
            | _ => throw (IO.userError "expected GitHub Copilot auth bridge text prompt")
          notify := fun event =>
            match event with
            | .deviceCode userCode verificationUri intervalSeconds expiresInSeconds =>
                seenDeviceCode.set (some (userCode, verificationUri, intervalSeconds, expiresInSeconds))
            | .progress _ => pure ()
            | .authUrl _ _ =>
                fail "unexpected auth-url event for GitHub Copilot login"
          signal := some { isAborted := pure false }
        }
    assertTrue
      (credential.access == "tid=test;exp=9999999999;proxy-ep=proxy.individual.githubcopilot.com;")
      "expected GitHub Copilot auth bridge access token"
    assertTrue (credential.refresh == "ghu_refresh_token")
      "expected GitHub Copilot auth bridge refresh token"
    match ← seenDeviceCode.get with
    | some (userCode, verificationUri, intervalSeconds, expiresInSeconds) =>
        assertTrue (userCode == "ABCD-EFGH")
          "expected GitHub Copilot auth bridge device user code"
        assertTrue (verificationUri == "https://github.com/login/device")
          "expected GitHub Copilot auth bridge verification URI"
        assertTrue (intervalSeconds == some 1)
          "expected GitHub Copilot auth bridge device polling interval"
        assertTrue (expiresInSeconds == some 900)
          "expected GitHub Copilot auth bridge device-code expiration"
    | none => fail "expected GitHub Copilot auth bridge device-code notification"
    assertTrue (← sawTextPrompt.get)
      "expected GitHub Copilot auth bridge to surface a text prompt"
    assertTrue (← sawPromptSignal.get)
      "expected GitHub Copilot auth bridge to forward the login abort signal to text prompts"

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
    assertTrue (response.content == "trace-1|||") "expected OpenAI-compatible request header"
    let affinityResponse ← LeanAgent.AI.Api.OpenAICompletions.completeWithOptions
      { apiKey := "test-key"
        baseUrl := s!"http://127.0.0.1:{port}/headers-openai"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      (basicProviderRequest)
      { sessionId := some "session-http"
        sendSessionAffinityHeaders := true
        headers := #[("X-Trace", some "trace-2"), ("x-session-affinity", some "caller-session")]
      }
    assertTrue (affinityResponse.content == "trace-2|session-http|session-http|caller-session")
      "expected OpenAI-compatible session affinity headers with caller override"

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

def testCompatOpenAICompletionsTypedLegacyAliasLocal : IO Unit := do
  let port := 18108
  withHttpServer port do
    let tool : LeanAgent.AI.Tool :=
      { name := "lookup"
        description := "Lookup a value"
        parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
      }
    let model : LeanAgent.Models.ModelInfo :=
      { id := "typed-model"
        name := "Typed OpenAI-compatible"
        provider := "typed-openai"
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/openai-typed"
        contextWindow := 100000
        maxTokens := 2048
        reasoning := true
        input := #["text"]
        compat :=
          { maxTokensField := "max_completion_tokens"
            sendSessionAffinityHeaders := true
          }
        thinkingLevelMap := #[{ level := .level .xhigh, mapped := some "max" }]
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamOpenAICompletions
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
        tools := #[tool]
      }
      { apiKey := some "typed-key"
        maxTokens := some 321
        reasoningEffort := some .xhigh
        cacheRetention := some .long
        sessionId := some "session-typed"
        toolChoice := some (.function "lookup")
        headers := #[("X-Trace", some "trace-openai")]
      }
    assertTrue stream.isComplete "expected compat OpenAI Completions typed legacy alias stream"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content ==
        "typed-model|True|True|321||max|session-typed|24h|lookup|Bearer typed-key|session-typed|session-typed|trace-openai")
      "expected typed OpenAI Completions alias to preserve compat-mapped options"
    assertTrue (stream.result.usage.cacheRead == 2) "expected typed OpenAI Completions cache usage"

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
    let stream ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
      model
      context
      { apiKey := some "test-key" }
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "streamed") "expected runtime streamed text"
    assertTrue (stream.result.api == "openai-completions") "expected runtime api"
    assertTrue (stream.result.provider == LeanAgent.Models.deepSeekProviderId) "expected runtime provider"

def openAICompatibleResponseModelTestModel (id baseUrl : String) : LeanAgent.Models.ModelInfo :=
  { id := id
    name := "OpenAI-compatible response-model test"
    provider := LeanAgent.Models.openRouterProviderId
    api := "openai-completions"
    baseUrl := baseUrl
    contextWindow := 200000
    maxTokens := 8192
    reasoning := false
    input := #["text"]
  }

def testOpenAICompatibleCompleteSimpleSurfacesRoutedResponseModel : IO Unit := do
  let port := 18137
  withHttpServer port do
    let model := openAICompatibleResponseModelTestModel
      "openrouter/auto"
      s!"http://127.0.0.1:{port}/response-model-openai"
    let result ← LeanAgent.AI.Compat.completeSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "hi"], timestamp := 1 }] }
      { apiKey := some "test-key" }
    assertTrue (result.model == "openrouter/auto")
      "expected requested router model to stay pinned on result"
    assertTrue (result.responseModel == some "anthropic/claude-opus-4.8")
      "expected routed chunk.model to surface on responseModel"
    assertTrue (result.provider == LeanAgent.Models.openRouterProviderId)
      "expected OpenRouter provider to be preserved"
    assertTrue (result.stopReason == .stop)
      "expected routed response-model stream to stop normally"

def testOpenAICompatibleCompleteSimpleOmitsMatchingResponseModel : IO Unit := do
  let port := 18138
  withHttpServer port do
    let model := openAICompatibleResponseModelTestModel
      "openrouter/same"
      s!"http://127.0.0.1:{port}/response-model-openai"
    let result ← LeanAgent.AI.Compat.completeSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "hi"], timestamp := 1 }] }
      { apiKey := some "test-key" }
    assertTrue (result.model == "openrouter/same")
      "expected same-id response-model test to preserve requested model"
    assertTrue (result.responseModel == none)
      "expected same chunk.model to be omitted from responseModel"

def testOpenAICompatibleCompleteSimpleIgnoresEmptyOrMissingResponseModel : IO Unit := do
  let port := 18139
  withHttpServer port do
    let model := openAICompatibleResponseModelTestModel
      "openrouter/missing"
      s!"http://127.0.0.1:{port}/response-model-openai"
    let result ← LeanAgent.AI.Compat.completeSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "hi"], timestamp := 1 }] }
      { apiKey := some "test-key" }
    assertTrue (result.model == "openrouter/missing")
      "expected missing-model response-model test to preserve requested model"
    assertTrue (result.responseModel == none)
      "expected empty or missing chunk.model to leave responseModel unset"
    assertTrue (LeanAgent.AI.contentPlainText result.content == "hi!")
      "expected response-model runtime to preserve streamed content"

def testOpenAICompatibleCompleteSimpleMapsUnknownFinishReasonToError : IO Unit := do
  let port := 18140
  withHttpServer port do
    let model := openAICompatibleResponseModelTestModel
      "openrouter/network-error"
      s!"http://127.0.0.1:{port}/finish-reason-openai"
    let result ← LeanAgent.AI.Compat.completeSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
      { apiKey := some "test-key" }
    assertTrue (result.stopReason == .error)
      "expected non-standard provider finish_reason to map to error"
    assertTrue (result.errorMessage == some "Provider finish_reason: network_error")
      "expected provider finish_reason error message"
    assertTrue (LeanAgent.AI.contentPlainText result.content == "partial")
      "expected partial content to survive finish_reason error mapping"

def testOpenAICompatibleCompleteSimpleIgnoresNullStreamChunks : IO Unit := do
  let port := 18141
  withHttpServer port do
    let model := openAICompatibleResponseModelTestModel
      "openrouter/null-chunks"
      s!"http://127.0.0.1:{port}/finish-reason-openai"
    let result ← LeanAgent.AI.Compat.completeSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Reply with exactly OK"], timestamp := 1 }] }
      { apiKey := some "test-key" }
    assertTrue (result.stopReason == .stop)
      "expected null stream chunks to be ignored"
    assertTrue (result.errorMessage.isNone)
      "expected null stream chunks not to set an error message"
    assertTrue (result.responseId == some "chatcmpl-null-chunks")
      "expected null stream chunks path to preserve response id"
    assertTrue (result.usage.totalTokens == 4)
      "expected null stream chunks path to preserve usage"
    assertTrue (LeanAgent.AI.contentPlainText result.content == "OK")
      "expected null stream chunks path to preserve streamed content"

def testOpenAICompatibleCompleteSimpleErrorsWhenFinishReasonIsMissing : IO Unit := do
  let port := 18142
  withHttpServer port do
    let model := openAICompatibleResponseModelTestModel
      "openrouter/missing-finish-reason"
      s!"http://127.0.0.1:{port}/finish-reason-openai"
    let result ← LeanAgent.AI.Compat.completeSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Reply with a longer sentence"], timestamp := 1 }] }
      { apiKey := some "test-key" }
    assertTrue (result.stopReason == .error)
      "expected missing finish_reason to become an error"
    assertTrue (result.errorMessage == some "Stream ended without finish_reason")
      "expected missing finish_reason error message"
    assertTrue (LeanAgent.AI.contentPlainText result.content == "partial answer")
      "expected missing finish_reason path to preserve partial content"

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
    let stream ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
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

def testOpenAICompatibleStreamsDetectOpenRouterDeveloperRole : IO Unit := do
  let port := 18113
  withHttpServer port do
    let deepseekModel : LeanAgent.Models.ModelInfo :=
      { id := "deepseek/deepseek-v4-pro"
        name := "DeepSeek via OpenRouter"
        provider := LeanAgent.Models.openRouterProviderId
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        contextWindow := 1000000
        maxTokens := 384000
        reasoning := true
        input := #["text"]
      }
    let openAIModel : LeanAgent.Models.ModelInfo :=
      { id := "openai/gpt-5.2-codex"
        name := "GPT 5.2 Codex via OpenRouter"
        provider := LeanAgent.Models.openRouterProviderId
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        contextWindow := 400000
        maxTokens := 128000
        reasoning := true
        input := #["text", "image"]
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "Follow instructions."
        messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }]
      }
    let deepseekPayload ← IO.mkRef Lean.Json.null
    let openAIPayload ← IO.mkRef Lean.Json.null
    let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
      deepseekModel
      context
      { apiKey := some "test-key"
        onPayload := some fun payload _ => do
          deepseekPayload.set payload
          pure none
      }
    let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
      openAIModel
      context
      { apiKey := some "test-key"
        onPayload := some fun payload _ => do
          openAIPayload.set payload
          pure none
      }
    let deepseekPayload ← deepseekPayload.get
    let openAIPayload ← openAIPayload.get
    match jsonArrayField? deepseekPayload "messages", jsonArrayField? openAIPayload "messages" with
    | some deepseekMessages, some openAIMessages =>
        match deepseekMessages[0]?, openAIMessages[0]? with
        | some deepseekInstruction, some openAIInstruction =>
            assertTrue (jsonStringField? deepseekInstruction "role" == some "system")
              "expected DeepSeek OpenRouter instructions to stay as system"
            assertTrue (jsonStringField? openAIInstruction "role" == some "developer")
              "expected OpenAI OpenRouter instructions to use developer role"
        | _, _ => fail "expected OpenRouter instruction messages"
    | _, _ => fail "expected OpenRouter payload messages arrays"

def testOpenAICompatibleStreamsDetectMoonshotCompatDefaults : IO Unit := do
  let port := 18114
  withHttpServer port do
    let tool : LeanAgent.AI.Tool :=
      { name := "lookup"
        description := "Lookup a value"
        parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
      }
    let model : LeanAgent.Models.ModelInfo :=
      { id := "kimi-k2.6"
        name := "Kimi K2.6"
        provider := LeanAgent.Models.moonshotAIProviderId
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        contextWindow := 262144
        maxTokens := 262144
        reasoning := true
        input := #["text", "image"]
      }
    let payloadRef ← IO.mkRef Lean.Json.null
    let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }]
        tools := #[tool]
      }
      { apiKey := some "test-key"
        maxTokens := some 123
        onPayload := some fun payload _ => do
          payloadRef.set payload
          pure none
      }
    let payload ← payloadRef.get
    assertTrue (LeanAgent.Json.optVal? payload "max_tokens" == some (LeanAgent.Json.nat 123))
      "expected Moonshot auto-detect to use max_tokens"
    assertTrue ((LeanAgent.Json.optVal? payload "max_completion_tokens").isNone)
      "expected Moonshot auto-detect to omit max_completion_tokens"
    assertTrue ((LeanAgent.Json.optVal? payload "reasoning_effort").isNone)
      "expected Moonshot auto-detect to omit top-level reasoning_effort"
    match jsonObjectField? payload "thinking", jsonArrayField? payload "tools" with
    | some thinking, some tools =>
        assertTrue (jsonStringField? thinking "type" == some "disabled")
          "expected Moonshot auto-detect to keep disabled thinking payload"
        match jsonObjectField? tools[0]! "function" with
        | some fn =>
            assertTrue ((LeanAgent.Json.optVal? fn "strict").isNone)
              "expected Moonshot auto-detect to omit strict"
        | none => fail "expected Moonshot tool function"
    | _, _ => fail "expected Moonshot thinking object and tools array"

def testOpenAICompatibleStreamsUseTogetherGptOssReasoningEffort : IO Unit := do
  let port := 18115
  withHttpServer port do
    let tool : LeanAgent.AI.Tool :=
      { name := "lookup"
        description := "Lookup a value"
        parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
      }
    let model : LeanAgent.Models.ModelInfo :=
      { LeanAgent.Models.togetherGptOss120B with
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
      }
    let payloadRef ← IO.mkRef Lean.Json.null
    let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }]
        tools := #[tool]
      }
      { apiKey := some "test-key"
        maxTokens := some 123
        reasoning := some .high
        onPayload := some fun payload _ => do
          payloadRef.set payload
          pure none
      }
    let payload ← payloadRef.get
    assertTrue (LeanAgent.Json.optVal? payload "max_tokens" == some (LeanAgent.Json.nat 123))
      "expected Together GPT OSS to use max_tokens"
    assertTrue (LeanAgent.Json.optVal? payload "reasoning_effort" == some (LeanAgent.Json.str "high"))
      "expected Together GPT OSS to send reasoning_effort"
    assertTrue ((LeanAgent.Json.optVal? payload "reasoning").isNone)
      "expected Together GPT OSS to avoid toggle reasoning object"
    match jsonArrayField? payload "tools" with
    | some tools =>
        match jsonObjectField? tools[0]! "function" with
        | some fn =>
            assertTrue ((LeanAgent.Json.optVal? fn "strict").isNone)
              "expected Together GPT OSS to omit strict"
        | none => fail "expected Together GPT OSS tool function"
    | none => fail "expected Together GPT OSS tools array"

def testOpenAICompatibleStreamsDetectTogetherReasoningOnlyCompat : IO Unit := do
  let port := 18116
  withHttpServer port do
    let tool : LeanAgent.AI.Tool :=
      { name := "lookup"
        description := "Lookup a value"
        parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
      }
    let model : LeanAgent.Models.ModelInfo :=
      { id := "deepseek-ai/DeepSeek-R1"
        name := "DeepSeek R1 via Together"
        provider := LeanAgent.Models.togetherProviderId
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        contextWindow := 131072
        maxTokens := 32768
        reasoning := true
        input := #["text"]
      }
    let payloadRef ← IO.mkRef Lean.Json.null
    let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }]
        tools := #[tool]
      }
      { apiKey := some "test-key"
        maxTokens := some 123
        reasoning := some .high
        onPayload := some fun payload _ => do
          payloadRef.set payload
          pure none
      }
    let payload ← payloadRef.get
    assertTrue (LeanAgent.Json.optVal? payload "max_tokens" == some (LeanAgent.Json.nat 123))
      "expected Together reasoning-only fallback to use max_tokens"
    assertTrue ((LeanAgent.Json.optVal? payload "reasoning_effort").isNone)
      "expected Together reasoning-only fallback to omit reasoning_effort"
    assertTrue ((LeanAgent.Json.optVal? payload "reasoning").isNone)
      "expected Together reasoning-only fallback to avoid toggle reasoning object"
    assertTrue ((LeanAgent.Json.optVal? payload "thinking").isNone)
      "expected Together reasoning-only fallback to avoid thinking object"
    match jsonArrayField? payload "tools" with
    | some tools =>
        match jsonObjectField? tools[0]! "function" with
        | some fn =>
            assertTrue ((LeanAgent.Json.optVal? fn "strict").isNone)
              "expected Together reasoning-only fallback to omit strict"
        | none => fail "expected Together reasoning-only fallback tool function"
    | none => fail "expected Together reasoning-only fallback tools array"

def testOpenAICompatibleStreamsUseOpenCodeMaxTokensCompat : IO Unit := do
  let port := 18117
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "big-pickle"
        name := "Big Pickle"
        provider := LeanAgent.Models.opencodeProviderId
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        contextWindow := 200000
        maxTokens := 32000
        reasoning := true
        compat := LeanAgent.Models.opencodeOpenAICompat
        input := #["text"]
      }
    let payloadRef ← IO.mkRef Lean.Json.null
    let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
      { apiKey := some "test-key"
        maxTokens := some 123
        onPayload := some fun payload _ => do
          payloadRef.set payload
          pure none
      }
    let payload ← payloadRef.get
    assertTrue (LeanAgent.Json.optVal? payload "max_tokens" == some (LeanAgent.Json.nat 123))
      "expected OpenCode compat metadata to use max_tokens"
    assertTrue ((LeanAgent.Json.optVal? payload "max_completion_tokens").isNone)
      "expected OpenCode compat metadata to omit max_completion_tokens"

def testOpenAICompatibleStreamsUseOpenCodeGoMaxTokensCompat : IO Unit := do
  let port := 18118
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "qwen3.6-plus"
        name := "Qwen3.6 Plus"
        provider := LeanAgent.Models.opencodeGoProviderId
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        contextWindow := 1000000
        maxTokens := 65536
        reasoning := true
        compat := LeanAgent.Models.opencodeQwenCompat
        input := #["text", "image"]
      }
    let payloadRef ← IO.mkRef Lean.Json.null
    let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
      { apiKey := some "test-key"
        maxTokens := some 123
        reasoning := some .high
        onPayload := some fun payload _ => do
          payloadRef.set payload
          pure none
      }
    let payload ← payloadRef.get
    assertTrue (LeanAgent.Json.optVal? payload "max_tokens" == some (LeanAgent.Json.nat 123))
      "expected OpenCode Go compat metadata to use max_tokens"
    assertTrue ((LeanAgent.Json.optVal? payload "max_completion_tokens").isNone)
      "expected OpenCode Go compat metadata to omit max_completion_tokens"
    assertTrue (LeanAgent.Json.optVal? payload "enable_thinking" == some (LeanAgent.Json.bool true))
      "expected OpenCode Go qwen compat metadata to preserve qwen thinking payload"

def testOpenAICompatibleStreamsOmitMoonshotDisabledThinkingForK27Code : IO Unit := do
  let port := 18135
  withHttpServer port do
    for baseModel in
      #[ LeanAgent.Models.moonshotAIModels.find? (fun model => model.id == "kimi-k2.7-code")
       , LeanAgent.Models.moonshotAICNModels.find? (fun model => model.id == "kimi-k2.7-code")
       ] do
      match baseModel with
      | none => fail "expected Moonshot Kimi K2.7 Code model"
      | some model =>
          let payloadRef ← IO.mkRef Lean.Json.null
          let runtimeModel := { model with baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai" }
          let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
            runtimeModel
            { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
            { apiKey := some "test-key"
              onPayload := some fun payload _ => do
                payloadRef.set payload
                pure none
            }
          let payload ← payloadRef.get
          assertTrue ((LeanAgent.Json.optVal? payload "thinking").isNone)
            "expected Moonshot K2.7 Code builtins to omit disabled thinking"
          assertTrue ((LeanAgent.Json.optVal? payload "reasoning_effort").isNone)
            "expected Moonshot K2.7 Code builtins to omit reasoning_effort when thinking is off"

def testOpenAICompatibleStreamsKeepMoonshotDisabledThinkingForK26 : IO Unit := do
  let port := 18136
  withHttpServer port do
    match LeanAgent.Models.moonshotAICNModels.find? (fun model => model.id == "kimi-k2.6") with
    | none => fail "expected Moonshot CN Kimi K2.6 model"
    | some model =>
        let payloadRef ← IO.mkRef Lean.Json.null
        let runtimeModel := { model with baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai" }
        let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
          runtimeModel
          { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
          { apiKey := some "test-key"
            onPayload := some fun payload _ => do
              payloadRef.set payload
              pure none
          }
        let payload ← payloadRef.get
        match jsonObjectField? payload "thinking" with
        | some thinking =>
            assertTrue (jsonStringField? thinking "type" == some "disabled")
              "expected Moonshot K2.6 builtins to keep disabled thinking payload"
            assertTrue ((LeanAgent.Json.optVal? payload "reasoning_effort").isNone)
              "expected Moonshot K2.6 builtins to omit reasoning_effort when thinking is off"
        | none => fail "expected Moonshot K2.6 builtins to include thinking payload"

def testOpenAICompatibleStreamsOmitStreamingUsageWhenCompatDisablesIt : IO Unit := do
  let port := 18133
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "custom-no-usage"
        name := "Custom No Usage"
        provider := "custom"
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        contextWindow := 100000
        maxTokens := 16000
        compat := { supportsUsageInStreaming := false }
        input := #["text"]
      }
    let payloadRef ← IO.mkRef Lean.Json.null
    let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
      { apiKey := some "test-key"
        onPayload := some fun payload _ => do
          payloadRef.set payload
          pure none
      }
    let payload ← payloadRef.get
    assertTrue ((LeanAgent.Json.optVal? payload "stream_options").isNone)
      "expected runtime compat to omit streaming usage option"

def testLegacyOpenAICompletionsAliasOmitStreamingUsageWhenCompatDisablesIt : IO Unit := do
  let port := 18134
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "custom-no-usage"
        name := "Custom No Usage"
        provider := "custom"
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
        contextWindow := 100000
        maxTokens := 16000
        compat := { supportsUsageInStreaming := false }
        input := #["text"]
      }
    let payloadRef ← IO.mkRef Lean.Json.null
    let _ ← LeanAgent.AI.Compat.Aliases.streamOpenAICompletionsWithOptions
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
      { apiKey := some "test-key"
        onPayload := some fun payload _ => do
          payloadRef.set payload
          pure none
      }
    let payload ← payloadRef.get
    assertTrue ((LeanAgent.Json.optVal? payload "stream_options").isNone)
      "expected legacy alias compat to omit streaming usage option"

def testOpenAICompatibleStreamsKeepGitHubCopilotDetectedMaxCompletionTokens : IO Unit := do
  let port := 18131
  withHttpServer port do
    match LeanAgent.Models.githubCopilotModels.find? (fun model => model.id == "claude-fable-5") with
    | none => fail "expected GitHub Copilot Claude Fable 5 model"
    | some baseModel =>
        let model : LeanAgent.Models.ModelInfo :=
          { baseModel with
            baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
          }
        let payloadRef ← IO.mkRef Lean.Json.null
        let _ ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
          model
          { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
          { apiKey := some "test-key"
            maxTokens := some 123
            reasoning := some .high
            onPayload := some fun payload _ => do
              payloadRef.set payload
              pure none
          }
        let payload ← payloadRef.get
        assertTrue (LeanAgent.Json.optVal? payload "max_completion_tokens" == some (LeanAgent.Json.nat 123))
          "expected GitHub Copilot partial compat to keep detected max_completion_tokens"
        assertTrue ((LeanAgent.Json.optVal? payload "max_tokens").isNone)
          "expected GitHub Copilot partial compat to avoid forced max_tokens"
        assertTrue ((LeanAgent.Json.optVal? payload "reasoning_effort").isNone)
          "expected GitHub Copilot partial compat to keep reasoning_effort disabled"

def testLegacyOpenAICompletionsAliasKeepsGitHubCopilotDetectedMaxCompletionTokens : IO Unit := do
  let port := 18132
  withHttpServer port do
    match LeanAgent.Models.githubCopilotModels.find? (fun model => model.id == "claude-fable-5") with
    | none => fail "expected GitHub Copilot Claude Fable 5 model"
    | some baseModel =>
        let model : LeanAgent.Models.ModelInfo :=
          { baseModel with
            baseUrl := s!"http://127.0.0.1:{port}/runtime-stream-openai"
          }
        let payloadRef ← IO.mkRef Lean.Json.null
        let _ ← LeanAgent.AI.Compat.Aliases.streamOpenAICompletionsWithOptions
          model
          { messages := #[.user { content := #[LeanAgent.AI.text "Hi"], timestamp := 1 }] }
          { apiKey := some "test-key"
            maxTokens := some 123
            reasoningEffort := some .high
            onPayload := some fun payload _ => do
              payloadRef.set payload
              pure none
          }
        let payload ← payloadRef.get
        assertTrue (LeanAgent.Json.optVal? payload "max_completion_tokens" == some (LeanAgent.Json.nat 123))
          "expected legacy OpenAI alias to keep detected max_completion_tokens"
        assertTrue ((LeanAgent.Json.optVal? payload "max_tokens").isNone)
          "expected legacy OpenAI alias to avoid forced max_tokens"
        assertTrue ((LeanAgent.Json.optVal? payload "reasoning_effort").isNone)
          "expected legacy OpenAI alias to keep reasoning_effort disabled"

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
        compat := { thinkingFormat := some "openai" }
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "abcd"
        messages := #[.user { content := #[LeanAgent.AI.text "abcd"], timestamp := 1 }]
      }
    let stream ← LeanAgent.AI.Providers.Streams.openAICompatibleStreams.streamSimple
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
        apis := #[{ api := "openai-completions", streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams }]
      }
    collection.setProvider provider
    let message ← collection.completeSimple
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
    assertTrue
      (LeanAgent.AI.contentPlainText message.content == "Bearer cf-env-key||gpt-4o-mini")
      "expected Cloudflare AI Gateway header-only auth through OpenAI-compatible runtime"

def testCompatBuiltinDispatchUsesCloudflareGatewayAuth : IO Unit := do
  let port := 18096
  withHttpServer port do
    LeanAgent.AI.Compat.resetApiProviders
    let model : LeanAgent.Models.ModelInfo :=
      { LeanAgent.AI.Providers.CloudflareAIGateway.workersAIKimiK26 with
        baseUrl :=
          s!"http://127.0.0.1:{port}/cloudflare-openai/" ++
            "{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}"
      }
    let message ← LeanAgent.AI.Compat.complete
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
      { env :=
          #[ ("CLOUDFLARE_API_KEY", "cf-env-key")
           , ("CLOUDFLARE_ACCOUNT_ID", "acct-env")
           , ("CLOUDFLARE_GATEWAY_ID", "gateway-env")
           ]
      }
    assertTrue
      (LeanAgent.AI.contentPlainText message.content ==
        "Bearer cf-env-key||workers-ai/@cf/moonshotai/kimi-k2.6")
      "expected compat builtin dispatch to reuse Cloudflare AI Gateway auth path"
    LeanAgent.AI.Compat.resetApiProviders

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
    let provider ← LeanAgent.AI.Providers.Catalog.createCatalogProvider
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

def testOpenAIProviderFactoryDispatchesResponsesRuntime : IO Unit := do
  let port := 18096
  withHttpServer port do
    let provider ← LeanAgent.AI.Providers.OpenAI.provider
    let model :=
      { LeanAgent.Models.openAIGpt41Mini with
        baseUrl := s!"http://127.0.0.1:{port}/responses-stream"
        cost := { input := 1000000.0, output := 2000000.0 }
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
    let stream ← provider.streamSimple model context { apiKey := some "test-key" }
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "streamed")
      "expected OpenAI provider factory to dispatch Responses runtime"
    assertTrue (stream.result.api == "openai-responses") "expected OpenAI provider runtime api"
    assertTrue (stream.result.provider == LeanAgent.Models.openAIProviderId)
      "expected OpenAI provider runtime provider"
    assertTrue (stream.result.usage.cost.input == 4.0) "expected OpenAI provider input cost"
    assertTrue (stream.result.usage.cost.output == 4.0) "expected OpenAI provider output cost"

def testOpenAICodexProviderDispatchesSSEWithStoredOAuth : IO Unit := do
  let port := 18097
  withHttpServer port do
    let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
    let _ ← store.modify LeanAgent.Models.openAICodexProviderId fun _ =>
      pure
        (some
          (.oauth
            { access := fakeOpenAICodexJwt
              refresh := "refresh-token"
              expires := 2000
            }))
    let ctx : LeanAgent.AI.Auth.AuthContext :=
      { env := fun _ => pure none
        fileExists := fun _ => pure false
        nowMs := pure 1000
      }
    let collection ← LeanAgent.Models.createModels (some store) ctx
    collection.setProvider (← LeanAgent.AI.Providers.OpenAICodex.provider)
    let model :=
      { LeanAgent.Models.openAICodexModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 272000 128000 with
        baseUrl := s!"http://127.0.0.1:{port}/codex-provider"
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "codex system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
    let stream ← collection.streamSimple
      model
      context
      { sessionId := some "codex-session", reasoning := some .minimal }
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "codex-ok")
      "expected OpenAI Codex provider to dispatch SSE runtime with stored OAuth"
    assertTrue (stream.result.api == LeanAgent.AI.Api.OpenAICodexResponses.api)
      "expected Codex runtime api"
    assertTrue (stream.result.provider == LeanAgent.Models.openAICodexProviderId)
      "expected Codex runtime provider"
    assertTrue (stream.result.usage.input == 4) "expected Codex input usage"
    assertTrue (stream.result.usage.output == 2) "expected Codex output usage"

def testCompatOpenAICodexResponsesBuiltinDispatch : IO Unit := do
  let port := 18098
  withHttpServer port do
    let sawResponse ← IO.mkRef false
    let model :=
      { LeanAgent.Models.openAICodexModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 272000 128000 with
        baseUrl := s!"http://127.0.0.1:{port}/codex-provider"
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "codex system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamSimpleOpenAICodexResponses
      model
      context
      { apiKey := some fakeOpenAICodexJwt
        sessionId := some "codex-session"
        reasoning := some .minimal
        onResponse := some fun response ref => do
          assertTrue (ref.api == LeanAgent.AI.Api.OpenAICodexResponses.api)
            "expected Codex response hook model api"
          assertTrue (response.status == 200) "expected Codex response hook status"
          assertTrue (headerValueCaseInsensitive? response.headers "x-hook-response" == some "codex")
            "expected Codex response hook headers"
          sawResponse.set true
      }
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "codex-ok")
      "expected compat OpenAI Codex Responses alias to dispatch"
    assertTrue (stream.result.api == LeanAgent.AI.Api.OpenAICodexResponses.api)
      "expected compat Codex runtime api"
    assertTrue (← sawResponse.get) "expected Codex response hook to run"

def testCompatOpenAICodexResponsesMissingTokenUsesOauthCode : IO Unit := do
  let model :=
    LeanAgent.Models.openAICodexModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 272000 128000
  let context : LeanAgent.AI.Context :=
    { systemPrompt := some "codex system"
      messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
    }
  let stream ← LeanAgent.AI.Compat.Aliases.streamSimpleOpenAICodexResponses
    model
    context
    {}
  assertTrue (stream.result.stopReason == .error)
    "expected missing Codex OAuth token to produce error stream"
  match stream.result.errorMessage with
  | some message =>
      assertTrue (message.contains "ModelsError(oauth)")
        "expected typed oauth error for missing Codex token"
      assertTrue (message.contains "missing OAuth access token")
        "expected missing token details"
  | none => fail "expected error message in Codex OAuth error stream"

def testCompatOpenAICodexResponsesTypedLegacyAliasLocal : IO Unit := do
  let port := 18104
  withHttpServer port do
    let model :=
      { LeanAgent.Models.openAICodexModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 272000 128000 with
        baseUrl := s!"http://127.0.0.1:{port}/codex-provider"
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "codex system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamOpenAICodexResponses
      model
      context
      { apiKey := some fakeOpenAICodexJwt
        sessionId := some "codex-session"
        reasoningEffort := some (.level .minimal)
        textVerbosity := some "low"
      }
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "codex-ok")
      "expected compat OpenAI Codex Responses typed alias to preserve provider-specific options"
    assertTrue (stream.result.api == LeanAgent.AI.Api.OpenAICodexResponses.api)
      "expected typed compat Codex runtime api"

def testOpenAICodexResponsesProviderHttpError : IO Unit := do
  let port := 18121
  withHttpServer port do
    let sawResponse ← IO.mkRef false
    let failed ←
      try
        let _stream ← LeanAgent.AI.Api.OpenAICodexResponses.completeStreamWithOptions
          { apiKey := fakeOpenAICodexJwt
            baseUrl := s!"http://127.0.0.1:{port}/codex-provider-rate-limit"
            timeoutSeconds := 5
            connectTimeoutSeconds := 5
            noProxy := some "*"
            userAgent := "lean-agent-test/0.1.0"
          }
          ((LeanAgent.Models.openAICodexModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 272000 128000).toResponsesModel)
          { systemPrompt := some "codex system"
            messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
          }
          { sessionId := some "codex-session"
            reasoning := some .minimal
            onResponse := some fun response ref => do
              assertTrue (ref.api == LeanAgent.AI.Api.OpenAICodexResponses.api)
                "expected Codex HTTP error hook model api"
              assertTrue (response.status == 429) "expected Codex HTTP error hook status"
              assertTrue
                (headerValueCaseInsensitive? response.headers "x-diagnostic-trace" ==
                  some "codex-rate-limit-route")
                "expected Codex HTTP error hook headers"
              sawResponse.set true
          }
        pure false
      catch err =>
        pure
          (err.toString.contains "provider HTTP 429" &&
            err.toString.contains "rate limit exceeded" &&
            err.toString.contains "type=rate_limit_error")
    assertTrue failed "expected Codex HTTP provider error"
    assertTrue (← sawResponse.get) "expected Codex HTTP error response hook to run"

def testOpenAICodexProviderHttpErrorDiagnosticsIncludeResponseHeaders : IO Unit := do
  let port := 18122
  withHttpServer port do
    let store ← LeanAgent.AI.Auth.InMemoryCredentialStore.mk
    let _ ← store.modify LeanAgent.Models.openAICodexProviderId fun _ =>
      pure
        (some
          (.oauth
            { access := fakeOpenAICodexJwt
              refresh := "refresh-token"
              expires := 2000
            }))
    let ctx : LeanAgent.AI.Auth.AuthContext :=
      { env := fun _ => pure none
        fileExists := fun _ => pure false
        nowMs := pure 1000
      }
    let collection ← LeanAgent.Models.createModels (some store) ctx
    collection.setProvider (← LeanAgent.AI.Providers.OpenAICodex.provider)
    let model :=
      { LeanAgent.Models.openAICodexModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 272000 128000 with
        baseUrl := s!"http://127.0.0.1:{port}/codex-provider-rate-limit"
      }
    let context : LeanAgent.AI.Context :=
      { systemPrompt := some "codex system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
    let stream ← collection.streamSimple
      model
      context
      { sessionId := some "codex-session", reasoning := some .minimal }
    assertTrue stream.isComplete "expected Codex provider error stream to complete"
    assertTrue (stream.result.stopReason == .error) "expected Codex provider error stop reason"
    match stream.result.errorMessage with
    | some message =>
        assertTrue (message.contains "provider HTTP 429") "expected Codex provider status in error"
        assertTrue (message.contains "rate limit exceeded") "expected Codex provider message in error"
    | none => fail "expected Codex provider error message"
    match stream.result.diagnostics[0]? with
    | some diagnostic =>
        assertTrue (diagnostic.type == "provider_error") "expected Codex provider_error diagnostic"
        match diagnostic.details with
        | some details =>
            assertTrue (jsonNatField? details "status" == some 429)
              "expected Codex diagnostic HTTP status"
        | none => fail "expected Codex diagnostic details"
        assertTrue
          (diagnosticResponseHeaderValueCaseInsensitive? diagnostic "x-diagnostic-trace" ==
            some "codex-rate-limit-route")
          "expected Codex diagnostic response headers"
    | none => fail "expected Codex provider diagnostic entry"

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

def testCompatOpenAIResponsesTypedLegacyAliasLocal : IO Unit := do
  let port := 18102
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-5.4"
        name := "GPT 5.4"
        provider := LeanAgent.Models.openAIProviderId
        api := "openai-responses"
        baseUrl := s!"http://127.0.0.1:{port}/responses-stream"
        cost := { input := 1000000.0, output := 2000000.0 }
        contextWindow := 100000
        maxTokens := 4096
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamOpenAIResponses
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "test-key"
        serviceTier := some "flex"
      }
    assertTrue stream.isComplete "expected compat OpenAI Responses typed legacy alias stream"
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "streamed")
      "expected compat OpenAI Responses typed alias content"
    assertTrue (stream.result.usage.cost.input == 2.0)
      "expected compat OpenAI Responses typed alias flex input cost multiplier"
    assertTrue (stream.result.usage.cost.output == 2.0)
      "expected compat OpenAI Responses typed alias flex output cost multiplier"

def testCompatOpenAIResponsesRootLegacyAliasLocal : IO Unit := do
  let port := 18102
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-5.4"
        name := "GPT 5.4"
        provider := LeanAgent.Models.openAIProviderId
        api := "openai-responses"
        baseUrl := s!"http://127.0.0.1:{port}/responses-stream"
        cost := { input := 1000000.0, output := 2000000.0 }
        contextWindow := 100000
        maxTokens := 4096
      }
    let stream ← LeanAgent.AI.Compat.streamOpenAIResponses
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "test-key"
        serviceTier := some "flex"
      }
    assertTrue stream.isComplete "expected compat root OpenAI Responses typed legacy alias stream"
    assertTrue (LeanAgent.AI.contentPlainText stream.result.content == "streamed")
      "expected compat root OpenAI Responses typed alias content"
    assertTrue (stream.result.usage.cost.input == 2.0)
      "expected compat root OpenAI Responses typed alias flex input cost multiplier"
    assertTrue (stream.result.usage.cost.output == 2.0)
      "expected compat root OpenAI Responses typed alias flex output cost multiplier"

def testCompatOpenAIResponsesTypedLegacyAliasCompleteLocal : IO Unit := do
  let port := 18102
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-5.4"
        name := "GPT 5.4"
        provider := LeanAgent.Models.openAIProviderId
        api := "openai-responses"
        baseUrl := s!"http://127.0.0.1:{port}/responses-stream"
        cost := { input := 1000000.0, output := 2000000.0 }
        contextWindow := 100000
        maxTokens := 4096
      }
    let message ← LeanAgent.AI.Compat.Aliases.completeOpenAIResponses
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "test-key"
        serviceTier := some "flex"
      }
    assertTrue (LeanAgent.AI.contentPlainText message.content == "streamed")
      "expected compat OpenAI Responses typed complete alias content"
    assertTrue (message.usage.cost.input == 2.0)
      "expected compat OpenAI Responses typed complete alias flex input cost multiplier"
    assertTrue (message.usage.cost.output == 2.0)
      "expected compat OpenAI Responses typed complete alias flex output cost multiplier"

def testOpenAIResponsesEarlyEofInvokesResponseHook : IO Unit := do
  let port := 18117
  withHttpServer port do
    let sawResponseHeader ← IO.mkRef false
    let failed ←
      try
        let _stream ← LeanAgent.AI.Api.OpenAIResponses.completeStreamWithOptions
          { apiKey := "test-key"
            baseUrl := s!"http://127.0.0.1:{port}/responses-stream-early-eof"
            timeoutSeconds := 5
            connectTimeoutSeconds := 5
            noProxy := some "*"
            userAgent := "lean-agent-test/0.1.0"
          }
          responsesCodexModel
          { systemPrompt := some "system"
            messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
          }
          { onResponse := some fun response _model => do
              assertTrue (response.status == 200) "expected direct early EOF response hook status"
              assertTrue
                (headerValueCaseInsensitive? response.headers "x-diagnostic-trace" ==
                  some "early-eof-route")
                "expected direct early EOF response hook headers"
              sawResponseHeader.set true
          }
        pure false
      catch err =>
        pure (err.toString.contains "OpenAI Responses stream ended before a terminal response event")
    assertTrue failed "expected direct OpenAI Responses early EOF parse failure"
    assertTrue (← sawResponseHeader.get) "expected direct OpenAI Responses early EOF response hook to run"

def testOpenAIResponsesProviderStreamsEarlyEofInvokesResponseHook : IO Unit := do
  let port := 18118
  withHttpServer port do
    let sawResponseHeader ← IO.mkRef false
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-5.4"
        name := "GPT 5.4"
        provider := LeanAgent.Models.openAIProviderId
        api := "openai-responses"
        baseUrl := s!"http://127.0.0.1:{port}/responses-stream-early-eof"
        contextWindow := 100000
        maxTokens := 4096
        reasoning := true
      }
    let failed ←
      try
        let _stream ← LeanAgent.AI.Providers.Streams.openAIResponsesStreams.streamSimple
          model
          { systemPrompt := some "system"
            messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
          }
          { apiKey := some "test-key"
            onResponse := some fun response _model => do
              assertTrue (response.status == 200) "expected provider-stream early EOF response hook status"
              assertTrue
                (headerValueCaseInsensitive? response.headers "x-diagnostic-trace" ==
                  some "early-eof-route")
                "expected provider-stream early EOF response hook headers"
              sawResponseHeader.set true
          }
        pure false
      catch err =>
        pure (err.toString.contains "OpenAI Responses stream ended before a terminal response event")
    assertTrue failed "expected provider-stream OpenAI Responses early EOF parse failure"
    assertTrue
      (← sawResponseHeader.get)
      "expected provider-stream OpenAI Responses early EOF response hook to run"

def testWrappedOpenAIResponsesProviderStreamsEarlyEofInvokesResponseHook : IO Unit := do
  let port := 18119
  withHttpServer port do
    let sawResponseHeader ← IO.mkRef false
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-5.4"
        name := "GPT 5.4"
        provider := LeanAgent.Models.openAIProviderId
        api := "openai-responses"
        baseUrl := s!"http://127.0.0.1:{port}/responses-stream-early-eof"
        contextWindow := 100000
        maxTokens := 4096
        reasoning := true
      }
    let (responseRef, wrappedOptions) ← LeanAgent.Models.withCapturedResponseHook
      { apiKey := some "test-key"
        onResponse := some fun response _model => do
          assertTrue (response.status == 200) "expected wrapped provider-stream early EOF response hook status"
          assertTrue
            (headerValueCaseInsensitive? response.headers "x-diagnostic-trace" ==
              some "early-eof-route")
            "expected wrapped provider-stream early EOF response hook headers"
          sawResponseHeader.set true
      }
    let failed ←
      try
        let _stream ← LeanAgent.AI.Providers.Streams.openAIResponsesStreams.streamSimple
          model
          { systemPrompt := some "system"
            messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
          }
          wrappedOptions
        pure false
      catch err =>
        pure (err.toString.contains "OpenAI Responses stream ended before a terminal response event")
    assertTrue failed "expected wrapped provider-stream OpenAI Responses early EOF parse failure"
    assertTrue
      (← sawResponseHeader.get)
      "expected wrapped provider-stream OpenAI Responses early EOF response hook to run"
    match ← responseRef.get with
    | some response =>
        assertTrue (response.status == 200) "expected wrapped provider-stream to capture status"
        assertTrue
          (headerValueCaseInsensitive? response.headers "x-diagnostic-trace" == some "early-eof-route")
          "expected wrapped provider-stream to capture response headers"
    | none => fail "expected wrapped provider-stream to capture response"

def testCompatOpenAIResponsesEarlyEofReturnsErrorStream : IO Unit := do
  let port := 18112
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-5.4"
        name := "GPT 5.4"
        provider := LeanAgent.Models.openAIProviderId
        api := "openai-responses"
        baseUrl := s!"http://127.0.0.1:{port}/responses-stream-early-eof"
        contextWindow := 100000
        maxTokens := 4096
        reasoning := true
      }
    assertTrue (← LeanAgent.AI.Compat.shouldUseBuiltinModels model)
      "expected early EOF compat model to route through builtin models"
    let stream ← LeanAgent.AI.Compat.streamSimple
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "test-key" }
    assertTrue stream.isComplete "expected compat early EOF error stream to complete"
    assertTrue (stream.result.stopReason == .error) "expected early EOF compat stop reason"
    match stream.result.errorMessage with
    | some message =>
        assertTrue
          (message.contains "OpenAI Responses stream ended before a terminal response event")
          "expected early EOF compat error message"
    | none => fail "expected compat early EOF error message"
    match stream.result.diagnostics[0]? with
    | some diagnostic =>
        assertTrue (diagnostic.type == "provider_error") "expected provider_error diagnostic"
        match diagnostic.error with
        | some err =>
            assertTrue
              (err.message.contains "OpenAI Responses stream ended before a terminal response event")
              "expected early EOF diagnostic detail"
        | none => fail "expected early EOF diagnostic error payload"
        match diagnostic.details with
        | some details =>
            assertTrue (jsonNatField? details "status" == some 200)
              "expected early EOF diagnostic HTTP status"
        | none => fail "expected early EOF diagnostic details"
    | none => fail "expected early EOF diagnostic entry"
    assertTrue
      (match stream.events.back? with
       | some (.error .error _) => true
       | _ => false)
      "expected compat early EOF final error event"

def testAzureOpenAIResponsesStreamWithOptionsLocal : IO Unit := do
  let port := 18094
  withHttpServer port do
    let sawResponse ← IO.mkRef false
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
        onResponse := some fun response model => do
          assertTrue (model.api == azureResponsesModel.api)
            "expected Azure response hook model api"
          assertTrue (response.status == 200) "expected Azure response hook status"
          assertTrue (headerValueCaseInsensitive? response.headers "x-hook-response" == some "azure-responses")
            "expected Azure response hook headers"
          sawResponse.set true
      }
    assertTrue stream.isComplete "expected completed Azure Responses stream"
    assertTrue (stream.result.responseId == some "resp_azure_http") "expected Azure response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content == "mini-deployment|True|azure-key||trace-azure")
      "expected Azure deployment, stream flag, api-key header, no bearer auth, and custom header"
    assertTrue (← sawResponse.get) "expected Azure response hook to run"

def testCompatAzureOpenAIResponsesTypedLegacyAliasLocal : IO Unit := do
  let port := 18103
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-4o-mini"
        name := "Azure GPT-4o mini"
        provider := "azure-openai-responses"
        api := "azure-openai-responses"
        baseUrl := s!"http://127.0.0.1:{port}/azure-responses"
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamAzureOpenAIResponses
      model
      { messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }] }
      { apiKey := some "azure-key"
        azureApiVersion := some "2025-01-01"
        azureDeploymentName := some "mini-deployment"
        headers := #[("X-Trace", some "trace-azure")]
      }
    assertTrue stream.isComplete "expected compat Azure Responses typed legacy alias stream"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content == "mini-deployment|True|azure-key||trace-azure")
      "expected compat Azure Responses typed alias to preserve deployment options"

def testAnthropicMessagesStreamWithOptionsLocal : IO Unit := do
  let port := 18096
  withHttpServer port do
    let sawResponse ← IO.mkRef false
    let stream ← LeanAgent.AI.Api.AnthropicMessages.completeStreamWithOptions
      { apiKey := "anthropic-key"
        baseUrl := s!"http://127.0.0.1:{port}/anthropic-stream/v1"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      anthropicModelRef
      #["text", "image"]
      64000
      true
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { headers := #[("X-Trace", some "trace-anthropic")]
        onResponse := some fun response model => do
          assertTrue (model.api == LeanAgent.AI.Api.AnthropicMessages.api)
            "expected Anthropic response hook model api"
          assertTrue (response.status == 200) "expected Anthropic response hook status"
          assertTrue (headerValueCaseInsensitive? response.headers "x-hook-response" == some "anthropic")
            "expected Anthropic response hook headers"
          sawResponse.set true
      }
    assertTrue stream.isComplete "expected completed Anthropic stream"
    assertTrue (stream.result.responseId == some "msg_anthropic_http") "expected Anthropic response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content ==
        "claude-sonnet-4-5|True|anthropic-key|2023-06-01|trace-anthropic|")
      "expected Anthropic model, stream flag, x-api-key, version header, and custom header"
    assertTrue (stream.result.usage.input == 4) "expected Anthropic local input usage"
    assertTrue (stream.result.usage.output == 2) "expected Anthropic local output usage"
    assertTrue
      (stream.events.any fun
        | .textDelta _ "claude-sonnet-4-5|True|anthropic-key|2023-06-01|trace-anthropic|" _ => true
        | _ => false)
      "expected Anthropic local text delta"
    assertTrue (← sawResponse.get) "expected Anthropic response hook to run"
    let affinityStream ← LeanAgent.AI.Api.AnthropicMessages.completeStreamWithOptions
      { apiKey := "anthropic-key"
        baseUrl := s!"http://127.0.0.1:{port}/anthropic-stream/v1"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      anthropicModelRef
      #["text", "image"]
      64000
      true
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { sessionId := some "session-anthropic"
        sendSessionAffinityHeaders := true
        headers := #[("X-Trace", some "trace-anthropic"), ("x-session-affinity", some "caller-session")]
      }
    assertTrue
      (LeanAgent.AI.contentPlainText affinityStream.result.content ==
        "claude-sonnet-4-5|True|anthropic-key|2023-06-01|trace-anthropic|caller-session")
      "expected Anthropic session affinity header with caller override"

def testCompatAnthropicTypedLegacyAliasLocal : IO Unit := do
  let port := 18105
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := LeanAgent.Models.anthropicDefaultModel
        name := "Claude Sonnet"
        provider := LeanAgent.Models.anthropicProviderId
        api := LeanAgent.AI.Api.AnthropicMessages.api
        baseUrl := s!"http://127.0.0.1:{port}/anthropic-typed/v1"
        contextWindow := 200000
        maxTokens := 64000
        reasoning := true
        input := #["text", "image"]
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamAnthropic
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "anthropic-key"
        thinkingEnabled := some true
        thinkingBudgetTokens := some 2048
        thinkingDisplay := some "omitted"
        toolChoice := some .any
        headers := #[("X-Trace", some "trace-anthropic")]
      }
    assertTrue stream.isComplete "expected compat Anthropic typed legacy alias stream"
    assertTrue (stream.result.responseId == some "msg_anthropic_typed_http")
      "expected typed Anthropic response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content ==
        "claude-sonnet-4-5|True|anthropic-key|enabled|2048|omitted|any|trace-anthropic")
      "expected compat Anthropic typed alias to preserve thinking and tool choice options"

def testCompatAnthropicBuiltinDispatch : IO Unit := do
  let port := 18094
  withHttpServer port do
    LeanAgent.AI.Compat.resetApiProviders
    match ← LeanAgent.AI.Compat.getApiProvider? LeanAgent.AI.Api.AnthropicMessages.api with
    | some provider =>
        assertTrue (provider.api == LeanAgent.AI.Api.AnthropicMessages.api)
          "expected compat Anthropic builtin provider registration"
    | none => fail "expected compat Anthropic builtin provider"
    let model : LeanAgent.Models.ModelInfo :=
      { id := LeanAgent.Models.anthropicDefaultModel
        name := "Claude Sonnet"
        provider := LeanAgent.Models.anthropicProviderId
        api := LeanAgent.AI.Api.AnthropicMessages.api
        baseUrl := s!"http://127.0.0.1:{port}/anthropic-typed/v1"
        contextWindow := 200000
        maxTokens := 64000
        reasoning := true
        input := #["text", "image"]
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamSimpleAnthropic
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "anthropic-key"
        headers := #[("X-Trace", some "trace-anthropic")]
      }
    assertTrue stream.isComplete "expected compat Anthropic built-in stream"
    assertTrue (stream.result.responseId == some "msg_anthropic_typed_http")
      "expected compat Anthropic built-in response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content ==
        "claude-sonnet-4-5|True|anthropic-key|disabled||||trace-anthropic")
      "expected compat Anthropic built-in dispatch"
    LeanAgent.AI.Compat.resetApiProviders

def testCompatAnthropicCompleteSimpleAliasLocal : IO Unit := do
  let port := 18094
  withHttpServer port do
    LeanAgent.AI.Compat.resetApiProviders
    let model : LeanAgent.Models.ModelInfo :=
      { id := LeanAgent.Models.anthropicDefaultModel
        name := "Claude Sonnet"
        provider := LeanAgent.Models.anthropicProviderId
        api := LeanAgent.AI.Api.AnthropicMessages.api
        baseUrl := s!"http://127.0.0.1:{port}/anthropic-typed/v1"
        contextWindow := 200000
        maxTokens := 64000
        reasoning := true
        input := #["text", "image"]
      }
    let message ← LeanAgent.AI.Compat.Aliases.completeSimpleAnthropic
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "anthropic-key"
        headers := #[("X-Trace", some "trace-anthropic")]
      }
    assertTrue (message.responseId == some "msg_anthropic_typed_http")
      "expected compat Anthropic simple complete alias response id"
    assertTrue
      (LeanAgent.AI.contentPlainText message.content ==
        "claude-sonnet-4-5|True|anthropic-key|disabled||||trace-anthropic")
      "expected compat Anthropic simple complete alias dispatch"
    LeanAgent.AI.Compat.resetApiProviders

def testGoogleGenerativeAIStreamWithOptionsLocal : IO Unit := do
  let port := 18098
  withHttpServer port do
    let sawResponse ← IO.mkRef false
    let stream ← LeanAgent.AI.Api.GoogleGenerativeAI.completeStreamWithOptions
      { apiKey := "google-key"
        baseUrl := s!"http://127.0.0.1:{port}/google-stream"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      googleModelRef
      #["text", "image"]
      true
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { maxTokens := some 64
        headers := #[("X-Trace", some "trace-google")]
        onResponse := some fun response model => do
          assertTrue (model.api == LeanAgent.AI.Api.GoogleGenerativeAI.api)
            "expected Google response hook model api"
          assertTrue (response.status == 200) "expected Google response hook status"
          assertTrue (headerValueCaseInsensitive? response.headers "x-hook-response" == some "google")
            "expected Google response hook headers"
          sawResponse.set true
      }
    assertTrue stream.isComplete "expected completed Google stream"
    assertTrue (stream.result.responseId == some "resp_google_http") "expected Google response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content == "hello|True|google-key|trace-google")
      "expected Google user text, generation config flag, api key, and custom header"
    assertTrue (stream.result.usage.input == 3) "expected Google local input usage"
    assertTrue (stream.result.usage.output == 2) "expected Google local output usage"
    assertTrue (stream.result.usage.cacheRead == 1) "expected Google local cache read"
    assertTrue
      (stream.events.any fun
        | .textDelta _ "hello|True" _ => true
        | _ => false)
      "expected Google local text delta"
    assertTrue (← sawResponse.get) "expected Google response hook to run"

def testCompatGoogleTypedLegacyAliasLocal : IO Unit := do
  let port := 18106
  withHttpServer port do
    let tool : LeanAgent.AI.Tool :=
      { name := "lookup"
        description := "Lookup a value"
        parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
      }
    let model : LeanAgent.Models.ModelInfo :=
      { id := LeanAgent.Models.googleDefaultModel
        name := "Gemini 2.5 Flash"
        provider := LeanAgent.Models.googleProviderId
        api := LeanAgent.AI.Api.GoogleGenerativeAI.api
        baseUrl := s!"http://127.0.0.1:{port}/google-typed"
        contextWindow := 1048576
        maxTokens := 65536
        reasoning := true
        input := #["text", "image"]
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamGoogle
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
        tools := #[tool]
      }
      { apiKey := some "google-key"
        thinkingEnabled := some true
        thinkingBudgetTokens := some 1234
        thinkingLevel := some "HIGH"
        toolChoice := some .any
        headers := #[("X-Trace", some "trace-google")]
      }
    assertTrue stream.isComplete "expected compat Google typed legacy alias stream"
    assertTrue (stream.result.responseId == some "resp_google_typed_http")
      "expected typed Google response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content ==
        "True|1234|HIGH|ANY|google-key|trace-google")
      "expected compat Google typed alias to preserve thinking and tool choice options"
    assertTrue (stream.result.usage.reasoning == some 3) "expected Google typed thinking token usage"

def testGoogleVertexResolvedRequestHeadersWithAuthorizedUserAdc : IO Unit := do
  let port := 18110
  withHttpServer port do
    IO.FS.withTempDir fun root => do
      let credentialsPath := root / "google-authorized-user.json"
      writeGoogleVertexAuthorizedUserCredentials
        credentialsPath
        s!"http://127.0.0.1:{port}/google-oauth-authorized-user"
      let headers ← LeanAgent.AI.Api.GoogleVertex.resolvedRequestHeaders
        { apiKey := LeanAgent.AI.Api.GoogleVertex.vertexCredentialsMarker
          timeoutSeconds := 5
          connectTimeoutSeconds := 5
          noProxy := some "*"
          userAgent := "lean-agent-test/0.1.0"
        }
        { env := #[("GOOGLE_APPLICATION_CREDENTIALS", credentialsPath.toString)]
          headers := #[("X-Trace", some "trace-vertex")]
        }
      assertTrue
        (headerValueCaseInsensitive? headers "authorization" == some "Bearer adc-authorized-user-token")
        "expected authorized-user ADC bearer token"
      assertTrue
        (headerValueCaseInsensitive? headers "x-trace" == some "trace-vertex")
        "expected ADC-resolved headers to keep caller headers"

def testGoogleVertexStreamWithOptionsLocal : IO Unit := do
  let port := 18099
  withHttpServer port do
    let sawResponse ← IO.mkRef false
    let stream ← LeanAgent.AI.Api.GoogleVertex.completeStreamWithOptions
      { apiKey := LeanAgent.AI.Api.GoogleVertex.vertexCredentialsMarker
        baseUrl := s!"http://127.0.0.1:{port}/vertex"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      googleVertexModelRef
      #["text", "image"]
      true
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { project := some "project-1"
        location := some "us-central1"
        maxTokens := some 64
        headers := #[("Authorization", some "Bearer adc-token"), ("X-Trace", some "trace-vertex")]
        onResponse := some fun response model => do
          assertTrue (model.api == LeanAgent.AI.Api.GoogleVertex.api)
            "expected Vertex response hook model api"
          assertTrue (response.status == 200) "expected Vertex response hook status"
          assertTrue (headerValueCaseInsensitive? response.headers "x-hook-response" == some "vertex")
            "expected Vertex response hook headers"
          sawResponse.set true
      }
    assertTrue stream.isComplete "expected completed Vertex stream"
    assertTrue (stream.result.responseId == some "resp_vertex_http") "expected Vertex response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content == "hello|Bearer adc-token||trace-vertex")
      "expected Vertex user text, bearer auth, omitted API key header, and custom header"
    assertTrue (stream.result.usage.input == 3) "expected Vertex local cached input subtraction"
    assertTrue (stream.result.usage.output == 3) "expected Vertex local output usage"
    assertTrue (stream.result.usage.cacheRead == 2) "expected Vertex local cache read"
    assertTrue
      (stream.events.any fun
        | .textDelta _ "hello|Bearer" _ => true
        | _ => false)
      "expected Vertex local text delta"
    assertTrue (← sawResponse.get) "expected Vertex response hook to run"

def testGoogleVertexStreamWithServiceAccountAdcLocal : IO Unit := do
  let port := 18111
  withHttpServer port do
    IO.FS.withTempDir fun root => do
      let credentialsPath := root / "google-service-account.json"
      writeGoogleVertexServiceAccountCredentials
        credentialsPath
        s!"http://127.0.0.1:{port}/google-oauth-service-account"
      let stream ← LeanAgent.AI.Api.GoogleVertex.completeStreamWithOptions
        { apiKey := LeanAgent.AI.Api.GoogleVertex.vertexCredentialsMarker
          baseUrl := s!"http://127.0.0.1:{port}/vertex"
          timeoutSeconds := 5
          connectTimeoutSeconds := 5
          noProxy := some "*"
          userAgent := "lean-agent-test/0.1.0"
        }
        googleVertexModelRef
        #["text", "image"]
        true
        { systemPrompt := some "system"
          messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
        }
        { project := some "project-1"
          location := some "us-central1"
          maxTokens := some 64
          env := #[("GOOGLE_APPLICATION_CREDENTIALS", credentialsPath.toString)]
          headers := #[("X-Trace", some "trace-vertex")]
        }
      assertTrue stream.isComplete "expected completed Vertex ADC service-account stream"
      assertTrue (stream.result.responseId == some "resp_vertex_http")
        "expected Vertex ADC service-account response id"
      assertTrue
        (LeanAgent.AI.contentPlainText stream.result.content ==
          "hello|Bearer adc-service-token||trace-vertex")
        "expected Vertex service-account ADC bearer auth"

def testCompatGoogleVertexTypedLegacyAliasLocal : IO Unit := do
  let port := 18107
  withHttpServer port do
    let tool : LeanAgent.AI.Tool :=
      { name := "lookup"
        description := "Lookup a value"
        parameters := LeanAgent.Json.obj [("type", LeanAgent.Json.str "object")]
      }
    let model : LeanAgent.Models.ModelInfo :=
      { id := LeanAgent.Models.googleVertexDefaultModel
        name := "Gemini 2.5 Flash Vertex"
        provider := LeanAgent.Models.googleVertexProviderId
        api := LeanAgent.AI.Api.GoogleVertex.api
        baseUrl := s!"http://127.0.0.1:{port}/vertex-typed"
        contextWindow := 1048576
        maxTokens := 65536
        reasoning := true
        input := #["text", "image"]
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamGoogleVertex
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
        tools := #[tool]
      }
      { apiKey := some LeanAgent.AI.Api.GoogleVertex.vertexCredentialsMarker
        project := some "project-typed"
        location := some "europe-west4"
        thinkingEnabled := some true
        thinkingBudgetTokens := some 4321
        thinkingLevel := some "MEDIUM"
        toolChoice := some .any
        headers := #[("Authorization", some "Bearer adc-token"), ("X-Trace", some "trace-vertex")]
      }
    assertTrue stream.isComplete "expected compat Google Vertex typed legacy alias stream"
    assertTrue (stream.result.responseId == some "resp_vertex_typed_http")
      "expected typed Vertex response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content ==
        "True|4321|MEDIUM|ANY|Bearer adc-token||trace-vertex")
      "expected compat Vertex typed alias to preserve project/location, thinking, tool choice, and ADC auth headers"
    assertTrue (stream.result.usage.reasoning == some 5) "expected Vertex typed thinking token usage"

def testMistralConversationsStreamWithOptionsLocal : IO Unit := do
  let port := 18100
  withHttpServer port do
    let sawResponse ← IO.mkRef false
    let stream ← LeanAgent.AI.Api.MistralConversations.completeStreamWithOptions
      { apiKey := "mistral-key"
        baseUrl := s!"http://127.0.0.1:{port}/mistral"
        timeoutSeconds := 5
        connectTimeoutSeconds := 5
        noProxy := some "*"
        userAgent := "lean-agent-test/0.1.0"
      }
      mistralModelRef
      #["text", "image"]
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { sessionId := some "session-123"
        reasoningEffort := some "high"
        promptMode := some "reasoning"
        headers := #[("X-Trace", some "trace-mistral")]
        onResponse := some fun response model => do
          assertTrue (model.api == LeanAgent.AI.Api.MistralConversations.api)
            "expected Mistral response hook model api"
          assertTrue (response.status == 200) "expected Mistral response hook status"
          assertTrue (headerValueCaseInsensitive? response.headers "x-hook-response" == some "mistral")
            "expected Mistral response hook headers"
          sawResponse.set true
      }
    assertTrue stream.isComplete "expected completed Mistral stream"
    assertTrue (stream.result.responseId == some "chatcmpl_mistral_http") "expected Mistral response id"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content ==
        "devstral-medium-latest|True|Bearer mistral-key|session-123|session-123|high|reasoning|trace-mistral|system")
      "expected Mistral model, stream flag, bearer auth, cache affinity, reasoning, prompt mode, custom header, and system text"
    assertTrue (stream.result.usage.input == 3) "expected Mistral local cached input subtraction"
    assertTrue (stream.result.usage.output == 3) "expected Mistral local output usage"
    assertTrue (stream.result.usage.cacheRead == 2) "expected Mistral local cache read"
    assertTrue
      (stream.events.any fun
        | .textDelta _ delta _ => delta.contains "devstral-medium-latest"
        | _ => false)
      "expected Mistral local text delta"
    assertTrue (← sawResponse.get) "expected Mistral response hook to run"

def testCompatMistralTypedLegacyAliasLocal : IO Unit := do
  let port := 18101
  withHttpServer port do
    let model : LeanAgent.Models.ModelInfo :=
      { id := LeanAgent.Models.mistralDefaultModel
        name := "Devstral"
        provider := LeanAgent.Models.mistralProviderId
        api := LeanAgent.AI.Api.MistralConversations.api
        baseUrl := s!"http://127.0.0.1:{port}/mistral"
        input := #["text", "image"]
      }
    let stream ← LeanAgent.AI.Compat.Aliases.streamMistral
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "mistral-key"
        sessionId := some "session-typed"
        toolChoice := some .required
        reasoningEffort := some "high"
        promptMode := some "reasoning"
        headers := #[("X-Trace", some "trace-mistral")]
      }
    assertTrue stream.isComplete "expected compat Mistral typed legacy alias stream"
    assertTrue
      (LeanAgent.AI.contentPlainText stream.result.content ==
        "devstral-medium-latest|True|Bearer mistral-key|session-typed|session-typed|high|reasoning|trace-mistral|system")
      "expected compat Mistral typed alias to preserve provider-specific options"

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

def testModelsCollectionProviderErrorDiagnosticsIncludeResponseHeaders : IO Unit := do
  let port := 18083
  withHttpServer port do
    let providerId := "diagnostic-openai"
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-4o-mini"
        name := "Diagnostic OpenAI"
        provider := providerId
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/diagnostic-openai"
        contextWindow := 128000
        maxTokens := 4096
      }
    let provider ← LeanAgent.Models.createProvider
      { id := providerId
        name := some "Diagnostic OpenAI"
        auth := {}
        models := #[model]
        apis := #[{ api := model.api, streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams }]
      }
    let collection ← LeanAgent.Models.createModels
    collection.setProvider provider
    let stream ← collection.streamSimple
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "test-key" }
    assertTrue stream.isComplete "expected collection provider error stream to complete"
    assertTrue (stream.result.stopReason == .error) "expected collection provider error stop reason"
    match stream.result.errorMessage with
    | some message =>
        assertTrue (message.contains "provider HTTP 429") "expected collection provider error message"
    | none => fail "expected collection provider error message"
    match stream.result.diagnostics[0]? with
    | some diagnostic =>
        assertTrue (diagnostic.type == "provider_error") "expected collection provider_error diagnostic"
        match diagnostic.details with
        | some details =>
            assertTrue (jsonNatField? details "status" == some 429)
              "expected collection diagnostic HTTP status"
        | none => fail "expected collection diagnostic details"
        assertTrue
          (diagnosticResponseHeaderValueCaseInsensitive? diagnostic "x-diagnostic-trace" ==
            some "rate-limit-route")
          "expected collection diagnostic response headers"
    | none => fail "expected collection provider diagnostic entry"

def testModelsCollectionProviderErrorDiagnosticsPreserveResponseHeadersWhenOnResponseThrows : IO Unit := do
  let port := 18084
  withHttpServer port do
    let providerId := "diagnostic-openai"
    let model : LeanAgent.Models.ModelInfo :=
      { id := "gpt-4o-mini"
        name := "Diagnostic OpenAI"
        provider := providerId
        api := "openai-completions"
        baseUrl := s!"http://127.0.0.1:{port}/diagnostic-openai"
        contextWindow := 128000
        maxTokens := 4096
      }
    let provider ← LeanAgent.Models.createProvider
      { id := providerId
        name := some "Diagnostic OpenAI"
        auth := {}
        models := #[model]
        apis := #[{ api := model.api, streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams }]
      }
    let collection ← LeanAgent.Models.createModels
    collection.setProvider provider
    let stream ← collection.streamSimple
      model
      { systemPrompt := some "system"
        messages := #[.user { content := #[LeanAgent.AI.text "hello"], timestamp := 1 }]
      }
      { apiKey := some "test-key"
        onResponse := some fun response _model => do
          assertTrue (response.status == 429) "expected throwing hook response status"
          throw (IO.userError "response hook failed")
      }
    assertTrue stream.isComplete "expected throwing-hook error stream to complete"
    assertTrue (stream.result.stopReason == .error) "expected throwing-hook stop reason"
    match stream.result.errorMessage with
    | some message =>
        assertTrue (message.contains "response hook failed") "expected throwing hook error message"
    | none => fail "expected throwing hook error message"
    match stream.result.diagnostics[0]? with
    | some diagnostic =>
        assertTrue (diagnostic.type == "provider_error") "expected throwing-hook provider_error diagnostic"
        match diagnostic.details with
        | some details =>
            assertTrue (jsonNatField? details "status" == some 429)
              "expected throwing-hook diagnostic HTTP status"
        | none => fail "expected throwing-hook diagnostic details"
        assertTrue
          (diagnosticResponseHeaderValueCaseInsensitive? diagnostic "x-diagnostic-trace" ==
            some "rate-limit-route")
          "expected throwing-hook diagnostic response headers"
    | none => fail "expected throwing-hook diagnostic entry"

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
    testOpenAICompletionsContextSerializesUserImages
    testOpenAICompletionsContextBatchesToolResultImages
    testOpenAICompletionsContextReplaysThinkingAsText
    testOpenAICompletionsContextAddsAnthropicCacheMarkers
    testOpenAICompletionsContextRequiresToolResultNameAndBridgeForImageReplay
    testOpenAICompletionsContextAddsBridgeBeforeUserAfterToolResults
    testOpenAICompletionsContextAddsRoutingPreferences
    testOpenAICompletionsContextReplaysXiaomiMissingThinkingAsEmptyReasoningContent
    testOpenAICompletionsContextStrictCompat
    testOpenAICompletionsContextSetsZaiToolStream
    testOpenAICompletionsParsesReasoningDetailsBeforeToolCall
    testOpenAICompletionsContextReplaysReasoningDetails
    testOpenAICompletionsContextUsesOpenRouterReasoningObject
    testOpenAICompletionsContextUsesDeepSeekThinkingToggle
    testOpenAICompletionsContextUsesQwenThinkingFlags
    testOpenAICompletionsContextUsesConfigurableChatTemplateKwargs
    testOpenAICompletionsContextOmitsChatTemplateKwargsForNonReasoningModel
    testOpenAICompletionsContextUsesAntLingReasoningObject
    testOpenAICompletionsContextOmitsAntLingReasoningWhenSuppressed
    testOpenAICompletionsSerializesOptions
    testOpenAICompletionsUsesMappedReasoningEffort
    testOpenAICompletionsCompatSuppressesUnsupportedFields
    testOpenAICompletionsLegacyDetectsOpenRouterCompat
    testOpenAICompletionsLegacyDetectsAntLingCompat
    testOpenAICompletionsPromptCacheKey
    testOpenAICompletionsPromptCacheLongRetention
    testOpenAICompletionsPromptCacheClampsKey
    testOpenAICompletionsPromptCacheNoneOmitsFields
    testOpenAIPromptCacheClampHelper
    testOpenAICompletionsPromptCacheEnvLongRetention
    testOpenAICompletionsSessionAffinityHeaders
    testSSEParsesDataEvents
    testOpenAICompletionsStreamingPayload
    testOpenAICompletionsStreamingPayloadCanOmitUsageOption
    testOpenAICompletionsParsesStreamingText
    testOpenAICompletionsParsesStreamingToolCall
    testOpenAICompletionsCoalescesStreamingToolCallsByStableIndex
    testOpenAICompletionsAccumulatesMixedParallelToolDeltas
    testOpenAICompletionsParsesStreamingThinking
    testOpenAICompletionsParsesOpenCodeGoStreamingReasoning
    testOpenAICompletionsParsesGenericStreamingReasoningField
    testTransformMessagesCrossModelHandoff
    testTransformMessagesAddsSyntheticToolResults
    testTransformMessagesDowngradesUnsupportedImages
    testTransformMessagesSkipsErroredAssistant
    testOpenAIResponsesSharedNormalizesForeignToolCallIds
    testOpenAIResponsesSharedOmitsDifferentModelFcItemId
    testOpenAIResponsesSharedGeneratesFallbackMessageIds
    testOpenAIResponsesSharedConvertsTools
    testAnthropicMessagesRequestPayload
    testAnthropicMessagesCompatOptions
    testAnthropicMessagesCompatPayloadOptions
    testAnthropicMessagesHeaders
    testAnthropicMessagesParsesResponse
    testAnthropicMessagesParsesStreamingEvents
    testAnthropicMessagesStreamingRequiresMessageStop
    testGoogleGenerativeAIRequestPayload
    testGoogleSharedConvertToolsSanitizesOpenApiParameters
    testGoogleSharedThinkingHelpers
    testGoogleSharedImageToolResultRouting
    testGoogleSharedGemini3ToolCallThoughtSignatures
    testGoogleGenerativeAIParsesResponse
    testGoogleGenerativeAIParsesStreamingEvents
    testGoogleVertexUrlsAndHeaders
    testGoogleVertexAuthResolution
    testGoogleVertexResolvedRequestHeadersWithAuthorizedUserAdc
    testMistralConversationsRequestPayloadAndHeaders
    testMistralToolChoiceOptionVariants
    testMistralReasoningAndPromptCacheOptions
    testMistralConversationsParsesResponse
    testMistralConversationsParsesStreamingEvents
    testBedrockConverseRequestPayload
    testBedrockConverseHelpersAndTransportBoundary
    testBedrockConverseGovCloudThinkingDisplayOmitted
    testBedrockConversePreparedRequestSigV4
    testCompatBedrockTypedLegacyAliasBoundary
    testGitHubCopilotDynamicHeaders
    testOpenAIResponsesRequestPayload
    testOpenAIResponsesRequestUsesThinkingLevelMap
    testOpenAIResponsesRequestClampsMaxTokens
    testOpenAICodexResponsesAuthAndUrlHelpers
    testOpenAICodexResponsesRequestPayload
    testAzureOpenAIResponsesBaseUrlNormalization
    testAzureOpenAIResponsesConfigAndDeployment
    testAzureOpenAIResponsesRequestPayload
    testOpenAIResponsesServiceTierCostMultiplier
    testOpenAIResponsesParsesResponse
    testOpenAIResponsesParsesStreamingTextAndUsage
    testOpenAIResponsesParsesStreamingToolCall
    testOpenAIResponsesStreamingRequiresTerminalEvent
    testOpenAIResponsesStreamingIncompleteTerminalEvent
    testOpenAIResponsesStreamingFailedTerminalEvent
    testDiagnosticsExtractsProviderError
    testDiagnosticsFormatsThrownJsonValues
    testDiagnosticsProviderErrorObjectExtraction
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
    testJsonParseStreamingDropsDanglingSegments
    testJsonParseTruncatesPartialLiterals
    testJsonParseTryHarderMultiplePasses
    testSchemaStringEnum
    testValidationCoercesPlainJsonSchemas
    testValidationRejectsInvalidCoercions
    testValidationChecksSchemaBounds
    testValidationChecksSchemaCombinatorsAndConst
    testValidationChecksObjectAndArrayKeywords
    testValidationToolLookupAndRequired
    testSanitizeUnicodeSurrogates
    testEstimateTextTokensPredictable
    testOverflowClassifiesProviderErrors
    testAnthropicMessagesPreserveUnicodePayloads
    testOpenAICompletionsPreserveUnicodeInMessages
    testOverflowClassifiesContextWindowSignals
    testRetryClassifiesAssistantErrors
    testRetryWithRetriesSucceedsAfterTransientFailures
    testRetryWithRetriesStopsOnNonRetryableFailure
    testAbortCombineSignals
    testRetryWithRetriesStopsOnAbortSignal
    testModelCatalogDeepSeekDefaults
    testOpenAICompatibleProviderFamilyCatalog
    testTogetherCatalogReasoningEffortCompat
    testOpenCodeCatalogMaxTokensCompat
    testDefaultModelsRegistersOpenAICompatibleFamily
    testOpenAICompatibleProviderFactoriesMatchCatalog
    testBuiltinModelsGitHubCopilotOAuthFiltersModelList
    testDefaultModelsGitHubCopilotOAuthFiltersModelList
    testLegacySelectionRejectsAnthropicProvider
    testAuthDefaultContextEnvAndExpandHomePath
    testEnvApiKeyAuthLoginPromptsForSecret
    testModelsAuthEnvApiKeyResolution
    testModelsAuthStoredCredentialWins
    testFileCredentialStoreRoundTrip
    testFileCredentialStoreRejectsUnsupportedCredentialType
    testFileCredentialStoreOAuthRoundTrip
    testFileCredentialStoreWaitsForExternalLock
    testModelsAuthFileCredentialStore
    testModelsAuthOAuthValidCredential
    testModelsAuthOAuthExpiredCredentialRefreshes
    testModelsAuthOAuthConcurrentRefreshesSerialize
    testModelsAuthOAuthRefreshFailureUsesModelsErrorOauth
    testModelsAuthReadFailureUsesModelsErrorAuth
    testModelsAuthApiKeyFailureUsesModelsErrorAuth
    testModelsAuthOAuthModifyFailureUsesModelsErrorAuth
    testModelsAuthOAuthToAuthFailureUsesModelsErrorOauth
    testModelsAuthOAuthCredentialOwnsProvider
    testLazyOAuthLoadsOnceAndDelegates
    testOAuthProviderRegistryCrud
    testOAuthProviderRegistryReplacementPreservesOrder
    testModelsCollectionAppliesRegisteredOAuthModelHook
    testOAuthStandaloneModuleImportBootstrapsBuiltIns
    testCompatStandaloneModuleImportIncludesLegacyAliases
    testAIStandaloneModuleImportIncludesCoreSurface
    testOAuthRefreshTokenDispatch
    testOAuthGetOAuthApiKey
    testOAuthGetOAuthApiKeyErrors
    testOAuthDeviceCodeCompletesAfterPending
    testOAuthDeviceCodeSlowDownIncreasesInterval
    testOAuthDeviceCodeFailureAndCancellation
    testOAuthDeviceCodeSignalCancelsInFlightWait
    testOAuthDeviceCodeTimeouts
    testOAuthPageHtmlEscapesDynamicContent
    testOAuthSuccessPageOmitsDetails
    testOAuthPKCEChallengeMatchesRfcVector
    testOAuthPKCEGenerateUsesBase64UrlVerifier
    testAnthropicOAuthRegisterBuiltInProvider
    testAnthropicOAuthRefreshExchangesToken
    testAnthropicOAuthBrowserLoginUsesManualCode
    testAnthropicOAuthBrowserLoginUsesLocalCallback
    testAnthropicOAuthLocalCallbackAbortsManualCodePrompt
    testAnthropicOAuthBrowserLoginRejectsStateMismatch
    testOpenAICodexOAuthRegisterBuiltInProvider
    testOpenAICodexOAuthRefreshExchangesToken
    testOpenAICodexOAuthBrowserLoginUsesManualCode
    testOpenAICodexOAuthBrowserLoginUsesLocalCallback
    testOpenAICodexOAuthLocalCallbackAbortsManualCodePrompt
    testOpenAICodexOAuthBrowserLoginRejectsStateMismatch
    testOpenAICodexOAuthProviderDeviceCodeLogin
    testOpenAICodexOAuthDeviceCodeStart404UsesHelpfulError
    testOpenAICodexOAuthDeviceCodeLoginRespectsAbortSignal
    testGitHubCopilotOAuthDomainAndBaseUrlHelpers
    testGitHubCopilotOAuthParsesAvailableModels
    testGitHubCopilotOAuthModifiesModelsFromCredential
    testGitHubCopilotOAuthRegisterBuiltInProvider
    testGitHubCopilotOAuthRefreshFetchesAvailableModels
    testGitHubCopilotOAuthLoginReportsDeviceCode
    testGitHubCopilotOAuthLoginRespectsAbortSignal
    testGitHubCopilotOAuthRejectsUntrustedVerificationUri
    testGitHubCopilotOAuthNormalizesVerificationUri
    testGitHubCopilotOAuthLoginEnablesKnownModels
    testAuthOAuthBridgeAnthropicBrowserLogin
    testAuthOAuthBridgeOpenAICodexDeviceCodeLogin
    testAuthOAuthBridgeGitHubCopilotLogin
    testGitHubCopilotHeadersInference
    testCatalogProviderHeadersApplyThroughAuth
    testCloudflareWorkersAIAuthResolution
    testCloudflareAIGatewayAuthResolution
    testCloudflareStoredCredentialResolution
    testCloudflareProviderFactoriesExposeModelsAndAuth
    testBuiltinProvidersAllAggregatesImplementedProviders
    testBuiltinModelsCollectionMatchesPiInvariants
    testEnvApiKeysProviderMap
    testEnvApiKeysPrefersAnthropicOAuthToken
    testEnvApiKeysAmbientAuthMarkers
    testModelsCollectionDispatchesWithAuth
    testModelsCollectionGenericStreamAndCompleteDispatchWithAuth
    testModelsCollectionListingSwallowsProviderSourceFailures
    testModelsCollectionReplacementPreservesOrder
    testModelsCollectionUnknownProviderReturnsError
    testModelsCollectionAuthSetupFailureReturnsErrorStream
    testModelsCreateProviderDynamicRefreshDedupes
    testModelsCollectionRefreshAndFailureSemantics
    testModelsCollectionAppliesCloudflareAIGatewayAuth
    testCompatApiRegistryDispatchesAndUnregisters
    testCompatApiRegistryReplacementPreservesOrder
    testCompatGenericStreamAndCompleteDispatch
    testBedrockLazyApiOverride
    testCompatBuiltinDispatchUsesCloudflareGatewayAuth
    testImagesApiRegistryDispatchesAndUnregisters
    testImagesApiRegistryReplacementPreservesOrder
    testImagesApiRegistryMissingProviderReturnsError
    testCompatImageEntrypointsDispatchAndCatalog
    testImagesBuiltInRegistryRestoresOpenRouter
    testImageModelCatalogOpenRouter
    testImagesCollectionProviderCrudAndRefresh
    testImagesCollectionReplacementPreservesOrder
    testImagesCollectionAppliesAuthAndOptions
    testImagesCollectionAppliesOAuthAuth
    testImagesCollectionUnknownProviderReturnsError
    testImagesCollectionAbortSignalReturnsAborted
    testOpenRouterImagesAbortSignalReturnsAborted
    testOpenRouterImagesProviderFactoryAuthAndModels
    testBuiltinImagesModelsMatchesPiInvariants
    testCompatInjectsEnvApiKeyForKnownProviders
    testCompatInjectsEnvApiKeyForMappedProvidersOutsideCatalog
    testCompatMissingProviderReturnsError
    testCompatLegacyAliasesDispatchFixedApi
    testCompatLegacyAliasesRejectMismatchedApi
    testCompatLegacyAliasesUseRegistryForNonBuiltins
    testModelsCreateProviderMissingApiReturnsLazyErrorStream
    testModelsCreateProviderSetupFailurePropagatesProviderError
    testModelsLazyProviderStreamsLoadFailureReturnsErrorStream
    testApiLazyApiLoadFailureReturnsErrorStream
    testImagesLazyProviderLoadFailureReturnsErrorResult
    testModelsCalculateCost
    testModelsThinkingLevelMapSupport
    testModelsClampSimpleOptionsClampsReasoning
    testFauxProviderQueuesResponses
    testFauxProviderHelperBlocksAndEvents
    testFauxProviderModelsFactoriesAndCache
    testCompatRegisterFauxProviderDispatchesAndUnregisters
    testFauxProviderAbortSignalReturnsAborted
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
    testHttpClientGenericRequest
    testHttpClientResponseLimit
    testOpenAICompletionsRetriesTransientHttpFailure
    testOpenAICompletionsSendsCustomHeaders
    testOpenAICompletionsPayloadAndResponseHooks
    testOpenAICompletionsStreamWithOptionsLocal
    testCompatOpenAICompletionsTypedLegacyAliasLocal
    testOpenAICompatibleStreamsUsesStreamingRuntime
    testOpenAICompatibleCompleteSimpleSurfacesRoutedResponseModel
    testOpenAICompatibleCompleteSimpleOmitsMatchingResponseModel
    testOpenAICompatibleCompleteSimpleIgnoresEmptyOrMissingResponseModel
    testOpenAICompatibleCompleteSimpleMapsUnknownFinishReasonToError
    testOpenAICompatibleCompleteSimpleIgnoresNullStreamChunks
    testOpenAICompatibleCompleteSimpleErrorsWhenFinishReasonIsMissing
    testOpenAICompatibleStreamsApplyModelCost
    testOpenAICompatibleStreamsDetectOpenRouterDeveloperRole
    testOpenAICompatibleStreamsDetectMoonshotCompatDefaults
    testOpenAICompatibleStreamsUseTogetherGptOssReasoningEffort
    testOpenAICompatibleStreamsDetectTogetherReasoningOnlyCompat
    testOpenAICompatibleStreamsUseOpenCodeMaxTokensCompat
    testOpenAICompatibleStreamsUseOpenCodeGoMaxTokensCompat
    testOpenAICompatibleStreamsOmitMoonshotDisabledThinkingForK27Code
    testOpenAICompatibleStreamsKeepMoonshotDisabledThinkingForK26
    testOpenAICompatibleStreamsOmitStreamingUsageWhenCompatDisablesIt
    testLegacyOpenAICompletionsAliasOmitStreamingUsageWhenCompatDisablesIt
    testOpenAICompatibleStreamsKeepGitHubCopilotDetectedMaxCompletionTokens
    testLegacyOpenAICompletionsAliasKeepsGitHubCopilotDetectedMaxCompletionTokens
    testOpenAICompatibleStreamsClampMaxTokens
    testCloudflareAIGatewayOpenAICompatibleHeaderAuthLocal
    testOpenRouterImagesRequestPayload
    testOpenRouterImagesGenerateLocal
    testOpenRouterImagesMissingApiKeyReturnsError
    testOpenAIResponsesDispatchesThroughModelsCollection
    testOpenAIProviderFactoryDispatchesResponsesRuntime
    testOpenAICodexProviderDispatchesSSEWithStoredOAuth
    testOpenAIResponsesCompleteWithOptionsLocal
    testOpenAIResponsesPayloadAndResponseHooks
    testOpenAIResponsesSendsCopilotDynamicHeaders
    testOpenAIResponsesStreamWithOptionsLocal
    testOpenAIResponsesOptionsFromSimplePreserveResponseHook
    testModelsApplyAuthPreservesResponseHook
    testModelsWithCapturedResponseHookPreservesOriginalHook
    testModelsWithCapturedResponseHookCapturesResponseBeforeOriginalHookFailure
    testWrappedOpenAIResponsesCompatOptionChainPreservesResponseHook
    testBuiltinOpenAIApplyAuthPreservesResponseHook
    testCompatOpenAIResponsesTypedLegacyAliasLocal
    testCompatOpenAIResponsesRootLegacyAliasLocal
    testCompatOpenAIResponsesTypedLegacyAliasCompleteLocal
    testOpenAIResponsesEarlyEofInvokesResponseHook
    testOpenAIResponsesProviderStreamsEarlyEofInvokesResponseHook
    testWrappedOpenAIResponsesProviderStreamsEarlyEofInvokesResponseHook
    testCompatOpenAIResponsesEarlyEofReturnsErrorStream
    testAzureOpenAIResponsesStreamWithOptionsLocal
    testCompatAzureOpenAIResponsesTypedLegacyAliasLocal
    testAnthropicMessagesStreamWithOptionsLocal
    testCompatAnthropicBuiltinDispatch
    testCompatAnthropicTypedLegacyAliasLocal
    testCompatAnthropicCompleteSimpleAliasLocal
    testGoogleGenerativeAIStreamWithOptionsLocal
    testCompatGoogleTypedLegacyAliasLocal
    testGoogleVertexStreamWithOptionsLocal
    testGoogleVertexStreamWithServiceAccountAdcLocal
    testCompatGoogleVertexTypedLegacyAliasLocal
    testMistralConversationsStreamWithOptionsLocal
    testCompatMistralTypedLegacyAliasLocal
    testCompatAzureOpenAIResponsesBuiltinDispatch
    testCompatOpenAICodexResponsesBuiltinDispatch
    testCompatOpenAICodexResponsesTypedLegacyAliasLocal
    testCompatOpenAICodexResponsesMissingTokenUsesOauthCode
    testOpenAICodexResponsesProviderHttpError
    testOpenAICodexProviderHttpErrorDiagnosticsIncludeResponseHeaders
    testOpenAICompletionsProviderErrorDiagnostics
    testModelsCollectionProviderErrorDiagnosticsIncludeResponseHeaders
    testModelsCollectionProviderErrorDiagnosticsPreserveResponseHeadersWhenOnResponseThrows
    IO.println "lean-agent tests passed"
    pure 0
  catch err =>
    IO.eprintln err.toString
    pure 1
