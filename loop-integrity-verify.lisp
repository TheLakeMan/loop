;;; loop-integrity-verify.lisp — report the integrity verdict for the session
;;; on REAL disk under $HOME, as a machine-readable line.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; Companion to loop-integrity-drive.lisp. run_tests.sh drives a genuine
;;; session under a THROWAWAY $HOME, then runs this before and after tampering
;;; with a stored transcript — proving the check reports "intact" on an
;;; untouched session AND actually BITES when a response is edited or deleted.
;;; A check that only ever says "intact" would pass a weaker test forever.
;;;
;;; The session id is read back from loop's own index rather than passed in, so
;;; this needs no argv and reads exactly what a resumed session would.

(load "loop-core.lisp")
(load "loop-questions.lisp")

(let ((ids (list-sessions)))
  (if (null? ids)
    (println "VERDICT no-sessions")
    (println (str "VERDICT " (nth (loop-integrity (nth ids 0)) 0)))))
