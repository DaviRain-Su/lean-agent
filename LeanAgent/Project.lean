import LeanAgent.Prompt

namespace LeanAgent.Project

structure FileCommand where
  name : String
  description : String
  body : String
  path : System.FilePath
  source : String

structure Skill where
  name : String
  description : String
  body : String
  path : System.FilePath
  source : String

structure ProjectExtensions where
  commands : Array FileCommand := #[]
  skills : Array Skill := #[]

def trim (value : String) : String :=
  value.trimAscii.toString

def stripMatchingQuotes (value : String) : String :=
  let value := trim value
  if value.length >= 2 && value.startsWith "\"" && value.endsWith "\"" then
    (value.drop 1 |>.dropEnd 1).toString
  else if value.length >= 2 && value.startsWith "'" && value.endsWith "'" then
    (value.drop 1 |>.dropEnd 1).toString
  else
    value

def frontmatter? (content : String) : Option (List String × String) :=
  match content.splitOn "\n" with
  | first :: rest =>
      if trim first != "---" then
        none
      else
        let rec loop (acc : List String) : List String → Option (List String × String)
          | [] => none
          | line :: tail =>
              if trim line == "---" then
                some (acc.reverse, String.intercalate "\n" tail)
              else
                loop (line :: acc) tail
        loop [] rest
  | [] => none

def frontmatterValue? (lines : List String) (key : String) : Option String :=
  let keyPrefix := key ++ ":"
  let rec loop : List String → Option String
    | [] => none
    | line :: rest =>
        let line := trim line
        if line.startsWith keyPrefix then
          some (stripMatchingQuotes (line.drop keyPrefix.length).toString)
        else
          loop rest
  loop lines

def stripFrontmatter (content : String) : String :=
  match frontmatter? content with
  | some (_, body) => body
  | none => content

def parsedName? (content : String) : Option String :=
  match frontmatter? content with
  | some (metadata, _) =>
      match frontmatterValue? metadata "name" with
      | some value => if value.isEmpty then none else some value
      | none => none
  | none => none

def firstMeaningfulLine (body : String) : String :=
  let rec loop : List String → String
    | [] => ""
    | line :: rest =>
        let line := trim line
        if line.isEmpty || line.startsWith "#" then
          loop rest
        else
          line
  loop (body.splitOn "\n")

def descriptionFromMarkdown (content : String) : String :=
  let body := stripFrontmatter content
  let fallback := firstMeaningfulLine body
  match frontmatter? content with
  | some (metadata, _) =>
      match frontmatterValue? metadata "description" with
      | some value => if value.isEmpty then fallback else value
      | none => fallback
  | none => fallback

def fileStem (path : System.FilePath) : String :=
  path.fileStem.getD (path.fileName.getD path.toString)

def commandNameFromPath (path : System.FilePath) (content : String) : String :=
  match parsedName? content with
  | some name => name
  | none => fileStem path

def skillNameFromPath (path : System.FilePath) (content : String) : String :=
  match parsedName? content with
  | some name => name
  | none =>
      match path.parent with
      | some parent => fileStem parent
      | none => fileStem path

def homeDir? : IO (Option System.FilePath) := do
  match ← IO.getEnv "HOME" with
  | some value =>
      let value := trim value
      pure (if value.isEmpty then none else some (System.FilePath.mk value))
  | none => pure none

def commandRoots (cwd : System.FilePath) : IO (Array (System.FilePath × String)) := do
  let roots := #[(cwd / ".omp" / "commands", "project")]
  match ← homeDir? with
  | some home => pure (roots.push (home / ".omp" / "agent" / "commands", "user"))
  | none => pure roots

def skillRoots (cwd : System.FilePath) : IO (Array (System.FilePath × String)) := do
  let roots := #[(cwd / ".omp" / "skills", "project")]
  match ← homeDir? with
  | some home => pure (roots.push (home / ".omp" / "agent" / "skills", "user"))
  | none => pure roots

def readDirIfExists (path : System.FilePath) : IO (Array IO.FS.DirEntry) := do
  if ← path.pathExists then
    if ← path.isDir then
      path.readDir
    else
      pure #[]
  else
    pure #[]

def isMarkdownFile (entry : IO.FS.DirEntry) : IO Bool := do
  let isDir ← entry.path.isDir
  pure (!isDir && entry.path.extension == some "md")

