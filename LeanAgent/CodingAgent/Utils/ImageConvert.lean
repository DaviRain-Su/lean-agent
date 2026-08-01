import Lean
import LeanAgent.CodingAgent.Utils.Photon

/-!
# Image conversion (Pi `utils/image-convert.ts`)

Convert image bytes to PNG using Photon (Rust/WASM). Since Photon is not
available in Lean (`Utils.Photon.loadPhoton` always returns `none`), the
conversion functions return `none` — documented as Exclusion-adjacent
(photon WASM dependency, Exclusion List §7).

`convertToPng` still has its pure fast path: if the input is already PNG,
it returns the data unchanged without needing Photon.
-/

namespace LeanAgent.CodingAgent.Utils.ImageConvert

/-- Result of a successful PNG conversion: base64 data + MIME type. -/
structure ConvertResult where
  data : String
  mimeType : String
deriving Inhabited, Repr

-- ===========================================================================
-- Base64 helpers (local copies — no shared base64 module in LeanAgent)
-- ===========================================================================

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

/-- Value of a single base64 character, or `none`. -/
def b64Val? (c : Char) : Option Nat :=
  match c with
  | 'A' => some 0  | 'B' => some 1  | 'C' => some 2  | 'D' => some 3
  | 'E' => some 4  | 'F' => some 5  | 'G' => some 6  | 'H' => some 7
  | 'I' => some 8  | 'J' => some 9  | 'K' => some 10 | 'L' => some 11
  | 'M' => some 12 | 'N' => some 13 | 'O' => some 14 | 'P' => some 15
  | 'Q' => some 16 | 'R' => some 17 | 'S' => some 18 | 'T' => some 19
  | 'U' => some 20 | 'V' => some 21 | 'W' => some 22 | 'X' => some 23
  | 'Y' => some 24 | 'Z' => some 25
  | 'a' => some 26 | 'b' => some 27 | 'c' => some 28 | 'd' => some 29
  | 'e' => some 30 | 'f' => some 31 | 'g' => some 32 | 'h' => some 33
  | 'i' => some 34 | 'j' => some 35 | 'k' => some 36 | 'l' => some 37
  | 'm' => some 38 | 'n' => some 39 | 'o' => some 40 | 'p' => some 41
  | 'q' => some 42 | 'r' => some 43 | 's' => some 44 | 't' => some 45
  | 'u' => some 46 | 'v' => some 47 | 'w' => some 48 | 'x' => some 49
  | 'y' => some 50 | 'z' => some 51
  | '0' => some 52 | '1' => some 53 | '2' => some 54 | '3' => some 55
  | '4' => some 56 | '5' => some 57 | '6' => some 58 | '7' => some 59
  | '8' => some 60 | '9' => some 61
  | '+' => some 62 | '/' => some 63
  | _ => none

/-- Decode a standard base64 string to `ByteArray`. Returns `none` on invalid input. -/
def base64Decode (s : String) : Option ByteArray := Id.run do
  let chars := s.toList.filter (fun c => c != '=' && c != '\n' && c != '\r')
  let mut vals : Array Nat := #[]
  let mut ok := true
  for c in chars do
    if !ok then break
    match b64Val? c with
    | some v => vals := vals.push v
    | none => ok := false
  if !ok then none
  else
    let mut out : ByteArray := ByteArray.mk #[]
    let mut i := 0
    let mut valid := true
    while i + 3 < vals.size do
      let n := vals[i]! * (1 <<< 18) + vals[i+1]! * (1 <<< 12) + vals[i+2]! * (1 <<< 6) + vals[i+3]!
      out := out.push ((n >>> 16) &&& 0xFF).toUInt8
      out := out.push ((n >>> 8) &&& 0xFF).toUInt8
      out := out.push (n &&& 0xFF).toUInt8
      i := i + 4
    let rem := vals.size - i
    if rem == 2 then
      let n := vals[i]! * (1 <<< 18) + vals[i+1]! * (1 <<< 12)
      out := out.push ((n >>> 16) &&& 0xFF).toUInt8
    else if rem == 3 then
      let n := vals[i]! * (1 <<< 18) + vals[i+1]! * (1 <<< 12) + vals[i+2]! * (1 <<< 6)
      out := out.push ((n >>> 16) &&& 0xFF).toUInt8
      out := out.push ((n >>> 8) &&& 0xFF).toUInt8
    else if rem == 1 then
      valid := false
    if !valid then none else some out

-- ===========================================================================
-- Conversion functions
-- ===========================================================================

/--
Pi `convertImageBytesToPng`: convert raw image bytes to PNG.

Returns `none` because Photon (`@silvia-odwyer/photon-node`) is a Rust/WASM
module not available in Lean. The function signature and call site are
preserved so callers compile without conditional imports.
-/
def convertImageBytesToPng (bytes : ByteArray) : IO (Option ByteArray) := do
  let _ ← Photon.loadPhoton
  -- Photon WASM is not available in Lean — cannot convert.
  pure none

/--
Pi `convertToPng`: convert a base64-encoded image to PNG if needed.

If the MIME type is already `image/png`, returns the data unchanged
(pure fast path, no Photon needed). Otherwise, decodes the base64, calls
`convertImageBytesToPng`, and re-encodes. Returns `none` when conversion
is unavailable (Photon not loaded).
-/
def convertToPng (base64Data : String) (mimeType : String) : IO (Option ConvertResult) := do
  if mimeType == "image/png" then
    pure (some { data := base64Data, mimeType := "image/png" })
  else
    match base64Decode base64Data with
    | none => pure none
    | some bytes =>
      match ← convertImageBytesToPng bytes with
      | none => pure none
      | some pngBytes =>
        pure (some { data := base64Encode pngBytes, mimeType := "image/png" })

end LeanAgent.CodingAgent.Utils.ImageConvert