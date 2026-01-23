# YAML Validator для изолированных контуров

**Version: 2.5.0** | Pure Bash | Zero Dependencies

Валидатор YAML файлов для закрытых сред без доступа к интернету и возможности установки дополнительных утилит.

## Назначение

Валидатор предназначен для проверки YAML манифестов Kubernetes (и других YAML файлов) в закрытых контурах на Astra Linux SE 1.7 Smolensk, где работа ведётся с кластером Deckhouse и нет возможности установить дополнительные утилиты типа `yamllint`, `yq` и т.д.

## Ключевые особенности

- **54 проверки** различных категорий
- **Чистый Bash** — никаких внешних зависимостей
- **Детальный вывод** — указывает номера строк и как исправить
- **Автоматическое исправление** — 7 типов ошибок (отдельный скрипт)
- **Поддержка Deckhouse CRD** — валидация enum-значений

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

# Рекурсивная проверка с verbose
./yaml_validator.sh -r -v /path/to/manifests

# Автоматическое исправление
./fix_yaml_issues.sh config.yaml
```

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         YAML VALIDATOR WORKFLOW                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐    │
│   │  yaml_validator  │     │   fix_yaml_      │     │   Validation     │    │
│   │      .sh         │     │    issues.sh     │     │    Report        │    │
│   │                  │     │                  │     │     (.txt)       │    │
│   │  • 54 проверки   │     │  • 7 авто-       │     │  • Статистика    │    │
│   │  • Отчёт ошибок  │────▶│    исправлений   │────▶│  • Ошибки        │    │
│   │  • Exit codes    │     │  • Dry-run       │     │  • Рекомендации  │    │
│   │                  │     │  • Backup        │     │                  │    │
│   └──────────────────┘     └──────────────────┘     └──────────────────┘    │
│                                                                              │
│   ВАЖНО: Скрипты работают НЕЗАВИСИМО                                        │
│          Валидатор НЕ редактирует файлы                                     │
│          Fix script НЕ спрашивает разрешения (используйте --dry-run)        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Алгоритм работы для пользователя

### Шаг 1: Валидация

```bash
./yaml_validator.sh -v /path/to/manifests
```

Валидатор:
1. Сканирует все `.yaml` и `.yml` файлы
2. Выполняет **54 проверки** на каждом файле
3. Выводит **номера строк** с проблемами
4. Показывает **что именно не так** и **как исправить**
5. Генерирует отчёт `yaml_validation_report.txt`

**Пример вывода:**
```
[ПРОВЕРЯЮ] config.yaml
  ├─ Проверка BOM (Byte Order Mark)...
  ├─ Проверка кодировки Windows (CRLF)...
  ├─ Проверка табов...
  └─ ...

[✗ ОШИБКА] config.yaml - обнаружены проблемы

=== ОШИБКИ КОДИРОВКИ ===
Строка 15: Обнаружены табы. YAML требует пробелы для отступов
  Содержимое:     name: myapp

=== KUBERNETES: ВАЛИДАЦИЯ ===
Строка 23: imagePullPolicy должен быть: Always, IfNotPresent, Never
  Найдено: always (регистр!)
