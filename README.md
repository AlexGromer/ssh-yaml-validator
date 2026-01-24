# YAML Validator для изолированных контуров

**Version: 2.8.0** | Pure Bash | Zero Dependencies | **Coverage: 99.4%**

Валидатор YAML файлов для закрытых сред без доступа к интернету и возможности установки дополнительных утилит.

## Назначение

Валидатор предназначен для проверки YAML манифестов Kubernetes (и других YAML файлов) в закрытых контурах на Astra Linux SE 1.7 Smolensk, где работа ведётся с кластером Deckhouse и нет возможности установить дополнительные утилиты типа `yamllint`, `yq` и т.д.

## Ключевые особенности

- **124 проверки** в 5 категориях (YAML Syntax, Semantics, K8s Base, Security, Best Practices)
- **Система severity levels** — ERROR, WARNING, INFO, SECURITY
- **Режимы безопасности** — strict, normal, permissive
- **Чистый Bash** — никаких внешних зависимостей
- **Детальный вывод** — указывает номера строк и как исправить
- **Автоматическое исправление** — 13 типов ошибок + интерактивный режим
- **Поддержка Deckhouse CRD** — валидация enum-значений
- **yamllint-совместимость** — проверки аналогичные yamllint

---

## Быстрый старт

```bash
# Установка
git clone https://github.com/AlexGromer/ssh-yaml-validator.git
cd ssh-yaml-validator
chmod +x yaml_validator.sh fix_yaml_issues.sh

# Проверить файл
./yaml_validator.sh config.yaml

# Проверить директорию
./yaml_validator.sh /path/to/manifests

# Строгий режим (WARNING → ERROR)
./yaml_validator.sh --strict /path/to/manifests

# Режим безопасности для production
./yaml_validator.sh --security-mode strict /path/to/manifests

# Все проверки включая опциональные
./yaml_validator.sh --all-checks /path/to/manifests

# Автоматическое исправление
./fix_yaml_issues.sh config.yaml

# Интерактивный режим (для security fixes)
./fix_yaml_issues.sh -i config.yaml
```

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         YAML VALIDATOR WORKFLOW v2.8.0                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐    │
│   │  yaml_validator  │     │   fix_yaml_      │     │   Validation     │    │
│   │      .sh         │     │    issues.sh     │     │    Report        │    │
│   │                  │     │     v3.0.0       │     │     (.txt)       │    │
│   │  • 124 проверки  │     │  • 13 авто-      │     │  • Статистика    │    │
│   │  • Severity      │────▶│    исправлений   │────▶│  • Ошибки        │    │
│   │  • Security mode │     │  • Interactive   │     │  • Рекомендации  │    │
│   │                  │     │  • Dry-run       │     │                  │    │
│   └──────────────────┘     └──────────────────┘     └──────────────────┘    │
│                                                                              │
│   ВАЖНО: Скрипты работают НЕЗАВИСИМО                                        │
│          Валидатор НЕ редактирует файлы                                     │
│          Fix script имеет интерактивный режим (-i)                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Система Severity Levels (v2.7.0+)

### Уровни серьёзности

| Level | Описание | Поведение |
|-------|----------|-----------|
| **ERROR** | Критические ошибки | Всегда fail |
| **WARNING** | Должны быть исправлены | Fail в `--strict` |
| **INFO** | Стиль/информация | Никогда не fail |
| **SECURITY** | Проблемы безопасности | Зависит от `--security-mode` |

### Режимы безопасности

```bash
# Production (SECURITY = ERROR)
./yaml_validator.sh --security-mode strict manifests/

# Default (SECURITY = WARNING)
./yaml_validator.sh --security-mode normal manifests/

# Test/Dev (SECURITY = INFO)
./yaml_validator.sh --security-mode permissive manifests/
```

---

## Полный список проверок (124 шт.)

### A. YAML Syntax (22 проверки) — 100%

