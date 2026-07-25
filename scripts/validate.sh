#!/usr/bin/env bash
set -euo pipefail

bash -n scripts/deploy-prd.sh
for file in \
  .github/workflows/ci.yml \
  .github/workflows/prd-po-approval.yml \
  .github/workflows/deploy-prd.yml \
  .github/CODEOWNERS \
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

echo 'Repository contracts: PASS'
