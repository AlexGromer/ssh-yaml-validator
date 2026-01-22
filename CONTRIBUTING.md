# Contributing to SSH YAML Validator

Спасибо за интерес к проекту! Этот документ описывает процесс контрибуции.

## 🌳 Git Workflow

Мы используем **GitHub Flow** - простой и эффективный workflow для feature-driven разработки.

### Структура веток

```
main (защищена)
  ├── feature/add-new-validation     ← новые функции
  ├── fix/correct-indentation-bug    ← исправления багов
  ├── docs/update-readme             ← документация
  ├── test/add-edge-cases            ← добавление тестов
  └── refactor/optimize-parsing      ← рефакторинг
```

### Процесс контрибуции

#### 1. Подготовка

```bash
# Форкните репозиторий на GitHub, затем клонируйте свой форк
git clone git@github.com:YOUR_USERNAME/ssh-yaml-validator.git
cd ssh-yaml-validator

# Добавьте upstream remote
git remote add upstream git@github.com:AlexGromer/ssh-yaml-validator.git

# Настройте GPG подпись (рекомендуется)
git config user.signingkey YOUR_GPG_KEY
git config commit.gpgsign true
```

#### 2. Создание feature branch

```bash
# Убедитесь, что main актуален
git checkout main
git pull upstream main

# Создайте feature branch с осмысленным именем
git checkout -b feature/add-yaml-anchors-validation

# Или для багфикса
git checkout -b fix/null-byte-detection
```

#### 3. Разработка

```bash
# Вносите изменения, делайте атомарные коммиты
git add yaml_validator.sh
git commit -S -m "Add YAML anchors validation check

- Implement check_yaml_anchors() function
- Add detection for undefined anchor references
- Add test samples for anchor validation
- Update documentation

Refs #42"

# Push в ваш форк
git push -u origin feature/add-yaml-anchors-validation
```

#### 4. Создание Pull Request

```bash
# Используйте gh CLI (если доступен)
gh pr create \
  --title "feat: Add YAML anchors validation" \
  --body "Implements validation for YAML anchors and aliases.

## Changes
- New check_yaml_anchors() function
- 3 new test samples
- Documentation updates

## Testing
- Tested on Astra Linux SE 1.7
- All existing tests pass
- New tests added for edge cases

Closes #42" \
  --base main \
  --head YOUR_USERNAME:feature/add-yaml-anchors-validation

# Или создайте PR через веб-интерфейс GitHub
```

#### 5. Code Review и Merge

- CI автоматически запустит тесты
- Дождитесь review от мейнтейнера
- Внесите изменения, если требуется
- После approval PR будет смержен в main

## 🔒 Branch Protection Rules

Ветка `main` защищена следующими правилами:

### Обязательные требования

- ✅ **Require pull request reviews**: минимум 1 approval
- ✅ **Require status checks to pass**: CI должен быть зелёным
  - `CI - YAML Validator Tests`
  - `ShellCheck Linting`
  - `Security Scan`
- ✅ **Require signed commits**: все коммиты должны быть GPG подписаны
- ✅ **Require linear history**: запрещён merge без fast-forward/rebase
- ✅ **Require conversation resolution**: все комментарии должны быть resolved

### Запрещено

- ❌ Прямой push в `main`
- ❌ Force push в `main`
- ❌ Удаление `main`
- ❌ Merge без approval
- ❌ Bypass правил (даже для администраторов)

## 📋 Стандарты кода

### Bash Style Guide

```bash
# ✅ Good
check_yaml_syntax() {
    local file="$1"
    local errors=()

    if [[ ! -f "$file" ]]; then
        errors+=("Файл не найден: $file")
        return 1
    fi

    # ... validation logic
}

# ❌ Bad
check_yaml_syntax(){
  file=$1  # не local, не quoted
  if [ ! -f $file ]  # старый синтаксис, не quoted
  then
    echo "error"  # использование echo вместо array
  fi
}
```

### Правила

1. **Используйте `local`** для всех переменных внутри функций
2. **Цитируйте переменные**: `"$variable"` (не `$variable`)
3. **Используйте `[[` вместо `[`** для условий
4. **Используйте массивы** для коллекций (`errors=()`)
5. **Функции должны возвращать статус**: `return 0` (success) или `return 1` (failure)
6. **Добавляйте комментарии** для сложной логики
7. **Используйте `set -o pipefail`** в начале скрипта

