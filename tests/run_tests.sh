#!/usr/bin/env bash
# =============================================================================
# HA Load Balancer — Test Suite Runner
#
# Usage:
#   cd tests && bash run_tests.sh           # Run all tests
#   cd tests && bash run_tests.sh entrypoint  # Run specific test group
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_FILES=(
    test_entrypoint.sh
    test_deploy.sh
    test_config.sh
    test_ha_check.sh
    test_install_deps.sh
    test_templates.sh
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_RUN=0
TOTAL_PASSED=0
TOTAL_FAILED=0

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   HA Load Balancer — Test Suite                      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Filter
FILTER="${1:-}"

for test_file in "${TEST_FILES[@]}"; do
    # Filter: if argument provided, only run matching file
    if [[ -n "$FILTER" ]]; then
        if [[ "$test_file" != *"$FILTER"* ]]; then
            continue
        fi
    fi

    echo -e "${BLUE}▶ Running: $test_file${NC}"
    echo ""

    # Run the test file directly (not in subshell) — capture output via temp file
    TMPFILE=$(mktemp)
    bash "$SCRIPT_DIR/$test_file" > "$TMPFILE" 2>&1; EXIT_CODE=$?
    OUTPUT=$(cat "$TMPFILE")
    rm -f "$TMPFILE"

    # Count results from output
    PASSED=$(echo "$OUTPUT" | grep -c "PASS" || true)
    FAILED=$(echo "$OUTPUT" | grep -c "FAIL" || true)

    TOTAL_PASSED=$((TOTAL_PASSED + PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + FAILED))
    TOTAL_RUN=$((TOTAL_RUN + PASSED + FAILED))

    if [[ "$EXIT_CODE" -eq 0 ]]; then
        echo -e "  ${GREEN}✓ $test_file passed (${PASSED} assertions)${NC}"
    else
        echo -e "  ${RED}✗ $test_file failed (exit $EXIT_CODE, $FAILED assertions)${NC}"
        echo ""
        echo -e "${YELLOW}--- $test_file output ---${NC}"
        echo "$OUTPUT"
        echo -e "${YELLOW}--- end output ---${NC}"
        echo ""
    fi
    echo ""
done

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo -e "  ${GREEN}All $TOTAL_RUN assertions passed! ✓${NC}"
else
    echo -e "  ${RED}$TOTAL_FAILED assertion(s) failed out of $TOTAL_RUN${NC}"
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Run shellcheck if available
echo -e "${BLUE}▶ Static analysis (shellcheck)${NC}"
if command -v shellcheck &>/dev/null; then
    SC_FILES=(
        "$SCRIPT_DIR/test_entrypoint.sh"
        "$SCRIPT_DIR/test_deploy.sh"
        "$SCRIPT_DIR/test_config.sh"
        "$SCRIPT_DIR/test_ha_check.sh"
        "$SCRIPT_DIR/test_install_deps.sh"
        "$SCRIPT_DIR/test_templates.sh"
    )
    SC_WARNINGS=0
    for sc_file in "${SC_FILES[@]}"; do
        if [[ -f "$sc_file" ]]; then
            SC_OUT=$(shellcheck "$sc_file" 2>&1) || true
            SC_COUNT=$(echo "$SC_OUT" | grep -c "^[[:space:]]" || true)
            SC_WARNINGS=$((SC_WARNINGS + SC_COUNT))
            if [[ $SC_COUNT -gt 0 ]]; then
                echo -e "  ${YELLOW}⚠ $(basename "$sc_file"): $SC_COUNT hint(s)${NC}"
            else
                echo -e "  ${GREEN}✓ $(basename "$sc_file"): clean${NC}"
            fi
        fi
    done
    if [[ $SC_WARNINGS -gt 0 ]]; then
        echo -e "  ${YELLOW}  $SC_WARNINGS total hint(s) — see above${NC}"
    fi
else
    echo -e "  ${YELLOW}  shellcheck not installed — skipping${NC}"
fi
echo ""

exit $TOTAL_FAILED