| # | Проверка | Описание |
|---|----------|----------|
| A1 | `check_bom` | BOM (Byte Order Mark) в начале файла |
| A2 | `check_windows_encoding` | Windows CRLF вместо Unix LF |
| A3 | `check_tabs` | Табы вместо пробелов |
| A4 | `check_trailing_whitespace` | Пробелы в конце строк |
| A5 | `check_indentation` | Консистентность отступов |
| A6 | `check_empty_file` | Пустые файлы без содержимого |
| A7 | `check_document_markers` | Маркеры `---` и `...` |
| A8 | `check_duplicate_keys` | Дубликаты ключей |
| A9 | `check_empty_keys` | Пустые ключи |
| A10-11 | `check_basic_syntax` | Кавычки, скобки, двоеточия |
| A12 | `check_colons_spacing` | Пробелы после двоеточий |
| A13 | `check_comment_format` | Формат комментариев |
| A14 | `check_comment_indentation` | Отступы комментариев |
| A15 | `check_line_length` | Длина строк (>200) |
| A16 | `check_empty_lines` | Множественные пустые строки |
| A17 | `check_newline_at_eof` | Перенос строки в конце файла |
| A18 | `check_key_ordering` | Порядок ключей K8s (опционально) |
| A19 | `check_multiline_blocks` | Блоки `\|` и `>` |
| A20 | `check_flow_style` | Flow style `{}` и `[]` |
| A21 | `check_brackets_spacing` | Пробелы в скобках |
| A22 | `check_truthy_values` | yamllint truthy правило |

### B. YAML Semantics (20 проверок) — 100%

| # | Проверка | Описание |
|---|----------|----------|
| B1 | `check_special_values` | Boolean-like: `yes/no/on/off` |
| B2 | `check_extended_norway` | Norway Problem: `NO` → `false` |
| B3 | `check_null_values` | NULL варианты: `~`, `Null`, `NULL` |
| B4-5 | `check_numeric_formats` | Octal (`0644`), Hex (`0xFF`) |
| B6 | `check_sexagesimal` | Base-60: `21:00` → `1260` |
| B7-8 | `check_implicit_types` | Scientific notation, Infinity/NaN |
| B9 | `check_timestamp_values` | ISO8601 даты без кавычек |
| B10 | `check_version_numbers` | Версии как float: `1.0` → `1` |
| B11-12 | `check_anchors_aliases` | Anchors `&name` и Aliases `*name` |
| B13 | `check_merge_keys` | Merge keys `<<:` валидация |
| B14 | `check_yaml_bomb` | Billion Laughs Attack detection |
| B15 | `check_string_quoting` | Спецсимволы требующие кавычек |
| B16 | `check_embedded_json` | JSON синтаксис внутри YAML |
| B17 | `check_float_leading_zero` | Float без ведущего нуля |
| B18 | `check_special_floats` | Явный запрет .inf/.nan |
| B19 | `check_nesting_depth` | Максимальная глубина вложенности |
| B20 | `check_unicode_normalization` | Unicode нормализация |

### C. Kubernetes Base (32 проверки) — 97%

| # | Проверка | Описание |
|---|----------|----------|
| C1-5 | `check_kubernetes_specific` | apiVersion, kind, metadata, spec |
| C6 | `check_label_format` | RFC 1123 формат меток |
| C7 | `check_annotation_length` | Длина аннотаций ≤256KB |
| C8 | `check_dns_names` | DNS-совместимые имена |
| C9 | `check_container_name` | Валидные имена контейнеров |
| C10 | `check_resource_quantities` | CPU: `100m`, Memory: `128Mi` |
| C11 | `check_port_ranges` | Порты 1-65535 |
| C12-13 | `check_network_values` | Protocol, IP/CIDR format |
| C14 | `check_deprecated_api` | Устаревшие API versions |
| C15 | `check_selector_match` | selector ↔ template.labels |
| C16 | `check_service_selector` | Service → Pod matching |
| C17 | `check_configmap_keys` | Валидные ключи ConfigMap |
| C18 | `check_ingress_rules` | Ingress path/host валидация |
| C19 | `check_cronjob_schedule` | Cron формат, concurrency |
| C20 | `check_hpa_config` | HPA min/max replicas |
| C21 | `check_pdb_config` | PodDisruptionBudget |
| C22 | `check_base64_in_secrets` | Base64 валидация в Secrets |
| C23 | `check_env_vars` | Валидация переменных окружения |
| C24 | `check_replicas_type` | replicas: integer |
| C25 | `check_image_pull_policy` | Always/IfNotPresent/Never |
| C26 | `check_restart_policy` | Always/OnFailure/Never |
| C27 | `check_service_type` | ClusterIP/NodePort/LoadBalancer |
| C28 | `check_probe_config` | liveness/readiness probes |
| C29 | `check_kubernetes_specific` | Field name typos (snake→camel) |
| C31 | `check_field_types` | Типы полей (опционально) |
| C32 | `check_enum_values` | Enum значения (опционально) |
| C33 | `check_required_nested` | Обязательные вложенные поля (опционально) |

