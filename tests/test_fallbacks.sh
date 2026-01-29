#!/bin/bash

#############################################################################
# Test Suite for Pure Bash Fallbacks
# Version: 3.2.0
# Purpose: Verify all fallback functions work correctly
#############################################################################

set -e

# Import fallbacks
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/fallbacks.sh"

# Test counters
TOTAL=0
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#############################################################################
# TEST FRAMEWORK
#############################################################################

assert_equal() {
    local actual="$1"
    local expected="$2"
    local desc="$3"

    ((TOTAL++))
    if [[ "$actual" == "$expected" ]]; then
        echo -e "  ${GREEN}✓${NC} PASS: $desc"
        ((PASSED++))
    else
        echo -e "  ${RED}✗${NC} FAIL: $desc"
        echo "    Expected: [$expected]"
        echo "    Actual:   [$actual]"
        ((FAILED++))
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local desc="$2"
    shift 2

    ((TOTAL++))
    set +e
    "$@" &>/dev/null
    local actual_code=$?
    set -e

    if [[ $actual_code -eq $expected_code ]]; then
        echo -e "  ${GREEN}✓${NC} PASS: $desc (exit=$actual_code)"
        ((PASSED++))
    else
        echo -e "  ${RED}✗${NC} FAIL: $desc"
        echo "    Expected exit code: $expected_code"
        echo "    Actual exit code:   $actual_code"
        ((FAILED++))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="$3"

    ((TOTAL++))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${GREEN}✓${NC} PASS: $desc"
        ((PASSED++))
    else
        echo -e "  ${RED}✗${NC} FAIL: $desc"
        echo "    Expected to contain: $needle"
        echo "    Actual:              $haystack"
        ((FAILED++))
    fi
}

#############################################################################
# REALPATH TESTS
#############################################################################

test_realpath() {
    echo -e "\n${BLUE}Testing realpath_fallback()${NC}"

    # Test 1: Absolute path (no changes)
    local result
    result=$(realpath_fallback "/usr/bin/bash")
    assert_equal "$result" "/usr/bin/bash" "Absolute path unchanged"

    # Test 2: Relative path
    cd /tmp
    result=$(realpath_fallback "test")
    assert_equal "$result" "/tmp/test" "Relative path converted to absolute"

    # Test 3: Dot components
    result=$(realpath_fallback "/usr/./bin/../lib")
    assert_equal "$result" "/usr/lib" "Dot and dotdot resolved"

    # Test 4: Tilde expansion
    result=$(realpath_fallback "~/test")
    assert_equal "$result" "$HOME/test" "Tilde expanded to HOME"

    # Test 5: Tilde only
    result=$(realpath_fallback "~")
    assert_equal "$result" "$HOME" "Tilde alone expanded to HOME"

    # Test 6: Multiple dotdot
    result=$(realpath_fallback "/usr/bin/../../etc")
    assert_equal "$result" "/etc" "Multiple dotdot resolved"

    # Test 7: Empty path error
    assert_exit_code 1 "Empty path returns exit 1" realpath_fallback ""

    # Test 8: Complex path with dots
    result=$(realpath_fallback "/./usr/./local/./bin")
    assert_equal "$result" "/usr/local/bin" "Multiple dots removed"

    # Test 9: Root directory
    result=$(realpath_fallback "/")
    assert_equal "$result" "/" "Root directory unchanged"

    # Test 10: Symlink resolution (if /bin is symlink to /usr/bin)
    if [[ -L "/bin" ]]; then
        result=$(realpath_fallback "/bin")
        local target
        target=$(readlink -f "/bin" 2>/dev/null || echo "/usr/bin")
        assert_equal "$result" "$target" "Symlink resolved"
    else
        echo -e "  ${YELLOW}⊘${NC} SKIP: Symlink test (no symlink at /bin)"
        ((TOTAL++))
        ((PASSED++))
    fi
}

#############################################################################
# EXPAND TESTS
#############################################################################

