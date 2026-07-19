import Lean

namespace LeanAgent.Agent.Harness.Truncate

/-- Pi `DEFAULT_MAX_LINES`. -/
def defaultMaxLines : Nat := 2000

/-- Pi `DEFAULT_MAX_BYTES` (50KB). -/
def defaultMaxBytes : Nat := 50 * 1024

/-- Pi `GREP_MAX_LINE_LENGTH`. -/
def grepMaxLineLength : Nat := 500

inductive TruncatedBy where
  | lines
  | bytes
deriving BEq, Repr, Inhabited

structure TruncationResult where
  content : String
  truncated : Bool
  truncatedBy : Option TruncatedBy
  totalLines : Nat
  totalBytes : Nat
  outputLines : Nat
  outputBytes : Nat
  lastLinePartial : Bool := false
  firstLineExceedsLimit : Bool := false
  maxLines : Nat
  maxBytes : Nat
deriving Inhabited

structure TruncationOptions where
  maxLines : Nat := defaultMaxLines
  maxBytes : Nat := defaultMaxBytes
deriving Inhabited

/-- UTF-8 byte length (Pi `utf8ByteLength`). -/
def utf8ByteLength (content : String) : Nat :=
  content.utf8ByteSize

/-- Format bytes as human-readable size (Pi `formatSize`). -/
def formatSize (bytes : Nat) : String :=
  if bytes < 1024 then
    s!"{bytes}B"
  else if bytes < 1024 * 1024 then
    let kb := bytes / 1024
    let frac := ((bytes % 1024) * 10) / 1024
    s!"{kb}.{frac}KB"
  else
    let mb := bytes / (1024 * 1024)
    let frac := ((bytes % (1024 * 1024)) * 10) / (1024 * 1024)
    s!"{mb}.{frac}MB"

/-- Truncate text to at most `maxChars`, appending ellipsis when cut. -/
def truncate (text : String) (maxChars : Nat) : String :=
  if text.length ≤ maxChars then
    text
  else if maxChars == 0 then
    ""
  else if maxChars ≤ 3 then
    text.take maxChars |>.toString
  else
    (text.take (maxChars - 3)).toString ++ "..."

/--
Pi-style simple tail truncation by character budget (shell-output path),
prefixing a marker when cut. Distinct from multi-limit `truncateTail`.
-/
def truncateTailChars (text : String) (maxChars : Nat := defaultMaxBytes) : String × Bool :=
  if text.length ≤ maxChars then
    (text, false)
  else if maxChars == 0 then
    ("", true)
  else
    let marker := "\n...[truncated]...\n"
    if maxChars ≤ marker.length then
      ((text.take maxChars).toString, true)
    else
      let keep := maxChars - marker.length
      let tail := (text.drop (text.length - keep)).toString
      (marker ++ tail, true)

/-- Backward-compatible name used by shell capture. -/
def truncateTailSimple := truncateTailChars

/-- Multi-line shell output keeping head and tail lines. -/
def truncateShellOutput (text : String) (maxLines : Nat := 40) : String :=
  let lines := text.splitOn "\n"
  if lines.length ≤ maxLines then
    text
  else
    let headCount := maxLines / 2
    let tailCount := maxLines - headCount
    let head := lines.take headCount
    let tail := lines.drop (lines.length - tailCount)
    String.intercalate "\n" (head ++ ["..."] ++ tail)

/--
Pi `sanitizeBinaryOutput`: keep tab/LF/CR and printable codepoints;
drop other C0 controls and U+FFF9..U+FFFB.
-/
def sanitizeBinaryOutput (text : String) : String :=
  String.ofList <|
    text.toList.filter fun c =>
      let code := c.toNat
      code == 0x09 || code == 0x0a || code == 0x0d ||
        (code > 0x1f && !(code >= 0xfff9 && code <= 0xfffb))

/--
Truncate a single line to max characters, adding `... [truncated]` suffix
(Pi `truncateLine`).
-/
def truncateLine
    (line : String)
    (maxChars : Nat := grepMaxLineLength) : String × Bool :=
  if line.length ≤ maxChars then
    (line, false)
  else
    ((line.take maxChars).toString ++ "... [truncated]", true)

/-- Take the last `maxBytes` UTF-8 bytes of `str` (Pi subset; char-boundary safe via Lean String). -/
def truncateStringToBytesFromEnd (str : String) (maxBytes : Nat) : String :=
  if maxBytes == 0 then
    ""
  else if utf8ByteLength str ≤ maxBytes then
    str
  else
    -- Drop characters from the front until remaining fits.
    let rec go (s : String) (fuel : Nat) : String :=
      match fuel with
      | 0 => s
      | fuel + 1 =>
          if utf8ByteLength s ≤ maxBytes then
            s
          else if s.isEmpty then
            s
          else
            go (s.drop 1).toString fuel
    go str (str.length + 1)

