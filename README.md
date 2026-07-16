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

**Version:** 0.4.0

## Quickstart

You need the `rusty` interpreter on your PATH and (for live interviews) an
OpenAI-compatible LLM endpoint — e.g. `llama-server` on `localhost:8080`
(override with `RUSTY_LLM_URL`).

```bash
git clone https://github.com/TheLakeMan/rusty
cd rusty && cargo install --path . --bin rusty --root ~/.local

git clone https://github.com/TheLakeMan/loop
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

## Has anything changed since it was said?

Every response is hashed (SHA-256) the moment it is written. Later — a month
later, a machine later — `(loop-integrity "session-id")` re-reads what is on
disk and tells you whether it still says what was said:

```lisp
(loop-integrity-report "loop-Marta-1783394592")
;;   ok        ~/.loop/responses/loop-Marta-1783394592-0.txt
;;   ok        ~/.loop/responses/loop-Marta-1783394592-1.txt
;;   changed   ~/.loop/responses/loop-Marta-1783394592-2.txt
```

Per response: `ok`, `changed`, `missing` (the file is gone), or `unsealed` (no
hash was recorded, so the check declines to speak for it). `(loop-integrity id)`
returns the same thing as data — `(overall rows)` — if you'd rather act on it
than read it.

**What this is, exactly.** It is tamper-*evidence*, scoped to one machine: it
tells you nothing was changed *quietly* — by a stray editor, a bad sync, a
half-finished restore. It is **not** unforgeable and not adversarial crypto:
the hashes live in the same `~/.rusty/memory.lisp` the session is indexed from,
so anyone who can rewrite a transcript can rewrite its hash in the same breath.
Resisting *that* would need an anchor somewhere they cannot reach, which loop
deliberately does not have — it is a local vessel, not a notary. The honest
promise is the small one: if these words changed, you will know.

## Files

| File | Role |
|------|------|
| `loop.lisp` | entry point — loads everything, prints the banner |
| `loop-core.lisp` | interview engine: sessions, turns, advisor, persistence |
| `loop-questions.lisp` | question bank — 22 questions across 10 categories |
| `loop-soul.lisp` | the soul layer: portrait + witness + `(loop-remember)` |
| `loop-test.lisp` | hermetic golden test — 14 invariants, no LLM, no disk |
| `expected_loop.txt` | the golden output |
| `loop-integrity-drive.lisp` | drives a real on-disk session (run under a throwaway `$HOME`) |
| `loop-integrity-verify.lisp` | reports the integrity verdict for that session |

## Tests

```bash
./run_tests.sh
```

Three checks. The **golden test** is fully hermetic: the LLM seams, the clock,
and every disk path are stubbed in-memory, so it runs identically anywhere
`rusty` runs and never touches a real `~/.loop/` or `~/.rusty/`. The two
**real-disk checks** run the genuine persistence path under a throwaway `$HOME`
— one proves a session only ever *adds* its own `loop.*` keys, leaving
pre-existing memory byte-identical; the other proves the integrity check both
reports `intact` on an untouched session *and* actually bites, catching an
edited transcript and a deleted one. Your real `~/.loop/` and `~/.rusty/` are
never read or written by any of them.

loop needs [Rusty](https://github.com/TheLakeMan/rusty) **0.45.0 or newer**
(that release added the `file-hash` builtin the integrity check is built on).

## License

AGPL-3.0-or-later — Copyright (c) 2026 Nicholas Vermeulen.
Commercial licensing available on inquiry.
