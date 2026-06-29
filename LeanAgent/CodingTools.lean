import Lean
import LeanAgent.Core
import LeanAgent.Agent.Types
import LeanAgent.Json
namespace LeanAgent.CodingTools

open LeanAgent

def maxReadLines : Nat := 2000
def maxToolOutputChars : Nat := 50000
def defaultBashTimeoutSeconds : Nat := 120
def maxListEntries : Nat := 500

def candidatePath (root : System.FilePath) (raw : String) : System.FilePath :=
  let path := System.FilePath.mk raw
  if path.isAbsolute then path.normalize else (root / path).normalize

def pathWithin? (root path : System.FilePath) : Bool :=
  let rootStr := root.normalize.toString
  let pathStr := path.normalize.toString
  let rootPrefix := if rootStr.endsWith "/" then rootStr else rootStr ++ "/"
  pathStr == rootStr || pathStr.startsWith rootPrefix

def ensureWithinRoot (root path : System.FilePath) : IO System.FilePath := do
  let rootReal ← IO.FS.realPath root
  let path := path.normalize
  if pathWithin? rootReal path then
    pure path
  else
    throw (IO.userError s!"path escapes working directory: {path}")

def resolveExistingPath (root : System.FilePath) (raw : String) : IO System.FilePath := do
  let candidate := candidatePath root raw
  let pathExists ← candidate.pathExists
  if !pathExists then
    throw (IO.userError s!"path not found: {candidate}")
  let actual ← IO.FS.realPath candidate
  ensureWithinRoot root actual

def resolveExistingFile (root : System.FilePath) (raw : String) : IO System.FilePath := do
  let path ← resolveExistingPath root raw
  let isDir ← path.isDir
  if isDir then
    throw (IO.userError s!"path is a directory: {path}")
  pure path

def resolveExistingDir (root : System.FilePath) (raw : String) : IO System.FilePath := do
  let path ← resolveExistingPath root raw
  let isDir ← path.isDir
  if !isDir then
    throw (IO.userError s!"path is not a directory: {path}")
  pure path

def resolveWritablePath (root : System.FilePath) (raw : String) : IO System.FilePath := do
  let candidate := candidatePath root raw
  let pathExists ← candidate.pathExists
  if pathExists then
    resolveExistingFile root raw
  else
    let rootReal ← IO.FS.realPath root
    let normalized := candidate.normalize
    if !pathWithin? rootReal normalized then
      throw (IO.userError s!"path escapes working directory: {normalized}")
    match normalized.parent with
    | none => throw (IO.userError s!"path has no parent directory: {normalized}")
    | some parent =>
        let parentExists ← parent.pathExists
        if parentExists then
          let parentReal ← IO.FS.realPath parent
          let _ ← ensureWithinRoot root parentReal
          pure normalized
        else
          let _ ← ensureWithinRoot root parent.normalize
          pure normalized

def shellQuote (value : String) : String :=
  "'" ++ String.intercalate "'\\''" (value.splitOn "'") ++ "'"

def readFileIfExists (path : System.FilePath) : IO String := do
  if ← path.pathExists then
    IO.FS.readFile path
  else
    pure ""

def safeRemoveDirAll (path : System.FilePath) : IO Unit := do
  try
    IO.FS.removeDirAll path
  catch _ =>
    pure ()

def requireArgString (args : Lean.Json) (key : String) : IO String :=
  match LeanAgent.Json.requiredString args key with
  | .ok value => pure value
  | .error err => throw (IO.userError s!"invalid `{key}` argument: {err}")

def optionalArgString (args : Lean.Json) (key : String) : IO (Option String) :=
  match LeanAgent.Json.optionalString args key with
  | .ok value => pure value
  | .error err => throw (IO.userError s!"invalid `{key}` argument: {err}")

def optionalArgNat (args : Lean.Json) (key : String) : IO (Option Nat) :=
  match LeanAgent.Json.optionalNat args key with
  | .ok value => pure value
  | .error err => throw (IO.userError s!"invalid `{key}` argument: {err}")

def optionalArgBool (args : Lean.Json) (key : String) : IO (Option Bool) :=
  match LeanAgent.Json.optionalBool args key with
  | .ok value => pure value
  | .error err => throw (IO.userError s!"invalid `{key}` argument: {err}")

