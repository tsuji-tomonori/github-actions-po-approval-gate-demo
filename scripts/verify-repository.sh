#!/usr/bin/env bash
set -euo pipefail

for command in gh jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "$command is required." >&2
    exit 2
  }
done

gh auth status >/dev/null

OWNER=${1:-$(gh api user --jq .login)}
REPO=${2:-github-actions-po-approval-gate-demo}
PO_LOGIN=${3:-$OWNER}
FULL_REPO="$OWNER/$REPO"
API_VERSION=2026-03-10
failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

repo=$(gh api "repos/$FULL_REPO")
[[ $(jq -r .visibility <<<"$repo") == public ]] && pass 'repository is public' || fail 'repository is not public'

po_id=$(gh api "users/$PO_LOGIN" --jq .id)
approval=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/environments/prd-approval")
production=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/environments/production")

[[ $(jq -r .can_admins_bypass <<<"$approval") == false ]] && pass 'prd-approval blocks administrator bypass' || fail 'prd-approval permits administrator bypass'
[[ $(jq -r --argjson id "$po_id" '[.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]? | select(.reviewer.id == $id)] | length' <<<"$approval") -ge 1 ]] \
  && pass "prd-approval required reviewer is $PO_LOGIN" \
  || fail "prd-approval required reviewer is not $PO_LOGIN"
[[ $(jq -r .can_admins_bypass <<<"$production") == false ]] && pass 'production blocks administrator bypass' || fail 'production permits administrator bypass'

approval_policies=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/environments/prd-approval/deployment-branch-policies")
production_policies=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/environments/production/deployment-branch-policies")
[[ $(jq '[.branch_policies[] | select(.name == "main" and .type == "branch")] | length' <<<"$approval_policies") -eq 1 ]] \
  && pass 'prd-approval permits only the trusted main execution ref' \
  || fail 'prd-approval main branch policy is missing'
[[ $(jq '[.branch_policies[] | select(.name == "prd" and .type == "branch")] | length' <<<"$production_policies") -eq 1 ]] \
  && pass 'production permits the prd branch' \
  || fail 'production prd branch policy is missing'

rulesets=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/rulesets")
for name in 'Protect prd with PO approval' 'Protect main governance'; do
  id=$(jq -r --arg name "$name" '.[] | select(.name == $name and .enforcement == "active") | .id' <<<"$rulesets" | head -n 1)
  if [[ -z "$id" ]]; then
    fail "$name is missing or inactive"
    continue
  fi
  detail=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/rulesets/$id")
  [[ $(jq '.bypass_actors | length' <<<"$detail") -eq 0 ]] && pass "$name has no bypass actor" || fail "$name has a bypass actor"
  if [[ "$name" == 'Protect prd with PO approval' ]]; then
    contexts=$(jq -r '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort | join(",")' <<<"$detail")
    [[ "$contexts" == 'PO approval for PRD,Validate repository' ]] \
      && pass 'prd requires PO approval and CI checks' \
      || fail "prd required checks are unexpected: $contexts"
  fi
done

if (( failures > 0 )); then
  printf '%s verification failure(s)\n' "$failures" >&2
  exit 1
fi

printf 'Repository Administration configuration: PASS\n'
