import Lean
import LeanAgent.CodingAgent.Utils.Photon
import LeanAgent.CodingAgent.Utils.ImageConvert
import LeanAgent.CodingAgent.Utils.Mime

/-!
# Image processing (Pi `utils/image-process.ts`)

Process an image for inline provider display: normalize the MIME type,
convert unsupported formats to PNG, and optionally resize.

Since Photon is not available in Lean (`Utils.Photon.loadPhoton` returns
`none`), the conversion and resize paths return `none`. The MIME-type
normalization logic is fully ported (pure, offline-testable).

`getImageDimensions` is a **Lean-side addition** — it does not exist in
Pi's `image-process.ts`. Pi gets dimensions via `photon.get_width()` /
`photon.get_height()`. Since we cannot load Photon, we parse dimensions
from binary headers (PNG IHDR, JPEG SOF0/SOF2, GIF logical-screen-descriptor,
WebP VP8/VP8L/VP8X). This complements `Utils.Mime` magic-byte detection.
-/

namespace LeanAgent.CodingAgent.Utils.ImageProcess

/-- Pi `ProcessImageOptions`. -/
structure ProcessImageOptions where
  autoResizeImages : Bool := true
deriving Inhabited, Repr

/-- Pi `ProcessImageResult` — success variant. -/
structure ProcessImageOk where
  data : String
  mimeType : String
  hints : Array String
deriving Inhabited, Repr

/-- Pi `ProcessImageResult` — failure variant. -/
structure ProcessImageErr where
  message : String
deriving Inhabited, Repr

/-- Pi `ProcessImageResult` (discriminated union). -/
inductive ProcessImageResult where
  | ok : ProcessImageOk → ProcessImageResult
  | error : ProcessImageErr → ProcessImageResult
deriving Inhabited, Repr

/-- Pi `NormalizedImage`. -/
structure NormalizedImage where
  bytes : ByteArray
  mimeType : String
  convertedFrom : Option String := none
deriving Inhabited

/-- Pi `baseMimeType`: strip parameters, trim, lowercase. -/
def baseMimeType (mimeType : String) : String :=
  match mimeType.splitOn ";" with
  | first :: _ => first.trimAscii.toString.toLower
  | [] => mimeType.toLower

/-- Pi `normalizeSupportedImageMimeType`: map known MIME types. -/
def normalizeSupportedImageMimeType (mimeType : String) : Option String :=
  match baseMimeType mimeType with
  | "image/png" => some "image/png"
  | "image/jpeg" => some "image/jpeg"
  | "image/jpg" => some "image/jpeg"
  | "image/gif" => some "image/gif"
  | "image/webp" => some "image/webp"
  | _ => none

/--
Pi `normalizeImage`: normalize the MIME type, converting to PNG if needed.
Returns `none` when the format is unsupported and conversion fails
(Photon unavailable).
-/
def normalizeImage (bytes : ByteArray) (mimeType : String) : IO (Option NormalizedImage) := do
  match normalizeSupportedImageMimeType mimeType with
  | some normalized => pure (some { bytes := bytes, mimeType := normalized })
  | none =>
    match ← ImageConvert.convertImageBytesToPng bytes with
    | none => pure none
    | some pngBytes =>
      pure (some { bytes := pngBytes, mimeType := "image/png"
                   convertedFrom := some (baseMimeType mimeType) })

/-- Pi `conversionHint`: format a conversion note. -/
def conversionHint (fromMime : Option String) (toMime : String) : Option String :=
  match fromMime with
  | none => none
  | some f => if f == toMime then none else some s!"[Image converted from {f} to {toMime}.]"

/--
Pi `processImage`: normalize, optionally resize, and return base64 data.

Since Photon is unavailable, resize and conversion paths return an error
result. When the MIME type is already supported and `autoResizeImages` is
`false`, the image is returned as-is (pure path, no Photon needed).
-/
def processImage
    (bytes : ByteArray) (mimeType : String)
    (options : ProcessImageOptions := {}) : IO ProcessImageResult := do
  match ← normalizeImage bytes mimeType with
  | none =>
    pure (ProcessImageResult.error
      { message := "[Image omitted: could not be converted to a supported inline image format.]" })
  | some normalized =>
    if !options.autoResizeImages then
      let hints := match conversionHint normalized.convertedFrom normalized.mimeType with
        | some h => #[h]
        | none => #[]
      let data := ImageConvert.base64Encode normalized.bytes
      pure (ProcessImageResult.ok { data := data, mimeType := normalized.mimeType, hints := hints })
    else
      -- Resize requires Photon — not available.
      pure (ProcessImageResult.error
        { message := "[Image omitted: could not be resized below the inline image size limit.]" })

