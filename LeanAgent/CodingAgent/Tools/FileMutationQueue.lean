import Lean
import Std.Sync.Mutex
import LeanAgent.CodingAgent.Utils.Paths

/-!
# File mutation queue (Pi `core/tools/file-mutation-queue.ts`)

Serializes file-mutation operations that target the same file; operations for
distinct files still run in parallel. Ports Pi's
`core/tools/file-mutation-queue.ts`.

Pi builds a chain of JS `Promise`s per file, guarded by a `registrationQueue`
promise so key insertion is atomic. The Lean port uses one `Std.Mutex Unit`
per canonical file key (the per-file queue), held for the duration of `fn`,
and a global registration `Std.Mutex` that makes get-or-create of a per-file
mutex atomic. Different files get distinct mutexes and run in parallel.

`getMutationQueueKey` mirrors Pi: lexically resolve (`resolvePath`), then
`realpath` if the entry exists (canonicalizing symlinks so a symlink and its
target share a queue). Missing entries (ENOENT/ENOTDIR) fall back to the
resolved path; `Utils.Paths.canonicalizePath` already encodes that fallback,
so Pi's `isMissingPathError` classifier is not needed here.

Divergence: Pi deletes a per-file queue entry after the last waiter releases
it (when its chained queue is still current), bounding the registry to in-flight
files. The Lean port retains per-file mutexes for the process lifetime — the
set is bounded by the distinct files mutated in a session, the mutexes are
small, and reusing them keeps serialization correct. Cleanup is deferred.
-/

namespace LeanAgent.CodingAgent.Tools.FileMutationQueue

open LeanAgent.CodingAgent.Utils.Paths

-- ============================================================================
-- Global registry (process-wide)
-- ============================================================================

/-- Guards atomic get-or-create of per-file mutexes (Pi `registrationQueue`). -/
initialize registrationMutex : Std.Mutex Unit ← Std.Mutex.new ()

/-- Per-canonical-key mutex; each is held for the duration of one mutation. -/
initialize fileQueues : IO.Ref (Std.HashMap String (Std.Mutex Unit)) ← IO.mkRef {}

-- ============================================================================
-- getMutationQueueKey
-- ============================================================================

/--
Pi `getMutationQueueKey`: realpath if the entry exists, else the lexically
resolved path. Symlinks collapse to their target so a symlink and its target
share a queue. Missing entries fall back to the resolved path (no throw).
-/
def getMutationQueueKey (filePath : String) : IO String := do
  let resolved ← resolvePath filePath
  canonicalizePath resolved

-- ============================================================================
-- getOrCreateQueue
-- ============================================================================

/--
Atomically get-or-create the per-file mutex for `key` (Pi registration step).
Held under `registrationMutex` so two concurrent registrations for a new key
cannot each create a distinct mutex.
-/
def getOrCreateQueue (key : String) : IO (Std.Mutex Unit) := do
  registrationMutex.atomically fun _ => do
    let qs ← fileQueues.get
    match qs.get? key with
    | some m => pure m
    | none => do
        let m ← Std.Mutex.new ()
        fileQueues.modify fun s => s.insert key m
        pure m

-- ============================================================================
-- withFileMutationQueue
-- ============================================================================

/--
Pi `withFileMutationQueue`: run `fn` while holding the per-file mutex, so
mutations of the same file are serialized. Different files run in parallel.
-/
def withFileMutationQueue {α : Type} (filePath : String) (fn : IO α) : IO α := do
  let key ← getMutationQueueKey filePath
  let m ← getOrCreateQueue key
  m.atomically fun _ => fn

/-- Reset the registry (tests only). -/
def resetForTests : IO Unit := do
  registrationMutex.atomically fun _ => do
    fileQueues.set {}

/-- Number of distinct per-file queues registered (tests only). -/
def queueCount : IO Nat := do
  registrationMutex.atomically fun _ => do
    let qs ← fileQueues.get
    pure qs.size

end LeanAgent.CodingAgent.Tools.FileMutationQueue