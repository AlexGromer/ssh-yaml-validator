#!/bin/bash
# YAML Validator v3.3.1 - Baseline Performance Benchmark

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$PROJECT_ROOT/yaml_validator.sh"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

# Test configuration
TEST_DIR="/tmp/yaml_validator_perf_test"
NUM_FILES=100
RESULTS_FILE="${RESULTS_FILE:-/tmp/benchmark_baseline_results.txt}"

echo "=========================================="
echo "YAML Validator - Baseline Benchmark"
echo "=========================================="
echo

# Cleanup
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
data:
  key1: value1
EOF
done

echo "Running baseline benchmark..."
START=$(date +%s)
"$VALIDATOR" --no-parallel "$TEST_DIR"/*.yaml > /dev/null 2>&1
END=$(date +%s)
DURATION=$((END - START))

echo -e "${GREEN}Baseline: ${DURATION}s for $NUM_FILES files${NC}"

# Save results
cat > "$RESULTS_FILE" << EOF
duration=$DURATION
files=$NUM_FILES
EOF

echo "✓ Results saved to: $RESULTS_FILE"
