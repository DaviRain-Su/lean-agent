import Lean

/-!
# File-system watch (Pi `utils/fs-watch.ts`)

Lean has no direct equivalent of Node's `fs.watch` (inotify / FSEvents).
This module defines a `FsWatcher` interface with `close : IO Unit` so
callers can write watch-and-retry loops against an abstract handle.

A production implementation could wrap an external watcher process
(`fswatch`/`watchman`), but that is deferred. The error-handling wrapper
and retry-delay constant are ported for structural parity.
-/

namespace LeanAgent.CodingAgent.Utils.FsWatch

/-- Retry delay (ms) after a watch error (Pi `FS_WATCH_RETRY_DELAY_MS`). -/
def FS_WATCH_RETRY_DELAY_MS : Nat := 5000

/--
Abstract file-system watcher handle. `close` releases the watcher's
resources; `isOpen` tracks whether it is still active.
-/
structure FsWatcher where
  close : IO Unit
  isOpen : IO Bool

/-- Pi `closeWatcher`: best-effort close, swallowing errors. -/
def closeWatcher (watcher : Option FsWatcher) : IO Unit := do
  match watcher with
  | some w =>
    try w.close catch _ => pure ()
  | none => pure ()

/--
Pi `watchWithErrorHandler`: start watching `path`, calling `onError` if
the watcher fails or cannot be created.

Since Lean has no built-in `fs.watch`, this returns `none` and calls
`onError` immediately. A real implementation would spawn an external
process and wire `onError` to its exit.
-/
def watchWithErrorHandler
    (path : String)
    (onError : IO Unit) : IO (Option FsWatcher) := do
  -- No native fs.watch in Lean; signal the error to the caller.
  onError
  pure none

end LeanAgent.CodingAgent.Utils.FsWatch