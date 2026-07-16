;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later

;; ─────────────────────────────────────────────────────────────────────────────
;; loop-test.lisp — Hermetic, deterministic golden test for the Loop engine.
;;
;; HERMETIC BY CONSTRUCTION: after loading the real engine we REDEFINE every
;; impure/nondeterministic function it can reach (clock, LLM advisor,
;; remember/recall, save-response, dir helpers) with pure in-memory stubs.
;; The committed test touches NO real files, NO shell, NO LLM. The engine's own
;; functions call our stubs because Lisp resolves free identifiers at call time.
;; ─────────────────────────────────────────────────────────────────────────────

(load "loop-core.lisp")
(load "loop-questions.lisp")
(load "loop-soul.lisp")


;; ── Stubs: replace every impurity source the test can reach ─────────────────────

;; Fixed clock → deterministic session IDs / started-at.
(define (current-unix-time) 1000000)

;; In-memory key/value store replacing remember/recall (which hit ~/.rusty/memory.lisp).
;; Contract preserved exactly: recall returns Nil on a miss, the stored string on a hit.
(define *mem* (list))
(define (remember key val)
  (set! *mem* (cons (list key val) *mem*))
  val)
(define (recall key)
  ;; newest write wins (cons-to-front), Nil on miss — matches the real builtin
  (let ((hit (filter (lambda (p) (equal? (nth p 0) key)) *mem*)))
    (if (null? hit) (nil) (nth (nth hit 0) 1))))

;; Scripted LLM advisor: pop one decision per call; default "continue" when empty.
(define *advice-script* (list))
(define (llm-advise session transcript)
  (if (null? *advice-script*)
    "continue"
    (let ((a (nth *advice-script* 0)))
      (set! *advice-script* (cdr *advice-script*))
      a)))

