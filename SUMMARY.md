# YAML Validator - Итоговая информация

## Что создано

YAML валидатор на чистом bash для изолированных контуров без доступа к интернету и внешним утилитам.

## Файлы проекта

| Файл | Размер | Описание |
|------|--------|----------|
| `yaml_validator.sh` | 25K | Основной валидатор YAML файлов |
| `fix_yaml_issues.sh` | 10K | Автоматическое исправление простых ошибок |
| `README.md` | 18K | Полная документация с примерами |
| `QUICKSTART.md` | 3.4K | Краткая инструкция быстрого старта |
| `PROJECT_STRUCTURE.md` | 5.8K | Структура проекта и развёртывание |
| `DEMO.sh` | - | Интерактивная демонстрация |
| `test_samples/` | - | Примеры файлов для тестирования |

## Возможности валидатора

### ✓ Проверки

1. **Windows Encoding** - обнаруживает CRLF символы
2. **Табы** - находит табы вместо пробелов
3. **Trailing Whitespace** - лишние пробелы в конце строк
4. **Отступы** - проверяет консистентность отступов
5. **Синтаксис YAML**:
   - Непарные кавычки
   - Отсутствие пробела после двоеточия
   - Некорректные символы в ключах
6. **Kubernetes поля** - проверяет apiVersion и kind

### ✓ Автоматическое исправление

Скрипт `fix_yaml_issues.sh` автоматически исправляет:
- Windows CRLF → Unix LF
- Табы → Пробелы (2 пробела)
- Trailing whitespace

### ✓ Отчёты

- Real-time статусы проверки
- Детальные отчёты с номерами строк
- Содержимое проблемных строк
- Рекомендации по исправлению
- Итоговая статистика

## Быстрый старт

### 1. Проверка файлов

```bash
# Базовая проверка
./yaml_validator.sh /путь/к/манифестам

# Рекурсивная проверка
./yaml_validator.sh -r /путь/к/манифестам

# С подробным выводом
./yaml_validator.sh -v /путь/к/манифестам
```

### 2. Автоматическое исправление

```bash
# Исправить простые ошибки
./fix_yaml_issues.sh /путь/к/манифестам

# С backup и рекурсивно
./fix_yaml_issues.sh -r -b /путь/к/манифестам

# Dry-run (только показать)
./fix_yaml_issues.sh -n /путь/к/манифестам
```

### 3. Типичный workflow

```bash
# 1. Проверить
./yaml_validator.sh -r ~/k8s/manifests/

# 2. Автоматически исправить
./fix_yaml_issues.sh -b -r ~/k8s/manifests/

# 3. Проверить снова
./yaml_validator.sh -r ~/k8s/manifests/

# 4. Вручную исправить оставшиеся (если есть)
# См. yaml_validation_report.txt

# 5. Применить
kubectl apply -f ~/k8s/manifests/
```

## Развёртывание в закрытом контуре

### Копирование файлов

```bash
# Упаковать на машине с интернетом
tar -czf yaml_validator.tar.gz \
    yaml_validator.sh \
    fix_yaml_issues.sh \
    README.md \
    QUICKSTART.md \
    PROJECT_STRUCTURE.md

# Перенести на целевую машину (USB/CD/сеть)

# Распаковать на Astra Linux
tar -xzf yaml_validator.tar.gz
chmod +x yaml_validator.sh fix_yaml_issues.sh
```

### Установка в систему (опционально)

```bash
sudo cp yaml_validator.sh /usr/local/bin/yaml-validator
sudo cp fix_yaml_issues.sh /usr/local/bin/yaml-fix
sudo chmod +x /usr/local/bin/yaml-validator /usr/local/bin/yaml-fix

# Использовать из любой директории
yaml-validator /path/to/manifests
yaml-fix /path/to/manifests
```

## Интеграция в процессы

### Bash скрипт деплоя

```bash
#!/bin/bash

MANIFESTS="./k8s-manifests"

# Валидация
if ! ./yaml_validator.sh -r "$MANIFESTS"; then
    echo "❌ YAML валидация не пройдена!"
    exit 1
fi

# Применение
kubectl apply -f "$MANIFESTS"
echo "✅ Деплой завершён"
```

### Git Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

YAML_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(yaml|yml)$')

if [ -n "$YAML_FILES" ]; then
    echo "Проверка YAML файлов..."
    TEMP_DIR=$(mktemp -d)

    for file in $YAML_FILES; do
        mkdir -p "$TEMP_DIR/$(dirname "$file")"
        git show ":$file" > "$TEMP_DIR/$file"
    done

    if ! /path/to/yaml_validator.sh "$TEMP_DIR"; then
        echo "❌ YAML валидация не пройдена!"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    rm -rf "$TEMP_DIR"
    echo "✓ YAML валидация успешна"
