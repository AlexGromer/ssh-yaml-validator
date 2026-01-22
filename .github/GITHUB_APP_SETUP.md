# GitHub App Setup for Automated PR Approvals

This guide walks through creating a GitHub App that Claude Code can use to automatically approve Pull Requests.

## 🎯 Why GitHub App?

**Advantages over Personal Access Token:**
- ✅ Fine-grained permissions (только PR review, ничего больше)
- ✅ Separate audit trail (видно, что это бот, а не человек)
- ✅ Automatic installation на все новые репозитории
- ✅ Масштабируется на organization
- ✅ Более безопасно (можно отозвать без смены PAT)

---

## 📋 Step 1: Create GitHub App

### 1.1 Navigate to Settings

1. Откройте https://github.com/settings/apps
2. Нажмите **"New GitHub App"**

### 1.2 Basic Information

| Field | Value |
|-------|-------|
| **GitHub App name** | `AlexGromer-Claude-Code-Bot` (уникальное имя) |
| **Homepage URL** | `https://github.com/AlexGromer` |
| **Webhook** | ❌ Uncheck "Active" (нам не нужны webhooks) |

### 1.3 Permissions

Настройте следующие **Repository permissions**:

| Permission | Access | Why Needed |
|------------|--------|------------|
| **Pull requests** | Read & Write | Approve PRs, create reviews |
| **Contents** | Read-only | Read repo files for context |
| **Metadata** | Read-only | Required by default |

**Важно**: Остальные permissions оставить **No access**.

### 1.4 Where can this GitHub App be installed?

Выберите:
- ✅ **"Any account"** (чтобы можно было использовать в других аккаунтах/organizations)

### 1.5 Create App

Нажмите **"Create GitHub App"**

---

## 📋 Step 2: Generate Private Key

### 2.1 Generate Key

1. После создания App, scroll down to **"Private keys"** section
2. Нажмите **"Generate a private key"**
3. Файл `.pem` скачается автоматически (например: `alexgromer-claude-code-bot.2026-01-22.private-key.pem`)

### 2.2 Store Key Securely

Сохраните ключ в `pass`:

```bash
# Store private key in pass
cat ~/Downloads/alexgromer-claude-code-bot.*.private-key.pem | \
  pass insert -m github/claude-code-bot-private-key

# Store App ID (найти на странице App)
pass insert github/claude-code-bot-app-id
# Введите App ID (например: 123456)
```

**Важно**: Удалите файл `.pem` после сохранения в `pass`!

```bash
rm ~/Downloads/alexgromer-claude-code-bot.*.private-key.pem
```

---

## 📋 Step 3: Install App to Repositories

### 3.1 Install App

1. На странице GitHub App нажмите **"Install App"**
2. Выберите **"AlexGromer"** (ваш аккаунт)
3. Выберите репозитории:
   - **"All repositories"** (рекомендуется - автоматически добавится во все новые)
   - Или **"Only select repositories"** (выбрать ssh-yaml-validator)

4. Нажмите **"Install"**

### 3.2 Get Installation ID

После установки вы будете перенаправлены на URL вида:
```
https://github.com/settings/installations/12345678
```

Число `12345678` - это **Installation ID**. Сохраните его:

```bash
pass insert github/claude-code-bot-installation-id
# Введите Installation ID
```

---

## 📋 Step 4: Configure Claude Code

### 4.1 Add GitHub App Authentication to settings.json

Edit `~/.claude/settings.local.json`:

```json
{
  "github": {
    "app": {
      "appId": "GITHUB_APP_ID",
      "privateKey": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----",
      "installationId": "INSTALLATION_ID"
    }
  }
}
```

**Или используйте команды:**

```bash
# Read values from pass
APP_ID=$(pass show github/claude-code-bot-app-id)
INSTALLATION_ID=$(pass show github/claude-code-bot-installation-id)
PRIVATE_KEY=$(pass show github/claude-code-bot-private-key)

# Create settings.local.json (будет добавлено автоматически Claude Code)
cat > ~/.claude/github_app_config.json <<EOF
{
  "github": {
    "app": {
      "appId": "$APP_ID",
      "installationId": "$INSTALLATION_ID",
      "privateKeyPath": "~/.claude/github_app_key.pem"
    }
  }
}
EOF

# Save private key separately
echo "$PRIVATE_KEY" > ~/.claude/github_app_key.pem
chmod 600 ~/.claude/github_app_key.pem
```

### 4.2 Update Claude Code Configuration Module

Add to `~/.claude/modules/03-devops.md` Section 1.5:

```markdown
### 1.5.12 Claude Code GitHub App Authentication

Claude Code uses GitHub App for automated PR operations:

**Authentication Flow:**
1. Claude Code loads GitHub App credentials from settings
2. Generates JWT token using App ID + Private Key
3. Exchanges JWT for Installation Access Token
4. Uses Installation Token for GitHub API calls

**What GitHub App Does:**
- ✅ Approve Pull Requests (when different author)
- ✅ Add review comments
- ✅ Merge PRs after approval
- ✅ Create/update PR labels

**What GitHub App CANNOT Do:**
- ❌ Push commits (uses SSH key for that)
- ❌ Access unrelated repositories
- ❌ Modify repository settings
- ❌ Approve PRs created by the same Claude Code session
```

