from __future__ import annotations

import numpy as np
import pandas as pd

from config import (
    OHLC_COLUMNS,
    PIP_SIZE,
    TARGET_TIMEZONE,
    TIMEFRAME_1D,
    TRADINGVIEW_ANALYTICAL_DATE_SHIFT_HOURS,
)

from validate import select_trusted_rows


# ============================================================
# Output values
# ============================================================

DIRECTION_UP = "UP"
DIRECTION_DOWN = "DOWN"
DIRECTION_FLAT = "FLAT"

SEQUENCE_CONTINUATION = "CONTINUATION"
SEQUENCE_STOP = "STOP"
SEQUENCE_TURN = "TURN"
SEQUENCE_REVERSE = "REVERSE"
SEQUENCE_FLAT = "FLAT"

IMBALANCE_UP = "UP"
IMBALANCE_DOWN = "DOWN"

WEEK_HIGHER = "HIGHER"
WEEK_LOWER = "LOWER"
WEEK_EQUAL = "EQUAL"


SERIES_KEYS = (
    "source",
    "symbol",
    "timeframe",
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


# ============================================================
# Time
# ============================================================

def add_core_time_fields(
    df: pd.DataFrame,
) -> pd.DataFrame:
    result = df.copy()

    result["bar_start_utc"] = result["timestamp"]

    result["time_utc9"] = (
        result["bar_start_utc"]
        .dt.tz_convert(TARGET_TIMEZONE)
    )

    return result


def add_tradingview_analytical_date(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """
    Add the Daily analytical date.

    This shift applies to TradingView Daily only.
    It is not the Dukascopy H1 aggregation boundary.
    """

    result = df.copy()

    shifted = (
        result["bar_start_utc"]
        + pd.Timedelta(
            hours=TRADINGVIEW_ANALYTICAL_DATE_SHIFT_HOURS
        )
    )

    result["date"] = (
        shifted
        .dt.tz_localize(None)
        .dt.normalize()
    )

    result["day_of_week"] = (
        result["date"]
        .dt.day_name()
        .str[:3]
        .str.upper()
    )

    return result


# ============================================================
# Range / candle anatomy
# ============================================================

def add_candle_anatomy(
    df: pd.DataFrame,
    pip_size: float = PIP_SIZE,
) -> pd.DataFrame:
    result = df.copy()

    result["range"] = (
        result["high"]
        - result["low"]
    )

    result["range_pips"] = (
        result["range"]
        / pip_size
    )

    result["body_size"] = (
        result["close"]
        - result["open"]
    ).abs()

    result["body_size_pips"] = (
        result["body_size"]
        / pip_size
    )

    body_high = (
        result[
            [
                "open",
                "close",
            ]
        ]
        .max(axis=1)
    )

    body_low = (
        result[
            [
                "open",
                "close",
            ]
        ]
        .min(axis=1)
    )

    result["upper_wick"] = (
        result["high"]
        - body_high
    )

    result["upper_wick_pips"] = (
        result["upper_wick"]
        / pip_size
    )

    result["lower_wick"] = (
        body_low
        - result["low"]
    )

    result["lower_wick_pips"] = (
        result["lower_wick"]
        / pip_size
    )

    valid_range = (
        result["range"]
        .replace(0, np.nan)
    )

    result["body_pct_of_range"] = (
        result["body_size"]
        / valid_range
    )

    result["upper_wick_pct_of_range"] = (
        result["upper_wick"]
        / valid_range
    )

    result["lower_wick_pct_of_range"] = (
        result["lower_wick"]
        / valid_range
    )

    return result


# ============================================================
# Previous bar
# ============================================================

def add_previous_bar_features(
    df: pd.DataFrame,
    pip_size: float = PIP_SIZE,
) -> pd.DataFrame:
    result = df.copy()

    result["previous_open"] = (
        result["open"]
        .shift(1)
    )

    result["previous_high"] = (
        result["high"]
        .shift(1)
    )

    result["previous_low"] = (
        result["low"]
        .shift(1)
    )

    result["previous_close"] = (
        result["close"]
        .shift(1)
    )

    result["close_change"] = (
        result["close"]
        - result["previous_close"]
    )

    result["close_change_pips"] = (
        result["close_change"]
        / pip_size
    )

    result["break_previous_high"] = pd.Series(
        result["high"]
        > result["previous_high"],
        index=result.index,
        dtype="boolean",
    )

    result["break_previous_low"] = pd.Series(
        result["low"]
        < result["previous_low"],
        index=result.index,
        dtype="boolean",
    )

    no_previous = (
        result["previous_close"]
        .isna()
    )

    result.loc[
        no_previous,
        "break_previous_high",
    ] = pd.NA

    result.loc[
        no_previous,
        "break_previous_low",
    ] = pd.NA

    return result


# ============================================================
# Candle direction
# ============================================================

def add_candle_direction(
    df: pd.DataFrame,
) -> pd.DataFrame:
    result = df.copy()

    result["candle_direction"] = np.select(
        [
            result["close"] > result["open"],
            result["close"] < result["open"],
        ],
        [
            DIRECTION_UP,
            DIRECTION_DOWN,
        ],
        default=DIRECTION_FLAT,
    )

    return result


def add_candle_direction_streak(
    df: pd.DataFrame,
) -> pd.DataFrame:
    result = df.copy()

    direction_changed = (
        result["candle_direction"]
        .ne(
            result["candle_direction"]
            .shift(1)
        )
    )

    streak_group = (
        direction_changed
        .cumsum()
    )

    result["candle_direction_streak"] = (
        result
        .groupby(
            streak_group,
            sort=False,
        )
        .cumcount()
        .add(1)
    )

    return result


# ============================================================
# Candle sequence state
# ============================================================

def add_candle_sequence_state(
    df: pd.DataFrame,
) -> pd.DataFrame:
    """
    Mechanical candle-sequence description only.

    REVERSE means three consecutive opposite candles.
    It does not mean confirmed market reversal.
    """

    result = df.copy()

    established_direction = None
    opposite_count = 0
    sequence_length = 0

    states: list[str] = []
    directions: list[str | None] = []
    lengths: list[int] = []

    for move in result["candle_direction"]:

        if move == DIRECTION_FLAT:
            states.append(SEQUENCE_FLAT)
            directions.append(
                established_direction
            )
            lengths.append(0)
            continue

        if established_direction is None:
            established_direction = move
            opposite_count = 0
            sequence_length = 1

            states.append(
                SEQUENCE_CONTINUATION
            )

            directions.append(
                established_direction
            )

            lengths.append(
                sequence_length
            )

            continue

        if move == established_direction:

            if opposite_count > 0:
                sequence_length = 1
            else:
                sequence_length += 1

            opposite_count = 0

            states.append(
                SEQUENCE_CONTINUATION
            )

            directions.append(
                established_direction
            )

            lengths.append(
                sequence_length
            )

            continue

        opposite_count += 1

        if opposite_count == 1:

            states.append(
                SEQUENCE_STOP
            )

            directions.append(
                move
            )

            lengths.append(0)

        elif opposite_count == 2:

            states.append(
                SEQUENCE_TURN
            )

            directions.append(
                move
            )

            lengths.append(0)

        else:

            established_direction = move
            sequence_length = 3
            opposite_count = 0

            states.append(
                SEQUENCE_REVERSE
            )

            directions.append(
                established_direction
            )

            lengths.append(
                sequence_length
            )

    result["candle_sequence_state"] = (
        states
    )

    result["candle_sequence_direction"] = (
        directions
    )

    result["candle_sequence_length"] = (
        lengths
    )

    return result


# ============================================================
# Imbalance
# ============================================================

def add_imbalance_features(
    df: pd.DataFrame,
    pip_size: float = PIP_SIZE,
) -> pd.DataFrame:
    """
    3-candle Imbalance.

    UP:
        Candle 1 High < Candle 3 Low

    DOWN:
        Candle 1 Low > Candle 3 High

    Touching counts as overlap.
    """

    result = df.copy()

    candle_1_high = (
        result["high"]
        .shift(2)
    )

    candle_1_low = (
        result["low"]
        .shift(2)
    )

    up_imbalance = (
        candle_1_high
        < result["low"]
    )

    down_imbalance = (
        candle_1_low
        > result["high"]
    )

    result["has_imbalance"] = pd.Series(
        (
            up_imbalance
            | down_imbalance
        ),
        index=result.index,
        dtype="boolean",
    )

    result["imbalance_direction"] = (
        np.select(
            [
                up_imbalance,
                down_imbalance,
            ],
            [
                IMBALANCE_UP,
                IMBALANCE_DOWN,
            ],
            default=None,
        )
    )

    result["imbalance_high"] = np.where(
        up_imbalance,
        result["low"],
        np.where(
            down_imbalance,
            candle_1_low,
            np.nan,
        ),
    )

    result["imbalance_low"] = np.where(
        up_imbalance,
        candle_1_high,
        np.where(
            down_imbalance,
            result["high"],
            np.nan,
        ),
    )

    result["imbalance_size"] = (
        result["imbalance_high"]
        - result["imbalance_low"]
    )

    result["imbalance_size_pips"] = (
        result["imbalance_size"]
        / pip_size
    )

    return result


# ============================================================
# One source × symbol × timeframe series
# ============================================================

def transform_one_series(
    df: pd.DataFrame,
    pip_size: float = PIP_SIZE,
) -> pd.DataFrame:
    result = (
        df
        .copy()
        .sort_values(
            "timestamp"
        )
        .reset_index(
            drop=True
        )
    )

    result = add_core_time_fields(
        result
    )

    result = add_candle_anatomy(
        result,
        pip_size=pip_size,
    )

    result = add_previous_bar_features(
        result,
        pip_size=pip_size,
    )

    result = add_candle_direction(
        result
    )

    result = add_candle_direction_streak(
        result
    )

    result = add_candle_sequence_state(
        result
    )

    result = add_imbalance_features(
        result,
        pip_size=pip_size,
    )

    return result


# ============================================================
# Core market-bar transformation
# ============================================================

def transform_market_bars(
    df: pd.DataFrame,
    dataset_name: str,
    pip_size: float = PIP_SIZE,
) -> pd.DataFrame:
    """
    Transform trusted bars without crossing source boundaries.
    """

    required_columns = (
        "timestamp",
        "open",
        "high",
        "low",
        "close",
        "source",
        "symbol",
        "timeframe",
        "eligible_for_trusted",
    )

    require_columns(
        df=df,
        required_columns=required_columns,
        dataset_name=dataset_name,
    )

    trusted = select_trusted_rows(
        df
    )

    if trusted.empty:
        raise ValueError(
            f"{dataset_name} has no trusted rows"
        )

    transformed_frames = []

    for _, group in trusted.groupby(
        list(SERIES_KEYS),
        sort=False,
        dropna=False,
    ):

        transformed_frames.append(
            transform_one_series(
                group,
                pip_size=pip_size,
            )
        )

    result = pd.concat(
        transformed_frames,
        ignore_index=True,
        sort=False,
    )

    return result


# ============================================================
# Weekly point-in-time context
# ============================================================

def add_weekly_context(
    df: pd.DataFrame,
    pip_size: float = PIP_SIZE,
) -> pd.DataFrame:
    """
    Add point-in-time weekly facts to Daily bars.

    Current week:
        running High / Low only

    Previous week:
        completed weekly aggregation

    No shift(5).
    """

    result = df.copy()

    require_columns(
        df=result,
        required_columns=(
            "date",
            "day_of_week",
            "high",
            "low",
            "source",
            "symbol",
            "timeframe",
        ),
        dataset_name="daily_weekly_context",
    )

    output_frames = []

    group_keys = [
        "source",
        "symbol",
        "timeframe",
    ]

    for _, group in result.groupby(
        group_keys,
        sort=False,
        dropna=False,
    ):

        group = (
            group
            .copy()
            .sort_values(
                "date"
            )
            .reset_index(
                drop=True
            )
        )

        group["_week_start"] = (
            group["date"]
            - pd.to_timedelta(
                group["date"].dt.weekday,
                unit="D",
            )
        )

        week_group = (
            group.groupby(
                "_week_start",
                sort=False,
            )
        )

        # Running week High / Low
        group["week_high_so_far"] = (
            week_group["high"]
            .cummax()
        )

        group["week_low_so_far"] = (
            week_group["low"]
            .cummin()
        )

        # Day where the running High changed
        previous_running_high = (
            week_group[
                "week_high_so_far"
            ]
            .shift(1)
        )

        new_week_high = (
            previous_running_high.isna()
            |
            (
                group["high"]
                > previous_running_high
            )
        )

        high_day_candidate = (
            group["day_of_week"]
            .where(
                new_week_high
            )
        )

        group[
            "week_high_day_so_far"
        ] = (
            high_day_candidate
            .groupby(
                group["_week_start"]
            )
            .ffill()
        )

        # Day where the running Low changed
        previous_running_low = (
            week_group[
                "week_low_so_far"
            ]
            .shift(1)
        )

        new_week_low = (
            previous_running_low.isna()
            |
            (
                group["low"]
                < previous_running_low
            )
        )

        low_day_candidate = (
            group["day_of_week"]
            .where(
                new_week_low
            )
        )

        group[
            "week_low_day_so_far"
        ] = (
            low_day_candidate
            .groupby(
                group["_week_start"]
            )
            .ffill()
        )

        # Completed weekly facts
        weekly = (
            group
            .groupby(
                "_week_start",
                as_index=False,
            )
            .agg(
                week_high=(
                    "high",
                    "max",
                ),
                week_low=(
                    "low",
                    "min",
                ),
                first_observed_date=(
                    "date",
                    "min",
                ),
                last_observed_date=(
                    "date",
                    "max",
                ),
            )
            .sort_values(
                "_week_start"
            )
            .reset_index(
                drop=True
            )
        )

        # First observed week may be a partial extraction boundary.
        weekly[
            "_usable_completed_week"
        ] = True

        if not weekly.empty:

            first_week_is_boundary_complete = (
                weekly.loc[
                    0,
                    "first_observed_date",
                ]
                ==
                weekly.loc[
                    0,
                    "_week_start",
                ]
            )

            weekly.loc[
                0,
                "_usable_completed_week",
            ] = (
                first_week_is_boundary_complete
            )

        weekly[
            "_previous_week_start"
        ] = (
            weekly["_week_start"]
            .shift(1)
        )

        weekly[
            "_previous_week_high_raw"
        ] = (
            weekly["week_high"]
            .shift(1)
        )

        weekly[
            "_previous_week_low_raw"
        ] = (
            weekly["week_low"]
            .shift(1)
        )

        weekly[
            "_previous_week_usable"
        ] = (
            weekly[
                "_usable_completed_week"
            ]
            .shift(1)
            .fillna(False)
        )

        previous_week_is_adjacent = (
            (
                weekly["_week_start"]
                - weekly[
                    "_previous_week_start"
                ]
            )
            ==
            pd.Timedelta(days=7)
        )

        previous_week_is_valid = (
            previous_week_is_adjacent
            &
            weekly[
                "_previous_week_usable"
            ]
        )

        weekly[
            "previous_week_high"
        ] = (
            weekly[
                "_previous_week_high_raw"
            ]
            .where(
                previous_week_is_valid
            )
        )

        weekly[
            "previous_week_low"
        ] = (
            weekly[
                "_previous_week_low_raw"
            ]
            .where(
                previous_week_is_valid
            )
        )

        weekly_reference = (
            weekly[
                [
                    "_week_start",
                    "previous_week_high",
                    "previous_week_low",
                ]
            ]
        )

        group = group.merge(
            weekly_reference,
            on="_week_start",
            how="left",
            validate="many_to_one",
        )

        group[
            "week_high_vs_previous_week_pips"
        ] = (
            (
                group[
                    "week_high_so_far"
                ]
                - group[
                    "previous_week_high"
                ]
            )
            / pip_size
        )

        group[
            "week_low_vs_previous_week_pips"
        ] = (
            (
                group[
                    "week_low_so_far"
                ]
                - group[
                    "previous_week_low"
                ]
            )
            / pip_size
        )

        high_difference = (
            group[
                "week_high_vs_previous_week_pips"
            ]
        )

        low_difference = (
            group[
                "week_low_vs_previous_week_pips"
            ]
        )

        group[
            "week_high_vs_previous_week"
        ] = pd.Series(
            pd.NA,
            index=group.index,
            dtype="string",
        )

        group.loc[
            high_difference > 0,
            "week_high_vs_previous_week",
        ] = WEEK_HIGHER

        group.loc[
            high_difference < 0,
            "week_high_vs_previous_week",
        ] = WEEK_LOWER

        group.loc[
            high_difference == 0,
            "week_high_vs_previous_week",
        ] = WEEK_EQUAL

        group[
            "week_low_vs_previous_week"
        ] = pd.Series(
            pd.NA,
            index=group.index,
            dtype="string",
        )

        group.loc[
            low_difference > 0,
            "week_low_vs_previous_week",
        ] = WEEK_HIGHER

        group.loc[
            low_difference < 0,
            "week_low_vs_previous_week",
        ] = WEEK_LOWER

        group.loc[
            low_difference == 0,
            "week_low_vs_previous_week",
        ] = WEEK_EQUAL

        group = group.drop(
            columns=[
                "_week_start",
            ]
        )

        output_frames.append(
            group
        )

    return pd.concat(
        output_frames,
        ignore_index=True,
        sort=False,
    )


# ============================================================
# Final columns
# ============================================================

CORE_COLUMNS = [

    # Time / identity
    "bar_start_utc",
    "time_utc9",
    "source",
    "symbol",
    "timeframe",

    # Price
    "open",
    "high",
    "low",
    "close",

    # Range
    "range",
    "range_pips",

    # Candle anatomy
    "body_size",
    "body_size_pips",
    "upper_wick",
    "upper_wick_pips",
    "lower_wick",
    "lower_wick_pips",
    "body_pct_of_range",
    "upper_wick_pct_of_range",
    "lower_wick_pct_of_range",

    # Previous bar
    "previous_open",
    "previous_high",
    "previous_low",
    "previous_close",
    "close_change",
    "close_change_pips",
    "break_previous_high",
    "break_previous_low",

    # Candle sequence
    "candle_direction",
    "candle_direction_streak",

    # Heuristic sequence state
    "candle_sequence_state",
    "candle_sequence_direction",
    "candle_sequence_length",

    # Imbalance
    "has_imbalance",
    "imbalance_direction",
    "imbalance_high",
    "imbalance_low",
    "imbalance_size",
    "imbalance_size_pips",
]


DAILY_WEEKLY_COLUMNS = [

    "week_high_so_far",
    "week_high_day_so_far",
    "week_low_so_far",
    "week_low_day_so_far",

    "previous_week_high",
    "previous_week_low",

    "week_high_vs_previous_week_pips",
    "week_low_vs_previous_week_pips",

    "week_high_vs_previous_week",
    "week_low_vs_previous_week",
]


DAILY_COLUMNS = [

    "date",
    "day_of_week",

    *CORE_COLUMNS,

    *DAILY_WEEKLY_COLUMNS,
]


# ============================================================
# TradingView Daily
# ============================================================

def transform_tradingview_daily(
    df: pd.DataFrame,
    pip_size: float = PIP_SIZE,
) -> pd.DataFrame:
    result = transform_market_bars(
        df=df,
        dataset_name="tradingview_daily",
        pip_size=pip_size,
    )

    if not (
        result["timeframe"]
        == TIMEFRAME_1D
    ).all():
        raise ValueError(
            "tradingview_daily contains non-1D rows"
        )

    result = add_tradingview_analytical_date(
        result
    )

    result = add_weekly_context(
        result,
        pip_size=pip_size,
    )

    result = (
        result
        .sort_values(
            [
                "source",
                "symbol",
                "date",
            ]
        )
        .reset_index(
            drop=True
        )
    )

    return result[
        DAILY_COLUMNS
    ]


# ============================================================
# Dukascopy H1
# ============================================================

def transform_dukascopy_1h(
    df: pd.DataFrame,
    pip_size: float = PIP_SIZE,
) -> pd.DataFrame:
    """
    Transform trusted Dukascopy H1 bars.

    No Daily analytical date is assigned here.
    Higher-timeframe aggregation boundaries are a separate contract.
    """

    result = transform_market_bars(
        df=df,
        dataset_name="dukascopy_1h",
        pip_size=pip_size,
    )

    result = (
        result
        .sort_values(
            [
                "source",
                "symbol",
                "bar_start_utc",
            ]
        )
        .reset_index(
            drop=True
        )
    )

    return result[
        CORE_COLUMNS
    ]


# ============================================================
# Full transformation
# ============================================================

def transform_all(
    validated: dict[str, pd.DataFrame],
) -> dict[str, pd.DataFrame]:
    required_datasets = {
        "tradingview_daily",
        "dukascopy_1h",
    }

    missing = (
        required_datasets
        - set(validated)
    )

    if missing:
        raise KeyError(
            f"Missing validated datasets: "
            f"{sorted(missing)}"
        )

    return {
        "tradingview_daily":
            transform_tradingview_daily(
                validated[
                    "tradingview_daily"
                ]
            ),

        "dukascopy_1h":
            transform_dukascopy_1h(
                validated[
                    "dukascopy_1h"
                ]
            ),
    }


# ============================================================
# Summary
# ============================================================

def print_transform_summary(
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

    print(
        "Sources:",
        sorted(
            df["source"]
            .dropna()
            .unique()
            .tolist()
        ),
    )

    print(
        "Timeframes:",
        sorted(
            df["timeframe"]
            .dropna()
            .unique()
            .tolist()
        ),
    )

    print(
        "Imbalances:",
        int(
            df["has_imbalance"]
            .fillna(False)
            .sum()
        ),
    )


# ============================================================
# Manual run
# ============================================================

if __name__ == "__main__":

    from ingest import ingest_all
    from validate import validate_all

    raw = ingest_all()

    validated = validate_all(
        raw
    )

    transformed = transform_all(
        validated
    )

    for name, df in transformed.items():

        print_transform_summary(
            name=name,
            df=df,
        )