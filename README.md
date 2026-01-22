# YAML Validator для изолированных контуров

Pure Bash валидатор YAML файлов для закрытых сред без доступа к интернету и возможности установки дополнительных утилит.

## Назначение

Валидатор предназначен для проверки YAML манифестов Kubernetes (и других YAML файлов) в закрытых контурах на Astra Linux SE 1.7 Smolensk, где работа ведётся с кластером Deckhouse и нет возможности установить дополнительные утилиты типа `yamllint`, `yq` и т.д.

## Основные возможности

### Проверки

1. **Кодировка Windows (CRLF)** - обнаруживает символы возврата каретки Windows
2. **Табы вместо пробелов** - YAML требует только пробелы для отступов
3. **Trailing whitespace** - лишние пробелы в конце строк
4. **Консистентность отступов** - проверяет кратность отступов
5. **Базовый синтаксис YAML**:
   - Непарные кавычки
   - Отсутствие пробела после двоеточия
   - Некорректные символы в ключах
6. **Kubernetes-специфичные проверки**:
   - Наличие обязательных полей `apiVersion` и `kind`

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

```bash
# Исправить простые ошибки (CRLF, табы, trailing whitespace)
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
