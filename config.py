"""
Shared configuration for my-decision-workbench.

Only shared rules go here.
Actual processing logic stays in each module.
"""

from pathlib import Path


# ============================================================
# Paths
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parent

DATA_DIR = PROJECT_ROOT / "data"

RAW_DATA_DIR = DATA_DIR / "raw"
TRUSTED_DATA_DIR = DATA_DIR / "trusted"
CURATED_DATA_DIR = DATA_DIR / "curated"

USDJPY_RAW_DIR = RAW_DATA_DIR / "usdjpy"

TRADINGVIEW_DAILY_DIR = (
    USDJPY_RAW_DIR
    / "tradingview_daily"
)

DUKASCOPY_RAW_DIR = (
    USDJPY_RAW_DIR
    / "dukascopy"
)

DATABASE_DIR = PROJECT_ROOT / "database"

DUCKDB_PATH = (
    DATABASE_DIR
    / "decision_workbench.duckdb"
)


# ============================================================
# Instrument
# ============================================================

SYMBOL = "USDJPY"

BASE_CURRENCY = "USD"
QUOTE_CURRENCY = "JPY"

# USDJPY: 1 pip = 0.01 JPY
PIP_SIZE = 0.01


# ============================================================
# Sources
# ============================================================

SOURCE_OANDA = "OANDA"
SOURCE_FOREXCOM = "FOREXCOM"
SOURCE_PEPPERSTONE = "PEPPERSTONE"
SOURCE_FX_IDC = "FX_IDC"

# Keep this neutral until the actual provider is verified.
SOURCE_FX_COMPOSITE = "FX_COMPOSITE"

SOURCE_DUKASCOPY = "DUKASCOPY"


TRADINGVIEW_SOURCES = (
    SOURCE_OANDA,
    SOURCE_FOREXCOM,
    SOURCE_PEPPERSTONE,
    SOURCE_FX_IDC,
    SOURCE_FX_COMPOSITE,
)


ALL_MARKET_DATA_SOURCES = (
    *TRADINGVIEW_SOURCES,
    SOURCE_DUKASCOPY,
)


# ============================================================
# TradingView files
# ============================================================

TRADINGVIEW_FILE_SOURCE_MAP = {
    "OANDA_USDJPY, 1D.csv": SOURCE_OANDA,
    "FOREXCOM_USDJPY, 1D.csv": SOURCE_FOREXCOM,
    "PEPPERSTONE_USDJPY, 1D.csv": SOURCE_PEPPERSTONE,
    "FX_IDC_USDJPY, 1D.csv": SOURCE_FX_IDC,
    "FX_USDJPY, 1D.csv": SOURCE_FX_COMPOSITE,
}


# ============================================================
# Source metadata
# ============================================================

SOURCE_REGISTRY = {
    SOURCE_OANDA: {
        "source_group": "TRADINGVIEW",
        "raw_timeframe": "1D",
        "bar_origin": "NATIVE",
    },

    SOURCE_FOREXCOM: {
        "source_group": "TRADINGVIEW",
        "raw_timeframe": "1D",
        "bar_origin": "NATIVE",
    },

    SOURCE_PEPPERSTONE: {
        "source_group": "TRADINGVIEW",
        "raw_timeframe": "1D",
        "bar_origin": "NATIVE",
    },

    SOURCE_FX_IDC: {
        "source_group": "TRADINGVIEW",
        "raw_timeframe": "1D",
        "bar_origin": "NATIVE",
    },

    SOURCE_FX_COMPOSITE: {
        "source_group": "TRADINGVIEW",
        "raw_timeframe": "1D",
        "bar_origin": "NATIVE",
    },

    SOURCE_DUKASCOPY: {
        "source_group": "DUKASCOPY",
        "raw_timeframe": "1H",
        "raw_timezone": "UTC",
        "bar_origin": "NATIVE",
    },
}


# ============================================================
# TradingView raw contract
# ============================================================

# These must exist and contain usable market data.
TRADINGVIEW_CORE_REQUIRED_COLUMNS = (
    "time",
    "open",
    "high",
    "low",
    "close",
)


# These exist in the current exports, but blank values can be valid.
# Validate them separately from core OHLC.
TRADINGVIEW_SEMANTIC_COLUMNS = (
    "Up",
    "Down",
    "Daily High",
    "Daily Low",
)


# ============================================================
# Dukascopy raw contract
# ============================================================

