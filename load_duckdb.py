from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import duckdb
import pandas as pd

from config import (
    DATABASE_DIR,
    DUCKDB_PATH,
)


# ============================================================
# Table names
# ============================================================

TABLE_VALIDATED_TRADINGVIEW_DAILY = (
    "validated_tradingview_daily"
)

TABLE_VALIDATED_DUKASCOPY_1H = (
    "validated_dukascopy_1h"
)

TABLE_MARKET_BARS_TRADINGVIEW_DAILY = (
    "market_bars_tradingview_daily"
)

TABLE_MARKET_BARS_DUKASCOPY_1H = (
    "market_bars_dukascopy_1h"
)

TABLE_PROVIDER_RECONCILIATION_DAILY = (
    "provider_reconciliation_daily"
)

TABLE_LOAD_AUDIT = (
    "load_audit"
)


# ============================================================
# Dataset contract
# ============================================================

LOAD_SPECS = {
    TABLE_VALIDATED_TRADINGVIEW_DAILY: {
        "group": "validated",
        "dataset": "tradingview_daily",
        "grain": (
            "timestamp",
            "source",
            "symbol",
            "timeframe",
        ),
    },

    TABLE_VALIDATED_DUKASCOPY_1H: {
        "group": "validated",
        "dataset": "dukascopy_1h",
        "grain": None,
    },

    TABLE_MARKET_BARS_TRADINGVIEW_DAILY: {
        "group": "transformed",
        "dataset": "tradingview_daily",
        "grain": (
            "date",
            "source",
            "symbol",
            "timeframe",
        ),
    },

    TABLE_MARKET_BARS_DUKASCOPY_1H: {
        "group": "transformed",
        "dataset": "dukascopy_1h",
        "grain": (
            "bar_start_utc",
            "source",
            "symbol",
            "timeframe",
        ),
    },

    TABLE_PROVIDER_RECONCILIATION_DAILY: {
        "group": "reconciled",
        "dataset": "tradingview_daily",
        "grain": (
            "date",
            "symbol",
            "timeframe",
        ),
    },
}


# ============================================================
# Basic checks
# ============================================================

def require_dataframe(
    value: object,
    name: str,
) -> None:
    if not isinstance(
        value,
        pd.DataFrame,
    ):
        raise TypeError(
            f"{name} must be a pandas DataFrame"
        )


def require_columns(
    df: pd.DataFrame,
    required_columns: tuple[str, ...],
    dataset_name: str,
) -> None:
    missing = [
        column
        for column in required_columns
        if column not in df.columns
    ]

    if missing:
        raise ValueError(
            f"{dataset_name} is missing required columns: "
            f"{missing}"
        )


def require_unique_grain(
    df: pd.DataFrame,
    grain: tuple[str, ...],
    dataset_name: str,
) -> None:
    """
    Fail before loading if a business grain is duplicated.
    """

    require_columns(
        df=df,
        required_columns=grain,
        dataset_name=dataset_name,
    )

    duplicate_mask = (
        df.duplicated(
            subset=list(grain),
            keep=False,
        )
    )

    if not duplicate_mask.any():
        return

    sample = (
        df.loc[
            duplicate_mask,
            list(grain),
        ]
        .head(10)
    )

    raise ValueError(
        f"{dataset_name} contains duplicate grain rows:\n"
        f"{sample.to_string(index=False)}"
    )


# ============================================================
# Validated Dukascopy contract
# ============================================================

def validate_dukascopy_validated_grain(
    df: pd.DataFrame,
) -> None:
    """
    The validated Dukascopy table intentionally keeps
    exact duplicate evidence.

    Therefore timestamp/source grain is NOT expected
    to be unique at this layer.

    Instead, verify the fields required to distinguish
    and audit those rows are present.
    """

    require_columns(
        df=df,
        required_columns=(
            "timestamp",
            "source",
            "symbol",
            "timeframe",
            "source_file",
            "file_hash",
            "duplicate_type",
            "dq_status",
            "eligible_for_trusted",
        ),
        dataset_name=(
            TABLE_VALIDATED_DUKASCOPY_1H
        ),
    )


# ============================================================
# Full input validation
# ============================================================

def validate_load_inputs(
    validated: dict[str, pd.DataFrame],
    transformed: dict[str, pd.DataFrame],
    reconciled: dict[str, pd.DataFrame],
) -> None:

    dataset_groups = {
        "validated": validated,
        "transformed": transformed,
        "reconciled": reconciled,
    }

    for table_name, spec in LOAD_SPECS.items():

        group_name = spec["group"]
        dataset_name = spec["dataset"]

        group = dataset_groups[
            group_name
        ]

        if dataset_name not in group:
            raise KeyError(
                f"Missing {group_name} dataset: "
                f"{dataset_name}"
            )

        df = group[
            dataset_name
        ]

        require_dataframe(
            value=df,
            name=(
                f"{group_name}."
                f"{dataset_name}"
            ),
        )

        if df.empty:
            raise ValueError(
                f"{group_name}.{dataset_name} "
                "is empty"
            )

        grain = spec["grain"]

        if grain is not None:

            require_unique_grain(
                df=df,
                grain=grain,
                dataset_name=table_name,
            )

    validate_dukascopy_validated_grain(
        validated[
            "dukascopy_1h"
        ]
    )


