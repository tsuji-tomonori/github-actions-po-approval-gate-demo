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
reviewer_ids=$(jq -c '[.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]?.reviewer.id] | sort' <<<"$approval")
[[ "$reviewer_ids" == "[$po_id]" ]] \
  && pass "prd-approval required reviewer is exactly $PO_LOGIN" \
  || fail "prd-approval reviewers are unexpected: $reviewer_ids"
[[ $(jq -r .can_admins_bypass <<<"$production") == false ]] && pass 'production blocks administrator bypass' || fail 'production permits administrator bypass'

approval_policies=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/environments/prd-approval/deployment-branch-policies")
production_policies=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/environments/production/deployment-branch-policies")
approval_policy_names=$(jq -r '[.branch_policies[] | select(.type == "branch") | .name] | sort | join(",")' <<<"$approval_policies")
production_policy_names=$(jq -r '[.branch_policies[] | select(.type == "branch") | .name] | sort | join(",")' <<<"$production_policies")
[[ "$approval_policy_names" == main ]] \
  && pass 'prd-approval permits only the trusted main execution ref' \
  || fail "prd-approval branch policies are unexpected: $approval_policy_names"
[[ "$production_policy_names" == prd ]] \
  && pass 'production permits only the prd branch' \
  || fail "production branch policies are unexpected: $production_policy_names"

rulesets=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/rulesets")
for name in 'Protect prd with PO approval' 'Protect main governance'; do
  id=$(jq -r --arg name "$name" '.[] | select(.name == $name and .enforcement == "active") | .id' <<<"$rulesets" | head -n 1)
  if [[ -z "$id" ]]; then
    fail "$name is missing or inactive"
    continue
  fi
  detail=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$FULL_REPO/rulesets/$id")
  [[ $(jq '.bypass_actors | length' <<<"$detail") -eq 0 ]] && pass "$name has no bypass actor" || fail "$name has a bypass actor"
  contexts=$(jq -r '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort | join(",")' <<<"$detail")
  if [[ "$name" == 'Protect prd with PO approval' ]]; then
    expected='PO approval for PRD,Validate branch direction,Validate repository'
  else
    expected='Validate branch direction,Validate repository'
  fi
  [[ "$contexts" == "$expected" ]] \
    && pass "$name requires the expected checks" \
    || fail "$name required checks are unexpected: $contexts"
done

if (( failures > 0 )); then
  printf '%s verification failure(s)\n' "$failures" >&2
  exit 1
fi

printf 'Repository Administration configuration: PASS\n'
