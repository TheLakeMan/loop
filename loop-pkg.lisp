;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later

;; ─────────────────────────────────────────────────────────────────────────────
;; loop-pkg.lisp — the package entry point (the manifest's `main`).
;;
;; Why this exists SEPARATELY from loop.lisp: Rusty's `load` resolves a relative
;; path against the process working directory, not against the file doing the
;; loading. loop.lisp loads its siblings by bare name — (load "loop-core.lisp") —
;; which only resolves when you are sitting IN the loop directory (the dev
;; quickstart: `cd loop; rusty; (load "loop.lisp")`). A package installed by pkg
;; lives at ~/.rusty/packages/loop and is loaded from wherever the user happens
;; to be, so the entry must load its siblings by ABSOLUTE path. That is the whole
;; difference — the engine files themselves are byte-identical either way.
;; ─────────────────────────────────────────────────────────────────────────────

;; pkg installs a package named "loop" at exactly this path (pkg-root is
;; $HOME/.rusty/packages). Deriving our own directory from it is what lets the
;; siblings load regardless of the caller's CWD.
(define loop-pkg-dir
  (string-append (shell "printf $HOME") "/.rusty/packages/loop"))

(define (loop-pkg-load rel)
  (load (string-append loop-pkg-dir "/" rel)))

(loop-pkg-load "loop-core.lisp")
(loop-pkg-load "loop-questions.lisp")
(loop-pkg-load "loop-soul.lisp")

;; ── Self-integrity: has loop's OWN installed code drifted since install day? ───
;; Delegates to pkg-drift, which compares the live package tree against the lock
;; pkg wrote at install (~/.rusty/pkg-locks/loop.json — OUTSIDE this tree, so a
;; `git pull` in here can't rewrite its own alibi). Returns pkg-drift's verdict:
;;   'verified | (changed ((path what)...)) | (no-lock "loop") | (not-installed "loop")
;; Guarded: if Rusty's pkg.lisp isn't loaded, pkg-drift is undefined and the
;; reference raises — we catch that and say so rather than crash.
;;
;; HONEST SCOPE (same as loop-integrity, and stated for the same reason): this
;; catches accident and quiet local drift — a stray editor, a bad sync, a
;; half-finished pull. It is NOT proof against a determined local attacker, who
;; can rewrite the lock as easily as the files it vouches for. For provenance —
;; "are these the bytes the publisher meant?" — use (pkg-verify "loop" fp) with a
;; fingerprint that reached you OUT OF BAND (a release note), never one loop
;; shipped in its own repo.
(define (loop-self-check)
  (try-catch (pkg-drift "loop")
    (e) (list 'pkg-not-loaded
              "load Rusty's pkg.lisp first to self-check installed integrity")))