;; Capture responses in memory (in order) instead of writing files via python3/shell.
(define *responses* (list))
(define (save-response session-id question-id depth transcript)
  (set! *responses*
    (append *responses* (list (list question-id depth transcript))))
  #t)

;; Directory helpers: no shell, ever.
(define (ensure-dirs) #t)
(define (responses-dir) "/fake/loop/responses")


;; ── Soul-layer stubs (portrait + witness): no disk, no LLM, no shell ────────────

;; Portrait's LLM seam: capture the prompt, count calls, return a fixed string.
;; (We stub the seam, not `llm` — `llm` is an unshadowable special form.)
(define *llm-prompt* "")
(define *llm-calls* 0)
(define (loop-portrait-llm prompt)
  (set! *llm-calls* (+ *llm-calls* 1))
  (set! *llm-prompt* prompt)
  "PORTRAIT-STUB")

;; Fixed transcript so the portrait needs no file reads / dir-list.
(define (session-transcript-text id)
  "CANNED-TRANSCRIPT: the river behind the house, and my mother's hands.")

;; Capture writes in memory instead of touching disk.
(define *writes* (list))
(define (file-write path content)
  (set! *writes* (cons (list path content) *writes*))
  #t)

;; Soul dir helpers: fixed fake paths, no shell, no dir-create.
(define (ensure-soul-dirs) #t)
(define (portraits-dir) "/fake/loop/portraits")
(define (witness-dir)   "/fake/loop/witness")

;; Fake filesystem for the integrity check's file-hash seam: a path -> hash
;; table. Stubbing file-hash (not the hash values themselves) is the point —
;; the verdict logic is what's under test here, and that real SHA-256 is real
;; SHA-256 is Rusty's own known-answer test to make, not loop's. A path with no
;; entry hashes to Nil, exactly as the builtin does for an unreadable file.
(define *fake-files* (list))
(define (fake-file! path hash)
  (set! *fake-files* (cons (list path hash) *fake-files*)))
(define (file-hash path)
  (let ((hit (filter (lambda (p) (equal? (nth p 0) path)) *fake-files*)))
    (if (null? hit) (nil) (nth (nth hit 0) 1))))

(define (reset-all)
  (set! *mem* (list))
  (set! *responses* (list))
  (set! *advice-script* (list))
  (set! *writes* (list))
  (set! *fake-files* (list))
  (set! *llm-prompt* "")
  (set! *llm-calls* 0))


;; ── Assertion helpers (print label on pass, divide-by-zero abort on fail) ───────

(define (assert-equal expected actual label)
  (if (equal? expected actual)
    (print label)
    (begin (print (str "FAIL " label)) (/ 1 0))))

(define (assert-true value label)
  (if value
    (print label)
    (begin (print (str "FAIL " label)) (/ 1 0))))

(define (all-unique? lst)
  (cond
    ((null? lst) #t)
    ((list-contains? (cdr lst) (nth lst 0)) #f)
    (else (all-unique? (cdr lst)))))

;; Run n turns (default/scripted advisor), asserting asked-ids stays duplicate-free.
(define (drive-check session n)
  (if (= n 0)
    session
    (let* ((r (loop-turn session "resp"))
           (s (nth r 0)))
      (if (not (all-unique? (session-asked-ids s))) (/ 1 0) #t)
      (drive-check s (- n 1)))))


;; ── Invariant 1: Start ──────────────────────────────────────────────────────────
(reset-all)
(let* ((r  (start-session "TestName"))
       (s  (nth r 0))
       (q  (nth r 1)))
  (assert-equal "childhood" (session-current-category s) "1a start category is childhood")
  ;; first question is the first childhood question in the bank
  (assert-equal (question-id (nth (get-category-questions "childhood") 0))
                (session-current-qid s) "1b start qid is first childhood question")
  (assert-equal (question-text q-childhood-001) q "1c start prompt is that question's text")
  (assert-equal "loop-TestName-1000000" (session-id s) "1d start session id is deterministic"))


;; ── Invariant 2: Follow-up depth (script "follow-up") ───────────────────────────
(reset-all)
(set! *advice-script* (list "follow-up" "follow-up" "follow-up" "follow-up"))
(let* ((r0 (start-session "Depth"))
       (s0 (nth r0 0))
       (r1 (loop-turn s0 "a")) (s1 (nth r1 0))
       (r2 (loop-turn s1 "b")) (s2 (nth r2 0))
       (r3 (loop-turn s2 "c")) (s3 (nth r3 0))
       (r4 (loop-turn s3 "d")) (s4 (nth r4 0)))
  (assert-equal 1 (session-follow-up-depth s1) "2a depth 1 after first follow-up")
  (assert-equal 2 (session-follow-up-depth s2) "2b depth 2")
  (assert-equal 3 (session-follow-up-depth s3) "2c depth 3 (at cap)")
  (assert-equal "childhood-001" (session-current-qid s3) "2d qid unchanged through follow-ups")
  (assert-true (not (list-contains? (session-asked-ids s3) "childhood-001"))
               "2e question not marked asked during follow-ups")
  ;; at the cap, next turn moves on AND marks the question asked
  (assert-equal 0 (session-follow-up-depth s4) "2f depth resets after cap")
  (assert-equal "childhood-002" (session-current-qid s4) "2g moves to next question at cap")
  (assert-true (list-contains? (session-asked-ids s4) "childhood-001")
               "2h question now marked asked"))


;; ── Invariant 3: No repeats ─────────────────────────────────────────────────────
(reset-all)
(let* ((r0 (start-session "NoRepeat"))
       (s0 (nth r0 0))
       (final (drive-check s0 10)))
  (assert-true (all-unique? (session-asked-ids final)) "3a asked-ids never contains a duplicate"))
;; next-question directly skips an already-asked question
(reset-all)
(let* ((r0 (start-session "Skip"))
       (s0 (nth r0 0))
       (s1 (session-set s0 "asked" (list "childhood-001")))
       (nq (next-question s1 "childhood")))
  (assert-equal "childhood-002" (question-id nq) "3b next-question skips an asked question"))


;; ── Invariant 4: Response capture (exactly one per turn, in order) ──────────────
(reset-all)
(set! *advice-script* (list "follow-up" "follow-up" "follow-up" "follow-up"))
(let* ((r0 (start-session "Capture"))
       (s0 (nth r0 0))
       (s1 (nth (loop-turn s0 "resp-1") 0))
       (s2 (nth (loop-turn s1 "resp-2") 0))
       (s3 (nth (loop-turn s2 "resp-3") 0))
       (s4 (nth (loop-turn s3 "resp-4") 0)))
  (assert-equal 4 (length *responses*) "4a one response captured per turn")
  (assert-equal
    (list (list "childhood-001" 0 "resp-1")
          (list "childhood-001" 1 "resp-2")
          (list "childhood-001" 2 "resp-3")
          (list "childhood-001" 3 "resp-4"))
    *responses*
    "4b responses captured in order with qid+depth"))


;; ── Invariant 5: Category advance ───────────────────────────────────────────────
;; Exhaust the whole childhood category (default "continue"); the turn that crosses
;; into family-and-roots returns text beginning with "Let's move on.".
(reset-all)
(let* ((r0 (start-session "Advance"))
       (s0 (nth r0 0)))
  ;; With the advisor saying "continue" (the default), follow-ups are skipped,
  ;; so childhood's 3 questions take one turn each — the 3rd turn crosses.
  (let* ((s2 (drive-check s0 2))
         (r3 (loop-turn s2 "resp"))
         (s10 (nth r3 0))
         (text (nth r3 1)))
    (assert-equal "family-and-roots" (session-current-category s10)
                  "5a advanced to next category in CATEGORY-ORDER")
    (assert-equal "Let's move on." (substring text 0 14)
                  "5b boundary text begins with \"Let's move on.\"")))


;; ── Invariant 6: Pause/resume round-trip (depth 0 AND depth>0) ──────────────────
;; Case A: depth 0
(reset-all)
(let* ((r0 (start-session "PauseA"))
       (s0 (nth r0 0)))
  (pause-session s0)                         ; saves status=paused to *mem*
  (let ((ld (load-session (session-id s0))))
    (assert-equal (session-subject s0)          (session-subject ld)          "6a-1 subject round-trips")
    (assert-equal "paused"                       (session-status ld)          "6a-2 status is paused")
    (assert-equal (session-current-category s0)  (session-current-category ld) "6a-3 category round-trips")
    (assert-equal (session-current-qid s0)       (session-current-qid ld)      "6a-4 qid round-trips")
    (assert-equal 0                              (session-follow-up-depth ld)  "6a-5 depth round-trips (0)")
    (assert-equal (session-asked-ids s0)         (session-asked-ids ld)        "6a-6 asked list round-trips")
    (assert-equal (question-text q-childhood-001) (pending-question ld)
                  "6a-7 pending-question at depth 0 is the core question")))

;; Case B: depth > 0 (mid follow-up)
(reset-all)
(set! *advice-script* (list "follow-up" "follow-up"))
(let* ((r0 (start-session "PauseB"))
       (s0 (nth r0 0))
       (s1 (nth (loop-turn s0 "x") 0))
       (s2 (nth (loop-turn s1 "y") 0)))     ; depth 2, still on childhood-001
  (pause-session s2)
  (let ((ld (load-session (session-id s2))))
    (assert-equal "paused"                  (session-status ld)           "6b-1 status is paused")
    (assert-equal "childhood-001"           (session-current-qid ld)      "6b-2 qid round-trips")
    (assert-equal "childhood"               (session-current-category ld) "6b-3 category round-trips")
    (assert-equal 2                         (session-follow-up-depth ld)  "6b-4 depth round-trips (2)")
    (assert-equal (session-asked-ids s2)    (session-asked-ids ld)        "6b-5 asked list round-trips")
    (assert-equal (nth (question-follow-ups q-childhood-001) 1) (pending-question ld)
                  "6b-6 pending-question at depth 2 is the mid follow-up")))


;; ── Invariant 7: Rest ("done for today" is resumable, not the end) ─────────────
;; The advisor's "complete" verdict means the person is done FOR TODAY — a RESTING
;; point, not the end of the telling. The session must stay resumable (status
;; "resting", never sealed "complete"), advance past the answered question so a
;; later resume starts on a fresh one, show the rest closing (distinct from the
;; final one), and still keep the last words. Only exhausting the whole bank is a
;; true end (invariant 15).
(reset-all)
(set! *advice-script* (list "complete"))
(let* ((r0 (start-session "Rest"))
       (s0 (nth r0 0))
       (r1 (loop-turn s0 "I'm tired now"))
       (s1 (nth r1 0))
       (msg (nth r1 1)))
  (assert-equal "resting" (session-status s1) "7a done-for-today is 'resting', not 'complete'")
  (assert-equal (loop-rest-closing s1) msg "7b message is the rest closing")
  (assert-true (not (equal? (loop-rest-closing s1) (loop-closing s1)))
               "7c rest closing and final closing are distinct")
  (assert-equal "childhood-002" (session-current-qid s1)
                "7d advanced past the answered question — a resume starts fresh")
  (assert-true (list-contains? (session-asked-ids s1) "childhood-001")
               "7e the answered question is marked asked")
  ;; Their last words must reach the transcript — resting must not drop them,
  ;; and must save exactly once (the advance does the single save).
  (assert-equal 1 (length *responses*) "7f final words saved exactly once")
  (assert-equal "I'm tired now" (nth (nth *responses* 0) 2) "7g final words kept verbatim"))


;; ── Invariant 7b: A rested session resumes and continues ────────────────────────
;; Resuming reactivates (status back to "active") without needing a turn, and the
;; next answer carries on normally — the telling paused for the day, not ended.
(reset-all)
(set! *advice-script* (list "complete"))
(let* ((r0     (start-session "Return"))
       (s0     (nth r0 0))
       (rested (nth (loop-turn s0 "enough for today") 0)))
  (assert-equal "resting" (session-status rested) "7b-1 rested after a 'complete' verdict")
  (let ((woken (nth (resume-session (session-id rested)) 0)))
    (assert-equal "active" (session-status woken) "7b-2 resume reactivates a rested session")
    (assert-equal (session-current-qid rested) (session-current-qid woken)
                  "7b-3 resume keeps the fresh question the rest advanced to"))
  ;; Answering a rested session also flips it active (the same-process path).
  (let ((s-next (nth (loop-turn rested "the smell of bread") 0)))
    (assert-equal "active" (session-status s-next)
                  "7b-4 answering a rested session makes it active again")
    (assert-equal "childhood-003" (session-current-qid s-next)
                  "7b-5 the interview proceeds to the next question")))


;; ── Invariant 8: save/load fidelity (field-by-field) ────────────────────────────
;; Build a session with a multi-element asked list, save it, load it, compare.
(reset-all)
(let* ((r0 (start-session "Fidelity"))
       (s0 (nth r0 0))
       (src (drive-check s0 7)))            ; "continue" (default): 7 questions asked across categories
  (save-session src)
  (let ((ld (load-session (session-id src))))
    (assert-equal (session-id src)               (session-id ld)               "8a id")
    (assert-equal (session-subject src)          (session-subject ld)          "8b subject")
    (assert-equal (session-started-at src)       (session-started-at ld)       "8c started-at")
    (assert-equal (session-status src)           (session-status ld)           "8d status")
    (assert-equal (session-current-category src) (session-current-category ld) "8e category")
    (assert-equal (session-current-qid src)      (session-current-qid ld)      "8f qid")
    (assert-equal (session-follow-up-depth src)  (session-follow-up-depth ld)  "8g depth")
    (assert-equal (session-asked-ids src)        (session-asked-ids ld)        "8h asked list")
    (assert-true  (> (length (session-asked-ids ld)) 1) "8i asked list is multi-element (delimiter round-trips)")))


;; ── Invariant 9: the advisor actually gates follow-ups ─────────────────────────
;; childhood-001 HAS follow-ups, but a "continue" verdict must SKIP them and move
;; straight on — this is the whole point of wiring the advisor into advance-session.
;; (Contrast invariant 2, where "follow-up" drills into those same follow-ups.)
(reset-all)
(set! *advice-script* (list "continue"))
(let* ((r0 (start-session "Advisor"))
       (s0 (nth r0 0))
       (r1 (loop-turn s0 "done with this one"))
       (s1 (nth r1 0)))
  (assert-true (> (length (question-follow-ups q-childhood-001)) 0)
               "9a childhood-001 has follow-ups available")
  (assert-equal 0 (session-follow-up-depth s1)
                "9b continue does NOT drill a follow-up")
  (assert-equal "childhood-002" (session-current-qid s1)
                "9c continue moves straight to the next question")
  (assert-true (list-contains? (session-asked-ids s1) "childhood-001")
               "9d question marked asked without drilling"))


;; ── Invariant 10: Portrait (LLM seam stubbed) ───────────────────────────────────
;; With subject + a canned transcript seeded, loop-portrait must build a prompt
;; that carries BOTH the subject and the transcript text into the LLM, write the
;; result to portraits/<id>.txt, and return the model's portrait.
(reset-all)
(remember (skey "loop-Soul-1000000" "subject") "Marguerite")
(let ((p (loop-portrait "loop-Soul-1000000")))
  (assert-true (string-contains? *llm-prompt* "Marguerite")
               "10a portrait prompt carries the subject")
  (assert-true (string-contains? *llm-prompt*
                 "CANNED-TRANSCRIPT: the river behind the house, and my mother's hands.")
               "10b portrait prompt carries the transcript text")
  (assert-equal "/fake/loop/portraits/loop-Soul-1000000.txt"
                (nth (nth *writes* 0) 0)
                "10c portrait written to portraits/<id>.txt")
  (assert-equal "PORTRAIT-STUB" p "10d portrait returns the model's text"))


;; ── Invariant 11: Witness (deterministic, NO LLM) ──────────────────────────────
;; loop-witness writes to witness/<id>.txt, names the subject, states the exchange
;; count, keeps the honest phrases verbatim, and calls no LLM path whatsoever.
(reset-all)
(remember (skey "loop-Soul-1000000" "subject") "Marguerite")
(remember (skey "loop-Soul-1000000" "rcount")  "7")
(let ((w (loop-witness "loop-Soul-1000000")))
  (assert-equal "/fake/loop/witness/loop-Soul-1000000.txt"
                (nth (nth *writes* 0) 0)
                "11a witness written to witness/<id>.txt")
  (assert-true (string-contains? w "Marguerite")        "11b witness names the subject")
  (assert-true (string-contains? w "7")                 "11c witness states the exchange count")
  (assert-true (string-contains? w "keeps no memory")   "11d witness: honest phrase \"keeps no memory\"")
  (assert-true (string-contains? w "shaped none of the story")
               "11e witness: honest phrase \"shaped none of the story\"")
  (assert-equal 0 *llm-calls* "11f witness calls no LLM path"))


;; ── Invariant 12: loop-remember runs portrait then witness for *session* ────────
;; The entry point advertised in loop.lisp — both artifacts written, LLM once.
(reset-all)
(set! *session* (make-session "loop-Soul-1000000" "Marguerite"))
(remember (skey "loop-Soul-1000000" "subject") "Marguerite")
(remember (skey "loop-Soul-1000000" "rcount")  "3")
(loop-remember)
(assert-equal 1 *llm-calls* "12a remember calls the portrait LLM once")
(assert-true (string-contains? *llm-prompt* "Marguerite")
             "12b remember portrait prompt names the subject")
;; *writes* is cons-front: last write is head → witness first in list
(assert-equal "/fake/loop/witness/loop-Soul-1000000.txt"
              (nth (nth *writes* 0) 0)
              "12c remember wrote the witness")
(assert-equal "/fake/loop/portraits/loop-Soul-1000000.txt"
              (nth (nth *writes* 1) 0)
              "12d remember wrote the portrait")
(assert-true (string-contains? (nth (nth *writes* 0) 1) "keeps no memory")
             "12e remember witness text is the honest one")


;; ── Invariant 13: Integrity verdicts, one per response ─────────────────────────
;; Four responses, one of each verdict, so every branch is pinned at once:
;; r0 matches its hash, r1's file changed, r2's file is gone, r3 was never
;; sealed. The rows are positional — a check that reported the right verdicts
;; against the wrong files would be worse than useless.
(reset-all)
(remember (skey "loop-I-1000000" "status") "active")
(remember (skey "loop-I-1000000" "rcount") "4")
(fake-file! "/fake/loop/responses/loop-I-1000000-0.txt" "HASH-A")
(remember (rhash-key "loop-I-1000000" 0) "HASH-A")           ; matches  -> ok
(fake-file! "/fake/loop/responses/loop-I-1000000-1.txt" "HASH-EDITED")
(remember (rhash-key "loop-I-1000000" 1) "HASH-B")           ; differs  -> changed
(remember (rhash-key "loop-I-1000000" 2) "HASH-C")           ; no file  -> missing
(fake-file! "/fake/loop/responses/loop-I-1000000-3.txt" "HASH-D")  ; no hash -> unsealed
(let* ((r    (loop-integrity "loop-I-1000000"))
       (rows (nth r 1)))
  (assert-equal 4 (length rows) "13a one row per recorded response")
  (assert-equal "/fake/loop/responses/loop-I-1000000-0.txt" (nth (nth rows 0) 0)
                "13b rows name the response file they judge")
  (assert-equal "ok"       (nth (nth rows 0) 1) "13c matching response -> ok")
  (assert-equal "changed"  (nth (nth rows 1) 1) "13d edited response -> changed")
  (assert-equal "missing"  (nth (nth rows 2) 1) "13e vanished response -> missing")
  (assert-equal "unsealed" (nth (nth rows 3) 1) "13f unhashed response -> unsealed")
  (assert-equal "changed"  (nth r 0) "13g overall: any change outranks the rest"))

;; ── Invariant 14: overall verdict keeps its three claims apart ─────────────────
;; "intact" is a claim about every response; "unsealed" is absence of evidence,
;; NOT evidence of absence — a run that can't speak for a file must not report
;; intact. "missing" is a change: a deleted transcript is the loudest one.
;; NB: each scenario is built from reset-all rather than by un-remembering a key
;; — `forget` is NOT stubbed here, so calling it would reach the real
;; ~/.rusty/memory.lisp. This test touches no real file, and stays that way.
(define (seal-two-responses)
  (reset-all)
  (remember (skey "loop-I-1000000" "status") "active")
  (remember (skey "loop-I-1000000" "rcount") "2")
  (fake-file! "/fake/loop/responses/loop-I-1000000-0.txt" "H0")
  (remember (rhash-key "loop-I-1000000" 0) "H0")
  (fake-file! "/fake/loop/responses/loop-I-1000000-1.txt" "H1"))

(seal-two-responses)
(remember (rhash-key "loop-I-1000000" 1) "H1")
(assert-equal "intact" (nth (loop-integrity "loop-I-1000000") 0)
              "14a all responses match -> intact")
(seal-two-responses)                     ; r1 sealed by nobody
(assert-equal "unsealed" (nth (loop-integrity "loop-I-1000000") 0)
              "14b one unsealed response -> unsealed, never intact")
(seal-two-responses)
(remember (rhash-key "loop-I-1000000" 1) "H1")
(set! *fake-files* (list (list "/fake/loop/responses/loop-I-1000000-0.txt" "H0")))
(assert-equal "changed" (nth (loop-integrity "loop-I-1000000") 0)
              "14c a deleted transcript is a change, not a silence")
;; A session nobody started is not "intact" — there is nothing to vouch for.
(reset-all)
(assert-equal "unknown-session" (nth (loop-integrity "loop-nope-0") 0)
              "14d unknown session -> unknown-session, not intact")
(assert-equal (list) (nth (loop-integrity "loop-nope-0") 1)
              "14e unknown session reports no rows")


;; ── Invariant 15: Genuine completion — the whole bank answered ─────────────────
;; With the advisor always saying "continue", every question is asked once; the
;; turn that answers the LAST one seals the session "complete" and returns the
;; FINAL closing (loop-closing), NOT a rest. This is the only true end, and the
;; only path that reaches loop-closing — so it is what pins that message.
(reset-all)
(define (drive-until-complete session cap)
  (if (<= cap 0)
    (list session "CAP-HIT")                 ; safety net; the bank is 22 questions
    (let* ((r (loop-turn session "resp"))
           (s (nth r 0)))
      (if (equal? (session-status s) "complete")
        r
        (drive-until-complete s (- cap 1))))))
(let* ((r0    (start-session "Whole"))
       (s0    (nth r0 0))
       (final (drive-until-complete s0 40))
       (fs    (nth final 0))
       (fmsg  (nth final 1)))
  (assert-equal "complete" (session-status fs) "15a answering the last question seals 'complete'")
  (assert-equal (loop-closing fs) fmsg "15b the final message is loop-closing, not a rest")
  (assert-equal 22 (length (session-asked-ids fs)) "15c every one of the 22 questions was asked")
  (assert-true (all-unique? (session-asked-ids fs)) "15d no question asked twice"))


(print "LOOP TESTS PASSED")
