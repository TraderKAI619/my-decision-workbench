"""
Phase 1 — Raw CSV Contract Verification

One-off diagnostic script.

Purpose:
Verify whether the real Dukascopy USDJPY 1H CSV files match the raw-data
contract expected by the existing pipeline.

This script:
- DOES inspect raw CSV files
- DOES compare observed schema with config.py
- DOES inspect timestamp format
- DOES inspect numeric parseability
- DOES scan all files for schema consistency

This script DOES NOT:
- modify raw CSV files
- write to DuckDB
- run validate.py
- run transform.py
- make trading/decision interpretations
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path
from typing import Any

import pandas as pd

from config import DUKASCOPY_REQUIRED_COLUMNS


NUMERIC_COLUMNS = (
    "Open",
    "High",
    "Low",
    "Close",
    "Volume",
)


# Explicit formats only.
# Do not rely on pandas inference for the actual contract.
#
# The first format is based on the real Dukascopy files already inspected:
# 2020-12-03T00:00:00+00:00
CANDIDATE_TIMESTAMP_FORMATS = (
    "%Y-%m-%dT%H:%M:%S%z",
    "%Y-%m-%dT%H:%M:%S.%f%z",
    "%d.%m.%Y %H:%M:%S.%f",
    "%d.%m.%Y %H:%M:%S",
    "%Y-%m-%d %H:%M:%S.%f",
    "%Y-%m-%d %H:%M:%S",
    "%Y.%m.%d %H:%M:%S",
)


# ============================================================
# 1. File-level inspection
# ============================================================

def inspect_file_encoding(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "file_name": path.name,
        "exists": path.is_file(),
        "file_size_bytes": path.stat().st_size if path.is_file() else 0,
        "encoding": None,
        "has_bom": False,
        "delimiter": None,
        "readable": False,
        "error": None,
    }

    if not result["exists"] or result["file_size_bytes"] == 0:
        result["error"] = "file missing or empty"
        return result

    raw = path.read_bytes()[:4096]

    if raw.startswith(b"\xef\xbb\xbf"):
        result["has_bom"] = True
        result["encoding"] = "utf-8-sig"
    else:
        try:
            raw.decode("utf-8")
            result["encoding"] = "utf-8"
        except UnicodeDecodeError:
            try:
                raw.decode("latin-1")
                result["encoding"] = "latin-1"
            except UnicodeDecodeError:
                result["encoding"] = "unknown"

    try:
        encoding = result["encoding"]

        if encoding == "unknown":
            raise UnicodeDecodeError(
                "unknown",
                b"",
                0,
                1,
                "unable to determine encoding",
            )

        text_sample = raw.decode(encoding, errors="strict")
        first_line = text_sample.splitlines()[0]
        dialect = csv.Sniffer().sniff(first_line)
        result["delimiter"] = dialect.delimiter

    except Exception as exc:
        result["error"] = f"delimiter sniff failed: {exc}"

    result["readable"] = result["encoding"] != "unknown"

    return result


# ============================================================
# 2. CSV structure inspection
# ============================================================

def inspect_csv_structure(path: Path) -> dict[str, Any]:
    try:
        df = pd.read_csv(path)
    except Exception as exc:
        return {
            "file_name": path.name,
            "load_error": str(exc),
        }

    return {
        "file_name": path.name,
        "row_count": len(df),
        "column_count": len(df.columns),
        "columns": list(df.columns),
        "has_duplicated_column_names": (
            len(df.columns) != len(set(df.columns))
        ),
        "has_unnamed_columns": any(
            str(column).startswith("Unnamed")
            for column in df.columns
        ),
        "first_row": (
            df.iloc[0].to_dict()
            if len(df)
            else None
        ),
        "last_row": (
            df.iloc[-1].to_dict()
            if len(df)
            else None
        ),
    }


# ============================================================
# 3. Schema inspection
# ============================================================

def inspect_schema(
    path: Path,
    expected_columns: tuple[str, ...],
) -> dict[str, Any]:

    try:
        df = pd.read_csv(path, nrows=5)
    except Exception as exc:
        return {
            "file_name": path.name,
            "load_error": str(exc),
        }

    observed = list(df.columns)

    expected_set = set(expected_columns)
    observed_set = set(observed)

    return {
        "file_name": path.name,
        "expected_columns": list(expected_columns),
        "observed_columns": observed,
        "missing_columns": sorted(
            expected_set - observed_set
        ),
        "extra_columns": sorted(
            observed_set - expected_set
        ),
        "exact_column_match": (
            expected_set == observed_set
        ),
        "column_order_match": (
            list(expected_columns) == observed
        ),
    }


# ============================================================
# 4. Timestamp inspection
# ============================================================

def guess_timestamp_column(
    columns: list[str],
) -> str | None:

    candidates = [
        column
        for column in columns
        if column not in NUMERIC_COLUMNS
    ]

    for column in candidates:
        if (
            column in DUKASCOPY_REQUIRED_COLUMNS
            and column not in NUMERIC_COLUMNS
        ):
            return column

    return candidates[0] if candidates else None


def inspect_timestamp_format(
    path: Path,
    timestamp_col: str | None = None,
) -> dict[str, Any]:

    try:
        df = pd.read_csv(path)
    except Exception as exc:
        return {
            "file_name": path.name,
            "load_error": str(exc),
        }

    column = (
        timestamp_col
        or guess_timestamp_column(list(df.columns))
    )

    if column is None or column not in df.columns:
        return {
            "file_name": path.name,
            "timestamp_column": column,
            "error": "no timestamp column found",
        }

    raw_values = df[column].astype(str)

    total_rows = len(raw_values)

    format_results: dict[str, Any] = {}

    best_format = None
    best_success = -1

    for timestamp_format in CANDIDATE_TIMESTAMP_FORMATS:

        parsed = pd.to_datetime(
            raw_values,
            format=timestamp_format,
            errors="coerce",
        )

        success = int(parsed.notna().sum())

        format_results[timestamp_format] = {
            "parsed_rows": success,
            "failed_rows": total_rows - success,
            "parse_success_pct": (
                round(
                    100 * success / total_rows,
                    4,
                )
                if total_rows
                else 0.0
            ),
        }

        if success > best_success:
            best_success = success
            best_format = timestamp_format

    timezone_offsets = sorted(
        {
            value[-6:]
            for value in raw_values
            if (
                len(value) >= 6
                and value[-6] in ("+", "-")
                and value[-3] == ":"
            )
        }
    )

    explicit_utc_offset = (
        timezone_offsets == ["+00:00"]
    )

    return {
        "file_name": path.name,
        "timestamp_column": column,
        "sample_raw_head": raw_values.head(5).tolist(),
        "sample_raw_tail": raw_values.tail(5).tolist(),
        "total_rows": total_rows,
        "explicit_format_results": format_results,
        "best_explicit_format": best_format,
        "best_explicit_success_pct": (
            round(
                100 * best_success / total_rows,
                4,
            )
            if total_rows
            else 0.0
        ),
        "timezone_offsets_observed": timezone_offsets,
        "explicit_utc_offset": explicit_utc_offset,
    }


# ============================================================
# 5. Numeric inspection
# ============================================================

def inspect_numeric_columns(
    path: Path,
) -> dict[str, Any]:

    try:
        df = pd.read_csv(path)
    except Exception as exc:
        return {
            "file_name": path.name,
            "load_error": str(exc),
        }

    result: dict[str, Any] = {
        "file_name": path.name,
        "columns": {},
    }

    for column in NUMERIC_COLUMNS:

        if column not in df.columns:
            result["columns"][column] = {
                "present": False,
            }
            continue

        raw = df[column]

        numeric = pd.to_numeric(
            raw,
            errors="coerce",
        )

        non_numeric_mask = (
            numeric.isna()
            & raw.notna()
        )

        result["columns"][column] = {
            "present": True,
            "inferred_dtype": str(raw.dtype),
            "null_count": int(
                raw.isna().sum()
            ),
            "non_numeric_count": int(
                non_numeric_mask.sum()
            ),
            "sample_non_numeric": (
                raw[non_numeric_mask]
                .head(5)
                .tolist()
            ),
            "min": (
                float(numeric.min())
                if numeric.notna().any()
                else None
            ),
            "max": (
                float(numeric.max())
                if numeric.notna().any()
                else None
            ),
        }

    return result


# ============================================================
# 6. Full-history lightweight schema scan
# ============================================================

def lightweight_schema_scan(
    files: list[Path],
) -> dict[str, Any]:

    signatures: dict[str, list[str]] = {}
    failures: list[dict[str, Any]] = []

    for path in files:

        try:
            df = pd.read_csv(
                path,
                nrows=1,
            )

            signature = ",".join(
                str(column)
                for column in df.columns
            )

            signatures.setdefault(
                signature,
                [],
            ).append(path.name)

        except Exception as exc:
            failures.append(
                {
                    "file_name": path.name,
                    "error": str(exc),
                }
            )

    return {
        "files_scanned": len(files),
        "unique_schema_count": len(signatures),
        "schema_signatures": {
            signature: {
                "file_count": len(names),
                "sample_files": names[:3],
            }
            for signature, names
            in signatures.items()
        },
        "unreadable_files": failures,
    }


# ============================================================
# 7. File discovery
# ============================================================

def discover_csv_files(
    raw_dir: Path,
) -> list[Path]:

    return sorted(
        raw_dir.glob("*.csv")
    )


def select_representative_files(
    files: list[Path],
) -> list[Path]:

    if not files:
        return []

    earliest = files[0]

    middle = files[
        len(files) // 2
    ]

    target_2026_08 = next(
        (
            path
            for path in files
            if "2026-08-03_to_2026-09-03"
            in path.name
        ),
        None,
    )

    selected = [
        earliest,
        middle,
    ]

    if target_2026_08 is not None:
        selected.append(
            target_2026_08
        )
    else:
        selected.append(
            files[-1]
        )

    # Remove accidental duplicates while preserving order.
    return list(
        dict.fromkeys(selected)
    )


# ============================================================
# 8. Price-type metadata inspection
# ============================================================

def inspect_price_type(
    files: list[Path],
) -> dict[str, Any]:

    detected_types: set[str] = set()
    unknown_files: list[str] = []

    for path in files:

        name = path.name.upper()

        if "_BID_" in name:
            detected_types.add("BID")

        elif "_ASK_" in name:
            detected_types.add("ASK")

        elif "_MID_" in name:
            detected_types.add("MID")

        else:
            unknown_files.append(
                path.name
            )

    return {
        "detected_price_types": sorted(
            detected_types
        ),
        "price_type_consistent": (
            len(detected_types) == 1
            and not unknown_files
        ),
        "unknown_price_type_files": (
            unknown_files
        ),
    }


# ============================================================
# 9. Cross-file consistency
# ============================================================

def compare_timestamp_contracts(
    deep_profiles: list[dict[str, Any]],
) -> dict[str, Any]:

    formats = {
        profile["file_name"]:
        profile["timestamp"].get(
            "best_explicit_format"
        )
        for profile in deep_profiles
    }

    unique_formats = set(
        formats.values()
    )

    utc_results = {
        profile["file_name"]:
        profile["timestamp"].get(
            "explicit_utc_offset",
            False,
        )
        for profile in deep_profiles
    }

    return {
        "timestamp_formats_by_file": formats,
        "timestamp_format_consistent": (
            len(unique_formats) <= 1
        ),
        "unique_timestamp_formats": sorted(
            str(value)
            for value in unique_formats
        ),
        "explicit_utc_by_file": utc_results,
        "all_representative_files_explicit_utc": (
            all(utc_results.values())
        ),
    }


# ============================================================
# 10. Orchestration
# ============================================================

def verify_dukascopy_raw_contract(
    raw_dir: Path,
) -> dict[str, Any]:

    files = discover_csv_files(
        raw_dir
    )

    if not files:
        return {
            "status": "FAIL",
            "reason": (
                f"no CSV files found in "
                f"{raw_dir}"
            ),
        }

    lightweight = (
        lightweight_schema_scan(
            files
        )
    )

    price_type = inspect_price_type(
        files
    )

    representative_files = (
        select_representative_files(
            files
        )
    )

    deep_profiles = []

    for path in representative_files:

        deep_profiles.append(
            {
                "file_name": path.name,
                "encoding": (
                    inspect_file_encoding(
                        path
                    )
                ),
                "structure": (
                    inspect_csv_structure(
                        path
                    )
                ),
                "schema": (
                    inspect_schema(
                        path,
                        DUKASCOPY_REQUIRED_COLUMNS,
                    )
                ),
                "timestamp": (
                    inspect_timestamp_format(
                        path
                    )
                ),
                "numeric": (
                    inspect_numeric_columns(
                        path
                    )
                ),
            }
        )

    timestamp_consistency = (
        compare_timestamp_contracts(
            deep_profiles
        )
    )

    reasons: list[str] = []

    schema_mismatches = [
        profile["file_name"]
        for profile in deep_profiles
        if not profile[
            "schema"
        ].get(
            "exact_column_match",
            False,
        )
    ]

    timestamp_failures = [
        profile["file_name"]
        for profile in deep_profiles
        if profile[
            "timestamp"
        ].get(
            "best_explicit_success_pct",
            0.0,
        )
        < 100.0
    ]

    numeric_failures = []

    for profile in deep_profiles:

        for column, details in (
            profile["numeric"]
            .get(
                "columns",
                {},
            )
            .items()
        ):

            if (
                not details.get(
                    "present",
                    False,
                )
                or details.get(
                    "non_numeric_count",
                    0,
                )
                > 0
            ):
                numeric_failures.append(
                    (
                        profile["file_name"],
                        column,
                    )
                )

    status = "PASS"

    if (
        lightweight[
            "unique_schema_count"
        ]
        != 1
    ):
        status = "FAIL"
        reasons.append(
            "multiple schema signatures "
            "found across full history"
        )

    if lightweight[
        "unreadable_files"
    ]:
        status = "FAIL"
        reasons.append(
            "one or more CSV files "
            "could not be read"
        )

    if schema_mismatches:
        status = "FAIL"
        reasons.append(
            "schema mismatch vs "
            "DUKASCOPY_REQUIRED_COLUMNS: "
            f"{schema_mismatches}"
        )

    if timestamp_failures:
        status = "FAIL"
        reasons.append(
            "timestamp format not fully "
            "resolved: "
            f"{timestamp_failures}"
        )

    if not timestamp_consistency[
        "timestamp_format_consistent"
    ]:
        status = "FAIL"
        reasons.append(
            "timestamp format differs "
            "across representative files"
        )

    if not timestamp_consistency[
        "all_representative_files_explicit_utc"
    ]:
        status = "FAIL"
        reasons.append(
            "representative timestamps "
            "do not all carry explicit "
            "+00:00 UTC offsets"
        )

    if numeric_failures:
        status = "FAIL"
        reasons.append(
            "numeric parsing failures: "
            f"{numeric_failures}"
        )

    if not price_type[
        "price_type_consistent"
    ]:
        status = "FAIL"
        reasons.append(
            "price type is not consistent "
            "across filenames"
        )

    return {
        "status": status,
        "reasons": reasons,
        "raw_directory": str(
            raw_dir
        ),
        "files_discovered": len(
            files
        ),
        "lightweight_schema_scan": (
            lightweight
        ),
        "price_type_contract": (
            price_type
        ),
        "representative_files": [
            path.name
            for path
            in representative_files
        ],
        "deep_profiles": (
            deep_profiles
        ),
        "timestamp_contract": (
            timestamp_consistency
        ),
        "raw_file_manual_edit_required": (
            False
        ),
        "production_contract_update_required": (
            status != "PASS"
        ),
    }


# ============================================================
# CLI
# ============================================================

if __name__ == "__main__":

    if len(sys.argv) != 2:

        print(
            "Usage: "
            "python "
            "verify_dukascopy_raw_contract.py "
            "/path/to/dukascopy/dir"
        )

        sys.exit(1)

    target_dir = Path(
        sys.argv[1]
    )

    report = (
        verify_dukascopy_raw_contract(
            target_dir
        )
    )

    print(
        json.dumps(
            report,
            indent=2,
            default=str,
            ensure_ascii=False,
        )
    )