# Branch Protection Status

**Дата настройки**: 2026-01-22
**Статус**: ✅ **АКТИВНА**
**Репозиторий**: AlexGromer/ssh-yaml-validator
**Защищённая ветка**: `main`

---

## ✅ Текущие настройки

### 1. Pull Request Requirements
- ✅ **Требуется PR перед merge**: Да
- ✅ **Требуется approvals**: 1
- ✅ **Dismiss stale reviews**: Да (при новых коммитах)
- ✅ **Require last push approval**: Да

### 2. Status Checks
- ✅ **Branches must be up to date**: Да
- ✅ **Required checks**:
  1. `validate / Validate YAML Files`
  2. `shellcheck / ShellCheck Linting`
  3. `security / Security Scan`

### 3. Commit Requirements
- ✅ **GPG signatures required**: Да (все коммиты)
- ✅ **Linear history**: Да (rebase/squash only)
- ✅ **Conversation resolution**: Да (все комментарии resolved)

### 4. Admin Rules
- ✅ **Enforce for administrators**: Да
- ❌ **Force push allowed**: Нет
- ❌ **Branch deletion allowed**: Нет
- ❌ **Branch locked**: Нет

---

## 🧪 Проверка (2026-01-22)

Тест прямого push в main:

```bash
$ git push origin main
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote:
remote: - Commits must have verified signatures.
remote:   Found 1 violation:
remote:   513ed27120da21e83e8766f3f3267e9a2101f455
remote:
remote: - Changes must be made through a pull request.
remote:
remote: - 3 of 3 required status checks are expected.
To github.com:AlexGromer/ssh-yaml-validator.git
 ! [remote rejected] main -> main (protected branch hook declined)
error: failed to push some refs to 'github.com:AlexGromer/ssh-yaml-validator.git'
```

**Результат**: ✅ Branch protection работает корректно

---

## 📋 Правильный workflow

### Шаг 1: Создать feature branch
```bash
git checkout -b feature/my-new-feature
# Внести изменения
git add .
git commit -S -m "feat: add new feature"
git push origin feature/my-new-feature
```

### Шаг 2: Создать Pull Request
```bash
gh pr create --title "feat: add new feature" --body "Description"
```

### Шаг 3: Дождаться CI
- ✅ validate / Validate YAML Files
- ✅ shellcheck / ShellCheck Linting
- ✅ security / Security Scan

### Шаг 4: Получить Approval
- Если есть GitHub App для approval — автоматически
- Иначе — попросить другого участника

### Шаг 5: Merge
```bash
gh pr merge --squash --delete-branch
```

---

## 🚫 Что теперь НЕВОЗМОЖНО

1. ❌ Прямой push в `main`
2. ❌ Force push в `main`
3. ❌ Удаление ветки `main`
4. ❌ Merge без approval
5. ❌ Merge без прохождения CI
6. ❌ Коммиты без GPG подписи
7. ❌ Merge commits (только rebase/squash)
8. ❌ Merge с нерешёнными комментариями

---

## 📝 История настройки

| Дата | Действие | Статус |
|------|----------|--------|
| 2026-01-22 | Создана документация `.github/BRANCH_PROTECTION_SETUP.md` | ✅ |
| 2026-01-22 | Применена branch protection через GitHub API | ✅ |
| 2026-01-22 | Протестирована защита (попытка push) | ✅ BLOCKED |

---

## 🔗 Ссылки

- **Настройки репозитория**: https://github.com/AlexGromer/ssh-yaml-validator/settings/branches
- **GitHub Docs**: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches
- **API endpoint**: `GET /repos/AlexGromer/ssh-yaml-validator/branches/main/protection`

---

## ⚠️ Важные заметки

### Почему первый коммит (18c152c) был напрямую в main?

Коммит `18c152c` ("fix(validator): add multiline context support + update to v2.0.0") был сделан **ДО** настройки branch protection. Это было ошибкой — следовало сначала настроить защиту, затем делать через PR.

**Решение**: Вариант Б — оставить коммит как есть, настроить защиту, далее работать правильно.

### Как работает с GitHub App для approval?

GitHub App (из `~/.claude/guides/GITHUB_APP_SETUP.md`) используется для автоматического approval PR, так как GitHub API не позволяет аппрувить собственные PR.

**Workflow**:
1. Claude Code создаёт PR (MCP GitHub + `GITHUB_TOKEN`)
2. CI проходит проверки
3. Claude Code аппрувит PR (GitHub App + Private Key)
4. Claude Code мержит PR (MCP GitHub + `GITHUB_TOKEN`)

---

**Последнее обновление**: 2026-01-22 12:45 UTC
