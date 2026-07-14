# loop ☯

**A memory vessel for the living.**

*In memory of my brother.*

loop is a guided life interview you run at your own table, on your own machine.
It asks the questions people wish they had asked — childhood, work, love, loss,
legacy — follows up when there is more underneath, and keeps what was said. At
the end of a telling it distills two things:

- a **portrait** — who this person is, drawn *only* from their own words
  (an LLM writes it, under a prompt that forbids invention and flattery), and
- a **witness** — a short, honest note from the one who listened: an AI that
  admits it keeps no memory, felt nothing it can claim, and shaped none of the
  story. Not a mind that remembers them — a record of the care taken in the
  telling.

Everything stays local: transcripts under `~/.loop/responses/`, portraits under
`~/.loop/portraits/`, the witness under `~/.loop/witness/`, session state in
Rusty's own memory (`~/.rusty/memory.lisp`). No cloud, no accounts, no
telemetry. Built on [Rusty](https://github.com/TheLakeMan/rusty) — a
zero-dependency Lisp interpreter in Rust — so the whole vessel runs on small,
ordinary hardware with a local LLM.

**Version:** 0.3.1

## Quickstart

You need the `rusty` interpreter on your PATH and (for live interviews) an
OpenAI-compatible LLM endpoint — e.g. `llama-server` on `localhost:8080`
(override with `RUSTY_LLM_URL`).

```bash
cd ~/projects/artifacts/rusty && cargo install --path . --bin rusty --root ~/.local

cd loop
rusty          # then, in the REPL:
```

```lisp
(load "loop.lisp")

(loop-start "Marta")      ; begin — loop asks the first question
(loop-say "I was born in 1949 in a two-room flat above my father's shop...")
;; ...loop decides: follow the thread deeper, or move on...
(loop-pause)              ; life happens — save and stop
(loop-resume "loop-Marta-...")   ; pick the telling back up
(loop-remember)           ; end of the telling: portrait + witness are kept
```

`(loop-status)` shows where you are; `(loop-sessions)` lists every telling.

## How it decides

After each answer, a small LLM call gives a one-word verdict: **follow-up**
(there is emotional depth worth staying with), **continue** (move to the next
question), or **complete** (they seem done for today). The advisor is wrapped
so that *no LLM failure can end a live telling* — a timeout or truncation
quietly degrades to "continue". Their final answer is always saved before a
telling closes.

Reasoning LLMs are supported: the seats carry enough token budget for the
model to think before it answers, and the interpreter refuses a reply that was
truncated mid-thought rather than passing chain-of-thought off as prose. On
slow hardware, raise the request timeout for portraits:
`RUSTY_LLM_TIMEOUT_SECS=1800`.

## What the soul layer promises

- The **portrait** is grounded: only their words go in, and the prompt forbids
  inventing anything they didn't say. Truthful, not flattering — the
  contradictions and hardships stay in.
- The **witness** never uses an LLM. It is fixed, honest text: no claimed
  feeling, no claimed continuity, no authorship of the life. It lives in its
  own directory and is never mixed into the portrait or the transcript.
- A failed portrait costs nothing: the transcripts and the witness survive,
  and `(loop-remember)` can simply be run again.

## Files

| File | Role |
|------|------|
| `loop.lisp` | entry point — loads everything, prints the banner |
| `loop-core.lisp` | interview engine: sessions, turns, advisor, persistence |
| `loop-questions.lisp` | question bank — 22 questions across 10 categories |
| `loop-soul.lisp` | the soul layer: portrait + witness + `(loop-remember)` |
| `loop-test.lisp` | hermetic golden test — 12 invariants, no LLM, no disk |
| `expected_loop.txt` | the golden output |

## Tests

```bash
./run_tests.sh
```

The golden test is fully hermetic: the LLM seams, the clock, and every disk
path are stubbed in-memory, so it runs identically anywhere `rusty` runs and
never touches a real `~/.loop/` or `~/.rusty/`.

## License

AGPL-3.0-or-later — Copyright (c) 2026 Nicholas Vermeulen.
Commercial licensing available on inquiry.