/--
Pi `truncateHead`: keep first N lines/bytes; never return partial lines.
If the first line alone exceeds the byte limit, return empty content with
`firstLineExceedsLimit = true`.
-/
def truncateHead (content : String) (options : TruncationOptions := {}) : TruncationResult :=
  let maxLines := options.maxLines
  let maxBytes := options.maxBytes
  let totalBytes := utf8ByteLength content
  let lines := content.splitOn "\n"
  let totalLines := lines.length
  if totalLines ≤ maxLines && totalBytes ≤ maxBytes then
    { content := content
      truncated := false
      truncatedBy := none
      totalLines := totalLines
      totalBytes := totalBytes
      outputLines := totalLines
      outputBytes := totalBytes
      maxLines := maxLines
      maxBytes := maxBytes
    }
  else
    let firstLineBytes := utf8ByteLength (lines.headD "")
    if firstLineBytes > maxBytes then
      { content := ""
        truncated := true
        truncatedBy := some .bytes
        totalLines := totalLines
        totalBytes := totalBytes
        outputLines := 0
        outputBytes := 0
        firstLineExceedsLimit := true
        maxLines := maxLines
        maxBytes := maxBytes
      }
    else
      let rec collect
          (remaining : List String)
          (idx : Nat)
          (acc : List String)
          (byteCount : Nat)
          (truncatedBy : TruncatedBy) :
          List String × Nat × TruncatedBy :=
        match remaining with
        | [] => (acc.reverse, byteCount, truncatedBy)
        | line :: rest =>
            if idx ≥ maxLines then
              (acc.reverse, byteCount, .lines)
            else
              let lineBytes := utf8ByteLength line + (if acc.isEmpty then 0 else 1)
              if byteCount + lineBytes > maxBytes then
                (acc.reverse, byteCount, .bytes)
              else
                collect rest (idx + 1) (line :: acc) (byteCount + lineBytes) truncatedBy
      let (outLines, _, truncatedBy) := collect lines 0 [] 0 .lines
      let outputContent := String.intercalate "\n" outLines
      { content := outputContent
        truncated := true
        truncatedBy := some truncatedBy
        totalLines := totalLines
        totalBytes := totalBytes
        outputLines := outLines.length
        outputBytes := utf8ByteLength outputContent
        maxLines := maxLines
        maxBytes := maxBytes
      }

/--
Pi `truncateTail`: keep last N lines/bytes. May return a partial first line
when a single last line exceeds the byte limit.
-/
def truncateTail (content : String) (options : TruncationOptions := {}) : TruncationResult :=
  let maxLines := options.maxLines
  let maxBytes := options.maxBytes
  let totalBytes := utf8ByteLength content
  let rawLines := content.splitOn "\n"
  -- Drop trailing empty line from final newline (Pi behavior).
  let lines : List String :=
    match rawLines.reverse with
    | "" :: rest => rest.reverse
    | other => other.reverse
  let totalLines := lines.length
  if totalLines ≤ maxLines && totalBytes ≤ maxBytes then
    { content := content
      truncated := false
      truncatedBy := none
      totalLines := totalLines
      totalBytes := totalBytes
      outputLines := totalLines
      outputBytes := totalBytes
      maxLines := maxLines
      maxBytes := maxBytes
    }
  else
    -- Iterate lines from end to start.
    let rec collect
        (revRemaining : List String)
        (acc : List String)
        (byteCount : Nat)
        (truncatedBy : TruncatedBy)
        (lastPartial : Bool) :
        List String × TruncatedBy × Bool :=
      match revRemaining with
      | [] =>
          let tb :=
            if acc.length ≥ maxLines && byteCount ≤ maxBytes then TruncatedBy.lines
            else truncatedBy
          (acc, tb, lastPartial)
      | line :: rest =>
          if acc.length ≥ maxLines then
            (acc, .lines, lastPartial)
          else
            let lineBytes := utf8ByteLength line + (if acc.isEmpty then 0 else 1)
            if byteCount + lineBytes > maxBytes then
              if acc.isEmpty then
                let sliced := truncateStringToBytesFromEnd line maxBytes
                ([sliced], .bytes, true)
              else
                (acc, .bytes, lastPartial)
            else
              collect rest (line :: acc) (byteCount + lineBytes) truncatedBy lastPartial
    let (outLines, truncatedBy, lastPartial) :=
      collect lines.reverse [] 0 .lines false
    let outputContent := String.intercalate "\n" outLines
    { content := outputContent
      truncated := true
      truncatedBy := some truncatedBy
      totalLines := totalLines
      totalBytes := totalBytes
      outputLines := outLines.length
      outputBytes := utf8ByteLength outputContent
      lastLinePartial := lastPartial
      maxLines := maxLines
      maxBytes := maxBytes
    }

end LeanAgent.Agent.Harness.Truncate
