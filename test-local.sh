#!/bin/bash

# Interactive Development Test Runner for assign-milestone.sh
# Use this for manual testing with real GitHub issues during development

set -e

echo "🧪 Interactive Development Test Runner"
echo "======================================"
echo "💡 This script lets you manually test milestone assignment with real GitHub issues"
echo "🤖 For automated CI testing, use: make test"
echo ""

# Check if required tools are available
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed. Please install it first:"
    echo "   brew install gh"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq is not installed. Please install it first:"
    echo "   brew install jq"
    exit 1
fi

# Check if GH_TOKEN is set
if [[ -z "${GH_TOKEN}" ]]; then
    echo "❌ GH_TOKEN environment variable is not set"
    echo "💡 Set it with: export GH_TOKEN=your_github_token"
    exit 1
fi

# Interactive input collection for development testing
collect_development_inputs() {
    echo "🔧 Development Test Configuration"
    echo "--------------------------------"
    
    # Repository (with current repo default)
    current_repo=""
    current_repo=$(git remote get-url origin 2>/dev/null | sed -E 's/.*github\.com[:/]([^/]+\/[^/.]+)(\.git)?$/\1/' || true)
    if [[ -n "${current_repo}" ]]; then
        read -rp "Repository [${current_repo}]: " repo_input
        REPOSITORY="${repo_input:-${current_repo}}"
    else
        while [[ -z "${REPOSITORY}" ]]; do
            read -rp "Repository (owner/repo): " REPOSITORY
        done
    fi
    
    # Issue number with validation
    while true; do
        read -rp "Issue number: " ISSUE_NUMBER
        if [[ "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "❌ Issue number must be numeric"
        fi
    done
    
    # Target milestone
    while [[ -z "${TARGET_MILESTONE}" ]]; do
        read -rp "Target milestone: " TARGET_MILESTONE
    done
    
    # Optional filters
    read -rp "Issue type - GitHub issue type (optional): " ISSUE_TYPE
    read -rp "Issue label - label filter (optional): " ISSUE_LABEL
    
    echo ""
    echo "Development Test Summary:"
    echo "   Repository: ${REPOSITORY}"
    echo "   Issue #${ISSUE_NUMBER} → Milestone: ${TARGET_MILESTONE}"
    echo "   Issue Type Filter: ${ISSUE_TYPE:-'(not specified)'}"
    echo "   Label Filter: ${ISSUE_LABEL:-'(not specified)'}"
    echo ""
    
    read -rp "Run test? (y/N): " confirm
    [[ "${confirm}" =~ ^[Yy]$ ]] || { echo "Cancelled"; exit 1; }
}

# Use command line args if provided, otherwise collect interactively
if [[ $# -ge 3 ]]; then
    ISSUE_NUMBER="$1"
    TARGET_MILESTONE="$2"
    REPOSITORY="$3"
    ISSUE_TYPE="$4"
    ISSUE_LABEL="$5"
    echo "Using command line arguments:"
    echo "   Issue #${ISSUE_NUMBER} → Milestone: ${TARGET_MILESTONE}"
    echo "   Repository: ${REPOSITORY}"
    echo "   Issue Type Filter: ${ISSUE_TYPE:-'(not specified)'}"
    echo "   Label Filter: ${ISSUE_LABEL:-'(not specified)'}"
    echo ""
else
    collect_development_inputs
fi

# Set up environment variables
export GH_TOKEN="${GH_TOKEN}"
export ISSUE_NUMBER="${ISSUE_NUMBER}"
export TARGET_MILESTONE="${TARGET_MILESTONE}"
export REPOSITORY="${REPOSITORY}"
export ISSUE_TYPE="${ISSUE_TYPE}"
export ISSUE_LABEL="${ISSUE_LABEL}"
export GITHUB_OUTPUT="/tmp/milestone_test_output"

# Clean up any previous output
rm -f "${GITHUB_OUTPUT}"
touch "${GITHUB_OUTPUT}"

# Run development test with detailed output
run_development_test() {
    echo "Running Development Test..."
    echo "============================="
    echo "Testing: Issue #${ISSUE_NUMBER} → Milestone '${TARGET_MILESTONE}'"
    echo "Repository: ${REPOSITORY}"
    [[ -n "${ISSUE_TYPE}" ]] && echo "Issue Type Filter: ${ISSUE_TYPE}"
    [[ -n "${ISSUE_LABEL}" ]] && echo "Label Filter: ${ISSUE_LABEL}"
    echo ""
    
    # Run the assignment script
    if ./assign-milestone.sh; then
        echo ""
        echo "Development Test PASSED!"
        echo ""
        echo "Test Results:"
        while IFS='=' read -r key value; do
            echo "   ${key}: ${value}"
        done < "${GITHUB_OUTPUT}"
        echo ""
        echo "Check the issue in GitHub to verify the milestone assignment"
    else
        exit_code=$?
        echo ""
        echo "Development Test FAILED! (exit code: ${exit_code})"
        if [[ -f "${GITHUB_OUTPUT}" ]]; then
            echo ""
            echo "Test Results:"
            while IFS='=' read -r key value; do
                echo "   ${key}: ${value}"
            done < "${GITHUB_OUTPUT}"
        fi
        echo ""
        echo "Troubleshooting Tips:"
        echo "   - Verify the issue exists and you have write access"
        echo "   - Check if the milestone exists in the repository"
        echo "   - Ensure GH_TOKEN has appropriate permissions"
        return "${exit_code}"
    fi
}

run_development_test

# Clean up
rm -f "${GITHUB_OUTPUT}"