---

## 📋 Step 5: Test GitHub App

### 5.1 Test Authentication

```bash
# Test JWT generation (Python example)
python3 <<EOF
import jwt
import time
from pathlib import Path

# Load credentials from pass or files
app_id = "YOUR_APP_ID"
private_key = Path("~/.claude/github_app_key.pem").expanduser().read_text()

# Generate JWT
payload = {
    "iat": int(time.time()),
    "exp": int(time.time()) + (10 * 60),  # 10 minutes
    "iss": app_id
}

token = jwt.encode(payload, private_key, algorithm="RS256")
print(f"JWT Token: {token}")
EOF
```

### 5.2 Test API Access

```bash
# Get Installation Access Token
APP_ID=$(pass show github/claude-code-bot-app-id)
INSTALLATION_ID=$(pass show github/claude-code-bot-installation-id)
JWT_TOKEN="<generated_jwt_token>"

curl -X POST \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens

# Response should include:
# {
#   "token": "ghs_...",
#   "expires_at": "2026-01-22T16:00:00Z",
#   ...
# }
```

---

## 🔄 Workflow: How Claude Code Uses GitHub App

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  USER REQUEST: "Create PR and approve it"                                   │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 1: Create PR (uses SSH key + personal token)                          │
│  ├─► git push origin feature/branch                                         │
│  └─► gh pr create --title "..." --body "..."                                │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 2: Wait for CI (GitHub Actions run automatically)                     │
│  ├─► validate job: Run tests                                                │
│  ├─► shellcheck job: Lint scripts                                           │
│  └─► security job: Scan for vulnerabilities                                 │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 3: Approve PR (uses GitHub App)                                       │
│  ├─► Load GitHub App credentials                                            │
│  ├─► Generate JWT token (App ID + Private Key)                              │
│  ├─► Exchange JWT for Installation Access Token                             │
│  ├─► POST /repos/{owner}/{repo}/pulls/{pr}/reviews                          │
│  │    {                                                                      │
│  │      "event": "APPROVE",                                                 │
│  │      "body": "Automated approval by Claude Code Bot"                     │
│  │    }                                                                      │
│  └─► ✅ PR approved                                                          │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 4: Merge PR (uses GitHub App)                                         │
│  ├─► POST /repos/{owner}/{repo}/pulls/{pr}/merge                            │
│  └─► ✅ PR merged to main                                                    │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  STEP 5: Cleanup                                                            │
│  ├─► git pull origin main                                                   │
│  ├─► git branch -d feature/branch                                           │
│  └─► git push origin --delete feature/branch                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Security Best Practices

### Private Key Security

✅ **DO:**
- Store in `pass` or encrypted vault
- Set file permissions: `chmod 600 github_app_key.pem`
- Never commit to git
- Rotate keys periodically (every 6-12 months)

❌ **DON'T:**
- Store in plaintext files
- Share via email/messengers
- Commit to repositories
- Use same key across multiple apps

### Token Expiration

GitHub App Installation Tokens expire after **1 hour**.

Claude Code should:
1. Cache token
2. Check expiration before each API call
3. Regenerate if expired

---

## 🛠️ Troubleshooting

### Issue: "Resource not accessible by integration"

**Cause**: GitHub App doesn't have required permissions

**Solution**:
1. Go to GitHub App settings
2. Update **Repository permissions**
3. Click **"Save changes"**
4. Re-accept permissions на странице installation

---

### Issue: "JWT signature verification failed"

**Cause**: Wrong private key or App ID

**Solution**:
```bash
# Verify App ID
pass show github/claude-code-bot-app-id

# Verify private key format
pass show github/claude-code-bot-private-key | head -1
# Should start with: -----BEGIN RSA PRIVATE KEY-----
```

---

### Issue: "Installation not found"

**Cause**: Wrong Installation ID или App не установлен

**Solution**:
1. Go to https://github.com/settings/installations
2. Find Installation ID в URL
3. Update in pass:
```bash
pass insert -f github/claude-code-bot-installation-id
```

---

## 📚 References

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Authenticating as a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/about-authentication-with-a-github-app)
- [GitHub App Permissions](https://docs.github.com/en/rest/overview/permissions-required-for-github-apps)

---

## ✅ Checklist

After setup, verify:

- [ ] GitHub App created with correct permissions
- [ ] Private key generated and stored in `pass`
- [ ] App installed to account (all repositories)
- [ ] Installation ID stored in `pass`
- [ ] Claude Code configuration updated
- [ ] Test authentication successful
- [ ] Test PR approval successful

---

**Setup complete! GitHub App ready for automated PR approvals.** 🚀
