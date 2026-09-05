from __future__ import annotations

import numpy as np
import pandas as pd

from config import (
    PIP_SIZE,
    TIMEFRAME_1D,
    TRADINGVIEW_FILE_SOURCE_MAP,
    MIN_SOURCES_FOR_CROSS_SOURCE_AGREEMENT,
    RECONCILIATION_DIVERGENCE_THRESHOLD_PCT,
)


# ============================================================
# Reconciliation values
# ============================================================

COVERAGE_COMPLETE = "COMPLETE"
COVERAGE_PARTIAL = "PARTIAL"
COVERAGE_INSUFFICIENT = "INSUFFICIENT"

AGREEMENT_UNANIMOUS = "UNANIMOUS"
AGREEMENT_MAJORITY = "MAJORITY"
AGREEMENT_MIXED = "MIXED"
AGREEMENT_INSUFFICIENT = "INSUFFICIENT"

MOVE_UP = "UP"
MOVE_DOWN = "DOWN"
MOVE_FLAT = "FLAT"

BOOLEAN_TRUE = "TRUE"
BOOLEAN_FALSE = "FALSE"

VALUE_NONE = "NONE"
VALUE_MISSING = "MISSING"

EXPECTED_TRADINGVIEW_SOURCES = tuple(
    sorted(
        set(
            TRADINGVIEW_FILE_SOURCE_MAP.values()
        )
    )
)

EXPECTED_TRADINGVIEW_SOURCE_COUNT = (
    len(EXPECTED_TRADINGVIEW_SOURCES)
)


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


def validate_tradingview_daily_input(
    df: pd.DataFrame,
) -> None:
    """
    Validate the transformed Daily grain before reconciliation.
    """

    required_columns = (
        "date",
        "source",
        "symbol",
        "timeframe",
        "open",
        "high",
        "low",
        "close",
        "range_pips",
        "close_change",
        "candle_direction",
        "break_previous_high",
        "break_previous_low",
        "has_imbalance",
        "imbalance_direction",
    )

    require_columns(
        df=df,
        required_columns=required_columns,
        dataset_name="tradingview_daily",
    )

    if not (
        df["timeframe"]
        == TIMEFRAME_1D
    ).all():
        raise ValueError(
            "tradingview_daily contains non-1D rows"
        )

    duplicate_provider_date = (
        df.duplicated(
            subset=[
                "date",
                "source",
                "symbol",
                "timeframe",
            ],
            keep=False,
        )
    )

    if duplicate_provider_date.any():

        sample = (
            df.loc[
                duplicate_provider_date,
                [
                    "date",
                    "source",
                    "symbol",
                    "timeframe",
                ],
            ]
            .head(10)
        )

        raise ValueError(
            "Multiple rows found for the same "
            "provider/date grain:\n"
            f"{sample.to_string(index=False)}"
        )


# ============================================================
# Deterministic behavior values
# ============================================================

def add_close_change_direction(
    df: pd.DataFrame,
) -> pd.DataFrame:
    result = df.copy()

    result["close_change_direction"] = np.select(
        [
            result["close_change"] > 0,
            result["close_change"] < 0,
            result["close_change"] == 0,
        ],
        [
            MOVE_UP,
            MOVE_DOWN,
            MOVE_FLAT,
        ],
        default=None,
    )

    return result


def normalize_boolean_value(
    value: object,
) -> str:
    if pd.isna(value):
        return VALUE_MISSING

    if bool(value):
        return BOOLEAN_TRUE

    return BOOLEAN_FALSE


def normalize_text_value(
    value: object,
) -> str:
    if pd.isna(value):
        return VALUE_MISSING

    return str(value)


def normalize_imbalance_value(
    has_imbalance: object,
    direction: object,
) -> str:
    if pd.isna(has_imbalance):
        return VALUE_MISSING

    if not bool(has_imbalance):
        return VALUE_NONE

    if pd.isna(direction):
        return VALUE_MISSING

    return str(direction)


def build_behavior_signature(
    df: pd.DataFrame,
) -> pd.Series:
    """
    One provider's objective Daily behavior signature.

    This is not a trading signal.
    """

    signatures = []

    for row in df.itertuples(
        index=False
    ):

        candle_direction = (
            normalize_text_value(
                row.candle_direction
            )
        )

        close_change_direction = (
            normalize_text_value(
                row.close_change_direction
            )
        )

        break_high = (
            normalize_boolean_value(
                row.break_previous_high
            )
        )

        break_low = (
            normalize_boolean_value(
                row.break_previous_low
            )
        )

        imbalance = (
            normalize_imbalance_value(
                row.has_imbalance,
                row.imbalance_direction,
            )
        )

        signature = "|".join(
            [
                f"CANDLE={candle_direction}",
                f"CLOSE_CHANGE={close_change_direction}",
                f"BREAK_HIGH={break_high}",
                f"BREAK_LOW={break_low}",
                f"IMBALANCE={imbalance}",
            ]
        )

        signatures.append(
            signature
        )

    return pd.Series(
        signatures,
        index=df.index,
        dtype="string",
    )