DUKASCOPY_REQUIRED_COLUMNS = (
    "Etc/UTC",
    "Open",
    "High",
    "Low",
    "Close",
    "Volume",
)


DUKASCOPY_COLUMN_MAP = {
    "Etc/UTC": "timestamp",
    "Open": "open",
    "High": "high",
    "Low": "low",
    "Close": "close",
    "Volume": "volume",
}


# ============================================================
# Time
# ============================================================

UTC_TIMEZONE = "UTC"
TARGET_TIMEZONE = "Asia/Tokyo"


# Current TradingView analytical-date rule.
# This is not the Dukascopy 1H -> Daily boundary.
TRADINGVIEW_ANALYTICAL_DATE_SHIFT_HOURS = 3


# ============================================================
# Timeframes
# ============================================================

TIMEFRAME_1H = "1H"
TIMEFRAME_4H = "4H"
TIMEFRAME_1D = "1D"
TIMEFRAME_1W = "1W"
TIMEFRAME_1M = "1M"


# Lowest raw grain currently available for higher-timeframe reconstruction.
BASE_TIMEFRAME = TIMEFRAME_1H


ANALYTICAL_TIMEFRAMES = (
    TIMEFRAME_1H,
    TIMEFRAME_4H,
    TIMEFRAME_1D,
    TIMEFRAME_1W,
    TIMEFRAME_1M,
)


# Actual Top-Down reading order.
TOP_DOWN_ORDER = (
    TIMEFRAME_1M,
    TIMEFRAME_1W,
    TIMEFRAME_1D,
    TIMEFRAME_4H,
    TIMEFRAME_1H,
)


# ============================================================
# Candle direction
# ============================================================

CANDLE_DIRECTION_UP = "UP"
CANDLE_DIRECTION_DOWN = "DOWN"
CANDLE_DIRECTION_FLAT = "FLAT"


CANDLE_DIRECTIONS = (
    CANDLE_DIRECTION_UP,
    CANDLE_DIRECTION_DOWN,
    CANDLE_DIRECTION_FLAT,
)


# ============================================================
# Candle sequence
# ============================================================

# REVERSE is a sequence state, not a confirmed market reversal.
SEQUENCE_STATE_CONTINUATION = "CONTINUATION"
SEQUENCE_STATE_STOP = "STOP"
SEQUENCE_STATE_TURN = "TURN"
SEQUENCE_STATE_REVERSE = "REVERSE"
SEQUENCE_STATE_FLAT = "FLAT"


CANDLE_SEQUENCE_STATES = (
    SEQUENCE_STATE_CONTINUATION,
    SEQUENCE_STATE_STOP,
    SEQUENCE_STATE_TURN,
    SEQUENCE_STATE_REVERSE,
    SEQUENCE_STATE_FLAT,
)


# ============================================================
# Imbalance
# ============================================================

# Detection logic stays in transform.py.
IMBALANCE_UP = "UP"
IMBALANCE_DOWN = "DOWN"


IMBALANCE_DIRECTIONS = (
    IMBALANCE_UP,
    IMBALANCE_DOWN,
)


# ============================================================
# Weekly context
# ============================================================

LEVEL_HIGHER = "HIGHER"
LEVEL_LOWER = "LOWER"
LEVEL_EQUAL = "EQUAL"


LEVEL_COMPARISON_VALUES = (
    LEVEL_HIGHER,
    LEVEL_LOWER,
    LEVEL_EQUAL,
)


# ============================================================
# Data quality
# ============================================================

DQ_STATUS_PASS = "PASS"
DQ_STATUS_REVIEW = "REVIEW"
DQ_STATUS_REJECTED = "REJECTED"


DQ_STATUSES = (
    DQ_STATUS_PASS,
    DQ_STATUS_REVIEW,
    DQ_STATUS_REJECTED,
)


OHLC_COLUMNS = (
    "open",
    "high",
    "low",
    "close",
)


MARKET_BAR_REQUIRED_COLUMNS = (
    "source",
    "symbol",
    "timeframe",
    "open",
    "high",
    "low",
    "close",
)


# ============================================================
# Reconciliation
# ============================================================

# One provider cannot prove cross-source agreement.
MIN_SOURCES_FOR_CROSS_SOURCE_AGREEMENT = 2


RECONCILIATION_DIVERGENCE_THRESHOLD_PCT = 15.0


# Provider prices can differ.
# Never build one synthetic OHLC bar from multiple providers.


