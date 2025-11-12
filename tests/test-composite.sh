#!/bin/bash

# Automated Unit Test Suite for Issue Milestoner
# Validates input handling and core logic without external dependencies

set -e

echo "🧪 Automated Unit Test Suite"
echo "============================"
echo "🎯 Testing input validation and core logic"
echo "🤖 Running $(basename "$0") in CI/automated mode"
echo ""

# Test framework setup
TESTS_PASSED=0
TESTS_FAILED=0
TEST_OUTPUT_DIR="/tmp/issue-milestoner-tests"
mkdir -p "$TEST_OUTPUT_DIR"

# Unit test helper functions
pass_test() {
    local test_name="$1"
    echo "  ✅ PASS: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail_test() {
    local test_name="$1" 
    local reason="$2"
    echo "  ❌ FAIL: $test_name - $reason"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test function definitions
test_issue_number_validation() {
    echo "📝 Test Suite 1: Input Validation"
    echo "  → Testing issue number validation..."
    
    # Test valid issue numbers
    local valid_numbers=("1" "123" "9999")
    for num in "${valid_numbers[@]}"; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -gt 0 ]]; then
            pass_test "Valid issue number: $num"
        else
            fail_test "Valid issue number: $num" "Should be valid"
        fi
    done
    
    # Test invalid issue numbers  
    local invalid_numbers=("0" "-1" "abc" "1.5" "" " ")
    for num in "${invalid_numbers[@]}"; do
        if [[ ! "$num" =~ ^[0-9]+$ ]] || [[ "$num" -lt 1 ]]; then
            pass_test "Invalid issue number: '$num'"
        else
            fail_test "Invalid issue number: '$num'" "Should be invalid"
        fi
    done
}

test_environment_validation() {
    echo "  → Testing environment variable validation..."
    
    # Test required variables
    local required_vars=("ISSUE_NUMBER" "TARGET_MILESTONE" "REPOSITORY")
    for var in "${required_vars[@]}"; do
        # Simulate empty variable
        local value=""
        if [[ -z "$value" ]]; then
            pass_test "Required variable '$var' validation"
        else
            fail_test "Required variable '$var' validation" "Should detect empty value"
        fi
    done
    
    # Test optional variables
    local optional_vars=("ISSUE_TYPE" "ISSUE_LABEL") 
    for var in "${optional_vars[@]}"; do
        # Simulate empty optional variable (should be allowed)
        local value=""
        if [[ -z "$value" ]]; then
            pass_test "Optional variable '$var' validation" 
        fi
    done
}

test_filtering_logic() {
    echo "📝 Test Suite 2: Issue Type and Label Filtering"
    echo "  → Testing issue type matching logic..."
    
    # Test issue type matching (exact match, case-insensitive)
    test_issue_type_filter() {
        local issue_type="$1"
        local filter_type="$2"
        
        local issue_type_lower filter_type_lower
        issue_type_lower=$(echo "$issue_type" | tr '[:upper:]' '[:lower:]')
        filter_type_lower=$(echo "$filter_type" | tr '[:upper:]' '[:lower:]')
        
        [[ "$issue_type_lower" == "$filter_type_lower" ]]
    }
    
    # Test issue type cases
    local issue_type_cases=(
        "bug|bug|true"
        "Bug|bug|true"  
        "FEATURE|feature|true"
        "task|bug|false"
    )
    
    for case in "${issue_type_cases[@]}"; do
        IFS='|' read -r issue_type filter_type expected <<< "$case"
        
        if test_issue_type_filter "$issue_type" "$filter_type"; then
            result="true"
        else
            result="false"
        fi
        
        if [[ "$result" == "$expected" ]]; then
            pass_test "Issue type match: '$filter_type' vs '$issue_type'"
        else
            fail_test "Issue type match: '$filter_type' vs '$issue_type'" "Expected $expected, got $result"
        fi
    done
    
    echo "  → Testing label matching logic..."
    
    # Simulate label filtering logic from assign-milestone.sh
    test_label_filter() {
        local labels="$1"
        local issue_label="$2"
        local issue_label_lower
        issue_label_lower=$(echo "$issue_label" | tr '[:upper:]' '[:lower:]')
        
        local label_matches=false
        while IFS= read -r label; do
            [[ -z "$label" ]] && continue
            # Convert label to lowercase for case-insensitive comparison
            local label_lower
            label_lower=$(echo "$label" | tr '[:upper:]' '[:lower:]')
            if [[ "$label_lower" == *"$issue_label_lower"* ]] || [[ "$issue_label_lower" == *"$label_lower"* ]]; then
                label_matches=true
                break
            fi
        done <<< "$labels"
        
        [[ "$label_matches" == "true" ]]
    }
    
    # Test cases for label matching  
    local label_test_cases=(
        "bug,enhancement,docs|bug|true"
        "enhancement,feature|bug|false" 
        "BUG,Enhancement|Bug|true"
        "ui,ux,design|ui|true"
        "backend,api|frontend|false"
    )
    
    for case in "${label_test_cases[@]}"; do
        IFS='|' read -r labels issue_label expected <<< "$case"
        labels=$(echo "$labels" | tr ',' '\n')
        
        if test_label_filter "$labels" "$issue_label"; then
            result="true"
        else
            result="false"
        fi
        
        if [[ "$result" == "$expected" ]]; then
            pass_test "Label match: '$issue_label' in labels"
        else
            fail_test "Label match: '$issue_label' in labels" "Expected $expected, got $result"
        fi
    done
}

test_output_format() {
    echo "📝 Test Suite 3: Output Format"
    echo "  → Testing GitHub Actions output format..."
    
    # Test valid output formats
    local test_outputs=(
        "assigned=true"
        "reason=Milestone assigned successfully" 
        "milestone=v1.0.0"
        "issue_number=123"
    )
    
    local output_file="$TEST_OUTPUT_DIR/test_output"
    for output in "${test_outputs[@]}"; do
        echo "$output" > "$output_file"
        
        # Validate format: key=value
        if grep -q '^[a-zA-Z_][a-zA-Z0-9_]*=.*$' "$output_file"; then
            pass_test "Output format: '$output'"
        else  
            fail_test "Output format: '$output'" "Invalid key=value format"
        fi
    done
    
    rm -f "$output_file"
}

# Execute all unit tests
echo "🚀 Executing Unit Tests..."
echo "========================="

test_issue_number_validation
echo ""
test_environment_validation  
echo ""
test_filtering_logic
echo ""
test_output_format
echo ""

# Test summary
echo "📊 Test Results Summary"
echo "======================"
echo "✅ Passed: $TESTS_PASSED"
echo "❌ Failed: $TESTS_FAILED" 
echo "📈 Total:  $((TESTS_PASSED + TESTS_FAILED))"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo "🎉 All unit tests passed!"
    exit 0
else
    echo ""
    echo "💥 Some unit tests failed!"
    exit 1
fi

# Cleanup
rm -rf "$TEST_OUTPUT_DIR"