# ============================================================
# Consensus
# ============================================================

def summarize_consensus(
    series: pd.Series,
) -> dict[str, object]:
    """
    Return the dominant value without breaking ties arbitrarily.
    """

    valid = (
        series
        .dropna()
    )

    valid_count = len(valid)

    if valid_count == 0:
        return {
            "value": pd.NA,
            "agreeing_count": 0,
            "valid_count": 0,
            "agreement_pct": np.nan,
            "is_tie": False,
        }

    counts = (
        valid
        .astype("string")
        .value_counts()
    )

    max_count = int(
        counts.max()
    )

    winners = (
        counts[
            counts == max_count
        ]
        .index
        .tolist()
    )

    is_tie = (
        len(winners) > 1
    )

    if is_tie:
        consensus_value = pd.NA
    else:
        consensus_value = winners[0]

    return {
        "value": consensus_value,
        "agreeing_count": max_count,
        "valid_count": valid_count,
        "agreement_pct": (
            max_count
            / valid_count
            * 100
        ),
        "is_tie": is_tie,
    }


def classify_signature_agreement(
    source_count: int,
    dominant_count: int,
) -> str:
    """
    Classify exact behavior-signature agreement.
    """

    if (
        source_count
        < MIN_SOURCES_FOR_CROSS_SOURCE_AGREEMENT
    ):
        return AGREEMENT_INSUFFICIENT

    if dominant_count == source_count:
        return AGREEMENT_UNANIMOUS

    if dominant_count > (
        source_count / 2
    ):
        return AGREEMENT_MAJORITY

    return AGREEMENT_MIXED


# ============================================================
# Provider coverage
# ============================================================

def summarize_coverage(
    group: pd.DataFrame,
) -> dict[str, object]:
    sources = tuple(
        sorted(
            group["source"]
            .dropna()
            .unique()
            .tolist()
        )
    )

    source_count = len(
        sources
    )

    missing_sources = tuple(
        sorted(
            set(
                EXPECTED_TRADINGVIEW_SOURCES
            )
            - set(sources)
        )
    )

    coverage_pct = (
        source_count
        / EXPECTED_TRADINGVIEW_SOURCE_COUNT
        * 100
    )

    if (
        source_count
        == EXPECTED_TRADINGVIEW_SOURCE_COUNT
    ):
        coverage_status = (
            COVERAGE_COMPLETE
        )

    elif (
        source_count
        >= MIN_SOURCES_FOR_CROSS_SOURCE_AGREEMENT
    ):
        coverage_status = (
            COVERAGE_PARTIAL
        )

    else:
        coverage_status = (
            COVERAGE_INSUFFICIENT
        )

    return {
        "source_count": source_count,
        "sources_present": "|".join(
            sources
        ),
        "missing_source_count": len(
            missing_sources
        ),
        "missing_sources": (
            "|".join(
                missing_sources
            )
            if missing_sources
            else pd.NA
        ),
        "coverage_pct": coverage_pct,
        "coverage_status": coverage_status,
    }


# ============================================================
# Price statistics
# ============================================================

def summarize_price_column(
    group: pd.DataFrame,
    column: str,
    pip_size: float,
) -> dict[str, float]:
    values = (
        group[column]
        .dropna()
        .astype(float)
    )

    if values.empty:
        return {
            f"{column}_median": np.nan,
            f"{column}_min": np.nan,
            f"{column}_max": np.nan,
            f"{column}_spread": np.nan,
            f"{column}_spread_pips": np.nan,
        }

    minimum = float(
        values.min()
    )

    maximum = float(
        values.max()
    )

    spread = (
        maximum
        - minimum
    )

    return {
        f"{column}_median":
            float(values.median()),

        f"{column}_min":
            minimum,

        f"{column}_max":
            maximum,

        f"{column}_spread":
            spread,

        f"{column}_spread_pips":
            spread / pip_size,
    }


def summarize_range_dispersion(
    group: pd.DataFrame,
) -> dict[str, object]:
    """
    Compare provider Daily range magnitude.

    This is a diagnostic only.
    It does not decide which provider is correct.
    """

    values = (
        group["range_pips"]
        .dropna()
        .astype(float)
    )

    if values.empty:
        return {
            "range_pips_median": np.nan,
            "range_pips_min": np.nan,
            "range_pips_max": np.nan,
            "range_pips_spread": np.nan,
            "range_divergence_pct": np.nan,
            "range_divergence_flag": False,
        }

    median = float(
        values.median()
    )

    minimum = float(
        values.min()
    )

    maximum = float(
        values.max()
    )

    spread = (
        maximum
        - minimum
    )

    if median == 0:
        divergence_pct = np.nan
    else:
        divergence_pct = (
            spread
            / abs(median)
            * 100
        )

    divergence_flag = bool(
        pd.notna(
            divergence_pct
        )
        and (
            divergence_pct
            >
            RECONCILIATION_DIVERGENCE_THRESHOLD_PCT
        )
    )

    return {
        "range_pips_median":
            median,

        "range_pips_min":
            minimum,

        "range_pips_max":
            maximum,

        "range_pips_spread":
            spread,

        "range_divergence_pct":
            divergence_pct,

        "range_divergence_flag":
            divergence_flag,
    }


