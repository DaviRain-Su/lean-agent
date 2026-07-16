import Lean

namespace LeanAgent.Agent.Harness.Uuid

/--
Pi-style UUIDv7: timestamp-ordered id with random bits.
Uses mono ms + mono nanos for uniqueness without OpenSSL in this helper.
-/
def uuidv7 : IO String := do
  let ms ← IO.monoMsNow
  let ns ← IO.monoNanosNow
  -- 48-bit timestamp (ms), version nibble 7, variant 10xxxxxx, remaining random-ish from nanos.
  let t0 := (ms >>> 40) &&& 0xff
  let t1 := (ms >>> 32) &&& 0xff
  let t2 := (ms >>> 24) &&& 0xff
  let t3 := (ms >>> 16) &&& 0xff
  let t4 := (ms >>> 8) &&& 0xff
  let t5 := ms &&& 0xff
  let seq := ns &&& 0xfffffff
  let b6 := 0x70 ||| ((seq >>> 24) &&& 0x0f)
  let b7 := (seq >>> 16) &&& 0xff
  let b8 := 0x80 ||| ((seq >>> 10) &&& 0x3f)
  let b9 := (seq >>> 2) &&& 0xff
  let r0 := (ns >>> 32) &&& 0xff
  let r1 := (ns >>> 40) &&& 0xff
  let r2 := (ns >>> 48) &&& 0xff
  let r3 := (ns >>> 56) &&& 0xff
  let r4 := (ns / 7) &&& 0xff
  let r5 := (ns / 13) &&& 0xff
  let hex (n : Nat) : String :=
    let s := Nat.toDigits 16 n
    if s.length == 1 then "0" ++ String.mk s else String.mk s
  pure s!"{hex t0}{hex t1}{hex t2}{hex t3}-{hex t4}{hex t5}-{hex b6}{hex b7}-{hex b8}{hex b9}-{hex r0}{hex r1}{hex r2}{hex r3}{hex r4}{hex r5}"

/-- True when `s` looks like an 8-4-4-4-12 hex UUID. -/
def looksLikeUuid (s : String) : Bool :=
  let parts := s.splitOn "-"
  parts.length == 5
    && parts[0]!.length == 8
    && parts[1]!.length == 4
    && parts[2]!.length == 4
    && parts[3]!.length == 4
    && parts[4]!.length == 12

end LeanAgent.Agent.Harness.Uuid
