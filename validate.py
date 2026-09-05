"""
Validate ingested market data before analytical transformation.

Detect problems, classify them, and decide which rows are safe
for downstream use.
"""

from __future__ import annotations

import pandas as pd

from config import (
    DQ_STATUS_PASS,
    DQ_STATUS_REVIEW,
    DQ_STATUS_REJECTED,
    OHLC_COLUMNS,
    TIMEFRAME_1H,
    TIMEFRAME_1D,
)


# ============================================================
# Validation rules
# ============================================================

TIMEFRAME_INTERVALS = {
    TIMEFRAME_1H: pd.Timedelta(hours=1),
    TIMEFRAME_1D: pd.Timedelta(days=1),
}


DUPLICATE_NONE = "NONE"
DUPLICATE_EXACT = "EXACT"
DUPLICATE_CONFLICTING = "CONFLICTING"


# ============================================================
# Basic checks
# ============================================================

def require_columns(
    df: pd.DataFrame,
    required_columns: tuple[str, ...],
    dataset_name: str,
) -> None:
    """Fail if validation input is missing required columns."""

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


def validate_supported_timeframes(
    df: pd.DataFrame,
    dataset_name: str,
) -> None:
    """Fail if a timeframe has no interval rule yet."""

    actual = set(
        df["timeframe"]
        .dropna()
        .unique()
    )

    supported = set(
        TIMEFRAME_INTERVALS
    )

    unsupported = actual - supported

    if unsupported:
        raise ValueError(
            f"{dataset_name} contains unsupported timeframes: "
            f"{sorted(unsupported)}"
        )


# ============================================================
# Type standardization
# ============================================================

