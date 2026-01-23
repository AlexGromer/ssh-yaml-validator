#!/bin/bash

#############################################################################
# YAML Auto-Fix Script
# Автоматическое исправление простых ошибок в YAML файлах
# Для использования в закрытых контурах
# Version: 2.1.0
#############################################################################

set -o pipefail

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

FIXED_FILES=0
TOTAL_FILES=0

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                    YAML Auto-Fix Tool v2.1.0                          ║"
    echo "║              Автоматическое исправление YAML файлов                   ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

usage() {
    cat << EOF
Использование: $0 [ОПЦИИ] <файл_или_директория>

Опции:
    -r, --recursive         Рекурсивная обработка поддиректорий (только для директорий)
    -b, --backup            Создать резервные копии (*.yaml.bak)
    -n, --dry-run           Только показать, что будет сделано (не изменять файлы)
    -h, --help              Показать эту справку

Исправляемые проблемы:
    1. BOM (Byte Order Mark) - удаление невидимых символов в начале файла
    2. Windows encoding (CRLF -> LF)
    3. Табы -> пробелы (2 пробела на таб)
    4. Trailing whitespace
    5. Boolean регистр (True->true, False->false, TRUE->true, FALSE->false)
    6. List spacing (-item -> - item)
    7. Document markers (---- -> ---, ..... -> ...)

Примеры:
    $0 /path/to/manifests
    $0 config.yaml
    $0 -r -b /path/to/manifests
    $0 --dry-run /path/to/manifests

EOF
    exit 0
}

create_backup() {
    local file="$1"
    cp "$file" "${file}.bak"
    echo -e "  ${BLUE}[BACKUP]${NC} Создана резервная копия: ${file}.bak"
}

fix_file() {
    local file="$1"
    local backup="$2"
    local dry_run="$3"

    echo -e "${CYAN}[ОБРАБОТКА]${NC} $file"

    local has_bom=0
    local has_crlf=0
    local has_tabs=0
    local has_trailing=0
    local has_booleans=0
    local has_list_spacing=0
    local has_doc_markers=0

    # Check for BOM
    local first_bytes
    first_bytes=$(head -c 3 "$file" | od -An -tx1 | tr -d ' \n')
    if [[ "$first_bytes" == "efbbbf" ]]; then
        has_bom=1
        echo -e "  ${YELLOW}├─ Обнаружен BOM (Byte Order Mark)${NC}"
    fi

    if grep -q $'\r' "$file" 2>/dev/null; then
        has_crlf=1
        echo -e "  ${YELLOW}├─ Обнаружены CRLF (Windows encoding)${NC}"
    fi

    if grep -q $'\t' "$file" 2>/dev/null; then
        has_tabs=1
        echo -e "  ${YELLOW}├─ Обнаружены табы${NC}"
    fi

    if grep -q '[[:space:]]$' "$file" 2>/dev/null; then
        has_trailing=1
        echo -e "  ${YELLOW}├─ Обнаружены trailing whitespace${NC}"
    fi

    # Check for boolean case issues (True, False, TRUE, FALSE)
    if grep -qE ': *(True|TRUE|False|FALSE)[[:space:]]*$' "$file" 2>/dev/null; then
        has_booleans=1
        echo -e "  ${YELLOW}├─ Обнаружены boolean значения с неправильным регистром${NC}"
    fi

    # Check for list items without space (-item instead of - item)
    if grep -qE '^[[:space:]]*-[^[:space:]-]' "$file" 2>/dev/null; then
        has_list_spacing=1
        echo -e "  ${YELLOW}├─ Обнаружены элементы списка без пробела после дефиса${NC}"
    fi

    # Check for malformed document markers (----, ....., etc)
    if grep -qE '^-{4,}[[:space:]]*$|^\.{4,}[[:space:]]*$' "$file" 2>/dev/null; then
        has_doc_markers=1
        echo -e "  ${YELLOW}├─ Обнаружены некорректные маркеры документа${NC}"
    fi

    if [[ $has_bom -eq 1 || $has_crlf -eq 1 || $has_tabs -eq 1 || $has_trailing -eq 1 || $has_booleans -eq 1 || $has_list_spacing -eq 1 || $has_doc_markers -eq 1 ]]; then
        if [[ $dry_run -eq 1 ]]; then
            echo -e "  ${BLUE}└─ [DRY-RUN] Файл будет исправлен${NC}"
        else
            if [[ $backup -eq 1 ]]; then
                create_backup "$file"
            fi

            local temp_file="${file}.tmp.$$"

            if [[ $has_bom -eq 1 ]]; then
                # Remove BOM (first 3 bytes)
                sed -i '1s/^\xEF\xBB\xBF//' "$file"
                echo -e "  ${GREEN}├─ [✓] Удален BOM${NC}"
            fi

            if [[ $has_crlf -eq 1 ]]; then
                sed 's/\r$//' "$file" > "$temp_file"
                mv "$temp_file" "$file"
                echo -e "  ${GREEN}├─ [✓] CRLF -> LF${NC}"
            fi

            if [[ $has_tabs -eq 1 ]]; then
                expand -t 2 "$file" > "$temp_file"
                mv "$temp_file" "$file"
                echo -e "  ${GREEN}├─ [✓] Табы -> Пробелы${NC}"
            fi

            if [[ $has_trailing -eq 1 ]]; then
                sed -i 's/[[:space:]]*$//' "$file"
                echo -e "  ${GREEN}├─ [✓] Удалены trailing whitespace${NC}"
            fi

            if [[ $has_booleans -eq 1 ]]; then
                # Fix boolean case: True->true, False->false, TRUE->true, FALSE->false
                sed -i 's/: True$/: true/g; s/: FALSE$/: false/g; s/: TRUE$/: true/g; s/: False$/: false/g' "$file"
                echo -e "  ${GREEN}├─ [✓] Исправлен регистр boolean значений${NC}"
            fi

            if [[ $has_list_spacing -eq 1 ]]; then
                # Fix list spacing: -item -> - item
                sed -i 's/^\([[:space:]]*\)-\([^[:space:]-]\)/\1- \2/' "$file"
                echo -e "  ${GREEN}├─ [✓] Добавлены пробелы после дефисов в списках${NC}"
            fi

            if [[ $has_doc_markers -eq 1 ]]; then
                # Fix document markers: ---- -> ---, ..... -> ...
                sed -i 's/^-\{4,\}$/---/g; s/^\.\{4,\}$/\.\.\./g' "$file"
                echo -e "  ${GREEN}├─ [✓] Исправлены маркеры документа${NC}"
            fi

            echo -e "  ${GREEN}└─ [УСПЕХ] Файл исправлен${NC}"
            ((FIXED_FILES++))
        fi
    else
        echo -e "  ${GREEN}└─ [OK] Проблем не обнаружено${NC}"
    fi

    ((TOTAL_FILES++))
    echo ""
}

