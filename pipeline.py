from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from time import perf_counter
from typing import Any

import pandas as pd

from config import (
    DUCKDB_PATH,
    validate_config,
)

from ingest import ingest_all
from validate import validate_all
from transform import transform_all
from reconcile import reconcile_all
from load_duckdb import (
    load_all_to_duckdb,
    inspect_database,
)


# ============================================================
# Stage result
# ============================================================

@dataclass
class StageResult:
    name: str
    started_at_utc: datetime
    completed_at_utc: datetime
    duration_seconds: float
    summary: dict[str, Any]


# ============================================================
# Helpers
# ============================================================

def utc_now() -> datetime:
    return datetime.now(
        timezone.utc
    )


def summarize_dataframe(
    df: pd.DataFrame,
) -> dict[str, int]:
    return {
        "rows": len(df),
        "columns": len(df.columns),
    }


def summarize_dataset_group(
    datasets: dict[str, pd.DataFrame],
) -> dict[str, dict[str, int]]:
    return {
        name: summarize_dataframe(df)
        for name, df in datasets.items()
    }


def print_stage_start(
    stage_name: str,
) -> None:
    print()
    print(
        f"=== {stage_name.upper()} ==="
    )


def print_dataset_summary(
    datasets: dict[str, pd.DataFrame],
) -> None:
    for name, df in datasets.items():
        print(
            f"{name}: "
            f"{len(df):,} rows | "
            f"{len(df.columns)} columns"
        )


def print_duration(
    duration_seconds: float,
) -> None:
    print(
        f"Duration: "
        f"{duration_seconds:.2f}s"
    )


# ============================================================
# Stage runner
# ============================================================

def run_stage(
    stage_name: str,
    function,
    *args,
    summary_builder=None,
    **kwargs,
):
    print_stage_start(
        stage_name
    )

    started_at_utc = utc_now()
    started_perf = perf_counter()

    try:
        result = function(
            *args,
            **kwargs,
        )

    except Exception as error:
        duration_seconds = (
            perf_counter()
            - started_perf
        )

        print(
            f"{stage_name} FAILED "
            f"after "
            f"{duration_seconds:.2f}s"
        )

        raise RuntimeError(
            f"Pipeline failed during "
            f"{stage_name}"
        ) from error

    completed_at_utc = utc_now()

    duration_seconds = (
        perf_counter()
        - started_perf
    )

    if summary_builder is None:
        summary = {}

    else:
        summary = summary_builder(
            result
        )

    print_duration(
        duration_seconds
    )

    return (
        result,
        StageResult(
            name=stage_name,
            started_at_utc=started_at_utc,
            completed_at_utc=completed_at_utc,
            duration_seconds=duration_seconds,
            summary=summary,
        ),
    )


# ============================================================
# Stage summary builders
# ============================================================

def summarize_ingest(
    datasets: dict[str, pd.DataFrame],
) -> dict[str, dict[str, int]]:
    print_dataset_summary(
        datasets
    )

    return summarize_dataset_group(
        datasets
    )


def summarize_validate(
    datasets: dict[str, pd.DataFrame],
) -> dict[str, dict[str, int]]:
    print_dataset_summary(
        datasets
    )

    return summarize_dataset_group(
        datasets
    )


def summarize_transform(
    datasets: dict[str, pd.DataFrame],
) -> dict[str, dict[str, int]]:
    print_dataset_summary(
        datasets
    )

    return summarize_dataset_group(
        datasets
    )


def summarize_reconcile(
    datasets: dict[str, pd.DataFrame],
) -> dict[str, dict[str, int]]:
    print_dataset_summary(
        datasets
    )

    return summarize_dataset_group(
        datasets
    )


def summarize_load(
    load_result: dict[str, int],
) -> dict[str, int]:
    for table_name, rows in (
        load_result.items()
    ):
        print(
            f"{table_name}: "
            f"{rows:,} rows"
        )

    return dict(
        load_result
    )


# ============================================================
# Cross-stage verification
# ============================================================

