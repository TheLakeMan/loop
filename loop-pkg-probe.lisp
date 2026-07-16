;;; loop-pkg-probe.lisp — proves loop is a valid, cwd-independent package.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; run_tests.sh copies loop into a throwaway $HOME/.rusty/packages/loop and runs
;;; this from an UNRELATED working directory. It checks three things without
;;; pkg.lisp, an LLM, or the network:
;;;   MANIFEST-OK        — package.lisp reads as a well-formed manifest
;;;   PKG-ENTRY-OK       — loading the manifest's `main` brings the whole engine
;;;                        up despite cwd-relative `load` (the reason the package
;;;                        needs its own absolute-path entry)
;;;   SELFCHECK-GUARDED  — loop-self-check degrades gracefully when pkg.lisp is
;;;                        absent, instead of crashing
;;; The real install/verify/drift chain is pkg.lisp's own job (Rusty's
;;; pkg-test.lisp); this proves loop holds up its end of the package contract.

(define pkgdir (string-append (shell "printf $HOME") "/.rusty/packages/loop"))

;; (1) Manifest well-formed — read exactly as pkg-read-manifest does, but without
;; needing pkg.lisp loaded: wrap the file in (quote ...) and evaluate.
(define manifest
  (eval-string
    (string-append "(quote " (file-read (string-append pkgdir "/package.lisp")) ")")))
(define (m-get k) (let ((h (assoc k manifest))) (if h (cadr h) #f)))
(println
  (if (and (equal? "loop" (m-get 'name))
           (string? (m-get 'version))
           (equal? "loop-pkg.lisp" (m-get 'main)))
    "MANIFEST-OK" "MANIFEST-FAIL"))

;; (2) The package entry loads the engine from this foreign cwd. If absolute-path
;; loading were broken, (load ...) would raise "cannot read loop-core.lisp".
(load (string-append pkgdir "/loop-pkg.lisp"))
(define fn-type (type-of (lambda (x) x)))
(println
  (try-catch
    (if (and (not (null? QUESTION-BANK))                  ; loop-questions loaded
             (equal? fn-type (type-of loop-start))        ; loop-core loaded
             (equal? fn-type (type-of loop-remember)))    ; loop-soul loaded
      "PKG-ENTRY-OK" "PKG-ENTRY-FAIL")
    (e) "PKG-ENTRY-FAIL"))

;; (3) Self-check degrades, not crashes, when pkg.lisp is not loaded.
(println
  (try-catch
    (if (equal? 'pkg-not-loaded (car (loop-self-check)))
      "SELFCHECK-GUARDED-OK" "SELFCHECK-GUARDED-FAIL")
    (e) "SELFCHECK-GUARDED-FAIL"))
