;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later

;; ─────────────────────────────────────────────────────────────────────────────
;; loop-core.lisp — Loop Interview Engine v0.3.0
;; ─────────────────────────────────────────────────────────────────────────────

(define LOOP-VERSION "0.4.0")
(define MAX-FOLLOW-UPS 3)


;; ── Utilities ─────────────────────────────────────────────────────────────────

(define (current-unix-time)
  (string->number (shell "printf '%s' $(date +%s)")))

;; Substring search and delimiter split use Rusty's native builtins
;; (string-contains? / string-split, since 0.26.0). Verified equivalent to
;; the former hand-rolled versions for loop's usage: (string-contains? hay
;; needle) matches the old arg order, and (string-split "a|b|c" "|") →
;; ("a" "b" "c") — the exact asked-list round-trip in save/load-session.

(define (list-contains? lst item)
  (not (null? (filter (lambda (x) (equal? x item)) lst))))

;; Strip a single trailing newline if present
(define (chomp s)
  (let ((len (string-length s)))
    (if (and (> len 0) (equal? (substring s (- len 1) len) "\n"))
      (substring s 0 (- len 1))
      s)))


;; ── Directories ───────────────────────────────────────────────────────────────
;; Rusty has no native env/home builtin, so $HOME is resolved with a single
;; minimal shell call (the only shell-out in the persistence path). Directory
;; creation and path building are otherwise fully native.

(define (loop-home)
  (chomp (shell "printf '%s' $HOME")))

(define (ensure-dirs)
  ;; dir-create makes parent dirs, so ~/.loop is created implicitly.
  (let ((base (str (loop-home) "/.loop")))
    (dir-create (str base "/sessions"))
    (dir-create (str base "/responses"))))

(define (responses-dir)
  (str (loop-home) "/.loop/responses"))


;; ── Data constructors / accessors ─────────────────────────────────────────────

(define (make-question id category text follow-ups)
  (list id category text follow-ups))

(define (question-id q)         (nth q 0))
(define (question-category q)   (nth q 1))
(define (question-text q)       (nth q 2))
(define (question-follow-ups q) (nth q 3))

(define (make-session id subject)
  (list id subject (current-unix-time) "active" "" "" 0 (list)))

;; session fields: id subject started status category qid depth asked
(define (session-id s)               (nth s 0))
(define (session-subject s)          (nth s 1))
(define (session-started-at s)       (nth s 2))
(define (session-status s)           (nth s 3))
(define (session-current-category s) (nth s 4))
(define (session-current-qid s)      (nth s 5))
(define (session-follow-up-depth s)  (nth s 6))
(define (session-asked-ids s)        (nth s 7))

(define (session-set s field value)
  (let ((id      (session-id s))
        (subject (session-subject s))
        (started (session-started-at s))
        (status  (session-status s))
        (cat     (session-current-category s))
        (qid     (session-current-qid s))
        (depth   (session-follow-up-depth s))
        (asked   (session-asked-ids s)))
    (list
      id subject started
      (if (equal? field "status")   value status)
      (if (equal? field "category") value cat)
      (if (equal? field "qid")      value qid)
      (if (equal? field "depth")    value depth)
      (if (equal? field "asked")    value asked))))


;; ── Persistence ───────────────────────────────────────────────────────────────
;; Session navigation state → memory.lisp (all controlled strings, no user text)
;; Response transcripts     → $HOME/.loop/responses/ (one file per response)

(define (skey id field) (str "loop." id "." field))

;; Where a response lands, and where its hash is remembered. Both derive from
;; the session id + response number, so a check can find a file without a
;; directory listing — a transcript that vanished is then a *missing* verdict
;; rather than a silently shorter list.
(define (response-file id n)
  (str (responses-dir) "/" id "-" (number->string n) ".txt"))

(define (rhash-key id n) (skey id (str "r" (number->string n) ".hash")))

