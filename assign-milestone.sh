#!/bin/bash

# Issue Milestoner - Composite Action Script
# Assigns GitHub issues to milestones based on criteria

set -e

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

# Validate inputs
if [[ ! "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]] || [[ "${ISSUE_NUMBER}" -lt 1 ]]; then
  echo "reason=Invalid issue number: ${ISSUE_NUMBER}" >> "${GITHUB_OUTPUT}"
  echo "::error::Invalid issue number: ${ISSUE_NUMBER}"
  exit 1
fi

if [[ -z "${TARGET_MILESTONE}" ]]; then
  echo "reason=Target milestone is required" >> "${GITHUB_OUTPUT}"
  echo "::error::Target milestone is required"
  exit 1
fi

echo "::notice::Processing issue #${ISSUE_NUMBER} in ${REPOSITORY}"

# Get issue details
echo "::group::Fetching issue details"
issue_data=$(gh issue view "${ISSUE_NUMBER}" --repo "${REPOSITORY}" --json milestone,labels,title,state)
issue_title=$(echo "${issue_data}" | jq -r '.title')
issue_state=$(echo "${issue_data}" | jq -r '.state')
current_milestone=$(echo "${issue_data}" | jq -r '.milestone.title // empty')

echo "::notice::Issue title: \"${issue_title}\""
echo "::notice::Issue state: ${issue_state}"
echo "::endgroup::"

# Check if issue already has a milestone
if [[ -n "${current_milestone}" ]]; then
  reason="Issue already assigned to milestone: ${current_milestone}"
  {
    echo "milestone=${current_milestone}"
    echo "reason=${reason}"
  } >> "${GITHUB_OUTPUT}"
  echo "::notice::${reason}"
  exit 0
fi

# Check issue type filter if provided
if [[ -n "${ISSUE_TYPE}" ]]; then
  echo "::group::Checking issue type filter"
  labels=$(echo "${issue_data}" | jq -r '.labels[].name')
  labels=$(echo "${labels}" | tr '[:upper:]' '[:lower:]')
  issue_type_lower=$(echo "${ISSUE_TYPE}" | tr '[:upper:]' '[:lower:]')
  
  type_matches=false
  while IFS= read -r label; do
    if [[ "${label}" == *"${issue_type_lower}"* ]] || [[ "${issue_type_lower}" == *"${label}"* ]]; then
      type_matches=true
      break
    fi
  done <<< "${labels}"
  
  if [[ "${type_matches}" != "true" ]]; then
    labels_list=$(echo "${labels}" | tr '\n' ',')
    labels_list="${labels_list%,}"
    reason="Issue type filter \"${ISSUE_TYPE}\" does not match issue labels: ${labels_list}"
    echo "reason=${reason}" >> "${GITHUB_OUTPUT}"
    echo "::notice::${reason}"
    exit 0
  fi
  echo "::endgroup::"
fi

# Assign issue to milestone (GitHub CLI handles validation and matching)
echo "::group::Assigning milestone"
if gh issue edit "${ISSUE_NUMBER}" --repo "${REPOSITORY}" --milestone "${TARGET_MILESTONE}" 2>/dev/null; then
  reason="Successfully assigned issue to milestone: ${TARGET_MILESTONE}"
  {
    echo "assigned=true"
    echo "milestone=${TARGET_MILESTONE}"
    echo "reason=${reason}"
  } >> "${GITHUB_OUTPUT}"
  echo "::notice::${reason}"
else
  reason="Milestone '${TARGET_MILESTONE}' not found or assignment failed"
  echo "reason=${reason}" >> "${GITHUB_OUTPUT}"
  echo "::error::${reason}"
  exit 1
fi
echo "::endgroup::"