def verify_pipeline_consistency(
    validated: dict[str, pd.DataFrame],
    transformed: dict[str, pd.DataFrame],
    reconciled: dict[str, pd.DataFrame],
    load_result: dict[str, int],
) -> None:
    """
    Verify key row-count relationships
    across locked pipeline stages.
    """

    print_stage_start(
        "VERIFY"
    )

    # --------------------------------------------------------
    # TradingView
    # --------------------------------------------------------

    validated_tv = (
        validated[
            "tradingview_daily"
        ]
    )

    transformed_tv = (
        transformed[
            "tradingview_daily"
        ]
    )

    if len(
        validated_tv
    ) != len(
        transformed_tv
    ):
        raise RuntimeError(
            "TradingView row-count mismatch: "
            f"validated={len(validated_tv):,}, "
            f"transformed={len(transformed_tv):,}"
        )

    # --------------------------------------------------------
    # Dukascopy
    # --------------------------------------------------------

    validated_duka = (
        validated[
            "dukascopy_1h"
        ]
    )

    transformed_duka = (
        transformed[
            "dukascopy_1h"
        ]
    )

    if (
        "eligible_for_trusted"
        not in validated_duka.columns
    ):
        raise RuntimeError(
            "validated.dukascopy_1h "
            "is missing eligible_for_trusted"
        )

    expected_trusted_rows = int(
        validated_duka[
            "eligible_for_trusted"
        ]
        .fillna(False)
        .astype(bool)
        .sum()
    )

    if len(
        transformed_duka
    ) != expected_trusted_rows:
        raise RuntimeError(
            "Dukascopy trusted-row mismatch: "
            f"expected="
            f"{expected_trusted_rows:,}, "
            f"transformed="
            f"{len(transformed_duka):,}"
        )

    # --------------------------------------------------------
    # Reconciliation
    # --------------------------------------------------------

    reconciled_tv = (
        reconciled[
            "tradingview_daily"
        ]
    )

    if reconciled_tv.empty:
        raise RuntimeError(
            "Reconciliation output is empty"
        )

    # --------------------------------------------------------
    # DuckDB load result
    # --------------------------------------------------------

    expected_loaded_rows = {
        "validated_tradingview_daily":
            len(validated_tv),

        "validated_dukascopy_1h":
            len(validated_duka),

        "market_bars_tradingview_daily":
            len(transformed_tv),

        "market_bars_dukascopy_1h":
            len(transformed_duka),

        "provider_reconciliation_daily":
            len(reconciled_tv),
    }

    for table_name, expected_rows in (
        expected_loaded_rows.items()
    ):

        actual_rows = (
            load_result.get(
                table_name
            )
        )

        if actual_rows is None:
            raise RuntimeError(
                "Missing load result for "
                f"{table_name}"
            )

        if actual_rows != expected_rows:
            raise RuntimeError(
                f"{table_name} load mismatch: "
                f"expected={expected_rows:,}, "
                f"actual={actual_rows:,}"
            )

    print(
        "TradingView validated "
        "→ transformed: PASS"
    )

    print(
        "Dukascopy eligible "
        "→ transformed: PASS"
    )

    print(
        "Reconciliation output: PASS"
    )

    print(
        "DuckDB load counts: PASS"
    )


# ============================================================
# Final database verification
# ============================================================

def verify_database_snapshot(
    load_result: dict[str, int],
) -> pd.DataFrame:

    print_stage_start(
        "DATABASE SNAPSHOT"
    )

    database_tables = (
        inspect_database()
    )

    if database_tables.empty:
        raise RuntimeError(
            "DuckDB contains no tables"
        )

    row_count_map = dict(
        zip(
            database_tables[
                "table_name"
            ],
            database_tables[
                "rows"
            ],
        )
    )

    for table_name, expected_rows in (
        load_result.items()
    ):

        if table_name not in (
            row_count_map
        ):
            raise RuntimeError(
                f"Missing DuckDB table: "
                f"{table_name}"
            )

        actual_rows = int(
            row_count_map[
                table_name
            ]
        )

        if actual_rows != expected_rows:
            raise RuntimeError(
                f"DuckDB snapshot mismatch "
                f"for {table_name}: "
                f"expected={expected_rows:,}, "
                f"actual={actual_rows:,}"
            )

    print(
        database_tables
        .to_string(
            index=False
        )
    )

    print()
    print(
        "Database snapshot: PASS"
    )

    return database_tables


# ============================================================
# Full pipeline
# ============================================================

