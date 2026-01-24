#!/bin/bash

#############################################################################
# YAML Validator for Air-Gapped Environments
# Pure bash implementation for Astra Linux SE 1.7 (Smolensk)
# Purpose: Validate YAML files in Kubernetes clusters without external tools
# Author: Generated for isolated environments
# Version: 2.8.0
# Updated: 2026-01-24
#############################################################################

set -o pipefail

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# Global variables
TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
ERRORS_FOUND=()

# Severity levels (exit code influence)
# ERROR: Blocks deployment, always fails validation (exit 1)
# WARNING: Should be fixed, fails in strict mode
# INFO: Style/informational, never fails
# SECURITY: Security issue, configurable severity

# Severity counters (per-file, reset for each file)
declare -A SEVERITY_COUNTS
SEVERITY_COUNTS[ERROR]=0
SEVERITY_COUNTS[WARNING]=0
SEVERITY_COUNTS[INFO]=0
SEVERITY_COUNTS[SECURITY]=0

# Total severity counters (cumulative)
declare -A TOTAL_SEVERITY_COUNTS
TOTAL_SEVERITY_COUNTS[ERROR]=0
TOTAL_SEVERITY_COUNTS[WARNING]=0
TOTAL_SEVERITY_COUNTS[INFO]=0
TOTAL_SEVERITY_COUNTS[SECURITY]=0

# Security mode: strict | normal | permissive
# strict: SECURITY → ERROR (production)
# normal: SECURITY → WARNING (default)
# permissive: SECURITY → INFO (test/dev)
SECURITY_MODE="normal"

# Strict mode: treat all warnings as errors
STRICT_MODE=0

# Optional checks (disabled by default)
CHECK_KEY_ORDERING=0      # A18: K8s key ordering convention
CHECK_PARTIAL_SCHEMA=0    # C31-33: Partial type/enum validation

# Reset severity counters for a new file
reset_severity_counts() {
    SEVERITY_COUNTS[ERROR]=0
    SEVERITY_COUNTS[WARNING]=0
    SEVERITY_COUNTS[INFO]=0
    SEVERITY_COUNTS[SECURITY]=0
}

# Add to total severity counters
add_to_totals() {
    ((TOTAL_SEVERITY_COUNTS[ERROR] += SEVERITY_COUNTS[ERROR]))
    ((TOTAL_SEVERITY_COUNTS[WARNING] += SEVERITY_COUNTS[WARNING]))
    ((TOTAL_SEVERITY_COUNTS[INFO] += SEVERITY_COUNTS[INFO]))
    ((TOTAL_SEVERITY_COUNTS[SECURITY] += SEVERITY_COUNTS[SECURITY]))
}

# Get effective severity based on SECURITY_MODE and STRICT_MODE
# Usage: get_effective_severity "SECURITY" → returns "ERROR" or "WARNING" or "INFO"
get_effective_severity() {
    local severity="$1"

    # Handle SECURITY level based on security mode
    if [[ "$severity" == "SECURITY" ]]; then
        case "$SECURITY_MODE" in
            strict) severity="ERROR" ;;
            normal) severity="WARNING" ;;
            permissive) severity="INFO" ;;
        esac
    fi

    # In strict mode, WARNING becomes ERROR
    if [[ $STRICT_MODE -eq 1 && "$severity" == "WARNING" ]]; then
        severity="ERROR"
    fi

    echo "$severity"
}

# Format message with severity prefix
# Usage: format_msg "ERROR" "Строка 5" "Description"
format_msg() {
    local severity="$1"
    local location="$2"
    local message="$3"

    local effective_severity
    effective_severity=$(get_effective_severity "$severity")

    # Increment counter
    ((SEVERITY_COUNTS[$severity]++))

    # Color and prefix based on effective severity
    local prefix color
    case "$effective_severity" in
        ERROR)   prefix="❌ [ERROR]"; color="$RED" ;;
        WARNING) prefix="⚠️  [WARN]"; color="$YELLOW" ;;
        INFO)    prefix="ℹ️  [INFO]"; color="$BLUE" ;;
        *)       prefix="[$severity]"; color="$NC" ;;
    esac

    # For security issues, add special marker
    if [[ "$severity" == "SECURITY" ]]; then
        prefix="🔒 [SECURITY:$SECURITY_MODE]"
        case "$SECURITY_MODE" in
            strict) color="$RED" ;;
            normal) color="$YELLOW" ;;
            permissive) color="$BLUE" ;;
        esac
    fi

    echo -e "${color}${prefix}${NC} ${location}: ${message}"
}

# Check if file has blocking errors (should fail validation)
file_has_errors() {
    # Always fail on ERROR
    [[ ${SEVERITY_COUNTS[ERROR]} -gt 0 ]] && return 0

    # In strict mode, WARNING and SECURITY also fail
    if [[ $STRICT_MODE -eq 1 ]]; then
        [[ ${SEVERITY_COUNTS[WARNING]} -gt 0 ]] && return 0
        [[ ${SEVERITY_COUNTS[SECURITY]} -gt 0 ]] && return 0
    fi

    # In strict security mode, SECURITY fails
    if [[ "$SECURITY_MODE" == "strict" && ${SEVERITY_COUNTS[SECURITY]} -gt 0 ]]; then
        return 0
    fi

    return 1
}

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                    YAML Validator v2.8.0                              ║"
    echo "║              Pure Bash Implementation for Air-Gapped Env              ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

usage() {
    cat << EOF
Использование: $0 [ОПЦИИ] <файл_или_директория>

Опции:
    -o, --output FILE       Сохранить отчёт в файл (по умолчанию: yaml_validation_report.txt)
    -r, --recursive         Рекурсивный поиск YAML файлов (только для директорий)
    -v, --verbose           Подробный вывод
    -s, --strict            Строгий режим: WARNING и SECURITY → ERROR
    --security-mode MODE    Режим безопасности: strict | normal | permissive
                            strict    - SECURITY → ERROR (production)
                            normal    - SECURITY → WARNING (default)
                            permissive - SECURITY → INFO (test/dev)
    --key-ordering          Включить проверку порядка ключей K8s (A18)
    --partial-schema        Включить частичную проверку типов (C31-C33)
    --all-checks            Включить все опциональные проверки
    -h, --help              Показать эту справку

Уровни серьёзности:
    ERROR     Блокирует деплой, всегда ошибка валидации
    WARNING   Следует исправить, ошибка в strict режиме
    INFO      Стиль/информация, никогда не ошибка
    SECURITY  Проблема безопасности, зависит от --security-mode

Примеры:
    $0 /path/to/manifests
    $0 config.yaml
    $0 -r -o report.txt /path/to/manifests
    $0 --strict /home/user/k8s/                      # Строгий режим
    $0 --security-mode permissive test-manifests/    # Тестовый кластер
    $0 --security-mode strict production-manifests/  # Продакшн

EOF
    exit 0
}

