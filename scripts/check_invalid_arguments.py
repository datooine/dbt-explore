#!/usr/bin/env python3
"""Assert that invalid public arguments produce actionable compilation errors.

Requires physical integration fixtures, but never executes generated profiling SQL.
Additional arguments are forwarded to dbt; DBT_CMD selects the runtime.
"""

import argparse
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parent.parent
CASES = {
    "relation_sql": "relation must be a physical dbt Relation",
    "relation_mapping": "relation must be a physical dbt Relation",
    "relation_ephemeral": "must be a physical",
    "columns_string": "columns must be a list",
    "columns_empty": "No fields remain to profile",
    "columns_unknown": "columns contains an unknown or unsupported path",
    "exclude_unknown": "exclude_columns contains an unknown or unsupported path",
    "exclude_all": "No fields remain to profile",
    "where_not_sql": "where must be a non-empty SQL predicate",
    "groups_mutually_exclusive": "group_by and grouping_sets are mutually exclusive",
    "groups_unknown": "grouping dimensions contains an unknown or unsupported path",
    "groups_parent": "grouping dimensions contains an unknown or unsupported path",
    "groups_array": "Grouping requires a supported scalar, groupable path",
    "groups_json": "Grouping requires a supported scalar, groupable path",
    "groups_duplicate_dimension": "Grouping dimensions must not be repeated",
    "groups_empty_sets": "grouping_sets must be a non-empty list of lists",
    "groups_string_set": "grouping_sets must be a list",
    "groups_null_set": "grouping_sets entries must be lists",
    "groups_duplicate_sets": "Duplicate grouping sets are not supported",
    "quantiles_negative": "quantiles must be a non-negative integer",
    "quantiles_fraction": "quantiles must be a non-negative integer",
    "quantiles_boolean": "quantiles must be a non-negative integer",
    "quantiles_string": "quantiles must be a non-negative integer",
    "percentiles_range": "extra_percentiles must contain only integers from 0 through 100",
    "percentiles_fraction": "extra_percentiles must contain only integers from 0 through 100",
    "percentiles_boolean": "extra_percentiles must contain only integers from 0 through 100",
    "top_negative": "top_n must be a non-negative integer",
    "top_fraction": "top_n must be a non-negative integer",
    "top_boolean": "top_n must be a non-negative integer",
    "population_missing": "require a population relation",
    "population_where_missing": "require a population relation",
    "population_not_subset": "population_group_by must be a subset",
    "population_incompatible_sets": "must be present in every profile grouping set",
    "population_incompatible_types": "Population grouping types must match",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", action="append", choices=sorted(CASES), dest="cases")
    parser.add_argument("--dbt-command", default=os.environ.get("DBT_CMD", "dbt"))
    parser.add_argument(
        "--in-process", action="store_true",
        help="Use dbt Core's Python runner; run this script in the Core environment.",
    )
    options, dbt_args = parser.parse_known_args()
    command_prefix = shlex.split(options.dbt_command)
    env = {**os.environ, "DBT_SEND_ANONYMOUS_USAGE_STATS": "false"}
    runner = None
    if options.in_process:
        from dbt.cli.main import dbtRunner

        os.environ["DBT_SEND_ANONYMOUS_USAGE_STATS"] = "false"
        runner = dbtRunner()
    failures = []
    for case in options.cases or CASES:
        command = [
            *command_prefix, "run-operation", "test_invalid_profile_arguments",
            "--args", json.dumps({"case": case}),
            "--project-dir", str(REPO_ROOT),
            "--vars", "{dbt_explore_integration_tests: true}",
            *dbt_args,
        ]
        if runner is None:
            result = subprocess.run(
                command, cwd=REPO_ROOT, env=env, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            )
            succeeded, output = result.returncode == 0, result.stdout
        else:
            captured = StringIO()
            with redirect_stdout(captured), redirect_stderr(captured):
                result = runner.invoke(command[len(command_prefix):])
            succeeded = result.success
            output = captured.getvalue() + (str(result.exception) if result.exception else "")
        if succeeded or CASES[case] not in output:
            failures.append(case)
            print(f"FAIL {case}: expected {CASES[case]!r}", flush=True)
            print(output, end="", flush=True)
        else:
            print(f"PASS {case}", flush=True)
    if failures:
        print(f"Invalid argument checks failed: {', '.join(failures)}", file=sys.stderr)
        return 1
    print(f"All {len(options.cases or CASES)} invalid argument checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