# ============================================================
# Behavior component consensus
# ============================================================

def add_consensus_fields(
    output: dict[str, object],
    group: pd.DataFrame,
    column: str,
    prefix: str,
) -> None:
    summary = summarize_consensus(
        group[column]
    )

    output[
        f"{prefix}_consensus"
    ] = summary["value"]

    output[
        f"{prefix}_agreeing_sources"
    ] = summary[
        "agreeing_count"
    ]

    output[
        f"{prefix}_valid_sources"
    ] = summary[
        "valid_count"
    ]

    output[
        f"{prefix}_agreement_pct"
    ] = summary[
        "agreement_pct"
    ]

    output[
        f"{prefix}_tie"
    ] = summary[
        "is_tie"
    ]


# ============================================================
# One analytical date
# ============================================================

def reconcile_one_date(
    group: pd.DataFrame,
    pip_size: float = PIP_SIZE,
) -> dict[str, object]:
    group = (
        group
        .copy()
        .sort_values(
            "source"
        )
        .reset_index(
            drop=True
        )
    )

    first = (
        group.iloc[0]
    )

    output: dict[str, object] = {
        "date":
            first["date"],

        "symbol":
            first["symbol"],

        "timeframe":
            first["timeframe"],
    }

    # Coverage
    output.update(
        summarize_coverage(
            group
        )
    )

    # Component consensus
    add_consensus_fields(
        output=output,
        group=group,
        column="candle_direction",
        prefix="candle_direction",
    )

    add_consensus_fields(
        output=output,
        group=group,
        column="close_change_direction",
        prefix="close_change_direction",
    )

    add_consensus_fields(
        output=output,
        group=group,
        column="break_previous_high",
        prefix="break_previous_high",
    )

    add_consensus_fields(
        output=output,
        group=group,
        column="break_previous_low",
        prefix="break_previous_low",
    )

    # Imbalance is normalized so "no imbalance"
    # is different from missing information.
    imbalance_state = pd.Series(
        [
            normalize_imbalance_value(
                row.has_imbalance,
                row.imbalance_direction,
            )
            for row in group.itertuples(
                index=False
            )
        ],
        index=group.index,
        dtype="string",
    )

    group[
        "_imbalance_state"
    ] = imbalance_state

    add_consensus_fields(
        output=output,
        group=group,
        column="_imbalance_state",
        prefix="imbalance",
    )

    # Exact behavior signature
    signature_counts = (
        group[
            "behavior_signature"
        ]
        .value_counts()
    )

    dominant_count = int(
        signature_counts.max()
    )

    dominant_signatures = (
        signature_counts[
            signature_counts
            == dominant_count
        ]
        .index
        .tolist()
    )

    signature_tie = (
        len(
            dominant_signatures
        )
        > 1
    )

    if signature_tie:
        dominant_signature = pd.NA
    else:
        dominant_signature = (
            dominant_signatures[0]
        )

    source_count = int(
        output["source_count"]
    )

    output[
        "dominant_behavior_signature"
    ] = dominant_signature

    output[
        "behavior_agreeing_sources"
    ] = dominant_count

    output[
        "behavior_agreement_pct"
    ] = (
        dominant_count
        / source_count
        * 100
    )

    output[
        "behavior_signature_tie"
    ] = signature_tie

    output[
        "behavior_agreement"
    ] = classify_signature_agreement(
        source_count=source_count,
        dominant_count=dominant_count,
    )

    # Price-level diagnostics
    for column in (
        "open",
        "high",
        "low",
        "close",
    ):
        output.update(
            summarize_price_column(
                group=group,
                column=column,
                pip_size=pip_size,
            )
        )

    # Range-magnitude diagnostic
    output.update(
        summarize_range_dispersion(
            group
        )
    )

    return output


# ============================================================
# TradingView Daily reconciliation
# ============================================================

