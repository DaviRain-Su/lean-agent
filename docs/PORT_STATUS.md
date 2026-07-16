# LeanAgent ↔ Pi port status (dashboard)

Living counts for the full rewrite. **Not** a completion certificate.  
Charter: [`goals/FULL_PI_PORT_PROMPT.md`](goals/FULL_PI_PORT_PROMPT.md), [`goals/FULL_PI_PORT_GOAL.md`](goals/FULL_PI_PORT_GOAL.md).

Update when ledgers change. Prefer under-claiming.

## Package rollup (manual; re-count from ledgers)

| Domain | Pi package | Lean target | Reality (honest) | Ledger |
| --- | --- | --- | --- | --- |
| AI | `packages/ai` | `LeanAgent.AI.*`, `Models`, `Http` | **Large partial** — many providers/APIs exist; transport live-stream, generated catalog, edges still open | `AI_PARITY.md` |
| Agent | `packages/agent` | `Agent.*`, `Session`, `Harness.*` | **Partial** — core loop usable offline; harness is thin vs Pi | `AGENT_PARITY.md` |
| Coding-agent | `packages/coding-agent` | `CodingTools`, `Project`, `Main` | **MVP partial** — few tools, REPL, OMP skills/commands, v1 JSONL | create `CODING_AGENT_PARITY.md` |
| TUI | `packages/tui` | future `LeanAgent.Tui` | **Missing** | create `TUI_PARITY.md` when started |
| Orchestrator | `packages/orchestrator` | future `LeanAgent.Orchestrator` | **Missing** | create `ORCHESTRATOR_PARITY.md` when started |

## Scale reminder (upstream pin)

| Package | ~TS LOC under `src` |
| --- | ---: |
| ai | ~35k |
| agent | ~8k |
| coding-agent | ~51k |
| tui | ~12k |
| orchestrator | ~2k |

## Definition of done

See `FULL_PI_PORT_PROMPT.md` §8. Until every in-scope Pi module is `implemented` or Exclusion-`deferred`, status is **IN PROGRESS**.

## Last audit note

Earlier “agent full parity” Goal completion was **rejected as product-complete**: harness façades and broad deferred must not be treated as a finished port. Use `FULL_PI_PORT_*` only for whole-project rewrite tracking.
