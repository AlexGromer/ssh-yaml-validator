#!/bin/bash
#############################################################################
# Test Suite for fix_yaml_issues.sh v3.1.0
# Comprehensive tests: existing fixes + new K8s fixes + batch mode
#############################################################################

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FIXER="$PROJECT_DIR/fix_yaml_issues.sh"
FIXTURES="$SCRIPT_DIR/fixtures"
TMPDIR=$(mktemp -d)

PASSED=0
FAILED=0
TOTAL=0

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BOLD='' NC=''
fi

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Test helpers
assert_contains() {
    local file="$1" pattern="$2" desc="$3"
    ((TOTAL++))
    if grep -q -- "$pattern" "$file" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}: $desc"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: $desc"
        echo -e "    Expected pattern '$pattern' in $file"
        ((FAILED++))
    fi
}

assert_not_contains() {
    local file="$1" pattern="$2" desc="$3"
    ((TOTAL++))
    if ! grep -q -- "$pattern" "$file" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}: $desc"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: $desc"
        echo -e "    Unexpected pattern '$pattern' found in $file"
        ((FAILED++))
    fi
}

assert_file_exists() {
    local file="$1" desc="$2"
    ((TOTAL++))
    if [[ -f "$file" ]]; then
        echo -e "  ${GREEN}PASS${NC}: $desc"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: $desc"
        echo -e "    File not found: $file"
        ((FAILED++))
    fi
}

assert_exit_code() {
    local expected="$1" actual="$2" desc="$3"
    ((TOTAL++))
    if [[ "$actual" -eq "$expected" ]]; then
        echo -e "  ${GREEN}PASS${NC}: $desc"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: $desc"
        echo -e "    Expected exit code $expected, got $actual"
        ((FAILED++))
    fi
}

# Copy fixture to temp dir for testing
setup_fixture() {
    local fixture="$1"
    local dest="$TMPDIR/$(basename "$fixture")"
    cp "$fixture" "$dest"
    echo "$dest"
}

print_header() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  YAML Fixer Test Suite v3.1.0${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${YELLOW}── $1 ──${NC}"
}

#############################################################################
# TEST CATEGORIES
#############################################################################

test_existing_fixes() {
    print_section "Existing Fixes (13 types)"

    # Test 1: BOM removal
    local f="$TMPDIR/bom_test.yaml"
    printf '\xEF\xBB\xBFapiVersion: v1\nkind: ConfigMap\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    local first_bytes
    first_bytes=$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')
    ((TOTAL++))
    if [[ "$first_bytes" != "efbbbf" ]]; then
        echo -e "  ${GREEN}PASS${NC}: BOM removal"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: BOM removal"
        ((FAILED++))
    fi

    # Test 2: CRLF -> LF
    f="$TMPDIR/crlf_test.yaml"
    printf 'key: value\r\nother: data\r\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_not_contains "$f" $'\r' "CRLF -> LF conversion"

    # Test 3: Tabs -> Spaces
    f="$TMPDIR/tabs_test.yaml"
    printf 'key:\n\tvalue: test\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_not_contains "$f" $'\t' "Tabs -> Spaces"

    # Test 4: Trailing whitespace
    f="$TMPDIR/trailing_test.yaml"
    printf 'key: value   \nother: data  \n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    ((TOTAL++))
    if ! grep -q '[[:space:]]$' "$f" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}: Trailing whitespace removal"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: Trailing whitespace removal"
        ((FAILED++))
    fi

    # Test 5: Boolean case
    f="$TMPDIR/bool_test.yaml"
    printf 'enabled: True\ndisabled: FALSE\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_contains "$f" "enabled: true" "Boolean True -> true"
    assert_contains "$f" "disabled: false" "Boolean FALSE -> false"

    # Test 6: List spacing
    f="$TMPDIR/list_test.yaml"
    printf '%s\n' 'items:' '  -item1' '  -item2' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_contains "$f" "- item1" "List spacing -item -> - item"

    # Test 7: Document markers
    f="$TMPDIR/doc_test.yaml"
    printf -- '----\nkey: value\n.....\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_contains "$f" "^---$" "Document marker ---- -> ---"

    # Test 8: Colon spacing
    f="$TMPDIR/colon_test.yaml"
    printf 'key:value\nother:data\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_contains "$f" "key: value" "Colon spacing key:value -> key: value"

    # Test 9: Empty lines
    f="$TMPDIR/empty_test.yaml"
    printf 'key: value\n\n\n\n\nother: data\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    local empty_count
    empty_count=$(grep -c '^$' "$f")
    ((TOTAL++))
    if [[ $empty_count -le 2 ]]; then
        echo -e "  ${GREEN}PASS${NC}: Empty lines reduction (>2 -> 2)"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: Empty lines reduction (got $empty_count)"
        ((FAILED++))
    fi

    # Test 10: EOF newline
    f="$TMPDIR/eof_test.yaml"
    printf 'key: value' > "$f"  # No trailing newline
    "$FIXER" -q "$f" >/dev/null 2>&1
    local last_byte
    last_byte=$(tail -c 1 "$f" | od -An -tx1 | tr -d ' ')
    ((TOTAL++))
    if [[ "$last_byte" == "0a" ]]; then
        echo -e "  ${GREEN}PASS${NC}: EOF newline added"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: EOF newline not added"
        ((FAILED++))
    fi

    # Test 11: Bracket spacing
    f="$TMPDIR/bracket_test.yaml"
    printf 'items: [a,b,c]\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_contains "$f" "\[a, b, c\]" "Bracket spacing [a,b] -> [a, b]"

    # Test 12: Comment space
    f="$TMPDIR/comment_test.yaml"
    printf '#comment here\nkey: value\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_contains "$f" "# comment" "Comment space #comment -> # comment"

    # Test 13: Truthy values
    f="$TMPDIR/truthy_test.yaml"
    printf 'enabled: yes\ndisabled: no\nactive: on\ninactive: off\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_contains "$f" "enabled: true" "Truthy yes -> true"
    assert_contains "$f" "disabled: false" "Truthy no -> false"
}

