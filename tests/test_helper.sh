#!/usr/bin/env bash
# =============================================================================
# Shared test utilities — sourced by every test file
# =============================================================================

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# --- Assertion helpers ---

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
        echo -e "    expected: ${YELLOW}${expected}${NC}"
        echo -e "    actual:   ${YELLOW}${actual}${NC}"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
        echo -e "    expected to contain: ${YELLOW}${needle}${NC}"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
        echo -e "    expected NOT to contain: ${YELLOW}${needle}${NC}"
    fi
}

assert_file_contains() {
    local file="$1" needle="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$file" ]] && grep -qF "$needle" "$file" 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
        if [[ ! -f "$file" ]]; then
            echo -e "    file does not exist: ${YELLOW}${file}${NC}"
        else
            echo -e "    file does not contain: ${YELLOW}${needle}${NC}"
        fi
    fi
}

assert_exit_code() {
    local actual_code="$1" expected_code="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$actual_code" -eq "$expected_code" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
        echo -e "    expected exit code: ${YELLOW}${expected_code}${NC}"
        echo -e "    actual exit code:   ${YELLOW}${actual_code}${NC}"
    fi
}

assert_true() {
    local condition="$1" msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if eval "$condition" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
    fi
}

assert_false() {
    local condition="$1" msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! eval "$condition" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
    fi
}

assert_file_exists() {
    local file="$1" msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$file" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
        echo -e "    file does not exist: ${YELLOW}${file}${NC}"
    fi
}

assert_file_not_exists() {
    local file="$1" msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -f "$file" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
        echo -e "    file exists but should not: ${YELLOW}${file}${NC}"
    fi
}

assert_gt() {
    local a="$1" b="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$a" -gt "$b" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}${msg:+ — $msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC}${msg:+ — $msg}"
        echo -e "    expected ${YELLOW}${a}${NC} > ${YELLOW}${b}${NC}"
    fi
}

# --- Test runner ---
# Usage:
#   run_test "description" 'assert_eq "1" "1"'
#   run_test "description" <<'EOF'
#     assert_eq "1" "1"
#   EOF
run_test() {
    local name="$1"
    shift
    echo -e "  ${BLUE}TEST:${NC} $name"

    # If there are remaining arguments, eval them (inline style)
    if [[ $# -gt 0 ]]; then
        (eval "$@")
    # Otherwise, read from stdin (heredoc style)
    else
        (eval "$(cat)")
    fi
    echo ""
}

# --- Cleanup ---

cleanup_tmp() {
    local prefix="$1"
    rm -rf "/tmp/${prefix}."*  2>/dev/null || true
}

# --- Summary ---

print_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     HA Load Balancer — Test Results  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo -e "  Total:   ${total}"
    echo -e "  ${GREEN}Passed:  ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed:  ${TESTS_FAILED}${NC}"
    if [[ $TESTS_SKIPPED -gt 0 ]]; then
        echo -e "  ${YELLOW}Skipped: ${TESTS_SKIPPED}${NC}"
    fi
    echo ""
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "  ${GREEN}All tests passed! ✓${NC}"
    else
        echo -e "  ${RED}Some tests failed. ✗${NC}"
    fi
    echo ""
    return $TESTS_FAILED
}