### ShellCheck

Весь код должен проходить ShellCheck без warnings:

```bash
shellcheck -S warning yaml_validator.sh
shellcheck -S warning fix_yaml_issues.sh
```

## 🧪 Тестирование

### Обязательные тесты

Перед созданием PR убедитесь, что:

```bash
# 1. Bash syntax check
bash -n yaml_validator.sh
bash -n fix_yaml_issues.sh

# 2. Validator работает на perfect_valid.yaml
./yaml_validator.sh test_samples/perfect_valid.yaml
# Ожидается: "✅ Проверка завершена. Ошибок не обнаружено"

# 3. Validator детектит ошибки
./yaml_validator.sh test_samples/complex_errors.yaml
# Ожидается: список ошибок

# 4. Auto-fix исправляет ошибки
cp test_samples/tabs_error.yaml /tmp/test.yaml
./fix_yaml_issues.sh /tmp/test.yaml
# Ожидается: сообщения об исправлениях

# 5. ShellCheck clean
shellcheck *.sh
```

### Добавление новых тестов

При добавлении новой проверки:

1. Создайте test sample в `test_samples/` демонстрирующий ошибку
2. Убедитесь, что валидатор её детектит
3. Если ошибка авто-исправляема, добавьте тест для auto-fix

## 📝 Commit Messages

### Формат

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: новая функциональность
- `fix`: исправление бага
- `docs`: изменения в документации
- `test`: добавление тестов
- `refactor`: рефакторинг
- `perf`: улучшение производительности
- `chore`: рутинные задачи (обновление зависимостей и т.д.)
- `ci`: изменения в CI/CD

### Примеры

```bash
# Feature
git commit -S -m "feat(validator): add YAML anchors validation

Implement check_yaml_anchors() to detect undefined anchor references.
Adds 3 new test samples covering edge cases.

Closes #42"

# Bug fix
git commit -S -m "fix(validator): correct NULL byte detection

Previous implementation caused false positives on valid files.
Now using 'od -An -tx1' for accurate detection.

Fixes #38"

# Documentation
git commit -S -m "docs: update installation instructions for Astra Linux

Add specific steps for Astra Linux SE 1.7 Smolensk.
Include firewall configuration notes.

Refs #45"
```

## 🔐 Security

### Обязательные проверки

- ❌ Никогда не коммитить credentials, токены, пароли
- ❌ Никогда не использовать `eval` с user input
- ❌ Никогда не использовать `system()` или `exec()` с непроверенными данными
- ✅ Всегда цитировать переменные: `"$var"`
- ✅ Всегда валидировать входные данные
- ✅ Использовать `set -o pipefail` и `set -u`

### GPG Signing

Все коммиты должны быть подписаны GPG:

```bash
# Настройка GPG
git config user.signingkey YOUR_GPG_KEY_ID
git config commit.gpgsign true

# Коммит с подписью
git commit -S -m "Your commit message"

# Проверка подписи
git log --show-signature -1
```

## 🎯 Versioning

Мы используем [Semantic Versioning](https://semver.org/):

- **MAJOR** (X.0.0): breaking changes
- **MINOR** (1.X.0): новая функциональность (backward compatible)
- **PATCH** (1.0.X): bug fixes (backward compatible)

### Когда обновлять версию?

```bash
# PATCH: bug fixes только
fix/correct-indentation-bug → 2.0.0 → 2.0.1

# MINOR: новые функции, backward compatible
feature/add-anchors-validation → 2.0.1 → 2.1.0

# MAJOR: breaking changes
refactor/change-cli-arguments → 2.1.0 → 3.0.0
```

Версия обновляется в:
- `yaml_validator.sh` (заголовок `# Version: X.Y.Z`)
- `fix_yaml_issues.sh` (заголовок `# Version: X.Y.Z`)
- Git tag `vX.Y.Z`

## 📞 Связь

- **Issues**: https://github.com/AlexGromer/ssh-yaml-validator/issues
- **Discussions**: https://github.com/AlexGromer/ssh-yaml-validator/discussions
- **Security**: alexei.pape@yandex.ru (для security issues)

## 📄 License

Контрибутя в проект, вы соглашаетесь, что ваш код будет распространяться под той же лицензией, что и проект.

---

**Спасибо за ваш вклад! 🚀**
