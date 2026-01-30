#!/bin/bash
# Parallel Processing Module for YAML Validator v3.3.0
# Provides multi-core file processing capabilities

# ============================================================================
# PARALLEL PROCESSING FUNCTIONS
# ============================================================================

# ----------------------------------------------------------------------------
# detect_cpu_cores - Auto-detect available CPU cores
# ----------------------------------------------------------------------------
detect_cpu_cores() {
    local cores=4  # Default fallback
    
    # Try multiple methods
    if command -v nproc &>/dev/null; then
        cores=$(nproc 2>/dev/null || echo "4")
    elif [[ -f /proc/cpuinfo ]]; then
        cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "4")
    elif command -v sysctl &>/dev/null; then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")
    fi
    
    # Sanity check (1-64 cores)
    if [[ $cores -lt 1 || $cores -gt 64 ]]; then
        cores=4
    fi
    
    echo "$cores"
}

# ----------------------------------------------------------------------------
# process_files_parallel_bash - Pure bash parallel processing
# ----------------------------------------------------------------------------
# Uses bash job control (&) with job limiting
# No external dependencies required
# ----------------------------------------------------------------------------
process_files_parallel_bash() {
    local -a files=("$@")
    local max_jobs="${PARALLEL_JOBS:-$(detect_cpu_cores)}"
    local active_jobs=0
    local failed_count=0
    
    echo "[ПАРАЛЛЕЛЬНАЯ ОБРАБОТКА] Используется $max_jobs ядер (pure bash)" >&2
    
    for file in "${files[@]}"; do
        # Launch background job
        (
            validate_yaml_file "$file" "$VERBOSE" || exit 1
        ) &
        
        ((active_jobs++))
        
        # Limit concurrent jobs
        if ((active_jobs >= max_jobs)); then
            # Wait for any job to complete
            wait -n
            if [[ $? -ne 0 ]]; then
                ((failed_count++))
            fi
            ((active_jobs--))
        fi
    done
    
    # Wait for all remaining jobs
    while ((active_jobs > 0)); do
        wait -n
        if [[ $? -ne 0 ]]; then
            ((failed_count++))
        fi
        ((active_jobs--))
    done
    
    return $failed_count
}

# ----------------------------------------------------------------------------
# process_files_parallel_gnu - GNU Parallel processing
# ----------------------------------------------------------------------------
# Uses GNU Parallel if available (better output handling)
# Graceful fallback to bash if not available
# ----------------------------------------------------------------------------
process_files_parallel_gnu() {
    local -a files=("$@")
    local max_jobs="${PARALLEL_JOBS:-$(detect_cpu_cores)}"
    
    if ! command -v parallel &>/dev/null; then
        echo "[INFO] GNU Parallel не найден, fallback на bash job control" >&2
        process_files_parallel_bash "${files[@]}"
        return $?
    fi
    
    echo "[ПАРАЛЛЕЛЬНАЯ ОБРАБОТКА] Используется $max_jobs ядер (GNU Parallel)" >&2
    
    # Export function for parallel
    export -f validate_yaml_file
    export VERBOSE
    
    # Process files with GNU Parallel
    printf '%s\n' "${files[@]}" | \
        parallel --jobs "$max_jobs" --keep-order --halt soon,fail=1 \
        validate_yaml_file {} "$VERBOSE"
    
    return $?
}

# ----------------------------------------------------------------------------
# process_files_sequential - Sequential processing (fallback/debug)
# ----------------------------------------------------------------------------
process_files_sequential() {
    local -a files=("$@")
    local failed_count=0
    
    for file in "${files[@]}"; do
        if ! validate_yaml_file "$file" "$VERBOSE"; then
            ((failed_count++))
        fi
    done
    
    return $failed_count
}

# ----------------------------------------------------------------------------
# process_files_auto - Automatic method selection
# ----------------------------------------------------------------------------
# Smart selection based on:
# - Number of files (parallel only worth it for 3+ files)
# - Availability of GNU Parallel
# - User preference (--parallel / --no-parallel flags)
# ----------------------------------------------------------------------------
process_files_auto() {
    local -a files=("$@")
    local file_count=${#files[@]}
    
    # Check user preference
    if [[ "${FORCE_SEQUENTIAL:-0}" -eq 1 ]]; then
        echo "[INFO] Параллелизация отключена (--no-parallel)" >&2
        process_files_sequential "${files[@]}"
        return $?
    fi
    
    # For 1-2 files, sequential is faster (no overhead)
    if [[ $file_count -le 2 ]]; then
        process_files_sequential "${files[@]}"
        return $?
    fi
    
    # For 3+ files, use parallel processing
    if [[ "${FORCE_PARALLEL:-0}" -eq 1 ]]; then
        # User explicitly requested parallel
        if command -v parallel &>/dev/null; then
            process_files_parallel_gnu "${files[@]}"
        else
            process_files_parallel_bash "${files[@]}"
        fi
    else
        # Auto-detect best method
        if [[ $file_count -ge 10 ]] && command -v parallel &>/dev/null; then
            # 10+ files + GNU Parallel available → use it
            process_files_parallel_gnu "${files[@]}"
        else
            # 3-9 files or no GNU Parallel → use bash job control
            process_files_parallel_bash "${files[@]}"
        fi
    fi
    
    return $?
}

# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
# In main script:
#
# # Source this module
# source "$SCRIPT_DIR/lib/parallel.sh"
#
# # Process files with auto-detection
# process_files_auto "${yaml_files[@]}"
#
# # Force specific method
# FORCE_PARALLEL=1 process_files_auto "${yaml_files[@]}"
# FORCE_SEQUENTIAL=1 process_files_auto "${yaml_files[@]}"
#
# # Specify number of jobs
# PARALLEL_JOBS=8 process_files_auto "${yaml_files[@]}"
#
# ============================================================================

