#!/bin/bash
# Incremental Validation Module for YAML Validator v3.3.0
# Hash-based caching to skip unchanged files

# ============================================================================
# INCREMENTAL VALIDATION FUNCTIONS
# ============================================================================

# Cache directory structure:
# $CACHE_DIR/
#   ├── hashes/
#   │   └── path_to_file.yaml.sha256
#   └── results/
#       └── path_to_file.yaml.result

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/yaml_validator"

# ----------------------------------------------------------------------------
# init_cache_dir - Initialize cache directory structure
# ----------------------------------------------------------------------------
init_cache_dir() {
    mkdir -p "$CACHE_DIR/hashes" 2>/dev/null || {
        echo "[WARNING] Не удалось создать cache directory: $CACHE_DIR" >&2
        return 1
    }
    mkdir -p "$CACHE_DIR/results" 2>/dev/null || {
        echo "[WARNING] Не удалось создать results directory: $CACHE_DIR/results" >&2
        return 1
    }
    return 0
}

# ----------------------------------------------------------------------------
# clear_cache - Clear all cached results
# ----------------------------------------------------------------------------
clear_cache() {
    if [[ -d "$CACHE_DIR" ]]; then
        rm -rf "$CACHE_DIR"
        echo "✓ Cache очищен: $CACHE_DIR"
    else
        echo "Cache directory не существует: $CACHE_DIR"
    fi
}

# ----------------------------------------------------------------------------
# get_cache_key - Generate cache key from file path
# ----------------------------------------------------------------------------
# Converts file path to safe filename for cache storage
# Example: /path/to/file.yaml -> _path_to_file.yaml
# ----------------------------------------------------------------------------
get_cache_key() {
    local file="$1"

    # Convert to absolute path for consistent cache keys
    local abs_path
    if command -v realpath &>/dev/null; then
        abs_path=$(realpath "$file" 2>/dev/null) || abs_path="$file"
    elif command -v readlink &>/dev/null; then
        abs_path=$(readlink -f "$file" 2>/dev/null) || abs_path="$file"
    else
        # Fallback: manually resolve to absolute path
        if [[ "$file" == /* ]]; then
            abs_path="$file"
        else
            abs_path="$(pwd)/$file"
        fi
    fi

    # Replace / with _ and remove leading /
    echo "$abs_path" | sed 's/^[\/]*//; s/\//_/g'
}

# ----------------------------------------------------------------------------
# compute_file_hash - Compute SHA256 hash of file
# ----------------------------------------------------------------------------
compute_file_hash() {
    local file="$1"
    
    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" 2>/dev/null | awk '{print $1}'
    elif command -v openssl &>/dev/null; then
        openssl sha256 -r "$file" 2>/dev/null | awk '{print $1}'
    else
        # Fallback: use file size + modification time
        stat -c "%s-%Y" "$file" 2>/dev/null || stat -f "%z-%m" "$file" 2>/dev/null
    fi
}

# ----------------------------------------------------------------------------
# is_file_changed - Check if file changed since last validation
# ----------------------------------------------------------------------------
# Returns 0 (true) if file changed or no cache exists
# Returns 1 (false) if file unchanged and cache valid
# ----------------------------------------------------------------------------
is_file_changed() {
    local file="$1"
    local cache_key
    cache_key=$(get_cache_key "$file")
    local hash_file="$CACHE_DIR/hashes/${cache_key}.sha256"
    
    # No cache → changed
    [[ ! -f "$hash_file" ]] && return 0
    
    # Compute current hash
    local current_hash
    current_hash=$(compute_file_hash "$file")
    [[ -z "$current_hash" ]] && return 0  # Hash failed → treat as changed
    
    # Read cached hash
    local cached_hash
    cached_hash=$(cat "$hash_file" 2>/dev/null)
    [[ -z "$cached_hash" ]] && return 0  # Cache corrupted → changed
    
    # Compare hashes
    if [[ "$current_hash" == "$cached_hash" ]]; then
        return 1  # Unchanged
    else
        return 0  # Changed
    fi
}

# ----------------------------------------------------------------------------
# save_validation_result - Save validation result to cache
# ----------------------------------------------------------------------------
save_validation_result() {
    local file="$1"
    local exit_code="$2"
    local output="$3"
    
    local cache_key
    cache_key=$(get_cache_key "$file")
    
    # Save hash
    local current_hash
    current_hash=$(compute_file_hash "$file")
    if [[ -n "$current_hash" ]]; then
        echo "$current_hash" > "$CACHE_DIR/hashes/${cache_key}.sha256" 2>/dev/null
    fi
    
    # Save result
    {
        echo "EXIT_CODE=$exit_code"
        echo "TIMESTAMP=$(date +%s)"
        echo "---"
        echo "$output"
    } > "$CACHE_DIR/results/${cache_key}.result" 2>/dev/null
}

# ----------------------------------------------------------------------------
# load_cached_result - Load cached validation result
# ----------------------------------------------------------------------------
# Outputs: cached validation output
# Returns: cached exit code
# ----------------------------------------------------------------------------
load_cached_result() {
    local file="$1"
    local cache_key
    cache_key=$(get_cache_key "$file")
    local result_file="$CACHE_DIR/results/${cache_key}.result"
    
    [[ ! -f "$result_file" ]] && return 1
    
    # Read result file
    local exit_code=0
    local in_output=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^EXIT_CODE=([0-9]+)$ ]]; then
            exit_code="${BASH_REMATCH[1]}"
        elif [[ "$line" == "---" ]]; then
            in_output=1
        elif [[ $in_output -eq 1 ]]; then
            echo "$line"
        fi
    done < "$result_file"
    
    return "$exit_code"
}

