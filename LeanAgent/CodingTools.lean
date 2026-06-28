import Lean
import LeanAgent.Core
import LeanAgent.Json

namespace LeanAgent.CodingTools

open LeanAgent

def maxReadLines : Nat := 2000
def maxToolOutputChars : Nat := 50000

def resolvePath (root : System.FilePath) (raw : String) : System.FilePath :=
  let path := System.FilePath.mk raw
  if path.isAbsolute then path.normalize else (root / path).normalize

def requireArgString (args : Lean.Json) (key : String) : IO String :=
  match LeanAgent.Json.requiredString args key with
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
      let path := resolvePath root rawPath
      let pathExists ← path.pathExists
      if !pathExists then
        throw (IO.userError s!"file not found: {path}")
      let isDir ← path.isDir
      if isDir then
        throw (IO.userError s!"path is a directory: {path}")
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
      let path := resolvePath root rawPath
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

def replaceAll (text old replacement : String) : String :=
  String.intercalate replacement (text.splitOn old)

def replaceFirst? (text old replacement : String) : Option String :=
  match text.splitOn old with
  | [] => some text
  | [_] => none
  | first :: rest => some (first ++ replacement ++ String.intercalate old rest)

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
      let path := resolvePath root rawPath
      let text ← IO.FS.readFile path
      let updated? :=
        if replaceAll? then
          if text.contains old then some (replaceAll text old newText) else none
        else
          replaceFirst? text old newText
      match updated? with
      | none => throw (IO.userError "text to replace was not found")
      | some updated =>
          IO.FS.writeFile path updated
          pure
            { toolCallId := call.id
              name := "edit"
              ok := true
              content := s!"edited {path}"
              data := some (LeanAgent.Json.obj [("path", LeanAgent.Json.str path.toString), ("replace_all", LeanAgent.Json.bool replaceAll?)])
            }
  }

def makeBashTool (root : System.FilePath) : AgentTool :=
  let schema :=
    LeanAgent.Json.obj
      [ ("type", LeanAgent.Json.str "object")
      , ("properties",
          LeanAgent.Json.obj
            [ ("command", LeanAgent.Json.obj [("type", LeanAgent.Json.str "string"), ("description", LeanAgent.Json.str "Shell command to run")])
            ])
      , ("required", LeanAgent.Json.arr #[LeanAgent.Json.str "command"])
      ]
  { name := "bash"
    description := "Run a shell command in the working directory and return stdout/stderr."
    inputSchema := schema
    execute := fun call => do
      let command ← requireArgString call.arguments "command"
      let output ← IO.Process.output
        { cmd := "/bin/sh"
          args := #["-lc", command]
          cwd := some root
        }
      let combined :=
        if output.stderr.trimAscii.isEmpty then
          output.stdout
        else if output.stdout.trimAscii.isEmpty then
          output.stderr
        else
          output.stdout ++ "\n[stderr]\n" ++ output.stderr
      let (content, truncated) := truncateChars combined maxToolOutputChars
      let ok := output.exitCode == 0
      pure
        { toolCallId := call.id
          name := "bash"
          ok := ok
          content := content
          data := some
            (LeanAgent.Json.obj
              [ ("exit_code", LeanAgent.Json.nat output.exitCode.toNat)
              , ("truncated", LeanAgent.Json.bool truncated)
              ])
          error := if ok then none else some s!"command exited with {output.exitCode}"
        }
  }

def defaultTools (root : System.FilePath) : Array AgentTool :=
  #[makeReadTool root, makeWriteTool root, makeEditTool root, makeBashTool root]

end LeanAgent.CodingTools