### D. Kubernetes Security (30 проверок) — 100%

| # | Проверка | PSS Level | Описание |
|---|----------|-----------|----------|
| D1-3 | `check_security_best_practices` | Baseline | hostNetwork/PID/IPC: false |
| D4-5 | `check_security_best_practices` | Baseline | privileged, hostPath |
| D6-7 | `check_pss_baseline` | Baseline | hostPort, capabilities |
| D8-12 | `check_pss_baseline` | Baseline | procMount, sysctls, AppArmor, SELinux |
| D13-14 | `check_security_context` | Restricted | allowPrivilegeEscalation, runAsNonRoot |
| D15-17 | `check_pss_restricted` | Restricted | runAsUser, volumes, seccomp |
| D18-19 | `check_sensitive_mounts` | kube-linter | docker.sock, sensitive mounts |
| D20 | `check_writable_hostpath` | kube-linter | Writable host mounts |
| D21-22 | `check_privileged_ports` | kube-linter | SSH port, ports <1024 |
| D23 | `check_drop_net_raw` | kube-linter | NET_RAW capability drop |
| D24 | `check_security_context` | kube-linter | readOnlyRootFilesystem |
| D25 | `check_volume_mounts` | CVE | CVE-2023-3676 subPath |
| D26 | `check_secrets_in_env` | kube-linter | Secrets в env vars |
| D27 | `check_default_service_account` | kube-linter | Default service account |
| D28-30 | `check_rbac_security` | CIS | cluster-admin, wildcards, secrets |

### E. Kubernetes Best Practices (20 проверок) — 100%

| # | Проверка | Описание |
|---|----------|----------|
| E1 | `check_image_tags` | Image :latest tag warning |
| E2-3 | `check_probe_config` | liveness/readiness probes |
| E4-7 | `check_resource_format` | CPU/Memory requests/limits |
| E8 | `check_replicas_ha` | Replicas < 3 warning (HA) |
| E9 | `check_anti_affinity` | Missing podAntiAffinity |
| E10 | `check_rolling_update` | Rolling update strategy |
| E11-14 | `check_dangling_resources` | Dangling Service/Ingress/HPA/NetworkPolicy |
| E15 | `check_duplicate_env` | Duplicate env vars |
| E16 | `check_missing_namespace` | Missing namespace |
| E17 | `check_priority_class` | Priority class not set |
| E18 | `check_probe_ports` | Probe ports validation |
| E19 | `check_owner_label` | Missing owner label |
| E20 | `check_deckhouse_crd` | Deckhouse CRD validation |

---

## Автоматическое исправление (13 типов)

Скрипт `fix_yaml_issues.sh` v3.0.0 автоматически исправляет:

| # | Проблема | Исправление |
|---|----------|-------------|
| 1 | BOM | Удаление UTF-8 BOM |
| 2 | CRLF | Windows → Unix line endings |
| 3 | Табы | Табы → 2 пробела |
| 4 | Trailing whitespace | Удаление пробелов в конце строк |
| 5 | Boolean регистр | `True` → `true`, `False` → `false` |
| 6 | List spacing | `-item` → `- item` |
| 7 | Document markers | `----` → `---`, `.....` → `...` |
| 8 | Colon spacing | `key:value` → `key: value` |
| 9 | Empty lines | 3+ пустые строки → 2 |
| 10 | EOF newline | Добавление newline в конец файла |
| 11 | Bracket spacing | `[item]` → `[ item ]` (опционально) |
| 12 | Comment space | `#comment` → `# comment` |
| 13 | Truthy values | `yes/no/on/off` → `true/false` |

