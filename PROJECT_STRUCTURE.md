# Структура проекта YAML Validator

```
yaml_validator/
├── yaml_validator.sh          (25K)  - Основной валидатор YAML файлов
├── fix_yaml_issues.sh         (10K)  - Скрипт автоматического исправления
├── README.md                  (18K)  - Полная документация
├── QUICKSTART.md              (3.4K) - Краткая инструкция быстрого старта
├── PROJECT_STRUCTURE.md              - Этот файл
│
└── test_samples/                     - Примеры файлов для тестирования
    ├── valid.yaml                    - Корректный YAML манифест
    ├── tabs_error.yaml               - Файл с табами
    ├── windows_encoding.yaml         - Файл с Windows CRLF
    ├── indentation_error.yaml        - Несогласованные отступы
    ├── syntax_error.yaml             - Синтаксические ошибки
    └── missing_k8s_fields.yaml       - Отсутствуют K8s поля
```

## Описание компонентов

### yaml_validator.sh
**Главный валидатор**

Функции:
- Проверка кодировки (CRLF)
- Проверка табов
- Проверка trailing whitespace
- Проверка отступов
- Проверка базового синтаксиса YAML
- Проверка Kubernetes-специфичных полей
- Генерация детальных отчётов

Использование:
```bash
./yaml_validator.sh [опции] <директория>
```

Опции:
- `-r, --recursive` - рекурсивный поиск
- `-v, --verbose` - подробный вывод
- `-o, --output FILE` - сохранить отчёт в файл
- `-h, --help` - справка

### fix_yaml_issues.sh
**Автоматическое исправление**

Исправляет:
- Windows CRLF → Unix LF
- Табы → Пробелы (2 пробела)
- Trailing whitespace

Использование:
```bash
./fix_yaml_issues.sh [опции] <директория>
```

Опции:
- `-r, --recursive` - рекурсивная обработка
- `-b, --backup` - создать резервные копии
- `-n, --dry-run` - только показать что будет сделано
- `-h, --help` - справка

### README.md
**Полная документация**

Содержит:
- Описание назначения и возможностей
- Требования к системе
- Инструкции по установке
- Детальные примеры использования
- Структура отчётов
- Типичные ошибки и их исправление
- Примеры автоматизации
- Интеграция в CI/CD
- Troubleshooting
- Changelog

### QUICKSTART.md
**Краткая инструкция**

Для быстрого старта:
- Минимальные примеры
- Типичный workflow
- Частые команды
- Решение распространённых проблем

### test_samples/
**Тестовые файлы**

Примеры различных типов ошибок для тестирования валидатора.

## Развёртывание в закрытом контуре

### Вариант 1: Копирование через USB/CD

```bash
# На машине с интернетом
git clone <репозиторий>
cd yaml_validator
tar -czf yaml_validator.tar.gz *.sh *.md

# Перенести yaml_validator.tar.gz на целевую машину

# На целевой машине (Astra Linux)
tar -xzf yaml_validator.tar.gz
chmod +x yaml_validator.sh fix_yaml_issues.sh
```

### Вариант 2: Копирование по внутренней сети

```bash
# С машины-источника
scp yaml_validator.sh fix_yaml_issues.sh README.md QUICKSTART.md \
    user@target:/opt/yaml_validator/

# На целевой машине
chmod +x /opt/yaml_validator/*.sh
```

### Вариант 3: Установка в систему

```bash
# Копировать в системную директорию
sudo cp yaml_validator.sh /usr/local/bin/yaml-validator
sudo cp fix_yaml_issues.sh /usr/local/bin/yaml-fix
sudo chmod +x /usr/local/bin/yaml-validator
sudo chmod +x /usr/local/bin/yaml-fix

# Использовать из любого места
yaml-validator /path/to/manifests
yaml-fix /path/to/manifests
```

## Минимальные требования

- **ОС**: Linux с bash 4.0+
- **Утилиты**: Только стандартные (sed, grep, find, expand)
- **Права**: Обычный пользователь (sudo не требуется)
- **Место**: ~50KB на диске

## Зависимости

**НЕТ внешних зависимостей!**

Используются только встроенные утилиты:
- `bash` (4.0+)
- `sed`
- `grep`
- `find`
- `expand`
- `wc`

Все они присутствуют в Astra Linux SE 1.7 Smolensk по умолчанию.

## Поддержка

Для вопросов и предложений создавайте issue или обращайтесь к документации:
- Полная документация: `README.md`
- Быстрый старт: `QUICKSTART.md`

## Changelog

**v1.0.0** (2026-01-21)
- Первый релиз
- Полная функциональность валидации
- Автоматическое исправление простых ошибок
- Детальные отчёты
- Документация на русском языке

## Лицензия

Свободное использование для любых целей.
