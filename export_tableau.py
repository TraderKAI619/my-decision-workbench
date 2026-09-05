from pathlib import Path

import duckdb

from config import DUCKDB_PATH


# --------------------------------------------------
# Paths
# --------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parent

SQL_DIR = PROJECT_ROOT / "sql"

OUTPUT_DIR = (
    PROJECT_ROOT
    / "data"
    / "curated"
    / "tableau"
)


# --------------------------------------------------
# Generic SQL export
# --------------------------------------------------
def export_sql_model(
    sql_filename: str,
    output_filename: str,
):
    """Run a SQL model and export the result to CSV."""

    sql_path = SQL_DIR / sql_filename
    output_path = OUTPUT_DIR / output_filename

    sql = sql_path.read_text(encoding="utf-8")

    con = duckdb.connect(str(DUCKDB_PATH))

    try:
        df = con.execute(sql).fetchdf()

        if df.empty:
            raise ValueError(
                f"{sql_filename} returned no rows."
            )

        df.to_csv(
            output_path,
            index=False,
        )

    finally:
        con.close()

    return output_path, df.shape


# --------------------------------------------------
# Export Tableau datasets
# --------------------------------------------------
def export_tableau_datasets():
    """Build all curated datasets used by Tableau."""

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    exports = [
        (
            "event_attention.sql",
            "event_attention.csv",
        ),
        (
            "event_context_daily.sql",
            "event_context_daily.csv",
        ),
    ]

    results = []

    for sql_filename, output_filename in exports:
        output_path, shape = export_sql_model(
            sql_filename,
            output_filename,
        )

        results.append(
            {
                "output_path": output_path,
                "shape": shape,
            }
        )

    return results


# --------------------------------------------------
# Entry point
# --------------------------------------------------
if __name__ == "__main__":
    results = export_tableau_datasets()

    print("Tableau datasets exported successfully.")
    print()

    for result in results:
        print(
            f"{result['output_path']} "
            f"shape={result['shape']}"
        )