def truncateChars (text : String) (limit : Nat) : String × Bool :=
  if text.length <= limit then
    (text, false)
  else
    ((text.take limit).toString ++ s!"\n\n[truncated to {limit} characters]", true)

def selectLines (text : String) (offset? : Option Nat) (limit? : Option Nat) : String × Bool :=
  let lines := text.splitOn "\n"
  let startLine := offset?.getD 1
  let startIndex := if startLine == 0 then 0 else startLine - 1
  let requestedLimit := limit?.getD maxReadLines
  let selected := (lines.drop startIndex).take requestedLimit
  let truncatedByLines := startIndex + selected.length < lines.length
  let rendered := String.intercalate "\n" selected
  if truncatedByLines then
    let nextOffset := startIndex + selected.length + 1
    (rendered ++ s!"\n\n[more lines remain, continue with offset={nextOffset}]", true)
  else
    (rendered, false)

def makeReadTool (root : System.FilePath) : AgentTool :=
  let schema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "object")
      , ("properties",
          LeanAgent.Json.obj
            [ ("path", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string"), ("description", LeanAgent.Json.str "File path to read")])
            , ("offset", LeanAgent.Json.obj [("type", LeanAgent.Json.str "integer"), ("description", LeanAgent.Json.str "1-indexed line offset")])
            , ("limit", LeanAgent.Json.obj [("type", LeanAgent.Json.str "integer"), ("description", LeanAgent.Json.str "Maximum number of lines")])
            ])
      , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "path"])
      ]
  { name := "read"
    description := "Read a UTF-8 text file relative to the working directory."
    inputSchema := schema
    execute := fun call => do
      let rawPath ← requireArgString call.arguments "path"
      let offset? ← optionalArgNat call.arguments "offset"
      let limit? ← optionalArgNat call.arguments "limit"
      let path ← resolveExistingFile root rawPath
      let text ← IO.FS.readFile path
      let (byLines, _) := selectLines text offset? limit?
      let (content, truncated) := truncateChars byLines maxToolOutputChars
      pure
        { toolCallId := call.id
          name := "read"
          ok := true
          content := content
          data := some (LeanAgent.Json.obj [("path", LeanAgent.Json.str path.toString), ("truncated", LeanAgent.Json.bool truncated)])
        }
  }

def makeWriteTool (root : System.FilePath) : AgentTool :=
  let schema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "object")
      , ("properties",
          LeanAgent.Json.obj
            [ ("path", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string"), ("description", LeanAgent.Json.str "File path to write")])
            , ("content", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string"), ("description", LeanAgent.Json.str "Full file content")])
            ])
      , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "path", LeanAgent.Json.str "content"])
      ]
  { name := "write"
    description := "Write full UTF-8 content to a file, creating parent directories."
    inputSchema := schema
    execute := fun call => do
      let rawPath ← requireArgString call.arguments "path"
      let content ← requireArgString call.arguments "content"
      let path ← resolveWritablePath root rawPath
      match path.parent with
      | some parent => IO.FS.createDirAll parent
      | none => pure ()
      IO.FS.writeFile path content
      pure
        { toolCallId := call.id
          name := "write"
          ok := true
          content := s!"wrote {content.length} characters to {path}"
          data := some (LeanAgent.Json.obj [("path", LeanAgent.Json.str path.toString), ("characters", LeanAgent.Json.nat content.length)])
        }
  }

def fileTypeSuffix : IO.FS.FileType → String
  | .dir => "/"
  | .symlink => "@"
  | .file => ""
  | .other => "*"

def renderDirEntry (entry : IO.FS.DirEntry) : IO String := do
  let metadata ← entry.path.symlinkMetadata
  pure (entry.fileName ++ fileTypeSuffix metadata.type)

def makeListTool (root : System.FilePath) : AgentTool :=
  let schema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "object")
      , ("properties",
          LeanAgent.Json.obj
            [ ("path", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string"), ("description", LeanAgent.Json.str "Directory path to list")])
            , ("limit", LeanAgent.Json.obj [("type", LeanAgent.Json.str "integer"), ("description", LeanAgent.Json.str "Maximum number of entries")])
            ])
      ]
  { name := "list"
    description := "List immediate directory entries relative to the working directory."
    inputSchema := schema
    execute := fun call => do
      let rawPath := (← optionalArgString call.arguments "path").getD "."
      let limit := (← optionalArgNat call.arguments "limit").getD maxListEntries
      let path ← resolveExistingDir root rawPath
      let entries ← path.readDir
      let rendered ← (entries.take limit).mapM renderDirEntry
      let truncated := entries.size > limit
      let suffix :=
        if truncated then
          s!"\n\n[truncated to {limit} entries]"
        else
          ""
      pure
        { toolCallId := call.id
          name := "list"
          ok := true
          content := String.intercalate "\n" rendered.toList ++ suffix
          data := some
            (LeanAgent.Json.obj
              [ ("path", LeanAgent.Json.str path.toString)
              , ("entries", LeanAgent.Json.nat rendered.size)
              , ("truncated", LeanAgent.Json.bool truncated)
              ])
        }
  }

