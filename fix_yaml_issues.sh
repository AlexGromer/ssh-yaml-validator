#!/bin/bash

#############################################################################
# YAML Auto-Fix Script
# Автоматическое исправление простых ошибок в YAML файлах
# Для использования в закрытых контурах
# Version: 3.1.0
#############################################################################

set -o pipefail

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' NC=''
fi

FIXED_FILES=0
TOTAL_FILES=0
INTERACTIVE=0
FROM_REPORT=""
QUIET_MODE=0
VERBOSE=0
CONFIG_FILE=""
declare -A CONFIG_VALUES

# Optional tools detection
declare -A OPTIONAL_TOOLS
OPTIONAL_TOOLS[jq]=0
OPTIONAL_TOOLS[yq]=0
OPTIONAL_TOOLS[dos2unix]=0
OPTIONAL_TOOLS[yamllint]=0

# Detect optional tools at startup
detect_optional_tools() {
    command -v jq &>/dev/null && OPTIONAL_TOOLS[jq]=1
    command -v yq &>/dev/null && OPTIONAL_TOOLS[yq]=1
    command -v dos2unix &>/dev/null && OPTIONAL_TOOLS[dos2unix]=1
    command -v yamllint &>/dev/null && OPTIONAL_TOOLS[yamllint]=1
}

# Track fix statistics
declare -A FIX_COUNTS=(
    [bom]=0
    [crlf]=0
    [tabs]=0
    [trailing]=0
    [booleans]=0
    [list_spacing]=0
    [doc_markers]=0
    [colon_spacing]=0
    [empty_lines]=0
    [eof_newline]=0
    [bracket_spacing]=0
    [comment_space]=0
    [truthy]=0
    [privileged]=0
    [run_as_non_root]=0
    [readonly_rootfs]=0
    [network_policy]=0
    [drop_capabilities]=0
    [missing_labels]=0
    [missing_annotations]=0
    [default_namespace]=0
    [liveness_probe]=0
    [readiness_probe]=0
    [pdb]=0
    [anti_affinity]=0
    [topology_spread]=0
    [resource_limits]=0
    [resource_requests]=0
    [requests_gt_limits]=0
    [resource_quota]=0
)

print_header() {
    [[ $QUIET_MODE -eq 0 ]] && echo -e "${BOLD}${CYAN}"
    [[ $QUIET_MODE -eq 0 ]] && echo "╔═══════════════════════════════════════════════════════════════════════╗"
    [[ $QUIET_MODE -eq 0 ]] && echo "║                    YAML Auto-Fix Tool v3.1.0                          ║"
    [[ $QUIET_MODE -eq 0 ]] && echo "║              Автоматическое исправление YAML файлов                   ║"
    [[ $QUIET_MODE -eq 0 ]] && echo "╚═══════════════════════════════════════════════════════════════════════╝"
    [[ $QUIET_MODE -eq 0 ]] && echo -e "${NC}"
}

usage() {
    cat << EOF
Использование: $0 [ОПЦИИ] <файл_или_директория>

Опции:
    -r, --recursive         Рекурсивная обработка поддиректорий (только для директорий)
    -b, --backup            Создать резервные копии (*.yaml.bak)
    -n, --dry-run           Только показать, что будет сделано (не изменять файлы)
    -i, --interactive       Интерактивный режим для сложных исправлений
    --from-report FILE      Использовать JSON отчет валидатора для целевых исправлений
    -v, --verbose           Подробный вывод (показывать каждое исправление)
    -q, --quiet             Тихий режим (только exit code, минимум вывода)
    -c, --config FILE       Файл конфигурации (.fixerrc) для batch-режима
    -h, --help              Показать эту справку

Автоматически исправляемые проблемы (безопасные):
    1.  BOM (Byte Order Mark) - удаление невидимых символов в начале файла
    2.  Windows encoding (CRLF -> LF)
    3.  Табы -> пробелы (2 пробела на таб)
    4.  Trailing whitespace
    5.  Boolean регистр (True->true, False->false, TRUE->true, FALSE->false)
    6.  List spacing (-item -> - item)
    7.  Document markers (---- -> ---, ..... -> ...)
    8.  Colon spacing (key:value -> key: value)
    9.  Empty lines (>2 подряд -> 2)
    10. Newline at EOF
    11. Bracket spacing ([a,b] -> [a, b])
    12. Comment space (#comment -> # comment)
    13. Truthy values (yes/no/on/off -> true/false)

Интерактивные исправления (-i):
    - Безопасность: privileged, hostNetwork, hostPID, runAsRoot
    - Missing probes: livenessProbe, readinessProbe
    - Missing resources: requests, limits
    - Missing namespace
    - И другие...

Batch-режим (--config):
    - Загружает параметры из .fixerrc файла
    - resource_profile: minimal | standard | heavy
    - liveness_path, liveness_port, readiness_path, readiness_port
    - namespace, probe_initial_delay, probe_period

Опциональные утилиты (расширенные возможности):
    jq        - JSON parsing для --from-report (fallback: grep)
    yq        - Расширенные YAML исправления
    dos2unix  - CRLF конвертация (fallback: sed)
    yamllint  - Дополнительная валидация перед исправлением

Примеры:
    $0 /path/to/manifests
    $0 config.yaml
    $0 -r -b /path/to/manifests
    $0 --dry-run /path/to/manifests
    $0 -i -r /path/to/manifests     # Интерактивный режим
    $0 --config .fixerrc /path/to/manifests  # Batch режим с конфигом

    # Интеграция с валидатором:
    ./yaml_validator.sh --json manifests/ > report.json
    $0 --from-report report.json manifests/

EOF
    exit 0
}

# Parse .fixerrc config file into CONFIG_VALUES associative array
parse_fixerrc() {
    local config_file="$1"
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Ошибка: Файл конфигурации не найден: $config_file${NC}"
        exit 1
    fi
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        # Parse key: value
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            # Strip inline comments
            value="${value%%#*}"
            # Trim trailing whitespace
            value="${value%"${value##*[![:space:]]}"}"
            CONFIG_VALUES["$key"]="$value"
        fi
    done < "$config_file"
    [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${BLUE}[CONFIG]${NC} Загружено ${#CONFIG_VALUES[@]} параметров из $config_file"
}

# Get config value with default fallback
get_config() {
    local key="$1"
    local default="$2"
    echo "${CONFIG_VALUES[$key]:-$default}"
}

# Check if file is a K8s workload resource
is_k8s_workload() {
    local file="$1"
    grep -qE 'kind:[[:space:]]*(Deployment|StatefulSet|DaemonSet|Job|CronJob)' "$file" 2>/dev/null
}

# Inject YAML block after a marker line
inject_yaml_after() {
    local file="$1" marker="$2" content="$3" indent="$4"
    local temp="${file}.tmp.$$"
    local found=0
    while IFS= read -r line; do
        echo "$line"
        if [[ $found -eq 0 && "$line" =~ $marker ]]; then
            echo "$content" | while IFS= read -r cline; do
                if [[ -n "$cline" ]]; then
                    printf '%*s%s\n' "$indent" '' "$cline"
                fi
            done
            found=1
        fi
    done < "$file" > "$temp"
    if [[ $found -eq 1 ]]; then
        mv "$temp" "$file"
    else
        rm -f "$temp"
    fi
    return $((1 - found))
}

# Find container spec indentation level in a K8s manifest
get_container_indent() {
    local file="$1"
    local indent=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^([[:space:]]*)containers: ]]; then
            indent=${#BASH_REMATCH[1]}
            break
        fi
    done < "$file"
    echo $((indent + 2))
}

# Get resource profile values
get_resource_profile() {
    local profile
    profile=$(get_config "resource_profile" "standard")
    case "$profile" in
        minimal)  echo "50m 200m 64Mi 128Mi" ;;
        heavy)    echo "500m 2 512Mi 2Gi" ;;
        *)        echo "100m 1 128Mi 512Mi" ;;  # standard
    esac
}

