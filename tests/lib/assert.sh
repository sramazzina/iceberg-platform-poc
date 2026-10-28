# Minimal assertion helpers for bash tests. Source this file; do not run it.

FAILURES=0

pass() { echo "  ok   - $1"; }
fail() { echo "  FAIL - $1"; FAILURES=$((FAILURES + 1)); }

# assert_eq ACTUAL EXPECTED MESSAGE
assert_eq() {
  if [[ $1 == "$2" ]]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

# assert_contains HAYSTACK NEEDLE MESSAGE
assert_contains() {
  if [[ $1 == *"$2"* ]]; then pass "$3"; else fail "$3 (missing '$2')"; fi
}

# assert_not_contains HAYSTACK NEEDLE MESSAGE
assert_not_contains() {
  if [[ $1 != *"$2"* ]]; then pass "$3"; else fail "$3 (unexpected '$2')"; fi
}

# finish: exit 1 when at least one assertion failed.
finish() {
  if ((FAILURES > 0)); then
    echo "$FAILURES assertion(s) failed"
    exit 1
  fi
  echo "all assertions passed"
}
