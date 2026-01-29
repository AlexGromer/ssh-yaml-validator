#!/bin/bash

#############################################################################
# PURE BASH FALLBACKS
# Provides compatibility when external commands are unavailable
# Version: 3.2.0
# Purpose: Enable validator to run on minimal systems (BusyBox, embedded, air-gapped)
#############################################################################

#############################################################################
# 1. realpath_fallback()
# Canonicalize path without external realpath command
#
# Usage: realpath_fallback PATH
# Returns: Absolute canonical path (stdout)
# Exit codes: 0=success, 1=invalid path, 2=readlink failed, 3=symlink loop
#############################################################################
realpath_fallback() {
    local path="$1"
    local components=()
    local depth=0 max_depth=40

    [[ -z "$path" ]] && { echo "realpath_fallback: missing operand" >&2; return 1; }

    # Expand tilde
    [[ "$path" == "~" ]] && path="$HOME"
    [[ "$path" == ~/* ]] && path="${HOME}${path:1}"

    # Convert to absolute
    [[ "$path" != /* ]] && path="$PWD/$path"

    # Resolve . and .. components
    IFS='/' read -ra parts <<< "$path"
    for component in "${parts[@]}"; do
        [[ -z "$component" || "$component" == "." ]] && continue
        if [[ "$component" == ".." ]]; then
            [[ ${#components[@]} -gt 0 ]] && unset 'components[-1]'
            components=("${components[@]}")
        else
            components+=("$component")
        fi
    done

    # Reconstruct path
    local resolved="/"
    [[ ${#components[@]} -gt 0 ]] && resolved+=$(IFS=/; echo "${components[*]}")

    # Resolve symlinks iteratively
    while [[ $depth -lt $max_depth ]]; do
        if [[ -L "$resolved" ]]; then
            local target
            target=$(readlink "$resolved" 2>/dev/null) || return 2
            [[ "$target" == /* ]] && resolved="$target" || resolved="${resolved%/*}/$target"
            ((depth++))
        else
            break
        fi
    done

    [[ $depth -ge $max_depth ]] && { echo "realpath_fallback: symlink loop detected" >&2; return 3; }

    echo "$resolved"
}

#############################################################################
# 2. expand_fallback()
# Convert tabs to spaces without external expand command
#
# Usage: expand_fallback [-t TABSIZE] [FILE...]
# Converts tabs to spaces, writes to stdout
# Exit codes: 0=success, 1=invalid args, 2=file not found
#############################################################################
expand_fallback() {
    local tabsize=8
    local files=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--tabs)
                [[ -z "$2" || "$2" =~ ^- ]] && { echo "expand_fallback: option requires argument" >&2; return 1; }
                [[ ! "$2" =~ ^[0-9]+$ ]] && { echo "expand_fallback: invalid tab size: $2" >&2; return 1; }
                tabsize="$2"
                shift 2
                ;;
            -*) echo "expand_fallback: invalid option: $1" >&2; return 1 ;;
            *) files+=("$1"); shift ;;
        esac
    done

    # Default to stdin
    [[ ${#files[@]} -eq 0 ]] && files=("-")

    # Process each file
    for file in "${files[@]}"; do
        local content
        if [[ "$file" == "-" ]]; then
            content=$(cat)
        else
            [[ ! -f "$file" ]] && { echo "expand_fallback: $file: No such file or directory" >&2; return 2; }
            content=$(<"$file")
        fi

        # Expand tabs character by character
        local output="" column=0 char i
        for ((i = 0; i < ${#content}; i++)); do
            char="${content:$i:1}"
            case "$char" in
                $'\t')
                    local spaces_needed=$(( tabsize - (column % tabsize) ))
                    for ((j = 0; j < spaces_needed; j++)); do output+=" "; done
                    column=$((column + spaces_needed))
                    ;;
                $'\n'|$'\r') output+="$char"; column=0 ;;
                *) output+="$char"; ((column++)) ;;
            esac
        done

        printf '%s' "$output"
    done
}

#############################################################################
# 3. od_fallback()
# Convert stdin to hex dump without external od command
#
# Usage: od_fallback -An -tx1
# Converts stdin to hex dump format
# Exit codes: 0=success, 1=invalid args
#
# Note: Supports 3-tier fallback: native od → xxd → pure bash
#############################################################################
od_fallback() {
    local no_address=0 format=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -An) no_address=1; shift ;;
            -tx1) format="hex1"; shift ;;
            *) echo "od_fallback: invalid option: $1" >&2; return 1 ;;
        esac
    done

    [[ "$format" != "hex1" || $no_address -eq 0 ]] && {
        echo "od_fallback: only -An -tx1 format supported" >&2
        return 1
    }

    # Try xxd first (faster, more common than od on minimal systems)
    if command -v xxd &>/dev/null; then
        xxd -p -c 1 | awk '{printf " %s", $0} END {print ""}'
        return 0
    fi

    # Pure bash fallback (slower but works everywhere)
    local input
    input=$(cat)

    local output=" " i byte hex_byte
    for ((i = 0; i < ${#input}; i++)); do
        byte="${input:$i:1}"
        # Handle special characters
        case "$byte" in
            $'\0') hex_byte='00' ;;
            *)
                # Convert character to hex (LC_ALL=C ensures byte value, not UTF-8)
                printf -v hex_byte '%02x' "'$byte" 2>/dev/null || hex_byte='00'
                ;;
        esac
        output+="$hex_byte "
    done

    echo "$output"
}

#############################################################################
# 4. tput_compat()
# Get terminal dimensions with 3-tier fallback
#
# Usage: tput_compat cols|lines
# Returns: Terminal columns or lines
# Exit codes: 0=success
#
# Fallback chain: tput → $COLUMNS/$LINES → defaults (80x24)
#############################################################################
tput_compat() {
    local cmd="$1"

    if command -v tput &>/dev/null; then
        tput "$cmd" 2>/dev/null || { [[ "$cmd" == "cols" ]] && echo 80 || echo 24; }
    elif [[ "$cmd" == "cols" && -n "${COLUMNS:-}" ]]; then
        echo "$COLUMNS"
    elif [[ "$cmd" == "lines" && -n "${LINES:-}" ]]; then
        echo "$LINES"
    else
        [[ "$cmd" == "cols" ]] && echo 80 || echo 24
    fi
}

#############################################################################
# WRAPPER FUNCTIONS
# Transparent fallback to native commands when available
#############################################################################

realpath_compat() {
    if command -v realpath &>/dev/null; then
        realpath "$@"
    else
        realpath_fallback "$@"
    fi
}

expand_compat() {
    if command -v expand &>/dev/null; then
        expand "$@"
    else
        expand_fallback "$@"
    fi
}

od_compat() {
    if command -v od &>/dev/null; then
        od "$@"
    elif command -v xxd &>/dev/null && [[ "$*" == "-An -tx1" ]]; then
        xxd -p -c 1 | awk '{printf " %s", $0} END {print ""}'
    else
        od_fallback "$@"
    fi
}

#############################################################################
# FALLBACK DETECTION
# Reports which commands are using fallbacks (for debugging)
#############################################################################

report_fallbacks() {
    local missing=()
    command -v realpath &>/dev/null || missing+=("realpath")
    command -v expand &>/dev/null || missing+=("expand")
    command -v od &>/dev/null || { command -v xxd &>/dev/null || missing+=("od"); }
    command -v tput &>/dev/null || missing+=("tput")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "# Using pure bash fallbacks for: ${missing[*]}" >&2
    fi
}