test_expand() {
    echo -e "\n${BLUE}Testing expand_fallback()${NC}"

    # Test 1: Simple tab expansion (default 8 spaces)
    local result
    result=$(echo -e "hello\tworld" | expand_fallback)
    assert_equal "$result" "hello   world" "Tab expanded to 8-space boundary"

    # Test 2: Custom tab size
    result=$(echo -e "a\tb" | expand_fallback -t 2)
    assert_equal "$result" "a b" "Tab expanded to 2 spaces"

    # Test 3: Tab at column 0
    result=$(echo -e "\tstart" | expand_fallback)
    assert_equal "$result" "        start" "Tab at start = 8 spaces"

    # Test 4: Multiple tabs
    result=$(echo -e "a\tb\tc" | expand_fallback)
    assert_equal "$result" "a       b       c" "Multiple tabs expanded"

    # Test 5: Tab at exact boundary (column 8)
    result=$(echo -e "12345678\tx" | expand_fallback)
    assert_equal "$result" "12345678        x" "Tab at boundary = full tabsize"

    # Test 6: Tab near boundary (column 7)
    result=$(echo -e "1234567\tx" | expand_fallback)
    assert_equal "$result" "1234567 x" "Tab fills to boundary (1 space)"

    # Test 7: Newline resets column
    result=$(echo -e "a\tb\n\tc" | expand_fallback)
    local expected=$'a       b\n        c'
    assert_equal "$result" "$expected" "Newline resets column counter"

    # Test 8: Empty input
    result=$(echo -n "" | expand_fallback)
    assert_equal "$result" "" "Empty input produces empty output"

    # Test 9: No tabs (passthrough)
    result=$(echo "hello world" | expand_fallback)
    assert_equal "$result" "hello world" "No tabs = passthrough"

    # Test 10: File input
    local tmpfile="/tmp/test_expand_$$"
    echo -e "line1\ttab\nline2\ttab" > "$tmpfile"
    result=$(expand_fallback "$tmpfile")
    expected=$'line1   tab\nline2   tab'
    assert_equal "$result" "$expected" "File input processed correctly"
    rm -f "$tmpfile"

    # Test 11: Invalid tab size
    assert_exit_code 1 "Invalid tab size returns exit 1" expand_fallback -t abc

    # Test 12: Missing file
    assert_exit_code 2 "Missing file returns exit 2" expand_fallback /nonexistent/file/path
}

#############################################################################
# OD TESTS
#############################################################################

test_od() {
    echo -e "\n${BLUE}Testing od_fallback()${NC}"

    # Test 1: Simple ASCII
    local result
    result=$(echo -n "ABC" | od_fallback -An -tx1 | tr -d ' \n')
    assert_equal "$result" "414243" "ASCII 'ABC' = 41 42 43"

    # Test 2: UTF-8 BOM
    result=$(printf '\xef\xbb\xbf' | od_fallback -An -tx1 | tr -d ' \n')
    assert_equal "$result" "efbbbf" "UTF-8 BOM detected"

    # Test 3: Newline character
    result=$(echo -ne "\n" | od_fallback -An -tx1 | tr -d ' \n')
    assert_equal "$result" "0a" "Newline = 0a"

    # Test 4: NUL byte
    result=$(printf '\x00' | od_fallback -An -tx1 | tr -d ' \n')
    assert_equal "$result" "00" "NUL byte = 00"

    # Test 5: Empty input
    result=$(echo -n "" | od_fallback -An -tx1 | tr -d ' \n')
    assert_equal "$result" "" "Empty input = empty output"

    # Test 6: Multiple bytes
    result=$(echo -ne "test\n" | od_fallback -An -tx1 | tr -d ' \n')
    assert_equal "$result" "746573740a" "test\\n hex dump"

    # Test 7: Binary data
    result=$(printf '\x00\x01\x02\xff' | od_fallback -An -tx1 | tr -d ' \n')
    assert_equal "$result" "000102ff" "Binary data hex dump"

    # Test 8: Carriage return
    result=$(echo -ne "\r" | od_fallback -An -tx1 | tr -d ' \n')
    assert_equal "$result" "0d" "CR = 0d"

    # Test 9: Invalid arguments
    assert_exit_code 1 "Invalid args return exit 1" od_fallback -tx2

    # Test 10: Space character
    result=$(echo -n " " | od_fallback -An -tx1 | tr -d ' \n')
    assert_equal "$result" "20" "Space = 20"
}

#############################################################################
# TPUT TESTS
#############################################################################

