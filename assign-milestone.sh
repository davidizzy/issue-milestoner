#!/bin/bash

# Issue Milestoner - Composite Action Script
# Assigns GitHub issues to milestones based on criteria

set -e
shopt -s inherit_errexit  # Ensure set -e applies in command substitutions

# Constants
readonly MIN_ISSUE_NUMBER=1
readonly MAX_ISSUE_NUMBER=999999999  # GitHub's practical limit
readonly MAX_RETRY_ATTEMPTS=3
readonly INITIAL_RETRY_DELAY=2

# Helper Functions
# ================

# Convert string to lowercase
to_lowercase() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Retry a command with exponential backoff
retry_gh_command() {
  local max_attempts=${MAX_RETRY_ATTEMPTS}
  local attempt=1
  local delay=${INITIAL_RETRY_DELAY}
  
  while (( attempt <= max_attempts )); do
    if "$@"; then
      return 0
    fi
    echo "::warning::Attempt ${attempt}/${max_attempts} failed, retrying in ${delay}s..."
    sleep "${delay}"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
  
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

  # Validate milestone name
  if [[ -z "${TARGET_MILESTONE}" ]]; then
    set_output "reason" "Target milestone is required"
    echo "::error::Target milestone is required"
    exit 1
  fi

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
  echo "::group::Fetching issue details"
  
  local issue_data
  issue_data=$(retry_gh_command gh issue view "${ISSUE_NUMBER}" --repo "${REPOSITORY}" --json milestone,labels,title,state)
  local exit_code=$?

  if [[ ${exit_code} -ne 0 ]]; then
    echo "::error::Failed to fetch issue data after ${MAX_RETRY_ATTEMPTS} attempts"
    exit 1
  fi

  # Validate JSON parsing
  if [[ -z "${issue_data}" ]] || ! echo "${issue_data}" | jq -e . >/dev/null 2>&1; then
    echo "::error::Failed to parse issue data"
    exit 1
  fi

  local issue_state
  issue_state=$(echo "${issue_data}" | jq -r '.state')
  
  echo "::notice::Issue #${ISSUE_NUMBER}"
  echo "::notice::Issue state: ${issue_state}"
  echo "::endgroup::"
  
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
  
  # Skip if no filter specified
  [[ -z "${ISSUE_TYPE}" ]] && return 0
  
  echo "::group::Checking GitHub issue type filter"
  
  local issue_type_field
  issue_type_field=$(echo "${issue_data}" | jq -r '.type // empty')
  
  if [[ -n "${issue_type_field}" ]]; then
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
  else
    local reason="Issue type filter \"${ISSUE_TYPE}\" specified but issue has no type set"
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
    local label_lower
    label_lower=$(to_lowercase "${label}")
    if [[ "${label_lower}" == *"${issue_label_lower}"* ]] || \
       [[ "${issue_label_lower}" == *"${label_lower}"* ]]; then
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

# Assign the issue to the target milestone
assign_milestone() {
  echo "::group::Assigning milestone"
  
  if gh issue edit "${ISSUE_NUMBER}" --repo "${REPOSITORY}" --milestone "${TARGET_MILESTONE}" 2>/dev/null; then
    local reason="Successfully assigned issue to milestone: ${TARGET_MILESTONE}"
    set_output "assigned" "true"
    set_output "milestone" "${TARGET_MILESTONE}"
    set_output "reason" "${reason}"
    echo "::notice::${reason}"
  else
    local reason="Milestone '${TARGET_MILESTONE}' not found or assignment failed"
    set_output "reason" "${reason}"
    echo "::error::${reason}"
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

main "$@"