create_backup() {
    local file="$1"
    cp "$file" "${file}.bak"
    [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${BLUE}[BACKUP]${NC} Создана резервная копия: ${file}.bak"
}

# Ask user for interactive fix
ask_user() {
    local question="$1"
    local default="${2:-n}"
    local response

    echo -en "  ${MAGENTA}[?]${NC} $question "
    if [[ "$default" == "y" ]]; then
        echo -en "[Y/n]: "
    else
        echo -en "[y/N]: "
    fi

    read -r response
    response=${response:-$default}

    [[ "${response,,}" == "y" || "${response||}" == "yes" ]]
}

# Parse JSON report from yaml_validator.sh
# Returns space-separated list of fix_types for a given file
get_fixable_issues() {
    local report_file="$1"
    local target_file="$2"
    local fix_types=""

    # Extract fixable issues for this file from JSON
    if [[ -f "$report_file" ]]; then
        # Use jq if available, otherwise fallback to pure bash parser
        if command -v jq &>/dev/null; then
            fix_types=$(jq -r --arg file "$target_file" '.files[] | select(.path == $file) | .issues[] | select(.fixable == true) | .fix_type' "$report_file" 2>/dev/null | sort -u | tr '\n' ' ')
        else
            # Fallback: Pure bash JSON parser (works without jq, sed, awk)
            local in_target_file=0
            local current_fixable=0
            local temp_types=""

            while IFS= read -r line; do
                # Check if we're in the target file block
                if [[ "$line" =~ \"path\".*\"$target_file\" ]]; then
                    in_target_file=1
                    continue
                fi

                if [[ $in_target_file -eq 1 ]]; then
                    # Check for fixable: true
                    if [[ "$line" =~ \"fixable\"[[:space:]]*:[[:space:]]*true ]]; then
                        current_fixable=1
                    fi

                    # Extract fix_type when fixable
                    if [[ $current_fixable -eq 1 && "$line" =~ \"fix_type\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                        local type="${BASH_REMATCH[1]}"
                        if [[ -n "$type" ]]; then
                            temp_types="$temp_types$type "
                        fi
                        current_fixable=0
                    fi
                fi
            done < "$report_file"

            # Remove duplicates and clean up
            fix_types=$(echo "$temp_types" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')
            fix_types="${fix_types% }"  # Remove trailing space
        fi
    fi

    echo "$fix_types"
}

# Check if specific fix_type should be applied
should_fix() {
    local fix_type="$1"
    local allowed_fixes="$2"

    # If no report mode, fix everything
    [[ -z "$FROM_REPORT" ]] && return 0

    # In report mode, only fix issues from report
    [[ " $allowed_fixes " == *" $fix_type "* ]] && return 0

    return 1
}

# Fix colon spacing: key:value -> key: value
fix_colon_spacing() {
    local file="$1"
    local dry_run="$2"
    local found=0

    # Check for key:value (no space after colon) but NOT for URLs or time formats
    if grep -qE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*:[^[:space:]:/]' "$file" 2>/dev/null; then
        found=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены пропущенные пробелы после двоеточий${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Fix key:value -> key: value, but not URLs (://) or ports (:80)
        sed -i 's/^\([[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*\):\([^[:space:]:/]\)/\1: \2/g' "$file"
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлены пробелы после двоеточий${NC}"
        ((FIX_COUNTS[colon_spacing]++))
    fi

    return $found
}

# Fix excessive empty lines (>2 -> 2)
fix_empty_lines() {
    local file="$1"
    local dry_run="$2"
    local found=0

    # Check for more than 2 consecutive empty lines
    # Fixed: END block overwrites exit code, use flag instead
    if awk '/^$/{c++;if(c>2){found=1}} !/^$/{c=0} END{if(found==1)exit 0; exit 1}' "$file" 2>/dev/null; then
        found=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены лишние пустые строки (>2 подряд)${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Replace 3+ empty lines with 2
        awk 'BEGIN{blank=0} /^$/{blank++;if(blank<=2)print;next} {blank=0;print}' "$file" > "${file}.tmp.$$"
        mv "${file}.tmp.$$" "$file"
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Удалены лишние пустые строки${NC}"
        ((FIX_COUNTS[empty_lines]++))
    fi

    return $found
}

# Fix missing newline at EOF
fix_eof_newline() {
    local file="$1"
    local dry_run="$2"
    local found=0

    # Check if file doesn't end with newline
    if [[ -s "$file" && "$(tail -c 1 "$file" | od -An -tx1 | tr -d ' ')" != "0a" ]]; then
        found=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Файл не заканчивается переводом строки${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        echo "" >> "$file"
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлен перевод строки в конец файла${NC}"
        ((FIX_COUNTS[eof_newline]++))
    fi

    return $found
}

# Fix bracket spacing: [a,b] -> [a, b]
fix_bracket_spacing() {
    local file="$1"
    local dry_run="$2"
    local found=0

    # Check for commas without space after in inline arrays
    if grep -qE '\[[^]]*,[^[:space:]]' "$file" 2>/dev/null; then
        found=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены пропущенные пробелы в массивах${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Add space after comma in arrays
        sed -i ':a;s/\(\[[^]]*\),\([^[:space:]]\)/\1, \2/;ta' "$file"
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлены пробелы в массивах после запятых${NC}"
        ((FIX_COUNTS[bracket_spacing]++))
    fi

    return $found
}

# Fix comment space: #comment -> # comment
fix_comment_space() {
    local file="$1"
    local dry_run="$2"
    local found=0

    # Check for comments without space after #
    if grep -qE '^[[:space:]]*#[^#[:space:]!]' "$file" 2>/dev/null; then
        found=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены комментарии без пробела после #${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Add space after # in comments (but not ## or #!)
        sed -i 's/^\([[:space:]]*\)#\([^#[:space:]!]\)/\1# \2/' "$file"
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлены пробелы в комментариях${NC}"
        ((FIX_COUNTS[comment_space]++))
    fi

    return $found
}

# Fix truthy values: yes/no/on/off -> true/false
fix_truthy_values() {
    local file="$1"
    local dry_run="$2"
    local found=0

    # Check for truthy values
    if grep -qEi ': *(yes|no|on|off|y|n)[[:space:]]*$' "$file" 2>/dev/null; then
        found=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены truthy values (yes/no/on/off)${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Fix truthy values -> true/false
        sed -i -E 's/: *(yes|Yes|YES|on|On|ON|y|Y)[[:space:]]*$/: true/g' "$file"
        sed -i -E 's/: *(no|No|NO|off|Off|OFF|n|N)[[:space:]]*$/: false/g' "$file"
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Исправлены truthy values -> true/false${NC}"
        ((FIX_COUNTS[truthy]++))
    fi

    return $found
}

#############################################################################
# NEW AUTO-FIX FUNCTIONS v3.1.0 (K8s security, best practices, HA, resources)
# These fixes require --config or --interactive mode for safety
#############################################################################

# E2: Add securityContext.privileged: false if missing
fix_privileged() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    # Skip if privileged is already set anywhere
    grep -q 'privileged:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует securityContext.privileged${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local indent
        indent=$(get_container_indent "$file")
        local sc_indent=$((indent + 2))
        # Check if securityContext already exists at container level
        if grep -q "^$(printf '%*s' "$indent" '')securityContext:" "$file" 2>/dev/null; then
            # Add privileged: false inside existing securityContext
            inject_yaml_after "$file" "^[[:space:]]*securityContext:" "privileged: false" "$sc_indent"
        else
            # Add full securityContext block after "image:" line
            local content
            content=$(printf '%*ssecurityContext:\n%*sprivileged: false' "$indent" '' "$sc_indent" '')
            inject_yaml_after "$file" "^[[:space:]]*image:" "$content" 0
        fi
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлен securityContext.privileged: false${NC}"
        ((FIX_COUNTS[privileged]++))
    fi
    return 0
}

# E3: Add securityContext.runAsNonRoot: true if missing
fix_run_as_non_root() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'runAsNonRoot:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует securityContext.runAsNonRoot${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local indent
        indent=$(get_container_indent "$file")
        local sc_indent=$((indent + 2))
        if grep -q "^$(printf '%*s' "$indent" '')securityContext:" "$file" 2>/dev/null; then
            inject_yaml_after "$file" "^[[:space:]]*securityContext:" "runAsNonRoot: true" "$sc_indent"
        else
            local content
            content=$(printf '%*ssecurityContext:\n%*srunAsNonRoot: true' "$indent" '' "$sc_indent" '')
            inject_yaml_after "$file" "^[[:space:]]*image:" "$content" 0
        fi
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлен securityContext.runAsNonRoot: true${NC}"
        ((FIX_COUNTS[run_as_non_root]++))
    fi
    return 0
}

# E4: Add securityContext.readOnlyRootFilesystem: true if missing
fix_readonly_rootfs() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'readOnlyRootFilesystem:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует securityContext.readOnlyRootFilesystem${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local indent
        indent=$(get_container_indent "$file")
        local sc_indent=$((indent + 2))
        if grep -q "^$(printf '%*s' "$indent" '')securityContext:" "$file" 2>/dev/null; then
            inject_yaml_after "$file" "^[[:space:]]*securityContext:" "readOnlyRootFilesystem: true" "$sc_indent"
        else
            local content
            content=$(printf '%*ssecurityContext:\n%*sreadOnlyRootFilesystem: true' "$indent" '' "$sc_indent" '')
            inject_yaml_after "$file" "^[[:space:]]*image:" "$content" 0
        fi
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлен readOnlyRootFilesystem: true${NC}"
        ((FIX_COUNTS[readonly_rootfs]++))
    fi
    return 0
}

# E7: Create deny-all NetworkPolicy companion file (interactive/config only)
fix_network_policy() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1

    # Extract app name from metadata
    local app_name
    app_name=$(grep -A2 'metadata:' "$file" | grep 'name:' | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d ' ')
    [[ -z "$app_name" ]] && return 1

    local dir
    dir=$(dirname "$file")
    local netpol_file="${dir}/${app_name}-networkpolicy.yaml"
    [[ -f "$netpol_file" ]] && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует NetworkPolicy для $app_name${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local ns
        ns=$(grep 'namespace:' "$file" | head -1 | sed 's/.*namespace:[[:space:]]*//' | tr -d ' ')
        ns="${ns:-default}"
        cat > "$netpol_file" << NETPOL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${app_name}-deny-all
  namespace: ${ns}
spec:
  podSelector:
    matchLabels:
      app: ${app_name}
  policyTypes:
    - Ingress
    - Egress
NETPOL
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Создан NetworkPolicy: $netpol_file${NC}"
        ((FIX_COUNTS[network_policy]++))
    fi
    return 0
}

# E9: Add securityContext.capabilities.drop: ["ALL"] if missing
fix_drop_capabilities() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'capabilities:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует capabilities.drop${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local indent
        indent=$(get_container_indent "$file")
        local sc_indent=$((indent + 2))
        local cap_indent=$((indent + 4))
        if grep -q "^$(printf '%*s' "$indent" '')securityContext:" "$file" 2>/dev/null; then
            local content
            content=$(printf 'capabilities:\n%*sdrop:\n%*s- "ALL"' "$cap_indent" '' "$cap_indent" '')
            inject_yaml_after "$file" "^[[:space:]]*securityContext:" "$content" "$sc_indent"
        else
            local content
            content=$(printf '%*ssecurityContext:\n%*scapabilities:\n%*sdrop:\n%*s- "ALL"' "$indent" '' "$sc_indent" '' "$cap_indent" '' "$cap_indent" '')
            inject_yaml_after "$file" "^[[:space:]]*image:" "$content" 0
        fi
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлен capabilities.drop: [\"ALL\"]${NC}"
        ((FIX_COUNTS[drop_capabilities]++))
    fi
    return 0
}

# E13: Add standard K8s labels if missing
fix_missing_labels() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'app.kubernetes.io/name:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствуют стандартные K8s labels${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local app_name
        app_name=$(grep -A2 'metadata:' "$file" | grep 'name:' | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d ' ')
        [[ -z "$app_name" ]] && return 1

        if grep -q '^  labels:' "$file" 2>/dev/null; then
            inject_yaml_after "$file" "^  labels:" "app.kubernetes.io/name: ${app_name}
app.kubernetes.io/version: \"1.0.0\"
app.kubernetes.io/component: server" 4
        else
            inject_yaml_after "$file" "^  name:" "labels:
    app.kubernetes.io/name: ${app_name}
    app.kubernetes.io/version: \"1.0.0\"
    app.kubernetes.io/component: server" 2
        fi
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлены стандартные K8s labels${NC}"
        ((FIX_COUNTS[missing_labels]++))
    fi
    return 0
}

# E14: Add description annotation if missing
fix_missing_annotations() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'annotations:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствуют annotations${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local app_name
        app_name=$(grep -A2 'metadata:' "$file" | grep 'name:' | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d ' ')
        inject_yaml_after "$file" "^  name:" "annotations:
    description: \"${app_name} workload\"" 2
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлены annotations${NC}"
        ((FIX_COUNTS[missing_annotations]++))
    fi
    return 0
}

# E15: Change namespace: default to configured namespace
fix_default_namespace() {
    local file="$1" dry_run="$2"
    grep -qE 'namespace:[[:space:]]*default[[:space:]]*$' "$file" 2>/dev/null || return 1

    local target_ns
    target_ns=$(get_config "namespace" "")
    [[ -z "$target_ns" ]] && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружен namespace: default${NC}"
    if [[ $dry_run -eq 0 ]]; then
        sed -i "s/namespace:[[:space:]]*default[[:space:]]*$/namespace: $target_ns/" "$file"
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] namespace: default -> $target_ns${NC}"
        ((FIX_COUNTS[default_namespace]++))
    fi
    return 0
}

# E16: Add livenessProbe template
fix_liveness_probe() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'livenessProbe:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует livenessProbe${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local path port delay period
        path=$(get_config "liveness_path" "/healthz")
        port=$(get_config "liveness_port" "8080")
        delay=$(get_config "probe_initial_delay" "30")
        period=$(get_config "probe_period" "10")
        local indent
        indent=$(get_container_indent "$file")
        local sub=$((indent + 2))
        local subsub=$((indent + 4))
        local content
        content=$(printf '%*slivenessProbe:\n%*shttpGet:\n%*spath: %s\n%*sport: %s\n%*sinitialDelaySeconds: %s\n%*speriodSeconds: %s' \
            "$indent" '' "$sub" '' "$subsub" '' "$path" "$subsub" '' "$port" "$sub" '' "$delay" "$sub" '' "$period")
        inject_yaml_after "$file" "^[[:space:]]*image:" "$content" 0
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлен livenessProbe (httpGet $path:$port)${NC}"
        ((FIX_COUNTS[liveness_probe]++))
    fi
    return 0
}

# E17: Add readinessProbe template
fix_readiness_probe() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'readinessProbe:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует readinessProbe${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local path port delay period
        path=$(get_config "readiness_path" "/ready")
        port=$(get_config "readiness_port" "8080")
        delay=$(get_config "probe_initial_delay" "5")
        period=$(get_config "probe_period" "5")
        local indent
        indent=$(get_container_indent "$file")
        local sub=$((indent + 2))
        local subsub=$((indent + 4))
        local content
        content=$(printf '%*sreadinessProbe:\n%*shttpGet:\n%*spath: %s\n%*sport: %s\n%*sinitialDelaySeconds: %s\n%*speriodSeconds: %s' \
            "$indent" '' "$sub" '' "$subsub" '' "$path" "$subsub" '' "$port" "$sub" '' "$delay" "$sub" '' "$period")
        inject_yaml_after "$file" "^[[:space:]]*image:" "$content" 0
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлен readinessProbe (httpGet $path:$port)${NC}"
        ((FIX_COUNTS[readiness_probe]++))
    fi
    return 0
}

# E18: Create PodDisruptionBudget companion file
fix_pdb() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1

    local app_name
    app_name=$(grep -A2 'metadata:' "$file" | grep 'name:' | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d ' ')
    [[ -z "$app_name" ]] && return 1

    local dir
    dir=$(dirname "$file")
    local pdb_file="${dir}/${app_name}-pdb.yaml"
    [[ -f "$pdb_file" ]] && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует PodDisruptionBudget для $app_name${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local ns
        ns=$(grep 'namespace:' "$file" | head -1 | sed 's/.*namespace:[[:space:]]*//' | tr -d ' ')
        ns="${ns:-default}"
        cat > "$pdb_file" << PDB
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${app_name}-pdb
  namespace: ${ns}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: ${app_name}
PDB
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Создан PDB: $pdb_file${NC}"
        ((FIX_COUNTS[pdb]++))
    fi
    return 0
}

# E19: Add podAntiAffinity
fix_anti_affinity() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'podAntiAffinity:' "$file" 2>/dev/null && return 1
    # Only for Deployments/StatefulSets
    grep -qE 'kind:[[:space:]]*(Deployment|StatefulSet)' "$file" 2>/dev/null || return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует podAntiAffinity${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local app_name
        app_name=$(grep -A2 'metadata:' "$file" | grep 'name:' | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d ' ')
        # Find spec.template.spec and inject affinity
        local content
        content=$(cat << 'AFFINITY'
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - APPNAME
                topologyKey: kubernetes.io/hostname
AFFINITY
)
        content="${content//APPNAME/$app_name}"
        inject_yaml_after "$file" "^[[:space:]]*containers:" "$content" 0
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлен podAntiAffinity${NC}"
        ((FIX_COUNTS[anti_affinity]++))
    fi
    return 0
}

# E20: Add topologySpreadConstraints
fix_topology_spread() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'topologySpreadConstraints:' "$file" 2>/dev/null && return 1
    grep -qE 'kind:[[:space:]]*(Deployment|StatefulSet)' "$file" 2>/dev/null || return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует topologySpreadConstraints${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local app_name
        app_name=$(grep -A2 'metadata:' "$file" | grep 'name:' | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d ' ')
        local content
        content=$(cat << TOPO
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: ${app_name}
TOPO
)
        inject_yaml_after "$file" "^[[:space:]]*containers:" "$content" 0
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлен topologySpreadConstraints${NC}"
        ((FIX_COUNTS[topology_spread]++))
    fi
    return 0
}

# E21: Add resource limits if missing
fix_resource_limits() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'limits:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствуют resource limits${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local profile_vals
        read -r req_cpu lim_cpu req_mem lim_mem <<< "$(get_resource_profile)"
        local indent
        indent=$(get_container_indent "$file")
        local sub=$((indent + 2))
        local subsub=$((indent + 4))
        if grep -q "^$(printf '%*s' "$indent" '')resources:" "$file" 2>/dev/null; then
            local content
            content=$(printf 'limits:\n%*scpu: "%s"\n%*smemory: "%s"' "$subsub" '' "$lim_cpu" "$subsub" '' "$lim_mem")
            inject_yaml_after "$file" "^[[:space:]]*resources:" "$content" "$sub"
        else
            local content
            content=$(printf '%*sresources:\n%*slimits:\n%*scpu: "%s"\n%*smemory: "%s"' \
                "$indent" '' "$sub" '' "$subsub" '' "$lim_cpu" "$subsub" '' "$lim_mem")
            inject_yaml_after "$file" "^[[:space:]]*image:" "$content" 0
        fi
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлены resource limits (cpu: $lim_cpu, mem: $lim_mem)${NC}"
        ((FIX_COUNTS[resource_limits]++))
    fi
    return 0
}

# E22: Add resource requests if missing
fix_resource_requests() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    grep -q 'requests:' "$file" 2>/dev/null && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствуют resource requests${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local profile_vals
        read -r req_cpu lim_cpu req_mem lim_mem <<< "$(get_resource_profile)"
        local indent
        indent=$(get_container_indent "$file")
        local sub=$((indent + 2))
        local subsub=$((indent + 4))
        if grep -q "^$(printf '%*s' "$indent" '')resources:" "$file" 2>/dev/null; then
            local content
            content=$(printf 'requests:\n%*scpu: "%s"\n%*smemory: "%s"' "$subsub" '' "$req_cpu" "$subsub" '' "$req_mem")
            inject_yaml_after "$file" "^[[:space:]]*resources:" "$content" "$sub"
        else
            local content
            content=$(printf '%*sresources:\n%*srequests:\n%*scpu: "%s"\n%*smemory: "%s"' \
                "$indent" '' "$sub" '' "$subsub" '' "$req_cpu" "$subsub" '' "$req_mem")
            inject_yaml_after "$file" "^[[:space:]]*image:" "$content" 0
        fi
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлены resource requests (cpu: $req_cpu, mem: $req_mem)${NC}"
        ((FIX_COUNTS[resource_requests]++))
    fi
    return 0
}

# E23: Fix requests > limits (set requests = 50% of limits)
fix_requests_gt_limits() {
    local file="$1" dry_run="$2"
    is_k8s_workload "$file" || return 1
    # This is complex — only fix obvious cases where we can parse values
    local has_limits has_requests
    has_limits=$(grep -c 'limits:' "$file" 2>/dev/null)
    has_requests=$(grep -c 'requests:' "$file" 2>/dev/null)
    [[ $has_limits -eq 0 || $has_requests -eq 0 ]] && return 1

    # Parse CPU/memory values (simplified: look for patterns)
    local lim_cpu req_cpu
    lim_cpu=$(grep -A3 'limits:' "$file" | grep 'cpu:' | head -1 | sed 's/.*cpu:[[:space:]]*"\?\([^"]*\)"\?/\1/' | tr -d ' ')
    req_cpu=$(grep -A3 'requests:' "$file" | grep 'cpu:' | head -1 | sed 's/.*cpu:[[:space:]]*"\?\([^"]*\)"\?/\1/' | tr -d ' ')

    [[ -z "$lim_cpu" || -z "$req_cpu" ]] && return 1

    # Convert to millicores for comparison
    local lim_mc req_mc
    if [[ "$lim_cpu" =~ ^([0-9]+)m$ ]]; then
        lim_mc="${BASH_REMATCH[1]}"
    elif [[ "$lim_cpu" =~ ^([0-9]+)$ ]]; then
        lim_mc=$((BASH_REMATCH[1] * 1000))
    else
        return 1
    fi
    if [[ "$req_cpu" =~ ^([0-9]+)m$ ]]; then
        req_mc="${BASH_REMATCH[1]}"
    elif [[ "$req_cpu" =~ ^([0-9]+)$ ]]; then
        req_mc=$((BASH_REMATCH[1] * 1000))
    else
        return 1
    fi

    [[ $req_mc -le $lim_mc ]] && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ CPU requests ($req_cpu) > limits ($lim_cpu)${NC}"
    if [[ $dry_run -eq 0 ]]; then
        local new_req=$((lim_mc / 2))
        local new_req_str="${new_req}m"
        sed -i "/requests:/,/cpu:/{s/cpu:[[:space:]]*\"*[^\"]*\"*/cpu: \"$new_req_str\"/}" "$file"
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] CPU requests: $req_cpu -> $new_req_str (50% of limits)${NC}"
        ((FIX_COUNTS[requests_gt_limits]++))
    fi
    return 0
}

# E24: Create ResourceQuota companion file (interactive/config only)
fix_resource_quota() {
    local file="$1" dry_run="$2"
    # Only create for namespace-scoped resources
    local ns
    ns=$(grep 'namespace:' "$file" | head -1 | sed 's/.*namespace:[[:space:]]*//' | tr -d ' ')
    [[ -z "$ns" ]] && return 1

    local dir
    dir=$(dirname "$file")
    local quota_file="${dir}/${ns}-resourcequota.yaml"
    [[ -f "$quota_file" ]] && return 1

    [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $dry_run -eq 1) ]] && echo -e "  ${YELLOW}├─ Отсутствует ResourceQuota для namespace $ns${NC}"
    if [[ $dry_run -eq 0 ]]; then
        cat > "$quota_file" << QUOTA
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${ns}-quota
  namespace: ${ns}
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
    pods: "20"
QUOTA
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Создан ResourceQuota: $quota_file${NC}"
        ((FIX_COUNTS[resource_quota]++))
    fi
    return 0
}

# Interactive fix for security issues
interactive_fix_security() {
    local file="$1"
    local dry_run="$2"

    # Check for privileged: true
    if grep -q 'privileged: true' "$file" 2>/dev/null; then
        echo -e "  ${RED}[!] Обнаружен privileged: true${NC}"
        if ask_user "Исправить privileged: true -> false?"; then
            if [[ $dry_run -eq 0 ]]; then
                sed -i 's/privileged: true/privileged: false/' "$file"
                echo -e "  ${GREEN}├─ [✓] privileged: true -> false${NC}"
            fi
        fi
    fi

    # Check for hostNetwork: true
    if grep -q 'hostNetwork: true' "$file" 2>/dev/null; then
        echo -e "  ${RED}[!] Обнаружен hostNetwork: true${NC}"
        if ask_user "Исправить hostNetwork: true -> false?"; then
            if [[ $dry_run -eq 0 ]]; then
                sed -i 's/hostNetwork: true/hostNetwork: false/' "$file"
                echo -e "  ${GREEN}├─ [✓] hostNetwork: true -> false${NC}"
            fi
        fi
    fi

    # Check for hostPID: true
    if grep -q 'hostPID: true' "$file" 2>/dev/null; then
        echo -e "  ${RED}[!] Обнаружен hostPID: true${NC}"
        if ask_user "Исправить hostPID: true -> false?"; then
            if [[ $dry_run -eq 0 ]]; then
                sed -i 's/hostPID: true/hostPID: false/' "$file"
                echo -e "  ${GREEN}├─ [✓] hostPID: true -> false${NC}"
            fi
        fi
    fi

    # Check for hostIPC: true
    if grep -q 'hostIPC: true' "$file" 2>/dev/null; then
        echo -e "  ${RED}[!] Обнаружен hostIPC: true${NC}"
        if ask_user "Исправить hostIPC: true -> false?"; then
            if [[ $dry_run -eq 0 ]]; then
                sed -i 's/hostIPC: true/hostIPC: false/' "$file"
                echo -e "  ${GREEN}├─ [✓] hostIPC: true -> false${NC}"
            fi
        fi
    fi

    # Check for allowPrivilegeEscalation: true
    if grep -q 'allowPrivilegeEscalation: true' "$file" 2>/dev/null; then
        echo -e "  ${RED}[!] Обнаружен allowPrivilegeEscalation: true${NC}"
        if ask_user "Исправить allowPrivilegeEscalation: true -> false?"; then
            if [[ $dry_run -eq 0 ]]; then
                sed -i 's/allowPrivilegeEscalation: true/allowPrivilegeEscalation: false/' "$file"
                echo -e "  ${GREEN}├─ [✓] allowPrivilegeEscalation: true -> false${NC}"
            fi
        fi
    fi

    # Check for runAsUser: 0
    if grep -qE 'runAsUser:[[:space:]]*0[[:space:]]*$' "$file" 2>/dev/null; then
        echo -e "  ${RED}[!] Обнаружен runAsUser: 0 (root)${NC}"
        if ask_user "Исправить runAsUser: 0 -> 1000?"; then
            if [[ $dry_run -eq 0 ]]; then
                sed -i 's/runAsUser: 0$/runAsUser: 1000/' "$file"
                echo -e "  ${GREEN}├─ [✓] runAsUser: 0 -> 1000${NC}"
            fi
        fi
    fi

    # Check for readOnlyRootFilesystem: false
    if grep -q 'readOnlyRootFilesystem: false' "$file" 2>/dev/null; then
        echo -e "  ${YELLOW}[!] Обнаружен readOnlyRootFilesystem: false${NC}"
        if ask_user "Исправить readOnlyRootFilesystem: false -> true?"; then
            if [[ $dry_run -eq 0 ]]; then
                sed -i 's/readOnlyRootFilesystem: false/readOnlyRootFilesystem: true/' "$file"
                echo -e "  ${GREEN}├─ [✓] readOnlyRootFilesystem: false -> true${NC}"
            fi
        fi
    fi
}

# Interactive fix for missing probes
interactive_fix_probes() {
    local file="$1"
    local dry_run="$2"

    # Check if it's a workload resource
    if ! grep -qE 'kind:[[:space:]]*(Deployment|StatefulSet|DaemonSet|Job)' "$file" 2>/dev/null; then
        return
    fi

    # Check for missing livenessProbe
    if ! grep -q 'livenessProbe:' "$file" 2>/dev/null; then
        echo -e "  ${YELLOW}[!] Отсутствует livenessProbe${NC}"
        if ask_user "Добавить шаблон livenessProbe? (httpGet на порт 8080)"; then
            if [[ $dry_run -eq 0 ]]; then
                # Find the last containerPort line and add probe after it
                local probe_template="          livenessProbe:\n            httpGet:\n              path: /healthz\n              port: 8080\n            initialDelaySeconds: 30\n            periodSeconds: 10"
                # This is a simplified approach - real implementation would need more context
                echo -e "  ${BLUE}├─ [INFO] Добавьте следующий блок в container spec:${NC}"
                echo -e "$probe_template"
            fi
        fi
    fi

    # Check for missing readinessProbe
    if ! grep -q 'readinessProbe:' "$file" 2>/dev/null; then
        echo -e "  ${YELLOW}[!] Отсутствует readinessProbe${NC}"
        if ask_user "Показать шаблон readinessProbe?"; then
            echo -e "  ${BLUE}├─ [INFO] Добавьте следующий блок в container spec:${NC}"
            echo "          readinessProbe:"
            echo "            httpGet:"
            echo "              path: /ready"
            echo "              port: 8080"
            echo "            initialDelaySeconds: 5"
            echo "            periodSeconds: 5"
        fi
    fi
}

# Interactive fix for missing resources
interactive_fix_resources() {
    local file="$1"
    local dry_run="$2"

    # Check if it's a workload resource
    if ! grep -qE 'kind:[[:space:]]*(Deployment|StatefulSet|DaemonSet|Job|CronJob)' "$file" 2>/dev/null; then
        return
    fi

    # Check for missing resources
    if ! grep -q 'resources:' "$file" 2>/dev/null; then
        echo -e "  ${YELLOW}[!] Отсутствует resources (limits/requests)${NC}"
        if ask_user "Показать шаблон resources?"; then
            echo -e "  ${BLUE}├─ [INFO] Добавьте следующий блок в container spec:${NC}"
            echo "          resources:"
            echo "            requests:"
            echo "              memory: \"128Mi\""
            echo "              cpu: \"100m\""
            echo "            limits:"
            echo "              memory: \"256Mi\""
            echo "              cpu: \"200m\""
        fi
    fi
}

# Interactive fix for :latest tag
interactive_fix_latest_tag() {
    local file="$1"
    local dry_run="$2"

    # Check for :latest tag
    local latest_images
    latest_images=$(grep -E 'image:.*:latest' "$file" 2>/dev/null)

    if [[ -n "$latest_images" ]]; then
        echo -e "  ${YELLOW}[!] Обнаружены образы с тегом :latest${NC}"
        echo "$latest_images" | while read -r line; do
            echo -e "    ${CYAN}$line${NC}"
        done
        if ask_user "Заменить :latest на :stable?"; then
            if [[ $dry_run -eq 0 ]]; then
                sed -i 's/:latest/:stable/g' "$file"
                echo -e "  ${GREEN}├─ [✓] :latest -> :stable${NC}"
            fi
        fi
    fi
}

# Interactive fix for missing namespace
interactive_fix_namespace() {
    local file="$1"
    local dry_run="$2"

    # Check if it's a namespaced resource without namespace
    if grep -qE 'kind:[[:space:]]*(Deployment|Service|ConfigMap|Secret|Ingress|StatefulSet|DaemonSet|Job|CronJob|PersistentVolumeClaim)' "$file" 2>/dev/null; then
        if ! grep -qE 'namespace:' "$file" 2>/dev/null; then
            echo -e "  ${YELLOW}[!] Отсутствует namespace${NC}"
            if ask_user "Добавить namespace?"; then
                echo -en "  Введите имя namespace [default]: "
                read -r ns_name
                ns_name=${ns_name:-default}
                if [[ $dry_run -eq 0 ]]; then
                    # Add namespace after name in metadata
                    sed -i "/^  name:/a\  namespace: $ns_name" "$file"
                    echo -e "  ${GREEN}├─ [✓] Добавлен namespace: $ns_name${NC}"
                fi
            fi
        fi
    fi
}

fix_file() {
    local file="$1"
    local backup="$2"
    local dry_run="$3"
    local interactive="$4"
    local allowed_fixes="${5:-}"

    [[ $QUIET_MODE -eq 0 ]] && echo -e "${CYAN}[ОБРАБОТКА]${NC} $file"

    # If using report mode, show allowed fixes
    if [[ -n "$FROM_REPORT" && -n "$allowed_fixes" && $QUIET_MODE -eq 0 ]]; then
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${BLUE}[ОТЧЕТ]${NC} Исправляемые проблемы: $allowed_fixes"
    fi

    local has_bom=0
    local has_crlf=0
    local has_tabs=0
    local has_trailing=0
    local has_booleans=0
    local has_list_spacing=0
    local has_doc_markers=0
    local total_fixes=0

    # Check for BOM
    local first_bytes
    first_bytes=$(head -c 3 "$file" | od -An -tx1 | tr -d ' \n')
    if [[ "$first_bytes" == "efbbbf" ]]; then
        has_bom=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $interactive -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружен BOM (Byte Order Mark)${NC}"
    fi

    if grep -q $'\r' "$file" 2>/dev/null; then
        has_crlf=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $interactive -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены CRLF (Windows encoding)${NC}"
    fi

    if grep -q $'\t' "$file" 2>/dev/null; then
        has_tabs=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $interactive -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены табы${NC}"
    fi

    if grep -q '[[:space:]]$' "$file" 2>/dev/null; then
        has_trailing=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $interactive -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены trailing whitespace${NC}"
    fi

    # Check for boolean case issues (True, False, TRUE, FALSE)
    if grep -qE ': *(True|TRUE|False|FALSE)[[:space:]]*$' "$file" 2>/dev/null; then
        has_booleans=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $interactive -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены boolean значения с неправильным регистром${NC}"
    fi

    # Check for list items without space (-item instead of - item)
    if grep -qE '^[[:space:]]*-[^[:space:]-]' "$file" 2>/dev/null; then
        has_list_spacing=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $interactive -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены элементы списка без пробела после дефиса${NC}"
    fi

    # Check for malformed document markers (----, ....., etc)
    if grep -qE '^-{4,}[[:space:]]*$|^\.{4,}[[:space:]]*$' "$file" 2>/dev/null; then
        has_doc_markers=1
        [[ $QUIET_MODE -eq 0 && ($VERBOSE -eq 1 || $interactive -eq 1) ]] && echo -e "  ${YELLOW}├─ Обнаружены некорректные маркеры документа${NC}"
    fi

    # Calculate if we need to fix anything for basic checks
    local needs_basic_fix=0
    [[ $has_bom -eq 1 || $has_crlf -eq 1 || $has_tabs -eq 1 || $has_trailing -eq 1 || $has_booleans -eq 1 || $has_list_spacing -eq 1 || $has_doc_markers -eq 1 ]] && needs_basic_fix=1

    # Create backup if needed
    if [[ $needs_basic_fix -eq 1 && $dry_run -eq 0 && $backup -eq 1 ]]; then
        create_backup "$file"
    fi

    # Apply basic fixes
    if [[ $has_bom -eq 1 ]] && should_fix "bom" "$allowed_fixes"; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i '1s/^\xEF\xBB\xBF//' "$file"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Удален BOM${NC}"
            ((FIX_COUNTS[bom]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_crlf -eq 1 ]] && should_fix "crlf" "$allowed_fixes"; then
        if [[ $dry_run -eq 0 ]]; then
            local temp_file="${file}.tmp.$$"
            sed 's/\r$//' "$file" > "$temp_file"
            mv "$temp_file" "$file"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] CRLF -> LF${NC}"
            ((FIX_COUNTS[crlf]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_tabs -eq 1 ]] && should_fix "tabs" "$allowed_fixes"; then
        if [[ $dry_run -eq 0 ]]; then
            local temp_file="${file}.tmp.$$"
            expand -t 2 "$file" > "$temp_file"
            mv "$temp_file" "$file"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Табы -> Пробелы${NC}"
            ((FIX_COUNTS[tabs]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_trailing -eq 1 ]] && should_fix "trailing" "$allowed_fixes"; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i 's/[[:space:]]*$//' "$file"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Удалены trailing whitespace${NC}"
            ((FIX_COUNTS[trailing]++))
        fi
        ((total_fixes++))
    fi

    # IMPORTANT: Apply colon_spacing BEFORE booleans to handle cases like "enabled:True"
    if should_fix "colon_spacing" "$allowed_fixes"; then
        fix_colon_spacing "$file" "$dry_run" && ((total_fixes++))
    fi

    if [[ $has_booleans -eq 1 ]] && should_fix "booleans" "$allowed_fixes"; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i 's/: True$/: true/g; s/: FALSE$/: false/g; s/: TRUE$/: true/g; s/: False$/: false/g' "$file"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Исправлен регистр boolean значений${NC}"
            ((FIX_COUNTS[booleans]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_list_spacing -eq 1 ]] && should_fix "list_spacing" "$allowed_fixes"; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i 's/^\([[:space:]]*\)-\([^[:space:]-]\)/\1- \2/' "$file"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Добавлены пробелы после дефисов в списках${NC}"
            ((FIX_COUNTS[list_spacing]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_doc_markers -eq 1 ]] && should_fix "doc_markers" "$allowed_fixes"; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i 's/^-\{4,\}$/---/g; s/^\.\{4,\}$/\.\.\./g' "$file"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}├─ [✓] Исправлены маркеры документа${NC}"
            ((FIX_COUNTS[doc_markers]++))
        fi
        ((total_fixes++))
    fi

    # New safe fixes (8-13) - These functions internally check for issues
    # Note: colon_spacing moved earlier (before booleans) to handle "key:True" cases
    if should_fix "empty_lines" "$allowed_fixes"; then
        fix_empty_lines "$file" "$dry_run" && ((total_fixes++))
    fi
    if should_fix "eof_newline" "$allowed_fixes"; then
        fix_eof_newline "$file" "$dry_run" && ((total_fixes++))
    fi
    if should_fix "bracket_spacing" "$allowed_fixes"; then
        fix_bracket_spacing "$file" "$dry_run" && ((total_fixes++))
    fi
    if should_fix "comment_space" "$allowed_fixes"; then
        fix_comment_space "$file" "$dry_run" && ((total_fixes++))
    fi
    if should_fix "quotes" "$allowed_fixes"; then
        fix_truthy_values "$file" "$dry_run" && ((total_fixes++))
    fi

    # K8s auto-fixes (require --config or --interactive mode)
    if [[ -n "$CONFIG_FILE" || $interactive -eq 1 ]]; then
        # Security fixes
        if should_fix "privileged" "$allowed_fixes"; then
            fix_privileged "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "run_as_non_root" "$allowed_fixes"; then
            fix_run_as_non_root "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "readonly_rootfs" "$allowed_fixes"; then
            fix_readonly_rootfs "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "drop_capabilities" "$allowed_fixes"; then
            fix_drop_capabilities "$file" "$dry_run" && ((total_fixes++))
        fi
        # Best practices
        if should_fix "missing_labels" "$allowed_fixes"; then
            fix_missing_labels "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "missing_annotations" "$allowed_fixes"; then
            fix_missing_annotations "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "default_namespace" "$allowed_fixes"; then
            fix_default_namespace "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "liveness_probe" "$allowed_fixes"; then
            fix_liveness_probe "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "readiness_probe" "$allowed_fixes"; then
            fix_readiness_probe "$file" "$dry_run" && ((total_fixes++))
        fi
        # HA fixes
        if should_fix "pdb" "$allowed_fixes"; then
            fix_pdb "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "anti_affinity" "$allowed_fixes"; then
            fix_anti_affinity "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "topology_spread" "$allowed_fixes"; then
            fix_topology_spread "$file" "$dry_run" && ((total_fixes++))
        fi
        # Resource fixes
        if should_fix "resource_limits" "$allowed_fixes"; then
            fix_resource_limits "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "resource_requests" "$allowed_fixes"; then
            fix_resource_requests "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "requests_gt_limits" "$allowed_fixes"; then
            fix_requests_gt_limits "$file" "$dry_run" && ((total_fixes++))
        fi
        # Companion file fixes (interactive/config only)
        if should_fix "network_policy" "$allowed_fixes"; then
            fix_network_policy "$file" "$dry_run" && ((total_fixes++))
        fi
        if should_fix "resource_quota" "$allowed_fixes"; then
            fix_resource_quota "$file" "$dry_run" && ((total_fixes++))
        fi
    fi

    # Interactive fixes
    if [[ $interactive -eq 1 ]]; then
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${MAGENTA}[ИНТЕРАКТИВНЫЙ РЕЖИМ]${NC}"
        interactive_fix_security "$file" "$dry_run"
        interactive_fix_latest_tag "$file" "$dry_run"
        interactive_fix_namespace "$file" "$dry_run"
        interactive_fix_probes "$file" "$dry_run"
        interactive_fix_resources "$file" "$dry_run"
    fi

    if [[ $total_fixes -gt 0 ]]; then
        if [[ $dry_run -eq 1 ]]; then
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${BLUE}└─ [DRY-RUN] Файл будет исправлен ($total_fixes проблем)${NC}"
        else
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}└─ [УСПЕХ] Файл исправлен ($total_fixes проблем)${NC}"
            ((FIXED_FILES++))
        fi
    else
        [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${GREEN}└─ [OK] Проблем не обнаружено${NC}"
    fi

    ((TOTAL_FILES++))
    echo ""
}