```

### Шаг 2: Просмотр исправлений (опционально)

```bash
./fix_yaml_issues.sh -n /path/to/manifests   # Dry-run — только показать
```

### Шаг 3: Автоматическое исправление

```bash
./fix_yaml_issues.sh -b /path/to/manifests   # С backup
```

### Шаг 4: Повторная валидация

```bash
./yaml_validator.sh /path/to/manifests       # Проверить результат
```

---

## Полный список проверок (54 шт.)

### Категория 1: Критические ошибки

| # | Проверка | Описание |
|---|----------|----------|
| 1 | `check_bom` | BOM (Byte Order Mark) в начале файла |
| 2 | `check_empty_file` | Пустые файлы без содержимого |
| 3 | `check_windows_encoding` | Windows CRLF вместо Unix LF |

### Категория 2: Форматирование

| # | Проверка | Описание |
|---|----------|----------|
| 4 | `check_tabs` | Табы вместо пробелов |
| 5 | `check_trailing_whitespace` | Пробелы в конце строк |
| 6 | `check_indentation` | Консистентность отступов |
| 7 | `check_document_markers` | Маркеры `---` и `...` |

### Категория 3: Синтаксис YAML

| # | Проверка | Описание |
|---|----------|----------|
| 8 | `check_basic_syntax` | Кавычки, скобки, двоеточия |
| 9 | `check_empty_keys` | Пустые ключи |
| 10 | `check_duplicate_keys` | Дубликаты ключей |
| 11 | `check_multiline_blocks` | Блоки `\|` и `>` |
| 12 | `check_flow_style` | Flow style `{}` и `[]` |

### Категория 4: YAML 1.1 Edge Cases

| # | Проверка | Описание |
|---|----------|----------|
| 13 | `check_special_values` | Boolean-like: `yes/no/on/off` |
| 14 | `check_null_values` | NULL варианты: `~`, `Null`, `NULL` |
| 15 | `check_sexagesimal` | Base-60: `21:00` → `1260` |
| 16 | `check_extended_norway` | Norway Problem: `NO` → `false` |
| 17 | `check_numeric_formats` | Octal (`0644`), Hex (`0xFF`) |
| 18 | `check_string_quoting` | Спецсимволы требующие кавычек |

### Категория 5: YAML Anchors & Aliases

| # | Проверка | Описание |
|---|----------|----------|
| 19 | `check_anchors_aliases` | Anchors `&name` и Aliases `*name` |
| 20 | `check_yaml_bomb` | Billion Laughs Attack detection |
| 21 | `check_merge_keys` | Merge keys `<<:` валидация |

### Категория 6: Kubernetes Base

| # | Проверка | Описание |
|---|----------|----------|
| 22 | `check_kubernetes_specific` | apiVersion, kind, metadata, spec |
| 23 | `check_label_format` | RFC 1123 формат меток |
| 24 | `check_annotation_length` | Длина аннотаций ≤256KB |
| 25 | `check_dns_names` | DNS-совместимые имена |
| 26 | `check_container_name` | Валидные имена контейнеров |

### Категория 7: Kubernetes Resources

| # | Проверка | Описание |
|---|----------|----------|
| 27 | `check_resource_quantities` | CPU: `100m`, Memory: `128Mi` |
| 28 | `check_resource_format` | requests ≤ limits |
| 29 | `check_port_ranges` | Порты 1-65535 |
| 30 | `check_replicas_type` | replicas: integer |

### Категория 8: Kubernetes Workloads

| # | Проверка | Описание |
|---|----------|----------|
| 31 | `check_image_tags` | Предупреждение о `:latest` |
| 32 | `check_image_pull_policy` | Always/IfNotPresent/Never |
| 33 | `check_probe_config` | liveness/readiness probes |
| 34 | `check_restart_policy` | Always/OnFailure/Never |
| 35 | `check_env_vars` | Валидация переменных окружения |

### Категория 9: Kubernetes Controllers

| # | Проверка | Описание |
|---|----------|----------|
| 36 | `check_selector_match` | selector ↔ template.labels |
| 37 | `check_hpa_config` | HPA min/max replicas |
| 38 | `check_pdb_config` | PodDisruptionBudget |
| 39 | `check_cronjob_schedule` | Cron формат, concurrency |

### Категория 10: Kubernetes Networking

| # | Проверка | Описание |
|---|----------|----------|
| 40 | `check_service_type` | ClusterIP/NodePort/LoadBalancer |
| 41 | `check_service_selector` | Service → Pod matching |
| 42 | `check_ingress_rules` | Ingress path/host валидация |
| 43 | `check_network_values` | IP, CIDR, Protocol |

### Категория 11: Kubernetes Config

| # | Проверка | Описание |
|---|----------|----------|
| 44 | `check_base64_in_secrets` | Base64 валидация в Secrets |
| 45 | `check_configmap_keys` | Валидные ключи ConfigMap |
| 46 | `check_volume_mounts` | CVE-2023-3676 subPath injection |

### Категория 12: Kubernetes Security

| # | Проверка | Описание |
|---|----------|----------|
| 47 | `check_security_context` | runAsNonRoot, capabilities |
| 48 | `check_security_best_practices` | privileged, hostPID, hostNetwork |
| 49 | `check_deprecated_api` | Устаревшие API versions |

### Категория 13: Deckhouse CRD

| # | Проверка | Описание |
|---|----------|----------|
| 50 | `check_deckhouse_crd` | Полная валидация Deckhouse CRD |

**Поддерживаемые Deckhouse CRD:**
- `ModuleConfig` — version (integer), enabled (boolean)
- `NodeGroup` — nodeType enum: CloudEphemeral, CloudPermanent, CloudStatic, Static
- `IngressNginxController` — inlet enum: LoadBalancer, HostPort, etc.
- `ClusterAuthorizationRule` — accessLevel enum: User → SuperAdmin
- `ClusterLogDestination` — type enum: Loki, Elasticsearch, etc.
- `VirtualMachine` — runPolicy, osType, bootloader enums
- `DexAuthenticator`, `User`, `PrometheusRemoteWrite`, `GrafanaAlertsChannel`, `KeepalivedInstance`

### Категория 14: Type Coercion (v2.5.0)

| # | Проверка | Описание |
|---|----------|----------|
| 51 | `check_timestamp_values` | ISO8601 даты без кавычек |
| 52 | `check_version_numbers` | Версии как float: `1.0` → `1` |
| 53 | `check_implicit_types` | Расширенные type coercion |
| 54 | `check_embedded_json` | JSON синтаксис внутри YAML |
| 55 | `check_key_naming` | Именование ключей |

---

## Автоматическое исправление (7 типов)

Скрипт `fix_yaml_issues.sh` автоматически исправляет:

| # | Проблема | Исправление |
|---|----------|-------------|
| 1 | BOM | Удаление UTF-8 BOM |
| 2 | CRLF | Windows → Unix line endings |
| 3 | Табы | Табы → 2 пробела |
| 4 | Trailing whitespace | Удаление пробелов в конце строк |
| 5 | Boolean регистр | `True` → `true`, `False` → `false` |
| 6 | List spacing | `-item` → `- item` |
| 7 | Document markers | `----` → `---`, `.....` → `...` |

### Использование

```bash
# Просмотр изменений (dry-run)
./fix_yaml_issues.sh -n /path/to/files

