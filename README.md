# YAML Validator для изолированных контуров

Pure Bash валидатор YAML файлов для закрытых сред без доступа к интернету и возможности установки дополнительных утилит.

## Назначение

Валидатор предназначен для проверки YAML манифестов Kubernetes (и других YAML файлов) в закрытых контурах на Astra Linux SE 1.7 Smolensk, где работа ведётся с кластером Deckhouse и нет возможности установить дополнительные утилиты типа `yamllint`, `yq` и т.д.

## Основные возможности (v2.1.0)

### Проверки

#### Критические проверки
1. **BOM (Byte Order Mark)** - обнаруживает невидимые символы UTF-8 BOM в начале файла
2. **Пустые файлы** - файлы без содержимого (только комментарии/пробелы)

#### Форматирование
3. **Кодировка Windows (CRLF)** - обнаруживает символы возврата каретки Windows
4. **Табы вместо пробелов** - YAML требует только пробелы для отступов
5. **Trailing whitespace** - лишние пробелы в конце строк
6. **Консистентность отступов** - проверяет кратность отступов
7. **Маркеры документа** - проверяет корректность `---` и `...` (не `----` или `....`)

#### Синтаксис YAML
8. **Непарные кавычки** - одинарные и двойные кавычки
9. **Непарные скобки** - bracket matching для JSON в YAML (`[...]`, `{...}`)
10. **Отсутствие пробела после двоеточия** - `key:value` → `key: value`
11. **Некорректные символы в ключах**
12. **Пустые ключи** - отсутствие имени перед двоеточием
13. **Дубликаты ключей** - повторяющиеся ключи на одном уровне отступов
14. **Multiline блоки** - поддержка `|` и `>` операторов

#### Специальные значения YAML
15. **Boolean-like значения** - предупреждения для `yes/no/on/off`
16. **Null варианты** - предупреждения для `NULL/Null/~`

#### YAML Anchors & Aliases
17. **Anchors** - проверка определений `&anchor_name`
18. **Aliases** - проверка использования `*alias_name` (должен быть определен anchor)

#### Kubernetes-специфичные проверки
19. **Обязательные поля** - `apiVersion`, `kind`, `metadata`, `metadata.name`
20. **Регистр полей** - `apiVersion` (не `Apiversion`, `ApiVersion`)
21. **Опечатки snake_case → camelCase**:
    - `container_port` → `containerPort`
    - `image_pull_policy` → `imagePullPolicy`
    - `restart_policy` → `restartPolicy`
    - И другие распространенные опечатки
22. **Полный словарь Kubernetes/Deckhouse полей** - топ-уровень, metadata, spec, container fields
23. **Формат меток (labels)**:
    - Длина ≤ 63 символа
    - Формат: `[a-z0-9A-Z]([a-z0-9A-Z-_.]*[a-z0-9A-Z])?`
    - Начинается и заканчивается буквой/цифрой
24. **Resource-specific проверки** - например, Pod/Deployment требуют секцию `spec`

## Требования

- **ОС**: Astra Linux SE 1.7 (Smolensk) или любой Linux с bash 4.0+
- **Зависимости**: ТОЛЬКО стандартные утилиты bash (нет внешних зависимостей)

## Установка

```bash
git clone https://github.com/AlexGromer/ssh-yaml-validator.git
cd ssh-yaml-validator
chmod +x yaml_validator.sh fix_yaml_issues.sh
```

## Использование

### Базовый запуск

```bash
# Проверить все YAML файлы в директории
./yaml_validator.sh /path/to/manifests

# Рекурсивная проверка всех поддиректорий
./yaml_validator.sh -r /path/to/manifests

# Подробный вывод (verbose)
./yaml_validator.sh -v /path/to/manifests
```

### Автоматическое исправление

Скрипт `fix_yaml_issues.sh` автоматически исправляет 7 типов проблем:
- BOM (Byte Order Mark)
- Windows encoding (CRLF → LF)
- Табы → пробелы
- Trailing whitespace
- Boolean регистр (True→true, False→false)
- List spacing (-item → - item)
- Document markers (---- → ---, ..... → ...)

```bash
# Исправить все поддерживаемые ошибки
./fix_yaml_issues.sh /path/to/manifests

# Рекурсивно с созданием backup
./fix_yaml_issues.sh -r -b /path/to/manifests

# Посмотреть что будет исправлено (dry-run)
./fix_yaml_issues.sh -n /path/to/manifests
```

## Exit Codes

| Exit Code | Значение |
|-----------|----------|
| 0 | Все файлы валидны |
| 1 | Обнаружены ошибки |

## Лицензия

MIT License
