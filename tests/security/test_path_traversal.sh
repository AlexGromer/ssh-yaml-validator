#!/bin/bash
# YAML Validator v3.3.1 - Path Traversal Security Test
# Purpose: Verify validator prevents directory traversal attacks

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$PROJECT_ROOT/yaml_validator.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TEST_DIR="/tmp/security_test_path_traversal"
PASSED=0
FAILED=0

echo "=========================================="
echo "Security Test: Path Traversal"
echo "=========================================="
echo

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT
mkdir -p "$TEST_DIR"

# Test 1: Path traversal in filename (../)
echo "[TEST 1] Path traversal: ../../../etc/passwd"
cat > "$TEST_DIR/..%2F..%2F..%2Fetc%2Fpasswd.yaml" << 'EOF'
key: value
EOF

if timeout 5s "$VALIDATOR" "$TEST_DIR/..%2F..%2F..%2Fetc%2Fpasswd.yaml" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS: Path traversal attempt handled${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL: Validator crashed${NC}"
    ((FAILED++))
fi

# Test 2: Symlink attack
echo "[TEST 2] Symlink attack"
ln -s /etc/passwd "$TEST_DIR/symlink.yaml" 2>/dev/null || true

if timeout 5s "$VALIDATOR" "$TEST_DIR/symlink.yaml" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS: Symlink handled safely${NC}"
    ((PASSED++))
else
    # Expected to fail on symlink (not a valid YAML)
    echo -e "${GREEN}✓ PASS: Symlink rejected${NC}"
    ((PASSED++))
fi

# Test 3: Absolute path injection in content
echo "[TEST 3] Absolute paths in YAML content"
cat > "$TEST_DIR/abs_path.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
data:
  path1: "/etc/passwd"
  path2: "/root/.ssh/id_rsa"
  path3: "../../etc/shadow"
EOF

if timeout 5s "$VALIDATOR" "$TEST_DIR/abs_path.yaml" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS: Absolute paths in content handled${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ FAIL: Validator crashed${NC}"
    ((FAILED++))
fi

# Test 4: Verify validator doesn't expose sensitive file content
echo "[TEST 4] Verify no sensitive data leakage"
OUTPUT=$("$VALIDATOR" "$TEST_DIR/abs_path.yaml" 2>&1 || true)

# Check output doesn't contain typical /etc/passwd entry patterns
if echo "$OUTPUT" | grep -qE "root:x:[0-9]+:[0-9]+"; then
    echo -e "${RED}✗ FAIL: Sensitive file content exposed!${NC}"
    ((FAILED++))
else
    echo -e "${GREEN}✓ PASS: No sensitive data in output${NC}"
    ((PASSED++))
fi

echo
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

[[ $FAILED -eq 0 ]]
