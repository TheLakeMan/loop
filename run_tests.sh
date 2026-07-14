#!/usr/bin/env bash
# Golden-file test runner for loop. Deterministic — no LLM, no disk, no clock.
set -u

RUSTY="${RUSTY:-rusty}"
if ! command -v "$RUSTY" >/dev/null 2>&1; then
  echo "error: '$RUSTY' not found on PATH." >&2
  echo "Install it:  cd ~/projects/artifacts/rusty && cargo install --path . --bin rusty --root ~/.local" >&2
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

if [ "$fail" -eq 0 ]; then
  echo "🎉 ALL PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$fail"