(define (save-session session)
  (ensure-dirs)
  (let* ((id    (session-id session))
         (asked (session-asked-ids session))
         (asked-str (if (null? asked) ""
                      (foldl
                        (lambda (qid acc)
                          (if (equal? acc "") qid (str acc "|" qid)))
                        ""
                        asked))))
    (remember (skey id "subject")  (session-subject session))
    (remember (skey id "started")  (number->string (session-started-at session)))
    (remember (skey id "status")   (session-status session))
    (remember (skey id "category") (session-current-category session))
    (remember (skey id "qid")      (session-current-qid session))
    (remember (skey id "depth")    (number->string (session-follow-up-depth session)))
    (remember (skey id "asked")    asked-str)
    ;; Add to index if new
    (let ((idx (recall "loop.index")))
      (let ((existing (if (nil? idx) "" idx)))
        (if (not (string-contains? existing id))
          (remember "loop.index"
            (if (equal? existing "") id (str existing "|" id))))))
    session))

(define (load-session id)
  (let ((status (recall (skey id "status"))))
    (if (nil? status)
      #f
      (let* ((subject (recall (skey id "subject")))
             (started (let ((s (recall (skey id "started"))))
                        (if (nil? s) 0 (string->number s))))
             (cat     (recall (skey id "category")))
             (qid     (recall (skey id "qid")))
             (depth   (let ((d (recall (skey id "depth"))))
                        (if (nil? d) 0 (string->number d))))
             (asked-str (recall (skey id "asked")))
             (asked   (if (or (nil? asked-str) (equal? asked-str ""))
                        (list)
                        (string-split asked-str "|"))))
        (list id subject started status cat qid depth asked)))))

(define (list-sessions)
  (let ((idx (recall "loop.index")))
    (if (nil? idx) (list)
      (filter (lambda (s) (not (equal? s "")))
              (string-split idx "|")))))

;; Save a response transcript to a file, using Rusty's native file-write
;; (no python3, no shell quoting). Content is identical to the former
;; heredoc body: "question: <id>\ndepth: <n>\n---\n<transcript>\n".
(define (save-response session-id question-id depth transcript)
  (ensure-dirs)
  (let* ((rkey   (skey session-id "rcount"))
         (rcount (let ((r (recall rkey)))
                   (if (nil? r) 0 (string->number r))))
         (fname  (response-file session-id rcount)))
    (file-write fname
      (str "question: " question-id "\n"
           "depth: " (number->string depth) "\n"
           "---\n"
           transcript "\n"))
    ;; Seal it: record what we just wrote, so (loop-integrity id) can later tell
    ;; whether the file still says it. file-hash is Nil if the file can't be read
    ;; back — we'd rather leave the response unsealed and say so than remember a
    ;; Nil as though it were a hash.
    (let ((h (file-hash fname)))
      (if (string? h) (remember (rhash-key session-id rcount) h)))
    (remember rkey (number->string (+ rcount 1)))))


;; ── Integrity ─────────────────────────────────────────────────────────────────
;; Every response is hashed when it is written, so a later check can tell whether
;; the stored transcripts still say what the session recorded.
;;
;; HONEST SCOPE — read this before describing the feature to anyone. This is
;; tamper-EVIDENCE, session-scoped: it proves nothing was *quietly* changed (a
;; stray editor, a bad sync, a half-finished restore). It is NOT unforgeable, and
;; not adversarial crypto: the hashes live in the same memory.lisp the responses
;; are indexed from, so whoever can rewrite a transcript can rewrite its hash in
;; the same breath. Resisting that needs an anchor somewhere they cannot reach,
;; which loop deliberately does not have — it is a local, hermetic vessel.

;; Verdict for one response: ok | changed | missing | unsealed.
;; "unsealed" is absence of evidence, not evidence of change — it means no hash
;; was recorded (e.g. a response written by a loop older than this one), so the
;; check declines to speak for that file rather than guessing.
(define (check-response id n)
  (let* ((fname    (response-file id n))
         (expected (recall (rhash-key id n)))
         (actual   (file-hash fname)))
    (list fname
      (cond
        ((nil? expected)          "unsealed")
        ((nil? actual)            "missing")
        ((equal? expected actual) "ok")
        (else                     "changed")))))

(define (response-count id)
  (let ((r (recall (skey id "rcount"))))
    (if (nil? r) 0 (string->number r))))