def run_pipeline() -> dict[str, Any]:

    pipeline_started_at_utc = (
        utc_now()
    )

    pipeline_started_perf = (
        perf_counter()
    )

    print(
        "========================================"
    )

    print(
        "MY DECISION WORKBENCH"
    )

    print(
        "Pipeline V1"
    )

    print(
        "========================================"
    )

    print(
        f"Started: "
        f"{pipeline_started_at_utc.isoformat()}"
    )

    print(
        f"DuckDB: {DUCKDB_PATH}"
    )

    # --------------------------------------------------------
    # Config
    # --------------------------------------------------------

    print_stage_start(
        "CONFIG"
    )

    config_started = (
        perf_counter()
    )

    validate_config()

    config_duration = (
        perf_counter()
        - config_started
    )

    print(
        "Configuration: PASS"
    )

    print_duration(
        config_duration
    )

    config_stage = StageResult(
        name="CONFIG",
        started_at_utc=(
            pipeline_started_at_utc
        ),
        completed_at_utc=utc_now(),
        duration_seconds=(
            config_duration
        ),
        summary={
            "status": "PASS"
        },
    )

    # --------------------------------------------------------
    # Ingest
    # --------------------------------------------------------

    raw, ingest_stage = run_stage(
        "INGEST",
        ingest_all,
        summary_builder=(
            summarize_ingest
        ),
    )

    # --------------------------------------------------------
    # Validate
    # --------------------------------------------------------

    validated, validate_stage = (
        run_stage(
            "VALIDATE",
            validate_all,
            raw,
            summary_builder=(
                summarize_validate
            ),
        )
    )

    # --------------------------------------------------------
    # Transform
    # --------------------------------------------------------

    transformed, transform_stage = (
        run_stage(
            "TRANSFORM",
            transform_all,
            validated,
            summary_builder=(
                summarize_transform
            ),
        )
    )

    # --------------------------------------------------------
    # Reconcile
    # --------------------------------------------------------

    reconciled, reconcile_stage = (
        run_stage(
            "RECONCILE",
            reconcile_all,
            transformed,
            summary_builder=(
                summarize_reconcile
            ),
        )
    )

    # --------------------------------------------------------
    # Load
    # --------------------------------------------------------

    load_result, load_stage = (
        run_stage(
            "LOAD DUCKDB",
            load_all_to_duckdb,
            validated,
            transformed,
            reconciled,
            summary_builder=(
                summarize_load
            ),
        )
    )

    # --------------------------------------------------------
    # Cross-stage verification
    # --------------------------------------------------------

    verify_pipeline_consistency(
        validated=validated,
        transformed=transformed,
        reconciled=reconciled,
        load_result=load_result,
    )

    # --------------------------------------------------------
    # Persisted database verification
    # --------------------------------------------------------

    database_tables = (
        verify_database_snapshot(
            load_result=load_result
        )
    )

    # --------------------------------------------------------
    # Final summary
    # --------------------------------------------------------

    pipeline_completed_at_utc = (
        utc_now()
    )

    total_duration_seconds = (
        perf_counter()
        - pipeline_started_perf
    )

    stages = [
        config_stage,
        ingest_stage,
        validate_stage,
        transform_stage,
        reconcile_stage,
        load_stage,
    ]

    print()
    print(
        "========================================"
    )

    print(
        "PIPELINE COMPLETE"
    )

    print(
        "========================================"
    )

    print(
        f"Completed: "
        f"{pipeline_completed_at_utc.isoformat()}"
    )

    print(
        f"Total duration: "
        f"{total_duration_seconds:.2f}s"
    )

    print()

    print(
        "Stage durations:"
    )

    for stage in stages:
        print(
            f"{stage.name}: "
            f"{stage.duration_seconds:.2f}s"
        )

    print()

    print(
        "Final analytical snapshot:"
    )

    print(
        f"TradingView validated: "
        f"{len(validated['tradingview_daily']):,}"
    )

    print(
        f"Dukascopy validated: "
        f"{len(validated['dukascopy_1h']):,}"
    )

    print(
        f"TradingView analytical: "
        f"{len(transformed['tradingview_daily']):,}"
    )

    print(
        f"Dukascopy analytical: "
        f"{len(transformed['dukascopy_1h']):,}"
    )

    print(
        f"Daily reconciliation: "
        f"{len(reconciled['tradingview_daily']):,}"
    )

    return {
        "started_at_utc":
            pipeline_started_at_utc,

        "completed_at_utc":
            pipeline_completed_at_utc,

        "duration_seconds":
            total_duration_seconds,

        "raw":
            raw,

        "validated":
            validated,

        "transformed":
            transformed,

        "reconciled":
            reconciled,

        "load_result":
            load_result,

        "database_tables":
            database_tables,

        "stages":
            stages,
    }


# ============================================================
# Manual run
# ============================================================

if __name__ == "__main__":
    run_pipeline()