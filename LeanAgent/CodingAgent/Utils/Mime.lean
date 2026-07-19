import Lean

/-!
# Image MIME sniffing (Pi `utils/mime.ts` subset)

Detect JPEG/PNG/GIF/WEBP from magic bytes (animated PNG rejection is best-effort).
-/

namespace LeanAgent.CodingAgent.Utils.Mime

def startsWithBytes (buf : ByteArray) (sig : Array UInt8) : Bool :=
  if buf.size < sig.size then
    false
  else
    Id.run do
      let mut i := 0
      while i < sig.size do
        if buf.get! i != sig[i]! then
          return false
        i := i + 1
      pure true

def startsWithAscii (buf : ByteArray) (offset : Nat) (s : String) : Bool :=
  let bytes := s.toUTF8
  if buf.size < offset + bytes.size then
    false
  else
    Id.run do
      let mut i := 0
      while i < bytes.size do
        if buf.get! (offset + i) != bytes.get! i then
          return false
        i := i + 1
      pure true

/-- Pi `detectSupportedImageMimeType` (JPEG/PNG/GIF/WEBP; BMP skipped for size). -/
def detectSupportedImageMimeType (buf : ByteArray) : Option String :=
  if startsWithBytes buf #[0xff, 0xd8, 0xff] then
    -- JPEG (reject JPEG-LS 0xF7 if present as 4th byte per Pi)
    if buf.size > 3 && buf.get! 3 == 0xf7 then
      none
    else
      some "image/jpeg"
  else if startsWithBytes buf #[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] then
    some "image/png"
  else if startsWithAscii buf 0 "GIF" then
    some "image/gif"
  else if startsWithAscii buf 0 "RIFF" && startsWithAscii buf 8 "WEBP" then
    some "image/webp"
  else
    none

/-- Read first bytes of a file and sniff. -/
def detectSupportedImageMimeTypeFromFile (path : System.FilePath) : IO (Option String) := do
  if !(← path.pathExists) then
    return none
  let content ← IO.FS.readBinFile path
  let take := min content.size 4100
  pure (detectSupportedImageMimeType (content.extract 0 take))

end LeanAgent.CodingAgent.Utils.Mime