;; (loop-integrity id) -> (overall rows), rows = ((filename verdict) ...).
;; Data, not printing — so a caller can act on it. Overall keeps "unsealed"
;; distinct from "intact": a run where some files can't be spoken for is not the
;; same claim as one where every file matched.
(define (loop-integrity id)
  (if (nil? (recall (skey id "status")))
    (list "unknown-session" (list))
    (let* ((rows     (map (lambda (i) (check-response id i))
                          (range 0 (response-count id))))
           (verdicts (map (lambda (r) (nth r 1)) rows)))
      (list
        (cond
          ((or (list-contains? verdicts "changed")
               (list-contains? verdicts "missing")) "changed")
          ((list-contains? verdicts "unsealed")     "unsealed")
          (else                                     "intact"))
        rows))))

;; The human-facing form: prints, returns the overall verdict.
(define (loop-integrity-report id)
  (let* ((result  (loop-integrity id))
         (overall (nth result 0))
         (rows    (nth result 1))
         (n       (number->string (length rows))))
    (print (str "Integrity — session " id))
    (print "")
    (if (null? rows)
      (print "  (no responses recorded)")
      (for-each (lambda (r) (print (str "  " (nth r 1) "\t" (nth r 0)))) rows))
    (print "")
    (print
      (cond
        ((equal? overall "intact")
         (str n " response(s) still match the hashes written with them."))
        ((equal? overall "changed")
         "At least one response no longer matches what was written here.")
        ((equal? overall "unsealed")
         (str "Nothing looks changed, but some responses have no recorded hash; "
              "those cannot be spoken for."))
        (else (str "No such session: " id))))
    (if (not (null? rows))
      (begin
        (print "")
        (print "This shows whether anything changed quietly. It is not proof")
        (print "against someone who meant to: the hashes live alongside the")
        (print "session, and could be rewritten with it.")))
    overall))


;; ── Question Bank ─────────────────────────────────────────────────────────────

(define QUESTION-BANK (list))

(define CATEGORY-ORDER
  (list "childhood" "family-and-roots" "coming-of-age"
        "love-and-relationships" "work-and-purpose" "beliefs-and-values"
        "hardship-and-resilience" "joy-and-gratitude" "wisdom"
        "legacy-and-mortality"))

(define (get-category-questions cat)
  (filter (lambda (q) (equal? (question-category q) cat)) QUESTION-BANK))

