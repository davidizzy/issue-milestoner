#!/bin/bash

# Issue Milestoner - Composite Action Script
# Assigns GitHub issues to milestones based on criteria

set -e
# Ensure set -e applies in command substitutions. Best-effort: this option only
# exists in bash 4+. GitHub runners are always bash 4+, so the hardening is active
# in production; the guard just lets the script run on older local shells too.
shopt -s inherit_errexit 2>/dev/null || true

# Constants
readonly MIN_ISSUE_NUMBER=1
readonly MAX_ISSUE_NUMBER=999999999  # GitHub's practical limit
readonly MAX_RETRY_ATTEMPTS=3
# Overridable via env so tests can disable backoff sleeps; defaults to 2s.
readonly INITIAL_RETRY_DELAY="${INITIAL_RETRY_DELAY:-2}"

# Helper Functions
# ================

# Convert string to lowercase. Uses printf, not echo: echo would swallow values
# that look like flags (e.g. a label or milestone literally named "-n" or "-e").
to_lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Retry a command with exponential backoff.
# The command's stdout passes through to the caller; its stderr is captured so we
# can (a) avoid corrupting captured stdout and (b) decide whether to retry.
# Only deterministic client errors fail fast - errors that can never succeed on
# retry (400/401/404/410/422). Crucially, 403 and 429 are NOT in that set:
# GitHub signals secondary/abuse rate limits with HTTP 403 (and sometimes 429),
# which are transient and must be retried with backoff. Network errors (no HTTP
# status in the output) are also retried.
retry_gh_command() {
  local max_attempts=${MAX_RETRY_ATTEMPTS}
  local attempt=1
  local delay=${INITIAL_RETRY_DELAY}
  local err_file
  err_file=$(mktemp "${RUNNER_TEMP:-/tmp}/gh_stderr_XXXXXX")

  while (( attempt <= max_attempts )); do
    if "$@" 2>"${err_file}"; then
      rm -f "${err_file}"
      return 0
    fi

    # Surface the underlying error for diagnostics.
    cat "${err_file}" >&2

    # Fail fast only on deterministic client errors. Parse the HTTP status once;
    # if gh reported one of these, retrying cannot help.
    local http_status
    # shellcheck disable=SC2312  # grep exit status is intentionally ignored here
    http_status=$(grep -oiE 'HTTP [0-9]{3}' "${err_file}" | grep -oE '[0-9]{3}' | head -1)
    case "${http_status}" in
      400|401|404|410|422)
        echo "::warning::Non-retryable HTTP ${http_status}; not retrying." >&2
        rm -f "${err_file}"
        return 1
        ;;
      *) ;;  # any other status (incl. 403/429 rate limits, 5xx, none) → retry
    esac

    if (( attempt < max_attempts )); then
      echo "::warning::Attempt ${attempt}/${max_attempts} failed, retrying in ${delay}s..." >&2
      sleep "${delay}"
    fi
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done

  rm -f "${err_file}"
  return 1
}

# Set output value in GitHub Actions
set_output() {
  local key="$1"
  local value="$2"
  # shellcheck disable=SC2154  # GITHUB_OUTPUT is set by GitHub Actions runtime
  echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
}

# Core Functions
# ==============

