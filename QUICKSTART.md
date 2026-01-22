# YAML Validator - Быстрый старт

## Установка

```bash
git clone https://github.com/AlexGromer/ssh-yaml-validator.git
cd ssh-yaml-validator
chmod +x yaml_validator.sh fix_yaml_issues.sh
```

## Быстрое использование

### 1. Проверка YAML файлов

```bash
# Базовая проверка
./yaml_validator.sh /путь/к/манифестам

# Рекурсивная проверка всех поддиректорий
./yaml_validator.sh -r /путь/к/манифестам

# Подробный вывод процесса
./yaml_validator.sh -v /путь/к/манифестам
```

### 2. Автоматическое исправление

```bash
# Исправить простые ошибки (CRLF, табы, trailing whitespace)
./fix_yaml_issues.sh /путь/к/манифестам

# Исправить рекурсивно с созданием backup
./fix_yaml_issues.sh -r -b /путь/к/манифестам

# Посмотреть что будет исправлено (dry-run)
./fix_yaml_issues.sh -n /путь/к/манифестам
```

### 3. Типичный workflow

```bash
# Шаг 1: Проверить файлы
./yaml_validator.sh -r ~/k8s/manifests/

# Шаг 2: Автоматически исправить простые ошибки
./fix_yaml_issues.sh -b -r ~/k8s/manifests/

# Шаг 3: Проверить снова
./yaml_validator.sh -r ~/k8s/manifests/

# Шаг 4: Применить манифесты
kubectl apply -f ~/k8s/manifests/
```

## Интеграция в процесс деплоя

```bash
#!/bin/bash
# deploy.sh

MANIFESTS="./k8s-manifests"

if ! ./yaml_validator.sh -r "$MANIFESTS"; then
    echo "YAML валидация не пройдена!"
    exit 1
fi

kubectl apply -f "$MANIFESTS"
echo "Деплой завершён"
```

## Exit codes

- `0` - Все файлы валидны
- `1` - Обнаружены ошибки