-- ===========================================================================
-- getImageDimensions — Lean-side addition (not in Pi's image-process.ts)
-- ===========================================================================

/-- Image dimensions (width x height in pixels). -/
structure ImageDimensions where
  width : Nat
  height : Nat
deriving Inhabited, BEq, Repr

/-- Read a big-endian 16-bit value from a byte array at the given offset. -/
def readBE16 (buf : ByteArray) (offset : Nat) : Nat :=
  if offset + 1 < buf.size then
    (buf.get! offset).toNat * 256 + (buf.get! (offset + 1)).toNat
  else
    0

/-- Read a little-endian 16-bit value from a byte array at the given offset. -/
def readLE16 (buf : ByteArray) (offset : Nat) : Nat :=
  if offset + 1 < buf.size then
    (buf.get! offset).toNat + (buf.get! (offset + 1)).toNat * 256
  else
    0

/-- Read a big-endian 32-bit value from a byte array at the given offset. -/
def readBE32 (buf : ByteArray) (offset : Nat) : Nat :=
  if offset + 3 < buf.size then
    ((buf.get! offset).toNat <<< 24) ||| ((buf.get! (offset + 1)).toNat <<< 16)
      ||| ((buf.get! (offset + 2)).toNat <<< 8) ||| (buf.get! (offset + 3)).toNat
  else
    0

/-- Scan JPEG markers for SOF0 (0xFFC0) or SOF2 (0xFFC2) to extract dimensions. -/
partial def scanJpegSof (buf : ByteArray) (i : Nat) : Option ImageDimensions :=
  if i + 1 ≥ buf.size then none
  else if buf.get! i == 0xFF && (buf.get! (i + 1) == 0xC0 || buf.get! (i + 1) == 0xC2) then
    -- SOF0 or SOF2: skip 2-byte marker + 2-byte length + 1-byte precision,
    -- then height (BE16), width (BE16).
    let base := i + 5
    if base + 3 ≥ buf.size then none
    else
      let h := readBE16 buf base
      let w := readBE16 buf (base + 2)
      some { width := w, height := h }
  else if buf.get! i == 0xFF && i + 3 < buf.size then
    let marker := buf.get! (i + 1)
    if marker == 0xD8 || marker == 0xD9 then
      -- SOI/EOI: no payload, advance 2 bytes.
      scanJpegSof buf (i + 2)
    else
      -- Other marker: read 2-byte length and skip.
      let len := readBE16 buf (i + 2)
      scanJpegSof buf (i + 2 + len)
  else
    scanJpegSof buf (i + 1)

/-- Parse WebP dimensions from VP8 / VP8L / VP8X chunk headers. -/
def parseWebPDimensions (buf : ByteArray) : Option ImageDimensions :=
  if buf.size < 16 then none
  else
    let c0 := (buf.get! 12).toNat
    let c1 := (buf.get! 13).toNat
    let c2 := (buf.get! 14).toNat
    let c3 := (buf.get! 15).toNat
    if c0 == 0x56 && c1 == 0x50 && c2 == 0x38 && c3 == 0x20 then
      -- "VP8 " (lossy): width/height LE16 at offset 26/28, masked 0x3FFF.
      if buf.size < 30 then none
      else
        let w := readLE16 buf 26 &&& 0x3FFF
        let h := readLE16 buf 28 &&& 0x3FFF
        some { width := w, height := h }
    else if c0 == 0x56 && c1 == 0x50 && c2 == 0x38 && c3 == 0x4C then
      -- "VP8L" (lossless): 1-byte sig, then 14-bit width-1 + 14-bit height-1.
      if buf.size < 25 then none
      else
        let b0 := (buf.get! 21).toNat
        let b1 := (buf.get! 22).toNat
        let b2 := (buf.get! 23).toNat
        let b3 := (buf.get! 24).toNat
        let w := (b0 ||| ((b1 &&& 0x3F) <<< 8)) + 1
        let h := (((b1 >>> 6) ||| (b2 <<< 2) ||| ((b3 &&& 0x0F) <<< 10)) &&& 0x3FFF) + 1
        some { width := w, height := h }
    else if c0 == 0x56 && c1 == 0x50 && c2 == 0x38 && c3 == 0x58 then
      -- "VP8X" (extended): canvas width-1 (24-bit LE) at 24, height-1 at 27.
      if buf.size < 30 then none
      else
        let w := ((buf.get! 24).toNat ||| ((buf.get! 25).toNat <<< 8) ||| ((buf.get! 26).toNat <<< 16)) + 1
        let h := ((buf.get! 27).toNat ||| ((buf.get! 28).toNat <<< 8) ||| ((buf.get! 29).toNat <<< 16)) + 1
        some { width := w, height := h }
    else
      none

/--
Parse image dimensions from binary headers (PNG IHDR, JPEG SOF0/SOF2,
GIF logical-screen-descriptor, WebP VP8/VP8L/VP8X).

This is a **Lean-side addition** — Pi's `image-process.ts` does not have
this function. Pi relies on `photon.get_width()` / `photon.get_height()`.
Since Photon is unavailable, we parse headers directly. Returns `none`
for unrecognized formats or truncated headers.
-/
def getImageDimensions (buf : ByteArray) : Option ImageDimensions :=
  match Mime.detectSupportedImageMimeType buf with
  | some "image/png" =>
    -- PNG IHDR: width (BE32) at offset 16, height (BE32) at offset 20.
    if buf.size < 24 then none
    else
      let w := readBE32 buf 16
      let h := readBE32 buf 20
      some { width := w, height := h }
  | some "image/gif" =>
    -- GIF: width (LE16) at offset 6, height (LE16) at offset 8.
    if buf.size < 10 then none
    else some { width := readLE16 buf 6, height := readLE16 buf 8 }
  | some "image/jpeg" =>
    -- JPEG: scan for SOF0 (0xFF 0xC0) or SOF2 (0xFF 0xC2) marker.
    scanJpegSof buf 2
  | some "image/webp" =>
    parseWebPDimensions buf
  | _ => none

end LeanAgent.CodingAgent.Utils.ImageProcess