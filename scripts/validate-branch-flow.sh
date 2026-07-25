#!/usr/bin/env bash
set -euo pipefail

base_ref=${1:-${GITHUB_BASE_REF:-}}
head_ref=${2:-${GITHUB_HEAD_REF:-}}

if [[ -z "$base_ref" || -z "$head_ref" ]]; then
  echo 'base and head branch names are required.' >&2
  exit 2
fi

case "$base_ref" in
  main|prd) ;;
  *)
    echo "unsupported pull request target: $base_ref" >&2
    exit 3
    ;;
esac

if [[ "$head_ref" == prd ]]; then
  echo 'The prd branch is deployment-only and must never be merged back into another branch.' >&2
  echo 'Create a change branch from main, then merge that branch into main or prd.' >&2
  exit 4
fi

printf 'Branch flow: PASS (%s -> %s)\n' "$head_ref" "$base_ref"
