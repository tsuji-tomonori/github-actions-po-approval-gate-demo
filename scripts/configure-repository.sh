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
PREVENT_SELF_REVIEW=${PREVENT_SELF_REVIEW:-false}
FULL_REPO="$OWNER/$REPO"
API_VERSION=2026-03-10
PRD_RULESET_NAME='Protect prd with PO approval'
MAIN_RULESET_NAME='Protect main governance'

case "$PREVENT_SELF_REVIEW" in
  true|false) ;;
  *) echo 'PREVENT_SELF_REVIEW must be true or false.' >&2; exit 3 ;;
esac

visibility=$(gh api "repos/$FULL_REPO" --jq .visibility)
[[ "$visibility" == public ]] || {
  echo "$FULL_REPO must be public for this verification repository." >&2
  exit 4
}

po_id=$(gh api "users/$PO_LOGIN" --jq .id)
actions_app_id=$(gh api apps/github-actions --jq .id)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

put_environment() {
  local environment=$1
  local reviewers_json=$2
  local prevent_self_review=$3
  jq -n \
    --argjson reviewers "$reviewers_json" \
    --argjson prevent_self_review "$prevent_self_review" \
    '{
      wait_timer: 0,
      can_admins_bypass: false,
      prevent_self_review: $prevent_self_review,
      reviewers: $reviewers,
      deployment_branch_policy: {
        protected_branches: false,
        custom_branch_policies: true
      }
    }' >"$workdir/environment.json"

  gh api --method PUT \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "repos/$FULL_REPO/environments/$environment" \
    --input "$workdir/environment.json" >/dev/null
}

ensure_branch_policy() {
  local environment=$1
  local branch=$2
  local policy_id
  policy_id=$(gh api \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "repos/$FULL_REPO/environments/$environment/deployment-branch-policies" \
    --jq ".branch_policies[] | select(.name == \"$branch\" and .type == \"branch\") | .id" \
    | head -n 1 || true)

  if [[ -z "$policy_id" ]]; then
    gh api --method POST \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "repos/$FULL_REPO/environments/$environment/deployment-branch-policies" \
      -f "name=$branch" \
      -f type=branch >/dev/null
  fi
}

upsert_ruleset() {
  local name=$1
  local payload=$2
  local ruleset_id
  ruleset_id=$(gh api \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "repos/$FULL_REPO/rulesets" \
    --jq ".[] | select(.name == \"$name\") | .id" \
    | head -n 1 || true)

  if [[ -n "$ruleset_id" ]]; then
    gh api --method PUT \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "repos/$FULL_REPO/rulesets/$ruleset_id" \
      --input "$payload" >/dev/null
  else
    gh api --method POST \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "repos/$FULL_REPO/rulesets" \
      --input "$payload" >/dev/null
  fi
}

put_environment prd-approval "[{\"type\":\"User\",\"id\":$po_id}]" "$PREVENT_SELF_REVIEW"
ensure_branch_policy prd-approval main
put_environment production '[]' false
ensure_branch_policy production prd

jq -n \
  --arg name "$PRD_RULESET_NAME" \
  --argjson actions_app_id "$actions_app_id" \
  '{
    name: $name,
    target: "branch",
    enforcement: "active",
    bypass_actors: [],
    conditions: {ref_name: {include: ["refs/heads/prd"], exclude: []}},
    rules: [
      {type: "deletion"},
      {type: "non_fast_forward"},
      {
        type: "pull_request",
        parameters: {
          allowed_merge_methods: ["squash", "merge"],
          dismiss_stale_reviews_on_push: true,
          require_code_owner_review: false,
          require_last_push_approval: false,
          required_approving_review_count: 0,
          required_review_thread_resolution: true
        }
      },
      {
        type: "required_status_checks",
        parameters: {
          do_not_enforce_on_create: true,
          strict_required_status_checks_policy: true,
          required_status_checks: [
            {context: "PO approval for PRD", integration_id: $actions_app_id},
            {context: "Validate branch direction", integration_id: $actions_app_id},
            {context: "Validate repository", integration_id: $actions_app_id}
          ]
        }
      }
    ]
  }' >"$workdir/prd-ruleset.json"

jq -n \
  --arg name "$MAIN_RULESET_NAME" \
  --argjson actions_app_id "$actions_app_id" \
  '{
    name: $name,
    target: "branch",
    enforcement: "active",
    bypass_actors: [],
    conditions: {ref_name: {include: ["refs/heads/main"], exclude: []}},
    rules: [
      {type: "deletion"},
      {type: "non_fast_forward"},
      {
        type: "pull_request",
        parameters: {
          allowed_merge_methods: ["squash", "merge", "rebase"],
          dismiss_stale_reviews_on_push: true,
          require_code_owner_review: false,
          require_last_push_approval: false,
          required_approving_review_count: 0,
          required_review_thread_resolution: true
        }
      },
      {
        type: "required_status_checks",
        parameters: {
          do_not_enforce_on_create: true,
          strict_required_status_checks_policy: true,
          required_status_checks: [
            {context: "Validate branch direction", integration_id: $actions_app_id},
            {context: "Validate repository", integration_id: $actions_app_id}
          ]
        }
      }
    ]
  }' >"$workdir/main-ruleset.json"

upsert_ruleset "$PRD_RULESET_NAME" "$workdir/prd-ruleset.json"
upsert_ruleset "$MAIN_RULESET_NAME" "$workdir/main-ruleset.json"

printf 'Configured %s\n' "$FULL_REPO"
printf 'PO required reviewer: %s (id=%s)\n' "$PO_LOGIN" "$po_id"
printf 'Prevent self-review: %s\n' "$PREVENT_SELF_REVIEW"
printf 'Next: ./scripts/verify-repository.sh %s %s %s\n' "$OWNER" "$REPO" "$PO_LOGIN"