# ============================================================
# Database
# ============================================================

def ensure_database_directory() -> None:
    Path(
        DATABASE_DIR
    ).mkdir(
        parents=True,
        exist_ok=True,
    )


def connect_duckdb() -> duckdb.DuckDBPyConnection:
    ensure_database_directory()

    return duckdb.connect(
        str(DUCKDB_PATH)
    )


# ============================================================
# Audit table
# ============================================================

def create_load_audit_table(
    con: duckdb.DuckDBPyConnection,
) -> None:

    con.execute(
        f"""
        CREATE TABLE IF NOT EXISTS
        {TABLE_LOAD_AUDIT}
        (
            run_id VARCHAR,
            table_name VARCHAR,
            row_count BIGINT,
            column_count BIGINT,
            loaded_at_utc TIMESTAMPTZ
        )
        """
    )


# ============================================================
# Table loading
# ============================================================

def replace_table_from_dataframe(
    con: duckdb.DuckDBPyConnection,
    table_name: str,
    df: pd.DataFrame,
) -> None:
    """
    Replace one analytical snapshot.

    CREATE OR REPLACE makes reruns idempotent:
    the same pipeline run does not append duplicates.
    """

    relation_name = (
        f"_df_{table_name}"
    )

    con.register(
        relation_name,
        df,
    )

    try:

        con.execute(
            f"""
            CREATE OR REPLACE TABLE
            {table_name}
            AS
            SELECT *
            FROM {relation_name}
            """
        )

    finally:

        con.unregister(
            relation_name
        )


# ============================================================
# Post-load checks
# ============================================================

def get_table_row_count(
    con: duckdb.DuckDBPyConnection,
    table_name: str,
) -> int:

    return int(
        con.execute(
            f"""
            SELECT COUNT(*)
            FROM {table_name}
            """
        ).fetchone()[0]
    )


def get_table_column_count(
    con: duckdb.DuckDBPyConnection,
    table_name: str,
) -> int:

    return int(
        con.execute(
            f"""
            SELECT COUNT(*)
            FROM information_schema.columns
            WHERE table_name = ?
            """,
            [table_name],
        ).fetchone()[0]
    )


def verify_loaded_table(
    con: duckdb.DuckDBPyConnection,
    table_name: str,
    df: pd.DataFrame,
) -> None:
    """
    Verify the persisted snapshot matches the DataFrame shape.
    """

    database_rows = (
        get_table_row_count(
            con=con,
            table_name=table_name,
        )
    )

    expected_rows = len(
        df
    )

    if database_rows != expected_rows:
        raise RuntimeError(
            f"{table_name} row-count mismatch: "
            f"expected {expected_rows:,}, "
            f"found {database_rows:,}"
        )

    database_columns = (
        get_table_column_count(
            con=con,
            table_name=table_name,
        )
    )

    expected_columns = len(
        df.columns
    )

    if database_columns != expected_columns:
        raise RuntimeError(
            f"{table_name} column-count mismatch: "
            f"expected {expected_columns}, "
            f"found {database_columns}"
        )


# ============================================================
# Audit
# ============================================================

def write_load_audit(
    con: duckdb.DuckDBPyConnection,
    run_id: str,
    table_name: str,
    df: pd.DataFrame,
    loaded_at_utc: datetime,
) -> None:

    con.execute(
        f"""
        INSERT INTO {TABLE_LOAD_AUDIT}
        (
            run_id,
            table_name,
            row_count,
            column_count,
            loaded_at_utc
        )
        VALUES (?, ?, ?, ?, ?)
        """,
        [
            run_id,
            table_name,
            len(df),
            len(df.columns),
            loaded_at_utc,
        ],
    )


# ============================================================
# Dataset mapping
# ============================================================

def build_load_frames(
    validated: dict[str, pd.DataFrame],
    transformed: dict[str, pd.DataFrame],
    reconciled: dict[str, pd.DataFrame],
) -> dict[str, pd.DataFrame]:

    return {
        TABLE_VALIDATED_TRADINGVIEW_DAILY:
            validated[
                "tradingview_daily"
            ],

        TABLE_VALIDATED_DUKASCOPY_1H:
            validated[
                "dukascopy_1h"
            ],

        TABLE_MARKET_BARS_TRADINGVIEW_DAILY:
            transformed[
                "tradingview_daily"
            ],

        TABLE_MARKET_BARS_DUKASCOPY_1H:
            transformed[
                "dukascopy_1h"
            ],

        TABLE_PROVIDER_RECONCILIATION_DAILY:
            reconciled[
                "tradingview_daily"
            ],
    }