check_windows_encoding() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        if [[ "$line" == *$'\r'* ]]; then
            errors+=("Строка $line_num: Обнаружены символы Windows (CRLF). Используйте Unix формат (LF)")
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_tabs() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        if [[ "$line" == *$'\t'* ]]; then
            errors+=("Строка $line_num: Обнаружены табы. YAML требует пробелы для отступов")
            errors+=("  Содержимое: ${line}")
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_trailing_whitespace() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        if [[ "$line" =~ [[:space:]]$ ]] && [[ -n "$line" ]]; then
            errors+=("Строка $line_num: Обнаружены пробелы в конце строки")
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_bom() {
    local file="$1"
    local errors=()

    # Check for UTF-8 BOM (EF BB BF)
    if [[ -f "$file" ]]; then
        local first_bytes
        first_bytes=$(head -c 3 "$file" | od -An -tx1 | tr -d ' \n')
        if [[ "$first_bytes" == "efbbbf" ]]; then
            errors+=("КРИТИЧЕСКАЯ ОШИБКА: Обнаружен BOM (Byte Order Mark) в начале файла")
            errors+=("  BOM-символы невидимы, но могут нарушить парсинг YAML")
            errors+=("  Исправление: sed -i '1s/^\xEF\xBB\xBF//' $file")
        fi
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_empty_file() {
    local file="$1"
    local errors=()
    local has_content=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        if [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
            has_content=1
            break
        fi
    done < "$file"

    if [[ $has_content -eq 0 ]]; then
        errors+=("=== ОШИБКА: ПУСТОЙ ФАЙЛ ===")
        errors+=("Файл не содержит данных (только пробелы, комментарии или пустые строки)")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_empty_keys() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Check for empty key before colon (: value)
        if [[ "$line" =~ ^([[:space:]]*):([[:space:]].*)?$ ]]; then
            errors+=("Строка $line_num: Пустой ключ (отсутствует имя перед двоеточием)")
            errors+=("  Содержимое: ${line}")
        fi

        # Check for keys that are only whitespace in quotes
        if [[ "$line" =~ ^[[:space:]]*\"[[:space:]]+\":[[:space:]] ]]; then
            errors+=("Строка $line_num: Ключ состоит только из пробелов")
            errors+=("  Содержимое: ${line}")
        fi

        # Check for empty string keys
        if [[ "$line" =~ ^[[:space:]]*\"\":[[:space:]] ]]; then
            errors+=("Строка $line_num: Пустая строка в качестве ключа")
            errors+=("  Содержимое: ${line}")
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_duplicate_keys() {
    local file="$1"
    local line_num=0
    local errors=()
    declare -A keys_by_level
    local prev_indent=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^---$ || "$line" =~ ^\.\.\.$ ]] && continue

        # Detect list items (- key:) - they create new scope
        if [[ "$line" =~ ^([[:space:]]*)-[[:space:]] ]]; then
            local list_indent="${BASH_REMATCH[1]}"
            local list_indent_level=${#list_indent}

            # Clear keys from this level and deeper (new list item = new scope)
            for level_key in "${!keys_by_level[@]}"; do
                local stored_level="${level_key%%_*}"
                if (( stored_level >= list_indent_level )); then
                    unset "keys_by_level[$level_key]"
                fi
            done
            prev_indent=$list_indent_level
            continue
        fi

        # Extract key and indent level
        if [[ "$line" =~ ^([[:space:]]*)([^:[:space:]]+|\"[^\"]+\"):[[:space:]] ]]; then
            local indent="${BASH_REMATCH[1]}"
            local key="${BASH_REMATCH[2]}"
            local indent_level=${#indent}

            # Remove quotes from key if present
            key="${key//\"/}"

            # When indent decreases or stays same, clear keys from equal/deeper levels
            # (scope exit or sibling key like requests → limits)
            if (( indent_level <= prev_indent )); then
                for level_key in "${!keys_by_level[@]}"; do
                    local stored_level="${level_key%%_*}"
                    if (( stored_level >= indent_level )); then
                        unset "keys_by_level[$level_key]"
                    fi
                done
            fi

            # Create unique identifier for this indent level + key
            local level_key="${indent_level}_${key}"

            if [[ -n "${keys_by_level[$level_key]}" ]]; then
                errors+=("Строка $line_num: Дубликат ключа '$key' на уровне отступа $indent_level")
                errors+=("  Первое определение: строка ${keys_by_level[$level_key]}")
                errors+=("  Содержимое: ${line}")
            else
                keys_by_level[$level_key]=$line_num
            fi

            prev_indent=$indent_level
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_document_markers() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for malformed document start markers (more or less than 3 dashes)
        if [[ "$line" =~ ^-{4,}[[:space:]]*$ ]]; then
            errors+=("Строка $line_num: Слишком много дефисов в маркере документа (должно быть 3)")
            errors+=("  Содержимое: $line")
        elif [[ "$line" =~ ^-{1,2}[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            errors+=("Строка $line_num: Недостаточно дефисов в маркере документа (должно быть 3)")
            errors+=("  Содержимое: $line")
        fi

        # Check for malformed document end markers
        if [[ "$line" =~ ^\.{4,}[[:space:]]*$ ]]; then
            errors+=("Строка $line_num: Слишком много точек в маркере конца документа (должно быть 3)")
            errors+=("  Содержимое: $line")
        elif [[ "$line" =~ ^\.{1,2}[[:space:]]*$ ]]; then
            errors+=("Строка $line_num: Недостаточно точек в маркере конца документа (должно быть 3)")
            errors+=("  Содержимое: $line")
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_special_values() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for YAML 1.1 boolean-like values that may be misinterpreted
        if [[ "$line" =~ :[[:space:]]+(yes|Yes|YES)[[:space:]]*$ ]]; then
            errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: 'yes' интерпретируется как true в YAML 1.1")
            errors+=("  Содержимое: ${line}")
            errors+=("  Рекомендация: Используйте 'true' или закавычьте \"yes\" если нужна строка")
        fi

        if [[ "$line" =~ :[[:space:]]+(no|No|NO)[[:space:]]*$ ]]; then
            errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: 'no' интерпретируется как false в YAML 1.1")
            errors+=("  Содержимое: ${line}")
            errors+=("  Рекомендация: Используйте 'false' или закавычьте \"no\" если нужна строка")
        fi

        if [[ "$line" =~ :[[:space:]]+(on|On|ON)[[:space:]]*$ ]]; then
            errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: 'on' интерпретируется как true в YAML 1.1")
            errors+=("  Содержимое: ${line}")
        fi

        if [[ "$line" =~ :[[:space:]]+(off|Off|OFF)[[:space:]]*$ ]]; then
            errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: 'off' интерпретируется как false в YAML 1.1")
            errors+=("  Содержимое: ${line}")
        fi

        if [[ "$line" =~ :[[:space:]]+~[[:space:]]*$ ]]; then
            errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: '~' интерпретируется как null")
            errors+=("  Содержимое: ${line}")
            errors+=("  Рекомендация: Используйте явное 'null' для лучшей читаемости")
        fi

        if [[ "$line" =~ :[[:space:]]+(NULL|Null)[[:space:]]*$ ]]; then
            errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: '$( [[ "$line" =~ (NULL|Null) ]] && echo "${BASH_REMATCH[1]}")' будет интерпретировано как null")
            errors+=("  Содержимое: ${line}")
            errors+=("  Рекомендация: Используйте lowercase 'null' для стандартизации")
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_indentation() {
    local file="$1"
    local line_num=0
    local errors=()
    local indent_size=0
    local first_indent_detected=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^---$ || "$line" =~ ^\.\.\.$ ]] && continue

        local current_indent=0
        if [[ "$line" =~ ^([[:space:]]*) ]]; then
            current_indent=${#BASH_REMATCH[1]}
        fi

        if [[ $first_indent_detected -eq 0 && $current_indent -gt 0 ]]; then
            indent_size=$current_indent
            first_indent_detected=1
        fi

        if [[ $indent_size -gt 0 && $current_indent -gt 0 ]]; then
            if [[ $((current_indent % indent_size)) -ne 0 ]]; then
                errors+=("Строка $line_num: Несогласованный отступ ($current_indent пробелов, ожидается кратное $indent_size)")
                errors+=("  Содержимое: ${line}")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_basic_syntax() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_multiline=0
    local multiline_indent=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        [[ -z "$line" ]] && continue
        local trimmed_line="${line%%[[:space:]]}"
        [[ "$trimmed_line" =~ ^[[:space:]]*# ]] && continue

        # Detect multiline block start: "key: |" or "key: >"
        if [[ "$line" =~ ^([[:space:]]*)([^:]+):[[:space:]]*[\|\>]([[:space:]]*|[[:space:]]+.*)$ ]]; then
            in_multiline=1
            multiline_indent=${#BASH_REMATCH[1]}
            continue
        fi

        # Inside multiline: skip validation until indent returns to base level
        if [[ $in_multiline -eq 1 ]]; then
            local current_indent=0
            if [[ "$line" =~ ^([[:space:]]*) ]]; then
                current_indent=${#BASH_REMATCH[1]}
            fi

            # Check if we have a non-empty line at or before multiline indent level
            if [[ "$line" =~ ^[[:space:]]*[^[:space:]] ]] && [[ $current_indent -le $multiline_indent ]]; then
                in_multiline=0
                # Don't skip this line, process it as normal YAML
            else
                continue  # Skip validation for multiline content
            fi
        fi

        # Check bracket matching for inline JSON in YAML
        local open_square=0
        local close_square=0
        local open_curly=0
        local close_curly=0

        # Count brackets (simple approach, not accounting for quotes)
        open_square=$(echo "$line" | grep -o '\[' | wc -l)
        close_square=$(echo "$line" | grep -o '\]' | wc -l)
        open_curly=$(echo "$line" | grep -o '{' | wc -l)
        close_curly=$(echo "$line" | grep -o '}' | wc -l)

        if [[ $open_square -ne $close_square ]]; then
            errors+=("Строка $line_num: Непарные квадратные скобки [ ] (открытых: $open_square, закрытых: $close_square)")
            errors+=("  Содержимое: ${line}")
        fi

        if [[ $open_curly -ne $close_curly ]]; then
            errors+=("Строка $line_num: Непарные фигурные скобки { } (открытых: $open_curly, закрытых: $close_curly)")
            errors+=("  Содержимое: ${line}")
        fi

        local single_quotes
        local double_quotes
        single_quotes=$(echo "$line" | grep -o "'" | wc -l)
        double_quotes=$(echo "$line" | grep -o '"' | wc -l)

        if [[ $((single_quotes % 2)) -ne 0 ]]; then
            errors+=("Строка $line_num: Непарные одинарные кавычки")
            errors+=("  Содержимое: ${line}")
        fi

        if [[ $((double_quotes % 2)) -ne 0 ]]; then
            errors+=("Строка $line_num: Непарные двойные кавычки")
            errors+=("  Содержимое: ${line}")
        fi

        if [[ "$line" =~ ^[[:space:]]*([^:]+):(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            if [[ "$key" =~ ^[[:space:]]*-[[:space:]]+(.+)$ ]]; then
                key="${BASH_REMATCH[1]}"
            fi

            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"

            if [[ "$key" =~ [^a-zA-Z0-9_.\/-] ]]; then
                errors+=("Строка $line_num: Ключ содержит недопустимые символы: '$key'")
                errors+=("  Содержимое: ${line}")
            fi

            if [[ -n "$value" && ! "$value" =~ ^[[:space:]] ]]; then
                errors+=("Строка $line_num: Отсутствует пробел после двоеточия")
                errors+=("  Содержимое: ${line}")
                errors+=("  Исправление: Добавьте пробел после ':' -> '$key: ${value}'")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_label_format() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_labels=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect if we're inside a labels section
        if [[ "$line" =~ ^[[:space:]]*labels:[[:space:]]*$ ]]; then
            in_labels=1
            continue
        fi

        # Exit labels section if indent decreases or we hit a new top-level key
        if [[ $in_labels -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{0,2}[a-zA-Z] ]]; then
            in_labels=0
        fi

        # Validate label format if inside labels section
        if [[ $in_labels -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+([^:]+):[[:space:]] ]]; then
            local label_key="${BASH_REMATCH[1]}"
            label_key="${label_key#"${label_key%%[![:space:]]*}"}"
            label_key="${label_key%"${label_key##*[![:space:]]}"}"

            # Skip list items (- name:, - containerPort:, etc.)
            [[ "$label_key" =~ ^- ]] && continue

            # Kubernetes label name rules:
            # - Max 63 characters
            # - Alphanumeric, '-', '_', '.'
            # - Must start and end with alphanumeric

            if [[ ${#label_key} -gt 63 ]]; then
                errors+=("Строка $line_num: Ключ метки слишком длинный (${#label_key} > 63 символов)")
                errors+=("  Ключ: $label_key")
            fi

            if [[ "$label_key" =~ ^- ]] || [[ "$label_key" =~ -$ ]]; then
                errors+=("Строка $line_num: Некорректный формат ключа метки '$label_key'")
                errors+=("  Допустимы: буквы, цифры, '-', '_', '.' (начинается и заканчивается буквой/цифрой)")
            fi

            if [[ ! "$label_key" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$ ]]; then
                errors+=("Строка $line_num: Некорректный формат ключа метки '$label_key'")
                errors+=("  Допустимы: буквы, цифры, '-', '_', '.' (начинается и заканчивается буквой/цифрой)")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_anchors_aliases() {
    local file="$1"
    local line_num=0
    local errors=()
    declare -A anchors

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect anchor definitions (&anchor_name)
        if [[ "$line" =~ \&([a-zA-Z0-9_-]+) ]]; then
            local anchor_name="${BASH_REMATCH[1]}"
            if [[ -n "${anchors[$anchor_name]}" ]]; then
                errors+=("Строка $line_num: Дублированный anchor '&$anchor_name'")
                errors+=("  Первое определение: строка ${anchors[$anchor_name]}")
            else
                anchors[$anchor_name]=$line_num
            fi
        fi

        # Detect alias usage (*alias_name)
        if [[ "$line" =~ \*([a-zA-Z0-9_-]+) ]]; then
            local alias_name="${BASH_REMATCH[1]}"
            if [[ -z "${anchors[$alias_name]}" ]]; then
                errors+=("Строка $line_num: Использование неопределённого alias '*$alias_name'")
                errors+=("  Содержимое: ${line}")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_base64_in_secrets() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_data_section=0
    local is_secret_kind=0
    local data_indent=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect if this is a Secret
        if [[ "$line" =~ ^kind:[[:space:]]*Secret[[:space:]]*$ ]]; then
            is_secret_kind=1
        fi

        # Detect data: section in Secret
        if [[ $is_secret_kind -eq 1 ]] && [[ "$line" =~ ^data:[[:space:]]*$ ]]; then
            in_data_section=1
            data_indent=0
            continue
        fi

        # Track indent to know when we exit data section
        if [[ $in_data_section -eq 1 ]]; then
            local current_indent=0
            if [[ "$line" =~ ^([[:space:]]*) ]]; then
                current_indent=${#BASH_REMATCH[1]}
            fi

            # Exit data section on non-indented line
            if [[ "$line" =~ ^[a-zA-Z] ]]; then
                in_data_section=0
                continue
            fi

            # Set data_indent on first data line
            if [[ $data_indent -eq 0 ]] && [[ $current_indent -gt 0 ]]; then
                data_indent=$current_indent
            fi

            # Validate base64 values in data section
            if [[ "$line" =~ ^[[:space:]]+([^:]+):[[:space:]]+(.+)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"

                # Trim whitespace
                key="${key#"${key%%[![:space:]]*}"}"
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"

                # Skip if empty or quoted (stringData uses plain text)
                [[ -z "$value" ]] && continue
                [[ "$value" =~ ^[\"\'] ]] && continue

                # Check if it looks like base64 (alphanumeric + / + = padding)
                if [[ ! "$value" =~ ^[A-Za-z0-9+/]*=*$ ]]; then
                    errors+=("Строка $line_num: Secret.data '$key' содержит невалидный base64")
                    errors+=("  Значение: $value")
                    errors+=("  Рекомендация: Используйте 'stringData' для незакодированных значений")
                fi

                # Check base64 padding
                local len=${#value}
                local mod=$((len % 4))
                if [[ $mod -eq 1 ]]; then
                    errors+=("Строка $line_num: Secret.data '$key' имеет некорректную длину base64")
                    errors+=("  Длина $len не кратна 4 (mod=$mod)")
                fi
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_numeric_formats() {
    local file="$1"
    local line_num=0
    local info=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for octal numbers (common mistake with file permissions)
        # mode: 0644 is octal (420), mode: 644 is decimal (644)
        # This is INFO only - octal is valid, just informing user
        if [[ "$line" =~ (mode|defaultMode|fsGroup|runAsUser|runAsGroup):[[:space:]]+0([0-7]+)[[:space:]]*$ ]]; then
            local field="${BASH_REMATCH[1]}"
            local octal_value="0${BASH_REMATCH[2]}"
            # Convert octal to decimal for info
            local decimal_value=$((8#${BASH_REMATCH[2]}))
            info+=("Строка $line_num: ИНФОРМАЦИЯ: '$field: $octal_value' это octal (=$decimal_value в десятичной)")
            info+=("  Если нужен decimal 644, уберите ведущий 0")
        fi

        # Check for hexadecimal values (may be unintentional) - INFO only
        if [[ "$line" =~ :[[:space:]]+0x[0-9A-Fa-f]+[[:space:]]*$ ]]; then
            info+=("Строка $line_num: ИНФОРМАЦИЯ: Обнаружено hex число в значении")
            info+=("  Содержимое: ${line}")
        fi

        # Check for scientific notation (may be unintentional string) - INFO only
        if [[ "$line" =~ :[[:space:]]+[0-9]+[eE][+-]?[0-9]+[[:space:]]*$ ]]; then
            info+=("Строка $line_num: ИНФОРМАЦИЯ: Обнаружена научная нотация")
            info+=("  Содержимое: ${line}")
            info+=("  Если нужна строка, заключите в кавычки")
        fi

        # Check for infinity/NaN - INFO only
        if [[ "$line" =~ :[[:space:]]+(\.inf|-\.inf|\.nan|\.Inf|-\.Inf|\.NaN)[[:space:]]*$ ]]; then
            info+=("Строка $line_num: ИНФОРМАЦИЯ: Специальное числовое значение '${BASH_REMATCH[1]}'")
            info+=("  Содержимое: ${line}")
        fi
    done < "$file"

    # These are all informational - output but don't fail
    if [[ ${#info[@]} -gt 0 ]]; then
        printf '%s\n' "${info[@]}"
    fi

    # Always return 0 - these are just informational notices
    return 0
}

check_resource_quantities() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_resources=0
    local resource_indent=0

    # Valid K8s resource quantity suffixes
    # Binary: Ki, Mi, Gi, Ti, Pi, Ei
    # Decimal: n, u, m, k, M, G, T, P, E
    local valid_suffixes="(Ki|Mi|Gi|Ti|Pi|Ei|n|u|m|k|M|G|T|P|E)"

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Detect resources: section
        if [[ "$line" =~ ^([[:space:]]*)resources:[[:space:]]*$ ]]; then
            in_resources=1
            resource_indent=${#BASH_REMATCH[1]}
            continue
        fi

        # Track if we're still in resources section
        if [[ $in_resources -eq 1 ]]; then
            local current_indent=0
            if [[ "$line" =~ ^([[:space:]]*)[^[:space:]] ]]; then
                current_indent=${#BASH_REMATCH[1]}
            fi

            # Exit resources if indent goes back to or before resources level
            if [[ $current_indent -le $resource_indent ]] && [[ "$line" =~ ^[[:space:]]*[a-zA-Z] ]]; then
                in_resources=0
            fi
        fi

        # Validate memory/cpu quantities
        if [[ "$line" =~ (memory|cpu|storage|ephemeral-storage):[[:space:]]+([^[:space:]]+) ]]; then
            local resource_type="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove quotes if present
            value="${value//\"/}"
            value="${value//\'/}"

            # Skip if empty
            [[ -z "$value" ]] && continue

            # Memory/storage should have quantity suffix
            if [[ "$resource_type" =~ ^(memory|storage|ephemeral-storage)$ ]]; then
                if [[ ! "$value" =~ ^[0-9]+${valid_suffixes}?$ ]]; then
                    errors+=("Строка $line_num: Возможно некорректный формат $resource_type: '$value'")
                    errors+=("  Допустимые суффиксы: Ki, Mi, Gi, Ti (binary) или k, M, G, T (decimal)")
                    errors+=("  Примеры: 128Mi, 1Gi, 500M")
                fi
            fi

            # CPU can be decimal (0.5) or millicores (500m)
            if [[ "$resource_type" == "cpu" ]]; then
                if [[ ! "$value" =~ ^[0-9]+(\.[0-9]+)?m?$ ]] && [[ ! "$value" =~ ^[0-9]+$ ]]; then
                    errors+=("Строка $line_num: Возможно некорректный формат cpu: '$value'")
                    errors+=("  Допустимые форматы: 0.5, 1, 500m, 2000m")
                fi
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_port_ranges() {
    local file="$1"
    local line_num=0
    local errors=()
    local info=()
    local has_errors=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check port fields
        if [[ "$line" =~ (containerPort|hostPort|port|targetPort|nodePort):[[:space:]]+([0-9]+) ]]; then
            local port_type="${BASH_REMATCH[1]}"
            local port_value="${BASH_REMATCH[2]}"

            # Validate port range 1-65535
            if [[ $port_value -lt 1 ]] || [[ $port_value -gt 65535 ]]; then
                errors+=("Строка $line_num: Порт '$port_type: $port_value' вне допустимого диапазона (1-65535)")
                errors+=("  Содержимое: ${line}")
                has_errors=1
            fi

            # NodePort range is typically 30000-32767 (warning, not error)
            if [[ "$port_type" == "nodePort" ]]; then
                if [[ $port_value -lt 30000 ]] || [[ $port_value -gt 32767 ]]; then
                    info+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: nodePort $port_value вне стандартного диапазона (30000-32767)")
                fi
            fi

            # Privileged ports (info only, not error)
            if [[ $port_value -lt 1024 ]] && [[ "$port_type" =~ ^(containerPort|hostPort)$ ]]; then
                info+=("Строка $line_num: ИНФОРМАЦИЯ: Привилегированный порт $port_value (< 1024)")
            fi
        fi
    done < "$file"

    # Output all messages
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
    fi
    if [[ ${#info[@]} -gt 0 ]]; then
        printf '%s\n' "${info[@]}"
    fi

    # Only return 1 for actual errors, not for info/warnings
    return $has_errors
}

check_multiline_blocks() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_multiline=0
    # shellcheck disable=SC2034  # Reserved for future detailed error reporting
    local multiline_start=0
    # shellcheck disable=SC2034  # Reserved for future block type validation
    local multiline_type=""
    local multiline_indent=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip empty lines in multiline
        if [[ $in_multiline -eq 1 ]] && [[ -z "$line" ]]; then
            continue
        fi

        # Detect multiline block start: key: | or key: > with optional indicators
        # Indicators: |-, |+, |2, >-, >+, >2 etc.
        if [[ "$line" =~ ^([[:space:]]*)([^:]+):[[:space:]]*([\|\>])([-+]?[0-9]*)([[:space:]]*#.*)?$ ]]; then
            local indent="${BASH_REMATCH[1]}"
            local key="${BASH_REMATCH[2]}"
            local block_type="${BASH_REMATCH[3]}"
            local indicator="${BASH_REMATCH[4]}"

            in_multiline=1
            # shellcheck disable=SC2034
            multiline_start=$line_num
            multiline_indent=${#indent}
            # shellcheck disable=SC2034
            multiline_type="$block_type$indicator"

            # Info about block type
            if [[ -n "$indicator" ]]; then
                if [[ "$indicator" == "-" ]]; then
                    # Strip final newlines - valid
                    :
                elif [[ "$indicator" == "+" ]]; then
                    # Keep final newlines - valid
                    :
                elif [[ "$indicator" =~ ^[0-9]+$ ]]; then
                    # Explicit indentation indicator
                    if [[ $indicator -lt 1 ]] || [[ $indicator -gt 9 ]]; then
                        errors+=("Строка $line_num: Некорректный индикатор отступа '$indicator' (должен быть 1-9)")
                    fi
                fi
            fi
            continue
        fi

        # Track multiline block exit
        if [[ $in_multiline -eq 1 ]]; then
            local current_indent=0
            if [[ "$line" =~ ^([[:space:]]*)[^[:space:]] ]]; then
                current_indent=${#BASH_REMATCH[1]}
            fi

            # Exit multiline when indent returns to base level
            if [[ $current_indent -le $multiline_indent ]]; then
                in_multiline=0
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_sexagesimal() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Skip multiline blocks
        [[ "$line" =~ :[[:space:]]*[\|\>] ]] && continue

        # Detect sexagesimal patterns: XX:YY or XX:YY:ZZ (YAML 1.1 parses as base-60)
        # But skip if it looks like a port mapping (80:80) or time with quotes
        if [[ "$line" =~ :[[:space:]]+([0-9]{1,2}):([0-9]{2})(:[0-9]{2})?[[:space:]]*$ ]]; then
            local value="${BASH_REMATCH[0]}"
            # Skip if quoted
            [[ "$line" =~ :[[:space:]]+[\"\'] ]] && continue

            warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: '$value' интерпретируется как sexagesimal (base-60) в YAML 1.1")
            warnings+=("  Содержимое: ${line}")
            warnings+=("  21:00 = $((21*60)), 1:30:00 = $((1*3600 + 30*60))")
            warnings+=("  Рекомендация: Заключите в кавычки \"21:00\" если нужна строка")
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_extended_norway() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Extended boolean-like values in YAML 1.1
        # y, Y, n, N are also booleans!
        if [[ "$line" =~ :[[:space:]]+(y|Y)[[:space:]]*$ ]]; then
            warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: 'y/Y' = true в YAML 1.1 (Norway Problem)")
            warnings+=("  Содержимое: ${line}")
            warnings+=("  Рекомендация: Используйте 'true' или закавычьте \"y\"")
        fi

        if [[ "$line" =~ :[[:space:]]+(n|N)[[:space:]]*$ ]]; then
            warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: 'n/N' = false в YAML 1.1 (Norway Problem)")
            warnings+=("  Содержимое: ${line}")
            warnings+=("  Рекомендация: Используйте 'false' или закавычьте \"n\"")
        fi

        # Country codes that could be misinterpreted
        # NO (Norway), DE, FR are fine, but NO specifically is problematic
        if [[ "$line" =~ :[[:space:]]+(NO|No)[[:space:]]*$ ]]; then
            warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: 'NO' = false в YAML 1.1 (Norway Problem)")
            warnings+=("  Содержимое: ${line}")
            warnings+=("  Если это код страны Норвегии, закавычьте: \"NO\"")
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_yaml_bomb() {
    local file="$1"
    local errors=()
    declare -A anchor_refs
    # shellcheck disable=SC2034  # Reserved for future deep recursion check
    local max_depth=5
    local max_refs=10

    # Count anchor definitions and alias references
    local anchor_count=0
    local alias_count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Count anchors
        if [[ "$line" =~ \&([a-zA-Z0-9_-]+) ]]; then
            ((anchor_count++))
            local anchor="${BASH_REMATCH[1]}"
            anchor_refs[$anchor]=0
        fi

        # Count references to each anchor
        if [[ "$line" =~ \*([a-zA-Z0-9_-]+) ]]; then
            ((alias_count++))
            local alias="${BASH_REMATCH[1]}"
            if [[ -n "${anchor_refs[$alias]}" ]]; then
                ((anchor_refs[$alias]++))
            fi
        fi
    done < "$file"

    # Check for suspicious patterns
    # 1. Many aliases referencing same anchor (potential quadratic blowup)
    for anchor in "${!anchor_refs[@]}"; do
        if [[ ${anchor_refs[$anchor]} -gt $max_refs ]]; then
            errors+=("БЕЗОПАСНОСТЬ: Anchor '&$anchor' используется ${anchor_refs[$anchor]} раз (возможна YAML bomb)")
            errors+=("  Риск: Quadratic blowup attack (CVE-2019-11253)")
            errors+=("  Лимит: максимум $max_refs ссылок на один anchor")
        fi
    done

    # 2. Too many anchors (potential exponential expansion)
    if [[ $anchor_count -gt 20 ]]; then
        errors+=("БЕЗОПАСНОСТЬ: Обнаружено $anchor_count anchors (возможна Billion Laughs attack)")
        errors+=("  Рекомендация: Уменьшите количество anchors или проверьте файл вручную")
    fi

    # 3. High ratio of aliases to anchors (suspicious)
    if [[ $anchor_count -gt 0 ]] && [[ $alias_count -gt $((anchor_count * 10)) ]]; then
        errors+=("БЕЗОПАСНОСТЬ: Подозрительное соотношение aliases/anchors: $alias_count/$anchor_count")
        errors+=("  Риск: Возможная атака на расширение памяти")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_string_quoting() {
    local file="$1"
    local line_num=0
    local warnings=()

    # Characters that require quoting at start of value
    local special_start='[@{}\[\]*&!|>%#`]'

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Skip multiline blocks
        [[ "$line" =~ :[[:space:]]*[\|\>] ]] && continue

        # Check for unquoted values starting with special characters
        if [[ "$line" =~ :[[:space:]]+($special_start) ]]; then
            local char="${BASH_REMATCH[1]}"
            # Skip if already quoted
            [[ "$line" =~ :[[:space:]]+[\"\'] ]] && continue

            warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Значение начинается с '$char' — требуются кавычки")
            warnings+=("  Содержимое: ${line}")
        fi

        # Check for values that look like version numbers (1.0, 2.1.0)
        if [[ "$line" =~ :[[:space:]]+([0-9]+\.[0-9]+(\.[0-9]+)?)[[:space:]]*$ ]]; then
            local version="${BASH_REMATCH[1]}"
            # Skip if in known numeric contexts
            [[ "$line" =~ (apiVersion|version):[[:space:]] ]] && continue
            # Skip if already quoted
            [[ "$line" =~ :[[:space:]]+[\"\'] ]] && continue

            warnings+=("Строка $line_num: ИНФОРМАЦИЯ: '$version' может быть распарсен как float")
            warnings+=("  Если это версия, рекомендуется закавычить: \"$version\"")
        fi

        # Check for values containing ": " (colon-space) which breaks YAML
        if [[ "$line" =~ :[[:space:]]+[^\"\'][^:]*:[[:space:]] ]]; then
            # Skip if it's a nested key
            [[ "$line" =~ ^[[:space:]]+[a-zA-Z] ]] && continue
            warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Значение содержит ': ' — может сломать парсинг")
            warnings+=("  Содержимое: ${line}")
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_image_pull_policy() {
    local file="$1"
    local line_num=0
    local errors=()

    # Valid values (case-sensitive!)
    local valid_policies="Always|IfNotPresent|Never"

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check imagePullPolicy field
        if [[ "$line" =~ imagePullPolicy:[[:space:]]+([^[:space:]#]+) ]]; then
            local policy="${BASH_REMATCH[1]}"
            # Remove quotes if present
            policy="${policy//\"/}"
            policy="${policy//\'/}"

            if [[ ! "$policy" =~ ^($valid_policies)$ ]]; then
                errors+=("Строка $line_num: Некорректный imagePullPolicy: '$policy'")
                errors+=("  Допустимые значения: Always, IfNotPresent, Never (case-sensitive!)")

                # Suggest correction for common typos
                case "${policy,,}" in
                    always) errors+=("  Исправление: Always") ;;
                    ifnotpresent) errors+=("  Исправление: IfNotPresent") ;;
                    never) errors+=("  Исправление: Never") ;;
                esac
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_replicas_type() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check replicas field - must be a number, not a string
        if [[ "$line" =~ replicas:[[:space:]]+[\"\']([0-9]+)[\"\'] ]]; then
            local value="${BASH_REMATCH[1]}"
            errors+=("Строка $line_num: replicas должен быть числом, не строкой")
            errors+=("  Найдено: replicas: \"$value\"")
            errors+=("  Исправление: replicas: $value")
        fi

        # Check for non-numeric replicas
        if [[ "$line" =~ replicas:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            # Skip if it's a valid number
            [[ "$value" =~ ^[0-9]+$ ]] && continue
            # Skip if it's quoted (caught above)
            [[ "$value" =~ ^[\"\'] ]] && continue

            errors+=("Строка $line_num: replicas должен быть положительным целым числом")
            errors+=("  Найдено: replicas: $value")
        fi

        # Same for minReplicas, maxReplicas
        if [[ "$line" =~ (minReplicas|maxReplicas):[[:space:]]+[\"\']([0-9]+)[\"\'] ]]; then
            local field="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            errors+=("Строка $line_num: $field должен быть числом, не строкой")
            errors+=("  Исправление: $field: $value")
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_image_tags() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check image field
        if [[ "$line" =~ image:[[:space:]]+([^[:space:]#]+) ]]; then
            local image="${BASH_REMATCH[1]}"
            # Remove quotes
            image="${image//\"/}"
            image="${image//\'/}"

            # Skip empty
            [[ -z "$image" ]] && continue

            # Check for :latest tag
            if [[ "$image" =~ :latest$ ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Floating tag ':latest' не рекомендуется")
                warnings+=("  Image: $image")
                warnings+=("  Риск: Непредсказуемые обновления, проблемы с откатом")
                warnings+=("  Рекомендация: Используйте конкретный тег (например, nginx:1.21.0)")
            # Check for missing tag (no colon after image name, excluding digest)
            elif [[ ! "$image" =~ : ]] && [[ ! "$image" =~ @ ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Отсутствует тег образа (default: latest)")
                warnings+=("  Image: $image")
                warnings+=("  Рекомендация: Укажите конкретный тег: $image:version")
            fi

            # Check for digest (good practice, just info)
            if [[ "$image" =~ @sha256: ]]; then
                # This is actually good, no warning needed
                :
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_annotation_length() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_annotations=0
    local in_labels=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect sections
        if [[ "$line" =~ ^[[:space:]]+annotations:[[:space:]]*$ ]]; then
            in_annotations=1
            in_labels=0
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]+labels:[[:space:]]*$ ]]; then
            in_labels=1
            in_annotations=0
            continue
        fi

        # Exit section on dedent
        if [[ "$line" =~ ^[[:space:]]{0,4}[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]]{4,} ]]; then
            in_annotations=0
            in_labels=0
        fi

        # Check label values (max 63 chars)
        if [[ $in_labels -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+([^:]+):[[:space:]]+(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            key="${key#"${key%%[![:space:]]*}"}"
            value="${value//\"/}"
            value="${value//\'/}"
            value="${value%"${value##*[![:space:]]}"}"

            if [[ ${#value} -gt 63 ]]; then
                errors+=("Строка $line_num: Label value превышает 63 символа (${#value})")
                errors+=("  Ключ: $key")
                errors+=("  Значение: ${value:0:50}...")
            fi
        fi

        # Check annotation key format (max 253 chars with prefix)
        if [[ $in_annotations -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+([^:]+): ]]; then
            local key="${BASH_REMATCH[1]}"
            key="${key#"${key%%[![:space:]]*}"}"

            if [[ ${#key} -gt 253 ]]; then
                errors+=("Строка $line_num: Annotation key превышает 253 символа (${#key})")
                errors+=("  Ключ: ${key:0:50}...")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_security_context() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for privileged: true
        if [[ "$line" =~ privileged:[[:space:]]+(true|True|TRUE) ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: privileged: true — контейнер имеет root-доступ к хосту")
            warnings+=("  Риск: Container escape, полный доступ к хосту")
            warnings+=("  Рекомендация: Используйте capabilities вместо privileged")
        fi

        # Check for allowPrivilegeEscalation: true
        if [[ "$line" =~ allowPrivilegeEscalation:[[:space:]]+(true|True|TRUE) ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: allowPrivilegeEscalation: true")
            warnings+=("  Рекомендация: Установите allowPrivilegeEscalation: false")
        fi

        # Check for runAsNonRoot: false (explicitly allowing root)
        if [[ "$line" =~ runAsNonRoot:[[:space:]]+(false|False|FALSE) ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: runAsNonRoot: false — контейнер может работать от root")
            warnings+=("  Рекомендация: Установите runAsNonRoot: true и укажите runAsUser")
        fi

        # Check for hostNetwork: true
        if [[ "$line" =~ hostNetwork:[[:space:]]+(true|True|TRUE) ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: hostNetwork: true — контейнер использует сеть хоста")
            warnings+=("  Риск: Доступ ко всем сетевым интерфейсам хоста")
        fi

        # Check for hostPID: true
        if [[ "$line" =~ hostPID:[[:space:]]+(true|True|TRUE) ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: hostPID: true — контейнер видит процессы хоста")
        fi

        # Check for hostIPC: true
        if [[ "$line" =~ hostIPC:[[:space:]]+(true|True|TRUE) ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: hostIPC: true — контейнер имеет доступ к IPC хоста")
        fi

        # Check for common typos
        if [[ "$line" =~ runAsRoot:[[:space:]]+ ]]; then
            warnings+=("Строка $line_num: ОПЕЧАТКА: 'runAsRoot' не существует, используйте 'runAsNonRoot'")
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_probe_config() {
    local file="$1"
    local line_num=0
    local warnings=()
    # shellcheck disable=SC2034  # Used for state tracking in loop
    local has_liveness=0
    # shellcheck disable=SC2034  # Used for state tracking in loop
    local has_readiness=0
    # shellcheck disable=SC2034  # Used for state tracking in loop
    local in_container=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Track if we're in a container definition (for future probe-per-container checks)
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]] ]]; then
            # New container - reset probes
            # Note: Missing readinessProbe is common and not an error
            # shellcheck disable=SC2034
            in_container=1; has_liveness=0; has_readiness=0
        fi

        # Detect probes (for future per-container validation)
        # shellcheck disable=SC2034
        [[ "$line" =~ livenessProbe: ]] && has_liveness=1
        # shellcheck disable=SC2034
        [[ "$line" =~ readinessProbe: ]] && has_readiness=1

        # Check for dangerous probe configurations
        if [[ "$line" =~ initialDelaySeconds:[[:space:]]+([0-9]+) ]]; then
            local delay="${BASH_REMATCH[1]}"
            if [[ $delay -eq 0 ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: initialDelaySeconds: 0 может убить pod до старта приложения")
                warnings+=("  Рекомендация: Установите разумную задержку (например, 10-30 секунд)")
            fi
        fi

        # Check for very aggressive timeouts
        if [[ "$line" =~ timeoutSeconds:[[:space:]]+([0-9]+) ]]; then
            local timeout="${BASH_REMATCH[1]}"
            if [[ $timeout -lt 2 ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: timeoutSeconds: $timeout очень мал")
                warnings+=("  Риск: False positives при высокой нагрузке")
            fi
        fi

        # Check for very frequent probes
        if [[ "$line" =~ periodSeconds:[[:space:]]+([0-9]+) ]]; then
            local period="${BASH_REMATCH[1]}"
            if [[ $period -lt 5 ]]; then
                warnings+=("Строка $line_num: ИНФОРМАЦИЯ: periodSeconds: $period — частые проверки увеличивают нагрузку")
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_restart_policy() {
    local file="$1"
    local line_num=0
    local errors=()

    # Valid values for restartPolicy
    local valid_policies="Always|OnFailure|Never"

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        if [[ "$line" =~ restartPolicy:[[:space:]]+([^[:space:]#]+) ]]; then
            local policy="${BASH_REMATCH[1]}"
            policy="${policy//\"/}"
            policy="${policy//\'/}"

            if [[ ! "$policy" =~ ^($valid_policies)$ ]]; then
                errors+=("Строка $line_num: Некорректный restartPolicy: '$policy'")
                errors+=("  Допустимые значения: Always, OnFailure, Never")

                case "${policy,,}" in
                    always) errors+=("  Исправление: Always") ;;
                    onfailure) errors+=("  Исправление: OnFailure") ;;
                    never) errors+=("  Исправление: Never") ;;
                esac
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_service_type() {
    local file="$1"
    local line_num=0
    local errors=()

    # Valid values for Service type
    local valid_types="ClusterIP|NodePort|LoadBalancer|ExternalName"

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Only check type: in Service context (after kind: Service)
        if [[ "$line" =~ ^[[:space:]]+type:[[:space:]]+([^[:space:]#]+) ]]; then
            local svc_type="${BASH_REMATCH[1]}"
            svc_type="${svc_type//\"/}"
            svc_type="${svc_type//\'/}"

            # Skip non-Service types (like Secret type: Opaque)
            [[ "$svc_type" == "Opaque" ]] && continue
            [[ "$svc_type" =~ ^kubernetes.io/ ]] && continue
            [[ "$svc_type" =~ ^helm.sh/ ]] && continue

            if [[ ! "$svc_type" =~ ^($valid_types)$ ]]; then
                # Check for common typos
                case "${svc_type,,}" in
                    clusterip|nodeport|loadbalancer|externalname)
                        errors+=("Строка $line_num: Некорректный регистр Service type: '$svc_type'")
                        errors+=("  Допустимые значения: ClusterIP, NodePort, LoadBalancer, ExternalName")
                        ;;
                esac
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_deckhouse_crd() {
    local file="$1"
    local line_num=0
    local errors=()

    # Deckhouse CRD spec fields - COMPLETE
    # These schema definitions are for documentation and future generic validation
    # shellcheck disable=SC2034  # Schema definitions for docs and future validation

    # ModuleConfig spec fields
    declare -A moduleconfig_spec=(
        ["version"]="required|integer"
        ["enabled"]="optional|boolean"
        ["settings"]="optional|object"
    )

    # NodeGroup spec fields
    # shellcheck disable=SC2034
    declare -A nodegroup_spec=(
        ["nodeType"]="required|enum:CloudEphemeral,CloudPermanent,CloudStatic,Static"
        ["cloudInstances"]="optional|object"
        ["staticInstances"]="optional|object"
        ["cri"]="optional|object"
        ["kubelet"]="optional|object"
        ["disruptions"]="optional|object"
        ["nodeTemplate"]="optional|object"
        ["chaos"]="optional|object"
        ["operatingSystem"]="optional|object"
        ["update"]="optional|object"
    )

    # NodeGroup cloudInstances fields
    # shellcheck disable=SC2034
    declare -A cloudinstances_spec=(
        ["minPerZone"]="required|integer"
        ["maxPerZone"]="required|integer"
        ["maxUnavailablePerZone"]="optional|integer"
        ["maxSurgePerZone"]="optional|integer"
        ["classReference"]="required|object"
        ["zones"]="optional|array"
        ["standby"]="optional|integer"
        ["standbyHolder"]="optional|object"
    )

    # IngressNginxController spec fields
    # shellcheck disable=SC2034
    declare -A ingressnginx_spec=(
        ["ingressClass"]="required|string"
        ["inlet"]="required|enum:LoadBalancer,LoadBalancerWithProxyProtocol,HostPort,HostPortWithProxyProtocol,HostWithFailover"
        ["controllerVersion"]="optional|string"
        ["enableIstioSidecar"]="optional|boolean"
        ["waitLoadBalancerOnTerminating"]="optional|integer"
        ["chaosMonkey"]="optional|boolean"
        ["validationEnabled"]="optional|boolean"
        ["annotationValidationEnabled"]="optional|boolean"
        ["loadBalancer"]="optional|object"
        ["hostPort"]="optional|object"
        ["hostPortWithProxyProtocol"]="optional|object"
        ["loadBalancerWithProxyProtocol"]="optional|object"
        ["acceptRequestsFrom"]="optional|array"
        ["hsts"]="optional|boolean"
        ["hstsOptions"]="optional|object"
        ["geoIP2"]="optional|object"
        ["legacySSL"]="optional|boolean"
        ["disableHTTP2"]="optional|boolean"
        ["config"]="optional|object"
        ["additionalHeaders"]="optional|object"
        ["additionalLogFields"]="optional|object"
        ["resourcesRequests"]="optional|object"
        ["customErrors"]="optional|object"
        ["underscoresInHeaders"]="optional|boolean"
        ["minReplicas"]="optional|integer"
        ["maxReplicas"]="optional|integer"
    )

    # DexAuthenticator spec fields
    # shellcheck disable=SC2034
    declare -A dexauthenticator_spec=(
        ["applicationDomain"]="required|string"
        ["sendAuthorizationHeader"]="optional|boolean"
        ["applicationIngressCertificateSecretName"]="optional|string"
        ["applicationIngressClassName"]="optional|string"
        ["keepUsersLoggedInFor"]="optional|string"
        ["allowedGroups"]="optional|array"
        ["whitelistSourceRanges"]="optional|array"
        ["nodeSelector"]="optional|object"
        ["tolerations"]="optional|array"
    )

    # ClusterAuthorizationRule spec fields
    # shellcheck disable=SC2034
    declare -A clusterauthz_spec=(
        ["subjects"]="required|array"
        ["accessLevel"]="required|enum:User,PrivilegedUser,Editor,Admin,ClusterEditor,ClusterAdmin,SuperAdmin"
        ["portForwarding"]="optional|boolean"
        ["allowScale"]="optional|boolean"
        ["allowAccessToSystemNamespaces"]="optional|boolean"
        ["limitNamespaces"]="optional|array"
        ["additionalRoles"]="optional|array"
    )

    # User spec fields
    # shellcheck disable=SC2034
    declare -A user_spec=(
        ["email"]="required|string"
        ["password"]="optional|string"
        ["userID"]="optional|string"
        ["groups"]="optional|array"
        ["ttl"]="optional|string"
    )

    # ClusterLogDestination spec fields
    # shellcheck disable=SC2034
    declare -A logdest_spec=(
        ["type"]="required|enum:Loki,Elasticsearch,Logstash,Vector,Splunk,Kafka,Socket"
        ["loki"]="optional|object"
        ["elasticsearch"]="optional|object"
        ["logstash"]="optional|object"
        ["vector"]="optional|object"
        ["splunk"]="optional|object"
        ["kafka"]="optional|object"
        ["socket"]="optional|object"
        ["extraLabels"]="optional|object"
        ["rateLimit"]="optional|object"
        ["buffer"]="optional|object"
    )

    # VirtualMachine spec fields
    # shellcheck disable=SC2034
    declare -A virtualmachine_spec=(
        ["virtualMachineClassName"]="required|string"
        ["runPolicy"]="optional|enum:AlwaysOn,AlwaysOff,Manual,AlwaysOnUnlessStoppedGracefully"
        ["osType"]="optional|enum:Generic,Windows"
        ["bootloader"]="optional|enum:BIOS,EFI,EFIWithSecureBoot"
        ["cpu"]="required|object"
        ["memory"]="required|object"
        ["blockDeviceRefs"]="required|array"
        ["provisioning"]="optional|object"
        ["enableParavirtualization"]="optional|boolean"
        ["terminationGracePeriodSeconds"]="optional|integer"
        ["tolerations"]="optional|array"
        ["nodeSelector"]="optional|object"
        ["priorityClassName"]="optional|string"
        ["disruptions"]="optional|object"
        ["topologySpreadConstraints"]="optional|array"
        ["affinity"]="optional|object"
    )

    # PrometheusRemoteWrite spec fields
    # shellcheck disable=SC2034
    declare -A prometheusrw_spec=(
        ["url"]="required|string"
        ["basicAuth"]="optional|object"
        ["bearerToken"]="optional|string"
        ["customAuthToken"]="optional|string"
        ["tlsConfig"]="optional|object"
        ["writeRelabelConfigs"]="optional|array"
    )

    # GrafanaAlertsChannel spec fields
    # shellcheck disable=SC2034
    declare -A alertschannel_spec=(
        ["type"]="required|enum:prometheus,alertmanager"
        ["alertManager"]="optional|object"
        ["prometheus"]="optional|object"
    )

    # KeepalivedInstance spec fields
    # shellcheck disable=SC2034
    declare -A keepalived_spec=(
        ["nodeSelector"]="required|object"
        ["tolerations"]="optional|array"
        ["vrrpInstances"]="required|array"
    )

    # Parse file and validate each document separately (multi-document YAML support)
    local in_spec=0
    local current_api=""
    local current_kind=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Document separator - reset state for new document
        if [[ "$line" =~ ^---[[:space:]]*$ ]] || [[ "$line" == "---" ]]; then
            in_spec=0
            current_api=""
            current_kind=""
            continue
        fi

        # Detect apiVersion
        if [[ "$line" =~ ^apiVersion:[[:space:]]+([^[:space:]#]+) ]]; then
            current_api="${BASH_REMATCH[1]}"
        fi

        # Detect kind
        if [[ "$line" =~ ^kind:[[:space:]]+([^[:space:]#]+) ]]; then
            current_kind="${BASH_REMATCH[1]}"
        fi

        # Skip if not Deckhouse CRD
        [[ ! "$current_api" =~ ^deckhouse.io/ ]] && continue

        # Detect spec section
        if [[ "$line" =~ ^spec:[[:space:]]*$ ]] || [[ "$line" =~ ^spec:[[:space:]]*# ]]; then
            in_spec=1
            continue
        fi

        # Exit spec on dedent to top level (new section like status:, metadata:)
        if [[ $in_spec -eq 1 ]] && [[ "$line" =~ ^[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            in_spec=0
        fi

        # Validate spec fields based on kind
        if [[ $in_spec -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+([a-zA-Z][a-zA-Z0-9]*): ]]; then
            local field="${BASH_REMATCH[1]}"
            local value=""
            # Extract value, removing trailing comments
            if [[ "$line" =~ :[[:space:]]+([^#]+) ]]; then
                value="${BASH_REMATCH[1]}"
                # Trim trailing whitespace
                value="${value%"${value##*[![:space:]]}"}"
            fi

            case "$current_kind" in
                ModuleConfig)
                    # Validate version is integer
                    if [[ "$field" == "version" ]]; then
                        if [[ ! "$value" =~ ^[0-9]+$ ]]; then
                            errors+=("Строка $line_num: ModuleConfig.spec.version должен быть integer")
                            errors+=("  Найдено: $value")
                        fi
                    fi
                    # Validate enabled is boolean
                    if [[ "$field" == "enabled" ]]; then
                        if [[ ! "$value" =~ ^(true|false)$ ]]; then
                            errors+=("Строка $line_num: ModuleConfig.spec.enabled должен быть boolean")
                            errors+=("  Найдено: $value")
                            errors+=("  Допустимо: true, false")
                        fi
                    fi
                    ;;

                NodeGroup)
                    # Validate nodeType enum
                    if [[ "$field" == "nodeType" ]]; then
                        if [[ ! "$value" =~ ^(CloudEphemeral|CloudPermanent|CloudStatic|Static)$ ]]; then
                            errors+=("Строка $line_num: NodeGroup.spec.nodeType некорректный: '$value'")
                            errors+=("  Допустимо: CloudEphemeral, CloudPermanent, CloudStatic, Static")
                        fi
                    fi
                    ;;

                IngressNginxController)
                    # Validate inlet enum
                    if [[ "$field" == "inlet" ]]; then
                        local valid_inlets="LoadBalancer|LoadBalancerWithProxyProtocol|HostPort|HostPortWithProxyProtocol|HostWithFailover"
                        if [[ ! "$value" =~ ^($valid_inlets)$ ]]; then
                            errors+=("Строка $line_num: IngressNginxController.spec.inlet некорректный: '$value'")
                            errors+=("  Допустимо: LoadBalancer, HostPort, HostPortWithProxyProtocol, HostWithFailover")
                        fi
                    fi
                    ;;

                ClusterAuthorizationRule)
                    # Validate accessLevel enum
                    if [[ "$field" == "accessLevel" ]]; then
                        local valid_levels="User|PrivilegedUser|Editor|Admin|ClusterEditor|ClusterAdmin|SuperAdmin"
                        if [[ ! "$value" =~ ^($valid_levels)$ ]]; then
                            errors+=("Строка $line_num: ClusterAuthorizationRule.spec.accessLevel некорректный: '$value'")
                            errors+=("  Допустимо: User, PrivilegedUser, Editor, Admin, ClusterEditor, ClusterAdmin, SuperAdmin")
                        fi
                    fi
                    ;;

                ClusterLogDestination|PodLogDestination)
                    # Validate type enum
                    if [[ "$field" == "type" ]]; then
                        local valid_types="Loki|Elasticsearch|Logstash|Vector|Splunk|Kafka|Socket"
                        if [[ ! "$value" =~ ^($valid_types)$ ]]; then
                            errors+=("Строка $line_num: $current_kind.spec.type некорректный: '$value'")
                            errors+=("  Допустимо: Loki, Elasticsearch, Logstash, Vector, Splunk, Kafka, Socket")
                        fi
                    fi
                    ;;

                VirtualMachine)
                    # Validate runPolicy enum
                    if [[ "$field" == "runPolicy" ]]; then
                        local valid_policies="AlwaysOn|AlwaysOff|Manual|AlwaysOnUnlessStoppedGracefully"
                        if [[ ! "$value" =~ ^($valid_policies)$ ]]; then
                            errors+=("Строка $line_num: VirtualMachine.spec.runPolicy некорректный: '$value'")
                            errors+=("  Допустимо: AlwaysOn, AlwaysOff, Manual, AlwaysOnUnlessStoppedGracefully")
                        fi
                    fi
                    # Validate osType enum
                    if [[ "$field" == "osType" ]]; then
                        if [[ ! "$value" =~ ^(Generic|Windows)$ ]]; then
                            errors+=("Строка $line_num: VirtualMachine.spec.osType некорректный: '$value'")
                            errors+=("  Допустимо: Generic, Windows")
                        fi
                    fi
                    # Validate bootloader enum
                    if [[ "$field" == "bootloader" ]]; then
                        if [[ ! "$value" =~ ^(BIOS|EFI|EFIWithSecureBoot)$ ]]; then
                            errors+=("Строка $line_num: VirtualMachine.spec.bootloader некорректный: '$value'")
                            errors+=("  Допустимо: BIOS, EFI, EFIWithSecureBoot")
                        fi
                    fi
                    ;;

                GrafanaAlertsChannel)
                    # Validate type enum
                    if [[ "$field" == "type" ]]; then
                        if [[ ! "$value" =~ ^(prometheus|alertmanager)$ ]]; then
                            errors+=("Строка $line_num: GrafanaAlertsChannel.spec.type некорректный: '$value'")
                            errors+=("  Допустимо: prometheus, alertmanager")
                        fi
                    fi
                    ;;
            esac
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_kubernetes_specific() {
    local file="$1"
    local line_num=0
    local errors=()
    local has_apiversion=0
    local has_kind=0
    local has_metadata=0
    local has_metadata_name=0
    local has_spec=0
    local detected_kind=""

    # Kubernetes + Deckhouse field dictionary
    # Top-level fields (case-sensitive)
    # shellcheck disable=SC2034  # Dictionary for future validation features
    local -A k8s_top_fields=(
        ["apiVersion"]="top"
        ["kind"]="top"
        ["metadata"]="top"
        ["spec"]="top"
        ["status"]="top"
        ["data"]="top"
        ["stringData"]="top"
        ["type"]="top"
        ["subsets"]="top"
        ["roleRef"]="top"
        ["subjects"]="top"
        ["rules"]="top"
        ["webhooks"]="top"
        ["automountServiceAccountToken"]="top"
    )

    # Metadata fields
    # shellcheck disable=SC2034  # Dictionary for future validation features
    local -A k8s_metadata_fields=(
        ["name"]="metadata"
        ["namespace"]="metadata"
        ["labels"]="metadata"
        ["annotations"]="metadata"
        ["generateName"]="metadata"
        ["uid"]="metadata"
        ["resourceVersion"]="metadata"
        ["generation"]="metadata"
        ["creationTimestamp"]="metadata"
        ["deletionTimestamp"]="metadata"
        ["deletionGracePeriodSeconds"]="metadata"
        ["finalizers"]="metadata"
        ["ownerReferences"]="metadata"
        ["selfLink"]="metadata"
        ["managedFields"]="metadata"
    )

    # Spec fields (common across resources)
    # shellcheck disable=SC2034  # Dictionary for future validation features
    local -A k8s_spec_fields=(
        ["containers"]="spec"
        ["initContainers"]="spec"
        ["volumes"]="spec"
        ["restartPolicy"]="spec"
        ["terminationGracePeriodSeconds"]="spec"
        ["activeDeadlineSeconds"]="spec"
        ["dnsPolicy"]="spec"
        ["nodeSelector"]="spec"
        ["serviceAccountName"]="spec"
        ["serviceAccount"]="spec"
        ["nodeName"]="spec"
        ["hostNetwork"]="spec"
        ["hostPID"]="spec"
        ["hostIPC"]="spec"
        ["securityContext"]="spec"
        ["imagePullSecrets"]="spec"
        ["hostname"]="spec"
        ["subdomain"]="spec"
        ["affinity"]="spec"
        ["schedulerName"]="spec"
        ["tolerations"]="spec"
        ["hostAliases"]="spec"
        ["priorityClassName"]="spec"
        ["priority"]="spec"
        ["dnsConfig"]="spec"
        ["readinessGates"]="spec"
        ["runtimeClassName"]="spec"
        ["enableServiceLinks"]="spec"
        ["preemptionPolicy"]="spec"
        ["overhead"]="spec"
        ["topologySpreadConstraints"]="spec"
        ["replicas"]="spec"
        ["selector"]="spec"
        ["template"]="spec"
        ["strategy"]="spec"
        ["minReadySeconds"]="spec"
        ["revisionHistoryLimit"]="spec"
        ["progressDeadlineSeconds"]="spec"
        ["paused"]="spec"
        ["clusterIP"]="spec"
        ["clusterIPs"]="spec"
        ["externalIPs"]="spec"
        ["sessionAffinity"]="spec"
        ["loadBalancerIP"]="spec"
        ["loadBalancerSourceRanges"]="spec"
        ["externalName"]="spec"
        ["externalTrafficPolicy"]="spec"
        ["healthCheckNodePort"]="spec"
        ["publishNotReadyAddresses"]="spec"
        ["sessionAffinityConfig"]="spec"
        ["ipFamilies"]="spec"
        ["ipFamilyPolicy"]="spec"
        ["allocateLoadBalancerNodePorts"]="spec"
        ["loadBalancerClass"]="spec"
        ["internalTrafficPolicy"]="spec"
        ["ports"]="spec"
        ["accessModes"]="spec"
        ["capacity"]="spec"
        ["volumeMode"]="spec"
        ["storageClassName"]="spec"
        ["persistentVolumeReclaimPolicy"]="spec"
        ["mountOptions"]="spec"
        ["volumeBindingMode"]="spec"
        ["allowVolumeExpansion"]="spec"
        ["allowedTopologies"]="spec"
        ["rules"]="spec"
        ["backend"]="spec"
        ["tls"]="spec"
        ["ingressClassName"]="spec"
    )

    # Container fields
    # shellcheck disable=SC2034  # Dictionary for future validation features
    local -A k8s_container_fields=(
        ["name"]="container"
        ["image"]="container"
        ["command"]="container"
        ["args"]="container"
        ["workingDir"]="container"
        ["ports"]="container"
        ["env"]="container"
        ["envFrom"]="container"
        ["resources"]="container"
        ["volumeMounts"]="container"
        ["volumeDevices"]="container"
        ["livenessProbe"]="container"
        ["readinessProbe"]="container"
        ["startupProbe"]="container"
        ["lifecycle"]="container"
        ["terminationMessagePath"]="container"
        ["terminationMessagePolicy"]="container"
        ["imagePullPolicy"]="container"
        ["securityContext"]="container"
        ["stdin"]="container"
        ["stdinOnce"]="container"
        ["tty"]="container"
    )

    # Deckhouse-specific fields - COMPLETE MODULE LIST
    # shellcheck disable=SC2034  # Dictionary for future validation features
    local -A deckhouse_fields=(
        # Core modules
        ["deckhouse"]="top"
        ["global"]="top"
        ["common"]="top"
        # Networking modules
        ["cniCilium"]="deckhouse"
        ["cniFlannel"]="deckhouse"
        ["cniSimpleBridge"]="deckhouse"
        ["istio"]="deckhouse"
        ["metallb"]="deckhouse"
        ["metallbCrd"]="deckhouse"
        ["networkGateway"]="deckhouse"
        ["networkPolicyEngine"]="deckhouse"
        ["nodeLocalDns"]="deckhouse"
        ["openvpn"]="deckhouse"
        # Ingress modules
        ["ingressNginx"]="deckhouse"
        ["nginxIngress"]="deckhouse"
        # Monitoring modules
        ["extendedMonitoring"]="deckhouse"
        ["monitoringApplications"]="deckhouse"
        ["monitoringCustom"]="deckhouse"
        ["monitoringDeckhouse"]="deckhouse"
        ["monitoringKubernetes"]="deckhouse"
        ["monitoringKubernetesControlPlane"]="deckhouse"
        ["okmeter"]="deckhouse"
        ["operatorPrometheus"]="deckhouse"
        ["prometheus"]="deckhouse"
        ["prometheusMetricsAdapter"]="deckhouse"
        ["verticalPodAutoscaler"]="deckhouse"
        ["upmeter"]="deckhouse"
        # Security modules
        ["admissionPolicyEngine"]="deckhouse"
        ["operatorTrivy"]="deckhouse"
        ["runtimeAuditEngine"]="deckhouse"
        ["userAuthn"]="deckhouse"
        ["userAuthz"]="deckhouse"
        # Storage modules
        ["cephCsi"]="deckhouse"
        ["localPathProvisioner"]="deckhouse"
        ["linstor"]="deckhouse"
        ["nfsSubdirExternalProvisioner"]="deckhouse"
        ["snapshotController"]="deckhouse"
        ["sdsDrbd"]="deckhouse"
        ["sdsLocalVolume"]="deckhouse"
        ["sdsReplicatedVolume"]="deckhouse"
        ["sdsNodeConfigurator"]="deckhouse"
        # Cloud Provider modules
        ["cloudProviderAws"]="deckhouse"
        ["cloudProviderAzure"]="deckhouse"
        ["cloudProviderGcp"]="deckhouse"
        ["cloudProviderOpenstack"]="deckhouse"
        ["cloudProviderVsphere"]="deckhouse"
        ["cloudProviderYandex"]="deckhouse"
        ["cloudProviderVcd"]="deckhouse"
        ["cloudProviderZvirt"]="deckhouse"
        # Cluster Management modules
        ["nodeManager"]="deckhouse"
        ["controlPlaneManager"]="deckhouse"
        ["multitenancyManager"]="deckhouse"
        ["deckhouseController"]="deckhouse"
        ["terraformManager"]="deckhouse"
        ["staticRoutingManager"]="deckhouse"
        # Application modules
        ["certManager"]="deckhouse"
        ["dashboard"]="deckhouse"
        ["descheduler"]="deckhouse"
        ["flantIntegration"]="deckhouse"
        ["helm"]="deckhouse"
        ["keepalived"]="deckhouse"
        ["logShipper"]="deckhouse"
        ["namespaceConfigurator"]="deckhouse"
        ["podReloader"]="deckhouse"
        ["priorityClass"]="deckhouse"
        ["registrypackages"]="deckhouse"
        ["virtualization"]="deckhouse"
        # Legacy / deprecated (for backwards compat)
        ["nodeGroup"]="deckhouse"
        ["chaos"]="deckhouse"
        ["monitoring"]="deckhouse"
    )

    # Deckhouse CRD kinds
    # shellcheck disable=SC2034  # Dictionary for CRD validation
    local -A deckhouse_crds=(
        ["DeckhouseRelease"]="deckhouse.io"
        ["ModuleConfig"]="deckhouse.io"
        ["ModuleSource"]="deckhouse.io"
        ["ModuleUpdatePolicy"]="deckhouse.io"
        ["ModuleDocumentation"]="deckhouse.io"
        ["ModuleRelease"]="deckhouse.io"
        ["NodeGroup"]="deckhouse.io"
        ["NodeGroupConfiguration"]="deckhouse.io"
        ["SSHCredentials"]="deckhouse.io"
        ["StaticInstance"]="deckhouse.io"
        ["IngressNginxController"]="deckhouse.io"
        ["DexAuthenticator"]="deckhouse.io"
        ["DexProvider"]="deckhouse.io"
        ["DexClient"]="deckhouse.io"
        ["ClusterAuthorizationRule"]="deckhouse.io"
        ["User"]="deckhouse.io"
        ["Group"]="deckhouse.io"
        ["ClusterLogDestination"]="deckhouse.io"
        ["PodLogDestination"]="deckhouse.io"
        ["ClusterLoggingConfig"]="deckhouse.io"
        ["GrafanaAlertsChannel"]="deckhouse.io"
        ["CustomAlertManager"]="deckhouse.io"
        ["KeepalivedInstance"]="deckhouse.io"
        ["PrometheusRemoteWrite"]="deckhouse.io"
        ["CustomPrometheusRules"]="deckhouse.io"
        ["VirtualMachine"]="deckhouse.io"
        ["VirtualMachineIPAddressClaim"]="deckhouse.io"
        ["VirtualMachineBlockDeviceAttachment"]="deckhouse.io"
        ["VirtualDisk"]="deckhouse.io"
        ["VirtualImage"]="deckhouse.io"
        ["ClusterVirtualImage"]="deckhouse.io"
    )

    # Common typos (snake_case -> camelCase)
    local -A k8s_typos=(
        ["container_port"]="containerPort"
        ["image_pull_policy"]="imagePullPolicy"
        ["image_pull_secrets"]="imagePullSecrets"
        ["restart_policy"]="restartPolicy"
        ["service_account"]="serviceAccount"
        ["service_account_name"]="serviceAccountName"
        ["volume_mounts"]="volumeMounts"
        ["security_context"]="securityContext"
        ["host_network"]="hostNetwork"
        ["host_pid"]="hostPID"
        ["host_ipc"]="hostIPC"
        ["dns_policy"]="dnsPolicy"
        ["node_selector"]="nodeSelector"
        ["node_name"]="nodeName"
        ["working_dir"]="workingDir"
        ["target_port"]="targetPort"
        ["cluster_ip"]="clusterIP"
        ["external_ips"]="externalIPs"
        ["load_balancer_ip"]="loadBalancerIP"
        ["session_affinity"]="sessionAffinity"
    )

    # Case-sensitive field names that are commonly misspelled
    local -A k8s_case_sensitive=(
        ["apiversion"]="apiVersion"
        ["Apiversion"]="apiVersion"
        ["ApiVersion"]="apiVersion"
        ["APIVERSION"]="apiVersion"
        ["Kind"]="kind"
        ["KIND"]="kind"
        ["Metadata"]="metadata"
        ["MetaData"]="metadata"
        ["METADATA"]="metadata"
        ["Spec"]="spec"
        ["SPEC"]="spec"
        ["restartpolicy"]="restartPolicy"
        ["Restartpolicy"]="restartPolicy"
        ["RestartPolicy"]="restartPolicy"
        ["imagepullpolicy"]="imagePullPolicy"
        ["Imagepullpolicy"]="imagePullPolicy"
        ["ImagePullPolicy"]="imagePullPolicy"
        ["serviceaccountname"]="serviceAccountName"
        ["Serviceaccountname"]="serviceAccountName"
        ["ServiceAccountName"]="serviceAccountName"
        ["containerport"]="containerPort"
        ["Containerport"]="containerPort"
        ["ContainerPort"]="containerPort"
    )

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect top-level fields
        if [[ "$line" =~ ^apiVersion:[[:space:]]* ]]; then
            has_apiversion=1
        fi
        if [[ "$line" =~ ^kind:[[:space:]]*([a-zA-Z]+) ]]; then
            has_kind=1
            detected_kind="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ ^metadata:[[:space:]]*$ ]]; then
            has_metadata=1
        fi
        if [[ "$line" =~ ^[[:space:]]+name:[[:space:]]* ]] && [[ $has_metadata -eq 1 ]]; then
            has_metadata_name=1
        fi
        if [[ "$line" =~ ^spec:[[:space:]]*$ ]]; then
            has_spec=1
        fi

        # Check for case-sensitivity errors in field names
        if [[ "$line" =~ ^([[:space:]]*)([a-zA-Z_]+):[[:space:]]* ]]; then
            local field="${BASH_REMATCH[2]}"

            # Check if it's a misspelled case-sensitive field
            if [[ -n "${k8s_case_sensitive[$field]}" ]]; then
                errors+=("Строка $line_num: Неправильный регистр '$field', должно быть '${k8s_case_sensitive[$field]}'")
                errors+=("  Содержимое: $line")
            fi

            # Check for common snake_case typos
            if [[ -n "${k8s_typos[$field]}" ]]; then
                errors+=("Строка $line_num: Возможная опечатка '$field', должно быть '${k8s_typos[$field]}'")
                errors+=("  Содержимое: $line")
            fi
        fi
    done < "$file"

    # Basic field presence checks
    if [[ $has_apiversion -eq 0 ]]; then
        errors+=("ПРЕДУПРЕЖДЕНИЕ: Отсутствует поле 'apiVersion' (требуется для Kubernetes манифестов)")
    fi
    if [[ $has_kind -eq 0 ]]; then
        errors+=("ПРЕДУПРЕЖДЕНИЕ: Отсутствует поле 'kind' (требуется для Kubernetes манифестов)")
    fi
    if [[ $has_metadata -eq 0 ]] && [[ $has_kind -eq 1 ]]; then
        errors+=("ПРЕДУПРЕЖДЕНИЕ: Отсутствует секция 'metadata' (требуется для Kubernetes)")
    fi
    if [[ $has_metadata -eq 1 ]] && [[ $has_metadata_name -eq 0 ]]; then
        errors+=("ПРЕДУПРЕЖДЕНИЕ: Отсутствует 'metadata.name' (обязательное поле)")
    fi

    # Resource-specific checks
    if [[ -n "$detected_kind" ]]; then
        case "$detected_kind" in
            Pod|Deployment|StatefulSet|DaemonSet|Job|CronJob)
                if [[ $has_spec -eq 0 ]]; then
                    errors+=("ПРЕДУПРЕЖДЕНИЕ: Ресурс '$detected_kind' обычно требует секцию 'spec'")
                fi
                ;;
        esac
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

# ============================================================================
# NEW CHECKS v2.4.0 - Maximum coverage edge case validation
# ============================================================================

check_deprecated_api() {
    local file="$1"
    local line_num=0
    local warnings=()

    # Deprecated API versions database (Kubernetes 1.22+)
    declare -A deprecated_apis=(
        # Removed in 1.16
        ["extensions/v1beta1:Deployment"]="apps/v1"
        ["extensions/v1beta1:DaemonSet"]="apps/v1"
        ["extensions/v1beta1:ReplicaSet"]="apps/v1"
        ["extensions/v1beta1:StatefulSet"]="apps/v1"
        ["extensions/v1beta1:NetworkPolicy"]="networking.k8s.io/v1"
        ["extensions/v1beta1:PodSecurityPolicy"]="policy/v1beta1 (deprecated)"
        ["apps/v1beta1:Deployment"]="apps/v1"
        ["apps/v1beta2:Deployment"]="apps/v1"
        # Removed in 1.22
        ["extensions/v1beta1:Ingress"]="networking.k8s.io/v1"
        ["networking.k8s.io/v1beta1:Ingress"]="networking.k8s.io/v1"
        ["networking.k8s.io/v1beta1:IngressClass"]="networking.k8s.io/v1"
        ["rbac.authorization.k8s.io/v1beta1:ClusterRole"]="rbac.authorization.k8s.io/v1"
        ["rbac.authorization.k8s.io/v1beta1:ClusterRoleBinding"]="rbac.authorization.k8s.io/v1"
        ["rbac.authorization.k8s.io/v1beta1:Role"]="rbac.authorization.k8s.io/v1"
        ["rbac.authorization.k8s.io/v1beta1:RoleBinding"]="rbac.authorization.k8s.io/v1"
        ["admissionregistration.k8s.io/v1beta1:MutatingWebhookConfiguration"]="admissionregistration.k8s.io/v1"
        ["admissionregistration.k8s.io/v1beta1:ValidatingWebhookConfiguration"]="admissionregistration.k8s.io/v1"
        ["apiextensions.k8s.io/v1beta1:CustomResourceDefinition"]="apiextensions.k8s.io/v1"
        ["certificates.k8s.io/v1beta1:CertificateSigningRequest"]="certificates.k8s.io/v1"
        ["coordination.k8s.io/v1beta1:Lease"]="coordination.k8s.io/v1"
        ["storage.k8s.io/v1beta1:CSIDriver"]="storage.k8s.io/v1"
        ["storage.k8s.io/v1beta1:CSINode"]="storage.k8s.io/v1"
        ["storage.k8s.io/v1beta1:StorageClass"]="storage.k8s.io/v1"
        ["storage.k8s.io/v1beta1:VolumeAttachment"]="storage.k8s.io/v1"
        # Removed in 1.25
        ["batch/v1beta1:CronJob"]="batch/v1"
        ["discovery.k8s.io/v1beta1:EndpointSlice"]="discovery.k8s.io/v1"
        ["events.k8s.io/v1beta1:Event"]="events.k8s.io/v1"
        ["autoscaling/v2beta1:HorizontalPodAutoscaler"]="autoscaling/v2"
        ["policy/v1beta1:PodDisruptionBudget"]="policy/v1"
        ["policy/v1beta1:PodSecurityPolicy"]="REMOVED (use Pod Security Admission)"
        ["node.k8s.io/v1beta1:RuntimeClass"]="node.k8s.io/v1"
        # Removed in 1.26
        ["autoscaling/v2beta2:HorizontalPodAutoscaler"]="autoscaling/v2"
        ["flowcontrol.apiserver.k8s.io/v1beta1:FlowSchema"]="flowcontrol.apiserver.k8s.io/v1beta3"
        ["flowcontrol.apiserver.k8s.io/v1beta1:PriorityLevelConfiguration"]="flowcontrol.apiserver.k8s.io/v1beta3"
    )

    local current_api=""
    local current_kind=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect apiVersion
        if [[ "$line" =~ ^apiVersion:[[:space:]]+([^[:space:]#]+) ]]; then
            current_api="${BASH_REMATCH[1]}"
        fi

        # Detect kind
        if [[ "$line" =~ ^kind:[[:space:]]+([^[:space:]#]+) ]]; then
            current_kind="${BASH_REMATCH[1]}"

            # Check for deprecated combination
            local key="${current_api}:${current_kind}"
            if [[ -n "${deprecated_apis[$key]}" ]]; then
                warnings+=("Строка $line_num: УСТАРЕВШИЙ API: $current_api/$current_kind")
                warnings+=("  Рекомендация: Используйте ${deprecated_apis[$key]}")
                warnings+=("  Документация: https://kubernetes.io/docs/reference/using-api/deprecation-guide/")
            fi
        fi

        # Reset on document separator
        if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
            current_api=""
            current_kind=""
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_selector_match() {
    local file="$1"
    local errors=()

    # Kinds that require selector/template matching
    local selector_kinds="Deployment|DaemonSet|StatefulSet|ReplicaSet|Job"

    # Read file into array for multi-pass processing
    local -a lines
    mapfile -t lines < "$file"
    local total_lines=${#lines[@]}

    local detected_kind=""
    local selector_labels=""
    local template_labels=""
    local in_selector=0
    local in_template=0
    local in_template_metadata=0
    local in_template_labels=0
    local indent_selector=0
    local indent_template_labels=0

    for ((i=0; i<total_lines; i++)); do
        local line="${lines[$i]}"
        local line_num=$((i + 1))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Get current indent
        local indent=0
        if [[ "$line" =~ ^([[:space:]]*) ]]; then
            indent=${#BASH_REMATCH[1]}
        fi

        # Detect kind
        if [[ "$line" =~ ^kind:[[:space:]]+($selector_kinds) ]]; then
            detected_kind="${BASH_REMATCH[1]}"
        fi

        # Reset on document separator
        if [[ "$line" =~ ^---[[:space:]]*$ ]] || [[ "$line" == "---" ]]; then
            # Check match
            if [[ -n "$detected_kind" ]] && [[ -n "$selector_labels" ]] && [[ -n "$template_labels" ]]; then
                # Sort labels for comparison
                local sorted_selector
                local sorted_template
                sorted_selector=$(echo "$selector_labels" | tr ';' '\n' | sort | tr '\n' ';')
                sorted_template=$(echo "$template_labels" | tr ';' '\n' | sort | tr '\n' ';')

                if [[ "$sorted_selector" != "$sorted_template" ]]; then
                    errors+=("ОШИБКА: selector.matchLabels не соответствует template.metadata.labels")
                    errors+=("  selector: ${selector_labels%;}")
                    errors+=("  template: ${template_labels%;}")
                    errors+=("  Это приведёт к ошибке при применении манифеста")
                fi
            fi
            detected_kind=""
            selector_labels=""
            template_labels=""
            in_selector=0
            in_template=0
            in_template_metadata=0
            in_template_labels=0
            continue
        fi

        # Detect spec.selector.matchLabels
        if [[ "$line" =~ ^([[:space:]]*)matchLabels:[[:space:]]*$ ]]; then
            in_selector=1
            indent_selector=${#BASH_REMATCH[1]}
            continue
        fi

        # Collect selector labels
        if [[ $in_selector -eq 1 ]]; then
            if ((indent <= indent_selector)); then
                in_selector=0
            elif [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9._/-]+):[[:space:]]+([^#]+) ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                val="${val%"${val##*[![:space:]]}"}"  # trim trailing spaces
                selector_labels+="${key}=${val};"
            fi
        fi

        # Detect template section (spec.template)
        if [[ "$line" =~ ^[[:space:]]+template:[[:space:]]*$ ]]; then
            in_template=1
            in_template_metadata=0
            in_template_labels=0
            continue
        fi

        # Detect metadata under template
        if [[ $in_template -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+metadata:[[:space:]]*$ ]]; then
            in_template_metadata=1
            continue
        fi

        # Detect labels under template.metadata
        if [[ $in_template_metadata -eq 1 ]] && [[ "$line" =~ ^([[:space:]]*)labels:[[:space:]]*$ ]]; then
            in_template_labels=1
            indent_template_labels=${#BASH_REMATCH[1]}
            continue
        fi

        # Collect template labels
        if [[ $in_template_labels -eq 1 ]]; then
            if ((indent <= indent_template_labels)); then
                in_template_labels=0
                in_template_metadata=0
            elif [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9._/-]+):[[:space:]]+([^#]+) ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                val="${val%"${val##*[![:space:]]}"}"  # trim trailing spaces
                template_labels+="${key}=${val};"
            fi
        fi

        # Exit template section on major dedent
        if [[ $in_template -eq 1 ]] && ((indent <= 2)) && [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
            in_template=0
            in_template_metadata=0
            in_template_labels=0
        fi
    done

    # Final check for last document
    if [[ -n "$detected_kind" ]] && [[ -n "$selector_labels" ]] && [[ -n "$template_labels" ]]; then
        local sorted_selector
        local sorted_template
        sorted_selector=$(echo "$selector_labels" | tr ';' '\n' | sort | tr '\n' ';')
        sorted_template=$(echo "$template_labels" | tr ';' '\n' | sort | tr '\n' ';')

        if [[ "$sorted_selector" != "$sorted_template" ]]; then
            errors+=("ОШИБКА: selector.matchLabels не соответствует template.metadata.labels")
            errors+=("  selector: ${selector_labels%;}")
            errors+=("  template: ${template_labels%;}")
            errors+=("  Это приведёт к ошибке при применении манифеста")
        fi
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_env_vars() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_env=0
    local current_env_name=""
    local has_value=0
    local has_valuefrom=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Detect env section
        if [[ "$line" =~ ^[[:space:]]+env:[[:space:]]*$ ]]; then
            in_env=1
            continue
        fi

        # Exit env section on dedent
        if [[ $in_env -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{0,4}[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
            in_env=0
        fi

        if [[ $in_env -eq 1 ]]; then
            # New env var
            if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+name:[[:space:]]+([^[:space:]#]+) ]]; then
                # Check previous env var
                if [[ -n "$current_env_name" ]]; then
                    if [[ $has_value -eq 1 ]] && [[ $has_valuefrom -eq 1 ]]; then
                        errors+=("ОШИБКА: env '$current_env_name' имеет и value, и valueFrom (допустимо только одно)")
                    fi
                fi
                current_env_name="${BASH_REMATCH[1]}"
                has_value=0
                has_valuefrom=0

                # Validate env var name (must match [A-Za-z_][A-Za-z0-9_]*)
                if [[ ! "$current_env_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                    errors+=("Строка $line_num: Некорректное имя env переменной: '$current_env_name'")
                    errors+=("  Должно соответствовать: [A-Za-z_][A-Za-z0-9_]*")
                fi
            fi

            # Detect value
            if [[ "$line" =~ [[:space:]]value:[[:space:]] ]]; then
                has_value=1
            fi

            # Detect valueFrom
            if [[ "$line" =~ [[:space:]]valueFrom:[[:space:]]*$ ]]; then
                has_valuefrom=1
            fi
        fi
    done < "$file"

    # Check last env var
    if [[ -n "$current_env_name" ]] && [[ $has_value -eq 1 ]] && [[ $has_valuefrom -eq 1 ]]; then
        errors+=("ОШИБКА: env '$current_env_name' имеет и value, и valueFrom")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_dns_names() {
    local file="$1"
    local line_num=0
    local errors=()

    # RFC 1123 DNS label: lowercase, alphanumeric, hyphens, max 63 chars
    # RFC 1123 DNS subdomain: same but allows dots, max 253 chars

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check metadata.name
        if [[ "$line" =~ ^[[:space:]]+name:[[:space:]]+([^[:space:]#]+) ]]; then
            local name="${BASH_REMATCH[1]}"
            # Remove quotes if present
            name="${name#[\"\']}"
            name="${name%[\"\']}"

            # Skip if it's a variable reference
            [[ "$name" =~ ^\$ ]] && continue

            # Length check (253 for subdomain)
            if [[ ${#name} -gt 253 ]]; then
                errors+=("Строка $line_num: Имя '$name' превышает 253 символа (RFC 1123)")
            fi

            # DNS subdomain pattern check
            if [[ ! "$name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$ ]]; then
                # Check specific violations
                if [[ "$name" =~ [A-Z] ]]; then
                    errors+=("Строка $line_num: Имя '$name' содержит заглавные буквы")
                    errors+=("  RFC 1123 требует только строчные буквы")
                elif [[ "$name" =~ ^- ]] || [[ "$name" =~ -$ ]]; then
                    errors+=("Строка $line_num: Имя '$name' не может начинаться/заканчиваться дефисом")
                elif [[ "$name" =~ [^a-z0-9.-] ]]; then
                    errors+=("Строка $line_num: Имя '$name' содержит недопустимые символы")
                    errors+=("  RFC 1123: только [a-z0-9.-]")
                fi
            fi
        fi

        # Check namespace names (stricter: DNS label, max 63 chars)
        if [[ "$line" =~ ^[[:space:]]+namespace:[[:space:]]+([^[:space:]#]+) ]]; then
            local ns="${BASH_REMATCH[1]}"
            ns="${ns#[\"\']}"
            ns="${ns%[\"\']}"

            [[ "$ns" =~ ^\$ ]] && continue

            if [[ ${#ns} -gt 63 ]]; then
                errors+=("Строка $line_num: Namespace '$ns' превышает 63 символа")
            fi

            if [[ ! "$ns" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
                errors+=("Строка $line_num: Namespace '$ns' не соответствует RFC 1123 DNS label")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_null_values() {
    local file="$1"
    local warnings=()
    local -a lines
    local line_num=0
    local total_lines

    # Read all lines into array for lookahead
    mapfile -t lines < "$file"
    total_lines=${#lines[@]}

    for ((i=0; i<total_lines; i++)); do
        local line="${lines[$i]}"
        line_num=$((i + 1))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Detect explicit null representations
        if [[ "$line" =~ :[[:space:]]+(null|Null|NULL|~)[[:space:]]*$ ]]; then
            local value="${BASH_REMATCH[1]}"
            warnings+=("Строка $line_num: Явное null значение ($value)")
            warnings+=("  Содержимое: ${line}")
            warnings+=("  Убедитесь, что null допустим для этого поля")
        fi

        # Detect empty values (key: with nothing after)
        # But NOT if next line is indented or is a list item (i.e., it's a parent key)
        if [[ "$line" =~ ^([[:space:]]*)([a-zA-Z_][a-zA-Z0-9_-]*):[[:space:]]*$ ]]; then
            local current_indent="${BASH_REMATCH[1]}"
            local key="${BASH_REMATCH[2]}"
            local current_indent_len=${#current_indent}

            # Check if next non-empty, non-comment line is a child
            local has_children=0
            for ((j=i+1; j<total_lines; j++)); do
                local next_line="${lines[$j]}"
                # Skip empty lines and comments
                [[ -z "${next_line// /}" ]] && continue
                [[ "$next_line" =~ ^[[:space:]]*# ]] && continue

                # Get next line indent
                if [[ "$next_line" =~ ^([[:space:]]*) ]]; then
                    local next_indent_len=${#BASH_REMATCH[1]}
                    # Child exists if: more indented OR list item at same level
                    if ((next_indent_len > current_indent_len)); then
                        has_children=1
                    elif [[ "$next_line" =~ ^[[:space:]]*-[[:space:]] ]]; then
                        # List item at same or greater indent is also a child
                        has_children=1
                    fi
                fi
                break
            done

            # Only warn if no children (actual empty value)
            if [[ $has_children -eq 0 ]]; then
                warnings+=("Строка $line_num: Пустое значение для ключа (интерпретируется как null)")
                warnings+=("  Ключ: $key")
                warnings+=("  Рекомендация: Удалите ключ или укажите значение")
            fi
        fi
    done

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_flow_style() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and strings
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Detect flow mappings { }
        if [[ "$line" =~ \{[^\}]*$ ]] && [[ ! "$line" =~ \{[^\}]*\} ]]; then
            errors+=("Строка $line_num: Незакрытый flow mapping '{'")
            errors+=("  Содержимое: ${line}")
        fi

        # Detect flow sequences [ ]
        if [[ "$line" =~ \[[^\]]*$ ]] && [[ ! "$line" =~ \[[^\]]*\] ]]; then
            errors+=("Строка $line_num: Незакрытая flow sequence '['")
            errors+=("  Содержимое: ${line}")
        fi

        # Check for unquoted special chars in flow style
        if [[ "$line" =~ \{.*:.*[^\"\']\} ]] || [[ "$line" =~ \[.*:.*[^\"\']\] ]]; then
            # Check for unquoted colons in flow style values
            if [[ "$line" =~ \{[^\}]*:[[:space:]]+[^\"\'][^,\}]*:[^\"\'][^\}]*\} ]]; then
                errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Потенциально незакавыченное значение с ':' в flow style")
                errors+=("  Содержимое: ${line}")
            fi
        fi

        # Deep nesting warning (more than 3 levels)
        local open_braces="${line//[^\{]/}"
        local open_brackets="${line//[^\[]/}"
        if [[ ${#open_braces} -gt 3 ]] || [[ ${#open_brackets} -gt 3 ]]; then
            errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Глубокая вложенность в flow style (>3)")
            errors+=("  Рекомендация: Используйте block style для читаемости")
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_container_name() {
    local file="$1"
    local errors=()
    local -a lines
    mapfile -t lines < "$file"
    local total_lines=${#lines[@]}

    local in_containers=0
    local containers_indent=0
    local container_item_indent=-1  # The exact indent where container items start

    for ((i=0; i<total_lines; i++)); do
        local line="${lines[$i]}"
        local line_num=$((i + 1))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Get current line indent
        local indent=0
        if [[ "$line" =~ ^([[:space:]]*) ]]; then
            indent=${#BASH_REMATCH[1]}
        fi

        # Detect containers: or initContainers: section
        if [[ "$line" =~ ^([[:space:]]*)(containers|initContainers):[[:space:]]*$ ]]; then
            in_containers=1
            containers_indent=${#BASH_REMATCH[1]}
            container_item_indent=-1
            continue
        fi

        # Exit containers on dedent back to or below containers level
        if [[ $in_containers -eq 1 ]] && ((indent <= containers_indent)) && [[ ! "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            in_containers=0
            continue
        fi

        if [[ $in_containers -eq 1 ]]; then
            # Check for first container item to determine the exact indent
            if [[ "$line" =~ ^([[:space:]]*)-[[:space:]]+name:[[:space:]]+([^[:space:]#]+) ]]; then
                local item_indent=${#BASH_REMATCH[1]}

                # Set the container item indent on first container found
                if [[ $container_item_indent -eq -1 ]]; then
                    container_item_indent=$item_indent
                fi

                # Only validate if this item is at the container level indent
                # (not deeper, which would be env vars, ports, etc.)
                if [[ $item_indent -eq $container_item_indent ]]; then
                    local name="${BASH_REMATCH[2]}"
                    name="${name#[\"\']}"
                    name="${name%[\"\']}"

                    # Container name must be RFC 1123 DNS label (max 63 chars)
                    if [[ ${#name} -gt 63 ]]; then
                        errors+=("Строка $line_num: Имя контейнера '$name' превышает 63 символа")
                    fi

                    if [[ ! "$name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
                        if [[ "$name" =~ [A-Z] ]]; then
                            errors+=("Строка $line_num: Имя контейнера '$name' содержит заглавные буквы")
                        elif [[ "$name" =~ _ ]]; then
                            errors+=("Строка $line_num: Имя контейнера '$name' содержит подчёркивание (недопустимо)")
                            errors+=("  Используйте дефис вместо подчёркивания")
                        else
                            errors+=("Строка $line_num: Имя контейнера '$name' не соответствует RFC 1123")
                        fi
                    fi
                fi
            fi
        fi
    done

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_security_best_practices() {
    local file="$1"
    local line_num=0
    local warnings=()
    local has_security_context=0
    local has_run_as_non_root=0
    local has_read_only_fs=0
    local in_security_context=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Detect securityContext
        if [[ "$line" =~ securityContext:[[:space:]]*$ ]]; then
            has_security_context=1
            in_security_context=1
            continue
        fi

        if [[ $in_security_context -eq 1 ]]; then
            # runAsNonRoot check
            if [[ "$line" =~ runAsNonRoot:[[:space:]]+(true|True|TRUE) ]]; then
                has_run_as_non_root=1
            fi

            # readOnlyRootFilesystem check
            if [[ "$line" =~ readOnlyRootFilesystem:[[:space:]]+(true|True|TRUE) ]]; then
                has_read_only_fs=1
            fi

            # allowPrivilegeEscalation check
            if [[ "$line" =~ allowPrivilegeEscalation:[[:space:]]+(true|True|TRUE) ]]; then
                warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: allowPrivilegeEscalation: true")
                warnings+=("  Рекомендация: Установите allowPrivilegeEscalation: false")
            fi

            # runAsUser: 0 (root)
            if [[ "$line" =~ runAsUser:[[:space:]]+0[[:space:]]*$ ]]; then
                warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: runAsUser: 0 (контейнер запущен как root)")
                warnings+=("  Рекомендация: Используйте непривилегированного пользователя")
            fi
        fi

        # hostPID / hostIPC / hostNetwork
        if [[ "$line" =~ hostPID:[[:space:]]+(true|True|TRUE) ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: hostPID: true — доступ к процессам хоста")
        fi
        if [[ "$line" =~ hostIPC:[[:space:]]+(true|True|TRUE) ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: hostIPC: true — доступ к IPC хоста")
        fi
        if [[ "$line" =~ hostNetwork:[[:space:]]+(true|True|TRUE) ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: hostNetwork: true — доступ к сети хоста")
        fi

        # hostPath volumes
        if [[ "$line" =~ hostPath:[[:space:]]*$ ]]; then
            warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: hostPath volume — доступ к файловой системе хоста")
            warnings+=("  Риск: Потенциальный container escape")
        fi

        # Exit securityContext on dedent
        if [[ $in_security_context -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{0,6}[a-zA-Z] ]] && [[ ! "$line" =~ securityContext ]]; then
            in_security_context=0
        fi
    done < "$file"

    # Best practice recommendations (only if there are containers)
    if grep -q "containers:" "$file" 2>/dev/null; then
        if [[ $has_security_context -eq 0 ]]; then
            warnings+=("РЕКОМЕНДАЦИЯ: Отсутствует securityContext")
            warnings+=("  Добавьте securityContext с runAsNonRoot: true, readOnlyRootFilesystem: true")
        else
            if [[ $has_run_as_non_root -eq 0 ]]; then
                warnings+=("РЕКОМЕНДАЦИЯ: runAsNonRoot не установлен")
            fi
            if [[ $has_read_only_fs -eq 0 ]]; then
                warnings+=("РЕКОМЕНДАЦИЯ: readOnlyRootFilesystem не установлен")
            fi
        fi
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# === PSS BASELINE SECURITY CHECKS (v2.6.0) ===

check_pss_baseline() {
    local file="$1"
    local line_num=0
    local warnings=()
    local in_capabilities=0
    local capabilities_indent=0
    local in_add_caps=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check hostPort (PSS Baseline: should be restricted)
        if [[ "$line" =~ hostPort:[[:space:]]+([0-9]+) ]]; then
            local port="${BASH_REMATCH[1]}"
            warnings+=("Строка $line_num: PSS BASELINE: hostPort: $port — привязка к порту хоста")
            warnings+=("  Риск: Обход сетевых политик, потенциальный конфликт портов")
            warnings+=("  Рекомендация: Используйте Service NodePort/LoadBalancer")
        fi

        # Check procMount (PSS Baseline: must be Default or Unmasked)
        if [[ "$line" =~ procMount:[[:space:]]+([^[:space:]#]+) ]]; then
            local procmount="${BASH_REMATCH[1]}"
            procmount="${procmount//\"/}"
            procmount="${procmount//\'/}"
            if [[ "$procmount" != "Default" ]] && [[ "$procmount" != "Unmasked" ]]; then
                warnings+=("Строка $line_num: PSS BASELINE: procMount: $procmount")
                warnings+=("  Допустимо: Default, Unmasked")
            fi
        fi

        # Track capabilities section
        if [[ "$line" =~ ^([[:space:]]*)capabilities:[[:space:]]*$ ]]; then
            in_capabilities=1
            capabilities_indent=${#BASH_REMATCH[1]}
            continue
        fi

        # Check add capabilities
        if [[ $in_capabilities -eq 1 ]] && [[ "$line" =~ ^([[:space:]]*)add:[[:space:]]*$ ]]; then
            in_add_caps=1
            continue
        fi

        if [[ $in_add_caps -eq 1 ]]; then
            # Check for dangerous capabilities (PSS Baseline forbidden)
            local dangerous_caps="SYS_ADMIN|NET_ADMIN|SYS_PTRACE|SYS_RAWIO|SYS_MODULE|SYS_BOOT|SYS_TIME|SYS_CHROOT|MKNOD|SETUID|SETGID|CHOWN|DAC_OVERRIDE|FOWNER|FSETID|LINUX_IMMUTABLE|MAC_ADMIN|MAC_OVERRIDE|SYS_PACCT|SYS_NICE|SYS_RESOURCE|SYS_TTY_CONFIG|AUDIT_CONTROL|AUDIT_WRITE|BLOCK_SUSPEND|LEASE|NET_BIND_SERVICE|NET_BROADCAST|IPC_LOCK|IPC_OWNER|SETFCAP|SETPCAP|WAKE_ALARM"

            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([A-Z_]+) ]]; then
                local cap="${BASH_REMATCH[1]}"
                if [[ "$cap" =~ ^($dangerous_caps)$ ]]; then
                    warnings+=("Строка $line_num: PSS BASELINE: Опасная capability: $cap")
                    warnings+=("  Риск: Расширение привилегий контейнера")
                fi

                # ALL is especially dangerous
                if [[ "$cap" == "ALL" ]]; then
                    warnings+=("Строка $line_num: PSS BASELINE: capabilities.add: ALL — КРИТИЧНО!")
                    warnings+=("  Риск: Контейнер получает ВСЕ capabilities")
                    warnings+=("  Рекомендация: Укажите только необходимые capabilities")
                fi
            fi
        fi

        # Check drop capabilities (good practice to drop NET_RAW)
        if [[ $in_capabilities -eq 1 ]] && [[ "$line" =~ ^([[:space:]]*)drop:[[:space:]]*$ ]]; then
            in_add_caps=0
        fi

        # Exit capabilities section on dedent
        if [[ $in_capabilities -eq 1 ]] && [[ "$line" =~ ^([[:space:]]*)[a-zA-Z] ]]; then
            local current_indent=${#BASH_REMATCH[1]}
            if [[ $current_indent -le $capabilities_indent ]] && [[ ! "$line" =~ capabilities ]]; then
                in_capabilities=0
                in_add_caps=0
            fi
        fi

        # Check sysctls (PSS Baseline: only safe sysctls allowed)
        if [[ "$line" =~ sysctls:[[:space:]]*$ ]]; then
            # Track that sysctls are used - will check individual values
            :
        fi

        # Check for unsafe sysctls
        if [[ "$line" =~ name:[[:space:]]+([^[:space:]#]+) ]] && [[ "$line" =~ sysctl ]]; then
            local sysctl_name="${BASH_REMATCH[1]}"
            sysctl_name="${sysctl_name//\"/}"
            sysctl_name="${sysctl_name//\'/}"

            # Safe sysctls per PSS Baseline
            local safe_sysctls="kernel.shm_rmid_forced|net.ipv4.ip_local_port_range|net.ipv4.ip_unprivileged_port_start|net.ipv4.tcp_syncookies|net.ipv4.ping_group_range"

            if [[ ! "$sysctl_name" =~ ^($safe_sysctls)$ ]]; then
                warnings+=("Строка $line_num: PSS BASELINE: Небезопасный sysctl: $sysctl_name")
                warnings+=("  Допустимые: kernel.shm_rmid_forced, net.ipv4.ip_local_port_range, net.ipv4.tcp_syncookies")
            fi
        fi

        # Check AppArmor annotation (PSS Baseline)
        if [[ "$line" =~ container.apparmor.security.beta.kubernetes.io ]]; then
            if [[ "$line" =~ unconfined ]]; then
                warnings+=("Строка $line_num: PSS BASELINE: AppArmor profile: unconfined")
                warnings+=("  Риск: Контейнер без AppArmor защиты")
                warnings+=("  Рекомендация: Используйте runtime/default или custom profile")
            fi
        fi

        # Check SELinux options (PSS Baseline)
        if [[ "$line" =~ seLinuxOptions:[[:space:]]*$ ]]; then
            # seLinuxOptions allowed but type should be valid
            :
        fi
        if [[ "$line" =~ type:[[:space:]]+([^[:space:]#]+) ]] && [[ -n "$(echo "$line" | grep -i selinux)" ]]; then
            local se_type="${BASH_REMATCH[1]}"
            se_type="${se_type//\"/}"
            se_type="${se_type//\'/}"

            # Check for potentially unsafe SELinux types
            if [[ "$se_type" == "unconfined_t" ]] || [[ "$se_type" == "spc_t" ]]; then
                warnings+=("Строка $line_num: PSS BASELINE: SELinux type: $se_type")
                warnings+=("  Риск: Небезопасный SELinux контекст")
            fi
        fi

    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_pss_restricted() {
    local file="$1"
    local line_num=0
    local warnings=()
    local in_volumes=0
    local volumes_indent=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check runAsUser: 0 (PSS Restricted: must be non-zero)
        if [[ "$line" =~ runAsUser:[[:space:]]+([0-9]+) ]]; then
            local uid="${BASH_REMATCH[1]}"
            if [[ $uid -eq 0 ]]; then
                warnings+=("Строка $line_num: PSS RESTRICTED: runAsUser: 0 (root)")
                warnings+=("  Требование: Используйте непривилегированного пользователя (UID >= 1000)")
            fi
        fi

        # Check runAsGroup: 0 (PSS Restricted: should be non-zero)
        if [[ "$line" =~ runAsGroup:[[:space:]]+([0-9]+) ]]; then
            local gid="${BASH_REMATCH[1]}"
            if [[ $gid -eq 0 ]]; then
                warnings+=("Строка $line_num: PSS RESTRICTED: runAsGroup: 0 (root group)")
                warnings+=("  Рекомендация: Используйте непривилегированную группу (GID >= 1000)")
            fi
        fi

        # Check fsGroup: 0 (PSS Restricted: should be non-zero)
        if [[ "$line" =~ fsGroup:[[:space:]]+([0-9]+) ]]; then
            local fsgroup="${BASH_REMATCH[1]}"
            if [[ $fsgroup -eq 0 ]]; then
                warnings+=("Строка $line_num: PSS RESTRICTED: fsGroup: 0 (root group)")
            fi
        fi

        # Track volumes section
        if [[ "$line" =~ ^([[:space:]]*)volumes:[[:space:]]*$ ]]; then
            in_volumes=1
            volumes_indent=${#BASH_REMATCH[1]}
            continue
        fi

        # Check volume types (PSS Restricted: limited volume types)
        if [[ $in_volumes -eq 1 ]]; then
            # Allowed: configMap, csi, downwardAPI, emptyDir, ephemeral,
            # persistentVolumeClaim, projected, secret

            # Forbidden volume types
            if [[ "$line" =~ ^[[:space:]]*(hostPath|gcePersistentDisk|awsElasticBlockStore|gitRepo|nfs|iscsi|glusterfs|rbd|cephfs|cinder|fc|flocker|flexVolume|azureFile|azureDisk|vsphereVolume|quobyte|photonPersistentDisk|portworxVolume|scaleIO|storageos):[[:space:]]* ]]; then
                local vol_type="${BASH_REMATCH[1]}"
                warnings+=("Строка $line_num: PSS RESTRICTED: Запрещённый тип volume: $vol_type")
                warnings+=("  Допустимо: configMap, csi, downwardAPI, emptyDir, ephemeral, persistentVolumeClaim, projected, secret")
            fi

            # Exit volumes section on dedent
            if [[ "$line" =~ ^([[:space:]]*)[a-zA-Z] ]]; then
                local current_indent=${#BASH_REMATCH[1]}
                if [[ $current_indent -le $volumes_indent ]] && [[ ! "$line" =~ volumes ]]; then
                    in_volumes=0
                fi
            fi
        fi

        # Check seccompProfile (PSS Restricted: required)
        # Note: In PSS Restricted, seccomp profile must be set to RuntimeDefault or Localhost
        if [[ "$line" =~ seccompProfile:[[:space:]]*$ ]]; then
            # Found seccompProfile, check type on next relevant line
            :
        fi

        if [[ "$line" =~ type:[[:space:]]+Unconfined ]] && grep -q "seccompProfile" "$file" 2>/dev/null; then
            # Only warn if this is in seccompProfile context
            warnings+=("Строка $line_num: PSS RESTRICTED: seccompProfile type: Unconfined")
            warnings+=("  Требование: Используйте RuntimeDefault или Localhost")
        fi

    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_sensitive_mounts() {
    local file="$1"
    local line_num=0
    local warnings=()
    local in_hostpath=0
    local hostpath_line=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Track hostPath volume
        if [[ "$line" =~ hostPath:[[:space:]]*$ ]]; then
            in_hostpath=1
            hostpath_line=$line_num
            continue
        fi

        if [[ $in_hostpath -eq 1 ]]; then
            if [[ "$line" =~ path:[[:space:]]+([^[:space:]#]+) ]]; then
                local mount_path="${BASH_REMATCH[1]}"
                mount_path="${mount_path//\"/}"
                mount_path="${mount_path//\'/}"

                # Check docker.sock
                if [[ "$mount_path" == "/var/run/docker.sock" ]] || \
                   [[ "$mount_path" == "/run/docker.sock" ]] || \
                   [[ "$mount_path" =~ docker\.sock$ ]]; then
                    warnings+=("Строка $hostpath_line: КРИТИЧНО: Монтирование Docker socket: $mount_path")
                    warnings+=("  Риск: Полный контроль над Docker daemon → container escape")
                    warnings+=("  Рекомендация: Никогда не монтируйте docker.sock в контейнеры")
                fi

                # Check containerd socket
                if [[ "$mount_path" == "/run/containerd/containerd.sock" ]] || \
                   [[ "$mount_path" =~ containerd\.sock$ ]]; then
                    warnings+=("Строка $hostpath_line: КРИТИЧНО: Монтирование containerd socket: $mount_path")
                    warnings+=("  Риск: Полный контроль над container runtime")
                fi

                # Check CRI-O socket
                if [[ "$mount_path" == "/var/run/crio/crio.sock" ]] || \
                   [[ "$mount_path" =~ crio\.sock$ ]]; then
                    warnings+=("Строка $hostpath_line: КРИТИЧНО: Монтирование CRI-O socket: $mount_path")
                fi

                # Check sensitive host paths
                if [[ "$mount_path" == "/" ]]; then
                    warnings+=("Строка $hostpath_line: КРИТИЧНО: Монтирование root filesystem: /")
                    warnings+=("  Риск: Полный доступ к файловой системе хоста")
                fi

                if [[ "$mount_path" == "/etc" ]] || [[ "$mount_path" =~ ^/etc/ ]]; then
                    warnings+=("Строка $hostpath_line: ОПАСНО: Монтирование /etc: $mount_path")
                    warnings+=("  Риск: Доступ к конфигурации хоста, /etc/shadow, /etc/passwd")
                fi

                if [[ "$mount_path" == "/root" ]] || [[ "$mount_path" =~ ^/root/ ]]; then
                    warnings+=("Строка $hostpath_line: ОПАСНО: Монтирование /root: $mount_path")
                    warnings+=("  Риск: Доступ к домашней директории root")
                fi

                if [[ "$mount_path" == "/var/log" ]] || [[ "$mount_path" =~ ^/var/log/ ]]; then
                    warnings+=("Строка $hostpath_line: ПРЕДУПРЕЖДЕНИЕ: Монтирование /var/log: $mount_path")
                    warnings+=("  Риск: Доступ к логам хоста, возможная утечка данных")
                fi

                if [[ "$mount_path" == "/proc" ]] || [[ "$mount_path" =~ ^/proc/ ]]; then
                    warnings+=("Строка $hostpath_line: КРИТИЧНО: Монтирование /proc: $mount_path")
                    warnings+=("  Риск: Доступ к информации о процессах хоста")
                fi

                if [[ "$mount_path" == "/sys" ]] || [[ "$mount_path" =~ ^/sys/ ]]; then
                    warnings+=("Строка $hostpath_line: ОПАСНО: Монтирование /sys: $mount_path")
                    warnings+=("  Риск: Доступ к системной информации и параметрам ядра")
                fi

                if [[ "$mount_path" == "/dev" ]] || [[ "$mount_path" =~ ^/dev/ ]]; then
                    warnings+=("Строка $hostpath_line: ОПАСНО: Монтирование /dev: $mount_path")
                    warnings+=("  Риск: Доступ к устройствам хоста")
                fi

                # Check kubelet paths
                if [[ "$mount_path" =~ ^/var/lib/kubelet ]]; then
                    warnings+=("Строка $hostpath_line: ОПАСНО: Монтирование kubelet directory: $mount_path")
                    warnings+=("  Риск: Доступ к данным kubelet, включая секреты")
                fi

                # Check etcd paths
                if [[ "$mount_path" =~ ^/var/lib/etcd ]]; then
                    warnings+=("Строка $hostpath_line: КРИТИЧНО: Монтирование etcd directory: $mount_path")
                    warnings+=("  Риск: Доступ к данным etcd кластера")
                fi

                in_hostpath=0
            fi
        fi

        # Check for mountPath pointing to sensitive locations
        if [[ "$line" =~ mountPath:[[:space:]]+([^[:space:]#]+) ]]; then
            local mount_path="${BASH_REMATCH[1]}"
            mount_path="${mount_path//\"/}"
            mount_path="${mount_path//\'/}"

            # Check if mounting to sensitive container paths
            if [[ "$mount_path" == "/etc/kubernetes" ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: mountPath к /etc/kubernetes")
                warnings+=("  Проверьте, что это необходимо")
            fi
        fi

    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# D20: Check for writable hostPath mounts (readOnly not set or false)
check_writable_hostpath() {
    local file="$1"
    local line_num=0
    local warnings=()
    local in_volumemount=0
    local mount_name=""
    local mount_line=0
    local has_readonly=0
    local readonly_false=0

    # First pass: find volumeMounts with hostPath volumes that are not readOnly
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Track volumeMount blocks
        if [[ "$line" =~ volumeMounts:[[:space:]]*$ ]]; then
            in_volumemount=1
            continue
        fi

        if [[ $in_volumemount -eq 1 ]]; then
            # New mount item
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]+([^[:space:]#]+) ]]; then
                # Check previous mount
                if [[ -n "$mount_name" && $has_readonly -eq 0 ]]; then
                    warnings+=("[SECURITY] Строка $mount_line: volumeMount '$mount_name' без readOnly: true")
                    warnings+=("  Рекомендация: Добавьте readOnly: true для безопасности")
                elif [[ -n "$mount_name" && $readonly_false -eq 1 ]]; then
                    warnings+=("[SECURITY] Строка $mount_line: volumeMount '$mount_name' имеет readOnly: false")
                    warnings+=("  Риск: Запись в hostPath volume может повредить хост")
                fi

                mount_name="${BASH_REMATCH[1]}"
                mount_line=$line_num
                has_readonly=0
                readonly_false=0
                continue
            fi

            # Check for readOnly field
            if [[ "$line" =~ readOnly:[[:space:]]+(true|True|TRUE) ]]; then
                has_readonly=1
            elif [[ "$line" =~ readOnly:[[:space:]]+(false|False|FALSE) ]]; then
                has_readonly=1
                readonly_false=1
            fi

            # Exit volumeMounts on unindent
            if [[ "$line" =~ ^[[:space:]]{0,3}[^[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                # Check last mount
                if [[ -n "$mount_name" && $has_readonly -eq 0 ]]; then
                    warnings+=("[SECURITY] Строка $mount_line: volumeMount '$mount_name' без readOnly: true")
                    warnings+=("  Рекомендация: Добавьте readOnly: true для безопасности")
                elif [[ -n "$mount_name" && $readonly_false -eq 1 ]]; then
                    warnings+=("[SECURITY] Строка $mount_line: volumeMount '$mount_name' имеет readOnly: false")
                fi
                in_volumemount=0
                mount_name=""
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# D23: Check that NET_RAW capability is dropped
check_drop_net_raw() {
    local file="$1"
    local line_num=0
    local warnings=()
    local in_capabilities=0
    local in_drop=0
    local has_drop_all=0
    local has_drop_net_raw=0
    local container_line=0
    local container_name=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Track container start
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]+([^[:space:]#]+) ]]; then
            # Check previous container
            if [[ -n "$container_name" && $has_drop_all -eq 0 && $has_drop_net_raw -eq 0 ]]; then
                # Only warn if this is a container (not initContainer check for simplicity)
                warnings+=("[SECURITY] Контейнер '$container_name': NET_RAW capability не удалена")
                warnings+=("  Строка $container_line: Рекомендация: Добавьте capabilities.drop: [NET_RAW] или [ALL]")
                warnings+=("  Риск: NET_RAW позволяет создавать raw sockets (сетевые атаки)")
            fi
            container_name="${BASH_REMATCH[1]}"
            container_line=$line_num
            has_drop_all=0
            has_drop_net_raw=0
            in_capabilities=0
            in_drop=0
            continue
        fi

        # Track capabilities block
        if [[ "$line" =~ capabilities:[[:space:]]*$ ]]; then
            in_capabilities=1
            continue
        fi

        if [[ $in_capabilities -eq 1 ]]; then
            # Track drop section
            if [[ "$line" =~ drop:[[:space:]]*$ ]]; then
                in_drop=1
                continue
            fi

            # Check dropped capabilities
            if [[ $in_drop -eq 1 ]]; then
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(ALL|all) ]]; then
                    has_drop_all=1
                fi
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(NET_RAW|net_raw) ]]; then
                    has_drop_net_raw=1
                fi
                # Inline array format: drop: [ALL] or drop: [NET_RAW, ...]
                if [[ "$line" =~ drop:[[:space:]]*\[.*ALL.*\] ]]; then
                    has_drop_all=1
                fi
                if [[ "$line" =~ drop:[[:space:]]*\[.*NET_RAW.*\] ]]; then
                    has_drop_net_raw=1
                fi
            fi

            # Exit capabilities on unindent to add:
            if [[ "$line" =~ add: ]]; then
                in_drop=0
            fi
        fi

        # Exit capabilities block on securityContext end
        if [[ "$line" =~ ^[[:space:]]{4}[a-zA-Z] ]] && [[ $in_capabilities -eq 1 ]] && [[ ! "$line" =~ capabilities ]]; then
            in_capabilities=0
            in_drop=0
        fi
    done < "$file"

    # Check last container
    if [[ -n "$container_name" && $has_drop_all -eq 0 && $has_drop_net_raw -eq 0 ]]; then
        warnings+=("[SECURITY] Контейнер '$container_name': NET_RAW capability не удалена")
        warnings+=("  Строка $container_line: Рекомендация: Добавьте capabilities.drop: [NET_RAW] или [ALL]")
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_privileged_ports() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check containerPort for privileged ports
        if [[ "$line" =~ containerPort:[[:space:]]+([0-9]+) ]]; then
            local port="${BASH_REMATCH[1]}"

            # Check SSH port
            if [[ $port -eq 22 ]]; then
                warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: containerPort: 22 (SSH)")
                warnings+=("  Вопрос: Зачем SSH в контейнере? Используйте kubectl exec")
            fi

            # Check privileged ports (< 1024)
            if [[ $port -lt 1024 ]] && [[ $port -ne 80 ]] && [[ $port -ne 443 ]]; then
                warnings+=("Строка $line_num: ИНФОРМАЦИЯ: Privileged port $port (< 1024)")
                warnings+=("  Примечание: Требует NET_BIND_SERVICE capability или root")
            fi

            # Common dangerous ports
            case $port in
                23)
                    warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: Port 23 (Telnet) — небезопасный протокол")
                    ;;
                2375|2376)
                    warnings+=("Строка $line_num: КРИТИЧНО: Port $port (Docker API)")
                    warnings+=("  Риск: Прямой доступ к Docker daemon")
                    ;;
                6443)
                    warnings+=("Строка $line_num: ИНФОРМАЦИЯ: Port 6443 (Kubernetes API)")
                    ;;
                10250)
                    warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Port 10250 (Kubelet API)")
                    warnings+=("  Риск: При неправильной настройке — доступ к kubelet")
                    ;;
                2379|2380)
                    warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Port $port (etcd)")
                    warnings+=("  Риск: Прямой доступ к etcd")
                    ;;
            esac
        fi

        # Check hostPort
        if [[ "$line" =~ hostPort:[[:space:]]+([0-9]+) ]]; then
            local port="${BASH_REMATCH[1]}"
            if [[ $port -lt 1024 ]]; then
                warnings+=("Строка $line_num: БЕЗОПАСНОСТЬ: hostPort: $port (privileged < 1024)")
            fi
        fi

    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_rbac_security() {
    local file="$1"
    local line_num=0
    local warnings=()
    local detected_kind=""
    local in_rules=0
    local in_rule=0
    local current_verbs=""
    local current_resources=""
    local rule_line=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Detect RBAC kinds
        if [[ "$line" =~ ^kind:[[:space:]]+(ClusterRole|Role|ClusterRoleBinding|RoleBinding) ]]; then
            detected_kind="${BASH_REMATCH[1]}"
        fi

        # Reset on document separator
        if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
            detected_kind=""
            in_rules=0
            in_rule=0
        fi

        # Check for binding to cluster-admin
        if [[ "$detected_kind" =~ RoleBinding ]] && [[ "$line" =~ name:[[:space:]]+cluster-admin ]]; then
            warnings+=("Строка $line_num: КРИТИЧНО: Привязка к cluster-admin")
            warnings+=("  Риск: Полные права администратора кластера")
            warnings+=("  Рекомендация: Используйте минимально необходимые права")
        fi

        # Check for default service account usage
        if [[ "$detected_kind" =~ RoleBinding ]]; then
            if [[ "$line" =~ name:[[:space:]]+default[[:space:]]*$ ]] || \
               [[ "$line" =~ name:[[:space:]]+\"default\" ]] || \
               [[ "$line" =~ name:[[:space:]]+\'default\' ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Использование default ServiceAccount")
                warnings+=("  Рекомендация: Создайте отдельный ServiceAccount для приложения")
            fi
        fi

        # Track rules section
        if [[ "$detected_kind" =~ ^(Cluster)?Role$ ]]; then
            if [[ "$line" =~ ^([[:space:]]*)rules:[[:space:]]*$ ]]; then
                in_rules=1
                continue
            fi

            if [[ $in_rules -eq 1 ]]; then
                # New rule starts with -
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]* ]]; then
                    # Check previous rule if we had one
                    if [[ $in_rule -eq 1 ]] && [[ "$current_verbs" == *"*"* ]] && [[ "$current_resources" == *"*"* ]]; then
                        warnings+=("Строка $rule_line: КРИТИЧНО: Wildcard в verbs И resources")
                        warnings+=("  Правило: resources: *, verbs: * — эквивалент cluster-admin")
                    fi

                    in_rule=1
                    rule_line=$line_num
                    current_verbs=""
                    current_resources=""
                fi

                # Capture verbs
                if [[ "$line" =~ verbs:[[:space:]]*\[([^\]]*)\] ]]; then
                    current_verbs="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ verbs:[[:space:]]*$ ]]; then
                    # Multi-line verbs, will be captured below
                    :
                fi

                # Capture resources
                if [[ "$line" =~ resources:[[:space:]]*\[([^\]]*)\] ]]; then
                    current_resources="${BASH_REMATCH[1]}"
                fi

                # Check for wildcards in arrays
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*[\"\']?\*[\"\']?[[:space:]]*$ ]]; then
                    if [[ -n "$current_resources" ]] || [[ "$current_resources" == *"*"* ]]; then
                        # This is likely in verbs array
                        current_verbs="*"
                    fi
                fi

                # Direct wildcard checks
                if [[ "$line" =~ resources:[[:space:]]*\[.*\*.*\] ]]; then
                    warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Wildcard в resources")
                    warnings+=("  Рекомендация: Укажите конкретные ресурсы")
                fi

                if [[ "$line" =~ verbs:[[:space:]]*\[.*\*.*\] ]]; then
                    warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Wildcard в verbs")
                    warnings+=("  Рекомендация: Укажите конкретные действия (get, list, watch, etc.)")
                fi

                # Check for secrets access
                if [[ "$line" =~ resources:.*secrets ]]; then
                    warnings+=("Строка $line_num: ИНФОРМАЦИЯ: Доступ к secrets")
                    warnings+=("  Убедитесь, что это необходимо")
                fi
            fi
        fi

    done < "$file"

    # Check last rule
    if [[ $in_rule -eq 1 ]] && [[ "$current_verbs" == *"*"* ]] && [[ "$current_resources" == *"*"* ]]; then
        warnings+=("Строка $rule_line: КРИТИЧНО: Wildcard в verbs И resources")
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_secrets_in_env() {
    local file="$1"
    local line_num=0
    local warnings=()
    local in_env=0
    local env_indent=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Track env section
        if [[ "$line" =~ ^([[:space:]]*)env:[[:space:]]*$ ]]; then
            in_env=1
            env_indent=${#BASH_REMATCH[1]}
            continue
        fi

        if [[ $in_env -eq 1 ]]; then
            # Check for value: with sensitive keywords
            if [[ "$line" =~ value:[[:space:]]+([^[:space:]#]+) ]]; then
                local env_value="${BASH_REMATCH[1]}"
                env_value="${env_value//\"/}"
                env_value="${env_value//\'/}"

                # Check if previous line was a sensitive env name
                # This is a simple check, could be enhanced
                :
            fi

            # Check for hardcoded secrets patterns
            if [[ "$line" =~ name:[[:space:]]+(.*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd].*|.*[Ss][Ee][Cc][Rr][Ee][Tt].*|.*[Tt][Oo][Kk][Ee][Nn].*|.*[Aa][Pp][Ii][_-]?[Kk][Ee][Yy].*|.*[Pp][Rr][Ii][Vv][Aa][Tt][Ee][_-]?[Kk][Ee][Yy].*) ]]; then
                local env_name="${BASH_REMATCH[1]}"
                env_name="${env_name//\"/}"
                env_name="${env_name//\'/}"

                # Look ahead for value: (not valueFrom:)
                # This is simplified - would need more context tracking for accuracy
                warnings+=("Строка $line_num: ПРОВЕРЬТЕ: Env var '$env_name' может содержать секрет")
                warnings+=("  Рекомендация: Используйте valueFrom.secretKeyRef вместо value")
            fi

            # Exit env section on dedent
            if [[ "$line" =~ ^([[:space:]]*)[a-zA-Z] ]]; then
                local current_indent=${#BASH_REMATCH[1]}
                if [[ $current_indent -le $env_indent ]] && [[ ! "$line" =~ ^[[:space:]]*env: ]]; then
                    in_env=0
                fi
            fi
        fi

        # Check for hardcoded credentials in any value
        if [[ "$line" =~ value:[[:space:]]+(.*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd].*=|.*[Tt][Oo][Kk][Ee][Nn].*=) ]]; then
            warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Возможный hardcoded credential в value")
        fi

    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_default_service_account() {
    local file="$1"
    local warnings=()
    local has_service_account=0
    local has_automount_false=0
    local line_num=0
    local detected_kind=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Detect workload kinds
        if [[ "$line" =~ ^kind:[[:space:]]+(Deployment|StatefulSet|DaemonSet|Job|CronJob|Pod) ]]; then
            detected_kind="${BASH_REMATCH[1]}"
        fi

        # Reset on document separator
        if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
            # Check previous document
            if [[ -n "$detected_kind" ]] && [[ $has_service_account -eq 0 ]] && [[ $has_automount_false -eq 0 ]]; then
                # Only warn if it's a workload that might need service account check
                :
            fi
            detected_kind=""
            has_service_account=0
            has_automount_false=0
        fi

        # Check for serviceAccountName
        if [[ "$line" =~ serviceAccountName:[[:space:]]+([^[:space:]#]+) ]]; then
            local sa_name="${BASH_REMATCH[1]}"
            sa_name="${sa_name//\"/}"
            sa_name="${sa_name//\'/}"

            has_service_account=1

            if [[ "$sa_name" == "default" ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: serviceAccountName: default")
                warnings+=("  Рекомендация: Создайте отдельный ServiceAccount с минимальными правами")
            fi
        fi

        # Check for automountServiceAccountToken: false
        if [[ "$line" =~ automountServiceAccountToken:[[:space:]]+(false|False|FALSE) ]]; then
            has_automount_false=1
        fi

    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_resource_format() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # CPU format validation
        if [[ "$line" =~ cpu:[[:space:]]+([^[:space:]#]+) ]]; then
            local cpu="${BASH_REMATCH[1]}"
            cpu="${cpu#[\"\']}"
            cpu="${cpu%[\"\']}"

            # Valid formats: integer, decimal (0.5), millicore (100m, 500m)
            if [[ ! "$cpu" =~ ^[0-9]+$ ]] && \
               [[ ! "$cpu" =~ ^[0-9]+\.[0-9]+$ ]] && \
               [[ ! "$cpu" =~ ^[0-9]+m$ ]]; then
                errors+=("Строка $line_num: Некорректный формат CPU: '$cpu'")
                errors+=("  Допустимо: 1, 0.5, 100m, 500m, 2000m")
            fi

            # Warning for very high CPU
            if [[ "$cpu" =~ ^([0-9]+)$ ]] && [[ ${BASH_REMATCH[1]} -gt 64 ]]; then
                errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: CPU $cpu очень высокий (>64 cores)")
            fi
        fi

        # Memory format validation
        if [[ "$line" =~ memory:[[:space:]]+([^[:space:]#]+) ]]; then
            local mem="${BASH_REMATCH[1]}"
            mem="${mem#[\"\']}"
            mem="${mem%[\"\']}"

            # Valid formats: bytes, Ki/Mi/Gi/Ti, K/M/G/T
            if [[ ! "$mem" =~ ^[0-9]+$ ]] && \
               [[ ! "$mem" =~ ^[0-9]+(Ki|Mi|Gi|Ti|Pi|Ei)$ ]] && \
               [[ ! "$mem" =~ ^[0-9]+(K|M|G|T|P|E)$ ]] && \
               [[ ! "$mem" =~ ^[0-9]+e[0-9]+$ ]]; then
                errors+=("Строка $line_num: Некорректный формат memory: '$mem'")
                errors+=("  Допустимо: 128Mi, 1Gi, 512M, 1G")
            fi

            # Warning for lowercase m (millibytes - almost certainly wrong)
            if [[ "$mem" =~ ^[0-9]+m$ ]]; then
                errors+=("Строка $line_num: ОШИБКА: memory '$mem' использует 'm' (миллибайты)")
                errors+=("  Вероятно имелось в виду: ${mem%m}Mi (мебибайты)")
            fi

            # Warning for very high memory
            if [[ "$mem" =~ ^([0-9]+)Gi$ ]] && [[ ${BASH_REMATCH[1]} -gt 256 ]]; then
                errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Memory ${mem} очень высокий (>256Gi)")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_service_selector() {
    local file="$1"
    local line_num=0
    local errors=()
    local detected_kind=""
    local in_selector=0
    local selector_indent=0
    local has_selector=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect Service kind
        if [[ "$line" =~ ^kind:[[:space:]]+Service ]]; then
            detected_kind="Service"
        fi

        # Reset on document separator
        if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
            if [[ "$detected_kind" == "Service" ]] && [[ $has_selector -eq 0 ]]; then
                errors+=("ПРЕДУПРЕЖДЕНИЕ: Service без selector (headless service или ошибка?)")
            fi
            detected_kind=""
            has_selector=0
            in_selector=0
        fi

        # Detect selector in Service
        if [[ "$detected_kind" == "Service" ]]; then
            if [[ "$line" =~ ^([[:space:]]*)selector:[[:space:]]*$ ]]; then
                in_selector=1
                selector_indent=${#BASH_REMATCH[1]}
                has_selector=1
                continue
            fi

            # Check for empty selector
            if [[ $in_selector -eq 1 ]]; then
                local current_indent
                if [[ "$line" =~ ^([[:space:]]*)[a-zA-Z] ]]; then
                    current_indent=${#BASH_REMATCH[1]}
                    if [[ $current_indent -le $selector_indent ]]; then
                        in_selector=0
                    fi
                fi
            fi
        fi
    done < "$file"

    # Final check
    if [[ "$detected_kind" == "Service" ]] && [[ $has_selector -eq 0 ]]; then
        errors+=("ПРЕДУПРЕЖДЕНИЕ: Service без selector")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
    fi
    return 0
}

check_volume_mounts() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_volume_mounts=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect volumeMounts section
        if [[ "$line" =~ volumeMounts:[[:space:]]*$ ]]; then
            in_volume_mounts=1
            continue
        fi

        if [[ $in_volume_mounts -eq 1 ]]; then
            # Check mountPath
            if [[ "$line" =~ mountPath:[[:space:]]+([^[:space:]#]+) ]]; then
                local path="${BASH_REMATCH[1]}"
                path="${path#[\"\']}"
                path="${path%[\"\']}"

                # Dangerous mount paths
                if [[ "$path" == "/" ]]; then
                    errors+=("Строка $line_num: БЕЗОПАСНОСТЬ: mountPath: / — монтирование в корень")
                fi
                if [[ "$path" == "/etc" ]] || [[ "$path" =~ ^/etc/ ]]; then
                    errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: mountPath в /etc")
                fi
                if [[ "$path" == "/var/run/docker.sock" ]]; then
                    errors+=("Строка $line_num: БЕЗОПАСНОСТЬ: Docker socket mounted — container escape risk")
                fi
                if [[ "$path" =~ /proc ]] || [[ "$path" =~ /sys ]]; then
                    errors+=("Строка $line_num: БЕЗОПАСНОСТЬ: mountPath в системную директорию ($path)")
                fi

                # Relative path
                if [[ ! "$path" =~ ^/ ]]; then
                    errors+=("Строка $line_num: mountPath '$path' должен быть абсолютным путём")
                fi
            fi

            # subPath injection check (CVE-2023-3676)
            if [[ "$line" =~ subPath:[[:space:]]+([^[:space:]#]+) ]]; then
                local subpath="${BASH_REMATCH[1]}"
                if [[ "$subpath" =~ \.\. ]] || [[ "$subpath" =~ [\`\$\;] ]]; then
                    errors+=("Строка $line_num: БЕЗОПАСНОСТЬ: Подозрительный subPath: '$subpath'")
                    errors+=("  Возможная уязвимость: CVE-2023-3676 command injection")
                fi
            fi

            # Exit volumeMounts on dedent
            if [[ "$line" =~ ^[[:space:]]{0,6}[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
                in_volume_mounts=0
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_configmap_keys() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_data=0
    local detected_kind=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect ConfigMap/Secret kind
        if [[ "$line" =~ ^kind:[[:space:]]+(ConfigMap|Secret) ]]; then
            detected_kind="${BASH_REMATCH[1]}"
        fi

        # Detect data section
        if [[ "$line" =~ ^data:[[:space:]]*$ ]] || [[ "$line" =~ ^stringData:[[:space:]]*$ ]]; then
            in_data=1
            continue
        fi

        # Reset on new document
        if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
            detected_kind=""
            in_data=0
        fi

        # Validate keys in ConfigMap/Secret data
        if [[ $in_data -eq 1 ]] && [[ -n "$detected_kind" ]]; then
            if [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9._-]+):[[:space:]] ]]; then
                local key="${BASH_REMATCH[1]}"

                # Key must be valid DNS subdomain (RFC 1123) or path segment
                # Max 253 chars, alphanumeric, -, _, .
                if [[ ${#key} -gt 253 ]]; then
                    errors+=("Строка $line_num: $detected_kind ключ '$key' превышает 253 символа")
                fi

                # Check for potentially problematic keys
                if [[ "$key" =~ ^[0-9] ]]; then
                    errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: $detected_kind ключ '$key' начинается с цифры")
                fi

                if [[ "$key" =~ [[:space:]] ]]; then
                    errors+=("Строка $line_num: $detected_kind ключ '$key' содержит пробелы")
                fi
            fi

            # Exit data on dedent
            if [[ "$line" =~ ^[a-zA-Z] ]]; then
                in_data=0
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_ingress_rules() {
    local file="$1"
    local line_num=0
    local errors=()
    local detected_kind=""
    local detected_api=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect apiVersion
        if [[ "$line" =~ ^apiVersion:[[:space:]]+([^[:space:]#]+) ]]; then
            detected_api="${BASH_REMATCH[1]}"
        fi

        # Detect Ingress kind
        if [[ "$line" =~ ^kind:[[:space:]]+Ingress ]]; then
            detected_kind="Ingress"
        fi

        # Reset on document separator
        if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
            detected_kind=""
            detected_api=""
        fi

        if [[ "$detected_kind" == "Ingress" ]]; then
            # Check for deprecated API (already handled but reinforce)
            if [[ "$detected_api" == "extensions/v1beta1" ]] || [[ "$detected_api" == "networking.k8s.io/v1beta1" ]]; then
                # Already handled in check_deprecated_api
                :
            fi

            # Check for missing ingressClassName (required in v1)
            if [[ "$detected_api" == "networking.k8s.io/v1" ]]; then
                if [[ "$line" =~ ^spec:[[:space:]]*$ ]]; then
                    # Should have ingressClassName
                    :
                fi
            fi

            # Validate host format
            if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+host:[[:space:]]+([^[:space:]#]+) ]]; then
                local host="${BASH_REMATCH[1]}"
                host="${host#[\"\']}"
                host="${host%[\"\']}"

                # Basic hostname validation
                if [[ ! "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] && [[ "$host" != "*" ]]; then
                    errors+=("Строка $line_num: Некорректный hostname в Ingress: '$host'")
                fi
            fi

            # Check path type (required in v1)
            if [[ "$line" =~ pathType:[[:space:]]+([^[:space:]#]+) ]]; then
                local pathtype="${BASH_REMATCH[1]}"
                if [[ ! "$pathtype" =~ ^(Prefix|Exact|ImplementationSpecific)$ ]]; then
                    errors+=("Строка $line_num: Некорректный pathType: '$pathtype'")
                    errors+=("  Допустимо: Prefix, Exact, ImplementationSpecific")
                fi
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_hpa_config() {
    local file="$1"
    local line_num=0
    local errors=()
    local detected_kind=""
    local min_replicas=0
    local max_replicas=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect HPA kind
        if [[ "$line" =~ ^kind:[[:space:]]+HorizontalPodAutoscaler ]]; then
            detected_kind="HPA"
        fi

        # Reset on document separator
        if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
            # Validate HPA config
            if [[ "$detected_kind" == "HPA" ]]; then
                if [[ $min_replicas -gt $max_replicas ]] && [[ $max_replicas -gt 0 ]]; then
                    errors+=("ОШИБКА: HPA minReplicas ($min_replicas) > maxReplicas ($max_replicas)")
                fi
                if [[ $min_replicas -eq 0 ]]; then
                    errors+=("ПРЕДУПРЕЖДЕНИЕ: HPA minReplicas = 0 может привести к отсутствию pods")
                fi
            fi
            detected_kind=""
            min_replicas=0
            max_replicas=0
        fi

        if [[ "$detected_kind" == "HPA" ]]; then
            # Get minReplicas
            if [[ "$line" =~ minReplicas:[[:space:]]+([0-9]+) ]]; then
                min_replicas="${BASH_REMATCH[1]}"
            fi

            # Get maxReplicas
            if [[ "$line" =~ maxReplicas:[[:space:]]+([0-9]+) ]]; then
                max_replicas="${BASH_REMATCH[1]}"
            fi

            # Check target CPU utilization
            if [[ "$line" =~ targetCPUUtilizationPercentage:[[:space:]]+([0-9]+) ]]; then
                local cpu="${BASH_REMATCH[1]}"
                if [[ $cpu -gt 100 ]]; then
                    errors+=("Строка $line_num: HPA targetCPUUtilizationPercentage > 100% ($cpu)")
                fi
                if [[ $cpu -lt 10 ]]; then
                    errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: HPA targetCPU очень низкий ($cpu%)")
                fi
            fi
        fi
    done < "$file"

    # Final check
    if [[ "$detected_kind" == "HPA" ]]; then
        if [[ $min_replicas -gt $max_replicas ]] && [[ $max_replicas -gt 0 ]]; then
            errors+=("ОШИБКА: HPA minReplicas ($min_replicas) > maxReplicas ($max_replicas)")
        fi
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_pdb_config() {
    local file="$1"
    local line_num=0
    local errors=()
    local detected_kind=""
    local has_min_available=0
    local has_max_unavailable=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect PDB kind
        if [[ "$line" =~ ^kind:[[:space:]]+PodDisruptionBudget ]]; then
            detected_kind="PDB"
        fi

        # Reset on document separator
        if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
            if [[ "$detected_kind" == "PDB" ]]; then
                if [[ $has_min_available -eq 1 ]] && [[ $has_max_unavailable -eq 1 ]]; then
                    errors+=("ОШИБКА: PDB имеет и minAvailable, и maxUnavailable (допустимо только одно)")
                fi
                if [[ $has_min_available -eq 0 ]] && [[ $has_max_unavailable -eq 0 ]]; then
                    errors+=("ОШИБКА: PDB требует minAvailable или maxUnavailable")
                fi
            fi
            detected_kind=""
            has_min_available=0
            has_max_unavailable=0
        fi

        if [[ "$detected_kind" == "PDB" ]]; then
            if [[ "$line" =~ minAvailable:[[:space:]]+ ]]; then
                has_min_available=1
            fi
            if [[ "$line" =~ maxUnavailable:[[:space:]]+ ]]; then
                has_max_unavailable=1
            fi
        fi
    done < "$file"

    # Final check
    if [[ "$detected_kind" == "PDB" ]]; then
        if [[ $has_min_available -eq 1 ]] && [[ $has_max_unavailable -eq 1 ]]; then
            errors+=("ОШИБКА: PDB имеет и minAvailable, и maxUnavailable")
        fi
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

check_cronjob_schedule() {
    local file="$1"
    local line_num=0
    local errors=()
    local detected_kind=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect CronJob kind
        if [[ "$line" =~ ^kind:[[:space:]]+CronJob ]]; then
            detected_kind="CronJob"
        fi

        # Reset on document separator
        if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
            detected_kind=""
        fi

        if [[ "$detected_kind" == "CronJob" ]]; then
            # Validate schedule format
            if [[ "$line" =~ schedule:[[:space:]]+[\"\']?([^\"\'#]+)[\"\']? ]]; then
                local schedule="${BASH_REMATCH[1]}"
                schedule="${schedule#[\"\']}"
                schedule="${schedule%[\"\']}"
                schedule="${schedule% }"  # Trim trailing space

                # Count fields (should be 5 for standard cron)
                local field_count
                field_count=$(echo "$schedule" | awk '{print NF}')

                if [[ $field_count -ne 5 ]]; then
                    errors+=("Строка $line_num: CronJob schedule должен иметь 5 полей: '$schedule' (найдено: $field_count)")
                    errors+=("  Формат: минута час день месяц день_недели")
                fi

                # Check for very frequent schedules
                if [[ "$schedule" =~ ^\*/1[[:space:]] ]] || [[ "$schedule" =~ ^\*[[:space:]] ]]; then
                    errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: CronJob запускается каждую минуту")
                    errors+=("  Это может создать высокую нагрузку")
                fi
            fi

            # Check concurrencyPolicy
            if [[ "$line" =~ concurrencyPolicy:[[:space:]]+([^[:space:]#]+) ]]; then
                local policy="${BASH_REMATCH[1]}"
                if [[ ! "$policy" =~ ^(Allow|Forbid|Replace)$ ]]; then
                    errors+=("Строка $line_num: Некорректный concurrencyPolicy: '$policy'")
                    errors+=("  Допустимо: Allow, Forbid, Replace")
                fi
            fi

            # Check successfulJobsHistoryLimit / failedJobsHistoryLimit
            if [[ "$line" =~ successfulJobsHistoryLimit:[[:space:]]+([0-9]+) ]]; then
                local limit="${BASH_REMATCH[1]}"
                if [[ $limit -gt 100 ]]; then
                    errors+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: successfulJobsHistoryLimit очень высокий ($limit)")
                fi
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

# NEW CHECK: Timestamp values that might be auto-converted by YAML parsers
check_timestamp_values() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Check for unquoted ISO8601-like dates (YYYY-MM-DD)
        # These might be parsed as datetime objects instead of strings
        if [[ "$line" =~ :[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})([[:space:]]|$) ]]; then
            local value="${BASH_REMATCH[1]}"
            # Only warn if not already quoted
            if [[ ! "$line" =~ :[[:space:]]+[\"\'][0-9]{4}-[0-9]{2}-[0-9]{2}[\"\'] ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Незакавыченная дата '$value' может быть преобразована в timestamp")
                warnings+=("  Рекомендация: Используйте кавычки для сохранения строки: \"$value\"")
            fi
        fi

        # Check for ISO8601 datetime format (YYYY-MM-DDTHH:MM:SS)
        if [[ "$line" =~ :[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ ! "$line" =~ :[[:space:]]+[\"\'][0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Незакавыченный datetime '$value' будет преобразован парсером")
                warnings+=("  Рекомендация: Если нужна строка, используйте кавычки")
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
        return 1
    fi
    return 0
}

# NEW CHECK: Version numbers that might be parsed as floats
check_version_numbers() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Check for version-like fields with unquoted decimal numbers
        # Examples: version: 1.0, version: 2.1, appVersion: 1.0
        if [[ "$line" =~ ([vV]ersion|VERSION):[[:space:]]+([0-9]+\.[0-9]+)([[:space:]]|$) ]]; then
            local field="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            # Check if it's just X.Y (no third component) and unquoted
            if [[ ! "$line" =~ $field:[[:space:]]+[\"\'] ]] && [[ ! "$value" =~ \.[0-9]+\. ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Версия '$value' может быть распознана как float")
                warnings+=("  Примеры: 1.0 → 1, 1.10 → 1.1 (потеря precision)")
                warnings+=("  Рекомендация: Используйте кавычки: \"$value\"")
            fi
        fi

        # Check for chart version without quotes
        if [[ "$line" =~ ^(appVersion|chartVersion):[[:space:]]+([0-9]+\.[0-9]+)([[:space:]]|$) ]]; then
            local field="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            if [[ ! "$line" =~ $field:[[:space:]]+[\"\'] ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: $field '$value' должен быть в кавычках")
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
        return 1
    fi
    return 0
}

# NEW CHECK: YAML merge keys (<<:) support and validation
check_merge_keys() {
    local file="$1"
    local line_num=0
    local errors=()
    local declared_anchors=()

    # First pass: collect all anchors
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ \&([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            declared_anchors+=("${BASH_REMATCH[1]}")
        fi
    done < "$file"

    # Second pass: validate merge keys
    line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for merge key syntax
        if [[ "$line" =~ \<\<:[[:space:]]+\*([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            local alias="${BASH_REMATCH[1]}"
            # Check if referenced anchor exists
            local found=0
            for anchor in "${declared_anchors[@]}"; do
                if [[ "$anchor" == "$alias" ]]; then
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                errors+=("Строка $line_num: Merge key ссылается на несуществующий anchor: '*$alias'")
            fi
        fi

        # Check for invalid merge key syntax
        if [[ "$line" =~ \<\<[[:space:]]*:[[:space:]]*[^\*] ]] && [[ ! "$line" =~ \<\<:[[:space:]]*$ ]]; then
            if [[ ! "$line" =~ \<\<:[[:space:]]*\[ ]]; then
                errors+=("Строка $line_num: Некорректный синтаксис merge key, ожидается alias (*name)")
            fi
        fi

        # Check for merge with array of aliases (advanced syntax)
        if [[ "$line" =~ \<\<:[[:space:]]*\[([^\]]+)\] ]]; then
            local aliases_str="${BASH_REMATCH[1]}"
            # Parse comma-separated aliases
            IFS=',' read -ra alias_list <<< "$aliases_str"
            for alias_entry in "${alias_list[@]}"; do
                alias_entry="${alias_entry// /}"  # Trim spaces
                if [[ "$alias_entry" =~ ^\*([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                    local alias="${BASH_REMATCH[1]}"
                    local found=0
                    for anchor in "${declared_anchors[@]}"; do
                        if [[ "$anchor" == "$alias" ]]; then
                            found=1
                            break
                        fi
                    done
                    if [[ $found -eq 0 ]]; then
                        errors+=("Строка $line_num: Merge key list содержит несуществующий anchor: '*$alias'")
                    fi
                fi
            done
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

# NEW CHECK: Implicit type coercion warnings (extended)
check_implicit_types() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        # Skip multiline blocks (| or > indicators)
        [[ "$line" == *": |"* ]] && continue
        [[ "$line" == *": >"* ]] && continue
        [[ "$line" == *":|"* ]] && continue
        [[ "$line" == *":>"* ]] && continue

        # Check for country codes that might be parsed as booleans (Norway problem extended)
        # NO (Norway), NO (number), Y (yes in some locales)
        if [[ "$line" =~ :[[:space:]]+(NO|No|no|Y|N)([[:space:]]|$|#) ]]; then
            local value="${BASH_REMATCH[1]}"
            # shellcheck disable=SC1087
            if [[ ! "$line" =~ :[[:space:]]+[\"\']${value}[\"\'] ]]; then
                case "$value" in
                    NO|No|no)
                        warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: '$value' может быть интерпретирован как boolean false")
                        warnings+=("  Если это код страны (Норвегия) или другое значение, используйте кавычки: \"$value\"")
                        ;;
                    Y|N)
                        warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: '$value' может быть интерпретирован как boolean")
                        warnings+=("  Рекомендация: Используйте кавычки: \"$value\"")
                        ;;
                esac
            fi
        fi

        # Check for scientific notation that might be unintended
        if [[ "$line" =~ :[[:space:]]+([0-9]+[eE][+-]?[0-9]+)([[:space:]]|$) ]]; then
            local value="${BASH_REMATCH[1]}"
            # shellcheck disable=SC1087
            if [[ ! "$line" =~ :[[:space:]]+[\"\']${value}[\"\'] ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: '$value' интерпретируется как научная нотация")
                warnings+=("  Если это строка, используйте кавычки")
            fi
        fi

        # Check for infinity/nan values
        if [[ "$line" =~ :[[:space:]]+(\.inf|\.Inf|\.INF|-\.inf|\.nan|\.NaN|\.NAN)([[:space:]]|$) ]]; then
            local value="${BASH_REMATCH[1]}"
            warnings+=("Строка $line_num: ИНФОРМАЦИЯ: '$value' - специальное значение YAML (infinity/NaN)")
        fi

        # Check for unquoted strings starting with special characters
        if [[ "$line" == *": @"* ]]; then
            warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Значение начинается с '@' - рекомендуется закавычить")
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
        return 1
    fi
    return 0
}

# NEW CHECK: Embedded JSON validation in YAML
check_embedded_json() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect JSON-style inline values (single line)
        if [[ "$line" =~ :[[:space:]]+(\{[^\}]+\})([[:space:]]|$) ]]; then
            local json_val="${BASH_REMATCH[1]}"
            # Basic JSON object validation
            # Count braces
            local open_braces="${json_val//[^\{]/}"
            local close_braces="${json_val//[^\}]/}"
            if [[ ${#open_braces} -ne ${#close_braces} ]]; then
                errors+=("Строка $line_num: Несбалансированные фигурные скобки в inline JSON")
            fi
            # Check for common JSON errors
            if [[ "$json_val" =~ ,[[:space:]]*\} ]]; then
                errors+=("Строка $line_num: Trailing comma в JSON объекте")
            fi
        fi

        # Detect JSON-style inline arrays
        if [[ "$line" =~ :[[:space:]]+(\[[^\]]+\])([[:space:]]|$) ]]; then
            local json_arr="${BASH_REMATCH[1]}"
            local open_brackets="${json_arr//[^\[]/}"
            local close_brackets="${json_arr//[^\]]/}"
            if [[ ${#open_brackets} -ne ${#close_brackets} ]]; then
                errors+=("Строка $line_num: Несбалансированные квадратные скобки в inline JSON array")
            fi
            if [[ "$json_arr" =~ ,[[:space:]]*\] ]]; then
                errors+=("Строка $line_num: Trailing comma в JSON массиве")
            fi
        fi

        # Check for JSON keys without quotes (common mistake when embedding JSON)
        if [[ "$line" =~ \{[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]] ]]; then
            local key="${BASH_REMATCH[1]}"
            # If it looks like JSON (has : after a word), but key is unquoted
            if [[ "$line" =~ \{[^\"]*$key:[[:space:]] ]]; then
                errors+=("Строка $line_num: JSON ключ '$key' должен быть в двойных кавычках")
                errors+=("  Пример: {\"$key\": value}")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

# B17: Check for floats without leading zero (e.g., .5 instead of 0.5)
check_float_leading_zero() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        # Skip multiline content
        [[ "$line" == *": |"* ]] && continue
        [[ "$line" == *": >"* ]] && continue

        # Check for float values starting with . (no leading zero)
        # Match: key: .5 or key: -.5
        if [[ "$line" =~ :[[:space:]]+-?(\.[0-9]+)([[:space:]]|$|#) ]]; then
            local value="${BASH_REMATCH[1]}"
            # Check not in quotes
            if [[ ! "$line" =~ :[[:space:]]+[\"\'].*${value}.*[\"\'] ]]; then
                warnings+=("[WARNING] Строка $line_num: Float '$value' без ведущего нуля")
                warnings+=("  Рекомендация: Используйте '0$value' для ясности")
            fi
        fi

        # Also check in arrays: [.5, .25]
        if [[ "$line" =~ \[.*[,[:space:]]-?(\.[0-9]+)[,\]] ]]; then
            warnings+=("[WARNING] Строка $line_num: Float значение в массиве без ведущего нуля")
            warnings+=("  Рекомендация: Используйте 0.x вместо .x")
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# B18: Check for NaN/Inf values and optionally forbid them
check_special_floats() {
    local file="$1"
    local strict="${2:-0}"  # 1 = forbid, 0 = warn only
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for infinity values
        if [[ "$line" =~ :[[:space:]]+(\.inf|\.Inf|\.INF|-\.inf|-\.Inf|-\.INF|\+\.inf|\+\.Inf|\+\.INF)([[:space:]]|$|#) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ $strict -eq 1 ]]; then
                warnings+=("[ERROR] Строка $line_num: Infinity '$value' запрещено в strict режиме")
            else
                warnings+=("[INFO] Строка $line_num: Infinity значение '$value' - убедитесь, что это намеренно")
            fi
        fi

        # Check for NaN values
        if [[ "$line" =~ :[[:space:]]+(\.nan|\.NaN|\.NAN)([[:space:]]|$|#) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ $strict -eq 1 ]]; then
                warnings+=("[ERROR] Строка $line_num: NaN '$value' запрещено в strict режиме")
            else
                warnings+=("[INFO] Строка $line_num: NaN значение '$value' - убедитесь, что это намеренно")
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# B19: Check maximum nesting depth
check_nesting_depth() {
    local file="$1"
    local max_depth="${2:-10}"  # Default max 10 levels
    local line_num=0
    local warnings=()
    local max_found=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Calculate indentation (assume 2 spaces per level)
        local stripped="${line#"${line%%[![:space:]]*}"}"
        local indent=$((${#line} - ${#stripped}))
        local depth=$((indent / 2))

        # Track maximum depth
        if [[ $depth -gt $max_found ]]; then
            max_found=$depth
        fi

        # Warn if exceeds threshold
        if [[ $depth -gt $max_depth ]]; then
            warnings+=("[WARNING] Строка $line_num: Глубина вложенности ($depth) превышает рекомендуемый максимум ($max_depth)")
            warnings+=("  Рекомендация: Рассмотрите рефакторинг или использование якорей/алиасов")
        fi
    done < "$file"

    # Summary warning
    if [[ $max_found -gt $max_depth ]]; then
        warnings+=("[WARNING] Максимальная глубина вложенности в файле: $max_found (рекомендуется не более $max_depth)")
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# B20: Check for Unicode normalization issues
check_unicode_normalization() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Check for common Unicode issues:

        # 1. Zero-width characters (invisible but problematic)
        if [[ "$line" =~ $'\u200B' ]] || [[ "$line" =~ $'\u200C' ]] || [[ "$line" =~ $'\u200D' ]] || [[ "$line" =~ $'\uFEFF' ]]; then
            warnings+=("[WARNING] Строка $line_num: Обнаружены zero-width символы (невидимые Unicode)")
            warnings+=("  Это может вызвать проблемы парсинга или сравнения строк")
        fi

        # 2. Homoglyphs in ASCII-looking content (Cyrillic а/о/е/с looks like Latin)
        # Check if line has key: pattern with mixed scripts
        if [[ "$line" =~ ^[[:space:]]*([^:]+): ]]; then
            local key="${BASH_REMATCH[1]}"
            # Check for Cyrillic characters in what looks like ASCII key
            if [[ "$key" =~ [а-яА-ЯёЁ] ]] && [[ "$key" =~ [a-zA-Z] ]]; then
                warnings+=("[WARNING] Строка $line_num: Смешение латиницы и кириллицы в ключе '$key'")
                warnings+=("  Возможно использование похожих символов (homoglyphs)")
            fi
        fi

        # 3. Non-breaking space instead of regular space
        if [[ "$line" =~ $'\u00A0' ]]; then
            warnings+=("[WARNING] Строка $line_num: Обнаружен неразрывный пробел (U+00A0)")
            warnings+=("  Это может вызвать проблемы в YAML отступах")
        fi

        # 4. Different dash types
        if [[ "$line" =~ [–—] ]] && [[ "$line" =~ ^[[:space:]]*[–—] ]]; then
            warnings+=("[WARNING] Строка $line_num: Использован длинное тире (en/em-dash) вместо дефиса в начале")
            warnings+=("  YAML требует обычный дефис (-) для списков")
        fi

        # 5. Full-width characters
        if [[ "$line" =~ [：＝] ]]; then
            warnings+=("[WARNING] Строка $line_num: Обнаружены full-width символы (: или =)")
            warnings+=("  Используйте обычные ASCII двоеточия и равно")
        fi

    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# NEW CHECK: Networking and protocol values
check_network_values() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check protocol field (TCP, UDP, SCTP)
        if [[ "$line" =~ protocol:[[:space:]]+([^[:space:]#]+) ]]; then
            local proto="${BASH_REMATCH[1]}"
            proto="${proto%\"}"
            proto="${proto#\"}"
            if [[ ! "$proto" =~ ^(TCP|UDP|SCTP)$ ]]; then
                errors+=("Строка $line_num: Некорректный protocol: '$proto'")
                errors+=("  Допустимо: TCP, UDP, SCTP")
            fi
        fi

        # Check IP addresses format
        if [[ "$line" =~ (clusterIP|loadBalancerIP|externalIP):[[:space:]]+([^[:space:]#]+) ]]; then
            local field="${BASH_REMATCH[1]}"
            local ip="${BASH_REMATCH[2]}"
            ip="${ip%\"}"
            ip="${ip#\"}"
            # Skip special values
            if [[ "$ip" != "None" ]] && [[ "$ip" != "\"\"" ]] && [[ -n "$ip" ]]; then
                # Basic IPv4 validation
                if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$ip" =~ : ]]; then
                    errors+=("Строка $line_num: Некорректный формат IP для $field: '$ip'")
                fi
            fi
        fi

        # Check for CIDR notation
        if [[ "$line" =~ (cidr|CIDR|podCIDR|serviceCIDR):[[:space:]]+([^[:space:]#]+) ]]; then
            local cidr="${BASH_REMATCH[2]}"
            cidr="${cidr%\"}"
            cidr="${cidr#\"}"
            if [[ -n "$cidr" ]] && [[ ! "$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                errors+=("Строка $line_num: Некорректный CIDR формат: '$cidr'")
                errors+=("  Ожидается: X.X.X.X/Y (например: 10.0.0.0/8)")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

# NEW CHECK: Key naming conventions
check_key_naming() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Extract key from "key: value" pattern
        if [[ "$line" =~ ^([[:space:]]*)([a-zA-Z_][a-zA-Z0-9_-]*):[[:space:]] ]]; then
            local indent="${BASH_REMATCH[1]}"
            local key="${BASH_REMATCH[2]}"

            # Check for keys with double underscores (often typos)
            if [[ "$key" =~ __ ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Ключ '$key' содержит двойное подчёркивание")
            fi

            # Check for keys that start with numbers (valid YAML but unusual)
            if [[ "$key" =~ ^[0-9] ]]; then
                warnings+=("Строка $line_num: ПРЕДУПРЕЖДЕНИЕ: Ключ '$key' начинается с цифры")
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
        return 1
    fi
    return 0
}

# === YAMLLINT-COMPATIBLE CHECKS (v2.6.0) ===

check_line_length() {
    local file="$1"
    local max_length="${2:-120}"  # Default 120, yamllint default is 80
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        local line_len=${#line}
        if [[ $line_len -gt $max_length ]]; then
            warnings+=("Строка $line_num: Длина строки $line_len > $max_length символов")
            warnings+=("  Рекомендация: Разбейте на несколько строк для читаемости")
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_comment_format() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for comments without space after #
        # Skip shebang and YAML directives
        if [[ "$line" =~ ^[[:space:]]*#[^[:space:]!%] ]]; then
            # Not: # comment (space), #! shebang, #% directive
            warnings+=("Строка $line_num: Комментарий без пробела после #")
            warnings+=("  Было: ${line:0:50}...")
            warnings+=("  Рекомендация: Добавьте пробел после #")
        fi

        # Check for inline comment without space before #
        if [[ "$line" =~ [^[:space:]]#[[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
            # Skip URLs and other valid uses of # in strings
            if [[ ! "$line" =~ https?:// ]] && [[ ! "$line" =~ [\"\'][^\"\']*#[^\"\']*[\"\'] ]]; then
                warnings+=("Строка $line_num: Inline комментарий без пробела перед #")
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# A14: Comment indentation check (yamllint comments-indentation)
# Comments should be indented like content around them
check_comment_indentation() {
    local file="$1"
    local line_num=0
    local warnings=()
    local prev_indent=0
    local prev_is_comment=0
    local prev_line=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip empty lines for indentation tracking
        if [[ -z "${line// }" ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        # Calculate current line indentation
        local stripped="${line#"${line%%[![:space:]]*}"}"
        local current_indent=$((${#line} - ${#stripped}))

        # Check if current line is a comment
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            # Skip document start marker comments
            if [[ "$line" =~ ^#.*--- ]] || [[ "$line" =~ ^#.*\.\.\. ]]; then
                prev_indent=$current_indent
                prev_is_comment=1
                prev_line="$line"
                continue
            fi

            # If previous non-empty line was not a comment, check indentation
            if [[ $prev_is_comment -eq 0 && $prev_indent -gt 0 ]]; then
                # Comment should match previous content indentation OR be at column 0
                if [[ $current_indent -ne $prev_indent && $current_indent -ne 0 ]]; then
                    # Check if it might be a block comment (next content has different indent)
                    warnings+=("[INFO] Строка $line_num: Отступ комментария ($current_indent) не совпадает с окружающим кодом ($prev_indent)")
                fi
            fi

            prev_is_comment=1
        else
            # Content line after comment - comment should have matched this line's indent
            if [[ $prev_is_comment -eq 1 && $prev_indent -ne $current_indent && $prev_indent -ne 0 ]]; then
                # Previous comment had wrong indentation relative to this content
                local comment_line=$((line_num - 1))
                warnings+=("[INFO] Строка $comment_line: Комментарий с отступом ($prev_indent) перед содержимым с отступом ($current_indent)")
            fi
            prev_is_comment=0
        fi

        prev_indent=$current_indent
        prev_line="$line"
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_empty_lines() {
    local file="$1"
    local max_empty="${2:-2}"  # Default max 2 consecutive empty lines
    local line_num=0
    local empty_count=0
    local warnings=()
    local empty_start=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        if [[ -z "${line// }" ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            ((empty_count++))
            if [[ $empty_count -eq 1 ]]; then
                empty_start=$line_num
            fi
        else
            if [[ $empty_count -gt $max_empty ]]; then
                warnings+=("Строки $empty_start-$((line_num-1)): $empty_count подряд пустых строк (max: $max_empty)")
            fi
            empty_count=0
        fi
    done < "$file"

    # Check at end of file
    if [[ $empty_count -gt $max_empty ]]; then
        warnings+=("Строки $empty_start-$line_num: $empty_count подряд пустых строк в конце файла")
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_newline_at_eof() {
    local file="$1"
    local warnings=()

    # Check if file ends with newline
    if [[ -s "$file" ]]; then
        local last_char
        last_char=$(tail -c 1 "$file" | od -An -tx1 | tr -d ' ')

        if [[ "$last_char" != "0a" ]] && [[ "$last_char" != "" ]]; then
            warnings+=("ПРЕДУПРЕЖДЕНИЕ: Файл не заканчивается символом новой строки")
            warnings+=("  POSIX: Текстовые файлы должны заканчиваться newline")
            warnings+=("  Исправление: echo >> $file")
        fi
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_colons_spacing() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for colon without space after (except in URLs, times, port numbers)
        # Pattern: key:value (no space after colon)
        if [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*:[^[:space:]] ]]; then
            # Skip if it's a URL or port
            if [[ ! "$line" =~ (https?://|:[0-9]+) ]]; then
                local key_part="${line%%:*}"
                key_part="${key_part#"${key_part%%[![:space:]]*}"}"  # trim leading spaces
                # Additional check to avoid false positives on flow style
                if [[ ! "$line" =~ :[[:space:]]*[\[\{] ]]; then
                    warnings+=("Строка $line_num: Отсутствует пробел после двоеточия")
                    warnings+=("  Строка: ${line:0:60}...")
                fi
            fi
        fi

        # Check for space before colon in key:value
        if [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*[[:space:]]+: ]]; then
            warnings+=("Строка $line_num: Лишний пробел перед двоеточием")
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_brackets_spacing() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for space after [ or {
        if [[ "$line" =~ \[[[:space:]]{2,} ]] || [[ "$line" =~ \{[[:space:]]{2,} ]]; then
            warnings+=("Строка $line_num: Лишние пробелы после открывающей скобки")
        fi

        # Check for space before ] or }
        if [[ "$line" =~ [[:space:]]{2,}\] ]] || [[ "$line" =~ [[:space:]]{2,}\} ]]; then
            warnings+=("Строка $line_num: Лишние пробелы перед закрывающей скобкой")
        fi

        # Check for missing space after comma in arrays
        if [[ "$line" =~ \[[^\]]*,[^[:space:]] ]]; then
            # Skip if it's not a flow-style array
            if [[ "$line" =~ \[[^\]]+\] ]]; then
                warnings+=("Строка $line_num: Отсутствует пробел после запятой в массиве")
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

check_truthy_values() {
    local file="$1"
    local line_num=0
    local warnings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for truthy values that should be quoted or explicit true/false
        # yamllint truthy rule: warn about yes/no/on/off/y/n
        if [[ "$line" =~ :[[:space:]]+(yes|Yes|YES|no|No|NO|on|On|ON|off|Off|OFF)[[:space:]]*$ ]]; then
            local value="${BASH_REMATCH[1]}"
            warnings+=("Строка $line_num: Truthy value '$value' — неоднозначно")
            warnings+=("  YAML 1.1: Интерпретируется как boolean")
            warnings+=("  Рекомендация: Используйте true/false или заключите в кавычки")
        fi

        # Check for y/n (single letter)
        if [[ "$line" =~ :[[:space:]]+(y|Y|n|N)[[:space:]]*$ ]]; then
            local value="${BASH_REMATCH[1]}"
            warnings+=("Строка $line_num: Single letter '$value' — может быть boolean в YAML 1.1")
            warnings+=("  Рекомендация: Заключите в кавычки если это строка")
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# =============================================================================
# A18: K8s Key Ordering Convention (OPTIONAL)
# =============================================================================
# K8s convention: apiVersion → kind → metadata → spec → data/stringData → status
check_key_ordering() {
    local file="$1"
    local warnings=()

    # K8s top-level key order convention
    declare -A KEY_ORDER
    KEY_ORDER[apiVersion]=1
    KEY_ORDER[kind]=2
    KEY_ORDER[metadata]=3
    KEY_ORDER[spec]=4
    KEY_ORDER[data]=5
    KEY_ORDER[stringData]=5
    KEY_ORDER[status]=6
    KEY_ORDER[rules]=5        # For RBAC
    KEY_ORDER[subjects]=6     # For RoleBinding
    KEY_ORDER[roleRef]=7      # For RoleBinding

    local prev_order=0
    local prev_key=""
    local line_num=0
    local in_document=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Document separator - reset
        if [[ "$line" =~ ^--- ]]; then
            prev_order=0
            prev_key=""
            in_document=1
            continue
        fi

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Only check top-level keys (no leading whitespace)
        if [[ "$line" =~ ^([a-zA-Z][a-zA-Z0-9]*): ]]; then
            local key="${BASH_REMATCH[1]}"
            local order="${KEY_ORDER[$key]:-99}"

            if [[ $order -lt $prev_order && $prev_order -ne 99 && $order -ne 99 ]]; then
                warnings+=("[INFO] Строка $line_num: Порядок ключей: '$key' должен быть перед '$prev_key'")
                warnings+=("  K8s конвенция: apiVersion → kind → metadata → spec → data → status")
            fi

            prev_order=$order
            prev_key="$key"
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# =============================================================================
# C31-C33: Partial Schema Validation (OPTIONAL)
# =============================================================================

# C31: Field type validation for common K8s fields
check_field_types() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # replicas should be integer
        if [[ "$line" =~ replicas:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ ! "$value" =~ ^[0-9]+$ ]]; then
                errors+=("[ERROR] Строка $line_num: replicas должен быть integer, найдено: '$value'")
            fi
        fi

        # containerPort should be integer 1-65535
        if [[ "$line" =~ containerPort:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ ! "$value" =~ ^[0-9]+$ ]]; then
                errors+=("[ERROR] Строка $line_num: containerPort должен быть integer, найдено: '$value'")
            elif [[ $value -lt 1 || $value -gt 65535 ]]; then
                errors+=("[ERROR] Строка $line_num: containerPort должен быть 1-65535, найдено: $value")
            fi
        fi

        # port (in Service) should be integer
        if [[ "$line" =~ ^[[:space:]]+port:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ ! "$value" =~ ^[0-9]+$ ]]; then
                errors+=("[ERROR] Строка $line_num: port должен быть integer, найдено: '$value'")
            fi
        fi

        # targetPort can be integer or string (named port)
        # minReplicas/maxReplicas in HPA
        if [[ "$line" =~ (minReplicas|maxReplicas):[[:space:]]+([^[:space:]#]+) ]]; then
            local field="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            if [[ ! "$value" =~ ^[0-9]+$ ]]; then
                errors+=("[ERROR] Строка $line_num: $field должен быть integer, найдено: '$value'")
            fi
        fi

        # terminationGracePeriodSeconds should be integer
        if [[ "$line" =~ terminationGracePeriodSeconds:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ ! "$value" =~ ^[0-9]+$ ]]; then
                errors+=("[ERROR] Строка $line_num: terminationGracePeriodSeconds должен быть integer")
            fi
        fi

        # revisionHistoryLimit should be integer
        if [[ "$line" =~ revisionHistoryLimit:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ ! "$value" =~ ^[0-9]+$ ]]; then
                errors+=("[ERROR] Строка $line_num: revisionHistoryLimit должен быть integer")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

# C32: Enum value validation
check_enum_values() {
    local file="$1"
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # restartPolicy: Always | OnFailure | Never
        if [[ "$line" =~ restartPolicy:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            value="${value//\"/}"
            value="${value//\'/}"
            if [[ ! "$value" =~ ^(Always|OnFailure|Never)$ ]]; then
                errors+=("[ERROR] Строка $line_num: restartPolicy должен быть Always|OnFailure|Never, найдено: '$value'")
            fi
        fi

        # imagePullPolicy: Always | IfNotPresent | Never
        if [[ "$line" =~ imagePullPolicy:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            value="${value//\"/}"
            value="${value//\'/}"
            if [[ ! "$value" =~ ^(Always|IfNotPresent|Never)$ ]]; then
                errors+=("[ERROR] Строка $line_num: imagePullPolicy должен быть Always|IfNotPresent|Never, найдено: '$value'")
            fi
        fi

        # type (Service): ClusterIP | NodePort | LoadBalancer | ExternalName
        if [[ "$line" =~ ^[[:space:]]+type:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            # Only check if it looks like a Service type (common values)
            if [[ "$value" =~ ^(ClusterIP|NodePort|LoadBalancer|ExternalName|clusterip|nodeport|loadbalancer)$ ]]; then
                # Valid, but check case
                if [[ ! "$value" =~ ^(ClusterIP|NodePort|LoadBalancer|ExternalName)$ ]]; then
                    errors+=("[WARNING] Строка $line_num: Service type неправильный регистр: '$value'")
                fi
            fi
        fi

        # protocol: TCP | UDP | SCTP
        if [[ "$line" =~ protocol:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            value="${value//\"/}"
            value="${value//\'/}"
            if [[ ! "$value" =~ ^(TCP|UDP|SCTP)$ ]]; then
                errors+=("[ERROR] Строка $line_num: protocol должен быть TCP|UDP|SCTP, найдено: '$value'")
            fi
        fi

        # strategy.type (Deployment): Recreate | RollingUpdate
        if [[ "$line" =~ ^[[:space:]]+type:[[:space:]]+(Recreate|RollingUpdate|recreate|rollingupdate)[[:space:]]*$ ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ ! "$value" =~ ^(Recreate|RollingUpdate)$ ]]; then
                errors+=("[WARNING] Строка $line_num: strategy.type неправильный регистр: '$value'")
            fi
        fi

        # concurrencyPolicy (CronJob): Allow | Forbid | Replace
        if [[ "$line" =~ concurrencyPolicy:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ ! "$value" =~ ^(Allow|Forbid|Replace)$ ]]; then
                errors+=("[ERROR] Строка $line_num: concurrencyPolicy должен быть Allow|Forbid|Replace, найдено: '$value'")
            fi
        fi

        # dnsPolicy: Default | ClusterFirst | ClusterFirstWithHostNet | None
        if [[ "$line" =~ dnsPolicy:[[:space:]]+([^[:space:]#]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ ! "$value" =~ ^(Default|ClusterFirst|ClusterFirstWithHostNet|None)$ ]]; then
                errors+=("[ERROR] Строка $line_num: dnsPolicy должен быть Default|ClusterFirst|ClusterFirstWithHostNet|None")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

# C33: Required nested fields validation
check_required_nested() {
    local file="$1"
    local errors=()
    local content
    content=$(cat "$file")

    # Check Deployment/StatefulSet has spec.selector
    if [[ "$content" =~ kind:[[:space:]]*(Deployment|StatefulSet|ReplicaSet|DaemonSet) ]]; then
        if [[ ! "$content" =~ selector: ]]; then
            errors+=("[ERROR] Deployment/StatefulSet/ReplicaSet/DaemonSet требует spec.selector")
        fi
    fi

    # Check Service has spec.ports
    if [[ "$content" =~ kind:[[:space:]]*Service ]] && [[ ! "$content" =~ kind:[[:space:]]*ServiceAccount ]]; then
        if [[ ! "$content" =~ ports: ]]; then
            errors+=("[WARNING] Service обычно требует spec.ports")
        fi
    fi

    # Check Ingress has rules
    if [[ "$content" =~ kind:[[:space:]]*Ingress ]]; then
        if [[ ! "$content" =~ rules: ]]; then
            errors+=("[WARNING] Ingress обычно требует spec.rules")
        fi
    fi

    # Check ConfigMap has data or binaryData
    if [[ "$content" =~ kind:[[:space:]]*ConfigMap ]]; then
        if [[ ! "$content" =~ (data:|binaryData:) ]]; then
            errors+=("[WARNING] ConfigMap обычно требует data или binaryData")
        fi
    fi

    # Check container has name and image
    if [[ "$content" =~ containers: ]]; then
        # Simple check - containers should have - name: and image:
        if [[ ! "$content" =~ -[[:space:]]*name: ]]; then
            errors+=("[ERROR] Контейнеры требуют name")
        fi
        # Image can be omitted in some cases, so just warning
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
    fi
    return 0
}

# =============================================================================
# E8-E19: Best Practices Checks
# =============================================================================

# E8: Replicas < 3 for HA
check_replicas_ha() {
    local file="$1"
    local line_num=0
    local warnings=()
    local kind=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Track kind
        if [[ "$line" =~ ^kind:[[:space:]]+([^[:space:]#]+) ]]; then
            kind="${BASH_REMATCH[1]}"
        fi

        # Check replicas for Deployment/StatefulSet
        if [[ "$line" =~ replicas:[[:space:]]+([0-9]+) ]]; then
            local replicas="${BASH_REMATCH[1]}"
            if [[ "$kind" =~ ^(Deployment|StatefulSet)$ ]] && [[ $replicas -lt 3 ]]; then
                warnings+=("[INFO] Строка $line_num: replicas: $replicas — для HA рекомендуется минимум 3")
                warnings+=("  Kind: $kind")
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# E9: Missing anti-affinity for HA
check_anti_affinity() {
    local file="$1"
    local warnings=()
    local content
    content=$(cat "$file")

    # Check if it's a Deployment or StatefulSet with replicas > 1
    if [[ "$content" =~ kind:[[:space:]]*(Deployment|StatefulSet) ]]; then
        local kind="${BASH_REMATCH[1]}"
        if [[ "$content" =~ replicas:[[:space:]]*([0-9]+) ]]; then
            local replicas="${BASH_REMATCH[1]}"
            if [[ $replicas -gt 1 ]]; then
                # Check for podAntiAffinity
                if [[ ! "$content" =~ podAntiAffinity: ]]; then
                    warnings+=("[INFO] $kind с replicas: $replicas без podAntiAffinity")
                    warnings+=("  Рекомендация: Добавьте podAntiAffinity для распределения по нодам")
                fi
            fi
        fi
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# E10: No rolling update strategy
check_rolling_update() {
    local file="$1"
    local warnings=()
    local content
    content=$(cat "$file")

    # Check Deployment has strategy
    if [[ "$content" =~ kind:[[:space:]]*Deployment ]]; then
        if [[ ! "$content" =~ strategy: ]]; then
            warnings+=("[INFO] Deployment без явной strategy")
            warnings+=("  По умолчанию: RollingUpdate, но лучше указать явно")
        elif [[ "$content" =~ type:[[:space:]]*Recreate ]]; then
            warnings+=("[WARNING] Deployment использует strategy: Recreate")
            warnings+=("  Риск: Downtime при обновлении")
            warnings+=("  Рекомендация: Используйте RollingUpdate для zero-downtime")
        fi
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# E15: Duplicate env vars
check_duplicate_env() {
    local file="$1"
    local line_num=0
    local errors=()
    local in_env=0
    local env_names=()
    local container_name=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Track container name
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]+([^[:space:]#]+) ]]; then
            # Could be container or env var name
            if [[ $in_env -eq 0 ]]; then
                container_name="${BASH_REMATCH[1]}"
            fi
        fi

        # Track env section
        if [[ "$line" =~ ^[[:space:]]+env:[[:space:]]*$ ]]; then
            in_env=1
            env_names=()
            continue
        fi

        # Exit env section on unindent or new section
        if [[ $in_env -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]{6}[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                in_env=0
                env_names=()
            fi

            # Check env var name
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]+([^[:space:]#]+) ]]; then
                local env_name="${BASH_REMATCH[1]}"
                env_name="${env_name//\"/}"
                env_name="${env_name//\'/}"

                # Check for duplicate
                for existing in "${env_names[@]}"; do
                    if [[ "$existing" == "$env_name" ]]; then
                        errors+=("[ERROR] Строка $line_num: Дубликат env переменной: '$env_name'")
                        errors+=("  Контейнер: $container_name")
                    fi
                done
                env_names+=("$env_name")
            fi
        fi
    done < "$file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    return 0
}

# E16: Missing namespace
check_missing_namespace() {
    local file="$1"
    local warnings=()
    local content
    content=$(cat "$file")

    # Skip cluster-scoped resources
    if [[ "$content" =~ kind:[[:space:]]*(Namespace|ClusterRole|ClusterRoleBinding|PersistentVolume|StorageClass|CustomResourceDefinition|Node) ]]; then
        return 0
    fi

    # Check for namespace in metadata
    if [[ ! "$content" =~ namespace:[[:space:]]+ ]]; then
        if [[ "$content" =~ kind:[[:space:]]+([^[:space:]#]+) ]]; then
            local kind="${BASH_REMATCH[1]}"
            warnings+=("[INFO] $kind без явного namespace")
            warnings+=("  Будет создан в default или текущем namespace контекста")
            warnings+=("  Рекомендация: Явно укажите metadata.namespace")
        fi
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# E17: Priority class not set
check_priority_class() {
    local file="$1"
    local warnings=()
    local content
    content=$(cat "$file")

    # Check workloads
    if [[ "$content" =~ kind:[[:space:]]*(Deployment|StatefulSet|DaemonSet|Job|CronJob) ]]; then
        local kind="${BASH_REMATCH[1]}"
        if [[ ! "$content" =~ priorityClassName: ]]; then
            warnings+=("[INFO] $kind без priorityClassName")
            warnings+=("  Рекомендация: Установите priorityClassName для управления приоритетом Pod")
        fi
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# E18: Probe ports validation (httpGet.port должен быть в ports[])
check_probe_ports() {
    local file="$1"
    local warnings=()
    local ports=()
    local probe_ports=()
    local line_num=0

    # First pass: collect all containerPort values
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ containerPort:[[:space:]]+([0-9]+) ]]; then
            ports+=("${BASH_REMATCH[1]}")
        fi
        if [[ "$line" =~ ^[[:space:]]+port:[[:space:]]+([0-9]+) ]] && [[ "$line" =~ httpGet|tcpSocket ]]; then
            probe_ports+=("${BASH_REMATCH[1]}")
        fi
    done < "$file"

    # Second pass: check probe ports
    line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check httpGet port
        if [[ "$line" =~ port:[[:space:]]+([0-9]+) ]]; then
            local probe_port="${BASH_REMATCH[1]}"
            # Check if this port exists in containerPorts (simple check)
            local found=0
            for p in "${ports[@]}"; do
                if [[ "$p" == "$probe_port" ]]; then
                    found=1
                    break
                fi
            done
            # Only warn if we have ports defined and this port isn't in them
            if [[ ${#ports[@]} -gt 0 && $found -eq 0 ]]; then
                # This might be a named port, so just info
                warnings+=("[INFO] Строка $line_num: Probe port $probe_port может не соответствовать containerPort")
            fi
        fi
    done < "$file"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# E19: Missing owner label
check_owner_label() {
    local file="$1"
    local warnings=()
    local content
    content=$(cat "$file")

    # Check for common ownership labels
    if [[ "$content" =~ kind:[[:space:]]*(Deployment|StatefulSet|Service|ConfigMap|Secret) ]]; then
        local kind="${BASH_REMATCH[1]}"
        local has_owner=0

        # Check for various ownership label patterns
        [[ "$content" =~ app\.kubernetes\.io/managed-by: ]] && has_owner=1
        [[ "$content" =~ app\.kubernetes\.io/owner: ]] && has_owner=1
        [[ "$content" =~ owner: ]] && has_owner=1
        [[ "$content" =~ team: ]] && has_owner=1
        [[ "$content" =~ maintainer: ]] && has_owner=1

        if [[ $has_owner -eq 0 ]]; then
            warnings+=("[INFO] $kind без метки владельца")
            warnings+=("  Рекомендация: Добавьте app.kubernetes.io/managed-by или team/owner label")
        fi
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

# E11-E14: Dangling resources (requires multi-file analysis)
# These are implemented as single-file heuristics
check_dangling_resources() {
    local file="$1"
    local warnings=()
    local content
    content=$(cat "$file")

    # E11: Dangling Service - Service without matching Pod selector
    # (Can only check if selector is defined, not if Pods exist)
    if [[ "$content" =~ kind:[[:space:]]*Service ]] && [[ ! "$content" =~ kind:[[:space:]]*ServiceAccount ]]; then
        if [[ ! "$content" =~ selector: ]]; then
            warnings+=("[WARNING] Service без selector — может быть dangling")
            warnings+=("  Рекомендация: Укажите selector для связи с Pods")
        fi
    fi

    # E12: Ingress без backend service (простая проверка)
    if [[ "$content" =~ kind:[[:space:]]*Ingress ]]; then
        if [[ ! "$content" =~ (backend:|service:) ]]; then
            warnings+=("[WARNING] Ingress без явного backend — может быть dangling")
        fi
    fi

    # E13: HPA without matching target
    if [[ "$content" =~ kind:[[:space:]]*HorizontalPodAutoscaler ]]; then
        if [[ ! "$content" =~ scaleTargetRef: ]]; then
            warnings+=("[ERROR] HPA без scaleTargetRef — dangling!")
        fi
    fi

    # E14: NetworkPolicy without podSelector
    if [[ "$content" =~ kind:[[:space:]]*NetworkPolicy ]]; then
        if [[ ! "$content" =~ podSelector: ]]; then
            warnings+=("[WARNING] NetworkPolicy без podSelector")
        fi
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        printf '%s\n' "${warnings[@]}"
    fi
    return 0
}

validate_yaml_file() {
    local file="$1"
    local verbose="$2"
    local file_errors=()

    # Reset severity counters for this file
    reset_severity_counts

    echo -e "${BLUE}[ПРОВЕРЯЮ]${NC} $file"

    # Critical checks first
    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка BOM (Byte Order Mark)...${NC}"
    fi
    local bom_errors
    if ! bom_errors=$(check_bom "$file"); then
        file_errors+=("=== КРИТИЧЕСКАЯ ОШИБКА: BOM ===")
        file_errors+=("$bom_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка на пустой файл...${NC}"
    fi
    local empty_errors
    if ! empty_errors=$(check_empty_file "$file"); then
        file_errors+=("$empty_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка кодировки Windows (CRLF)...${NC}"
    fi
    local encoding_errors
    if ! encoding_errors=$(check_windows_encoding "$file"); then
        file_errors+=("=== ОШИБКИ КОДИРОВКИ ===")
        file_errors+=("$encoding_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка табов...${NC}"
    fi
    local tab_errors
    if ! tab_errors=$(check_tabs "$file"); then
        file_errors+=("=== ОШИБКИ ТАБОВ ===")
        file_errors+=("$tab_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка пробелов в конце строк...${NC}"
    fi
    local trailing_errors
    if ! trailing_errors=$(check_trailing_whitespace "$file"); then
        file_errors+=("=== ПРЕДУПРЕЖДЕНИЯ: TRAILING WHITESPACE ===")
        file_errors+=("$trailing_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка отступов...${NC}"
    fi
    local indent_errors
    if ! indent_errors=$(check_indentation "$file"); then
        file_errors+=("=== ОШИБКИ ОТСТУПОВ ===")
        file_errors+=("$indent_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка синтаксиса и скобок...${NC}"
    fi
    local syntax_errors
    if ! syntax_errors=$(check_basic_syntax "$file"); then
        file_errors+=("=== ОШИБКИ СИНТАКСИСА ===")
        file_errors+=("$syntax_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка пустых ключей...${NC}"
    fi
    local empty_key_errors
    if ! empty_key_errors=$(check_empty_keys "$file"); then
        file_errors+=("=== ОШИБКИ ПУСТЫХ КЛЮЧЕЙ ===")
        file_errors+=("$empty_key_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка дубликатов ключей...${NC}"
    fi
    local duplicate_errors
    if ! duplicate_errors=$(check_duplicate_keys "$file"); then
        file_errors+=("=== ОШИБКИ ДУБЛИКАТОВ КЛЮЧЕЙ ===")
        file_errors+=("$duplicate_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка специальных значений (yes/no/on/off)...${NC}"
    fi
    local special_value_errors
    if ! special_value_errors=$(check_special_values "$file"); then
        file_errors+=("=== ПРЕДУПРЕЖДЕНИЯ: СПЕЦИАЛЬНЫЕ ЗНАЧЕНИЯ ===")
        file_errors+=("$special_value_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка маркеров документа (---, ...)...${NC}"
    fi
    local marker_errors
    if ! marker_errors=$(check_document_markers "$file"); then
        file_errors+=("=== ОШИБКИ МАРКЕРОВ ДОКУМЕНТА ===")
        file_errors+=("$marker_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка формата Kubernetes меток...${NC}"
    fi
    local label_errors
    if ! label_errors=$(check_label_format "$file"); then
        file_errors+=("=== KUBERNETES: ФОРМАТ МЕТОК ===")
        file_errors+=("$label_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка YAML anchors/aliases...${NC}"
    fi
    local anchor_errors
    if ! anchor_errors=$(check_anchors_aliases "$file"); then
        file_errors+=("=== ОШИБКИ YAML ANCHORS/ALIASES ===")
        file_errors+=("$anchor_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка Kubernetes полей и опечаток...${NC}"
    fi
    local k8s_errors
    if ! k8s_errors=$(check_kubernetes_specific "$file"); then
        file_errors+=("=== KUBERNETES: РАСШИРЕННАЯ ПРОВЕРКА ===")
        file_errors+=("$k8s_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка base64 в Secrets...${NC}"
    fi
    local base64_errors
    if ! base64_errors=$(check_base64_in_secrets "$file"); then
        file_errors+=("=== KUBERNETES: ВАЛИДАЦИЯ BASE64 ===")
        file_errors+=("$base64_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка числовых форматов (octal, hex)...${NC}"
    fi
    local numeric_errors
    if ! numeric_errors=$(check_numeric_formats "$file"); then
        file_errors+=("=== ИНФОРМАЦИЯ: ЧИСЛОВЫЕ ФОРМАТЫ ===")
        file_errors+=("$numeric_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка resource quantities (cpu, memory)...${NC}"
    fi
    local resource_errors
    if ! resource_errors=$(check_resource_quantities "$file"); then
        file_errors+=("=== KUBERNETES: RESOURCE QUANTITIES ===")
        file_errors+=("$resource_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка диапазонов портов...${NC}"
    fi
    local port_errors
    if ! port_errors=$(check_port_ranges "$file"); then
        file_errors+=("=== KUBERNETES: ВАЛИДАЦИЯ ПОРТОВ ===")
        file_errors+=("$port_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка multiline блоков (|, >)...${NC}"
    fi
    local multiline_errors
    if ! multiline_errors=$(check_multiline_blocks "$file"); then
        file_errors+=("=== YAML: MULTILINE БЛОКИ ===")
        file_errors+=("$multiline_errors")
    fi

    # === NEW CHECKS v2.3.0 ===

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка sexagesimal (21:00 = 1260)...${NC}"
    fi
    local sexagesimal_warnings
    sexagesimal_warnings=$(check_sexagesimal "$file")
    if [[ -n "$sexagesimal_warnings" ]]; then
        file_errors+=("=== YAML 1.1: SEXAGESIMAL ===")
        file_errors+=("$sexagesimal_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка Norway Problem (y/n/NO)...${NC}"
    fi
    local norway_warnings
    norway_warnings=$(check_extended_norway "$file")
    if [[ -n "$norway_warnings" ]]; then
        file_errors+=("=== YAML 1.1: NORWAY PROBLEM ===")
        file_errors+=("$norway_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка YAML Bomb (Billion Laughs)...${NC}"
    fi
    local bomb_errors
    if ! bomb_errors=$(check_yaml_bomb "$file"); then
        file_errors+=("=== БЕЗОПАСНОСТЬ: YAML BOMB ===")
        file_errors+=("$bomb_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка кавычек для спецсимволов...${NC}"
    fi
    local quoting_warnings
    quoting_warnings=$(check_string_quoting "$file")
    if [[ -n "$quoting_warnings" ]]; then
        file_errors+=("=== YAML: КАВЫЧКИ ===")
        file_errors+=("$quoting_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка imagePullPolicy...${NC}"
    fi
    local pullpolicy_errors
    if ! pullpolicy_errors=$(check_image_pull_policy "$file"); then
        file_errors+=("=== KUBERNETES: IMAGEPULLPOLICY ===")
        file_errors+=("$pullpolicy_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка replicas (тип данных)...${NC}"
    fi
    local replicas_errors
    if ! replicas_errors=$(check_replicas_type "$file"); then
        file_errors+=("=== KUBERNETES: REPLICAS ===")
        file_errors+=("$replicas_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка image tags (:latest)...${NC}"
    fi
    local imagetag_warnings
    imagetag_warnings=$(check_image_tags "$file")
    if [[ -n "$imagetag_warnings" ]]; then
        file_errors+=("=== KUBERNETES: IMAGE TAGS ===")
        file_errors+=("$imagetag_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка длины labels/annotations...${NC}"
    fi
    local length_errors
    if ! length_errors=$(check_annotation_length "$file"); then
        file_errors+=("=== KUBERNETES: LABEL/ANNOTATION LENGTH ===")
        file_errors+=("$length_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка securityContext...${NC}"
    fi
    local security_warnings
    security_warnings=$(check_security_context "$file")
    if [[ -n "$security_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: SECURITY CONTEXT ===")
        file_errors+=("$security_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка probe config...${NC}"
    fi
    local probe_warnings
    probe_warnings=$(check_probe_config "$file")
    if [[ -n "$probe_warnings" ]]; then
        file_errors+=("=== KUBERNETES: PROBES ===")
        file_errors+=("$probe_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка restartPolicy...${NC}"
    fi
    local restart_errors
    if ! restart_errors=$(check_restart_policy "$file"); then
        file_errors+=("=== KUBERNETES: RESTARTPOLICY ===")
        file_errors+=("$restart_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка Service type...${NC}"
    fi
    local svctype_errors
    if ! svctype_errors=$(check_service_type "$file"); then
        file_errors+=("=== KUBERNETES: SERVICE TYPE ===")
        file_errors+=("$svctype_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка Deckhouse CRD...${NC}"
    fi
    local deckhouse_errors
    if ! deckhouse_errors=$(check_deckhouse_crd "$file"); then
        file_errors+=("=== DECKHOUSE: CRD VALIDATION ===")
        file_errors+=("$deckhouse_errors")
    fi

    # === NEW CHECKS v2.4.0 ===

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка deprecated API versions...${NC}"
    fi
    local deprecated_api_warnings
    deprecated_api_warnings=$(check_deprecated_api "$file")
    if [[ -n "$deprecated_api_warnings" ]]; then
        file_errors+=("=== KUBERNETES: DEPRECATED API ===")
        file_errors+=("$deprecated_api_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка selector/template labels...${NC}"
    fi
    local selector_errors
    if ! selector_errors=$(check_selector_match "$file"); then
        file_errors+=("=== KUBERNETES: SELECTOR MISMATCH ===")
        file_errors+=("$selector_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка environment variables...${NC}"
    fi
    local env_errors
    if ! env_errors=$(check_env_vars "$file"); then
        file_errors+=("=== KUBERNETES: ENV VARS ===")
        file_errors+=("$env_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка DNS names (RFC 1123)...${NC}"
    fi
    local dns_errors
    if ! dns_errors=$(check_dns_names "$file"); then
        file_errors+=("=== KUBERNETES: DNS NAMES ===")
        file_errors+=("$dns_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка null values...${NC}"
    fi
    local null_warnings
    null_warnings=$(check_null_values "$file")
    if [[ -n "$null_warnings" ]]; then
        file_errors+=("=== YAML: NULL VALUES ===")
        file_errors+=("$null_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка flow style (inline JSON)...${NC}"
    fi
    local flow_errors
    if ! flow_errors=$(check_flow_style "$file"); then
        file_errors+=("=== YAML: FLOW STYLE ===")
        file_errors+=("$flow_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка container names...${NC}"
    fi
    local container_name_errors
    if ! container_name_errors=$(check_container_name "$file"); then
        file_errors+=("=== KUBERNETES: CONTAINER NAMES ===")
        file_errors+=("$container_name_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка security best practices...${NC}"
    fi
    local security_bp_warnings
    security_bp_warnings=$(check_security_best_practices "$file")
    if [[ -n "$security_bp_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: BEST PRACTICES ===")
        file_errors+=("$security_bp_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка resource format (cpu/memory)...${NC}"
    fi
    local resource_fmt_errors
    if ! resource_fmt_errors=$(check_resource_format "$file"); then
        file_errors+=("=== KUBERNETES: RESOURCE FORMAT ===")
        file_errors+=("$resource_fmt_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка Service selector...${NC}"
    fi
    local svc_selector_warnings
    svc_selector_warnings=$(check_service_selector "$file")
    if [[ -n "$svc_selector_warnings" ]]; then
        file_errors+=("=== KUBERNETES: SERVICE SELECTOR ===")
        file_errors+=("$svc_selector_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка volume mounts (CVE-2023-3676)...${NC}"
    fi
    local volume_errors
    if ! volume_errors=$(check_volume_mounts "$file"); then
        file_errors+=("=== БЕЗОПАСНОСТЬ: VOLUME MOUNTS ===")
        file_errors+=("$volume_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка ConfigMap keys...${NC}"
    fi
    local cm_key_errors
    if ! cm_key_errors=$(check_configmap_keys "$file"); then
        file_errors+=("=== KUBERNETES: CONFIGMAP KEYS ===")
        file_errors+=("$cm_key_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка Ingress rules...${NC}"
    fi
    local ingress_errors
    if ! ingress_errors=$(check_ingress_rules "$file"); then
        file_errors+=("=== KUBERNETES: INGRESS ===")
        file_errors+=("$ingress_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка HPA config...${NC}"
    fi
    local hpa_errors
    if ! hpa_errors=$(check_hpa_config "$file"); then
        file_errors+=("=== KUBERNETES: HPA ===")
        file_errors+=("$hpa_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка PodDisruptionBudget...${NC}"
    fi
    local pdb_errors
    if ! pdb_errors=$(check_pdb_config "$file"); then
        file_errors+=("=== KUBERNETES: PDB ===")
        file_errors+=("$pdb_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка CronJob schedule...${NC}"
    fi
    local cronjob_errors
    if ! cronjob_errors=$(check_cronjob_schedule "$file"); then
        file_errors+=("=== KUBERNETES: CRONJOB ===")
        file_errors+=("$cronjob_errors")
    fi

    # === NEW CHECKS v2.5.0 ===

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка timestamp/date values...${NC}"
    fi
    local timestamp_warnings
    timestamp_warnings=$(check_timestamp_values "$file")
    if [[ -n "$timestamp_warnings" ]]; then
        file_errors+=("=== YAML: TIMESTAMP VALUES ===")
        file_errors+=("$timestamp_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка version numbers...${NC}"
    fi
    local version_warnings
    version_warnings=$(check_version_numbers "$file")
    if [[ -n "$version_warnings" ]]; then
        file_errors+=("=== YAML: VERSION NUMBERS ===")
        file_errors+=("$version_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка merge keys (<<:)...${NC}"
    fi
    local merge_errors
    if ! merge_errors=$(check_merge_keys "$file"); then
        file_errors+=("=== YAML: MERGE KEYS ===")
        file_errors+=("$merge_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка implicit type coercion...${NC}"
    fi
    local implicit_warnings
    implicit_warnings=$(check_implicit_types "$file")
    if [[ -n "$implicit_warnings" ]]; then
        file_errors+=("=== YAML: IMPLICIT TYPES ===")
        file_errors+=("$implicit_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка embedded JSON...${NC}"
    fi
    local json_errors
    if ! json_errors=$(check_embedded_json "$file"); then
        file_errors+=("=== YAML: EMBEDDED JSON ===")
        file_errors+=("$json_errors")
    fi

    # === B17-B20: Additional YAML Semantics Checks (v2.7.0) ===

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка float без ведущего нуля...${NC}"
    fi
    local float_warnings
    float_warnings=$(check_float_leading_zero "$file")
    if [[ -n "$float_warnings" ]]; then
        file_errors+=("=== YAML: FLOAT LEADING ZERO ===")
        file_errors+=("$float_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка NaN/Infinity...${NC}"
    fi
    local special_float_warnings
    special_float_warnings=$(check_special_floats "$file" "$STRICT_MODE")
    if [[ -n "$special_float_warnings" ]]; then
        file_errors+=("=== YAML: SPECIAL FLOATS ===")
        file_errors+=("$special_float_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка глубины вложенности...${NC}"
    fi
    local nesting_warnings
    nesting_warnings=$(check_nesting_depth "$file" 10)
    if [[ -n "$nesting_warnings" ]]; then
        file_errors+=("=== YAML: NESTING DEPTH ===")
        file_errors+=("$nesting_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка Unicode...${NC}"
    fi
    local unicode_warnings
    unicode_warnings=$(check_unicode_normalization "$file")
    if [[ -n "$unicode_warnings" ]]; then
        file_errors+=("=== YAML: UNICODE ISSUES ===")
        file_errors+=("$unicode_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка network values...${NC}"
    fi
    local network_errors
    if ! network_errors=$(check_network_values "$file"); then
        file_errors+=("=== KUBERNETES: NETWORK VALUES ===")
        file_errors+=("$network_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка key naming...${NC}"
    fi
    local naming_warnings
    naming_warnings=$(check_key_naming "$file")
    if [[ -n "$naming_warnings" ]]; then
        file_errors+=("=== YAML: KEY NAMING ===")
        file_errors+=("$naming_warnings")
    fi

    # === NEW CHECKS v2.6.0 - PSS SECURITY ===

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка PSS Baseline...${NC}"
    fi
    local pss_baseline_warnings
    pss_baseline_warnings=$(check_pss_baseline "$file")
    if [[ -n "$pss_baseline_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: PSS BASELINE ===")
        file_errors+=("$pss_baseline_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка PSS Restricted...${NC}"
    fi
    local pss_restricted_warnings
    pss_restricted_warnings=$(check_pss_restricted "$file")
    if [[ -n "$pss_restricted_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: PSS RESTRICTED ===")
        file_errors+=("$pss_restricted_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка sensitive mounts...${NC}"
    fi
    local sensitive_mount_warnings
    sensitive_mount_warnings=$(check_sensitive_mounts "$file")
    if [[ -n "$sensitive_mount_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: SENSITIVE MOUNTS ===")
        file_errors+=("$sensitive_mount_warnings")
    fi

    # === D20: Writable hostPath (v2.7.0) ===
    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка writable hostPath...${NC}"
    fi
    local writable_hostpath_warnings
    writable_hostpath_warnings=$(check_writable_hostpath "$file")
    if [[ -n "$writable_hostpath_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: WRITABLE HOSTPATH ===")
        file_errors+=("$writable_hostpath_warnings")
    fi

    # === D23: drop NET_RAW capability (v2.7.0) ===
    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка drop NET_RAW...${NC}"
    fi
    local net_raw_warnings
    net_raw_warnings=$(check_drop_net_raw "$file")
    if [[ -n "$net_raw_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: DROP NET_RAW ===")
        file_errors+=("$net_raw_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка privileged ports...${NC}"
    fi
    local priv_port_warnings
    priv_port_warnings=$(check_privileged_ports "$file")
    if [[ -n "$priv_port_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: PRIVILEGED PORTS ===")
        file_errors+=("$priv_port_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка RBAC security...${NC}"
    fi
    local rbac_warnings
    rbac_warnings=$(check_rbac_security "$file")
    if [[ -n "$rbac_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: RBAC ===")
        file_errors+=("$rbac_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка secrets in env...${NC}"
    fi
    local secrets_env_warnings
    secrets_env_warnings=$(check_secrets_in_env "$file")
    if [[ -n "$secrets_env_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: SECRETS IN ENV ===")
        file_errors+=("$secrets_env_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка default ServiceAccount...${NC}"
    fi
    local default_sa_warnings
    default_sa_warnings=$(check_default_service_account "$file")
    if [[ -n "$default_sa_warnings" ]]; then
        file_errors+=("=== БЕЗОПАСНОСТЬ: SERVICE ACCOUNT ===")
        file_errors+=("$default_sa_warnings")
    fi

    # === YAMLLINT-COMPATIBLE CHECKS v2.6.0 ===

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка длины строк...${NC}"
    fi
    local line_length_warnings
    line_length_warnings=$(check_line_length "$file" 120)
    if [[ -n "$line_length_warnings" ]]; then
        file_errors+=("=== СТИЛЬ: LINE LENGTH ===")
        file_errors+=("$line_length_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка формата комментариев...${NC}"
    fi
    local comment_warnings
    comment_warnings=$(check_comment_format "$file")
    if [[ -n "$comment_warnings" ]]; then
        file_errors+=("=== СТИЛЬ: COMMENTS ===")
        file_errors+=("$comment_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка отступов комментариев...${NC}"
    fi
    local comment_indent_warnings
    comment_indent_warnings=$(check_comment_indentation "$file")
    if [[ -n "$comment_indent_warnings" ]]; then
        file_errors+=("=== СТИЛЬ: COMMENT INDENTATION ===")
        file_errors+=("$comment_indent_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка пустых строк...${NC}"
    fi
    local empty_line_warnings
    empty_line_warnings=$(check_empty_lines "$file" 2)
    if [[ -n "$empty_line_warnings" ]]; then
        file_errors+=("=== СТИЛЬ: EMPTY LINES ===")
        file_errors+=("$empty_line_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка newline в конце файла...${NC}"
    fi
    local eof_warnings
    eof_warnings=$(check_newline_at_eof "$file")
    if [[ -n "$eof_warnings" ]]; then
        file_errors+=("=== СТИЛЬ: NEWLINE AT EOF ===")
        file_errors+=("$eof_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка пробелов у двоеточий...${NC}"
    fi
    local colon_warnings
    colon_warnings=$(check_colons_spacing "$file")
    if [[ -n "$colon_warnings" ]]; then
        file_errors+=("=== СТИЛЬ: COLONS SPACING ===")
        file_errors+=("$colon_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка пробелов в скобках...${NC}"
    fi
    local bracket_warnings
    bracket_warnings=$(check_brackets_spacing "$file")
    if [[ -n "$bracket_warnings" ]]; then
        file_errors+=("=== СТИЛЬ: BRACKETS SPACING ===")
        file_errors+=("$bracket_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}└─ Проверка truthy values...${NC}"
    fi
    local truthy_warnings
    truthy_warnings=$(check_truthy_values "$file")
    if [[ -n "$truthy_warnings" ]]; then
        file_errors+=("=== YAML: TRUTHY VALUES ===")
        file_errors+=("$truthy_warnings")
    fi

    # A18: K8s key ordering (optional)
    if [[ $CHECK_KEY_ORDERING -eq 1 ]]; then
        if [[ $verbose -eq 1 ]]; then
            echo -e "  ${CYAN}├─ Проверка порядка ключей K8s...${NC}"
        fi
        local key_order_warnings
        key_order_warnings=$(check_key_ordering "$file")
        if [[ -n "$key_order_warnings" ]]; then
            file_errors+=("=== СТИЛЬ: KEY ORDERING ===")
            file_errors+=("$key_order_warnings")
        fi
    fi

    # C31-C33: Partial schema validation (optional)
    if [[ $CHECK_PARTIAL_SCHEMA -eq 1 ]]; then
        if [[ $verbose -eq 1 ]]; then
            echo -e "  ${CYAN}├─ Проверка типов полей...${NC}"
        fi
        local field_type_errors
        field_type_errors=$(check_field_types "$file")
        if [[ -n "$field_type_errors" ]]; then
            file_errors+=("=== СХЕМА: FIELD TYPES ===")
            file_errors+=("$field_type_errors")
        fi

        if [[ $verbose -eq 1 ]]; then
            echo -e "  ${CYAN}├─ Проверка enum значений...${NC}"
        fi
        local enum_errors
        enum_errors=$(check_enum_values "$file")
        if [[ -n "$enum_errors" ]]; then
            file_errors+=("=== СХЕМА: ENUM VALUES ===")
            file_errors+=("$enum_errors")
        fi

        if [[ $verbose -eq 1 ]]; then
            echo -e "  ${CYAN}├─ Проверка обязательных вложенных полей...${NC}"
        fi
        local required_errors
        required_errors=$(check_required_nested "$file")
        if [[ -n "$required_errors" ]]; then
            file_errors+=("=== СХЕМА: REQUIRED NESTED ===")
            file_errors+=("$required_errors")
        fi
    fi

    # E8-E19: Best practices checks
    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка HA (replicas >= 3)...${NC}"
    fi
    local ha_warnings
    ha_warnings=$(check_replicas_ha "$file")
    if [[ -n "$ha_warnings" ]]; then
        file_errors+=("=== BEST PRACTICE: HIGH AVAILABILITY ===")
        file_errors+=("$ha_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка anti-affinity...${NC}"
    fi
    local affinity_warnings
    affinity_warnings=$(check_anti_affinity "$file")
    if [[ -n "$affinity_warnings" ]]; then
        file_errors+=("=== BEST PRACTICE: ANTI-AFFINITY ===")
        file_errors+=("$affinity_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка rolling update strategy...${NC}"
    fi
    local strategy_warnings
    strategy_warnings=$(check_rolling_update "$file")
    if [[ -n "$strategy_warnings" ]]; then
        file_errors+=("=== BEST PRACTICE: UPDATE STRATEGY ===")
        file_errors+=("$strategy_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка дублирующихся env переменных...${NC}"
    fi
    local dup_env_warnings
    dup_env_warnings=$(check_duplicate_env "$file")
    if [[ -n "$dup_env_warnings" ]]; then
        file_errors+=("=== BEST PRACTICE: DUPLICATE ENV ===")
        file_errors+=("$dup_env_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка namespace...${NC}"
    fi
    local ns_warnings
    ns_warnings=$(check_missing_namespace "$file")
    if [[ -n "$ns_warnings" ]]; then
        file_errors+=("=== BEST PRACTICE: NAMESPACE ===")
        file_errors+=("$ns_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка priorityClassName...${NC}"
    fi
    local priority_warnings
    priority_warnings=$(check_priority_class "$file")
    if [[ -n "$priority_warnings" ]]; then
        file_errors+=("=== BEST PRACTICE: PRIORITY CLASS ===")
        file_errors+=("$priority_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка портов в probes...${NC}"
    fi
    local probe_port_warnings
    probe_port_warnings=$(check_probe_ports "$file")
    if [[ -n "$probe_port_warnings" ]]; then
        file_errors+=("=== BEST PRACTICE: PROBE PORTS ===")
        file_errors+=("$probe_port_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка ownership labels...${NC}"
    fi
    local owner_warnings
    owner_warnings=$(check_owner_label "$file")
    if [[ -n "$owner_warnings" ]]; then
        file_errors+=("=== BEST PRACTICE: OWNERSHIP LABELS ===")
        file_errors+=("$owner_warnings")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}└─ Проверка dangling resources...${NC}"
    fi
    local dangling_warnings
    dangling_warnings=$(check_dangling_resources "$file")
    if [[ -n "$dangling_warnings" ]]; then
        file_errors+=("=== BEST PRACTICE: DANGLING RESOURCES ===")
        file_errors+=("$dangling_warnings")
    fi

    # Add severity counts to totals
    add_to_totals

    # Build severity summary for this file
    local severity_summary=""
    [[ ${SEVERITY_COUNTS[ERROR]} -gt 0 ]] && severity_summary+=" E:${SEVERITY_COUNTS[ERROR]}"
    [[ ${SEVERITY_COUNTS[WARNING]} -gt 0 ]] && severity_summary+=" W:${SEVERITY_COUNTS[WARNING]}"
    [[ ${SEVERITY_COUNTS[INFO]} -gt 0 ]] && severity_summary+=" I:${SEVERITY_COUNTS[INFO]}"
    [[ ${SEVERITY_COUNTS[SECURITY]} -gt 0 ]] && severity_summary+=" S:${SEVERITY_COUNTS[SECURITY]}"

    if [[ ${#file_errors[@]} -eq 0 ]]; then
        echo -e "${GREEN}[✓ УСПЕХ]${NC} $file - ошибок не найдено"
        ((PASSED_FILES++))
        return 0
    else
        # Check if this should be a failure based on severity mode
        if file_has_errors; then
            echo -e "${RED}[✗ ОШИБКА]${NC} $file - обнаружены проблемы [${severity_summary# }]"
            ((FAILED_FILES++))
        else
            echo -e "${YELLOW}[⚠ ПРЕДУПРЕЖДЕНИЯ]${NC} $file - найдены замечания [${severity_summary# }]"
            ((PASSED_FILES++))
        fi
        ERRORS_FOUND+=("" "═══════════════════════════════════════════════════════════════════════")
        ERRORS_FOUND+=("ФАЙЛ: $file")
        ERRORS_FOUND+=("Severity: [${severity_summary# }] Mode: $SECURITY_MODE $([ $STRICT_MODE -eq 1 ] && echo "+STRICT")")
        ERRORS_FOUND+=("═══════════════════════════════════════════════════════════════════════")
        ERRORS_FOUND+=("${file_errors[@]}")

        file_has_errors && return 1 || return 0
    fi
}

find_yaml_files() {
    local dir="$1"
    local recursive="$2"
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
    printf '%s\n' "${files[@]}"
}

generate_report() {
    local output_file="$1"
    {
        echo "╔═══════════════════════════════════════════════════════════════════════╗"
        echo "║                    YAML VALIDATION REPORT                             ║"
        echo "╚═══════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Директория: $TARGET_DIR"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "СТАТИСТИКА"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Всего файлов проверено: $TOTAL_FILES"
        echo "Успешно:                $PASSED_FILES"
        echo "С ошибками:             $FAILED_FILES"
        echo ""

        if [[ ${#ERRORS_FOUND[@]} -gt 0 ]]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "ДЕТАЛЬНЫЙ ОТЧЁТ ОБ ОШИБКАХ"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            printf '%s\n' "${ERRORS_FOUND[@]}"
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "РЕКОМЕНДАЦИИ ПО ИСПРАВЛЕНИЮ"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "1. WINDOWS ENCODING (CRLF -> LF):"
            printf "   Команда: sed -i 's/\\r\$//' <файл>\n"
            echo ""
            echo "2. ТАБЫ -> ПРОБЕЛЫ:"
            echo "   Команда: expand -t 2 <файл> > <файл>.tmp && mv <файл>.tmp <файл>"
            echo ""
            echo "3. TRAILING WHITESPACE:"
            echo "   Команда: sed -i 's/[[:space:]]*$//' <файл>"
            echo ""
        else
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "✓ ВСЕ ФАЙЛЫ ПРОШЛИ ВАЛИДАЦИЮ УСПЕШНО"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        fi
        echo ""
        echo "Конец отчёта"
    } > "$output_file"
    echo -e "\n${GREEN}Отчёт сохранён в: $output_file${NC}"
}

main() {
    local target_dir=""
    local recursive=0
    local verbose=0
    local output_file="yaml_validation_report.txt"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -r|--recursive) recursive=1; shift ;;
            -v|--verbose) verbose=1; shift ;;
            -s|--strict) STRICT_MODE=1; shift ;;
            --security-mode)
                case "$2" in
                    strict|normal|permissive) SECURITY_MODE="$2" ;;
                    *) echo "Ошибка: --security-mode должен быть strict|normal|permissive"; exit 1 ;;
                esac
                shift 2
                ;;
            -o|--output) output_file="$2"; shift 2 ;;
            --key-ordering) CHECK_KEY_ORDERING=1; shift ;;
            --partial-schema) CHECK_PARTIAL_SCHEMA=1; shift ;;
            --all-checks) CHECK_KEY_ORDERING=1; CHECK_PARTIAL_SCHEMA=1; shift ;;
            -*) echo "Неизвестная опция: $1"; usage ;;
            *) target_dir="$1"; shift ;;
        esac
    done

    if [[ -z "$target_dir" ]]; then
        echo -e "${RED}Ошибка: Не указан файл или директория для проверки${NC}"
        usage
    fi

    if [[ ! -e "$target_dir" ]]; then
        echo -e "${RED}Ошибка: Файл или директория не существует: $target_dir${NC}"
        exit 1
    fi

    TARGET_DIR="$target_dir"

    print_header
    echo -e "${BOLD}Начинаю валидацию YAML файлов...${NC}"

    # Handle both files and directories
    if [[ -f "$target_dir" ]]; then
        echo -e "Файл: ${CYAN}$target_dir${NC}"
        yaml_files=("$target_dir")
    else
        echo -e "Директория: ${CYAN}$target_dir${NC}"
        echo -e "Режим: ${CYAN}$([ $recursive -eq 1 ] && echo "Рекурсивный" || echo "Только текущая директория")${NC}"
        echo -e "Безопасность: ${CYAN}$SECURITY_MODE${NC}$([ $STRICT_MODE -eq 1 ] && echo " + ${YELLOW}STRICT${NC}")"
        echo ""
        echo -e "${YELLOW}[ПОИСК]${NC} Сканирование файлов..."
        mapfile -t yaml_files < <(find_yaml_files "$target_dir" "$recursive")
    fi
    TOTAL_FILES=${#yaml_files[@]}

    if [[ $TOTAL_FILES -eq 0 ]]; then
        echo -e "${YELLOW}Предупреждение: YAML файлы не найдены${NC}"
        exit 0
    fi

    echo -e "${GREEN}Найдено файлов: $TOTAL_FILES${NC}"
    echo ""

    for file in "${yaml_files[@]}"; do
        validate_yaml_file "$file" "$verbose"
    done

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}ИТОГИ ВАЛИДАЦИИ${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Всего проверено:  ${BOLD}$TOTAL_FILES${NC} файлов"
    echo -e "Успешно:          ${GREEN}$PASSED_FILES${NC} файлов"
    echo -e "С ошибками:       ${RED}$FAILED_FILES${NC} файлов"
    echo ""

    generate_report "$output_file"

    if [[ $FAILED_FILES -gt 0 ]]; then
        echo -e "${RED}Валидация завершена с ошибками${NC}"
        exit 1
    else
        echo -e "${GREEN}Валидация успешно завершена${NC}"
        exit 0
    fi
}

main "$@"