def loadCommandsFromRoot (root : System.FilePath) (source : String) : IO (Array FileCommand) := do
  let entries ← readDirIfExists root
  let mut commands := #[]
  for entry in entries do
    if ← isMarkdownFile entry then
      let content ← IO.FS.readFile entry.path
      let body := stripFrontmatter content
      commands := commands.push
        { name := commandNameFromPath entry.path content
          description := descriptionFromMarkdown content
          body := body
          path := entry.path
          source := source
        }
  pure commands

def loadSkillFromDir? (entry : IO.FS.DirEntry) (source : String) : IO (Option Skill) := do
  if !(← entry.path.isDir) then
    pure none
  else
    let skillPath := entry.path / "SKILL.md"
    if !(← skillPath.pathExists) then
      pure none
    else
      let content ← IO.FS.readFile skillPath
      let body := stripFrontmatter content
      pure (some
        { name := skillNameFromPath skillPath content
          description := descriptionFromMarkdown content
          body := body
          path := skillPath
          source := source
        })

def loadSkillsFromRoot (root : System.FilePath) (source : String) : IO (Array Skill) := do
  let entries ← readDirIfExists root
  let mut skills := #[]
  for entry in entries do
    match ← loadSkillFromDir? entry source with
    | some skill => skills := skills.push skill
    | none => pure ()
  pure skills

def dedupeByName {α : Type} (items : Array α) (nameOf : α → String) : Array α :=
  let rec loop (index : Nat) (seen : List String) (out : Array α) :=
    if h : index < items.size then
      let item := items[index]
      let name := nameOf item
      if seen.contains name then
        loop (index + 1) seen out
      else
        loop (index + 1) (name :: seen) (out.push item)
    else
      out
  loop 0 [] #[]

def loadExtensions (cwd : System.FilePath) : IO ProjectExtensions := do
  let mut commands := #[]
  for (root, source) in (← commandRoots cwd) do
    commands := commands ++ (← loadCommandsFromRoot root source)
  let mut skills := #[]
  for (root, source) in (← skillRoots cwd) do
    skills := skills ++ (← loadSkillsFromRoot root source)
  pure
    { commands := dedupeByName commands (fun command => command.name)
      skills := dedupeByName skills (fun skill => skill.name)
    }

def findCommand? (extensions : ProjectExtensions) (name : String) : Option FileCommand :=
  extensions.commands.find? (fun command => command.name == name)

def findSkill? (extensions : ProjectExtensions) (name : String) : Option Skill :=
  extensions.skills.find? (fun skill => skill.name == name)

def parseCommandArgs (raw : String) : Array String :=
  let chars := raw.toList
  let rec finishToken (token : List Char) (out : Array String) : Array String :=
    match token with
    | [] => out
    | _ => out.push (String.ofList token.reverse)
  let rec loop (chars : List Char) (quote? : Option Char) (token : List Char) (out : Array String) :
      Array String :=
    match chars with
    | [] => finishToken token out
    | c :: rest =>
        match quote? with
        | some quote =>
            if c == quote then
              loop rest none token out
            else
              loop rest quote? (c :: token) out
        | none =>
            if c == '"' || c == '\'' then
              loop rest (some c) token out
            else if c == ' ' || c == '\t' || c == '\n' || c == '\r' then
              loop rest none [] (finishToken token out)
            else
              loop rest none (c :: token) out
  loop chars none [] #[]

def joinArgsFrom (args : Array String) (start : Nat) (len? : Option Nat) : String :=
  let startIndex := start - 1
  let available :=
    if startIndex >= args.size then
      #[]
    else
      args.extract startIndex args.size
  let selected :=
    match len? with
    | some len => available.extract 0 (Nat.min len available.size)
    | none => available
  String.intercalate " " selected.toList

partial def replaceSlicePlaceholders (template : String) (args : Array String) : String :=
  let marker := "$@["
  match template.splitOn marker with
  | [] => template
  | first :: rest =>
      let renderedRest :=
        rest.map fun segment =>
          match segment.splitOn "]" with
          | inside :: after =>
              let replacement :=
                match inside.splitOn ":" with
                | [start] =>
                    match start.toNat? with
                    | some n => joinArgsFrom args n none
                    | none => marker ++ inside ++ "]"
                | [start, len] =>
                    match start.toNat?, len.toNat? with
                    | some s, some l => joinArgsFrom args s (some l)
                    | _, _ => marker ++ inside ++ "]"
                | _ => marker ++ inside ++ "]"
              replacement ++ String.intercalate "]" after
          | [] => marker ++ segment
      first ++ String.intercalate marker renderedRest