find_and_fix_files() {
    local dir="$1"
    local recursive="$2"
    local backup="$3"
    local dry_run="$4"
    local interactive="$5"
    local files=()

    if [[ $recursive -eq 1 ]]; then
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)
    else
        for file in "$dir"/*.yaml "$dir"/*.yml; do
            [[ -f "$file" ]] && files+=("$file")
        done
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        [[ $QUIET_MODE -eq 0 ]] && echo -e "${YELLOW}Предупреждение: YAML файлы не найдены${NC}"
        exit 0
    fi

    [[ $QUIET_MODE -eq 0 ]] && echo -e "${BOLD}Найдено файлов: ${#files[@]}${NC}"
    echo ""

    for file in "${files[@]}"; do
        local allowed_fixes=""
        if [[ -n "$FROM_REPORT" ]]; then
            allowed_fixes=$(get_fixable_issues "$FROM_REPORT" "$file")
        fi
        fix_file "$file" "$backup" "$dry_run" "$interactive" "$allowed_fixes"
    done
}

print_statistics() {
    echo -e "${BOLD}СТАТИСТИКА ПО ТИПАМ ИСПРАВЛЕНИЙ${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local total=0
    for key in "${!FIX_COUNTS[@]}"; do
        total=$((total + FIX_COUNTS[$key]))
    done

    if [[ $total -gt 0 ]]; then
        [[ ${FIX_COUNTS[bom]} -gt 0 ]] && echo -e "  BOM удалён:              ${FIX_COUNTS[bom]}"
        [[ ${FIX_COUNTS[crlf]} -gt 0 ]] && echo -e "  CRLF -> LF:              ${FIX_COUNTS[crlf]}"
        [[ ${FIX_COUNTS[tabs]} -gt 0 ]] && echo -e "  Табы -> Пробелы:         ${FIX_COUNTS[tabs]}"
        [[ ${FIX_COUNTS[trailing]} -gt 0 ]] && echo -e "  Trailing whitespace:     ${FIX_COUNTS[trailing]}"
        [[ ${FIX_COUNTS[booleans]} -gt 0 ]] && echo -e "  Boolean регистр:         ${FIX_COUNTS[booleans]}"
        [[ ${FIX_COUNTS[list_spacing]} -gt 0 ]] && echo -e "  List spacing:            ${FIX_COUNTS[list_spacing]}"
        [[ ${FIX_COUNTS[doc_markers]} -gt 0 ]] && echo -e "  Document markers:        ${FIX_COUNTS[doc_markers]}"
        [[ ${FIX_COUNTS[colon_spacing]} -gt 0 ]] && echo -e "  Colon spacing:           ${FIX_COUNTS[colon_spacing]}"
        [[ ${FIX_COUNTS[empty_lines]} -gt 0 ]] && echo -e "  Empty lines:             ${FIX_COUNTS[empty_lines]}"
        [[ ${FIX_COUNTS[eof_newline]} -gt 0 ]] && echo -e "  EOF newline:             ${FIX_COUNTS[eof_newline]}"
        [[ ${FIX_COUNTS[bracket_spacing]} -gt 0 ]] && echo -e "  Bracket spacing:         ${FIX_COUNTS[bracket_spacing]}"
        [[ ${FIX_COUNTS[comment_space]} -gt 0 ]] && echo -e "  Comment space:           ${FIX_COUNTS[comment_space]}"
        [[ ${FIX_COUNTS[truthy]} -gt 0 ]] && echo -e "  Truthy values:           ${FIX_COUNTS[truthy]}"
        [[ ${FIX_COUNTS[privileged]} -gt 0 ]] && echo -e "  Privileged fix:          ${FIX_COUNTS[privileged]}"
        [[ ${FIX_COUNTS[run_as_non_root]} -gt 0 ]] && echo -e "  RunAsNonRoot:            ${FIX_COUNTS[run_as_non_root]}"
        [[ ${FIX_COUNTS[readonly_rootfs]} -gt 0 ]] && echo -e "  ReadOnlyRootFS:          ${FIX_COUNTS[readonly_rootfs]}"
        [[ ${FIX_COUNTS[network_policy]} -gt 0 ]] && echo -e "  NetworkPolicy:           ${FIX_COUNTS[network_policy]}"
        [[ ${FIX_COUNTS[drop_capabilities]} -gt 0 ]] && echo -e "  Drop capabilities:       ${FIX_COUNTS[drop_capabilities]}"
        [[ ${FIX_COUNTS[missing_labels]} -gt 0 ]] && echo -e "  Missing labels:          ${FIX_COUNTS[missing_labels]}"
        [[ ${FIX_COUNTS[missing_annotations]} -gt 0 ]] && echo -e "  Missing annotations:     ${FIX_COUNTS[missing_annotations]}"
        [[ ${FIX_COUNTS[default_namespace]} -gt 0 ]] && echo -e "  Default namespace:       ${FIX_COUNTS[default_namespace]}"
        [[ ${FIX_COUNTS[liveness_probe]} -gt 0 ]] && echo -e "  Liveness probe:          ${FIX_COUNTS[liveness_probe]}"
        [[ ${FIX_COUNTS[readiness_probe]} -gt 0 ]] && echo -e "  Readiness probe:         ${FIX_COUNTS[readiness_probe]}"
        [[ ${FIX_COUNTS[pdb]} -gt 0 ]] && echo -e "  PDB:                     ${FIX_COUNTS[pdb]}"
        [[ ${FIX_COUNTS[anti_affinity]} -gt 0 ]] && echo -e "  Anti-affinity:           ${FIX_COUNTS[anti_affinity]}"
        [[ ${FIX_COUNTS[topology_spread]} -gt 0 ]] && echo -e "  Topology spread:         ${FIX_COUNTS[topology_spread]}"
        [[ ${FIX_COUNTS[resource_limits]} -gt 0 ]] && echo -e "  Resource limits:         ${FIX_COUNTS[resource_limits]}"
        [[ ${FIX_COUNTS[resource_requests]} -gt 0 ]] && echo -e "  Resource requests:       ${FIX_COUNTS[resource_requests]}"
        [[ ${FIX_COUNTS[requests_gt_limits]} -gt 0 ]] && echo -e "  Requests > limits fix:   ${FIX_COUNTS[requests_gt_limits]}"
        [[ ${FIX_COUNTS[resource_quota]} -gt 0 ]] && echo -e "  Resource quota:          ${FIX_COUNTS[resource_quota]}"
        echo -e "  ─────────────────────────────────"
        echo -e "  ${BOLD}ВСЕГО:                     $total${NC}"
    else
        echo -e "  Исправлений не требовалось"
    fi
    echo ""
}

main() {
    local target_dir=""
    local recursive=0
    local backup=0
    local dry_run=0

    # Detect optional tools at startup
    detect_optional_tools

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -r|--recursive) recursive=1; shift ;;
            -b|--backup) backup=1; shift ;;
            -n|--dry-run) dry_run=1; shift ;;
            -i|--interactive) INTERACTIVE=1; shift ;;
            --from-report) FROM_REPORT="$2"; shift 2 ;;
            -v|--verbose) VERBOSE=1; shift ;;
            -q|--quiet) QUIET_MODE=1; shift ;;
            -c|--config) CONFIG_FILE="$2"; shift 2 ;;
            -*) echo "Неизвестная опция: $1"; usage ;;
            *) target_dir="$1"; shift ;;
        esac
    done

    if [[ -z "$target_dir" ]]; then
        echo -e "${RED}Ошибка: Не указан файл или директория${NC}"
        usage
    fi

    if [[ ! -e "$target_dir" ]]; then
        echo -e "${RED}Ошибка: Файл или директория не существует: $target_dir${NC}"
        exit 1
    fi

    # Validate report file if provided
    if [[ -n "$FROM_REPORT" ]]; then
        if [[ ! -f "$FROM_REPORT" ]]; then
            echo -e "${RED}Ошибка: Файл отчета не найден: $FROM_REPORT${NC}"
            exit 1
        fi
        if ! grep -q '"version"' "$FROM_REPORT" 2>/dev/null; then
            echo -e "${RED}Ошибка: Некорректный формат JSON отчета: $FROM_REPORT${NC}"
            exit 1
        fi
    fi

    # Parse config file if provided
    if [[ -n "$CONFIG_FILE" ]]; then
        parse_fixerrc "$CONFIG_FILE"
    fi

    if [[ $QUIET_MODE -eq 0 ]]; then
        print_header

        if [[ $dry_run -eq 1 ]]; then
            [[ $QUIET_MODE -eq 0 ]] && echo -e "${YELLOW}${BOLD}РЕЖИМ: DRY-RUN (файлы не будут изменены)${NC}"
            echo ""
        fi

        if [[ $INTERACTIVE -eq 1 ]]; then
            [[ $QUIET_MODE -eq 0 ]] && echo -e "${MAGENTA}${BOLD}РЕЖИМ: ИНТЕРАКТИВНЫЙ (будут заданы вопросы)${NC}"
            echo ""
        fi

        if [[ -n "$FROM_REPORT" ]]; then
            [[ $QUIET_MODE -eq 0 ]] && echo -e "${BLUE}${BOLD}РЕЖИМ: ИНТЕГРАЦИЯ С ОТЧЕТОМ ВАЛИДАТОРА${NC}"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  Отчет: ${CYAN}$FROM_REPORT${NC}"
            if [[ ${OPTIONAL_TOOLS[jq]} -eq 1 ]]; then
                [[ $QUIET_MODE -eq 0 ]] && echo -e "  JSON parser: ${GREEN}jq${NC}"
            else
                [[ $QUIET_MODE -eq 0 ]] && echo -e "  JSON parser: ${YELLOW}grep (fallback)${NC}"
            fi
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${BOLD}Будут исправлены только проблемы из отчета${NC}"
            echo ""
        fi

        if [[ -n "$CONFIG_FILE" ]]; then
            [[ $QUIET_MODE -eq 0 ]] && echo -e "${BLUE}${BOLD}РЕЖИМ: BATCH С КОНФИГУРАЦИЕЙ${NC}"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  Конфиг: ${CYAN}$CONFIG_FILE${NC}"
            [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${BOLD}K8s auto-fixes включены${NC}"
            echo ""
        fi

        [[ $QUIET_MODE -eq 0 ]] && echo -e "${BOLD}Начинаю обработку YAML файлов...${NC}"
    fi

    # Handle both files and directories
    if [[ -f "$target_dir" ]]; then
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "Файл: ${CYAN}$target_dir${NC}"
            echo -e "Backup: ${CYAN}$([ $backup -eq 1 ] && echo "Да" || echo "Нет")${NC}"
            echo ""
        fi

        local allowed_fixes=""
        if [[ -n "$FROM_REPORT" ]]; then
            allowed_fixes=$(get_fixable_issues "$FROM_REPORT" "$target_dir")
        fi
        fix_file "$target_dir" "$backup" "$dry_run" "$INTERACTIVE" "$allowed_fixes"
    else
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "Директория: ${CYAN}$target_dir${NC}"
            echo -e "Режим: ${CYAN}$([ $recursive -eq 1 ] && echo "Рекурсивный" || echo "Только текущая директория")${NC}"
            echo -e "Backup: ${CYAN}$([ $backup -eq 1 ] && echo "Да" || echo "Нет")${NC}"
            echo ""
        fi

        find_and_fix_files "$target_dir" "$recursive" "$backup" "$dry_run" "$INTERACTIVE"
    fi

    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}ИТОГИ${NC}"
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "Всего обработано: ${BOLD}$TOTAL_FILES${NC} файлов"

        if [[ $dry_run -eq 1 ]]; then
            echo -e "${YELLOW}Режим DRY-RUN: Изменения не применены${NC}"
        else
            echo -e "Исправлено:       ${GREEN}$FIXED_FILES${NC} файлов"
            echo ""
            print_statistics
            if [[ $FIXED_FILES -gt 0 ]]; then
                echo -e "${GREEN}Рекомендация: Запустите валидатор для проверки результата:${NC}"
                echo -e "  ./yaml_validator.sh $([ $recursive -eq 1 ] && echo "-r") \"$target_dir\""
            else
                echo -e "${GREEN}Все файлы уже корректны!${NC}"
            fi
        fi
    fi
    echo ""
}

main "$@"
