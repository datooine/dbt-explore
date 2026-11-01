#!/usr/bin/env python3
"""Compare shared and per-column profiling on an existing BigQuery relation."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shlex
import statistics
import subprocess
import sys
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
VARIANTS = {
    "shared": "profile_relation_benchmark_shared",
    "per_column": "profile_relation_benchmark_per_column",
}


def json_argument(value: str) -> Any:
    try:
        return json.loads(value)
    except json.JSONDecodeError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--relation", required=True, help="PROJECT.DATASET.TABLE or VIEW")
    parser.add_argument(
        "--columns", required=True, nargs="+", help="At least two scalar-leaf or ARRAY paths."
    )
    parser.add_argument("--grouping-sets", type=json_argument, default=[[]])
    parser.add_argument("--where", help="Trusted profile predicate without WHERE.")
    parser.add_argument("--quantiles", type=int, default=4)
    parser.add_argument("--extra-percentiles", type=json_argument, default=[])
    parser.add_argument("--top-n", type=int, default=10)
    parser.add_argument("--project", help="BigQuery billing/job project; defaults to source project.")
    parser.add_argument("--location", default="EU")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--maximum-bytes-billed", type=int)
    parser.add_argument("--dbt-command", default="dbt", help="dbt executable or command prefix.")
    parser.add_argument("--profile")
    parser.add_argument("--profiles-dir", type=Path)
    parser.add_argument("--target")
    parser.add_argument("--output", type=Path, default=ROOT / "target/benchmark/results.json")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Estimate bytes; do not execute queries.")
    mode.add_argument("--compile-only", action="store_true", help="Compile SQL without benchmark jobs.")
    args = parser.parse_args()
    parts = args.relation.strip("`").split(".")
    if len(parts) != 3 or not all(parts):
        parser.error("--relation must have the form PROJECT.DATASET.TABLE")
    args.source = dict(zip(("database", "schema", "identifier"), parts, strict=True))
    if len(args.columns) < 2 or len(set(args.columns)) != len(args.columns):
        parser.error("--columns requires at least two distinct field paths")
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    if args.quantiles < 0 or args.top_n < 0:
        parser.error("--quantiles and --top-n must be non-negative")
    if args.maximum_bytes_billed is not None and args.maximum_bytes_billed < 1:
        parser.error("--maximum-bytes-billed must be positive")
    if not isinstance(args.grouping_sets, list) or not args.grouping_sets:
        parser.error("--grouping-sets must be a non-empty JSON array of arrays")
    if any(
        not isinstance(group, list)
        or any(not isinstance(path, str) or not path for path in group)
        for group in args.grouping_sets
    ):
        parser.error("--grouping-sets must contain arrays of non-empty field-path strings")
    if not isinstance(args.extra_percentiles, list) or any(
        isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 100
        for value in args.extra_percentiles
    ):
        parser.error("--extra-percentiles must be a JSON array of integers from 0 through 100")
    if not shlex.split(args.dbt_command):
        parser.error("--dbt-command must not be empty")
    return args


def run_dbt(command: list[str]) -> str:
    process = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if process.returncode:
        raise RuntimeError(
            f"dbt exited with status {process.returncode}:\n"
            f"{process.stdout[-6000:]}\n{process.stderr[-6000:]}"
        )
    return process.stdout.strip()


def compile_queries(args: argparse.Namespace) -> tuple[dict[str, str], dict[str, Any]]:
    variables = {
        "dbt_explore_benchmark": True,
        "dbt_explore_benchmark_relation": args.source,
        "dbt_explore_benchmark_columns": args.columns,
        "dbt_explore_benchmark_grouping_sets": args.grouping_sets,
        "dbt_explore_benchmark_where": args.where,
        "dbt_explore_benchmark_quantiles": args.quantiles,
        "dbt_explore_benchmark_extra_percentiles": args.extra_percentiles,
        "dbt_explore_benchmark_top_n": args.top_n,
    }
    target_path = ROOT / "target/benchmark/compiled"
    command = shlex.split(args.dbt_command)
    options = []
    for key in ("profile", "profiles_dir", "target"):
        value = getattr(args, key)
        if value is not None:
            options.extend(("--" + key.replace("_", "-"), str(value)))
    run_dbt(
        command + [
            "compile",
            "--select",
            *VARIANTS.values(),
            "--vars",
            json.dumps(variables),
            "--target-path",
            str(target_path),
            "--no-partial-parse",
        ] + options
    )
    sql = {}
    for variant, name in VARIANTS.items():
        path = target_path / "compiled/dbt_explore/analyses" / f"{name}.sql"
        if not path.is_file():
            raise RuntimeError(f"dbt did not write expected compiled analysis: {path}")
        sql[variant] = path.read_text()
    metadata = {
        "dbt_version": run_dbt(command + ["--version"]),
        "variables": variables,
        "compiled_directory": str(target_path),
        "queries": {
            variant: {"sha256": hashlib.sha256(query.encode()).hexdigest()}
            for variant, query in sql.items()
        },
    }
    return sql, metadata


def execution_stage(stage: Any) -> dict[str, Any]:
    """Serialize public QueryPlanEntry properties; job API repr omits statistics."""
    return {
        "id": stage.entry_id,
        "name": stage.name,
        "status": stage.status,
        "inputStages": stage.input_stages,
        "parallelInputs": stage.parallel_inputs,
        "completedParallelInputs": stage.completed_parallel_inputs,
        "recordsRead": stage.records_read,
        "recordsWritten": stage.records_written,
        "shuffleOutputBytes": stage.shuffle_output_bytes,
        "shuffleOutputBytesSpilled": stage.shuffle_output_bytes_spilled,
        "slotMs": stage.slot_ms,
        "waitMsAvg": stage.wait_ms_avg,
        "readMsAvg": stage.read_ms_avg,
        "computeMsAvg": stage.compute_ms_avg,
        "writeMsAvg": stage.write_ms_avg,
        "steps": [{"kind": step.kind, "substeps": step.substeps} for step in stage.steps],
    }


def benchmark(args: argparse.Namespace, sql: dict[str, str]) -> list[dict[str, Any]]:
    try:
        from google.cloud import bigquery
    except ImportError as exc:
        raise RuntimeError("Install the benchmark extra: uv sync --extra dev --extra benchmark") from exc

    client = bigquery.Client(project=args.project or args.source["database"], location=args.location)
    records = []
    repetitions = 1 if args.dry_run else args.repeats
    for iteration in range(1, repetitions + 1):
        order = list(VARIANTS) if iteration % 2 else list(reversed(VARIANTS))
        for variant in order:
            config = bigquery.QueryJobConfig(
                dry_run=args.dry_run,
                use_query_cache=False,
                labels={"package": "dbt_explore", "benchmark": variant},
            )
            if args.maximum_bytes_billed is not None:
                config.maximum_bytes_billed = args.maximum_bytes_billed
            started = time.monotonic()
            job = client.query(sql[variant], job_config=config, location=args.location)
            rows = None if args.dry_run else job.result()
            elapsed = time.monotonic() - started
            if not args.dry_run:
                job.reload()  # Fetch complete stage metadata after the timed execution.
            record = {
                "variant": variant,
                "iteration": iteration,
                "job_id": job.job_id,
                "dry_run": args.dry_run,
                "elapsed_seconds": None if args.dry_run else elapsed,
                "total_bytes_processed": job.total_bytes_processed,
                "total_bytes_billed": job.total_bytes_billed,
                "slot_millis": None if args.dry_run else job.slot_millis,
                "cache_hit": job.cache_hit,
                "output_rows": None if rows is None else rows.total_rows,
                "execution_stages": [] if args.dry_run else [
                    execution_stage(stage) for stage in job.query_plan
                ],
            }
            records.append(record)
            print(
                f"{variant} repetition {iteration}: "
                f"bytes={record['total_bytes_processed']} slot_ms={record['slot_millis']} "
                f"stages={len(record['execution_stages'])}"
            )
    return records


def main() -> int:
    args = arguments()
    sql, metadata = compile_queries(args)
    records = [] if args.compile_only else benchmark(args, sql)
    summary = {}
    for variant in VARIANTS:
        runs = [record for record in records if record["variant"] == variant]
        summary[variant] = {}
        for metric in ("total_bytes_processed", "slot_millis", "elapsed_seconds"):
            values = [run[metric] for run in runs if run[metric] is not None]
            summary[variant][metric + "_median"] = statistics.median(values) if values else None
    report = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "mode": "compile_only" if args.compile_only else "dry_run" if args.dry_run else "executed",
        "job_project": args.project or args.source["database"],
        "location": args.location,
        "maximum_bytes_billed": args.maximum_bytes_billed,
        **metadata,
        "runs": records,
        "summary": summary,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
