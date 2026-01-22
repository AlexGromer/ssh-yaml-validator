#!/bin/bash

#############################################################################
# YAML Validator for Air-Gapped Environments
# Pure bash implementation for Astra Linux SE 1.7 (Smolensk)
# Purpose: Validate YAML files in Kubernetes clusters without external tools
# Author: Generated for isolated environments
# Version: 1.0.0
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
REPORT_FILE=""
ERRORS_FOUND=()

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                    YAML Validator v1.0.0                              ║"
    echo "║              Pure Bash Implementation for Air-Gapped Env              ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

usage() {
    cat << EOF
Использование: $0 [ОПЦИИ] <директория>

Опции:
    -o, --output FILE       Сохранить отчёт в файл (по умолчанию: yaml_validation_report.txt)
    -r, --recursive         Рекурсивный поиск YAML файлов
    -v, --verbose           Подробный вывод
    -h, --help              Показать эту справку

Примеры:
    $0 /path/to/manifests
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

check_indentation() {
    local file="$1"
    local line_num=0
    local errors=()
    local prev_indent=0
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
        prev_indent=$current_indent
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

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        [[ -z "$line" ]] && continue
        local trimmed_line="${line%%[[:space:]]}"
        [[ "$trimmed_line" =~ ^[[:space:]]*# ]] && continue

        local single_quotes=$(echo "$line" | grep -o "'" | wc -l)
        local double_quotes=$(echo "$line" | grep -o '"' | wc -l)

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

check_kubernetes_specific() {
    local file="$1"
    local errors=()
    local has_apiversion=0
    local has_kind=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^apiVersion:[[:space:]]* ]]; then
            has_apiversion=1
        fi
        if [[ "$line" =~ ^kind:[[:space:]]* ]]; then
            has_kind=1
        fi
    done < "$file"

    if [[ $has_apiversion -eq 0 ]]; then
        errors+=("ПРЕДУПРЕЖДЕНИЕ: Отсутствует поле 'apiVersion' (требуется для Kubernetes манифестов)")
    fi
    if [[ $has_kind -eq 0 ]]; then
        errors+=("ПРЕДУПРЕЖДЕНИЕ: Отсутствует поле 'kind' (требуется для Kubernetes манифестов)")
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

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка кодировки Windows (CRLF)...${NC}"
    fi
    local encoding_errors
    encoding_errors=$(check_windows_encoding "$file")
    if [[ $? -ne 0 ]]; then
        file_errors+=("=== ОШИБКИ КОДИРОВКИ ===")
        file_errors+=("$encoding_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка табов...${NC}"
    fi
    local tab_errors
    tab_errors=$(check_tabs "$file")
    if [[ $? -ne 0 ]]; then
        file_errors+=("=== ОШИБКИ ТАБОВ ===")
        file_errors+=("$tab_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка пробелов в конце строк...${NC}"
    fi
    local trailing_errors
    trailing_errors=$(check_trailing_whitespace "$file")
    if [[ $? -ne 0 ]]; then
        file_errors+=("=== ПРЕДУПРЕЖДЕНИЯ: TRAILING WHITESPACE ===")
        file_errors+=("$trailing_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка отступов...${NC}"
    fi
    local indent_errors
    indent_errors=$(check_indentation "$file")
    if [[ $? -ne 0 ]]; then
        file_errors+=("=== ОШИБКИ ОТСТУПОВ ===")
        file_errors+=("$indent_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}├─ Проверка синтаксиса...${NC}"
    fi
    local syntax_errors
    syntax_errors=$(check_basic_syntax "$file")
    if [[ $? -ne 0 ]]; then
        file_errors+=("=== ОШИБКИ СИНТАКСИСА ===")
        file_errors+=("$syntax_errors")
    fi

    if [[ $verbose -eq 1 ]]; then
        echo -e "  ${CYAN}└─ Проверка Kubernetes полей...${NC}"
    fi
    local k8s_errors
    k8s_errors=$(check_kubernetes_specific "$file")
    if [[ $? -ne 0 ]]; then
        file_errors+=("=== KUBERNETES ПРЕДУПРЕЖДЕНИЯ ===")
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
            echo "   Команда: sed -i 's/\r$//' <файл>"
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
        echo -e "${RED}Ошибка: Не указана директория для проверки${NC}"
        usage
    fi

    if [[ ! -d "$target_dir" ]]; then
        echo -e "${RED}Ошибка: Директория не существует: $target_dir${NC}"
        exit 1
    fi

    TARGET_DIR="$target_dir"
    REPORT_FILE="$output_file"

    print_header
    echo -e "${BOLD}Начинаю валидацию YAML файлов...${NC}"
    echo -e "Директория: ${CYAN}$target_dir${NC}"
    echo -e "Режим: ${CYAN}$([ $recursive -eq 1 ] && echo "Рекурсивный" || echo "Только текущая директория")${NC}"
    echo ""

    echo -e "${YELLOW}[ПОИСК]${NC} Сканирование файлов..."
    mapfile -t yaml_files < <(find_yaml_files "$target_dir" "$recursive")
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
