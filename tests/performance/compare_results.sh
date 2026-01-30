#!/bin/bash
# YAML Validator v3.3.1 - Performance Comparison Report
# Purpose: Generate comprehensive performance comparison report

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Results files
BASELINE_FILE="/tmp/benchmark_baseline_results.txt"
PARALLEL_FILE="/tmp/benchmark_parallel_results.txt"
INCREMENTAL_FILE="/tmp/benchmark_incremental_results.txt"

echo "=========================================="
echo "YAML Validator - Performance Report"
echo "=========================================="
echo

# Check if all results exist
MISSING=0
[[ ! -f "$BASELINE_FILE" ]] && echo -e "${RED}✗ Missing: baseline results${NC}" && MISSING=1
[[ ! -f "$PARALLEL_FILE" ]] && echo -e "${RED}✗ Missing: parallel results${NC}" && MISSING=1
[[ ! -f "$INCREMENTAL_FILE" ]] && echo -e "${RED}✗ Missing: incremental results${NC}" && MISSING=1

if [[ $MISSING -eq 1 ]]; then
    echo
    echo "Please run all benchmarks first:"
    echo "  1. ./benchmark_baseline.sh"
    echo "  2. ./benchmark_parallel.sh"
    echo "  3. ./benchmark_incremental.sh"
    exit 1
fi

# Read results
BASELINE_DURATION=$(grep "^duration=" "$BASELINE_FILE" | cut -d= -f2)
PARALLEL_DURATION=$(grep "^duration=" "$PARALLEL_FILE" | cut -d= -f2)
INCREMENTAL_DURATION=$(grep "^duration=" "$INCREMENTAL_FILE" | cut -d= -f2)

PARALLEL_SPEEDUP=$(grep "^speedup=" "$PARALLEL_FILE" | cut -d= -f2)
INCREMENTAL_SPEEDUP=$(grep "^speedup=" "$INCREMENTAL_FILE" | cut -d= -f2)

NUM_FILES=$(grep "^files=" "$BASELINE_FILE" | cut -d= -f2)

# Display comparison table
echo
echo -e "${BLUE}Performance Comparison (${NUM_FILES} files):${NC}"
echo
printf "%-20s | %-12s | %-10s | %-10s\n" "Mode" "Time" "Speedup" "Status"
echo "---------------------+--------------+------------+------------"
printf "%-20s | %-12s | %-10s | %-10s\n" "Baseline (sequential)" "${BASELINE_DURATION}s" "1.0x" "✓"
printf "%-20s | %-12s | %-10s | " "Parallel" "${PARALLEL_DURATION}s" "${PARALLEL_SPEEDUP}x"
if (( $(echo "$PARALLEL_SPEEDUP >= 5.0" | awk "{print $1}" -l) )); then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
fi
printf "%-20s | %-12s | %-10s | " "Incremental (2nd)" "${INCREMENTAL_DURATION}s" "${INCREMENTAL_SPEEDUP}x"
if (( $(echo "$INCREMENTAL_SPEEDUP >= 30.0" | awk "{print $1}" -l) )); then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
fi

echo
echo -e "${BLUE}Performance Metrics:${NC}"
echo "  Baseline:     ${BASELINE_DURATION}s  (100%)"
echo "  Parallel:     ${PARALLEL_DURATION}s  ($(echo "scale=1; 100 / $PARALLEL_SPEEDUP" | awk "{print $1}")% of baseline)"
echo "  Incremental:  ${INCREMENTAL_DURATION}s  ($(echo "scale=1; 100 / $INCREMENTAL_SPEEDUP" | awk "{print $1}")% of baseline)"

echo
echo -e "${BLUE}Speedup Summary:${NC}"
echo "  Sequential → Parallel:     ${PARALLEL_SPEEDUP}x faster"
echo "  Sequential → Incremental:  ${INCREMENTAL_SPEEDUP}x faster"

echo
echo -e "${BLUE}Recommendations:${NC}"
echo "  • Use --parallel for initial validation of many files (${PARALLEL_SPEEDUP}x speedup)"
echo "  • Use --incremental for CI/CD pipelines (${INCREMENTAL_SPEEDUP}x speedup on unchanged files)"
echo "  • Combine modes for maximum performance: --parallel --incremental"

echo
echo "=========================================="
echo "✓ Performance benchmarks complete"
echo "=========================================="
