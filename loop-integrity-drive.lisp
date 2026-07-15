;;; loop-integrity-drive.lisp — drive a REAL loop session on REAL disk.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; Unlike loop-test.lisp (hermetic, no disk), this driver runs the genuine
;;; persistence path — save-session -> remember -> $HOME/.rusty/memory.lisp and
;;; save-response -> $HOME/.loop/responses/. run_tests.sh runs it under a
;;; THROWAWAY $HOME and checks that loop only ADDED its own loop.* keys, leaving
;;; every pre-existing line in memory.lisp byte-identical. The one impurity we
;;; drop is the network: the advisor already fails closed to "continue" with no
;;; server, and we make that explicit so the run is deterministic and offline.

(load "loop-core.lisp")
(load "loop-questions.lisp")

;; Advisor without a live model degrades to "continue" anyway; pin it so the
;; run never reaches for localhost and is byte-stable turn to turn.
(define (llm-advise session transcript) "continue")

(let ((r (start-session "IntegrityTest")))
  (loop-turn (nth r 0) "a childhood by the river")
  ;; reload from disk each turn, exactly as a resumed session would
  (let* ((id (session-id (nth r 0)))
         (s1 (load-session id)))
    (loop-turn s1 "my mother's hands, flour to the wrist")
    (let ((s2 (load-session id)))
      (loop-turn s2 "the year everything changed")
      (println (str "DRIVE-OK " id)))))