def replacePositionalPlaceholders (template : String) (args : Array String) : String :=
  let rec loop (index : Nat) (text : String) :=
    if index < args.size then
      loop (index + 1) (text.replace ("$" ++ toString (index + 1)) (args[index]!))
    else
      text
  loop 0 template

def templateUsesInlineArgs (template : String) : Bool :=
  template.contains "$ARGUMENTS" || template.contains "$@" || template.contains "$1" || template.contains "$@["

def renderCommandTemplate (command : FileCommand) (args : Array String) (rawArgs : String) : String :=
  let body := command.body
  let withSlices := replaceSlicePlaceholders body args
  let withAggregate := withSlices.replace "$ARGUMENTS" rawArgs |>.replace "$@" rawArgs
  let rendered := replacePositionalPlaceholders withAggregate args
  if rawArgs.isEmpty || templateUsesInlineArgs body then
    rendered
  else
    rendered ++ "\n\nArguments: " ++ rawArgs

def parseSlashInput (input : String) : Option (String × String × Array String) :=
  let input := trim input
  if !input.startsWith "/" || input.startsWith "/skill:" then
    none
  else
    let withoutSlash := (input.drop 1).toString
    let parts := withoutSlash.splitOn " "
    match parts with
    | [] => none
    | name :: rest =>
        let rawArgs := trim (String.intercalate " " rest)
        if name.isEmpty then none else some (name, rawArgs, parseCommandArgs rawArgs)

def expandSlashCommand? (extensions : ProjectExtensions) (input : String) : Option String :=
  match parseSlashInput input with
  | some (name, rawArgs, args) =>
      match findCommand? extensions name with
      | some command => some (renderCommandTemplate command args rawArgs)
      | none => none
  | none => none

def parseSkillInput (input : String) : Option (String × String) :=
  let input := trim input
  if !input.startsWith "/skill:" then
    none
  else
    let withoutPrefix := (input.drop "/skill:".length).toString
    let parts := withoutPrefix.splitOn " "
    match parts with
    | [] => none
    | name :: rest =>
        let task := trim (String.intercalate " " rest)
        if name.isEmpty then none else some (name, task)

def renderSkillPrompt (skill : Skill) (task : String) : String :=
  String.intercalate "\n"
    [ "Use this skill for the task."
    , ""
    , "# Skill: " ++ skill.name
    , ""
    , skill.body
    , ""
    , "# Task"
    , if task.isEmpty then "Apply the skill to the current request." else task
    ]

def expandSkill? (extensions : ProjectExtensions) (input : String) : Option String :=
  match parseSkillInput input with
  | some (name, task) =>
      match findSkill? extensions name with
      | some skill => some (renderSkillPrompt skill task)
      | none => none
  | none => none

def expandPrompt (extensions : ProjectExtensions) (input : String) : String :=
  match expandSkill? extensions input with
  | some expanded => expanded
  | none =>
      match expandSlashCommand? extensions input with
      | some expanded => expanded
      | none => input

def renderCommandList (extensions : ProjectExtensions) : String :=
  if extensions.commands.isEmpty then
    "No .omp commands found."
  else
    String.intercalate "\n"
      (extensions.commands.toList.map fun command =>
        "/" ++ command.name ++
          (if command.description.isEmpty then "" else " - " ++ command.description) ++
          " [" ++ command.source ++ "]")

def renderSkillList (extensions : ProjectExtensions) : String :=
  if extensions.skills.isEmpty then
    "No .omp skills found."
  else
    String.intercalate "\n"
      (extensions.skills.toList.map fun skill =>
        "/skill:" ++ skill.name ++
          (if skill.description.isEmpty then "" else " - " ++ skill.description) ++
          " [" ++ skill.source ++ "]")

def renderSystemAppendix (extensions : ProjectExtensions) : String :=
  let commandText :=
    if extensions.commands.isEmpty then
      ""
    else
      "File slash commands available to the user:\n" ++ renderCommandList extensions
  let skillText :=
    if extensions.skills.isEmpty then
      ""
    else
      "Skills available through /skill:<name>:\n" ++ renderSkillList extensions
  String.intercalate "\n\n" (List.filter (fun s => !s.isEmpty) [commandText, skillText])

def applySystemAppendix (system : String) (extensions : ProjectExtensions) : String :=
  let appendix := renderSystemAppendix extensions
  if appendix.isEmpty then
    system
  else
    system ++ "\n\n" ++ appendix

end LeanAgent.Project
