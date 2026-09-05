"""
Read raw market data and attach provenance.

No data-quality judgement or analytical transformation here.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import pandas as pd

from config import (
    SYMBOL,
    SOURCE_DUKASCOPY,
    SOURCE_REGISTRY,
    TRADINGVIEW_DAILY_DIR,
    TRADINGVIEW_FILE_SOURCE_MAP,
    TRADINGVIEW_CORE_REQUIRED_COLUMNS,
    TRADINGVIEW_SEMANTIC_COLUMNS,
    DUKASCOPY_RAW_DIR,
    DUKASCOPY_REQUIRED_COLUMNS,
    DUKASCOPY_COLUMN_MAP,
    FILE_HASH_ALGORITHM,
)


# ============================================================
# File helpers
# ============================================================

def calculate_file_hash(file_path: Path) -> str:
    """Calculate the configured hash for one raw file."""

    hasher = hashlib.new(FILE_HASH_ALGORITHM)

    with file_path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            hasher.update(chunk)

    return hasher.hexdigest()


def get_ingestion_timestamp() -> pd.Timestamp:
    """Return the ingestion timestamp in UTC."""

    return pd.Timestamp.now(tz="UTC")


def require_file(file_path: Path) -> None:
    """Fail if an expected raw file does not exist."""

    if not file_path.is_file():
        raise FileNotFoundError(
            f"Raw file not found: {file_path}"
        )


def require_directory(directory: Path) -> None:
    """Fail if an expected raw directory does not exist."""

    if not directory.is_dir():
        raise FileNotFoundError(
            f"Raw directory not found: {directory}"
        )


def require_columns(
    df: pd.DataFrame,
    required_columns: tuple[str, ...],
    file_path: Path,
) -> None:
    """Fail if a raw file is missing expected columns."""

    missing = [
        column
        for column in required_columns
        if column not in df.columns
    ]

    if missing:
        raise ValueError(
            f"Missing required columns in {file_path.name}: "
            f"{missing}"
        )


# ============================================================
# TradingView
# ============================================================

def read_tradingview_file(
    file_path: Path,
    source: str,
    ingested_at_utc: pd.Timestamp,
) -> pd.DataFrame:
    """Read one TradingView Daily file."""

    require_file(file_path)

    df = pd.read_csv(file_path)

    require_columns(
        df=df,
        required_columns=TRADINGVIEW_CORE_REQUIRED_COLUMNS,
        file_path=file_path,
    )

    # These columns must exist in the current export.
    # Blank values inside them are valid.
    require_columns(
        df=df,
        required_columns=TRADINGVIEW_SEMANTIC_COLUMNS,
        file_path=file_path,
    )

    df = df.copy()

    df["source"] = source
    df["symbol"] = SYMBOL
    df["timeframe"] = SOURCE_REGISTRY[source]["raw_timeframe"]

    df["source_file"] = file_path.name
    df["file_hash"] = calculate_file_hash(file_path)
    df["ingested_at_utc"] = ingested_at_utc

    return df


def ingest_tradingview_daily() -> pd.DataFrame:
    """Read all configured TradingView Daily files."""

    require_directory(TRADINGVIEW_DAILY_DIR)

    ingested_at_utc = get_ingestion_timestamp()

    frames = []

    for filename, source in TRADINGVIEW_FILE_SOURCE_MAP.items():
        file_path = TRADINGVIEW_DAILY_DIR / filename

        frame = read_tradingview_file(
            file_path=file_path,
            source=source,
            ingested_at_utc=ingested_at_utc,
        )

        frames.append(frame)

    if not frames:
        raise ValueError(
            "No TradingView files were ingested."
        )

    return pd.concat(
        frames,
        ignore_index=True,
        sort=False,
    )


# ============================================================
# Dukascopy
# ============================================================

def read_dukascopy_file(
    file_path: Path,
    ingested_at_utc: pd.Timestamp,
) -> pd.DataFrame:
    """Read and standardize one Dukascopy 1H file."""

    require_file(file_path)

    df = pd.read_csv(file_path)

    require_columns(
        df=df,
        required_columns=DUKASCOPY_REQUIRED_COLUMNS,
        file_path=file_path,
    )

    df = df.copy()

    df = df.rename(
        columns=DUKASCOPY_COLUMN_MAP
    )

    df["source"] = SOURCE_DUKASCOPY
    df["symbol"] = SYMBOL
    df["timeframe"] = SOURCE_REGISTRY[
        SOURCE_DUKASCOPY
    ]["raw_timeframe"]

    df["source_file"] = file_path.name
    df["file_hash"] = calculate_file_hash(file_path)
    df["ingested_at_utc"] = ingested_at_utc

    return df


def ingest_dukascopy_1h() -> pd.DataFrame:
    """Read all Dukascopy 1H CSV files."""

    require_directory(DUKASCOPY_RAW_DIR)

    file_paths = sorted(
        DUKASCOPY_RAW_DIR.glob("*.csv")
    )

    if not file_paths:
        raise FileNotFoundError(
            f"No Dukascopy CSV files found in "
            f"{DUKASCOPY_RAW_DIR}"
        )

    ingested_at_utc = get_ingestion_timestamp()

    frames = []

    for file_path in file_paths:
        frame = read_dukascopy_file(
            file_path=file_path,
            ingested_at_utc=ingested_at_utc,
        )

        frames.append(frame)

    return pd.concat(
        frames,
        ignore_index=True,
        sort=False,
    )


# ============================================================
# Full ingestion
# ============================================================

def ingest_all() -> dict[str, pd.DataFrame]:
    """Read all currently supported raw market data."""

    tradingview_daily = ingest_tradingview_daily()
    dukascopy_1h = ingest_dukascopy_1h()

    return {
        "tradingview_daily": tradingview_daily,
        "dukascopy_1h": dukascopy_1h,
    }


# ============================================================
# Manual run
# ============================================================

if __name__ == "__main__":
    datasets = ingest_all()

    for name, df in datasets.items():
        print(
            f"{name}: "
            f"{len(df):,} rows | "
            f"{len(df.columns)} columns"
        )