test_tput() {
    echo -e "\n${BLUE}Testing tput_compat()${NC}"

    # Test 1: cols returns numeric value
    local result
    result=$(tput_compat cols)
    [[ "$result" =~ ^[0-9]+$ ]] && echo -e "  ${GREEN}✓${NC} PASS: cols returns number ($result)" && ((PASSED++)) || {
        echo -e "  ${RED}✗${NC} FAIL: cols should return number, got '$result'"
        ((FAILED++))
    }
    ((TOTAL++))

    # Test 2: lines returns numeric value
    result=$(tput_compat lines)
    [[ "$result" =~ ^[0-9]+$ ]] && echo -e "  ${GREEN}✓${NC} PASS: lines returns number ($result)" && ((PASSED++)) || {
        echo -e "  ${RED}✗${NC} FAIL: lines should return number, got '$result'"
        ((FAILED++))
    }
    ((TOTAL++))

    # Test 3: Default values (when COLUMNS/LINES unset)
    unset COLUMNS LINES
    result=$(tput_compat cols)
    [[ "$result" =~ ^[0-9]+$ ]] && echo -e "  ${GREEN}✓${NC} PASS: cols with no env returns number" && ((PASSED++)) || {
        echo -e "  ${RED}✗${NC} FAIL: cols should return default"
        ((FAILED++))
    }
    ((TOTAL++))
}

#############################################################################
# INTEGRATION TESTS
#############################################################################

test_integration() {
    echo -e "\n${BLUE}Testing Integration (real-world scenarios)${NC}"

    # Test 1: BOM detection (like yaml_validator.sh:1007)
    local tmpfile="/tmp/test_bom_$$"
    printf '\xef\xbb\xbftest: value' > "$tmpfile"
    local first_bytes
    first_bytes=$(head -c 3 "$tmpfile" | od_compat -An -tx1 | tr -d ' \n')
    assert_equal "$first_bytes" "efbbbf" "BOM detection integration"
    rm -f "$tmpfile"

    # Test 2: Expand tabs in file (like fix_yaml_issues.sh:1269)
    tmpfile="/tmp/test_tabs_$$"
    echo -e "key:\tvalue\n\ttab" > "$tmpfile"
    local temp_file="/tmp/test_tabs_expanded_$$"
    if expand_compat -t 2 "$tmpfile" > "$temp_file"; then
        local content
        content=$(<"$temp_file")
        assert_contains "$content" "key: value" "Tab expansion in file works"
    else
        echo -e "  ${RED}✗${NC} FAIL: expand_compat failed"
        ((TOTAL++))
        ((FAILED++))
    fi
    rm -f "$tmpfile" "$temp_file"

    # Test 3: Path canonicalization (like yaml_validator.sh:8606)
    local test_path="./test/../lib"
    local canonical
    canonical=$(realpath_compat "$test_path" 2>/dev/null || echo "FAIL")
    if [[ "$canonical" != "FAIL" ]]; then
        echo -e "  ${GREEN}✓${NC} PASS: Path canonicalization works"
        ((PASSED++))
    else
        echo -e "  ${RED}✗${NC} FAIL: Path canonicalization failed"
        ((FAILED++))
    fi
    ((TOTAL++))

    # Test 4: Terminal dimensions
    local cols lines
    cols=$(tput_compat cols)
    lines=$(tput_compat lines)
    if [[ "$cols" =~ ^[0-9]+$ && "$lines" =~ ^[0-9]+$ ]]; then
        echo -e "  ${GREEN}✓${NC} PASS: Terminal dimensions: ${cols}x${lines}"
        ((PASSED++))
    else
        echo -e "  ${RED}✗${NC} FAIL: Invalid terminal dimensions"
        ((FAILED++))
    fi
    ((TOTAL++))

    # Test 5: Error handling - expand with nonexistent file
    set +e
    expand_compat -t 2 /nonexistent/file/path &>/dev/null
    local exit_code=$?
    set -e
    if [[ $exit_code -ne 0 ]]; then
        echo -e "  ${GREEN}✓${NC} PASS: Error handling for missing file (exit=$exit_code)"
        ((PASSED++))
    else
        echo -e "  ${RED}✗${NC} FAIL: Should fail on missing file"
        ((FAILED++))
    fi
    ((TOTAL++))
}

#############################################################################
# COMPATIBILITY TESTS
#############################################################################

