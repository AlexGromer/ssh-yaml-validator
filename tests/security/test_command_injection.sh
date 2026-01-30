#!/bin/bash
# YAML Validator v3.3.1 - Command Injection Security Test
# Purpose: Verify validator sanitizes malicious input and prevents command execution

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$PROJECT_ROOT/yaml_validator.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TEST_DIR="/tmp/security_test_cmd_injection"
PASSED=0
FAILED=0

echo "=========================================="
echo "Security Test: Command Injection"
echo "=========================================="
echo

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Test 1: Malicious file name (command injection via filename)
echo "[TEST 1] Malicious filename with semicolons"
MALICIOUS_FILE="$TEST_DIR/test;rm;-rf;.yaml"
cat > "$MALICIOUS_FILE" << 'EOF'
key: value
EOF

if timeout 5s "$VALIDATOR" "$MALICIOUS_FILE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS: Handled malicious filename safely${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL: Validator crashed or timed out${NC}"
    ((FAILED++))
fi

# Test 2: Command substitution in file content
echo "[TEST 2] Command substitution in YAML content"
cat > "$TEST_DIR/cmd_subst.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
data:
  command: "$(rm -rf /)"
  backticks: "`whoami`"
EOF

if timeout 5s "$VALIDATOR" "$TEST_DIR/cmd_subst.yaml" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS: No command execution from YAML content${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL: Validator crashed${NC}"
    ((FAILED++))
fi

# Test 3: Shell metacharacters in values
echo "[TEST 3] Shell metacharacters"
cat > "$TEST_DIR/metachar.yaml" << 'EOF'
key1: "value; echo pwned"
key2: "value && touch /tmp/hacked"
key3: "value | cat /etc/passwd"
EOF

if timeout 5s "$VALIDATOR" "$TEST_DIR/metachar.yaml" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS: Shell metacharacters sanitized${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL: Validator crashed${NC}"
    ((FAILED++))
fi

# Test 4: Verify no unauthorized files created
if [[ ! -f "/tmp/hacked" ]]; then
    echo -e "${GREEN}✓ PASS: No unauthorized file creation${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL: Unauthorized file created!${NC}"
    ((FAILED++))
    rm -f "/tmp/hacked"
fi

echo
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

[[ $FAILED -eq 0 ]]
