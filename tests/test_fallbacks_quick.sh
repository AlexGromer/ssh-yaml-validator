#!/bin/bash

# Quick fallback tests
set -e

source "$(dirname "$0")/../lib/fallbacks.sh"

echo "Quick Fallback Tests"
echo "===================="

# Test realpath
echo -n "realpath_fallback... "
[[ "$(realpath_fallback /usr/bin)" == "/usr/bin" ]] && echo "✓" || { echo "✗"; exit 1; }

# Test expand
echo -n "expand_fallback... "
[[ "$(echo -e 'a\tb' | expand_fallback)" == "a       b" ]] && echo "✓" || { echo "✗"; exit 1; }

# Test od
echo -n "od_fallback... "
[[ "$(echo -n 'A' | od_fallback -An -tx1 | tr -d ' \n')" == "41" ]] && echo "✓" || { echo "✗"; exit 1; }

# Test tput
echo -n "tput_compat... "
[[ "$(tput_compat cols)" =~ ^[0-9]+$ ]] && echo "✓" || { echo "✗"; exit 1; }

# Test wrappers
echo -n "realpath_compat... "
[[ "$(realpath_compat /tmp)" == "/tmp" ]] && echo "✓" || { echo "✗"; exit 1; }

echo -n "expand_compat... "
[[ "$(echo -e 'x\ty' | expand_compat)" == "x       y" ]] && echo "✓" || { echo "✗"; exit 1; }

echo -n "od_compat... "
[[ "$(echo -n 'B' | od_compat -An -tx1 | tr -d ' \n')" == "42" ]] && echo "✓" || { echo "✗"; exit 1; }

echo ""
echo "All quick tests passed!"
report_fallbacks