def replaceAll (text old replacement : String) : String :=
  String.intercalate replacement (text.splitOn old)

def replaceFirst? (text old replacement : String) : Option String :=
  match text.splitOn old with
  | [] => some text
  | [_] => none
  | first :: rest => some (first ++ replacement ++ String.intercalate old rest)

def occurrenceCount (text needle : String) : Nat :=
  if needle.isEmpty then
    0
  else
    match text.splitOn needle with
    | [] => 0
    | parts => parts.length - 1

def makeEditTool (root : System.FilePath) : AgentTool :=
  let schema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "object")
      , ("properties",
          LeanAgent.Json.obj
            [ ("path", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string"), ("description", LeanAgent.Json.str "File path to edit")])
            , ("old", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string"), ("description", LeanAgent.Json.str "Text to replace")])
            , ("new", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string"), ("description", LeanAgent.Json.str "Replacement text")])
            , ("replace_all", LeanAgent.Json.obj [("type", LeanAgent.Json.str "boolean"), ("description", LeanAgent.Json.str "Replace every occurrence instead of only the first")])
            ])
      , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "path", LeanAgent.Json.str "old", LeanAgent.Json.str "new"])
      ]
  { name := "edit"
    description := "Replace text in an existing UTF-8 file."
    inputSchema := schema
    execute := fun call => do
      let rawPath ← requireArgString call.arguments "path"
      let old ← requireArgString call.arguments "old"
      let newText ← requireArgString call.arguments "new"
      let replaceAll? := (← optionalArgBool call.arguments "replace_all").getD false
      if old.isEmpty then
        throw (IO.userError "`old` must not be empty")
      let path ← resolveExistingFile root rawPath
      let text ← IO.FS.readFile path
      let matchCount := occurrenceCount text old
      if matchCount == 0 then
        throw (IO.userError "text to replace was not found")
      if !replaceAll? && matchCount > 1 then
        throw (IO.userError s!"text to replace is not unique ({matchCount} matches); set replace_all=true or provide more context")
      let updated? :=
        if replaceAll? then
          some (replaceAll text old newText)
        else
          replaceFirst? text old newText
      match updated? with
      | none => throw (IO.userError "text to replace was not found")
      | some updated =>
          let changed := updated != text
          if changed then
            IO.FS.writeFile path updated
          pure
            { toolCallId := call.id
              name := "edit"
              ok := true
              content :=
                if changed then
                  s!"edited {path} ({matchCount} match(es))"
                else
                  s!"unchanged {path} ({matchCount} match(es))"
              data := some
                (LeanAgent.Json.obj
                  [ ("path", LeanAgent.Json.str path.toString)
                  , ("replace_all", LeanAgent.Json.bool replaceAll?)
                  , ("matches", LeanAgent.Json.nat matchCount)
                  , ("changed", LeanAgent.Json.bool changed)
                  ])
            }
  }

def bashScript (command stdoutPath stderrPath : String) : String :=
  String.intercalate "\n"
    [ "exec > " ++ shellQuote stdoutPath ++ " 2> " ++ shellQuote stderrPath
    , command
    ]

def timeoutTicks (timeoutSeconds : Nat) : Nat :=
  timeoutSeconds * 10

