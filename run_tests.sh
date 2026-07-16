#!/usr/bin/env bash
# Test runner for loop.
#   1. loop-test.lisp  — hermetic golden (no LLM, no disk, no clock).
#   2. integrity check — runs the REAL persistence path under a THROWAWAY $HOME
#      and proves a session only ADDS loop.* keys, never altering pre-existing
#      memory. The real ~/.rusty/memory.lisp is never touched.
set -u

RUSTY="${RUSTY:-rusty}"
if ! command -v "$RUSTY" >/dev/null 2>&1; then
  echo "error: '$RUSTY' not found on PATH." >&2
  echo "Install it:  git clone https://github.com/TheLakeMan/rusty && cd rusty && cargo install --path . --bin rusty --root ~/.local" >&2
  exit 1
fi

cd "$(dirname "$0")"
fail=0

run_test() {
  local test_file="$1" expected="$2" label="$3"
  if "$RUSTY" "$test_file" 2>&1 | diff - "$expected" >/dev/null 2>&1; then
    echo "✅  $test_file ($label)"
  else
    echo "❌  $test_file ($label)"
    "$RUSTY" "$test_file" 2>&1 | diff - "$expected" | head -20
    fail=1
  fi
}

run_test loop-test.lisp expected_loop.txt "memory vessel — deterministic, no LLM"

# ── Integrity check: a real session must not alter pre-existing memory ─────────
# Seeds a throwaway $HOME/.rusty/memory.lisp with identity lines that are NOT
# loop's, drives a genuine 3-turn session on disk, and asserts the seeded block
# is byte-identical afterward and every added line is loop.*-namespaced.
integrity_check() {
  local label="integrity — real session only adds loop.* keys (throwaway HOME)"
  local th; th="$(mktemp -d "${TMPDIR:-/tmp}/loop-integrity-XXXXXX")"
  case "$th" in /tmp/*|"${TMPDIR%/}"/*) ;; *) echo "❌  $label (unsafe tmp: $th)"; fail=1; return;; esac
  mkdir -p "$th/.rusty"
  local mem="$th/.rusty/memory.lisp"
  cat > "$mem" <<'SEED'
(define my-name "Nick")
(define brother "In memory of my brother.")
(define favorite-number "7")
SEED
  local seed_lines; seed_lines="$(wc -l < "$mem")"
  local before; before="$(cat "$mem")"

  local out; out="$(HOME="$th" "$RUSTY" loop-integrity-drive.lisp 2>&1)"

  local ok=1
  # (a) the session actually ran the real path
  printf '%s\n' "$out" | grep -q "DRIVE-OK" || { echo "   drive did not complete"; ok=0; }
  # (b) the seeded identity block is byte-identical and still at the top
  [ "$(head -n "$seed_lines" "$mem")" = "$before" ] || { echo "   pre-existing memory was altered"; ok=0; }
  # (c) every line loop added is loop.*-namespaced (nothing else was written)
  local added; added="$(tail -n +"$((seed_lines + 1))" "$mem" | grep -c -vE '^\(define loop\.' || true)"
  [ "$added" -eq 0 ] || { echo "   $added non-loop line(s) written to memory"; ok=0; }
  # (d) transcripts landed under the session's own responses dir
  [ "$(ls "$th/.loop/responses/" 2>/dev/null | wc -l)" -eq 3 ] || { echo "   expected 3 response files"; ok=0; }

  rm -rf "$th"
  if [ "$ok" -eq 1 ]; then echo "✅  $label"; else echo "❌  $label"; fail=1; fi
}
integrity_check

# ── Hash check: the integrity report is honest, and it BITES ───────────────────
# Drives a real session on disk, then asks (loop-integrity id) three things:
# an untouched session reports "intact"; an EDITED transcript reports "changed";
# a DELETED one reports "changed" too. The last two are the point — a check that
# always said "intact" would satisfy the first assertion forever.
hash_check() {
  local label="integrity hashes — intact when untouched, changed when tampered"
  local th; th="$(mktemp -d "${TMPDIR:-/tmp}/loop-hash-XXXXXX")"
  case "$th" in /tmp/*|"${TMPDIR%/}"/*) ;; *) echo "❌  $label (unsafe tmp: $th)"; fail=1; return;; esac
  mkdir -p "$th/.rusty"

  HOME="$th" "$RUSTY" loop-integrity-drive.lisp >/dev/null 2>&1

  verdict() { HOME="$th" "$RUSTY" loop-integrity-verify.lisp 2>&1 \
                | grep '^VERDICT ' | head -1 | cut -d' ' -f2; }

  local ok=1 v
  # (a) an untouched session vouches for every response it wrote
  v="$(verdict)"
  [ "$v" = "intact" ] || { echo "   untouched session reported '$v', expected intact"; ok=0; }

  # (b) edit one stored transcript — one byte is enough
  local victim; victim="$(ls "$th"/.loop/responses/*.txt 2>/dev/null | head -1)"
  if [ -z "$victim" ]; then
    echo "   no transcript to tamper with"; ok=0
  else
    printf 'x' >> "$victim"
    v="$(verdict)"
    [ "$v" = "changed" ] || { echo "   edited transcript reported '$v', expected changed"; ok=0; }
    # (c) delete it outright — a vanished transcript is a change, not a silence
    rm -f "$victim"
    v="$(verdict)"
    [ "$v" = "changed" ] || { echo "   deleted transcript reported '$v', expected changed"; ok=0; }
  fi

  rm -rf "$th"
  if [ "$ok" -eq 1 ]; then echo "✅  $label"; else echo "❌  $label"; fail=1; fi
}
hash_check

if [ "$fail" -eq 0 ]; then
  echo "🎉 ALL PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$fail"
