import Lean

/-!
# EXIF orientation (Pi `packages/coding-agent/src/utils/exif-orientation.ts`)

Reads the EXIF orientation tag (`0x0112`) from JPEG and WebP image bytes. The
byte parsing (`getExifOrientation`, `findJpegTiffOffset`, `findWebpTiffOffset`,
`readOrientationFromTiff`, `hasExifHeader`) is fully ported and offline-tested.

The pixel-transform half (`applyExifOrientation`) drives the `photon` Rust/WASM
image library, which is not ported; the orientation → transform mapping is
documented in `orientationTransform` for callers that wire up a pixel backend.
-/

namespace LeanAgent.CodingAgent.Utils.ExifOrientation

-- ============================================================================
-- Byte readers (little- or big-endian, driven by the TIFF byte order mark)
-- ============================================================================

/-- Read a 16-bit value at `pos` honoring endianness. -/
def read16 (bytes : ByteArray) (pos : Nat) (le : Bool) : Nat :=
  let b0 := bytes.data[pos]!.toNat
  let b1 := bytes.data[pos + 1]!.toNat
  if le then b0 ||| (b1 <<< 8) else (b0 <<< 8) ||| b1

/-- Read a 32-bit value at `pos` honoring endianness. -/
def read32 (bytes : ByteArray) (pos : Nat) (le : Bool) : Nat :=
  let b0 := bytes.data[pos]!.toNat
  let b1 := bytes.data[pos + 1]!.toNat
  let b2 := bytes.data[pos + 2]!.toNat
  let b3 := bytes.data[pos + 3]!.toNat
  if le then b0 ||| (b1 <<< 8) ||| (b2 <<< 16) ||| (b3 <<< 24)
  else (b0 <<< 24) ||| (b1 <<< 16) ||| (b2 <<< 8) ||| b3

/--
Pi `readOrientationFromTiff`: parse the TIFF IFD at `tiffStart` and return the
orientation tag value (1-8), or 1 if absent/invalid.
-/
def readOrientationFromTiff (bytes : ByteArray) (tiffStart : Nat) : Nat := Id.run do
  if tiffStart + 8 > bytes.size then pure 1
  else
    let byteOrder := (bytes.data[tiffStart]!.toNat <<< 8) ||| bytes.data[tiffStart + 1]!.toNat
    let le := byteOrder == 0x4949
    let ifdOffset := read32 bytes (tiffStart + 4) le
    let ifdStart := tiffStart + ifdOffset
    if ifdStart + 2 > bytes.size then pure 1
    else
      let entryCount := read16 bytes ifdStart le
      let mut i := 0
      let mut found : Nat := 1
      let mut done := false
      while i < entryCount && !done do
        let entryPos := ifdStart + 2 + i * 12
        if entryPos + 12 > bytes.size then
          done := true
        else if read16 bytes entryPos le == 0x0112 then
          let value := read16 bytes (entryPos + 8) le
          found := if value ≥ 1 && value ≤ 8 then value else 1
          done := true
        i := i + 1
      pure found

/-- True iff `bytes` at `offset` begins the `Exif\0\0` marker. -/
def hasExifHeader (bytes : ByteArray) (offset : Nat) : Bool :=
  bytes.size > offset + 5
    && bytes.data[offset]! == 0x45
    && bytes.data[offset + 1]! == 0x78
    && bytes.data[offset + 2]! == 0x69
    && bytes.data[offset + 3]! == 0x66
    && bytes.data[offset + 4]! == 0x00
    && bytes.data[offset + 5]! == 0x00

/--
Pi `findJpegTiffOffset`: walk JPEG segments to the APP1 EXIF segment and return
the TIFF header offset, or `(none)` if not found.
-/
partial def findJpegTiffOffset (bytes : ByteArray) (offset : Nat := 2) : Option Nat :=
  if offset ≥ bytes.size - 1 then none
  else if bytes.data[offset]! != 0xFF then none
  else
    let marker := bytes.data[offset + 1]!.toNat
    if marker == 0xFF then findJpegTiffOffset bytes (offset + 1)
    else if marker == 0xE1 then
      if offset + 4 ≥ bytes.size then none
      else
        let segmentStart := offset + 4
        if segmentStart + 6 > bytes.size then none
        else if !hasExifHeader bytes segmentStart then none
        else some (segmentStart + 6)
    else
      if offset + 4 > bytes.size then none
      else
        let length := (bytes.data[offset + 2]!.toNat <<< 8) ||| bytes.data[offset + 3]!.toNat
        findJpegTiffOffset bytes (offset + 2 + length)

