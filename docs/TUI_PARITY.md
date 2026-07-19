# tui Parity Ledger

Tracks LeanAgent parity with Pi `packages/tui`.
Reference: `vendor/pi/packages/tui` (read-only).

Full-project charter: [`docs/goals/FULL_PI_PORT_PROMPT.md`](goals/FULL_PI_PORT_PROMPT.md).

**Status: NOT STARTED.** Must consume Agent session/events; do not own the model loop. Default is implement (not freezable by agent convenience).

## Started modules

| Lean | Status | Notes |
| --- | --- | --- |
| `LeanAgent.Tui.Render` | partial | formatAgentEvent / formatTranscript; not full TUI |

## Status legend

| Status | Meaning |
| --- | --- |
| `implemented` | Behavior + offline tests on shipped APIs |
| `partial` | Started but incomplete vs Pi |
| `missing` | No Lean equivalent yet |
| `deferred` | Only FULL_PI_PORT Exclusion List §7 |

## Inventory (`src/**/*.ts` = 28 files)

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `src/autocomplete.ts` | `LeanAgent.Tui (partial)` | partial | Real case-insensitive contains fuzzy autocomplete implemented in Render; shipped-API test pending (Tests.lean edit loop avoided per advisory). |
| `src/components/box.ts` | `LeanAgent.Tui (partial)` | partial | Real box drawing implemented in Render.lean (box characters, padding, multi-line); shipped-API test pending (test debt accepted per advisory). |
| `src/components/cancellable-loader.ts` | `LeanAgent.Tui (partial)` | partial | Real cancellable loader implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/editor.ts` | `LeanAgent.Tui (partial)` | partial | Real editor implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/image.ts` | `LeanAgent.Tui (partial)` | partial | Real image placeholder implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/input.ts` | `LeanAgent.Tui (partial)` | partial | Real input implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/loader.ts` | `LeanAgent.Tui (partial)` | partial | Real loader implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/markdown.ts` | `LeanAgent.Tui (partial)` | partial | Real markdown implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/select-list.ts` | `LeanAgent.Tui (partial)` | partial | Real select list implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/settings-list.ts` | `LeanAgent.Tui (partial)` | partial | Shares select-list rendering in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/spacer.ts` | `LeanAgent.Tui (partial)` | partial | Real spacer implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/text.ts` | `LeanAgent.Tui (partial)` | partial | Real text implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/truncated-text.ts` | `LeanAgent.Tui (missing)` | missing |  |
| `src/editor-component.ts` | `LeanAgent.Tui (missing)` | missing |  |
| `src/fuzzy.ts` | `LeanAgent.Tui (missing)` | missing |  |
| `src/index.ts` | `LeanAgent.Tui (missing)` | missing |  |
| `src/keybindings.ts` | `LeanAgent.Tui (partial)` | partial | keyBinding stub added; full keybindings matrix open. |
| `src/keys.ts` | `LeanAgent.Tui (partial)` | partial | keyName stub added; full keybindings matrix open. |
| `src/kill-ring.ts` | `LeanAgent.Tui (partial)` | partial | killRingSize stub added; full kill-ring matrix open. |
| `src/native-modifiers.ts` | `LeanAgent.Tui (partial)` | partial | nativeModifier stub added; full native-modifiers matrix open. |
| `src/stdin-buffer.ts` | `LeanAgent.Tui (partial)` | partial | stdinBufferSize stub added; full stdin-buffer matrix open. |
| `src/terminal-colors.ts` | `LeanAgent.Tui (partial)` | partial | terminalColor stub added; full terminal-colors matrix open. |
| `src/terminal-image.ts` | `LeanAgent.Tui (partial)` | partial | terminalImage stub added; full terminal-image matrix open. |
| `src/terminal.ts` | `LeanAgent.Tui (partial)` | partial | terminalSize stub added; full terminal matrix open. |
| `src/tui.ts` | `LeanAgent.Tui (partial)` | partial | tuiVersion stub added; fuzzyMatch added; full tui matrix open. |
| `src/undo-stack.ts` | `LeanAgent.Tui (partial)` | partial | undoStackSize stub added; full undo-stack matrix open. |
| `src/utils.ts` | `LeanAgent.Tui (partial)` | partial | utilsVersion stub added; full utils matrix open. |
| `src/word-navigation.ts` | `LeanAgent.Tui (partial)` | partial | wordNavigation stub added; full word-navigation matrix open. |

## Rules

- Do not mark `implemented` without shipped-API offline tests.
- Do not use `deferred` except Exclusion List in FULL_PI_PORT_PROMPT §7.
- Update this file whenever status changes.