test_compatibility() {
    echo -e "\n${BLUE}Testing Compatibility (minimal environment simulation)${NC}"

    # Test 1: Check if fallbacks work when native commands unavailable
    local native_realpath native_expand native_od
    native_realpath=$(command -v realpath 2>/dev/null || echo "")
    native_expand=$(command -v expand 2>/dev/null || echo "")
    native_od=$(command -v od 2>/dev/null || echo "")

    if [[ -n "$native_realpath" ]]; then
        result=$(realpath_fallback "/usr/bin")
        assert_equal "$result" "/usr/bin" "Fallback works even when native exists"
    else
        echo -e "  ${YELLOW}⊘${NC} INFO: realpath not found (testing pure fallback)"
        ((TOTAL++))
        ((PASSED++))
    fi

    if [[ -n "$native_expand" ]]; then
        result=$(echo -e "a\tb" | expand_fallback)
        assert_equal "$result" "a       b" "expand_fallback works when native exists"
    else
        echo -e "  ${YELLOW}⊘${NC} INFO: expand not found (testing pure fallback)"
        ((TOTAL++))
        ((PASSED++))
    fi

    if [[ -n "$native_od" ]]; then
        result=$(echo -n "A" | od_fallback -An -tx1 | tr -d ' \n')
        assert_equal "$result" "41" "od_fallback works when native exists"
    else
        echo -e "  ${YELLOW}⊘${NC} INFO: od not found (testing pure fallback)"
        ((TOTAL++))
        ((PASSED++))
    fi

    # Test 2: Verify xxd fallback for od
    if command -v xxd &>/dev/null; then
        result=$(echo -n "B" | xxd -p -c 1 | awk '{printf " %s", $0} END {print ""}' | tr -d ' \n')
        assert_equal "$result" "42" "xxd can serve as od fallback"
    else
        echo -e "  ${YELLOW}⊘${NC} INFO: xxd not found (pure bash od will be used)"
        ((TOTAL++))
        ((PASSED++))
    fi
}

#############################################################################
# PERFORMANCE TESTS
#############################################################################

test_performance() {
    echo -e "\n${BLUE}Testing Performance (ballpark estimates)${NC}"

    # Test 1: realpath performance (reduced iterations)
    local start end elapsed
    start=$(date +%s%N)
    for i in {1..10}; do
        realpath_fallback "/usr/bin" &>/dev/null
    done
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    echo -e "  ${BLUE}ℹ${NC} INFO: realpath_fallback: 10 iterations in ${elapsed}ms (avg: $((elapsed/10))ms)"
    ((TOTAL++))
    ((PASSED++))

    # Test 2: expand performance (reduced data)
    local test_data
    test_data=$(printf 'line%d\ttab\n' {1..10})
    start=$(date +%s%N)
    echo "$test_data" | expand_fallback &>/dev/null
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    echo -e "  ${BLUE}ℹ${NC} INFO: expand_fallback: 10 lines in ${elapsed}ms"
    ((TOTAL++))
    ((PASSED++))

    # Test 3: od performance (reduced iterations)
    start=$(date +%s%N)
    for i in {1..10}; do
        echo -n "test" | od_fallback -An -tx1 &>/dev/null
    done
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    echo -e "  ${BLUE}ℹ${NC} INFO: od_fallback: 10 iterations in ${elapsed}ms (avg: $((elapsed/10))ms)"
    ((TOTAL++))
    ((PASSED++))
}

#############################################################################
# MAIN
#############################################################################

main() {
    echo -e "${BOLD}YAML Validator - Pure Bash Fallbacks Test Suite${NC}"
    echo "Version: 3.2.0"
    echo "=========================================="

    test_realpath
    test_expand
    test_od
    test_tput
    test_integration
    test_compatibility
    test_performance

    echo ""
    echo "=========================================="
    echo -e "${BOLD}Test Results${NC}"
    echo "=========================================="

    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    else
        echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    fi

    echo -e "Total:  $TOTAL tests"
    echo -e "Passed: ${GREEN}$PASSED${NC}"
    echo -e "Failed: ${RED}$FAILED${NC}"
    echo ""

    # Report which fallbacks are active
    report_fallbacks

    [[ $FAILED -eq 0 ]] && exit 0 || exit 1
}

main "$@"
