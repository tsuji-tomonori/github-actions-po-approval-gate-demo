#!/usr/bin/env bash
set -euo pipefail

for command in node python3; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "$command is required." >&2
    exit 2
  }
done

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
grep -Fq 'workflow_run:' .github/workflows/branch-policy.yml
grep -Fq 'workflows: [CI]' .github/workflows/branch-policy.yml
grep -Fq 'actions: read' .github/workflows/branch-policy.yml
grep -Fq 'checks: write' .github/workflows/branch-policy.yml
grep -Fq 'issues: write' .github/workflows/branch-policy.yml
grep -Fq 'pull-requests: read' .github/workflows/branch-policy.yml
grep -Fq "const checkName = 'Validate branch direction'" .github/workflows/branch-policy.yml
grep -Fq 'run.head_sha' .github/workflows/branch-policy.yml
grep -Fq 'github.rest.pulls.get' .github/workflows/branch-policy.yml
grep -Fq 'head_sha: pr.head.sha' .github/workflows/branch-policy.yml
grep -Fq 'external_id: externalId' .github/workflows/branch-policy.yml
grep -Fq 'github.rest.checks.create' .github/workflows/branch-policy.yml
grep -Fq 'github.rest.checks.update' .github/workflows/branch-policy.yml
grep -Fq 'upsertObservation' .github/workflows/branch-policy.yml
! grep -Fq 'actions/checkout' .github/workflows/branch-policy.yml

# actions/github-script evaluates the inline body inside an async function.
# Recreate that execution context before asking Node to syntax-check it.
python3 - <<'PY' >/tmp/branch-policy-script.mjs
from pathlib import Path
import textwrap

path = Path('.github/workflows/branch-policy.yml')
lines = path.read_text(encoding='utf-8').splitlines()
try:
    start = next(index for index, line in enumerate(lines) if line.strip() == 'script: |')
except StopIteration as exc:
    raise SystemExit('branch-policy.yml has no inline script block') from exc
script = textwrap.dedent('\n'.join(lines[start + 1 :])).rstrip() + '\n'
if not script.strip():
    raise SystemExit('branch-policy.yml inline script is empty')
print('async function __githubScript__() {')
print(textwrap.indent(script, '  '), end='')
print('}')
PY
node --input-type=module --check </tmp/branch-policy-script.mjs

# The PO approval workflow must also remain metadata-only.
! grep -Fq 'actions/checkout' .github/workflows/prd-po-approval.yml

grep -Fq 'branches: [prd]' .github/workflows/deploy-prd.yml
grep -Fq "pr.base.ref === 'prd'" .github/workflows/deploy-prd.yml
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
