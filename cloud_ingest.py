from __future__ import annotations

import argparse
import re
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from google.cloud import bigquery


PROJECT_ID = "my-decision-workbench"
LOCATION = "asia-northeast1"

TRADINGVIEW_DATASET = "raw_tradingview"
DUKASCOPY_DATASET = "raw_dukascopy"
TABLE_NAME = "market_bars"

TRADINGVIEW_COLUMNS = (
    "time",
    "open",
    "high",
    "low",
    "close",
    "Up",
    "Down",
    "Daily High",
    "Daily Low",
)

DUKASCOPY_COLUMNS = (
    "Etc/UTC",
    "Open",
    "High",
    "Low",
    "Close",
    "Volume",
)


def client() -> bigquery.Client:
    return bigquery.Client(project=PROJECT_ID, location=LOCATION)


def assert_schema(df: pd.DataFrame, expected: tuple[str, ...], source_file: Path) -> None:
    actual = tuple(df.columns)

    if actual != expected:
        raise ValueError(
            f"Schema mismatch: {source_file}\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )


def parse_tradingview_filename(path: Path) -> tuple[str, str, str]:
    match = re.fullmatch(
        r"(?P<provider>.+?)_(?P<symbol>[A-Z]{6}), (?P<timeframe>\d+[DWMH])\.csv",
        path.name,
    )

    if not match:
        raise ValueError(f"Unsupported TradingView filename: {path.name}")

    provider = match.group("provider")
    symbol = match.group("symbol")

    raw_timeframe = match.group("timeframe")
    timeframe = {
        "1D": "D",
        "1W": "W",
        "1M": "M",
        "1H": "H1",
        "4H": "H4",
    }.get(raw_timeframe, raw_timeframe)

    return provider, symbol, timeframe


def parse_dukascopy_filename(path: Path) -> tuple[str, str, str]:
    match = re.fullmatch(
        r"(?P<base>[A-Z]{3})-(?P<quote>[A-Z]{3})_"
        r"(?P<hours>\d+)Hour_(?P<price_type>[A-Z]+)_.*\.csv",
        path.name,
    )

    if not match:
        raise ValueError(f"Unsupported Dukascopy filename: {path.name}")

    symbol = match.group("base") + match.group("quote")
    timeframe = f"H{int(match.group('hours'))}"
    price_type = match.group("price_type")

    return symbol, timeframe, price_type


def tradingview_frame(path: Path, ingested_at: datetime) -> pd.DataFrame:
    df = pd.read_csv(path)
    assert_schema(df, TRADINGVIEW_COLUMNS, path)

    provider, symbol, timeframe = parse_tradingview_filename(path)

    out = pd.DataFrame(
        {
            "source": "TRADINGVIEW",
            "provider": provider,
            "symbol": symbol,
            "timeframe": timeframe,
            "raw_timestamp": pd.to_numeric(df["time"], errors="raise").astype("int64"),
            "open": pd.to_numeric(df["open"], errors="coerce"),
            "high": pd.to_numeric(df["high"], errors="coerce"),
            "low": pd.to_numeric(df["low"], errors="coerce"),
            "close": pd.to_numeric(df["close"], errors="coerce"),
            "up": pd.to_numeric(df["Up"], errors="coerce"),
            "down": pd.to_numeric(df["Down"], errors="coerce"),
            "daily_high": pd.to_numeric(df["Daily High"], errors="coerce"),
            "daily_low": pd.to_numeric(df["Daily Low"], errors="coerce"),
            "source_file": str(path),
            "ingested_at": ingested_at,
        }
    )

    return out


def dukascopy_frame(path: Path, ingested_at: datetime) -> pd.DataFrame:
    df = pd.read_csv(path)
    assert_schema(df, DUKASCOPY_COLUMNS, path)

    symbol, timeframe, price_type = parse_dukascopy_filename(path)

    out = pd.DataFrame(
        {
            "source": "DUKASCOPY",
            "price_type": price_type,
            "symbol": symbol,
            "timeframe": timeframe,
            "bar_start_utc": pd.to_datetime(
                df["Etc/UTC"],
                utc=True,
                errors="raise",
            ),
            "open": pd.to_numeric(df["Open"], errors="coerce"),
            "high": pd.to_numeric(df["High"], errors="coerce"),
            "low": pd.to_numeric(df["Low"], errors="coerce"),
            "close": pd.to_numeric(df["Close"], errors="coerce"),
            "volume": pd.to_numeric(df["Volume"], errors="coerce").astype("Int64"),
            "source_file": str(path),
            "ingested_at": ingested_at,
        }
    )

    return out


def ensure_tables(bq: bigquery.Client) -> None:
    tv_table = bigquery.Table(
        f"{PROJECT_ID}.{TRADINGVIEW_DATASET}.{TABLE_NAME}",
        schema=[
            bigquery.SchemaField("source", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("provider", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("symbol", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("timeframe", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("raw_timestamp", "INT64", mode="REQUIRED"),
            bigquery.SchemaField("open", "FLOAT64"),
            bigquery.SchemaField("high", "FLOAT64"),
            bigquery.SchemaField("low", "FLOAT64"),
            bigquery.SchemaField("close", "FLOAT64"),
            bigquery.SchemaField("up", "FLOAT64"),
            bigquery.SchemaField("down", "FLOAT64"),
            bigquery.SchemaField("daily_high", "FLOAT64"),
            bigquery.SchemaField("daily_low", "FLOAT64"),
            bigquery.SchemaField("source_file", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("ingested_at", "TIMESTAMP", mode="REQUIRED"),
        ],
    )

    duka_table = bigquery.Table(
        f"{PROJECT_ID}.{DUKASCOPY_DATASET}.{TABLE_NAME}",
        schema=[
            bigquery.SchemaField("source", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("price_type", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("symbol", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("timeframe", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("bar_start_utc", "TIMESTAMP", mode="REQUIRED"),
            bigquery.SchemaField("open", "FLOAT64"),
            bigquery.SchemaField("high", "FLOAT64"),
            bigquery.SchemaField("low", "FLOAT64"),
            bigquery.SchemaField("close", "FLOAT64"),
            bigquery.SchemaField("volume", "INT64"),
            bigquery.SchemaField("source_file", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("ingested_at", "TIMESTAMP", mode="REQUIRED"),
        ],
    )

    bq.create_table(tv_table, exists_ok=True)
    bq.create_table(duka_table, exists_ok=True)


def load_snapshot(
    bq: bigquery.Client,
    table_id: str,
    df: pd.DataFrame,
) -> None:
    load_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE
    )

    bq.load_table_from_dataframe(
        df,
        table_id,
        job_config=load_config,
    ).result()


def ingest_tradingview(bq: bigquery.Client, root: Path) -> tuple[int, int]:
    files = sorted(root.glob("*.csv"))

    if not files:
        raise ValueError(f"No TradingView CSV files found in: {root}")

    ingested_at = datetime.now(timezone.utc)
    frames = []

    for path in files:
        df = tradingview_frame(path, ingested_at)
        frames.append(df)
        print(f"[TRADINGVIEW] {path.name}: {len(df):,} rows")

    snapshot = pd.concat(frames, ignore_index=True)

    load_snapshot(
        bq,
        f"{PROJECT_ID}.{TRADINGVIEW_DATASET}.{TABLE_NAME}",
        snapshot,
    )

    return len(files), len(snapshot)


def ingest_dukascopy(bq: bigquery.Client, root: Path) -> tuple[int, int]:
    files = sorted(root.glob("*.csv"))

    if not files:
        raise ValueError(f"No Dukascopy CSV files found in: {root}")

    ingested_at = datetime.now(timezone.utc)
    frames = []

    for path in files:
        df = dukascopy_frame(path, ingested_at)
        frames.append(df)
        print(f"[DUKASCOPY] {path.name}: {len(df):,} rows")

    snapshot = pd.concat(frames, ignore_index=True)

    load_snapshot(
        bq,
        f"{PROJECT_ID}.{DUKASCOPY_DATASET}.{TABLE_NAME}",
        snapshot,
    )

    return len(files), len(snapshot)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--tradingview-root",
        type=Path,
        default=Path("data/raw/usdjpy/tradingview_daily"),
    )
    parser.add_argument(
        "--dukascopy-root",
        type=Path,
        default=Path("data/raw/usdjpy/dukascopy"),
    )
    args = parser.parse_args()

    bq = client()
    ensure_tables(bq)

    tv_files, tv_rows = ingest_tradingview(
        bq,
        args.tradingview_root,
    )

    duka_files, duka_rows = ingest_dukascopy(
        bq,
        args.dukascopy_root,
    )

    print("\n=== CLOUD INGESTION COMPLETE ===")
    print(f"TradingView files: {tv_files}")
    print(f"TradingView rows:  {tv_rows:,}")
    print(f"Dukascopy files:   {duka_files}")
    print(f"Dukascopy rows:    {duka_rows:,}")


if __name__ == "__main__":
    main()