(define (get-question-by-id id)
  (let ((m (filter (lambda (q) (equal? (question-id q) id)) QUESTION-BANK)))
    (if (null? m) #f (nth m 0))))

(define (question-asked? session q)
  (list-contains? (session-asked-ids session) (question-id q)))

(define (next-question session cat)
  (let ((candidates (filter
          (lambda (q) (not (question-asked? session q)))
          (get-category-questions cat))))
    (if (null? candidates) #f (nth candidates 0))))

(define (next-category cat)
  (let ((pos (member cat CATEGORY-ORDER)))
    (if (or (not pos) (null? (cdr pos))) #f (nth pos 1))))

(define (first-category) (nth CATEGORY-ORDER 0))


;; ── Navigation ────────────────────────────────────────────────────────────────
;; Key fix: we only mark a question as ASKED when we are DONE with it
;; (moving to a new question or category). During follow-ups we stay
;; on the same question — it is NOT added to asked-ids until we leave it.

(define (advance-session session transcript advice)
  (let* ((cur-qid (session-current-qid session))
         (depth   (session-follow-up-depth session))
         (cur-q   (get-question-by-id cur-qid))
         (fups    (if cur-q (question-follow-ups cur-q) (list))))

    ;; Always save the response text to file
    (save-response (session-id session) cur-qid depth transcript)

    (cond
      ;; Drill a follow-up ONLY when the advisor judged this response worth
      ;; going deeper (and there is room). "continue" skips any remaining
      ;; follow-ups and moves on; the question is not marked asked while we're
      ;; still drilling it.
      ((and (equal? advice "follow-up")
            (< depth MAX-FOLLOW-UPS)
            (not (null? fups))
            (< depth (length fups)))
       (list (session-set session "depth" (+ depth 1))
             (nth fups depth)))

      ;; Done with this question — mark as asked, find next
      (else
       (let* ((new-asked (if (list-contains? (session-asked-ids session) cur-qid)
                           (session-asked-ids session)
                           (append (session-asked-ids session) (list cur-qid))))
              (s  (session-set session "asked" new-asked))
              (s  (session-set s "depth" 0))
              (cat (session-current-category s))
              (next-q (next-question s cat)))
         (if next-q
           ;; Next question in same category
           (list (session-set s "qid" (question-id next-q))
                 (question-text next-q))
           ;; Try next category
           (let ((next-cat (next-category cat)))
             (if next-cat
               (let* ((s2  (session-set s "category" next-cat))
                      (nq  (next-question s2 next-cat)))
                 (if nq
                   (list (session-set s2 "qid" (question-id nq))
                         (str "Let's move on. " (question-text nq)))
                   (list (session-set s "status" "complete")
                         (loop-closing s))))
               (list (session-set s "status" "complete")
                     (loop-closing s))))))))))


;; ── LLM Advisor ───────────────────────────────────────────────────────────────

(define (llm-advise session transcript)
  (let* ((cur-q  (get-question-by-id (session-current-qid session)))
         (q-text (if cur-q (question-text cur-q) ""))
         (depth  (session-follow-up-depth session))
         (prompt (str
           "You are an advisor for a life story interview.\n"
           "Question asked: \"" q-text "\"\n"
           "Person responded: \"" transcript "\"\n"
           "Current follow-up depth: " (number->string depth)
           " of " (number->string MAX-FOLLOW-UPS) "\n\n"
           "Reply with ONE word only:\n"
           "  follow-up = emotional depth worth exploring further\n"
           "  continue  = response complete, move to next question\n"
           "  complete  = person seems done for today\n"
           "One word:")))
    ;; 2000 tokens, not ~10: reasoning models think before the one-word
    ;; answer lands in content (typically ~270 tokens on a local 9B, but
    ;; occasionally past 1000), and a too-small budget truncates mid-thought.
    ;; Non-reasoning models stop right after the word, so headroom is free.
    ;; An advisor failure (truncation, timeout, server down) must never end
    ;; a live telling — default to "continue" and let the interview go on.
    (let ((raw (try-catch (llm prompt 0.2 2000) (e) "continue")))
      (cond
        ((string-contains? raw "follow") "follow-up")
        ((string-contains? raw "complete") "complete")
        (else "continue")))))


;; ── Main turn ─────────────────────────────────────────────────────────────────

(define (loop-turn session transcript)
  (if (equal? (session-status session) "complete")
    (list session (loop-closing session))
    (let ((advice (llm-advise session transcript)))
      (let ((result
        (if (equal? advice "complete")
          ;; Their last words still belong in the transcript — save before
          ;; closing, or the response that ended the telling is lost.
          (begin
            (save-response (session-id session)
                           (session-current-qid session)
                           (session-follow-up-depth session)
                           transcript)
            (list (session-set session "status" "complete")
                  (loop-closing session)))
          (advance-session session transcript advice))))
        (save-session (nth result 0))
        result))))


;; ── Session start / resume ────────────────────────────────────────────────────

(define (start-session subject)
  (let* ((id      (str "loop-" subject "-" (number->string (current-unix-time))))
         (session (make-session id subject))
         (cat     (first-category))
         (first-q (next-question session cat)))
    (if first-q
      (let* ((s (session-set session "category" cat))
             (s (session-set s "qid" (question-id first-q))))
        (save-session s)
        (list s (question-text first-q)))
      (list session "No questions loaded. Run: (load \"loop-questions.lisp\")"))))

(define (pending-question session)
  ;; Returns the text of the question currently waiting to be answered.
  ;; If depth > 0 we're mid-follow-up; show the last follow-up asked.
  (let* ((cur-q  (get-question-by-id (session-current-qid session)))
         (depth  (session-follow-up-depth session))
         (fups   (if cur-q (question-follow-ups cur-q) (list))))
    (cond
      ((not cur-q) "Let's continue where we left off.")
      ((= depth 0) (question-text cur-q))
      ((> depth 0)
       (let ((fup-idx (- depth 1)))
         (if (< fup-idx (length fups))
           (nth fups fup-idx)
           (question-text cur-q))))
      (else (question-text cur-q)))))

(define (resume-session id)
  (let ((session (load-session id)))
    (if session
      (list session
        (str "Welcome back"
             (if (string? (session-subject session))
               (str ", " (session-subject session)) "")
             ". We were here:\n\n"
             (pending-question session)))
      (let ((known (list-sessions)))
        (list #f (str "Session not found: " id
                      (if (null? known) ""
                        (str "\nKnown sessions: " (str known)))))))))

(define (pause-session session)
  (let ((s (session-set session "status" "paused")))
    (save-session s)
    (print (str "Paused. Resume with: (loop-resume \""
                (session-id session) "\")"))))


;; ── Simple REPL interface ─────────────────────────────────────────────────────

(define *session* #f)

(define (loop-start name)
  (let ((result (start-session name)))
    (set! *session* (nth result 0))
    (print "")
    (print (nth result 1))
    (print "")
    (print "; (loop-say \"what they said\") to respond")))

(define (loop-say transcript)
  (if (not *session*)
    (print "No active session. Use: (loop-start \"Name\")")
    (let ((result (loop-turn *session* transcript)))
      (set! *session* (nth result 0))
      (print "")
      (print (nth result 1))
      (print "")
      (if (equal? (session-status *session*) "complete")
        (print "; Session complete.")
        (print "; (loop-say \"...\") | (loop-pause) | (loop-status)")))))

(define (loop-pause)
  (if *session*
    (begin (pause-session *session*) (set! *session* #f))
    (print "No active session.")))

(define (loop-resume id)
  (let ((result (resume-session id)))
    (if (nth result 0)
      (begin
        (set! *session* (nth result 0))
        (print "") (print (nth result 1)) (print "")
        (print "; (loop-say \"...\") to continue"))
      (print (nth result 1)))))

(define (loop-status)
  (if *session*
    (begin
      (print (str "Subject:         " (session-subject *session*)))
      (print (str "Category:        " (session-current-category *session*)))
      (print (str "Question:        " (session-current-qid *session*)))
      (print (str "Follow-up depth: " (number->string (session-follow-up-depth *session*))))
      (print (str "Status:          " (session-status *session*)))
      (print (str "Questions asked: " (number->string (length (session-asked-ids *session*)))))
      (print (str "Session ID:      " (session-id *session*))))
    (print "No active session.")))

(define (loop-sessions)
  (let ((ids (list-sessions)))
    (if (null? ids)
      (print "No sessions found.")
      (for-each
        (lambda (id)
          (let ((s (load-session id)))
            (if s
              (print (str "  " id
                          "\n    Subject: " (session-subject s)
                          "  Status: " (session-status s)
                          "  Asked: " (number->string (length (session-asked-ids s)))))
              (print (str "  " id " (unreadable)")))))
        ids))))


;; ── Closing ───────────────────────────────────────────────────────────────────

(define (loop-closing session)
  (str "Thank you, " (session-subject session) ". "
       "What you've shared today is a gift. "
       "The people who love you will carry this with them always."))

(print (str "Loop v" LOOP-VERSION " core loaded."))


;; ── Chat mode ─────────────────────────────────────────────────────────────────
;; Replaces (loop-say "...") with a natural prompt where you just type.
;; Uses shell's `read` which inherits stdin from the terminal.

(define (loop-chat)
  (if (not *session*)
    (print "No active session. Start one with: (loop-start \"Name\")")
    (begin
      (print "")
      (print "┌─────────────────────────────────────────┐")
      (print "│  Loop Chat Mode                         │")
      (print "│  Type your response and press Enter.    │")
      (print "│  Type  quit  to exit chat mode.         │")
      (print "└─────────────────────────────────────────┘")
      (print "")
      (let go ()
        (if (equal? (session-status *session*) "complete")
          (print "[ Session complete ]")
          (let ((input (chomp (shell "printf 'You: ' >&2 && IFS= read -r line && printf '%s' \"$line\""))))
            (cond
              ((or (equal? input "quit") (equal? input "exit") (equal? input ""))
               (print "")
               (print "Exiting chat mode. Session saved."))
              (else
               (let ((result (loop-turn *session* input)))
                 (set! *session* (nth result 0))
                 (print "")
                 (print (str "Loop: " (nth result 1)))
                 (print "")
                 (go))))))))))