def reconcile_tradingview_daily(
    df: pd.DataFrame,
    pip_size: float = PIP_SIZE,
) -> pd.DataFrame:
    """
    Reconcile native TradingView Daily providers.

    One output row:
        one date × symbol × timeframe

    No synthetic market candle is created.
    """

    validate_tradingview_daily_input(
        df
    )

    result = add_close_change_direction(
        df
    )

    result[
        "behavior_signature"
    ] = build_behavior_signature(
        result
    )

    reconciled_rows = []

    group_keys = [
        "date",
        "symbol",
        "timeframe",
    ]

    for _, group in result.groupby(
        group_keys,
        sort=True,
        dropna=False,
    ):

        reconciled_rows.append(
            reconcile_one_date(
                group=group,
                pip_size=pip_size,
            )
        )

    reconciled = pd.DataFrame(
        reconciled_rows
    )

    reconciled = (
        reconciled
        .sort_values(
            [
                "symbol",
                "timeframe",
                "date",
            ]
        )
        .reset_index(
            drop=True
        )
    )

    return reconciled


# ============================================================
# Final columns
# ============================================================

RECONCILIATION_COLUMNS = [

    # Grain
    "date",
    "symbol",
    "timeframe",

    # Coverage
    "source_count",
    "sources_present",
    "missing_source_count",
    "missing_sources",
    "coverage_pct",
    "coverage_status",

    # Candle direction
    "candle_direction_consensus",
    "candle_direction_agreeing_sources",
    "candle_direction_valid_sources",
    "candle_direction_agreement_pct",
    "candle_direction_tie",

    # Close-to-close direction
    "close_change_direction_consensus",
    "close_change_direction_agreeing_sources",
    "close_change_direction_valid_sources",
    "close_change_direction_agreement_pct",
    "close_change_direction_tie",

    # Previous High
    "break_previous_high_consensus",
    "break_previous_high_agreeing_sources",
    "break_previous_high_valid_sources",
    "break_previous_high_agreement_pct",
    "break_previous_high_tie",

    # Previous Low
    "break_previous_low_consensus",
    "break_previous_low_agreeing_sources",
    "break_previous_low_valid_sources",
    "break_previous_low_agreement_pct",
    "break_previous_low_tie",

    # Imbalance
    "imbalance_consensus",
    "imbalance_agreeing_sources",
    "imbalance_valid_sources",
    "imbalance_agreement_pct",
    "imbalance_tie",

    # Exact behavior signature
    "dominant_behavior_signature",
    "behavior_agreeing_sources",
    "behavior_agreement_pct",
    "behavior_signature_tie",
    "behavior_agreement",

    # Open
    "open_median",
    "open_min",
    "open_max",
    "open_spread",
    "open_spread_pips",

    # High
    "high_median",
    "high_min",
    "high_max",
    "high_spread",
    "high_spread_pips",

    # Low
    "low_median",
    "low_min",
    "low_max",
    "low_spread",
    "low_spread_pips",

    # Close
    "close_median",
    "close_min",
    "close_max",
    "close_spread",
    "close_spread_pips",

    # Range dispersion
    "range_pips_median",
    "range_pips_min",
    "range_pips_max",
    "range_pips_spread",
    "range_divergence_pct",
    "range_divergence_flag",
]


# ============================================================
# Full reconciliation
# ============================================================

def reconcile_all(
    transformed: dict[str, pd.DataFrame],
) -> dict[str, pd.DataFrame]:
    required_datasets = {
        "tradingview_daily",
    }

    missing = (
        required_datasets
        - set(transformed)
    )

    if missing:
        raise KeyError(
            f"Missing transformed datasets: "
            f"{sorted(missing)}"
        )

    tradingview_daily = (
        reconcile_tradingview_daily(
            transformed[
                "tradingview_daily"
            ]
        )
    )

    return {
        "tradingview_daily":
            tradingview_daily[
                RECONCILIATION_COLUMNS
            ]
    }


# ============================================================
# Summary
# ============================================================

def print_reconciliation_summary(
    name: str,
    df: pd.DataFrame,
) -> None:
    print()
    print(
        f"=== {name} ==="
    )

    print(
        f"Rows: {len(df):,}"
    )

    print(
        f"Columns: {len(df.columns)}"
    )

    print()
    print("Coverage Status:")

    print(
        df["coverage_status"]
        .value_counts(
            dropna=False
        )
        .to_string()
    )

    print()
    print("Behavior Agreement:")

    print(
        df["behavior_agreement"]
        .value_counts(
            dropna=False
        )
        .to_string()
    )

    print()

    print(
        "Range divergence flags:",
        int(
            df[
                "range_divergence_flag"
            ]
            .sum()
        ),
    )

    print(
        "Insufficient-source dates:",
        int(
            (
                df["coverage_status"]
                == COVERAGE_INSUFFICIENT
            )
            .sum()
        ),
    )


# ============================================================
# Manual run
# ============================================================

if __name__ == "__main__":

    from ingest import ingest_all
    from validate import validate_all
    from transform import transform_all

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

    for name, df in reconciled.items():

        print_reconciliation_summary(
            name=name,
            df=df,
        )