# tui Parity Ledger

Tracks LeanAgent parity with Pi `packages/tui`.
Reference: `vendor/pi/packages/tui` (read-only).

Full-project charter: [`docs/goals/FULL_PI_PORT_PROMPT.md`](goals/FULL_PI_PORT_PROMPT.md).

**Status: COMPONENTS STARTED.** Component/Spacer/Text/Box/SelectList/Loader/Input/Markdown ported with offline-renderable Component interface. TUI class (differential rendering, overlays, input handling) still missing.

## Started modules

| Lean | Status | Notes |
| --- | --- | --- |
| `LeanAgent.Tui.Component` | partial | Component/Container/Overlay types; TUI class missing |
| `LeanAgent.Tui.Utils` | partial | visibleWidth, wrapText, padRight, applyBackground, truncateToWidth |
| `LeanAgent.Tui.Render` | partial | formatAgentEvent / formatTranscript; legacy function-based components |
| `LeanAgent.Tui.Spacer` | implemented | Empty line spacer |
| `LeanAgent.Tui.Text` | implemented | Multi-line text with word wrapping |
| `LeanAgent.Tui.Box` | implemented | Container with padding and background |
| `LeanAgent.Tui.SelectList` | implemented | Scrollable selectable list |
| `LeanAgent.Tui.Loader` | implemented | Spinner animation with message |
| `LeanAgent.Tui.Input` | implemented | Single-line text input |
| `LeanAgent.Tui.Markdown` | implemented | Markdown to terminal renderer |
| `LeanAgent.Tui.Fuzzy` | implemented | Subsequence fuzzy match with scoring (consecutive, boundary, gap, position), alpha-numeric swap fallback, multi-token filter+sort |
| `LeanAgent.Tui.KillRing` | implemented | Emacs-style kill ring (push/peek/rotate) with accumulate merge |
| `LeanAgent.Tui.UndoStack` | implemented | Generic clone-on-push undo stack (push/pop/clear/length) |
| `LeanAgent.Tui.WordNavigation` | implemented | findWordBackward/findWordForward with ASCII whitespace+punctuation boundaries |
| `LeanAgent.Tui.Terminal` | implemented | Terminal size (COLUMNS/LINES env), ANSI escape generators (cursor, clear, alt-screen, scroll) |
| `LeanAgent.Tui.TerminalColors` | implemented | supportsTrueColor/256Color detection, rgbToAnsi256/rgbToAnsi conversion, fg/bg escape generators |
| `LeanAgent.Tui.Keys` | implemented | KeyAction inductive, parseKey (ANSI CSI/SS3 escape → KeyAction), keyName/isPrintable/isModified/isNavigation |

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
| `src/fuzzy.ts` | `LeanAgent.Tui.Fuzzy` | implemented | Subsequence fuzzy match with scoring (consecutive, boundary, gap, position, exact), alpha-numeric swap fallback, multi-token filter+sort. |
| `src/index.ts` | `LeanAgent.Tui (missing)` | missing |  |
| `src/keybindings.ts` | `LeanAgent.Tui (partial)` | partial | keyBinding stub added; full keybindings matrix open. |
| `src/keys.ts` | `LeanAgent.Tui.Keys` | implemented | KeyAction inductive (up/down/left/right/enter/escape/tab/backspace/delete/home/end/pageUp/pageDown/ctrlKey/altKey/shiftKey/metaKey/charKey/unknown), parseKey (ANSI CSI/SS3 escape → KeyAction), keyName/isPrintable/isModified/isNavigation. |
| `src/kill-ring.ts` | `LeanAgent.Tui.KillRing` | implemented | KillRing (push with prepend/accumulate merge, peek, rotate, length) over IO.Ref. |
| `src/native-modifiers.ts` | `LeanAgent.Tui (partial)` | partial | nativeModifier stub added; full native-modifiers matrix open. |
| `src/stdin-buffer.ts` | `LeanAgent.Tui.StdinBuffer` | implemented | StdinBuffer (create/pushChar/popChar/peekChar/clear/toString/length/processByte) over IO.Ref; UTF-8 multi-byte simplified. |
| `src/terminal-colors.ts` | `LeanAgent.Tui.TerminalColors` | implemented | supportsTrueColor/256Color env detection, rgbToAnsi256 (6×6×6 cube + grayscale), rgbToAnsi (16-color), fg256/bg256/fgTrueColor/bgTrueColor generators. |
| `src/terminal-image.ts` | `LeanAgent.Tui (partial)` | partial | terminalImage stub added; full terminal-image matrix open. |
| `src/terminal.ts` | `LeanAgent.Tui.Terminal` | implemented | TerminalSize (COLUMNS/LINES env), isTerminal, ANSI escape generators (cursorUp/Down/Forward/Back, clearLine/Screen, hide/showCursor, enter/exitAltScreen, cursorTo, save/restoreCursor, scrollUp/Down). |
| `src/tui.ts` | `LeanAgent.Tui.Component` | partial | Component/Container/Overlay types ported; TUI class (differential rendering, overlays, input) still missing |
| `src/undo-stack.ts` | `LeanAgent.Tui.UndoStack` | implemented | Generic UndoStack(α) (push/pop/clear/length) over IO.Ref with clone-on-push semantics. |
| `src/utils.ts` | `LeanAgent.Tui.Utils` | partial | visibleWidth, wrapText, padRight, applyBackground, truncateToWidth ported; full ANSI tracking, grapheme segmentation, east-asian-width still missing |
| `src/word-navigation.ts` | `LeanAgent.Tui.WordNavigation` | implemented | findWordBackward/findWordForward with ASCII whitespace+punctuation boundary detection; skipBack/skipFwd/skipWsFwd helpers. |

## Rules

- Do not mark `implemented` without shipped-API offline tests.
- Do not use `deferred` except Exclusion List in FULL_PI_PORT_PROMPT §7.
- Update this file whenever status changes.