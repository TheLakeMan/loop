;; Rusty package manifest — format defined by pkg.lisp in the Rusty repo
;; (github.com/TheLakeMan/rusty). A package is any git repo with this file at
;; its root. To install (you need Rusty's pkg.lisp loaded first):
;;
;;   (load "pkg.lisp")
;;   (pkg-install "https://github.com/TheLakeMan/loop")   ; clones + auto-locks
;;   (pkg-load "loop")                                     ; brings the engine up
;;
;; loop is pure Lisp on Rusty (>= 0.45.0, for file-hash) with no package deps,
;; so there is no (deps ...) key. `main` is loop-pkg.lisp, NOT loop.lisp: a
;; package is loaded from an arbitrary working directory, and Rusty's `load`
;; resolves relative paths against the CWD — so the entry has to load its
;; siblings by absolute path. See loop-pkg.lisp.
((name "loop")
 (version "0.6.0")
 (main "loop-pkg.lisp"))
