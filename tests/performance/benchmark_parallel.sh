#!/bin/bash
# YAML Validator v3.3.1 - Parallel Performance Benchmark
# Purpose: Measure parallel validation performance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$PROJECT_ROOT/yaml_validator.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Test configuration
TEST_DIR="/tmp/yaml_validator_perf_test"
NUM_FILES=100
MIN_SPEEDUP=5.0  # Minimum 5x speedup required

# Results file
RESULTS_FILE="${RESULTS_FILE:-/tmp/benchmark_parallel_results.txt}"
BASELINE_FILE="${BASELINE_FILE:-/tmp/benchmark_baseline_results.txt}"

echo "=========================================="
echo "YAML Validator - Parallel Benchmark"
echo "=========================================="
echo

# Check if baseline exists
if [[ ! -f "$BASELINE_FILE" ]]; then
    echo -e "${RED}ERROR: Baseline results not found${NC}"
    echo "Please run benchmark_baseline.sh first"
    exit 1
fi

# Read baseline duration
BASELINE_DURATION=$(grep "^duration=" "$BASELINE_FILE" | cut -d= -f2)

# Cleanup and setup
cleanup() {
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_DIR"

# Generate test files
echo "Generating $NUM_FILES test YAML files..."
for i in $(seq 1 $NUM_FILES); do
    cat > "$TEST_DIR/test_${i}.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-config-${i}
  namespace: default
  labels:
    app: test
    version: "1.0"
data:
  key1: value1
  key2: value2
  key3: |
    multiline
    content
    here
EOF
done

echo "Files generated: $NUM_FILES"
echo

# Benchmark: Parallel mode
echo "Running parallel benchmark..."
START_TIME=$(date +%s.%N)

"$VALIDATOR" --parallel "$TEST_DIR"/*.yaml > /dev/null 2>&1

END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | awk "{print $1}")

# Calculate speedup
SPEEDUP=$(echo "$BASELINE_DURATION / $DURATION" | awk "{print $1}")

echo
echo -e "${GREEN}Parallel Results:${NC}"
echo "  Files:    $NUM_FILES"
echo "  Time:     ${DURATION}s"
echo "  Baseline: ${BASELINE_DURATION}s"
echo "  Speedup:  ${SPEEDUP}x"
echo

# Save results
cat > "$RESULTS_FILE" << EOF
# Parallel Benchmark Results
timestamp=$(date -Iseconds)
files=$NUM_FILES
duration=$DURATION
baseline=$BASELINE_DURATION
speedup=$SPEEDUP
mode=parallel
EOF

echo -e "${GREEN}✓ Results saved to: $RESULTS_FILE${NC}"
echo

# Assertion: Check minimum speedup
if (( $(echo "$SPEEDUP >= $MIN_SPEEDUP" | awk "{print $1}" -l) )); then
    echo -e "${GREEN}✓ PASS: Speedup ${SPEEDUP}x >= ${MIN_SPEEDUP}x${NC}"
    EXIT_CODE=0
else
    echo -e "${RED}✗ FAIL: Speedup ${SPEEDUP}x < ${MIN_SPEEDUP}x (expected minimum)${NC}"
    EXIT_CODE=1
fi

echo
echo "=========================================="
echo "Summary:"
echo "  ✓ Parallel: ${DURATION}s (${SPEEDUP}x faster)"
echo "  ✓ Next: Run benchmark_incremental.sh"
echo "=========================================="

exit $EXIT_CODE