fi
```

## Требования

- **ОС**: Astra Linux SE 1.7 (Smolensk) или любой Linux с bash 4.0+
- **Утилиты**: Только стандартные (sed, grep, find, expand)
- **Зависимости**: НЕТ внешних зависимостей
- **Права**: Обычный пользователь (sudo не требуется)
- **Место**: ~50KB на диске

## Тестирование

Проект включает набор тестовых файлов в директории `test_samples/`:

| Файл | Проблема |
|------|----------|
| `valid.yaml` | Корректный манифест (должен проходить) |
| `tabs_error.yaml` | Табы вместо пробелов |
| `windows_encoding.yaml` | Windows CRLF |
| `indentation_error.yaml` | Несогласованные отступы |
| `syntax_error.yaml` | Синтаксические ошибки |
| `missing_k8s_fields.yaml` | Отсутствуют K8s поля |

### Запуск тестов

```bash
# Проверить тестовые файлы
./yaml_validator.sh test_samples/

# Исправить автоматически исправляемые ошибки
cp -r test_samples test_fixed
./fix_yaml_issues.sh test_fixed/

# Проверить результат
./yaml_validator.sh test_fixed/
```

## Демонстрация

Запустите интерактивную демонстрацию:

```bash
./DEMO.sh
```

Демонстрация покажет:
1. Проверку тестовых файлов
2. Просмотр отчёта
3. Dry-run режим исправления
4. Реальное исправление с backup
5. Проверку после исправления

## Частые команды

```bash
# Проверить текущую директорию
./yaml_validator.sh .

# Проверить рекурсивно с отчётом
./yaml_validator.sh -r -o report.txt ./manifests

# Исправить с backup
./fix_yaml_issues.sh -b ./manifests

# Посмотреть что будет исправлено
./fix_yaml_issues.sh -n ./manifests

# Справка
./yaml_validator.sh --help
./fix_yaml_issues.sh --help
```

## Ограничения

Валидатор проверяет **базовый синтаксис** YAML и типичные ошибки копирования с Windows.

**Не проверяется**:
- Семантическая корректность K8s манифестов (используйте `kubectl --dry-run=client`)
- Сложные YAML конструкции (anchors, aliases, merge keys)
- Полная спецификация YAML 1.2

**Рекомендуемый workflow**:
1. Запустить YAML валидатор (синтаксис)
2. Использовать `kubectl apply --dry-run=client` (семантика K8s)

## Exit Codes

| Code | Значение |
|------|----------|
| 0 | Все файлы валидны |
| 1 | Обнаружены ошибки |

Используйте в скриптах для проверки:

```bash
if ./yaml_validator.sh ./manifests/; then
    echo "✓ Валидация пройдена"
else
    echo "✗ Валидация провалена"
    exit 1
fi
```

## Поддержка

- **Полная документация**: `README.md`
- **Быстрый старт**: `QUICKSTART.md`
- **Структура проекта**: `PROJECT_STRUCTURE.md`
- **Демонстрация**: `DEMO.sh`

## Changelog

### v1.0.0 (2026-01-21)

**Функционал**:
- ✓ Проверка Windows encoding (CRLF)
- ✓ Проверка табов
- ✓ Проверка trailing whitespace
- ✓ Проверка отступов
- ✓ Базовая проверка YAML синтаксиса
- ✓ Проверка Kubernetes полей
- ✓ Автоматическое исправление простых ошибок
- ✓ Детальные отчёты с номерами строк
- ✓ Цветной вывод
- ✓ Режим dry-run
- ✓ Создание backup

**Документация**:
- ✓ Полная документация (README.md)
- ✓ Краткая инструкция (QUICKSTART.md)
- ✓ Структура проекта (PROJECT_STRUCTURE.md)
- ✓ Тестовые файлы
- ✓ Демонстрация

**Тестирование**:
- ✓ Проверено на тестовых файлах
- ✓ Проверка различных типов ошибок
- ✓ Автоматическое исправление работает

## Автор

Создано для использования в закрытых контурах Astra Linux SE 1.7 (Smolensk) для работы с Kubernetes кластерами Deckhouse без возможности установки дополнительных утилит.

## Лицензия

Свободное использование в любых целях.

---

**Версия**: 1.0.0
**Дата**: 2026-01-21
**Язык**: Russian
**Платформа**: Astra Linux SE 1.7 (Smolensk)