def parse_tradingview_timestamp(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """Convert TradingView Unix time to UTC timestamp."""

    result = df.copy()

    numeric_time = pd.to_numeric(
        result["time"],
        errors="coerce",
    )

    result["timestamp"] = pd.to_datetime(
        numeric_time,
        unit="s",
        utc=True,
        errors="coerce",
    )

    return result


def parse_dukascopy_timestamp(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """Convert Dukascopy timestamp to UTC datetime."""

    result = df.copy()

    result["timestamp"] = pd.to_datetime(
        result["timestamp"],
        utc=True,
        errors="coerce",
    )

    return result


def standardize_numeric_columns(
    df: pd.DataFrame,
    columns: tuple[str, ...],
) -> pd.DataFrame:
    """Convert expected numeric fields without hiding failures."""

    result = df.copy()

    for column in columns:
        result[column] = pd.to_numeric(
            result[column],
            errors="coerce",
        )

    return result


# ============================================================
# Missing data
# ============================================================

def add_missing_flags(
    df: pd.DataFrame,
    check_volume: bool,
) -> pd.DataFrame:
    """Add missing-value flags used by DQ classification."""

    result = df.copy()

    result["missing_timestamp"] = (
        result["timestamp"].isna()
    )

    result["missing_ohlc"] = (
        result[list(OHLC_COLUMNS)]
        .isna()
        .any(axis=1)
    )

    if check_volume:
        result["missing_volume"] = (
            result["volume"].isna()
        )
    else:
        result["missing_volume"] = False

    return result


# ============================================================
# Price checks
# ============================================================

def add_price_flags(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """Check price validity and OHLC logic."""

    result = df.copy()

    has_complete_ohlc = ~result["missing_ohlc"]

    result["invalid_price"] = (
        (
            result[list(OHLC_COLUMNS)] <= 0
        )
        .any(axis=1)
        & has_complete_ohlc
    )

    max_expected = (
        result[
            ["open", "close", "low"]
        ]
        .max(axis=1)
    )

    min_expected = (
        result[
            ["open", "close", "high"]
        ]
        .min(axis=1)
    )

    result["invalid_ohlc"] = (
        (
            (result["high"] < max_expected)
            |
            (result["low"] > min_expected)
        )
        & has_complete_ohlc
    )

    return result


# ============================================================
# Duplicate checks
# ============================================================

def add_duplicate_flags(
    df: pd.DataFrame,
    payload_columns: tuple[str, ...],
) -> pd.DataFrame:
    """
    Classify duplicate timestamps within the same source.

    EXACT:
    Same key and same market payload.

    CONFLICTING:
    Same key but different market payload.
    """

    result = df.copy()

    key_columns = [
        "source",
        "symbol",
        "timeframe",
        "timestamp",
    ]

    result["duplicate_type"] = DUPLICATE_NONE

    result["is_duplicate_keep"] = False
    result["is_duplicate_drop"] = False

    valid_timestamp = (
        result["timestamp"].notna()
    )

    payload_hash = pd.util.hash_pandas_object(
        result[list(payload_columns)],
        index=False,
    )

    result["_payload_hash"] = payload_hash

    valid = result.loc[
        valid_timestamp
    ].copy()

    if valid.empty:
        result = result.drop(
            columns="_payload_hash"
        )

        return result

    group_size = (
        valid
        .groupby(
            key_columns,
            dropna=False,
        )["timestamp"]
        .transform("size")
    )

    payload_versions = (
        valid
        .groupby(
            key_columns,
            dropna=False,
        )["_payload_hash"]
        .transform("nunique")
    )

    duplicate_key = (
        group_size > 1
    )

    exact_duplicate = (
        duplicate_key
        & (payload_versions == 1)
    )

    conflicting_duplicate = (
        duplicate_key
        & (payload_versions > 1)
    )

    exact_index = valid.index[
        exact_duplicate
    ]

    conflicting_index = valid.index[
        conflicting_duplicate
    ]

    result.loc[
        exact_index,
        "duplicate_type",
    ] = DUPLICATE_EXACT

    result.loc[
        conflicting_index,
        "duplicate_type",
    ] = DUPLICATE_CONFLICTING

    # Keep exactly one representative from an exact duplicate group.
    exact_drop_mask = (
        result.loc[exact_index]
        .duplicated(
            subset=(
                key_columns
                + list(payload_columns)
            ),
            keep="first",
        )
    )

    exact_drop_index = (
        exact_drop_mask[
            exact_drop_mask
        ]
        .index
    )

    exact_keep_index = (
        exact_index.difference(
            exact_drop_index
        )
    )

    result.loc[
        exact_keep_index,
        "is_duplicate_keep",
    ] = True

    result.loc[
        exact_drop_index,
        "is_duplicate_drop",
    ] = True

    result = result.drop(
        columns="_payload_hash"
    )

    return result


# ============================================================
# Temporal checks
# ============================================================

def add_temporal_flags(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """
    Check source ordering and identify time-gap candidates.

    A gap is only an observation here.
    It is not automatically a DQ failure.
    """

    result = df.copy()

    # Check the order the rows arrived in.
    result["_raw_previous_timestamp"] = (
        result
        .groupby(
            [
                "source",
                "source_file",
            ],
            sort=False,
        )["timestamp"]
        .shift(1)
    )

    result["out_of_order_timestamp"] = (
        result["timestamp"].notna()
        &
        result["_raw_previous_timestamp"].notna()
        &
        (
            result["timestamp"]
            < result["_raw_previous_timestamp"]
        )
    )

    result = result.drop(
        columns="_raw_previous_timestamp"
    )

    # Canonical order for interval checks.
    result = (
        result
        .sort_values(
            [
                "source",
                "timeframe",
                "timestamp",
                "source_file",
            ],
            na_position="last",
        )
        .reset_index(drop=True)
    )

    result["previous_timestamp"] = (
        result
        .groupby(
            [
                "source",
                "timeframe",
            ],
            sort=False,
        )["timestamp"]
        .shift(1)
    )

    result["time_diff"] = (
        result["timestamp"]
        - result["previous_timestamp"]
    )

    result["expected_interval"] = (
        result["timeframe"]
        .map(TIMEFRAME_INTERVALS)
    )

    result["gap_candidate"] = (
        result["time_diff"].notna()
        &
        result["expected_interval"].notna()
        &
        (
            result["time_diff"]
            > result["expected_interval"]
        )
    )

    return result


# ============================================================
# DQ classification
# ============================================================

def add_dq_status(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """Assign PASS / REVIEW / REJECTED."""

    result = df.copy()

    result["dq_status"] = (
        DQ_STATUS_PASS
    )

    # Usable, but worth keeping visible.
    review_mask = (
        result["missing_volume"]
        |
        result["out_of_order_timestamp"]
        |
        result["is_duplicate_drop"]
    )

    result.loc[
        review_mask,
        "dq_status",
    ] = DQ_STATUS_REVIEW

    # Unsafe for trusted analytical use.
    reject_mask = (
        result["missing_timestamp"]
        |
        result["missing_ohlc"]
        |
        result["invalid_price"]
        |
        result["invalid_ohlc"]
        |
        (
            result["duplicate_type"]
            == DUPLICATE_CONFLICTING
        )
    )

    result.loc[
        reject_mask,
        "dq_status",
    ] = DQ_STATUS_REJECTED

    result["eligible_for_trusted"] = (
        (
            result["dq_status"]
            != DQ_STATUS_REJECTED
        )
        &
        ~result["is_duplicate_drop"]
    )

    return result


# ============================================================
# DQ reason
# ============================================================

def add_dq_reason(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """Create a compact audit trail for DQ decisions."""

    result = df.copy()

    reason_rules = (
        (
            "missing_timestamp",
            "missing_or_invalid_timestamp",
        ),
        (
            "missing_ohlc",
            "missing_or_invalid_ohlc",
        ),
        (
            "missing_volume",
            "missing_or_invalid_volume",
        ),
        (
            "invalid_price",
            "non_positive_price",
        ),
        (
            "invalid_ohlc",
            "invalid_ohlc",
        ),
        (
            "out_of_order_timestamp",
            "out_of_order_timestamp",
        ),
        (
            "is_duplicate_drop",
            "exact_duplicate_drop",
        ),
    )

    def collect_reasons(
        row: pd.Series,
    ) -> str | pd.NA:

        reasons = []

        for column, label in reason_rules:
            if bool(row[column]):
                reasons.append(label)

        if (
            row["duplicate_type"]
            == DUPLICATE_CONFLICTING
        ):
            reasons.append(
                "conflicting_duplicate"
            )

        if not reasons:
            return pd.NA

        return "|".join(reasons)

    result["dq_reason"] = (
        result.apply(
            collect_reasons,
            axis=1,
        )
    )

    return result


# ============================================================
# Shared validation flow
# ============================================================

def finalize_validation(
    df: pd.DataFrame,
    payload_columns: tuple[str, ...],
    check_volume: bool,
) -> pd.DataFrame:
    """Run shared DQ checks after type standardization."""

    result = add_missing_flags(
        df=df,
        check_volume=check_volume,
    )

    result = add_price_flags(
        result
    )

    result = add_duplicate_flags(
        df=result,
        payload_columns=payload_columns,
    )

    result = add_temporal_flags(
        result
    )

    result = add_dq_status(
        result
    )

    result = add_dq_reason(
        result
    )

    return result


# ============================================================
# TradingView
# ============================================================

def validate_tradingview_daily(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """Validate ingested TradingView Daily data."""

    dataset_name = "tradingview_daily"

    required_columns = (
        "time",
        "open",
        "high",
        "low",
        "close",
        "Up",
        "Down",
        "Daily High",
        "Daily Low",
        "source",
        "symbol",
        "timeframe",
        "source_file",
        "file_hash",
        "ingested_at_utc",
    )

    require_columns(
        df=df,
        required_columns=required_columns,
        dataset_name=dataset_name,
    )

    validate_supported_timeframes(
        df=df,
        dataset_name=dataset_name,
    )

    result = parse_tradingview_timestamp(
        df
    )

    result = standardize_numeric_columns(
        df=result,
        columns=(
            "open",
            "high",
            "low",
            "close",
        ),
    )

    # Semantic columns belong to the raw export.
    # Missing values inside them are allowed.
    payload_columns = (
        "open",
        "high",
        "low",
        "close",
        "Up",
        "Down",
        "Daily High",
        "Daily Low",
    )

    result = finalize_validation(
        df=result,
        payload_columns=payload_columns,
        check_volume=False,
    )

    return result


# ============================================================
# Dukascopy
# ============================================================

def validate_dukascopy_1h(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """Validate ingested Dukascopy 1H data."""

    dataset_name = "dukascopy_1h"

    required_columns = (
        "timestamp",
        "open",
        "high",
        "low",
        "close",
        "volume",
        "source",
        "symbol",
        "timeframe",
        "source_file",
        "file_hash",
        "ingested_at_utc",
    )

    require_columns(
        df=df,
        required_columns=required_columns,
        dataset_name=dataset_name,
    )

    validate_supported_timeframes(
        df=df,
        dataset_name=dataset_name,
    )

    result = parse_dukascopy_timestamp(
        df
    )

    result = standardize_numeric_columns(
        df=result,
        columns=(
            "open",
            "high",
            "low",
            "close",
            "volume",
        ),
    )

    payload_columns = (
        "open",
        "high",
        "low",
        "close",
        "volume",
    )

    result = finalize_validation(
        df=result,
        payload_columns=payload_columns,
        check_volume=True,
    )

    return result


# ============================================================
# Trusted selection
# ============================================================

def select_trusted_rows(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """
    Keep rows safe for downstream transformation.

    Exact duplicate copies are removed here.
    The validation output itself still keeps the evidence.
    """

    require_columns(
        df=df,
        required_columns=(
            "eligible_for_trusted",
        ),
        dataset_name="validated_dataset",
    )

    trusted = (
        df[
            df["eligible_for_trusted"]
        ]
        .copy()
        .sort_values(
            [
                "source",
                "timeframe",
                "timestamp",
            ]
        )
        .reset_index(drop=True)
    )

    return trusted


# ============================================================
# Full validation
# ============================================================

def validate_all(
    datasets: dict[str, pd.DataFrame],
) -> dict[str, pd.DataFrame]:
    """Validate all currently supported ingested datasets."""

    required_datasets = {
        "tradingview_daily",
        "dukascopy_1h",
    }

    missing = (
        required_datasets
        - set(datasets)
    )

    if missing:
        raise KeyError(
            f"Missing datasets for validation: "
            f"{sorted(missing)}"
        )

    tradingview_daily = (
        validate_tradingview_daily(
            datasets["tradingview_daily"]
        )
    )

    dukascopy_1h = (
        validate_dukascopy_1h(
            datasets["dukascopy_1h"]
        )
    )

    return {
        "tradingview_daily":
            tradingview_daily,

        "dukascopy_1h":
            dukascopy_1h,
    }


# ============================================================
# Summary
# ============================================================

def print_validation_summary(
    name: str,
    df: pd.DataFrame,
) -> None:
    """Print the main DQ results for one dataset."""

    print()
    print(
        f"=== {name} ==="
    )

    print(
        f"Rows: {len(df):,}"
    )

    print()
    print("DQ Status:")

    print(
        df["dq_status"]
        .value_counts(
            dropna=False
        )
        .to_string()
    )

    print()
    print("Duplicate Type:")

    print(
        df["duplicate_type"]
        .value_counts(
            dropna=False
        )
        .to_string()
    )

    print()

    print(
        "Exact duplicate rows dropped:",
        int(
            df["is_duplicate_drop"].sum()
        ),
    )

    print(
        "Conflicting duplicate rows:",
        int(
            (
                df["duplicate_type"]
                == DUPLICATE_CONFLICTING
            ).sum()
        ),
    )

    print(
        "Missing timestamp:",
        int(
            df["missing_timestamp"].sum()
        ),
    )

    print(
        "Missing OHLC:",
        int(
            df["missing_ohlc"].sum()
        ),
    )

    print(
        "Missing volume:",
        int(
            df["missing_volume"].sum()
        ),
    )

    print(
        "Invalid price:",
        int(
            df["invalid_price"].sum()
        ),
    )

    print(
        "Invalid OHLC:",
        int(
            df["invalid_ohlc"].sum()
        ),
    )

    print(
        "Out-of-order timestamps:",
        int(
            df[
                "out_of_order_timestamp"
            ].sum()
        ),
    )

    print(
        "Gap candidates:",
        int(
            df["gap_candidate"].sum()
        ),
    )

    print(
        "Eligible for trusted:",
        int(
            df[
                "eligible_for_trusted"
            ].sum()
        ),
    )


# ============================================================
# Manual run
# ============================================================

if __name__ == "__main__":

    from ingest import ingest_all

    datasets = ingest_all()

    validated = validate_all(
        datasets
    )

    for name, df in validated.items():

        print_validation_summary(
            name=name,
            df=df,
        )