### Использование

```bash
# Просмотр изменений (dry-run)
./fix_yaml_issues.sh -n /path/to/files

# Исправление с backup
./fix_yaml_issues.sh -b /path/to/files

# Интерактивный режим (подтверждение каждого изменения)
./fix_yaml_issues.sh -i /path/to/files

# Рекурсивно
./fix_yaml_issues.sh -r /path/to/directory

# Все опции
./fix_yaml_issues.sh -r -b -i -n /path/to/files
```

---

## Опции командной строки

### yaml_validator.sh

```
Использование: ./yaml_validator.sh [ОПЦИИ] <файл_или_директория>

Основные опции:
    -o, --output FILE       Сохранить отчёт в файл
    -r, --recursive         Рекурсивный поиск YAML файлов
    -v, --verbose           Подробный вывод
    -h, --help              Показать справку

Severity контроль:
    -s, --strict            Строгий режим: WARNING → ERROR
    --security-mode MODE    strict|normal|permissive

Опциональные проверки:
    --key-ordering          Проверка порядка ключей K8s
    --partial-schema        Частичная валидация схемы
    --all-checks            Включить все опциональные проверки
```

### fix_yaml_issues.sh

```
Использование: ./fix_yaml_issues.sh [ОПЦИИ] <файл_или_директория>

Опции:
    -r, --recursive         Рекурсивная обработка
    -b, --backup            Создать backup (.bak)
    -n, --dry-run           Только показать изменения
    -i, --interactive       Интерактивный режим (подтверждение)
    -h, --help              Показать справку
```

---

## Exit Codes

| Code | Значение |
|------|----------|
| 0 | Все файлы валидны |
| 1 | Обнаружены ошибки |

---

## Требования

- **ОС**: Astra Linux SE 1.7 (Smolensk), любой Linux, macOS
- **Bash**: 4.0+
- **Зависимости**: ТОЛЬКО стандартные утилиты (grep, sed, awk, od, head)

---

## Changelog

### v2.8.0 (2026-01-24)
- **Coverage: 99.4%** (+11.25%)
- Добавлено 12 новых проверок best practices (E8-E19)
- Частичная валидация схемы (C31-C33, опционально)
- Проверка порядка ключей K8s (A18, опционально)
- Auto-fixer v3.0.0: 13 типов исправлений + интерактивный режим
- Новые CLI опции: `--key-ordering`, `--partial-schema`, `--all-checks`

### v2.7.0 (2026-01-24)
- Система severity levels (ERROR/WARNING/INFO/SECURITY)
- Security modes: strict, normal, permissive
- Добавлены A14, B17-B20, D20, D23

### v2.6.0 (2026-01-24)
- **Coverage: 82.2%** (+19%)
- PSS Baseline/Restricted проверки (D1-D17)
- RBAC security (D28-D30)
- yamllint-совместимые проверки
- Sensitive mounts detection

### v2.5.0 (2026-01-23)
- 7 новых проверок type coercion
- Embedded JSON validation
- Network values validation

### v2.4.0 - v2.1.0
- Kubernetes base checks
- Deckhouse CRD support
- Edge case handling

---

## Документация

- [COVERAGE_ANALYSIS.md](COVERAGE_ANALYSIS.md) — Детальный анализ покрытия
- [ROADMAP.md](ROADMAP.md) — Планы развития (Ansible, Helm, GitLab CI, etc.)

---

## Лицензия

MIT License

---

## Авторы

- [AlexGromer](https://github.com/AlexGromer)
- AI-assisted development

---

## Поддержка

Issues: https://github.com/AlexGromer/ssh-yaml-validator/issues
