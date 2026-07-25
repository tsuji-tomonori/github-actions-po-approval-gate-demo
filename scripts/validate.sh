#!/usr/bin/env bash
set -euo pipefail

for script in \
  scripts/deploy-prd.sh \
  scripts/configure-repository.sh \
  scripts/verify-repository.sh \
  scripts/validate-branch-flow.sh; do
  bash -n "$script"
done

for file in \
  .github/workflows/ci.yml \
  .github/workflows/branch-policy.yml \
  .github/workflows/prd-po-approval.yml \
  .github/workflows/deploy-prd.yml \
  .github/CODEOWNERS \
  scripts/configure-repository.sh \
  scripts/verify-repository.sh \
  scripts/validate-branch-flow.sh \
  README.md; do
  test -s "$file"
done

grep -Fq 'pull_request_target:' .github/workflows/prd-po-approval.yml
grep -Fq 'environment:' .github/workflows/prd-po-approval.yml
grep -Fq 'name: prd-approval' .github/workflows/prd-po-approval.yml
grep -Fq 'current.data.head.sha !== approvedSha' .github/workflows/prd-po-approval.yml
grep -Fq 'pull_request_target:' .github/workflows/branch-policy.yml
grep -Fq 'checks: write' .github/workflows/branch-policy.yml
grep -Fq 'issues: write' .github/workflows/branch-policy.yml
grep -Fq "const checkName = 'Validate branch direction'" .github/workflows/branch-policy.yml
grep -Fq 'head_sha: pr.head.sha' .github/workflows/branch-policy.yml
grep -Fq 'external_id: externalId' .github/workflows/branch-policy.yml
grep -Fq 'github.rest.checks.create' .github/workflows/branch-policy.yml
grep -Fq 'github.rest.checks.update' .github/workflows/branch-policy.yml
! grep -Fq 'actions/checkout' .github/workflows/branch-policy.yml
grep -Fq 'branches: [prd]' .github/workflows/deploy-prd.yml
grep -Fq "pr.base.ref === 'prd'" .github/workflows/deploy-prd.yml
! grep -Fq 'actions/checkout' .github/workflows/prd-po-approval.yml
grep -Fq 'can_admins_bypass: false' scripts/configure-repository.sh
grep -Fq 'PO approval for PRD' scripts/configure-repository.sh
grep -Fq 'Validate branch direction' scripts/configure-repository.sh
grep -Fq 'Validate repository' scripts/configure-repository.sh

bash scripts/validate-branch-flow.sh main feature/example
bash scripts/validate-branch-flow.sh prd main
if bash scripts/validate-branch-flow.sh main prd; then
  echo 'reverse prd -> main flow was unexpectedly accepted' >&2
  exit 1
fi

echo 'Repository contracts: PASS'
