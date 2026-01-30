#!/bin/bash
# YAML Validator v3.3.1 - Performance Test Suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$PROJECT_ROOT/yaml_validator.sh"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_DIR="/tmp/yaml_perf_test"
NUM_FILES=100

echo "=========================================="
echo "Performance Test Suite v3.3.1"
echo "=========================================="
echo

# Setup
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

echo "Generating $NUM_FILES test files..."
for i in $(seq 1 $NUM_FILES); do
    cat > "$TEST_DIR/test_${i}.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: config-${i}
  namespace: default
data:
  key1: value1
  key2: value2
EOF
done

echo
echo -e "${BLUE}[1/3] Baseline (sequential, no cache)${NC}"
START=$(date +%s)
"$VALIDATOR" --no-parallel --recursive "$TEST_DIR" > /dev/null 2>&1
END=$(date +%s)
BASELINE=$((END - START))
echo "Time: ${BASELINE}s"

echo
echo -e "${BLUE}[2/3] Parallel mode${NC}"
START=$(date +%s)
"$VALIDATOR" --parallel --recursive "$TEST_DIR" > /dev/null 2>&1
END=$(date +%s)
PARALLEL=$((END - START))
[[ $PARALLEL -eq 0 ]] && PARALLEL=1  # Prevent division by zero
PARALLEL_SPEEDUP=$((BASELINE / PARALLEL))
echo "Time: ${PARALLEL}s (${PARALLEL_SPEEDUP}x speedup)"

echo
echo -e "${BLUE}[3/3] Incremental (2nd run)${NC}"
# First run
"$VALIDATOR" --incremental --recursive "$TEST_DIR" > /dev/null 2>&1
# Second run (cached)
START=$(date +%s)
"$VALIDATOR" --incremental --recursive "$TEST_DIR" > /dev/null 2>&1
END=$(date +%s)
INCR=$((END - START))
[[ $INCR -eq 0 ]] && INCR=1
INCR_SPEEDUP=$((BASELINE / INCR))
echo "Time: ${INCR}s (${INCR_SPEEDUP}x speedup)"

echo
echo "=========================================="
echo -e "${GREEN}Performance Summary${NC}"
echo "=========================================="
echo "Baseline:     ${BASELINE}s (100%)"
echo "Parallel:     ${PARALLEL}s (${PARALLEL_SPEEDUP}x faster)"
echo "Incremental:  ${INCR}s (${INCR_SPEEDUP}x faster)"
echo "=========================================="

# Cleanup
rm -rf "$TEST_DIR"

echo -e "${GREEN}✓ All benchmarks complete${NC}"