find_and_fix_files() {
    local dir="$1"
    local recursive="$2"
    local backup="$3"
    local dry_run="$4"
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
        echo -e "${YELLOW}Предупреждение: YAML файлы не найдены${NC}"
        exit 0
    fi

    echo -e "${BOLD}Найдено файлов: ${#files[@]}${NC}"
    echo ""

    for file in "${files[@]}"; do
        fix_file "$file" "$backup" "$dry_run"
    done
}

main() {
    local target_dir=""
    local recursive=0
    local backup=0
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -r|--recursive) recursive=1; shift ;;
            -b|--backup) backup=1; shift ;;
            -n|--dry-run) dry_run=1; shift ;;
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

    print_header

    if [[ $dry_run -eq 1 ]]; then
        echo -e "${YELLOW}${BOLD}РЕЖИМ: DRY-RUN (файлы не будут изменены)${NC}"
        echo ""
    fi

    echo -e "${BOLD}Начинаю обработку YAML файлов...${NC}"

    # Handle both files and directories
    if [[ -f "$target_dir" ]]; then
        echo -e "Файл: ${CYAN}$target_dir${NC}"
        echo -e "Backup: ${CYAN}$([ $backup -eq 1 ] && echo "Да" || echo "Нет")${NC}"
        echo ""

        fix_file "$target_dir" "$backup" "$dry_run"
    else
        echo -e "Директория: ${CYAN}$target_dir${NC}"
        echo -e "Режим: ${CYAN}$([ $recursive -eq 1 ] && echo "Рекурсивный" || echo "Только текущая директория")${NC}"
        echo -e "Backup: ${CYAN}$([ $backup -eq 1 ] && echo "Да" || echo "Нет")${NC}"
        echo ""

        find_and_fix_files "$target_dir" "$recursive" "$backup" "$dry_run"
    fi

    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}ИТОГИ${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Всего обработано: ${BOLD}$TOTAL_FILES${NC} файлов"

    if [[ $dry_run -eq 1 ]]; then
        echo -e "${YELLOW}Режим DRY-RUN: Изменения не применены${NC}"
    else
        echo -e "Исправлено:       ${GREEN}$FIXED_FILES${NC} файлов"
        echo ""
        if [[ $FIXED_FILES -gt 0 ]]; then
            echo -e "${GREEN}Рекомендация: Запустите валидатор для проверки результата:${NC}"
            echo -e "  ./yaml_validator.sh $([ $recursive -eq 1 ] && echo "-r") \"$target_dir\""
        else
            echo -e "${GREEN}Все файлы уже корректны!${NC}"
        fi
    fi
    echo ""
}

main "$@"
