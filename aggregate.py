from __future__ import annotations

import pandas as pd

from config import (
    DUKASCOPY_4H_BOUNDARY_OFFSET_HOURS,
    SOURCE_DUKASCOPY,
    TIMEFRAME_1H,
    TIMEFRAME_4H,
)

from validate import select_trusted_rows


# ============================================================
# Aggregation contract
# ============================================================

EXPECTED_1H_BARS_PER_4H = 4

AGGREGATED_4H_COLUMNS = [
    # Identity / time
    "timestamp",
    "source",
    "symbol",
    "timeframe",

    # OHLCV
    "open",
    "high",
    "low",
    "close",
    "volume",

    # Aggregation lineage
    "source_timeframe",
    "bar_origin",
    "expected_1h_bar_count",
    "actual_1h_bar_count",
    "first_1h_timestamp",
    "last_1h_timestamp",
    "is_complete_4h_bucket",
]


# ============================================================
# Input checks
# ============================================================

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


# ============================================================
# Fixed-UTC candidate aggregation
# ============================================================

def aggregate_dukascopy_1h_to_4h_fixed_utc(
    df: pd.DataFrame,
    boundary_offset_hours: int = 0,
) -> pd.DataFrame:
    """
    Aggregate trusted Dukascopy 1H bars into candidate 4H bars
    using a fixed UTC boundary.

    This function does NOT declare that the selected boundary
    matches the decision-time TradingView 4H chart.

    The correct 4H session / boundary contract must be calibrated
    separately against external chart evidence.

    Parameters
    ----------
    df:
        Validated Dukascopy 1H dataset. Trusted rows are selected
        internally.

    boundary_offset_hours:
        Fixed UTC offset used to construct candidate 4H buckets.

        Examples:
            0 -> 00/04/08/12/16/20 UTC
            1 -> 01/05/09/13/17/21 UTC
            2 -> 02/06/10/14/18/22 UTC
            3 -> 03/07/11/15/19/23 UTC

        This is a candidate construction parameter, not a frozen
        market-session assumption.
    """

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
        "eligible_for_trusted",
    )

    require_columns(
        df=df,
        required_columns=required_columns,
        dataset_name="dukascopy_1h_for_4h_aggregation",
    )

    if not isinstance(boundary_offset_hours, int):
        raise TypeError(
            "boundary_offset_hours must be an integer."
        )

    if boundary_offset_hours not in range(4):
        raise ValueError(
            "boundary_offset_hours must be one of: 0, 1, 2, 3."
        )

    trusted = select_trusted_rows(df)

    if trusted.empty:
        raise ValueError(
            "No trusted Dukascopy 1H rows available for aggregation."
        )

    if not (
        trusted["source"] == SOURCE_DUKASCOPY
    ).all():
        raise ValueError(
            "4H aggregation received non-Dukascopy rows."
        )

    if not (
        trusted["timeframe"] == TIMEFRAME_1H
    ).all():
        raise ValueError(
            "4H aggregation received non-1H rows."
        )

    if trusted["timestamp"].dt.tz is None:
        raise ValueError(
            "Dukascopy 1H timestamps must be timezone-aware."
        )

    working = (
        trusted[
            [
                "timestamp",
                "open",
                "high",
                "low",
                "close",
                "volume",
                "source",
                "symbol",
            ]
        ]
        .copy()
        .sort_values(
            [
                "source",
                "symbol",
                "timestamp",
            ]
        )
        .reset_index(drop=True)
    )

    # Shift -> floor -> shift back.
    #
    # offset 0:
    #     00/04/08/12/16/20
    #
    # offset 1:
    #     01/05/09/13/17/21
    #
    # This constructs candidate boundaries only.
    offset = pd.Timedelta(
        hours=boundary_offset_hours
    )

    working["_bucket_start"] = (
        (
            working["timestamp"]
            - offset
        )
        .dt.floor("4h")
        + offset
    )

    group_keys = [
        "source",
        "symbol",
        "_bucket_start",
    ]

    rows = []

    for (
        source,
        symbol,
        bucket_start,
    ), group in working.groupby(
        group_keys,
        sort=True,
        dropna=False,
    ):
        group = (
            group
            .sort_values("timestamp")
            .reset_index(drop=True)
        )

        actual_count = len(group)

        expected_timestamps = pd.date_range(
            start=bucket_start,
            periods=EXPECTED_1H_BARS_PER_4H,
            freq="1h",
            tz=bucket_start.tz,
        )

        actual_timestamps = pd.DatetimeIndex(
            group["timestamp"]
        )

        has_exact_expected_slots = (
            actual_count
            == EXPECTED_1H_BARS_PER_4H
            and actual_timestamps.equals(
                expected_timestamps
            )
        )

        rows.append(
            {
                "timestamp": bucket_start,
                "source": source,
                "symbol": symbol,
                "timeframe": TIMEFRAME_4H,

                "open": group.iloc[0]["open"],
                "high": group["high"].max(),
                "low": group["low"].min(),
                "close": group.iloc[-1]["close"],
                "volume": group["volume"].sum(),

                "source_timeframe": TIMEFRAME_1H,
                "bar_origin": "AGGREGATED",

                "expected_1h_bar_count":
                    EXPECTED_1H_BARS_PER_4H,

                "actual_1h_bar_count":
                    actual_count,

                "first_1h_timestamp":
                    group.iloc[0]["timestamp"],

                "last_1h_timestamp":
                    group.iloc[-1]["timestamp"],

                "is_complete_4h_bucket":
                    has_exact_expected_slots,
            }
        )

    result = pd.DataFrame(
        rows,
        columns=AGGREGATED_4H_COLUMNS,
    )

    result = (
        result
        .sort_values(
            [
                "source",
                "symbol",
                "timestamp",
            ]
        )
        .reset_index(drop=True)
    )

    return result


# ============================================================
# Production aggregation
# ============================================================

def aggregate_all(
    validated: dict[str, pd.DataFrame],
) -> dict[str, pd.DataFrame]:
    """
    Build derived higher-timeframe OHLCV datasets from validated
    source data.

    The production Dukascopy H4 boundary is frozen in config.py.
    Incomplete H4 buckets are retained here for lineage and audit.
    Canonical H4 market facts select complete buckets downstream.
    """
    required_datasets = {
        "dukascopy_1h",
    }

    missing = (
        required_datasets
        - set(validated)
    )

    if missing:
        raise KeyError(
            f"Missing validated datasets for aggregation: "
            f"{sorted(missing)}"
        )

    dukascopy_4h = (
        aggregate_dukascopy_1h_to_4h_fixed_utc(
            validated["dukascopy_1h"],
            boundary_offset_hours=(
                DUKASCOPY_4H_BOUNDARY_OFFSET_HOURS
            ),
        )
    )

    return {
        "dukascopy_4h": dukascopy_4h,
    }

