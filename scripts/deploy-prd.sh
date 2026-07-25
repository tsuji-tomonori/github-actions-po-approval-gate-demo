#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${SOURCE_PULL_REQUEST:?SOURCE_PULL_REQUEST is required}"

mkdir -p artifacts
python3 - <<'PY'
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path

payload = {
    "schema_version": "production-deployment-evidence/v1",
    "repository": os.environ["GITHUB_REPOSITORY"],
    "commit_sha": os.environ["GITHUB_SHA"],
    "workflow_run_id": os.environ["GITHUB_RUN_ID"],
    "source_pull_request": int(os.environ["SOURCE_PULL_REQUEST"]),
    "deployed_at": datetime.now(timezone.utc).isoformat(),
    "mode": "simulation",
}
Path("artifacts/deployment.json").write_text(
    json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
    encoding="utf-8",
)
print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
PY
