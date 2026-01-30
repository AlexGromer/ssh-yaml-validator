#!/bin/bash
# YAML Validator v3.3.1 - Run All Security Tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "YAML Validator - Security Test Suite"
echo "=========================================="
echo

TOTAL_PASSED=0
TOTAL_FAILED=0

# Test 1: Command Injection
echo -e "${BLUE}[1/3] Command Injection Tests${NC}"
if "$SCRIPT_DIR/test_command_injection.sh"; then
    echo -e "${GREEN}✓ Command Injection: PASS${NC}"
else
    echo -e "${RED}✗ Command Injection: FAIL${NC}"
    ((TOTAL_FAILED++))
fi
echo

# Test 2: Path Traversal
echo -e "${BLUE}[2/3] Path Traversal Tests${NC}"
if "$SCRIPT_DIR/test_path_traversal.sh"; then
    echo -e "${GREEN}✓ Path Traversal: PASS${NC}"
else
    echo -e "${RED}✗ Path Traversal: FAIL${NC}"
    ((TOTAL_FAILED++))
fi
echo

# Test 3: Secrets Detection
echo -e "${BLUE}[3/3] Secrets Detection Tests${NC}"
if "$SCRIPT_DIR/test_secrets_detection.sh"; then
    echo -e "${GREEN}✓ Secrets Detection: PASS${NC}"
else
    echo -e "${RED}✗ Secrets Detection: FAIL${NC}"
    ((TOTAL_FAILED++))
fi
echo

echo "=========================================="
if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All security tests PASSED${NC}"
    exit 0
else
    echo -e "${RED}✗ Some security tests FAILED${NC}"
    exit 1
fi
