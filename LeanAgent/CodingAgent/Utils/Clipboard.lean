import Lean

/-!
# Clipboard helpers (Pi `utils/clipboard.ts`)

Platform clipboard write with fallback chain:

1. Native addon (Pi uses `@mariozechner/clipboard` — not portable to Lean,
   skipped; treated as unavailable, like `clipboard-native.ts`).
2. Platform tools: macOS `pbcopy`, Windows `clip`, Linux `xclip`/`xsel`/
   `wl-copy`/`termux-clipboard-set`.
3. OSC 52 escape sequence for remote sessions (SSH/MOSH).

The OSC 52 sequence is `\x1b]52;c;<base64>\x07`. The encoded payload must
not exceed `MAX_OSC52_ENCODED_LENGTH` (100 000 chars).

Pi's native clipboard addon (`clipboard-native.ts`) is a Node native
module (`@mariozechner/clipboard`) — not portable to Lean, treated as
unavailable. Wayland detection (`isWaylandSession` from `clipboard-image.ts`)
is inlined here as a one-liner env check. The platform-tool fallback
chain and OSC 52 sequence are fully ported.
-/

namespace LeanAgent.CodingAgent.Utils.Clipboard

open System

/-- Maximum encoded length for OSC 52 payload (Pi `MAX_OSC52_ENCODED_LENGTH`). -/
def MAX_OSC52_ENCODED_LENGTH : Nat := 100000

/-- Base64 alphabet (standard, with padding). -/
def b64Chars : Array Char :=
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toList.toArray

/-- Encode a `ByteArray` to a standard base64 string. -/
def base64Encode (bytes : ByteArray) : String := Id.run do
  let len := bytes.size
  let mut out : String := ""
  let mut i := 0
  while i < len do
    let b0 := bytes.get! i
    let b1 := if i + 1 < len then bytes.get! (i + 1) else 0
    let b2 := if i + 2 < len then bytes.get! (i + 2) else 0
    let n := (b0.toNat <<< 16) ||| (b1.toNat <<< 8) ||| b2.toNat
    let c0 := b64Chars[(n >>> 18) &&& 0x3]!
    let c1 := b64Chars[(n >>> 12) &&& 0x3F]!
    let c2 := b64Chars[(n >>> 6) &&& 0x3F]!
    let c3 := b64Chars[n &&& 0x3F]!
    out := out.push c0
    out := out.push c1
    if i + 1 < len then out := out.push c2 else out := out.push '='
    if i + 2 < len then out := out.push c3 else out := out.push '='
    i := i + 3
  pure out

/--
Pi `isRemoteSession` (from `clipboard.ts`): true when `SSH_CONNECTION`,
`SSH_CLIENT`, or `MOSH_CONNECTION` is set in the environment.
-/
def isRemoteSession : IO Bool := do
  let keys := #["SSH_CONNECTION", "SSH_CLIENT", "MOSH_CONNECTION"]
  let mut found := false
  for k in keys do
    if !found then
      match ← IO.getEnv k with
      | some v => if !v.isEmpty then found := true
      | none => pure ()
  pure found

/--
Pi `isWaylandSession` (from `clipboard-image.ts`): true when
`WAYLAND_DISPLAY` is set or `XDG_SESSION_TYPE` is `"wayland"`.
Inlined here because `clipboard-image.ts` is not ported (its core
functionality — clipboard image reading via platform tools + photon —
is Exclusion-adjacent).
-/
def isWaylandSession : IO Bool := do
  match ← IO.getEnv "WAYLAND_DISPLAY" with
  | some v => if !v.isEmpty then pure true else
    match ← IO.getEnv "XDG_SESSION_TYPE" with
    | some t => pure (t == "wayland")
    | none => pure false
  | none =>
    match ← IO.getEnv "XDG_SESSION_TYPE" with
    | some t => pure (t == "wayland")
    | none => pure false

/--
Pi `emitOsc52`: write the OSC 52 escape sequence to stdout to set the
terminal clipboard. Returns `false` if the encoded payload exceeds
`MAX_OSC52_ENCODED_LENGTH`.
-/
def emitOsc52 (text : String) : IO Bool := do
  let encoded := base64Encode text.toUTF8
  if encoded.length > MAX_OSC52_ENCODED_LENGTH then
    pure false
  else
    let esc := s!"\x1b]52;c;{encoded}\x07"
    IO.print esc
    pure true

/--
Run a command with `text` piped to stdin, swallowing errors.
Uses `takeStdin` to extract the stdin handle so it can be written and
then closed (by dropping the reference) before waiting for the child.
-/
private def pipeToCommand
    (command : String) (args : Array String) (text : String) : IO Bool := do
  try
    let child ← IO.Process.spawn
      { cmd := command, args := args
        stdin := .piped, stdout := .null, stderr := .null }
    let (stdin, child) ← child.takeStdin
    stdin.putStr text
    stdin.flush
    let _ ← child.wait
    pure true
  catch _ => pure false

/--
Pi `copyToClipboard`: copy `text` to the system clipboard.

Fallback chain (native addon skipped):
1. Platform tool: `pbcopy` (macOS), `clip` (Windows), or Linux tools
   (`wl-copy`, `xclip`, `xsel`, `termux-clipboard-set`).
2. OSC 52 escape sequence for remote sessions or as last resort.

Throws `IO.userError "Failed to copy to clipboard"` if all methods fail.
-/
def copyToClipboard (text : String) : IO Unit := do
  let mut copied := false

  -- Platform-specific native tool.
  if !copied then
    if Platform.isWindows then
      copied ← pipeToCommand "clip" #[] text
    else if Platform.isOSX then
      copied ← pipeToCommand "pbcopy" #[] text
    else
      -- Linux: try Termux, Wayland, then X11.
      match ← IO.getEnv "TERMUX_VERSION" with
      | some _ =>
        if !copied then
          copied ← pipeToCommand "termux-clipboard-set" #[] text
      | none => pure ()
      let wayland ← isWaylandSession
      match ← IO.getEnv "WAYLAND_DISPLAY" with
      | some _ =>
        if !copied && wayland then
          copied ← pipeToCommand "wl-copy" #[] text
      | none => pure ()
      match ← IO.getEnv "DISPLAY" with
      | some _ =>
        if !copied then
          copied ← pipeToCommand "xclip" #["-selection", "clipboard"] text
        if !copied then
          copied ← pipeToCommand "xsel" #["--clipboard", "--input"] text
      | none => pure ()

  -- OSC 52 fallback for remote sessions or when native tools fail.
  let remote ← isRemoteSession
  if remote || !copied then
    let oscOk ← emitOsc52 text
    copied := copied || oscOk

  if !copied then
    throw <| IO.userError "Failed to copy to clipboard"

end LeanAgent.CodingAgent.Utils.Clipboard