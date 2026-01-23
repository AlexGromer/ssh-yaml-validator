#!/bin/bash

#############################################################################
# YAML Validator for Air-Gapped Environments
# Pure bash implementation for Astra Linux SE 1.7 (Smolensk)
# Purpose: Validate YAML files in Kubernetes clusters without external tools
# Author: Generated for isolated environments
# Version: 2.1.0
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
    echo "║                    YAML Validator v2.1.0                              ║"
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
    declare -A keys_by_indent

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^---$ || "$line" =~ ^\.\.\.$ ]] && continue

        # Extract key and indent level
        if [[ "$line" =~ ^([[:space:]]*)([^:[:space:]]+|\"[^\"]+\"):[[:space:]] ]]; then
            local indent="${BASH_REMATCH[1]}"
            local key="${BASH_REMATCH[2]}"
            local indent_level=${#indent}

            # Remove quotes from key if present
            key="${key//\"/}"

            # Skip list items (lines starting with -)
            [[ "$key" =~ ^- ]] && continue

            # Create unique identifier for this indent level
            local level_key="${indent_level}_${key}"

            if [[ -n "${keys_by_indent[$level_key]}" ]]; then
                errors+=("Строка $line_num: Дубликат ключа '$key' на уровне отступа $indent_level")
                errors+=("  Первое определение: строка ${keys_by_indent[$level_key]}")
                errors+=("  Содержимое: ${line}")
            else
                keys_by_indent[$level_key]=$line_num
            fi
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

    # Deckhouse-specific fields
    # shellcheck disable=SC2034  # Dictionary for future validation features
    local -A deckhouse_fields=(
        ["deckhouse"]="top"
        ["nodeManager"]="deckhouse"
        ["prometheus"]="deckhouse"
        ["userAuthn"]="deckhouse"
        ["ingressNginx"]="deckhouse"
        ["certManager"]="deckhouse"
        ["cloudProviderOpenstack"]="deckhouse"
        ["cloudProviderAws"]="deckhouse"
        ["cloudProviderAzure"]="deckhouse"
        ["cloudProviderGcp"]="deckhouse"
        ["cloudProviderVsphere"]="deckhouse"
        ["cloudProviderYandex"]="deckhouse"
        ["nodeGroup"]="deckhouse"
        ["chaos"]="deckhouse"
        ["monitoring"]="deckhouse"
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
        echo -e "  ${CYAN}└─ Проверка Kubernetes полей и опечаток...${NC}"
    fi
    local k8s_errors
    if ! k8s_errors=$(check_kubernetes_specific "$file"); then
        file_errors+=("=== KUBERNETES: РАСШИРЕННАЯ ПРОВЕРКА ===")
        file_errors+=("$k8s_errors")
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
