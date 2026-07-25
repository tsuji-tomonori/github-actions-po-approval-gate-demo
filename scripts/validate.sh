#!/usr/bin/env bash
set -euo pipefail

for script in \
  scripts/deploy-prd.sh \
  scripts/configure-repository.sh \
  scripts/verify-repository.sh; do
  bash -n "$script"
done

for file in \
  .github/workflows/ci.yml \
  .github/workflows/prd-po-approval.yml \
  .github/workflows/deploy-prd.yml \
  .github/CODEOWNERS \
  scripts/configure-repository.sh \
  scripts/verify-repository.sh \
  README.md; do
  test -s "$file"
done

grep -Fq 'pull_request_target:' .github/workflows/prd-po-approval.yml
grep -Fq 'environment:' .github/workflows/prd-po-approval.yml
grep -Fq 'name: prd-approval' .github/workflows/prd-po-approval.yml
grep -Fq 'current.data.head.sha !== approvedSha' .github/workflows/prd-po-approval.yml
grep -Fq 'branches: [prd]' .github/workflows/deploy-prd.yml
grep -Fq "pr.base.ref === 'prd'" .github/workflows/deploy-prd.yml
! grep -Fq 'actions/checkout' .github/workflows/prd-po-approval.yml
grep -Fq 'can_admins_bypass: false' scripts/configure-repository.sh
grep -Fq 'PO approval for PRD' scripts/configure-repository.sh
grep -Fq 'Validate repository' scripts/configure-repository.sh

echo 'Repository contracts: PASS'
