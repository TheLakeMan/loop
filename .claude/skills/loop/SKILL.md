---
name: loop
description: Work on loop (this repo) — the remembrance flagship on Rusty. Covers the hermetic-test discipline, the two LLM seams, the safety rules around real ~/.loop and ~/.rusty data, and how to verify changes live.
---

# Working on loop

loop is a pure-Lisp application on the [Rusty](https://github.com/TheLakeMan/rusty)
interpreter — **zero new Rust**. It is the remembrance flagship ("a memory
vessel for the living"): a guided life interview that keeps transcripts, then
distills a grounded **portrait** (LLM) and an honest **witness** (no LLM).
It is a separate product line from the safety suite (wuwei/shouzhong/mingjian)
— different buyer; never mix the stories.

## Hard safety rules (non-negotiable)

- Real personal data lives in **`~/.loop/`** and **`~/.rusty/memory.lisp`**.
  Tests and experiments must NEVER touch them.
- The golden test is hermetic by construction (all seams stubbed). Anything
  that exercises real disk or a real LLM runs under a **throwaway HOME**:
  `HOME=$(mktemp -d /tmp/loop-XXXX) rusty ...`
- Before/after any live run, verify the real data didn't change:
  `md5sum ~/.rusty/memory.lisp; find ~/.loop -type f | sort | xargs md5sum`

## Architecture

- `loop.lisp` — entry; loads core + questions + soul, prints banner (shows
  major.minor only).
- `loop-core.lisp` — engine. `LOOP-VERSION` lives here; bump it (and the
  golden's version line) whenever loop behavior changes. Sessions are plain
  lists; navigation state persists via Rusty's `remember`/`recall`; responses
  are one file each under `$HOME/.loop/responses/`. `$HOME` resolves through
  one minimal `shell` call (`loop-home`) — that's what makes throwaway-HOME
  isolation work. The advisor (`llm-advise`) returns one word
  (follow-up/continue/complete), is `try-catch`-wrapped (any LLM failure →
  "continue" — never end a live telling), and carries a 2000-token budget so
  reasoning models can think before answering. A "complete" verdict saves the
  final response BEFORE closing (invariants 7c/7d).
- `loop-questions.lisp` — 22 questions / 10 categories, with per-question
  follow-ups.
- `loop-soul.lisp` — `loop-portrait` (LLM through the `loop-portrait-llm`
  seam, 3000-token budget; grounded prompt: only their words, no invention,
  no flattery), `loop-witness` (NO LLM — fixed honest text: no claimed
  memory/feeling/authorship), `(loop-remember)` (portrait then witness;
  portrait failure is caught so witness + transcripts survive and the call is
  retryable). Separate dirs: portraits/ vs witness/ — never mix.

## The two LLM seams (why tests can stub them)

`llm` is a special form and cannot be shadowed, so all LLM use goes through
`define`d wrappers the test redefines: `llm-advise` (core) and
`loop-portrait-llm` (soul). Keep it that way — never call `(llm ...)` from
anywhere else.

## Testing

```bash
./run_tests.sh                                  # golden suite
rusty loop-test.lisp | diff - expected_loop.txt # by hand
```

After a behavior change: extend `loop-test.lisp` (invariants are numbered;
add, don't renumber), regenerate the golden with
`rusty loop-test.lisp > expected_loop.txt`, rerun to confirm determinism.
Never hand-edit the expected file; never add timing/randomness/LLM output.

Live verification (portrait quality, advisor behavior) is NOT golden — script
it under a throwaway HOME against a real local server, and raise
`RUSTY_LLM_TIMEOUT_SECS` (e.g. 1800) on slow hardware.

## Conventions

Symbol ☯ (never a crab). Dedication, where one appears, is exactly:
*In memory of my brother.* AGPL-3.0-or-later headers on every source file.
Commit trailers: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
(and Grok `<noreply@x.ai>` where Grok contributed).
