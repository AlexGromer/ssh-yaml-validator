# Branch Protection Status

**Дата настройки**: 2026-01-22
**Последнее обновление**: 2026-01-22 19:30 UTC
**Статус**: ✅ **АКТИВНА**
**Репозиторий**: AlexGromer/ssh-yaml-validator
**Защищённая ветка**: `main`

---

## ✅ Текущие настройки

### 1. Pull Request Requirements
- ✅ **Требуется PR перед merge**: Да
- ❌ **Требуется approvals**: Нет (solo development)
- ℹ️ **Почему нет approvals?** См. раздел "Solo Development" ниже

### 2. Status Checks
- ✅ **Branches must be up to date**: Да
- ✅ **Required checks** (GitHub Actions):
  1. `Validate YAML Files`
  2. `ShellCheck Linting`
  3. `Security Scan`

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
- ✅ Validate YAML Files
- ✅ ShellCheck Linting
- ✅ Security Scan

### Шаг 4: Merge (после успешного CI)
```bash
gh pr merge --squash --delete-branch
```

Или через MCP GitHub API.

---

## 🚫 Что теперь НЕВОЗМОЖНО

1. ❌ Прямой push в `main`
2. ❌ Force push в `main`
3. ❌ Удаление ветки `main`
4. ❌ Merge без прохождения CI (3 required checks)
5. ❌ Коммиты без GPG подписи
6. ❌ Merge commits (только rebase/squash)
7. ❌ Merge с нерешёнными комментариями

---

## 📝 История настройки

| Дата | Действие | Статус |
|------|----------|--------|
| 2026-01-22 10:00 | Создана документация `.github/BRANCH_PROTECTION_SETUP.md` | ✅ |
| 2026-01-22 12:30 | Применена branch protection через GitHub API (с required approvals) | ✅ |
| 2026-01-22 12:45 | Протестирована защита (попытка push) | ✅ BLOCKED |
| 2026-01-22 19:30 | Обновлена защита: удален required approvals (solo development) | ✅ |
| 2026-01-22 20:00 | Исправлены имена required checks (без префиксов job/) | ✅ |

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

### Solo Development: Почему нет Required Approvals?

**Проблема**: В **personal repositories** (не organization) GitHub Apps всегда имеют `author_association: NONE`, и их approval не засчитывается для branch protection.

**GitHub ограничение**:
- Вы не можете approve свои собственные PR (GitHub API блокирует)
- GitHub App не может стать collaborator в personal repo через UI
- GitHub App approval имеет `author_association: NONE` → не засчитывается

**Решение для solo projects** — **Best Practice**:
```yaml
✅ Required status checks (CI must pass)
✅ Required signatures (GPG)
✅ Required linear history
✅ Enforce for administrators
✅ Required conversation resolution
❌ Required approving review count: 0  # Отключено для solo
```

**Защиты остаются эффективными**:
- Нельзя push напрямую в main
- Все изменения через PR
- CI обязателен (3 checks)
- GPG подпись обязательна
- Только rebase/squash merge

**Для organization repos**: GitHub App будет работать корректно с required approvals.

---

**Последнее обновление**: 2026-01-22 19:30 UTC
