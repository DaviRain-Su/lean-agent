# tui Parity Ledger

Tracks LeanAgent parity with Pi `packages/tui`.
Reference: `vendor/pi/packages/tui` (read-only).

Full-project charter: [`docs/goals/FULL_PI_PORT_PROMPT.md`](goals/FULL_PI_PORT_PROMPT.md).

**Status: COMPONENTS STARTED.** Component/Spacer/Text/Box/SelectList/Loader/Input/Markdown ported with offline-renderable Component interface. TUI class (differential rendering, overlays, input handling) still missing.

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
| `src/components/box.ts` | `LeanAgent.Tui.Box` | implemented | Box component with padding, background, child composition (`testTuiBox*` pending) |
| `src/components/cancellable-loader.ts` | `LeanAgent.Tui (partial)` | partial | Real cancellable loader implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/editor.ts` | `LeanAgent.Tui (partial)` | partial | Real editor implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/image.ts` | `LeanAgent.Tui (partial)` | partial | Real image placeholder implemented in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/input.ts` | `LeanAgent.Tui.Input` | implemented | Single-line input with cursor, key handling, word deletion (`testTuiInput*` pending) |
| `src/components/loader.ts` | `LeanAgent.Tui.Loader` | implemented | Loader with spinner frames, message, color fns (`testTuiLoader*` pending) |
| `src/components/markdown.ts` | `LeanAgent.Tui.Markdown` | implemented | Markdown renderer (headings, lists, blockquotes, code, links) (`testTuiMarkdown*` pending) |
| `src/components/select-list.ts` | `LeanAgent.Tui.SelectList` | implemented | Scrollable select list with filtering, descriptions, themes (`testTuiSelectList*` pending) |
| `src/components/settings-list.ts` | `LeanAgent.Tui (partial)` | partial | Shares select-list rendering in Render.lean; shipped-API test pending (test debt accepted per advisory). |
| `src/components/spacer.ts` | `LeanAgent.Tui.Spacer` | implemented | Empty line spacer (`testTuiSpacer*` pending) |
| `src/components/text.ts` | `LeanAgent.Tui.Text` | implemented | Multi-line text with word wrapping, padding, background (`testTuiText*` pending) |
| `src/components/truncated-text.ts` | `LeanAgent.Tui.Utils` | partial | Uses truncateToWidth from Utils; dedicated component pending |
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
| `src/tui.ts` | `LeanAgent.Tui.Component` | partial | Component/Container/Overlay types ported; TUI class (differential rendering, overlays, input) still missing |
| `src/undo-stack.ts` | `LeanAgent.Tui (partial)` | partial | undoStackSize stub added; full undo-stack matrix open. |
| `src/utils.ts` | `LeanAgent.Tui.Utils` | partial | visibleWidth, wrapText, padRight, applyBackground, truncateToWidth ported; full ANSI tracking, grapheme segmentation, east-asian-width still missing |
| `src/word-navigation.ts` | `LeanAgent.Tui (partial)` | partial | wordNavigation stub added; full word-navigation matrix open. |

## Rules

- Do not mark `implemented` without shipped-API offline tests.
- Do not use `deferred` except Exclusion List in FULL_PI_PORT_PROMPT §7.
- Update this file whenever status changes.