# ----------------------------------------------------------------------------
# validate_file_incremental - Validate file with caching
# ----------------------------------------------------------------------------
# Main entry point for incremental validation
# ----------------------------------------------------------------------------
validate_file_incremental() {
    local file="$1"
    local verbose="${2:-0}"
    
    # Check if file changed
    if is_file_changed "$file"; then
        # File changed → validate
        local output
        output=$(validate_yaml_file "$file" "$verbose" 2>&1)
        local exit_code=$?
        
        # Save to cache
        save_validation_result "$file" "$exit_code" "$output"
        
        # Output result
        echo "$output"
        return $exit_code
    else
        # File unchanged → use cache
        if [[ $QUIET_MODE -ne 1 ]]; then
            echo "[CACHE] $file (unchanged, using cached result)"
        fi
        
        load_cached_result "$file"
        return $?
    fi
}

# ----------------------------------------------------------------------------
# process_files_incremental - Process files with incremental validation
# ----------------------------------------------------------------------------
process_files_incremental() {
    local -a files=("$@")
    local failed_count=0
    local cached_count=0
    local validated_count=0
    
    # Initialize cache directory
    if ! init_cache_dir; then
        echo "[WARNING] Cache недоступен, fallback на обычную валидацию" >&2
        for file in "${files[@]}"; do
            validate_yaml_file "$file" "$VERBOSE" || ((failed_count++))
        done
        return $failed_count
    fi
    
    echo "[INCREMENTAL MODE] Cache directory: $CACHE_DIR" >&2
    
    # Process each file
    for file in "${files[@]}"; do
        if is_file_changed "$file"; then
            # File changed → validate
            ((validated_count++))
            if ! validate_yaml_file "$file" "$VERBOSE"; then
                ((failed_count++))
            fi
            
            # Save result (simplified - just hash for now)
            local cache_key
            cache_key=$(get_cache_key "$file")
            local current_hash
            current_hash=$(compute_file_hash "$file")
            echo "$current_hash" > "$CACHE_DIR/hashes/${cache_key}.sha256" 2>/dev/null
        else
            # File unchanged → skip
            ((cached_count++))
            if [[ $QUIET_MODE -ne 1 ]]; then
                echo "[✓ CACHE] $file"
            fi
        fi
    done
    
    # Summary
    if [[ $QUIET_MODE -ne 1 ]]; then
        echo "" >&2
        echo "[INCREMENTAL SUMMARY]" >&2
        echo "  Validated: $validated_count files" >&2
        echo "  From cache: $cached_count files" >&2
        echo "  Speedup: ~$((cached_count * 100 / ${#files[@]}))% faster" >&2
    fi
    
    return $failed_count
}

# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
# # Enable incremental mode
# INCREMENTAL_MODE=1 ./yaml_validator.sh *.yaml
#
# # Or use flag
# ./yaml_validator.sh --incremental *.yaml
#
# # Clear cache
# ./yaml_validator.sh --clear-cache
#
# ============================================================================