# ============================================================
# Full load
# ============================================================

def load_all_to_duckdb(
    validated: dict[str, pd.DataFrame],
    transformed: dict[str, pd.DataFrame],
    reconciled: dict[str, pd.DataFrame],
) -> dict[str, int]:
    """
    Persist the current analytical snapshot.

    The load is transactional:
    either all target tables are replaced successfully,
    or none of the replacements are committed.
    """

    validate_load_inputs(
        validated=validated,
        transformed=transformed,
        reconciled=reconciled,
    )

    frames = build_load_frames(
        validated=validated,
        transformed=transformed,
        reconciled=reconciled,
    )

    run_id = str(
        uuid4()
    )

    loaded_at_utc = datetime.now(
        timezone.utc
    )

    con = connect_duckdb()

    try:

        con.execute(
            "BEGIN TRANSACTION"
        )

        create_load_audit_table(
            con
        )

        for table_name, df in frames.items():

            replace_table_from_dataframe(
                con=con,
                table_name=table_name,
                df=df,
            )

            verify_loaded_table(
                con=con,
                table_name=table_name,
                df=df,
            )

            write_load_audit(
                con=con,
                run_id=run_id,
                table_name=table_name,
                df=df,
                loaded_at_utc=loaded_at_utc,
            )

        con.execute(
            "COMMIT"
        )

    except Exception:

        try:
            con.execute(
                "ROLLBACK"
            )
        except Exception:
            pass

        raise

    finally:

        con.close()

    return {
        table_name: len(df)
        for table_name, df
        in frames.items()
    }


# ============================================================
# Database inspection
# ============================================================

def inspect_database() -> pd.DataFrame:
    """
    Return the persisted analytical tables and row counts.
    """

    con = connect_duckdb()

    try:

        existing_tables = (
            con.execute(
                """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'main'
                ORDER BY table_name
                """
            )
            .fetchdf()
        )

        rows = []

        for table_name in (
            existing_tables[
                "table_name"
            ]
            .tolist()
        ):

            row_count = (
                get_table_row_count(
                    con=con,
                    table_name=table_name,
                )
            )

            column_count = (
                get_table_column_count(
                    con=con,
                    table_name=table_name,
                )
            )

            rows.append(
                {
                    "table_name":
                        table_name,

                    "rows":
                        row_count,

                    "columns":
                        column_count,
                }
            )

        return pd.DataFrame(
            rows
        )

    finally:

        con.close()


# ============================================================
# Load audit inspection
# ============================================================

def read_latest_load_audit() -> pd.DataFrame:
    con = connect_duckdb()

    try:

        table_exists = (
            con.execute(
                """
                SELECT COUNT(*)
                FROM information_schema.tables
                WHERE table_schema = 'main'
                  AND table_name = ?
                """,
                [
                    TABLE_LOAD_AUDIT
                ],
            )
            .fetchone()[0]
            > 0
        )

        if not table_exists:
            return pd.DataFrame()

        return (
            con.execute(
                f"""
                SELECT
                    run_id,
                    table_name,
                    row_count,
                    column_count,
                    loaded_at_utc
                FROM {TABLE_LOAD_AUDIT}
                WHERE run_id = (
                    SELECT run_id
                    FROM {TABLE_LOAD_AUDIT}
                    ORDER BY loaded_at_utc DESC
                    LIMIT 1
                )
                ORDER BY table_name
                """
            )
            .fetchdf()
        )

    finally:

        con.close()


# ============================================================
# Summary
# ============================================================

def print_load_summary(
    load_result: dict[str, int],
) -> None:

    print()
    print("=== DUCKDB LOAD ===")

    print(
        f"Database: {DUCKDB_PATH}"
    )

    print()

    for table_name, rows in (
        load_result.items()
    ):

        print(
            f"{table_name}: "
            f"{rows:,} rows"
        )


# ============================================================
# Manual run
# ============================================================

if __name__ == "__main__":

    from ingest import ingest_all
    from validate import validate_all
    from transform import transform_all
    from reconcile import reconcile_all

    raw = ingest_all()

    validated = validate_all(
        raw
    )

    transformed = transform_all(
        validated
    )

    reconciled = reconcile_all(
        transformed
    )

    load_result = (
        load_all_to_duckdb(
            validated=validated,
            transformed=transformed,
            reconciled=reconciled,
        )
    )

    print_load_summary(
        load_result
    )

    print()
    print("=== DATABASE TABLES ===")

    database_tables = (
        inspect_database()
    )

    print(
        database_tables
        .to_string(
            index=False
        )
    )