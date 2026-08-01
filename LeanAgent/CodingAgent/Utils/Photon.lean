import Lean

/-!
# Photon image processing (Pi `utils/photon.ts`)

Photon (`@silvia-odwyer/photon-node`) is a Rust/WASM image processing
library. It is not available in Lean. This module provides a `loadPhoton`
stub that always returns `none`, and a `PhotonImage` type, so dependent
modules (`ImageConvert`, `ImageProcess`) can reference them in their
signatures without conditional imports.

Documented as Exclusion List §7-adjacent: Photon requires a WASM runtime
with `fs.readFileSync` patching for Bun compiled binaries — none of this
is portable to Lean.
-/

namespace LeanAgent.CodingAgent.Utils.Photon

/--
Stub type for a Photon image handle. In Pi this is
`PhotonImage.new_from_byteslice(bytes)`. No operations are available
since the WASM module cannot be loaded.
-/
structure PhotonImage where
  -- Opaque — no fields are accessible without the WASM runtime.
deriving Inhabited

/--
Pi `loadPhoton`: load the `@silvia-odwyer/photon-node` module.

Always returns `none` because Photon is a Rust/WASM module not available
in Lean. The function signature is preserved so callers compile.
-/
def loadPhoton : IO (Option PhotonImage) := do
  pure none

end LeanAgent.CodingAgent.Utils.Photon