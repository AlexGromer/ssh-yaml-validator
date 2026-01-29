#!/bin/bash

# Quick minimal environment test
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/fallbacks.sh"

GREEN='\033[0;32m'
NC='\033[0m'

echo "Quick Minimal Environment Test"
echo "==============================="

TMPDIR="/tmp/yaml_test_$$"
mkdir -p "$TMPDIR"

# Test 1: od_compat works for BOM
echo -n "1. BOM detection via od_compat... "
printf '\xef\xbb\xbf' | od_compat -An -tx1 | tr -d ' \n' | grep -q "efbbbf" && echo -e "${GREEN}✓${NC}" || exit 1

# Test 2: expand_compat works for tabs
echo -n "2. Tab expansion via expand_compat... "
echo -e 'a\tb' | expand_compat | grep -q 'a       b' && echo -e "${GREEN}✓${NC}" || exit 1

# Test 3: realpath_compat works
echo -n "3. Path canonicalization via realpath_compat... "
[[ "$(realpath_compat /usr/bin)" == "/usr/bin" ]] && echo -e "${GREEN}✓${NC}" || exit 1

# Test 4: tput_compat returns dimensions
echo -n "4. Terminal dimensions via tput_compat... "
[[ "$(tput_compat cols)" =~ ^[0-9]+$ ]] && echo -e "${GREEN}✓${NC}" || exit 1

# Test 5: Scripts load fallback library
echo -n "5. Validator sources fallbacks... "
grep -q "source.*fallbacks.sh" "$SCRIPT_DIR/../yaml_validator.sh" && echo -e "${GREEN}✓${NC}" || exit 1

echo -n "6. Fixer sources fallbacks... "
grep -q "source.*fallbacks.sh" "$SCRIPT_DIR/../fix_yaml_issues.sh" && echo -e "${GREEN}✓${NC}" || exit 1

rm -rf "$TMPDIR"

echo ""
echo -e "${GREEN}All tests passed!${NC}"
echo "Fallbacks are integrated and working."