/-- Read a 4-char chunk id from bytes (WebP RIFF chunk). -/
def chunkIdAt (bytes : ByteArray) (offset : Nat) : String :=
  String.ofList
    [ Char.ofNat bytes.data[offset]!.toNat
    , Char.ofNat bytes.data[offset + 1]!.toNat
    , Char.ofNat bytes.data[offset + 2]!.toNat
    , Char.ofNat bytes.data[offset + 3]!.toNat ]

/--
Pi `findWebpTiffOffset`: walk WebP RIFF chunks to the EXIF chunk and return the
TIFF header offset (skipping an optional `Exif\0\0` prefix), or `none`.
-/
partial def findWebpTiffOffset (bytes : ByteArray) (offset : Nat := 12) : Option Nat :=
  if offset + 8 > bytes.size then none
  else
    let chunkId := chunkIdAt bytes offset
    let chunkSize :=
      bytes.data[offset + 4]!.toNat
        ||| (bytes.data[offset + 5]!.toNat <<< 8)
        ||| (bytes.data[offset + 6]!.toNat <<< 16)
        ||| (bytes.data[offset + 7]!.toNat <<< 24)
    let dataStart := offset + 8
    if chunkId == "EXIF" then
      if dataStart + chunkSize > bytes.size then none
      else
        let tiffStart := if chunkSize ≥ 6 && hasExifHeader bytes dataStart then dataStart + 6 else dataStart
        some tiffStart
    else
      -- RIFF chunks are padded to even size.
      findWebpTiffOffset bytes (dataStart + chunkSize + (chunkSize % 2))

/--
Pi `getExifOrientation`: detect JPEG (`FF D8`) or WebP (`RIFF....WEBP`) and
return the EXIF orientation tag (1-8), or 1 if not present/invalid.
-/
def getExifOrientation (bytes : ByteArray) : Nat :=
  let tiffOffset? :=
    if bytes.size ≥ 2 && bytes.data[0]! == 0xFF && bytes.data[1]! == 0xD8 then
      findJpegTiffOffset bytes
    else if bytes.size ≥ 12
        && bytes.data[0]! == 0x52 && bytes.data[1]! == 0x49 && bytes.data[2]! == 0x46 && bytes.data[3]! == 0x46
        && bytes.data[8]! == 0x57 && bytes.data[9]! == 0x45 && bytes.data[10]! == 0x42 && bytes.data[11]! == 0x50 then
      findWebpTiffOffset bytes
    else none
  match tiffOffset? with
  | none => 1
  | some off => readOrientationFromTiff bytes off

-- ============================================================================
-- Orientation → transform mapping (Pi `applyExifOrientation` switch)
-- ============================================================================

/-- The pixel transforms an EXIF orientation implies. -/
inductive OrientationTransform where
  /-- No transform (orientation 1). -/
  | identity
  /-- Mirror horizontally. -/
  | flipH
  /-- Rotate 180° (= flipH + flipV). -/
  | rotate180
  /-- Mirror vertically. -/
  | flipV
  /-- Transpose (= rotate 90° CW then flipH). -/
  | transpose
  /-- Rotate 90° CW. -/
  | rotate90
  /-- Transverse (= rotate 90° CCW then flipH). -/
  | transverse
  /-- Rotate 90° CCW (= 270° CW). -/
  | rotate270
deriving Inhabited, BEq, Repr

/-- Map an orientation (1-8) to its transform (Pi `applyExifOrientation`). -/
def orientationTransform (orientation : Nat) : OrientationTransform :=
  match orientation with
  | 2 => .flipH
  | 3 => .rotate180
  | 4 => .flipV
  | 5 => .transpose
  | 6 => .rotate90
  | 7 => .transverse
  | 8 => .rotate270
  | _ => .identity

end LeanAgent.CodingAgent.Utils.ExifOrientation