def runBashWithTimeout
    (root : System.FilePath)
    (command : String)
    (timeoutSeconds : Nat) : IO (UInt32 × String × String × Bool) := do
  if timeoutSeconds == 0 then
    throw (IO.userError "timeout_seconds must be greater than zero")
  let tempDir ← IO.FS.createTempDir
  try
    let scriptPath := tempDir / "run.sh"
    let stdoutPath := tempDir / "stdout.txt"
    let stderrPath := tempDir / "stderr.txt"
    IO.FS.writeFile scriptPath (bashScript command stdoutPath.toString stderrPath.toString)
    let child ← IO.Process.spawn
      { cmd := "/bin/sh"
        args := #[scriptPath.toString]
        cwd := some root
        stdin := .null
        stdout := .null
        stderr := .null
        setsid := true
      }
    let rec waitLoop : Nat → IO (Option UInt32)
      | 0 => child.tryWait
      | remaining + 1 => do
          match ← child.tryWait with
          | some code => pure (some code)
          | none =>
              IO.sleep 100
              waitLoop remaining
    let result? ← waitLoop (timeoutTicks timeoutSeconds)
    let (exitCode, timedOut) ←
      match result? with
      | some code => pure (code, false)
      | none =>
          try
            child.kill
          catch _ =>
            pure ()
          let code ← child.wait
          pure (code, true)
    let stdout ← readFileIfExists stdoutPath
    let stderr ← readFileIfExists stderrPath
    let stderr :=
      if timedOut then
        let timeoutMessage := s!"[timed out after {timeoutSeconds}s]"
        if stderr.trimAscii.isEmpty then timeoutMessage else stderr ++ "\n" ++ timeoutMessage
      else
        stderr
    safeRemoveDirAll tempDir
    pure (exitCode, stdout, stderr, timedOut)
  catch err =>
    safeRemoveDirAll tempDir
    throw err

def makeBashTool (root : System.FilePath) : AgentTool :=
  let schema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "object")
      , ("properties",
          LeanAgent.Json.obj
            [ ("command", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string"), ("description", LeanAgent.Json.str "Shell command to run")])
            , ("timeout_seconds", LeanAgent.Json.obj [("type", LeanAgent.Json.str "integer"), ("description", LeanAgent.Json.str "Timeout in seconds")])
            ])
      , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "command"])
      ]
  { name := "bash"
    description := "Run a shell command in the working directory with a timeout and return stdout/stderr."
    inputSchema := schema
    execute := fun call => do
      let command ← requireArgString call.arguments "command"
      let timeoutSeconds := (← optionalArgNat call.arguments "timeout_seconds").getD defaultBashTimeoutSeconds
      let (exitCode, stdout, stderr, timedOut) ← runBashWithTimeout root command timeoutSeconds
      let combined :=
        if stderr.trimAscii.isEmpty then
          stdout
        else if stdout.trimAscii.isEmpty then
          stderr
        else
          stdout ++ "\n[stderr]\n" ++ stderr
      let (content, truncated) := truncateChars combined maxToolOutputChars
      let ok := exitCode == 0 && !timedOut
      pure
        { toolCallId := call.id
          name := "bash"
          ok := ok
          content := content
          data := some
            (LeanAgent.Json.obj
              [ ("exit_code", LeanAgent.Json.nat exitCode.toNat)
              , ("timeout_seconds", LeanAgent.Json.nat timeoutSeconds)
              , ("timed_out", LeanAgent.Json.bool timedOut)
              , ("truncated", LeanAgent.Json.bool truncated)
              ])
          error :=
            if ok then
              none
            else if timedOut then
              some s!"command timed out after {timeoutSeconds}s"
            else
              some s!"command exited with {exitCode}"
        }
  }

def defaultTools (root : System.FilePath) : Array AgentTool :=
  #[makeReadTool root, makeListTool root, makeWriteTool root, makeEditTool root, makeBashTool root]

def defaultAgentTools (root : System.FilePath) : Array LeanAgent.Agent.AgentTool :=
  let wrap (legacyTool : AgentTool) : LeanAgent.Agent.AgentTool :=
    { name := legacyTool.name
      description := legacyTool.description
      parameters := legacyTool.inputSchema
      label := legacyTool.name
      execute := fun toolCallId args signal updateCallback => do
        let call : ToolCall := { id := toolCallId, name := legacyTool.name, arguments := args }
        let result ← legacyTool.execute call
        let content : Array LeanAgent.AI.ContentBlock :=
          if result.content.isEmpty then
            #[]
          else
            #[.text { text := result.content }]
        let newResult : LeanAgent.Agent.AgentToolResult :=
          { content := content
            details := result.data
            terminate := false
          }
        match updateCallback with
        | some cb => cb newResult
        | none => pure ()
        pure newResult
    }
  defaultTools root |>.map wrap

end LeanAgent.CodingTools