# ============================================================
# Ingestion
# ============================================================

FILE_HASH_ALGORITHM = "sha256"


# ============================================================
# Temporal processing
# ============================================================

# Sequential features must run in chronological order.
SORT_ASCENDING = True


# ============================================================
# Config checks
# ============================================================

def validate_config() -> None:
    """Check config consistency. No market data is read here."""

    # Instrument
    if not SYMBOL:
        raise ValueError(
            "SYMBOL must not be empty."
        )

    if PIP_SIZE <= 0:
        raise ValueError(
            "PIP_SIZE must be greater than zero."
        )

    # Sources
    if len(set(ALL_MARKET_DATA_SOURCES)) != len(
        ALL_MARKET_DATA_SOURCES
    ):
        raise ValueError(
            "Duplicate source identities found."
        )

    for source in ALL_MARKET_DATA_SOURCES:
        if source not in SOURCE_REGISTRY:
            raise ValueError(
                f"Missing source in SOURCE_REGISTRY: {source}"
            )

    # TradingView file mapping
    mapped_sources = set(
        TRADINGVIEW_FILE_SOURCE_MAP.values()
    )

    expected_sources = set(
        TRADINGVIEW_SOURCES
    )

    if mapped_sources != expected_sources:
        raise ValueError(
            "TradingView file mapping does not match "
            "the registered TradingView sources."
        )

    if len(TRADINGVIEW_FILE_SOURCE_MAP) != len(
        TRADINGVIEW_SOURCES
    ):
        raise ValueError(
            "Each TradingView source must map to one file."
        )

    # TradingView raw contract
    if len(set(TRADINGVIEW_CORE_REQUIRED_COLUMNS)) != len(
        TRADINGVIEW_CORE_REQUIRED_COLUMNS
    ):
        raise ValueError(
            "Duplicate TradingView core columns found."
        )

    if len(set(TRADINGVIEW_SEMANTIC_COLUMNS)) != len(
        TRADINGVIEW_SEMANTIC_COLUMNS
    ):
        raise ValueError(
            "Duplicate TradingView semantic columns found."
        )

    overlap = (
        set(TRADINGVIEW_CORE_REQUIRED_COLUMNS)
        & set(TRADINGVIEW_SEMANTIC_COLUMNS)
    )

    if overlap:
        raise ValueError(
            "TradingView core and semantic columns overlap: "
            f"{sorted(overlap)}"
        )

    # Dukascopy raw contract
    if len(set(DUKASCOPY_REQUIRED_COLUMNS)) != len(
        DUKASCOPY_REQUIRED_COLUMNS
    ):
        raise ValueError(
            "Duplicate Dukascopy required columns found."
        )

    if set(DUKASCOPY_COLUMN_MAP) != set(
        DUKASCOPY_REQUIRED_COLUMNS
    ):
        raise ValueError(
            "Dukascopy column map does not match "
            "the raw contract."
        )

    # Timeframes
    if BASE_TIMEFRAME not in ANALYTICAL_TIMEFRAMES:
        raise ValueError(
            "BASE_TIMEFRAME is missing from "
            "ANALYTICAL_TIMEFRAMES."
        )

    if len(set(ANALYTICAL_TIMEFRAMES)) != len(
        ANALYTICAL_TIMEFRAMES
    ):
        raise ValueError(
            "Duplicate analytical timeframes found."
        )

    if len(set(TOP_DOWN_ORDER)) != len(
        TOP_DOWN_ORDER
    ):
        raise ValueError(
            "Duplicate timeframes found in TOP_DOWN_ORDER."
        )

    if set(TOP_DOWN_ORDER) != set(
        ANALYTICAL_TIMEFRAMES
    ):
        raise ValueError(
            "TOP_DOWN_ORDER and ANALYTICAL_TIMEFRAMES "
            "must contain the same timeframes."
        )

    # Reconciliation
    if MIN_SOURCES_FOR_CROSS_SOURCE_AGREEMENT < 2:
        raise ValueError(
            "Cross-source agreement requires "
            "at least two sources."
        )

    if RECONCILIATION_DIVERGENCE_THRESHOLD_PCT < 0:
        raise ValueError(
            "RECONCILIATION_DIVERGENCE_THRESHOLD_PCT "
            "cannot be negative."
        )

    # File hashing
    if FILE_HASH_ALGORITHM != "sha256":
        raise ValueError(
            "Current file hash standard is sha256."
        )


validate_config()