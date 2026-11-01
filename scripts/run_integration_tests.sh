#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: scripts/run_integration_tests.sh [additional dbt arguments]

Builds fixtures before compiling metadata-dependent profile models, then builds
the profiles and runs the BigQuery integration tests and invalid argument checks.
Uses normal dbt profile lookup; set DBT_PROFILES_DIR or pass --profiles-dir.
Override the dbt command with DBT_CMD. Set DBT_EXPLORE_TEST_PREFIX to isolate
warehouse relations (include a trailing underscore).
USAGE
  exit 0
fi

DBT_CMD=${DBT_CMD:-dbt}
IFS=' ' read -r -a DBT_CMD_ARR <<< "$DBT_CMD"
TEST_VARS='{dbt_explore_integration_tests: true}'

"${DBT_CMD_ARR[@]}" run --select path:models/inputs --vars "$TEST_VARS" "$@"
"${DBT_CMD_ARR[@]}" compile --select path:models/profiles --vars "$TEST_VARS" "$@"
"${DBT_CMD_ARR[@]}" run --select path:models/profiles --vars "$TEST_VARS" "$@"
"${DBT_CMD_ARR[@]}" test --select path:tests/integration --vars "$TEST_VARS" "$@"
python3 scripts/check_invalid_arguments.py "$@"
