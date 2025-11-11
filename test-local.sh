#!/bin/bash

# Local test runner for assign-milestone.sh
# This script helps test the milestone assignment logic locally

set -e

echo "🧪 Local Test Runner for assign-milestone.sh"
echo "=============================================="

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

# Get inputs from user or environment
ISSUE_NUMBER=${1:-${ISSUE_NUMBER}}
TARGET_MILESTONE=${2:-${TARGET_MILESTONE}}
REPOSITORY=${3:-${REPOSITORY}}
ISSUE_TYPE=${4:-${ISSUE_TYPE}}

if [[ -z "${ISSUE_NUMBER}" ]]; then
    read -rp "Enter issue number: " ISSUE_NUMBER
fi

if [[ -z "${TARGET_MILESTONE}" ]]; then
    read -rp "Enter target milestone: " TARGET_MILESTONE
fi

if [[ -z "${REPOSITORY}" ]]; then
    read -rp "Enter repository (owner/repo): " REPOSITORY
fi

if [[ -z "${ISSUE_TYPE}" ]]; then
    read -rp "Enter issue type filter (optional, press enter to skip): " ISSUE_TYPE
fi

# Set up environment variables
export GH_TOKEN="${GH_TOKEN}"
export ISSUE_NUMBER="${ISSUE_NUMBER}"
export TARGET_MILESTONE="${TARGET_MILESTONE}"
export REPOSITORY="${REPOSITORY}"
export ISSUE_TYPE="${ISSUE_TYPE}"
export GITHUB_OUTPUT="/tmp/milestone_test_output"

# Clean up any previous output
rm -f "${GITHUB_OUTPUT}"
touch "${GITHUB_OUTPUT}"

echo ""
echo "🚀 Running milestone assignment..."
echo "   Issue: #${ISSUE_NUMBER}"
echo "   Repository: ${REPOSITORY}"
echo "   Target Milestone: ${TARGET_MILESTONE}"
if [[ -n "${ISSUE_TYPE}" ]]; then
    echo "   Issue Type Filter: ${ISSUE_TYPE}"
fi
echo ""

# Run the script
if ./assign-milestone.sh; then
    echo ""
    echo "✅ Script completed successfully!"
    echo ""
    echo "📋 Outputs:"
    while IFS='=' read -r key value; do
        echo "   ${key}: ${value}"
    done < "${GITHUB_OUTPUT}"
else
    echo ""
    echo "❌ Script failed!"
    if [[ -f "${GITHUB_OUTPUT}" ]]; then
        echo ""
        echo "📋 Outputs:"
        while IFS='=' read -r key value; do
            echo "   ${key}: ${value}"
        done < "${GITHUB_OUTPUT}"
    fi
fi

# Clean up
rm -f "${GITHUB_OUTPUT}"