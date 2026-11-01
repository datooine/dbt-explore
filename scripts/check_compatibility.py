#!/usr/bin/env python3
"""Check metadata-free parsing and adapter errors without warehouse credentials."""

import json
import os
from pathlib import Path
import shlex
import subprocess
from tempfile import TemporaryDirectory
import tomllib


REPO_ROOT = Path(__file__).resolve().parent.parent
DBT_CMD = shlex.split(os.environ.get("DBT_CMD", "dbt"))


def main():
    package_version = tomllib.loads((REPO_ROOT / "pyproject.toml").read_text())["project"]["version"]
    project_version = next(
        line.partition(":")[2].strip().strip("\"'")
        for line in (REPO_ROOT / "dbt_project.yml").read_text().splitlines()
        if line.startswith("version:")
    )
    if package_version != project_version:
        raise RuntimeError("pyproject.toml and dbt_project.yml versions must match")
    env = {
        **os.environ,
        "DBT_SEND_ANONYMOUS_USAGE_STATS": "false",
        "DBT_DISABLE_VERSION_CHECK": "true",
        "DBT_PARTIAL_PARSE": "false",
        "DBT_WARN_ERROR": "true",
    }
    with TemporaryDirectory(prefix="dbt-explore-compatibility-") as directory:
        artifact_root = Path(directory)

        def run(target, *args, expected_error=None):
            command = [
                *DBT_CMD,
                *args,
                "--project-dir", str(REPO_ROOT),
                "--profiles-dir", str(REPO_ROOT / ".github/dbt/compatibility"),
                "--target", target,
                "--vars", "{dbt_explore_integration_tests: true}",
                "--target-path", str(artifact_root / target),
                "--log-path", str(artifact_root / target / "logs"),
            ]
            print(f"Running: {shlex.join(command)}", flush=True)
            result = subprocess.run(
                command, cwd=REPO_ROOT, env=env, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            )
            print(result.stdout, end="", flush=True)
            if expected_error:
                if result.returncode == 0 or expected_error not in result.stdout:
                    raise RuntimeError(f"Expected compiler error: {expected_error}")
            elif result.returncode:
                raise subprocess.CalledProcessError(result.returncode, command)

        def check_dependencies(target):
            manifest = json.loads((artifact_root / target / "manifest.json").read_text())
            dependencies = manifest["nodes"]["model.dbt_explore.explore_profile_all"]["depends_on"]["nodes"]
            if "model.dbt_explore.explore_fixture" not in dependencies:
                raise RuntimeError("Parsing lost the profiled model dependency")
            population_dependencies = manifest["nodes"]["model.dbt_explore.explore_profile_population"]["depends_on"]["nodes"]
            if "model.dbt_explore.explore_population" not in population_dependencies:
                raise RuntimeError("Parsing lost the population model dependency")
            return manifest

        # No compile is performed: profiling SQL needs real relation metadata.
        run("bigquery", "parse")
        manifest = check_dependencies("bigquery")
        version = manifest["metadata"]["dbt_version"]

        if int(version.split(".")[0]) >= 2:
            # dbt v2 includes Snowflake; Core's development extra is BigQuery-only.
            run("snowflake", "parse")
            check_dependencies("snowflake")
            run(
                "snowflake", "run-operation", "profile_relation",
                "--args", json.dumps({"relation": "placeholder"}),
                expected_error="dbt_explore: profile_relation not implemented for adapter 'snowflake'. Supported: bigquery.",
            )
        else:
            # Call the fallback directly so Core can verify the error without
            # installing another adapter or discovering any warehouse metadata.
            run(
                "bigquery", "run-operation", "default__profile_relation",
                "--args", json.dumps({"relation": "placeholder"}),
                expected_error="dbt_explore: profile_relation not implemented for adapter 'bigquery'. Supported: bigquery.",
            )

        run(
            "bigquery", "run-operation", "profile_relation",
            "--args", json.dumps({"relation": "SELECT 1"}),
            expected_error="relation must be a physical dbt Relation",
        )

    print(f"dbt {version} compatibility checks passed.")


if __name__ == "__main__":
    main()
