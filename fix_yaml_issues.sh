#!/bin/bash

#############################################################################
# YAML Auto-Fix Script
# Автоматическое исправление простых ошибок в YAML файлах
# Для использования в закрытых контурах
# Version: 3.0.0
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
VERBOSE=0

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
)

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                    YAML Auto-Fix Tool v3.0.0                          ║"
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
    -i, --interactive       Интерактивный режим для сложных исправлений
    -v, --verbose           Подробный вывод
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

Примеры:
    $0 /path/to/manifests
    $0 config.yaml
    $0 -r -b /path/to/manifests
    $0 --dry-run /path/to/manifests
    $0 -i -r /path/to/manifests     # Интерактивный режим

EOF
    exit 0
}

create_backup() {
    local file="$1"
    cp "$file" "${file}.bak"
    echo -e "  ${BLUE}[BACKUP]${NC} Создана резервная копия: ${file}.bak"
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

    [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]
}

# Fix colon spacing: key:value -> key: value
fix_colon_spacing() {
    local file="$1"
    local dry_run="$2"
    local found=0

    # Check for key:value (no space after colon) but NOT for URLs or time formats
    if grep -qE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*:[^[:space:]:/]' "$file" 2>/dev/null; then
        found=1
        echo -e "  ${YELLOW}├─ Обнаружены пропущенные пробелы после двоеточий${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Fix key:value -> key: value, but not URLs (://) or ports (:80)
        sed -i 's/^\([[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*\):\([^[:space:]:/]\)/\1: \2/g' "$file"
        echo -e "  ${GREEN}├─ [✓] Добавлены пробелы после двоеточий${NC}"
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
    if awk '/^$/{c++;if(c>2)exit 0}!/^$/{c=0}END{exit 1}' "$file" 2>/dev/null; then
        found=1
        echo -e "  ${YELLOW}├─ Обнаружены лишние пустые строки (>2 подряд)${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Replace 3+ empty lines with 2
        awk 'BEGIN{blank=0} /^$/{blank++;if(blank<=2)print;next} {blank=0;print}' "$file" > "${file}.tmp.$$"
        mv "${file}.tmp.$$" "$file"
        echo -e "  ${GREEN}├─ [✓] Удалены лишние пустые строки${NC}"
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
        echo -e "  ${YELLOW}├─ Файл не заканчивается переводом строки${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        echo "" >> "$file"
        echo -e "  ${GREEN}├─ [✓] Добавлен перевод строки в конец файла${NC}"
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
        echo -e "  ${YELLOW}├─ Обнаружены пропущенные пробелы в массивах${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Add space after comma in arrays
        sed -i ':a;s/\(\[[^]]*\),\([^[:space:]]\)/\1, \2/;ta' "$file"
        echo -e "  ${GREEN}├─ [✓] Добавлены пробелы в массивах после запятых${NC}"
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
        echo -e "  ${YELLOW}├─ Обнаружены комментарии без пробела после #${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Add space after # in comments (but not ## or #!)
        sed -i 's/^\([[:space:]]*\)#\([^#[:space:]!]\)/\1# \2/' "$file"
        echo -e "  ${GREEN}├─ [✓] Добавлены пробелы в комментариях${NC}"
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
        echo -e "  ${YELLOW}├─ Обнаружены truthy values (yes/no/on/off)${NC}"
    fi

    if [[ $found -eq 1 && $dry_run -eq 0 ]]; then
        # Fix truthy values -> true/false
        sed -i -E 's/: *(yes|Yes|YES|on|On|ON|y|Y)[[:space:]]*$/: true/g' "$file"
        sed -i -E 's/: *(no|No|NO|off|Off|OFF|n|N)[[:space:]]*$/: false/g' "$file"
        echo -e "  ${GREEN}├─ [✓] Исправлены truthy values -> true/false${NC}"
        ((FIX_COUNTS[truthy]++))
    fi

    return $found
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

    echo -e "${CYAN}[ОБРАБОТКА]${NC} $file"

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

    # Calculate if we need to fix anything for basic checks
    local needs_basic_fix=0
    [[ $has_bom -eq 1 || $has_crlf -eq 1 || $has_tabs -eq 1 || $has_trailing -eq 1 || $has_booleans -eq 1 || $has_list_spacing -eq 1 || $has_doc_markers -eq 1 ]] && needs_basic_fix=1

    # Create backup if needed
    if [[ $needs_basic_fix -eq 1 && $dry_run -eq 0 && $backup -eq 1 ]]; then
        create_backup "$file"
    fi

    # Apply basic fixes
    if [[ $has_bom -eq 1 ]]; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i '1s/^\xEF\xBB\xBF//' "$file"
            echo -e "  ${GREEN}├─ [✓] Удален BOM${NC}"
            ((FIX_COUNTS[bom]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_crlf -eq 1 ]]; then
        if [[ $dry_run -eq 0 ]]; then
            local temp_file="${file}.tmp.$$"
            sed 's/\r$//' "$file" > "$temp_file"
            mv "$temp_file" "$file"
            echo -e "  ${GREEN}├─ [✓] CRLF -> LF${NC}"
            ((FIX_COUNTS[crlf]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_tabs -eq 1 ]]; then
        if [[ $dry_run -eq 0 ]]; then
            local temp_file="${file}.tmp.$$"
            expand -t 2 "$file" > "$temp_file"
            mv "$temp_file" "$file"
            echo -e "  ${GREEN}├─ [✓] Табы -> Пробелы${NC}"
            ((FIX_COUNTS[tabs]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_trailing -eq 1 ]]; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i 's/[[:space:]]*$//' "$file"
            echo -e "  ${GREEN}├─ [✓] Удалены trailing whitespace${NC}"
            ((FIX_COUNTS[trailing]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_booleans -eq 1 ]]; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i 's/: True$/: true/g; s/: FALSE$/: false/g; s/: TRUE$/: true/g; s/: False$/: false/g' "$file"
            echo -e "  ${GREEN}├─ [✓] Исправлен регистр boolean значений${NC}"
            ((FIX_COUNTS[booleans]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_list_spacing -eq 1 ]]; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i 's/^\([[:space:]]*\)-\([^[:space:]-]\)/\1- \2/' "$file"
            echo -e "  ${GREEN}├─ [✓] Добавлены пробелы после дефисов в списках${NC}"
            ((FIX_COUNTS[list_spacing]++))
        fi
        ((total_fixes++))
    fi

    if [[ $has_doc_markers -eq 1 ]]; then
        if [[ $dry_run -eq 0 ]]; then
            sed -i 's/^-\{4,\}$/---/g; s/^\.\{4,\}$/\.\.\./g' "$file"
            echo -e "  ${GREEN}├─ [✓] Исправлены маркеры документа${NC}"
            ((FIX_COUNTS[doc_markers]++))
        fi
        ((total_fixes++))
    fi

    # New safe fixes (8-13)
    fix_colon_spacing "$file" "$dry_run" && ((total_fixes++))
    fix_empty_lines "$file" "$dry_run" && ((total_fixes++))
    fix_eof_newline "$file" "$dry_run" && ((total_fixes++))
    fix_bracket_spacing "$file" "$dry_run" && ((total_fixes++))
    fix_comment_space "$file" "$dry_run" && ((total_fixes++))
    fix_truthy_values "$file" "$dry_run" && ((total_fixes++))

    # Interactive fixes
    if [[ $interactive -eq 1 ]]; then
        echo -e "  ${MAGENTA}[ИНТЕРАКТИВНЫЙ РЕЖИМ]${NC}"
        interactive_fix_security "$file" "$dry_run"
        interactive_fix_latest_tag "$file" "$dry_run"
        interactive_fix_namespace "$file" "$dry_run"
        interactive_fix_probes "$file" "$dry_run"
        interactive_fix_resources "$file" "$dry_run"
    fi

    if [[ $total_fixes -gt 0 ]]; then
        if [[ $dry_run -eq 1 ]]; then
            echo -e "  ${BLUE}└─ [DRY-RUN] Файл будет исправлен ($total_fixes проблем)${NC}"
        else
            echo -e "  ${GREEN}└─ [УСПЕХ] Файл исправлен ($total_fixes проблем)${NC}"
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
        echo -e "${YELLOW}Предупреждение: YAML файлы не найдены${NC}"
        exit 0
    fi

    echo -e "${BOLD}Найдено файлов: ${#files[@]}${NC}"
    echo ""

    for file in "${files[@]}"; do
        fix_file "$file" "$backup" "$dry_run" "$interactive"
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

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -r|--recursive) recursive=1; shift ;;
            -b|--backup) backup=1; shift ;;
            -n|--dry-run) dry_run=1; shift ;;
            -i|--interactive) INTERACTIVE=1; shift ;;
            -v|--verbose) VERBOSE=1; shift ;;
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

    if [[ $INTERACTIVE -eq 1 ]]; then
        echo -e "${MAGENTA}${BOLD}РЕЖИМ: ИНТЕРАКТИВНЫЙ (будут заданы вопросы)${NC}"
        echo ""
    fi

    echo -e "${BOLD}Начинаю обработку YAML файлов...${NC}"

    # Handle both files and directories
    if [[ -f "$target_dir" ]]; then
        echo -e "Файл: ${CYAN}$target_dir${NC}"
        echo -e "Backup: ${CYAN}$([ $backup -eq 1 ] && echo "Да" || echo "Нет")${NC}"
        echo ""

        fix_file "$target_dir" "$backup" "$dry_run" "$INTERACTIVE"
    else
        echo -e "Директория: ${CYAN}$target_dir${NC}"
        echo -e "Режим: ${CYAN}$([ $recursive -eq 1 ] && echo "Рекурсивный" || echo "Только текущая директория")${NC}"
        echo -e "Backup: ${CYAN}$([ $backup -eq 1 ] && echo "Да" || echo "Нет")${NC}"
        echo ""

        find_and_fix_files "$target_dir" "$recursive" "$backup" "$dry_run" "$INTERACTIVE"
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
        print_statistics
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
