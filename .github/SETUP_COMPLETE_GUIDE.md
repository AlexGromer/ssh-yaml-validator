# Complete Setup Guide - Git Workflow & GitHub App

Этот документ объединяет все шаги для полной настройки Git workflow с GitHub App и branch protection.

## 📋 Table of Contents

1. [Git Configuration (Global)](#1-git-configuration-global)
2. [GitHub App Setup](#2-github-app-setup)
3. [Branch Protection Rules](#3-branch-protection-rules)
4. [Claude Code Configuration](#4-claude-code-configuration)
5. [Testing the Workflow](#5-testing-the-workflow)

---

## 1. Git Configuration (Global)

### ✅ Status: COMPLETED

Git настроен глобально с GPG подписью:

```bash
# Verify global configuration
git config --global --list | grep -E "user\.|signingkey|gpgsign"

# Output:
# user.name=AlexGromer
# user.email=alexei.pape@yandex.ru
# user.signingkey=548DC5F54C65D01C
# commit.gpgsign=true
```

### What This Means

- ✅ Все коммиты во всех репозиториях будут подписаны GPG автоматически
- ✅ Author: AlexGromer <alexei.pape@yandex.ru>
- ✅ Применяется ко всем новым репозиториям

---

## 2. GitHub App Setup

### 📍 Status: PENDING USER ACTION

Создайте GitHub App для автоматического approval PR.

### Quick Steps

1. **Create App**: https://github.com/settings/apps/new
   - Name: `AlexGromer-Claude-Code-Bot`
   - Permissions: Pull requests (Read & Write)
   - Install: All repositories

2. **Generate Private Key**
   - Download `.pem` file
   - Store in pass: `pass insert -m github/claude-code-bot-private-key`

3. **Get IDs**
   - App ID: найти на странице App
   - Installation ID: из URL после installation

4. **Store in pass**:
```bash
# Store App ID
pass insert github/claude-code-bot-app-id

# Store Installation ID
pass insert github/claude-code-bot-installation-id

# Store Private Key (multiline)
cat ~/Downloads/*.private-key.pem | pass insert -m github/claude-code-bot-private-key

# Clean up
rm ~/Downloads/*.private-key.pem
```

### Detailed Instructions

See: [GITHUB_APP_SETUP.md](./GITHUB_APP_SETUP.md) for complete step-by-step guide.

### Verification

```bash
# Verify credentials stored
pass show github/claude-code-bot-app-id
pass show github/claude-code-bot-installation-id
pass show github/claude-code-bot-private-key | head -1
# Should output: -----BEGIN RSA PRIVATE KEY-----
```

---

## 3. Branch Protection Rules

### 📍 Status: PENDING USER ACTION

Настройте branch protection для `main` ветки.

### Option A: Automated Script (Recommended)

```bash
# Run automated setup script
cd /opt/yaml_validator
./.github/BRANCH_PROTECTION_AUTO_SETUP.sh

# Script will:
# 1. Check for GitHub token (pass or env)
# 2. Verify token permissions
# 3. Apply branch protection rules
# 4. Verify application
```

### Option B: Manual Setup via Web UI

1. Go to: https://github.com/AlexGromer/ssh-yaml-validator/settings/branches
2. Click **"Add branch protection rule"**
3. Branch pattern: `main`
4. Enable:
   - ✅ Require pull request reviews (1 approval)
   - ✅ Require status checks (validate, shellcheck, security)
   - ✅ Require signed commits
   - ✅ Require linear history
   - ✅ Require conversation resolution
   - ✅ Enforce for admins
   - ❌ No direct push
   - ❌ No force push

See: [BRANCH_PROTECTION_SETUP.md](./BRANCH_PROTECTION_SETUP.md) for detailed manual instructions.

### Verification

```bash
# Test direct push (should fail)
git checkout main
echo "test" >> README.md
git commit -am "test direct push"
git push origin main
# Expected: Error "protected branch hook declined"

# Correct workflow (should work)
git checkout -b test/protection-working
git push origin test/protection-working
gh pr create --title "Test" --body "Testing branch protection"
```

---

## 4. Claude Code Configuration

### ✅ Status: COMPLETED

Claude Code configuration updated with Git Workflow and GitHub App documentation.

### What Was Added

**File**: `~/.claude/modules/03-devops.md`

- **Section 1.5**: Version Control & Git Workflow (11 subsections)
  - GitHub Flow explanation
  - Branch naming conventions
  - Commit message format (Conventional Commits)
  - PR workflow
  - Branch protection rules
  - Troubleshooting guide
  - Best practices

- **Section 1.5.12**: Claude Code GitHub App Authentication
  - Authentication flow diagram
  - What GitHub App does vs doesn't do
  - Configuration options
  - Security considerations
  - Troubleshooting

### Verification

```bash
# Check if section exists
grep -n "### 1.5.12 Claude Code GitHub App" ~/.claude/modules/03-devops.md
# Should output line number

# View section
sed -n '/### 1.5.12/,/^---$/p' ~/.claude/modules/03-devops.md | head -20
```

---

## 5. Testing the Workflow

### Test Checklist

#### ✅ Test 1: Feature Branch Creation

```bash
git checkout main
git pull origin main
git checkout -b test/workflow-verification
echo "test" >> README.md
git add README.md
git commit -S -m "test: verify workflow is working"
git push -u origin test/workflow-verification
```

**Expected**: ✅ Push succeeds

---

#### ✅ Test 2: PR Creation

```bash
# Using GitHub MCP
gh pr create \
  --title "test: Verify workflow" \
  --body "Testing the new Git workflow and CI/CD" \
  --base main \
  --head test/workflow-verification
```

**Expected**: ✅ PR created, CI starts automatically

---

#### ✅ Test 3: CI Validation

Check PR page: https://github.com/AlexGromer/ssh-yaml-validator/pulls

**Expected**:
- ✅ validate job: Running/Passed
- ✅ shellcheck job: Running/Passed
- ✅ security job: Running/Passed

---

#### ⏳ Test 4: GitHub App Approval (After App Setup)

```bash
# Claude Code attempts to approve PR
# This will use GitHub App credentials from pass
```

**Expected**: ✅ PR approved by AlexGromer-Claude-Code-Bot

---

#### ✅ Test 5: Merge PR

```bash
# After approval + CI pass
gh pr merge <PR#> --squash
```

**Expected**: ✅ PR merged to main, feature branch deleted

---

#### ❌ Test 6: Direct Push to Main (Should Fail)

```bash
git checkout main
echo "test" >> README.md
git commit -am "test: direct push"
git push origin main
```

**Expected**: ❌ Error "protected branch hook declined"

---

## 📊 Current Status Summary

| Component | Status | Details |
|-----------|--------|---------|
| **Git Config (Global)** | ✅ Complete | GPG signing, user info set globally |
| **CI/CD Workflows** | ✅ Complete | ci.yml, release.yml in main branch |
| **Documentation** | ✅ Complete | CONTRIBUTING.md, PR template, guides |
| **Claude Code Config** | ✅ Complete | Section 1.5 + 1.5.12 added |
| **GitHub App** | ⏳ Pending | User needs to create App and store credentials |
| **Branch Protection** | ⏳ Pending | User needs to run setup script or configure manually |
| **Testing** | ⏳ Pending | After GitHub App + branch protection setup |

---

## 🚀 Next Steps (In Order)

### Step 1: Create GitHub App (15 minutes)

Follow: [GITHUB_APP_SETUP.md](./GITHUB_APP_SETUP.md)

**Why First**: GitHub App credentials needed for automated approvals

---

### Step 2: Configure Branch Protection (5 minutes)

Run:
```bash
./.github/BRANCH_PROTECTION_AUTO_SETUP.sh
```

Or follow: [BRANCH_PROTECTION_SETUP.md](./BRANCH_PROTECTION_SETUP.md)

**Why Second**: Protection rules should be active before testing workflow

---

### Step 3: Test Complete Workflow (10 minutes)

Follow Test Checklist above (Tests 1-6)

**Why Last**: Validates everything works end-to-end

---

## 🔧 Troubleshooting

### Issue: "Cannot approve own PR"

**Solution**: This is why we need GitHub App. Complete Step 1 above.

---

### Issue: "Protected branch update failed"

**Solution**: This means branch protection is working! Use PR workflow instead.

---

### Issue: "Status check required but not present"

**Solution**: Status checks appear after first CI run. Merge first PR, then checks will be enforced.

---

## 📞 Support

- **GitHub App Issues**: [GITHUB_APP_SETUP.md](./GITHUB_APP_SETUP.md) Troubleshooting section
- **Branch Protection Issues**: [BRANCH_PROTECTION_SETUP.md](./BRANCH_PROTECTION_SETUP.md)
- **General Workflow**: [CONTRIBUTING.md](../CONTRIBUTING.md)

---

## ✅ Completion Checklist

After completing all steps, verify:

- [ ] Git config is global (`git config --global --list`)
- [ ] GitHub App created and credentials in pass
- [ ] Branch protection active on main
- [ ] CI runs automatically on new PRs
- [ ] GitHub App can approve PRs
- [ ] Direct push to main is blocked
- [ ] PR workflow works end-to-end
- [ ] Claude Code configuration updated

---

**When all items are checked, you're ready to use the professional Git workflow!** 🎉