# Исправление с backup
./fix_yaml_issues.sh -b /path/to/files

# Рекурсивно
./fix_yaml_issues.sh -r /path/to/directory

# Все опции
./fix_yaml_issues.sh -r -b -n /path/to/files
```

**ВАЖНО:** Fix script НЕ спрашивает подтверждения! Используйте `-n` (dry-run) для предварительного просмотра.

---

## Обработка сложных типов данных

### Boolean

```yaml
# YAML 1.1 проблемы (предупреждения)
enabled: yes      # → true (может быть неожиданно)
enabled: Yes      # → true
enabled: YES      # → true
enabled: no       # → false
country: NO       # → false (Norway Problem!)

# Рекомендация
enabled: true     # Явно
enabled: false    # Явно
country: "NO"     # В кавычках
```

### Числа

```yaml
# Octal (предупреждения)
mode: 0644        # YAML 1.1: 420 (octal)
mode: 0o644       # YAML 1.2: 420 (octal)
mode: "0644"      # Строка

# Sexagesimal (предупреждения)
time: 21:00       # → 1260 (base-60!)
time: "21:00"     # Строка

# Scientific notation
value: 1e10       # Число
value: "1e10"     # Строка
```

### Base64 (Secrets)

```yaml
apiVersion: v1
kind: Secret
data:
  password: cGFzc3dvcmQ=    # Валидный base64
  token: invalid!!!         # ОШИБКА: невалидный base64
```

### JSON в YAML

```yaml
# Inline JSON - валидируется
config: {"key": "value"}    # OK
config: {key: value}        # ОШИБКА: ключ без кавычек

# Trailing comma
config: {"key": "value",}   # ОШИБКА
```

### Multiline

```yaml
# Literal block (|) - сохраняет переносы
script: |
  #!/bin/bash
  echo "Hello"

# Folded block (>) - объединяет строки
description: >
  This is a long
  description
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

## Опции командной строки

### yaml_validator.sh

```
Использование: ./yaml_validator.sh [ОПЦИИ] <файл_или_директория>

Опции:
    -o, --output FILE       Сохранить отчёт в файл (по умолчанию: yaml_validation_report.txt)
    -r, --recursive         Рекурсивный поиск YAML файлов
    -v, --verbose           Подробный вывод
    -h, --help              Показать справку
```

### fix_yaml_issues.sh

```
Использование: ./fix_yaml_issues.sh [ОПЦИИ] <файл_или_директория>

Опции:
    -r, --recursive         Рекурсивная обработка
    -b, --backup            Создать backup (.bak)
    -n, --dry-run           Только показать изменения
    -h, --help              Показать справку
```

---

## FAQ

### Валидатор редактирует файлы?

**Нет.** `yaml_validator.sh` только проверяет и выводит отчёт. Для исправления используйте отдельный `fix_yaml_issues.sh`.

### Нужно подтверждение перед редактированием?

**Нет.** `fix_yaml_issues.sh` сразу применяет изменения. Используйте `-n` (dry-run) для предварительного просмотра и `-b` (backup) для безопасности.

### Как запустить на одном файле?

```bash
./yaml_validator.sh my-deployment.yaml
./fix_yaml_issues.sh my-deployment.yaml
```

### Как игнорировать определённые проверки?

В текущей версии нет возможности отключить отдельные проверки. Это запланировано для v3.0.

### Поддерживается multi-document YAML?

**Да.** Валидатор корректно обрабатывает `---` разделители и проверяет каждый документ отдельно.

---

## Changelog

### v2.5.0 (2026-01-23)
- Добавлено 7 новых проверок:
  - `check_timestamp_values` — ISO8601 date warnings
  - `check_version_numbers` — version float warnings
  - `check_merge_keys` — YAML merge key validation
  - `check_implicit_types` — extended type coercion
  - `check_embedded_json` — inline JSON validation
  - `check_network_values` — IP/CIDR/protocol validation
  - `check_key_naming` — key naming conventions
- Всего 54 проверки

### v2.4.0 (2026-01-23)
- Исправлен CI security scan (word boundaries в grep)
- Поддержка одиночных файлов

### v2.3.0
- Добавлены проверки sexagesimal, Norway Problem
- YAML Bomb detection

### v2.2.0
- Расширенная поддержка Deckhouse CRD

### v2.1.0
- Начальная версия с Kubernetes проверками

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
