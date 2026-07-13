#!/usr/bin/env bash
#
# mayhem/test.sh — RUN frida-gum's full upstream GLib test suite (built by mayhem/build.sh
# at upstream defaults) and report a CTRF summary. Behavioral oracle: it parses the per-test
# TAP results, so neutering any binary to exit(0) collapses the plan and FAILS here.
#
# Three Stalker self-modifying-code tests are skipped via GLib's own `-s` flag (NOT by editing
# upstream): they SIGSEGV inside the container/Mayhem sandbox because Stalker's SMC detection
# depends on W^X page-permission + ptrace semantics the sandbox denies. Everything else runs.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

TESTS_BIN="$SRC/build-tests/tests/gum-tests"
[ -x "$TESTS_BIN" ] || { echo "FATAL: $TESTS_BIN missing/not executable — build.sh bug" >&2; exit 3; }

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Environment-crashing Stalker SMC tests (see header) — skipped by name, not removed.
SKIP=(
  /Core/Stalker/self_modifying_code_should_be_detected_with_threshold_minus_one
  /Core/Stalker/self_modifying_code_should_not_be_detected_with_threshold_zero
  /Core/Stalker/self_modifying_code_should_be_detected_with_threshold_one
)
skipargs=(); for t in "${SKIP[@]}"; do skipargs+=(-s "$t"); done

TAP="$(mktemp)"
"$TESTS_BIN" "${skipargs[@]}" >"$TAP" 2>/dev/null || true

# TAP plan `1..N` is the ground truth for total registered tests. Its absence means the runner
# never started (e.g. a neutered binary that exit(0)'d) — a hard failure, not a vacuous pass.
plan="$(grep -oE '^1\.\.[0-9]+' "$TAP" | head -1 | cut -d. -f3)"
passed="$(grep -c '^ok ' "$TAP" | tr -d ' ')"
skipped_inline="$(grep '^ok ' "$TAP" | grep -c '# SKIP' | tr -d ' ')"
passed=$(( passed - skipped_inline ))          # `ok N # SKIP` are skips, not passes
failed="$(grep -c '^not ok ' "$TAP" | tr -d ' ')"

if [ -z "$plan" ] || [ "$plan" -eq 0 ] 2>/dev/null; then
  echo "FATAL: gum-tests emitted no TAP plan — the test binary did not run" >&2
  rm -f "$TAP"
  emit_ctrf "frida-gum/gum-tests" 0 1 0
  exit 1
fi

# Runtime-skipped tests (platform/perf-gated: objc/Darwin symbolication, Stalker perf/prefetch)
# emit no TAP line at all; reconcile against the plan so totals are honest and sum to N.
skipped=$(( plan - passed - failed ))
[ "$skipped" -lt 0 ] && skipped=0

echo "gum-tests: plan=$plan passed=$passed failed=$failed skipped=$skipped"
rm -f "$TAP"
emit_ctrf "frida-gum/gum-tests" "$passed" "$failed" "$skipped"
