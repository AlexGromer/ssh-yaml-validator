#!/bin/bash

#############################################################################
# Branch Protection Auto-Setup Script
# Automatically configures branch protection rules for main branch
#############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OWNER="AlexGromer"
REPO="ssh-yaml-validator"
BRANCH="main"

# Required status checks (will be available after first CI run)
REQUIRED_CHECKS=(
  "validate / Validate YAML Files"
  "shellcheck / ShellCheck Linting"
  "security / Security Scan"
)

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Branch Protection Setup${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "Repository: ${GREEN}${OWNER}/${REPO}${NC}"
echo -e "Branch: ${GREEN}${BRANCH}${NC}"
echo ""

# Step 1: Get GitHub Token
echo -e "${YELLOW}Step 1: Checking for GitHub token...${NC}"

# Try to get token from pass
if command -v pass >/dev/null 2>&1; then
  # Try common pass paths
  for path in "github/personal-access-token" "github/token" "github-token" "github/admin-token"; do
    if GITHUB_TOKEN=$(pass show "$path" 2>/dev/null); then
      echo -e "${GREEN}✓ Found token in pass: $path${NC}"
      break
    fi
  done
fi

# If not found in pass, check environment
if [ -z "${GITHUB_TOKEN:-}" ]; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo -e "${GREEN}✓ Using GITHUB_TOKEN from environment${NC}"
  else
    echo -e "${RED}✗ GitHub token not found${NC}"
    echo ""
    echo "Please provide a GitHub Personal Access Token with the following scopes:"
    echo "  - repo (full control)"
    echo "  - admin:repo_hook"
    echo ""
    echo "Create one at: https://github.com/settings/tokens/new"
    echo ""
    read -p "Enter GitHub Token: " GITHUB_TOKEN

    if [ -z "$GITHUB_TOKEN" ]; then
      echo -e "${RED}✗ Token is required. Exiting.${NC}"
      exit 1
    fi
  fi
fi

# Step 2: Verify token
echo ""
echo -e "${YELLOW}Step 2: Verifying token...${NC}"

if ! USER_LOGIN=$(curl -s -f \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/user | jq -r '.login'); then
  echo -e "${RED}✗ Token verification failed${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Authenticated as: ${USER_LOGIN}${NC}"

# Step 3: Check current branch protection
echo ""
echo -e "${YELLOW}Step 3: Checking current branch protection...${NC}"

if PROTECTION=$(curl -s \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" 2>/dev/null); then

  if echo "$PROTECTION" | jq -e '.url' >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Branch protection already exists${NC}"
    read -p "Update existing protection? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${BLUE}Cancelled by user${NC}"
      exit 0
    fi
  else
    echo -e "${GREEN}✓ No existing protection found${NC}"
  fi
else
  echo -e "${GREEN}✓ No existing protection found${NC}"
fi

# Step 4: Apply branch protection
echo ""
echo -e "${YELLOW}Step 4: Applying branch protection rules...${NC}"

# Build required status checks array
STATUS_CHECKS_JSON=$(printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R . | jq -s .)

# Create protection payload
PAYLOAD=$(cat <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": ${STATUS_CHECKS_JSON}
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
}
EOF
)

echo ""
echo -e "${BLUE}Protection rules to apply:${NC}"
echo "  • Require PR reviews (1 approval)"
echo "  • Require status checks: $(echo "${REQUIRED_CHECKS[@]}" | wc -w) checks"
echo "  • Require signed commits (GPG)"
echo "  • Require linear history (rebase/squash only)"
echo "  • Require conversation resolution"
echo "  • Enforce for admins"
echo "  • No direct push to main"
echo "  • No force push"
echo ""

read -p "Apply these rules? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
  echo -e "${BLUE}Cancelled by user${NC}"
  exit 0
fi

# Apply protection
if RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X PUT \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" \
  -d "$PAYLOAD"); then

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Branch protection applied successfully!${NC}"
  else
    echo -e "${RED}✗ Failed to apply branch protection${NC}"
    echo -e "${RED}HTTP Status: $HTTP_CODE${NC}"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    exit 1
  fi
else
  echo -e "${RED}✗ Failed to connect to GitHub API${NC}"
  exit 1
fi

# Step 5: Verify protection
echo ""
echo -e "${YELLOW}Step 5: Verifying protection...${NC}"

if VERIFICATION=$(curl -s -f \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER}/${REPO}/branches/${BRANCH}/protection"); then

  echo -e "${GREEN}✓ Branch protection verified${NC}"
  echo ""
  echo -e "${BLUE}Active protection rules:${NC}"
  echo "$VERIFICATION" | jq '{
    enforce_admins: .enforce_admins.enabled,
    required_reviews: .required_pull_request_reviews.required_approving_review_count,
    required_status_checks: .required_status_checks.contexts,
    required_signatures: .required_signatures.enabled,
    required_linear_history: .required_linear_history.enabled
  }' 2>/dev/null || echo "  (details available at GitHub)"
else
  echo -e "${YELLOW}⚠ Could not verify (but protection may be active)${NC}"
fi

# Step 6: Final instructions
echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Test workflow:"
echo "   git checkout -b test/branch-protection"
echo "   git push origin test/branch-protection"
echo "   # Try to push to main directly - should fail"
echo ""
echo "2. Verify on GitHub:"
echo "   https://github.com/${OWNER}/${REPO}/settings/branches"
echo ""
echo "3. Create your first PR using the new workflow!"
echo ""
echo -e "${YELLOW}Note: Status checks will be available after first CI run${NC}"
echo ""