# Validate all required inputs
validate_inputs() {
  # Check required environment variables
  : "${GITHUB_OUTPUT:?GITHUB_OUTPUT environment variable is required}"
  : "${ISSUE_NUMBER:?ISSUE_NUMBER environment variable is required}"
  : "${REPOSITORY:?REPOSITORY environment variable is required}"
  : "${TARGET_MILESTONE:?TARGET_MILESTONE environment variable is required}"

  # Set default outputs
  {
    echo "assigned=false"
    echo "milestone="
    echo "reason="
  } >> "${GITHUB_OUTPUT}"

  # Validate issue number
  if [[ ! "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]] || \
     [[ "${ISSUE_NUMBER}" -lt ${MIN_ISSUE_NUMBER} ]] || \
     [[ "${ISSUE_NUMBER}" -gt ${MAX_ISSUE_NUMBER} ]]; then
    set_output "reason" "Invalid issue number: ${ISSUE_NUMBER}"
    echo "::error::Invalid issue number: ${ISSUE_NUMBER}"
    exit 1
  fi

  # Note: TARGET_MILESTONE presence is already enforced by the ${VAR:?} guard
  # above (it triggers on unset *or* empty), so no explicit -z check is needed.

  # Validate repository format
  if [[ ! "${REPOSITORY}" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
    set_output "reason" "Invalid repository format: ${REPOSITORY}"
    echo "::error::Repository must be in format owner/repo"
    exit 1
  fi

  # Validate milestone name format
  if [[ "${TARGET_MILESTONE}" =~ [[:cntrl:]] ]]; then
    set_output "reason" "Milestone name contains invalid control characters"
    echo "::error::Milestone name contains invalid control characters"
    exit 1
  fi

  echo "::notice::Processing issue #${ISSUE_NUMBER} in ${REPOSITORY}"
}

# Fetch issue data from GitHub API
fetch_issue_data() {
  echo "::group::Fetching issue details" >&2

  local issue_data temp_file
  # mktemp (not a predictable PID-based name) avoids symlink/stale-file races
  # under a shared /tmp, matching retry_gh_command's stderr temp handling.
  temp_file=$(mktemp "${RUNNER_TEMP:-/tmp}/gh_issue_data_XXXXXX")

  # Fetch issue data using gh api (which supports all fields including type).
  # retry_gh_command captures the command's stderr separately, so temp_file
  # holds only the JSON response - no stderr chatter to corrupt jq parsing.
  # shellcheck disable=SC2310  # Intentionally using in if condition
  if retry_gh_command gh api "repos/${REPOSITORY}/issues/${ISSUE_NUMBER}" > "${temp_file}"; then
    # Extract only the fields we need from the full API response
    issue_data=$(jq '{milestone, labels, title, state, type}' < "${temp_file}" 2>/dev/null)
    rm -f "${temp_file}"

    # If jq failed to extract data, the API response was likely an error
    if [[ -z "${issue_data}" ]] || [[ "${issue_data}" == "null" ]]; then
      echo "::error::Failed to extract issue data from API response" >&2
      exit 1
    fi
  else
    rm -f "${temp_file}"
    echo "::error::Failed to fetch data for issue #${ISSUE_NUMBER} in ${REPOSITORY}" >&2
    exit 1
  fi

  # Validate JSON parsing
  if [[ -z "${issue_data}" ]] || ! jq -e . <<< "${issue_data}" >/dev/null 2>&1; then
    echo "::error::Failed to parse issue data" >&2
    echo "::error::Received data: ${issue_data}" >&2
    exit 1
  fi

  local issue_state
  issue_state=$(jq -r '.state' <<< "${issue_data}")

  echo "::notice::Issue #${ISSUE_NUMBER}" >&2
  echo "::notice::Issue state: ${issue_state}" >&2

  # Debug: report the issue type. Test `.type != null` (not has("type")): the
  # field projection above always includes a "type" key, null for repos without
  # issue types, so has("type") is always true. This mirrors apply_type_filter.
  if jq -e '.type != null' <<< "${issue_data}" >/dev/null 2>&1; then
    local type_info
    type_info=$(jq -r '.type | if type == "object" then .name else . end' <<< "${issue_data}" 2>/dev/null || echo "unknown")
    echo "::debug::Issue type field detected in API response: ${type_info}" >&2
  else
    echo "::debug::No type field found in API response" >&2
  fi

  echo "::endgroup::" >&2

  echo "${issue_data}"
}

# Check if issue already has a milestone
check_existing_milestone() {
  local issue_data="$1"
  local current_milestone
  current_milestone=$(echo "${issue_data}" | jq -r '.milestone.title // empty')

  if [[ -n "${current_milestone}" ]]; then
    local reason="Issue already assigned to milestone: ${current_milestone}"
    set_output "milestone" "${current_milestone}"
    set_output "reason" "${reason}"
    echo "::notice::${reason}"
    return 1  # Signal to exit main
  fi

  return 0
}

# Apply issue type filter if specified
apply_type_filter() {
  local issue_data="$1"

  # Skip if no filter specified - gracefully ignore lack of type field
  [[ -z "${ISSUE_TYPE}" ]] && return 0

  echo "::group::Checking GitHub issue type filter"

  local issue_type_field=""
  # Extract the type only when it is actually present (non-null). The upstream
  # field extraction always includes a "type" key (null for repos without issue
  # types), and `jq -r` renders null as the string "null" - so we must test for
  # a non-null value, not merely has("type"), to detect a genuinely typeless issue.
  if jq -e '.type != null' <<< "${issue_data}" >/dev/null 2>&1; then
    # Extract the type name if type is an object, or the type itself if it's a string
    issue_type_field=$(jq -r 'if (.type | type) == "object" then .type.name else .type end' <<< "${issue_data}" 2>/dev/null || echo "")
  fi

  # If type filter is specified but issue has no type field, skip gracefully.
  # This is a filter miss, not an error - issue types are only available for
  # organization repositories with issue types configured.
  if [[ -z "${issue_type_field}" ]]; then
    local reason="Issue type filter \"${ISSUE_TYPE}\" specified but issue has no type field. Issue types are only available for organization repositories with issue types configured."
    set_output "reason" "${reason}"
    echo "::notice::${reason}"
    echo "::endgroup::"
    return 1  # Signal to exit main
  fi

  # Compare type filter with issue type
  local issue_type_lower current_type_lower
  issue_type_lower=$(to_lowercase "${ISSUE_TYPE}")
  current_type_lower=$(to_lowercase "${issue_type_field}")

  if [[ "${current_type_lower}" != "${issue_type_lower}" ]]; then
    local reason="Issue type filter \"${ISSUE_TYPE}\" does not match issue type: ${issue_type_field}"
    set_output "reason" "${reason}"
    echo "::notice::${reason}"
    echo "::endgroup::"
    return 1  # Signal to exit main
  fi

  echo "::notice::Issue type matches filter: ${issue_type_field}"
  echo "::endgroup::"
  return 0
}

# Apply label filter if specified
apply_label_filter() {
  local issue_data="$1"

  # Skip if no filter specified
  [[ -z "${ISSUE_LABEL}" ]] && return 0

  echo "::group::Checking issue label filter"

  local labels
  labels=$(echo "${issue_data}" | jq -r '.labels // [] | .[].name')

  if [[ -z "${labels}" ]]; then
    local reason="Issue label filter \"${ISSUE_LABEL}\" specified but issue has no labels"
    set_output "reason" "${reason}"
    echo "::notice::${reason}"
    echo "::endgroup::"
    return 1  # Signal to exit main
  fi

  local labels_lower issue_label_lower
  labels_lower=$(to_lowercase "${labels}")
  issue_label_lower=$(to_lowercase "${ISSUE_LABEL}")

  local label_matches=false
  while IFS= read -r label; do
    [[ -z "${label}" ]] && continue
    local label_lower
    label_lower=$(to_lowercase "${label}")
    if [[ "${label_lower}" == "${issue_label_lower}" ]]; then
      label_matches=true
      break
    fi
  done <<< "${labels_lower}"

  if [[ "${label_matches}" != "true" ]]; then
    local labels_list
    labels_list=$(echo "${labels_lower}" | tr '\n' ',')
    labels_list="${labels_list%,}"
    local reason="Issue label filter \"${ISSUE_LABEL}\" does not match any issue labels: ${labels_list}"
    set_output "reason" "${reason}"
    echo "::notice::${reason}"
    echo "::endgroup::"
    return 1  # Signal to exit main
  fi

  echo "::notice::Issue label matches filter: found matching label"
  echo "::endgroup::"
  return 0
}

# Resolve the target milestone to its canonical title (case-insensitive).
# Echoes the real milestone title on success (return 0).
# Return 1 = milestone does not exist; return 2 = the milestones fetch failed.
# The caller must distinguish these so a transient/permission error is not
# reported to the user as a missing milestone.
resolve_milestone_title() {
  local milestones resolved

  # Fetch OPEN milestones only - a closed milestone is not a valid assignment
  # target, so it must not be resolvable. Paginated for repos with many.
  # stdout (the JSON) is captured here; retry_gh_command routes any error
  # output to stderr so it surfaces in the action log without polluting it.
  # shellcheck disable=SC2310  # Intentionally using in if condition
  if ! milestones=$(retry_gh_command gh api --paginate \
        "repos/${REPOSITORY}/milestones?state=open"); then
    echo "::error::Failed to fetch milestones for ${REPOSITORY}" >&2
    return 2
  fi

  # Fold BOTH the target and each title with ascii_downcase so the comparison
  # uses one consistent casing rule. (Doing the target side with shell `tr` and
  # the title side with jq diverges on non-ASCII names - e.g. tr lowercases "Ü"
  # but ascii_downcase does not - which would fail to match a real milestone.)
  # --paginate concatenates JSON arrays; -s slurps them into one stream.
  resolved=$(jq -rs --arg t "${TARGET_MILESTONE}" \
    'add // [] | map(select((.title | ascii_downcase) == ($t | ascii_downcase))) | .[0].title // empty' \
    <<< "${milestones}" 2>/dev/null)

  [[ -z "${resolved}" ]] && return 1
  echo "${resolved}"
}

# Assign the issue to the target milestone
assign_milestone() {
  echo "::group::Assigning milestone"

  # Capture the resolver's exit code without tripping set -e (|| handler), so we
  # can tell "milestone missing" (rc 1) from "couldn't fetch milestones" (rc 2).
  local milestone_title resolve_rc=0
  # shellcheck disable=SC2310  # || is intentional: we capture rc, not exit here
  milestone_title=$(resolve_milestone_title) || resolve_rc=$?
  if (( resolve_rc != 0 )); then
    local reason
    if (( resolve_rc == 2 )); then
      reason="Could not fetch milestones for ${REPOSITORY} (check token permissions or API availability)"
    else
      reason="Milestone '${TARGET_MILESTONE}' not found in ${REPOSITORY}"
    fi
    set_output "reason" "${reason}"
    echo "::error::${reason}"
    echo "::endgroup::"
    exit 1
  fi

  if gh issue edit "${ISSUE_NUMBER}" --repo "${REPOSITORY}" --milestone "${milestone_title}" 2>/dev/null; then
    local reason="Successfully assigned issue to milestone: ${milestone_title}"
    set_output "assigned" "true"
    set_output "milestone" "${milestone_title}"
    set_output "reason" "${reason}"
    echo "::notice::${reason}"
  else
    local reason="Failed to assign issue to milestone: ${milestone_title}"
    set_output "reason" "${reason}"
    echo "::error::${reason}"
    echo "::endgroup::"
    exit 1
  fi

  echo "::endgroup::"
}

# Main Execution
# ==============

main() {
  validate_inputs

  local issue_data
  issue_data=$(fetch_issue_data)

  # Check filters - if any return 1, exit gracefully
  # SC2310: Intentionally using || to handle filter rejections
  # shellcheck disable=SC2310
  check_existing_milestone "${issue_data}" || exit 0
  # shellcheck disable=SC2310
  apply_type_filter "${issue_data}" || exit 0
  # shellcheck disable=SC2310
  apply_label_filter "${issue_data}" || exit 0

  assign_milestone
}

# Only run main when executed directly, not when sourced (e.g. by the test suite).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
