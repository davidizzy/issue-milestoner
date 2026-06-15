#!/usr/bin/env bash
#
# End-to-end test suite for Issue Milestoner.
#
# Unlike a unit suite that re-implements the logic, this runs the REAL
# assign-milestone.sh as a subprocess with a mocked `gh` on PATH (see
# tests/bin/gh) and fixture API responses (see tests/fixtures). It asserts on
# the script's exit code, its GITHUB_OUTPUT contract, and its log annotations -
# so the behavior under test is exactly what ships.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures"
MOCK_BIN="${SCRIPT_DIR}/bin"
ACTION="${REPO_ROOT}/assign-milestone.sh"

TESTS_PASSED=0
TESTS_FAILED=0

OUTPUT_FILE=""
ACTION_LOG=""
CALL_LOG=""
ACTION_RC=0

echo "🧪 Issue Milestoner — end-to-end suite"
echo "======================================"
echo ""

# --- helpers ----------------------------------------------------------------

pass() { echo "  ✅ PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  ❌ FAIL: $1 — $2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Run the real action with the given inputs. Inputs are passed as env vars by
# the caller; defaults are filled here. The mocked gh serves fixtures named by
# GH_MOCK_ISSUE / GH_MOCK_MILESTONES.
run_action() {
  OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/im_out_XXXXXX")"
  ACTION_LOG="$(mktemp "${TMPDIR:-/tmp}/im_log_XXXXXX")"
  CALL_LOG="$(mktemp "${TMPDIR:-/tmp}/im_calls_XXXXXX")"

  PATH="${MOCK_BIN}:${PATH}" \
  GH_TOKEN="test-token" \
  GITHUB_OUTPUT="${OUTPUT_FILE}" \
  INITIAL_RETRY_DELAY=0 \
  ISSUE_NUMBER="${ISSUE_NUMBER:-7}" \
  REPOSITORY="${REPOSITORY:-acme/widgets}" \
  TARGET_MILESTONE="${TARGET_MILESTONE:-Wishlist}" \
  ISSUE_TYPE="${ISSUE_TYPE:-}" \
  ISSUE_LABEL="${ISSUE_LABEL:-}" \
  GH_MOCK_ISSUE="${GH_MOCK_ISSUE:-}" \
  GH_MOCK_MILESTONES="${GH_MOCK_MILESTONES:-${FIXTURES}/milestones.json}" \
  GH_MOCK_EDIT_RC="${GH_MOCK_EDIT_RC:-0}" \
  GH_MOCK_API_RC="${GH_MOCK_API_RC:-0}" \
  GH_MOCK_API_STDERR="${GH_MOCK_API_STDERR:-}" \
  GH_MOCK_CALL_LOG="${CALL_LOG}" \
    bash "${ACTION}" >"${ACTION_LOG}" 2>&1
  ACTION_RC=$?
}

# Last value wins, matching GitHub Actions output semantics.
get_output() { grep "^$1=" "${OUTPUT_FILE}" | tail -n1 | cut -d= -f2-; }

assert_rc() {
  local want="$1" name="$2"
  if [[ "${ACTION_RC}" -eq "${want}" ]]; then pass "${name} (exit ${want})"
  else fail "${name}" "expected exit ${want}, got ${ACTION_RC}; log: $(<"${ACTION_LOG}")"; fi
}

assert_output() {
  local key="$1" want="$2" name="$3" got
  got="$(get_output "${key}")"
  if [[ "${got}" == "${want}" ]]; then pass "${name} (${key}=${want})"
  else fail "${name}" "expected ${key}='${want}', got '${got}'"; fi
}

assert_log_contains() {
  if grep -qF "$1" "${ACTION_LOG}"; then pass "$2"
  else fail "$2" "log missing: $1"; fi
}

assert_log_excludes() {
  if grep -qF "$1" "${ACTION_LOG}"; then fail "$2" "log unexpectedly contains: $1"
  else pass "$2"; fi
}

assert_call_count() {
  local want="$1" name="$2" got
  got=$(wc -l < "${CALL_LOG}" | tr -d '[:space:]')
  if [[ "${got}" -eq "${want}" ]]; then pass "${name} (${want} gh api call(s))"
  else fail "${name}" "expected ${want} gh api call(s), got ${got}"; fi
}

cleanup_case() { rm -f "${OUTPUT_FILE}" "${ACTION_LOG}" "${CALL_LOG}"; }

# --- tests ------------------------------------------------------------------

test_label_exact_rejects_nearmiss() {
  echo "📝 Label filter is exact (regression: substring matching)"
  ISSUE_LABEL="ui" GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" \
    run_action  # labels are enhancement, build — neither equals "ui"
  assert_rc 0 "near-miss label does not assign"
  assert_output assigned false "near-miss label leaves issue unassigned"
  cleanup_case
}

test_label_exact_matches() {
  echo "📝 Label filter matches an exact label"
  ISSUE_LABEL="enhancement" GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" \
    run_action
  assert_rc 0 "exact label assigns"
  assert_output assigned true "exact label assigns"
  cleanup_case
}

test_milestone_case_insensitive() {
  echo "📝 Target milestone resolves case-insensitively to canonical title"
  TARGET_MILESTONE="wishlist" GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" \
    run_action  # no filters → assigns
  assert_rc 0 "lowercase target assigns"
  assert_output assigned true "lowercase target assigns"
  assert_output milestone "Wishlist" "output reports canonical milestone casing"
  cleanup_case
}

test_milestone_not_found() {
  echo "📝 Unknown milestone fails clearly"
  TARGET_MILESTONE="Ghost" GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" \
    run_action
  assert_rc 1 "unknown milestone exits non-zero"
  assert_output assigned false "unknown milestone leaves issue unassigned"
  assert_log_contains "not found in acme/widgets" "unknown milestone is reported"
  cleanup_case
}

test_already_assigned() {
  echo "📝 Existing milestone is never overwritten"
  GH_MOCK_ISSUE="${FIXTURES}/issue-has-milestone.json" run_action
  assert_rc 0 "already-assigned exits cleanly"
  assert_output assigned false "already-assigned does not reassign"
  assert_output milestone "Backlog" "already-assigned reports current milestone"
  cleanup_case
}

test_type_filter_no_field_is_notice() {
  echo "📝 Type filter on a typeless issue is a notice, not an error"
  ISSUE_TYPE="bug" GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" run_action
  assert_rc 0 "typeless + type filter exits cleanly"
  assert_output assigned false "typeless + type filter does not assign"
  assert_log_contains "::notice::Issue type filter" "typeless type filter logs a notice"
  assert_log_excludes "::error::Issue type filter" "typeless type filter is not an error"
  cleanup_case
}

test_type_filter_match() {
  echo "📝 Type filter matches the issue's type (case-insensitive)"
  ISSUE_TYPE="bug" GH_MOCK_ISSUE="${FIXTURES}/issue-typed-bug.json" run_action
  assert_rc 0 "matching type assigns"
  assert_output assigned true "matching type assigns"
  cleanup_case
}

test_type_filter_mismatch() {
  echo "📝 Type filter that does not match skips assignment"
  ISSUE_TYPE="feature" GH_MOCK_ISSUE="${FIXTURES}/issue-typed-bug.json" run_action
  assert_rc 0 "mismatched type exits cleanly"
  assert_output assigned false "mismatched type does not assign"
  cleanup_case
}

# --- input validation (validate_inputs) -------------------------------------

test_invalid_issue_number() {
  echo "📝 Non-numeric issue number is rejected"
  ISSUE_NUMBER="abc" GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" run_action
  assert_rc 1 "non-numeric issue number fails"
  assert_output assigned false "invalid issue number does not assign"
  assert_log_contains "Invalid issue number" "invalid issue number is reported"
  assert_call_count 0 "invalid issue number never calls the API"
  cleanup_case
}

test_invalid_repository() {
  echo "📝 Malformed repository is rejected"
  REPOSITORY="not-a-repo" GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" run_action
  assert_rc 1 "malformed repository fails"
  assert_log_contains "owner/repo" "malformed repository is reported"
  cleanup_case
}

test_control_char_milestone() {
  echo "📝 Control characters in the milestone name are rejected"
  TARGET_MILESTONE=$'bad\x01name' GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" run_action
  assert_rc 1 "control-char milestone fails"
  assert_log_contains "control characters" "control-char milestone is reported"
  cleanup_case
}

# --- retry / fail-fast classification (retry_gh_command) --------------------

test_404_fails_fast() {
  echo "📝 A deterministic HTTP 404 fails fast (no retry)"
  GH_MOCK_API_RC=1 GH_MOCK_API_STDERR="gh: Not Found (HTTP 404)" \
    GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" run_action
  assert_rc 1 "404 aborts the run"
  assert_call_count 1 "404 is not retried"
  cleanup_case
}

test_403_rate_limit_is_retried() {
  echo "📝 An HTTP 403 secondary rate limit is retried, not treated as fatal"
  GH_MOCK_API_RC=1 \
    GH_MOCK_API_STDERR="gh: HTTP 403: You have exceeded a secondary rate limit" \
    GH_MOCK_ISSUE="${FIXTURES}/issue-open-no-milestone.json" run_action
  assert_rc 1 "403 still ultimately fails after retries"
  assert_call_count 3 "403 is retried up to MAX_RETRY_ATTEMPTS"
  cleanup_case
}

# --- run --------------------------------------------------------------------

test_label_exact_rejects_nearmiss; echo ""
test_label_exact_matches; echo ""
test_milestone_case_insensitive; echo ""
test_milestone_not_found; echo ""
test_already_assigned; echo ""
test_type_filter_no_field_is_notice; echo ""
test_type_filter_match; echo ""
test_type_filter_mismatch; echo ""
test_invalid_issue_number; echo ""
test_invalid_repository; echo ""
test_control_char_milestone; echo ""
test_404_fails_fast; echo ""
test_403_rate_limit_is_retried; echo ""

echo "📊 Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
[[ "${TESTS_FAILED}" -eq 0 ]] && { echo "🎉 All tests passed!"; exit 0; }
echo "💥 Some tests failed!"; exit 1