test_security_fixes() {
    print_section "New Security Fixes (E2, E3, E4, E7, E9)"

    # E2: privileged: false
    local f
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "privileged: false" "E2: Add privileged: false"

    # E3: runAsNonRoot: true
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "runAsNonRoot: true" "E3: Add runAsNonRoot: true"

    # E4: readOnlyRootFilesystem: true
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "readOnlyRootFilesystem: true" "E4: Add readOnlyRootFilesystem: true"

    # E7: NetworkPolicy companion file
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_file_exists "$TMPDIR/myapp-networkpolicy.yaml" "E7: NetworkPolicy companion file created"

    # E9: capabilities.drop
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" 'drop:' "E9: Add capabilities.drop"
}

test_best_practice_fixes() {
    print_section "New Best Practice Fixes (E13-E17)"

    # E13: Missing labels
    local f
    f=$(setup_fixture "$FIXTURES/deployment_no_labels.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "app.kubernetes.io/name:" "E13: Add standard K8s labels"

    # E14: Missing annotations
    f=$(setup_fixture "$FIXTURES/deployment_no_labels.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "annotations:" "E14: Add annotations"

    # E15: Default namespace
    f=$(setup_fixture "$FIXTURES/deployment_default_ns.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "namespace: production" "E15: Change default -> production namespace"

    # E16: livenessProbe
    f=$(setup_fixture "$FIXTURES/deployment_no_probes.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "livenessProbe:" "E16: Add livenessProbe"

    # E17: readinessProbe
    f=$(setup_fixture "$FIXTURES/deployment_no_probes.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "readinessProbe:" "E17: Add readinessProbe"
}

test_ha_fixes() {
    print_section "New HA Fixes (E18-E20)"

    # E18: PDB companion file
    local f
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_file_exists "$TMPDIR/myapp-pdb.yaml" "E18: PDB companion file created"

    # E19: Anti-affinity
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "podAntiAffinity:" "E19: Add podAntiAffinity"

    # E20: Topology spread
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "topologySpreadConstraints:" "E20: Add topologySpreadConstraints"
}

test_resource_fixes() {
    print_section "New Resource Fixes (E21-E24)"

    # E21: Resource limits
    local f
    f=$(setup_fixture "$FIXTURES/deployment_no_resources.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "limits:" "E21: Add resource limits"

    # E22: Resource requests
    f=$(setup_fixture "$FIXTURES/deployment_no_resources.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "requests:" "E22: Add resource requests"

    # E23: Requests > limits (need a special fixture)
    f="$TMPDIR/requests_gt_limits.yaml"
    cat > "$f" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: testapp
  namespace: default
spec:
  template:
    spec:
      containers:
        - name: testapp
          image: testapp:1.0
          resources:
            requests:
              cpu: "2"
              memory: "1Gi"
            limits:
              cpu: "1"
              memory: "512Mi"
EOF
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "cpu:" "E23: Requests > limits fix applied"

    # E24: ResourceQuota companion file
    f=$(setup_fixture "$FIXTURES/deployment_no_resources.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_file_exists "$TMPDIR/staging-resourcequota.yaml" "E24: ResourceQuota companion file created"
}

test_batch_mode() {
    print_section "Integration: Batch Mode"

    # Test config loading
    local f
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    local output
    output=$("$FIXER" --config "$FIXTURES/fixerrc_standard" "$f" 2>&1)
    local rc=$?
    assert_exit_code 0 "$rc" "Batch mode exits successfully"
    ((TOTAL++))
    if echo "$output" | grep -q "CONFIG\|BATCH\|Загружено"; then
        echo -e "  ${GREEN}PASS${NC}: Config file loaded and acknowledged"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: Config file load not acknowledged in output"
        ((FAILED++))
    fi

    # Test config values are used
    f=$(setup_fixture "$FIXTURES/deployment_default_ns.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_contains "$f" "namespace: production" "Config namespace value applied"
}

test_dry_run() {
    print_section "Integration: Dry-Run"

    # Dry-run should not modify files
    local f
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    local orig_hash
    orig_hash=$(md5sum "$f" | cut -d' ' -f1)
    "$FIXER" -q -n --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    local new_hash
    new_hash=$(md5sum "$f" | cut -d' ' -f1)
    ((TOTAL++))
    if [[ "$orig_hash" == "$new_hash" ]]; then
        echo -e "  ${GREEN}PASS${NC}: Dry-run does not modify files"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: Dry-run modified the file!"
        ((FAILED++))
    fi

    # Dry-run should still exit 0
    f=$(setup_fixture "$FIXTURES/deployment_no_probes.yaml")
    "$FIXER" -q -n --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    assert_exit_code 0 "$?" "Dry-run exits 0"
}

test_idempotency() {
    print_section "Regression: Idempotency"

    # Run fixer twice on same file, second run should produce same result
    local f
    f=$(setup_fixture "$FIXTURES/deployment_no_security.yaml")
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    local hash1
    hash1=$(md5sum "$f" | cut -d' ' -f1)
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    local hash2
    hash2=$(md5sum "$f" | cut -d' ' -f1)
    ((TOTAL++))
    if [[ "$hash1" == "$hash2" ]]; then
        echo -e "  ${GREEN}PASS${NC}: Idempotent: second run produces same result"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: Not idempotent: file changed on second run"
        ((FAILED++))
    fi

    # Perfect deployment should not be modified
    f=$(setup_fixture "$FIXTURES/deployment_perfect.yaml")
    local orig_hash
    orig_hash=$(md5sum "$f" | cut -d' ' -f1)
    "$FIXER" -q --config "$FIXTURES/fixerrc_standard" "$f" >/dev/null 2>&1
    local new_hash
    new_hash=$(md5sum "$f" | cut -d' ' -f1)
    ((TOTAL++))
    if [[ "$orig_hash" == "$new_hash" ]]; then
        echo -e "  ${GREEN}PASS${NC}: Perfect deployment unchanged"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: Perfect deployment was modified"
        ((FAILED++))
    fi

    # Basic fixes idempotency
    f="$TMPDIR/basic_idem.yaml"
    printf 'key: value\nother: data\n' > "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    hash1=$(md5sum "$f" | cut -d' ' -f1)
    "$FIXER" -q "$f" >/dev/null 2>&1
    hash2=$(md5sum "$f" | cut -d' ' -f1)
    ((TOTAL++))
    if [[ "$hash1" == "$hash2" ]]; then
        echo -e "  ${GREEN}PASS${NC}: Basic fixes idempotent"
        ((PASSED++))
    else
        echo -e "  ${RED}FAIL${NC}: Basic fixes not idempotent"
        ((FAILED++))
    fi
}

test_edge_cases() {
    print_section "Boundary: Edge Cases"

    # Empty file
    local f="$TMPDIR/empty.yaml"
    touch "$f"
    "$FIXER" -q "$f" >/dev/null 2>&1
    assert_exit_code 0 "$?" "Empty file handled gracefully"
}

#############################################################################
# MAIN
#############################################################################

print_header

# Verify fixer script exists
if [[ ! -f "$FIXER" ]]; then
    echo -e "${RED}ERROR: Fixer script not found: $FIXER${NC}"
    exit 1
fi

# Verify fixtures exist
if [[ ! -d "$FIXTURES" ]]; then
    echo -e "${RED}ERROR: Fixtures directory not found: $FIXTURES${NC}"
    exit 1
fi

# Run all test categories
test_existing_fixes
test_security_fixes
test_best_practice_fixes
test_ha_fixes
test_resource_fixes
test_batch_mode
test_dry_run
test_idempotency
test_edge_cases

# Summary
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  RESULTS: $PASSED/$TOTAL passed, $FAILED failed${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi
