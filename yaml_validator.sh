#!/bin/bash

#############################################################################
# YAML Validator for Air-Gapped Environments
# Pure bash implementation for Astra Linux SE 1.7 (Smolensk)
# Purpose: Validate YAML files in Kubernetes clusters without external tools
# Author: Generated for isolated environments
# Version: 2.4.0
# Updated: 2026-01-23
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

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                    YAML Validator v2.4.0                              ║"
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
    -h, --help              Показать эту справку

Примеры:
    $0 /path/to/manifests
    $0 config.yaml
    $0 -r -o report.txt /path/to/manifests
    $0 --recursive --verbose /home/user/k8s/

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

validate_yaml_file() {
    local file="$1"
    local verbose="$2"
    local file_errors=()

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
        echo -e "  ${CYAN}└─ Проверка CronJob schedule...${NC}"
    fi
    local cronjob_errors
    if ! cronjob_errors=$(check_cronjob_schedule "$file"); then
        file_errors+=("=== KUBERNETES: CRONJOB ===")
        file_errors+=("$cronjob_errors")
    fi

    if [[ ${#file_errors[@]} -eq 0 ]]; then
        echo -e "${GREEN}[✓ УСПЕХ]${NC} $file - ошибок не найдено"
        ((PASSED_FILES++))
        return 0
    else
        echo -e "${RED}[✗ ОШИБКА]${NC} $file - обнаружены проблемы"
        ((FAILED_FILES++))
        ERRORS_FOUND+=("" "═══════════════════════════════════════════════════════════════════════")
        ERRORS_FOUND+=("ФАЙЛ: $file")
        ERRORS_FOUND+=("═══════════════════════════════════════════════════════════════════════")
        ERRORS_FOUND+=("${file_errors[@]}")
        return 1
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
            -o|--output) output_file="$2"; shift 2 ;;
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
