# Branch Protection Setup Instructions

Этот файл содержит инструкции по настройке branch protection rules для репозитория.

## 🔒 Настройка через GitHub Web UI

### Шаг 1: Перейти в Settings

1. Откройте https://github.com/AlexGromer/ssh-yaml-validator
2. Перейдите в **Settings** → **Branches**
3. Нажмите **Add branch protection rule**

### Шаг 2: Настроить правила для `main`

#### Branch name pattern
```
main
```

#### Protect matching branches

Включите следующие опции:

- ✅ **Require a pull request before merging**
  - ✅ Require approvals: **1**
  - ✅ Dismiss stale pull request approvals when new commits are pushed
  - ✅ Require review from Code Owners (опционально, если есть CODEOWNERS)
  - ✅ Require approval of the most recent reviewable push

- ✅ **Require status checks to pass before merging**
  - ✅ Require branches to be up to date before merging
  - Status checks to require (добавить после первого запуска CI):
    - `validate / Validate YAML Files`
    - `shellcheck / ShellCheck Linting`
    - `security / Security Scan`

- ✅ **Require signed commits**
  - Все коммиты должны иметь GPG подпись

- ✅ **Require linear history**
  - Запрещает merge commits, требует rebase или squash

- ✅ **Require conversation resolution before merging**
  - Все комментарии в PR должны быть resolved

- ✅ **Lock branch**
  - ❌ НЕ включать (это сделает ветку read-only для всех)

- ✅ **Do not allow bypassing the above settings**
  - ✅ Включить, чтобы правила действовали даже для администраторов

#### Rules applied to everyone including administrators

- ✅ **Restrict who can push to matching branches**
  - Оставить пустым (никто не может push напрямую)

- ✅ **Allow force pushes**
  - ❌ НЕ включать

- ✅ **Allow deletions**
  - ❌ НЕ включать

### Шаг 3: Сохранить

Нажмите **Create** для создания правила.

## 🤖 Настройка через GitHub CLI

Альтернативно, можно настроить через `gh` CLI:

```bash
# Требуется gh CLI v2.0+
gh api repos/AlexGromer/ssh-yaml-validator/branches/main/protection \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  -f required_status_checks='{"strict":true,"contexts":["validate / Validate YAML Files","shellcheck / ShellCheck Linting","security / Security Scan"]}' \
  -f enforce_admins=true \
  -f required_pull_request_reviews='{"dismissal_restrictions":{},"dismiss_stale_reviews":true,"require_code_owner_reviews":false,"required_approving_review_count":1,"require_last_push_approval":true}' \
  -f restrictions=null \
  -f required_linear_history=true \
  -f allow_force_pushes=false \
  -f allow_deletions=false \
  -f required_conversation_resolution=true \
  -f lock_branch=false \
  -f allow_fork_syncing=true \
  -f required_signatures=true
```

## 🔐 Настройка через GitHub API (с токеном)

```bash
# Экспорт токена (из pass)
export GITHUB_TOKEN=$(pass show github/personal-access-token)

# Применить branch protection
curl -X PUT \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/AlexGromer/ssh-yaml-validator/branches/main/protection \
  -d '{
    "required_status_checks": {
      "strict": true,
      "contexts": [
        "validate / Validate YAML Files",
        "shellcheck / ShellCheck Linting",
        "security / Security Scan"
      ]
    },
    "enforce_admins": true,
    "required_pull_request_reviews": {
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": false,
      "required_approving_review_count": 1,
      "require_last_push_approval": true
    },
    "restrictions": null,
    "required_linear_history": true,
    "allow_force_pushes": false,
    "allow_deletions": false,
    "required_conversation_resolution": true,
    "lock_branch": false,
    "allow_fork_syncing": true,
    "required_signatures": true
  }'
```

## ✅ Проверка настроек

После настройки проверьте:

```bash
# Через gh CLI
gh api repos/AlexGromer/ssh-yaml-validator/branches/main/protection

# Или через web UI
# https://github.com/AlexGromer/ssh-yaml-validator/settings/branches
```

## 📝 Результат

После настройки:

- ❌ Невозможен прямой push в `main`
- ✅ Все изменения только через Pull Request
- ✅ Требуется минимум 1 approval
- ✅ Требуется прохождение CI
- ✅ Требуется GPG подпись на всех коммитах
- ✅ Требуется linear history (rebase/squash)
- ✅ Правила действуют для всех, включая администраторов

## 🚨 Важно

После включения branch protection, попытка прямого push в main приведет к ошибке:

```bash
$ git push origin main
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: error: Required status check "validate / Validate YAML Files" is expected.
To github.com:AlexGromer/ssh-yaml-validator.git
 ! [remote rejected] main -> main (protected branch hook declined)
error: failed to push some refs to 'github.com:AlexGromer/ssh-yaml-validator.git'
```

Это ожидаемое поведение! Используйте feature branches и PR.
