PRAGMA threads=1;
PRAGMA memory_limit='1500MB';
PRAGMA preserve_insertion_order=false;
PRAGMA temp_directory='/tmp';
PRAGMA max_temp_directory_size='20GB';
PRAGMA enable_progress_bar=false;

CREATE OR REPLACE VIEW ticks AS
SELECT *
FROM read_parquet('/data/**/*.parquet', union_by_name=true, hive_partitioning=true, filename=true);

COPY (
    SELECT
        asset,
        source_schema,
        count(*) AS rows,
        count(DISTINCT source_file) AS source_files,
        min(event_ts) AS min_event_ts,
        max(event_ts) AS max_event_ts,
        count(*) FILTER (WHERE event_ts IS NULL) AS null_event_ts,
        count(*) FILTER (WHERE ticker IS NULL) AS null_ticker,
        count(*) FILTER (WHERE trade_number IS NULL) AS null_trade_number,
        count(*) FILTER (WHERE price IS NULL) AS null_price,
        count(*) FILTER (WHERE quantity IS NULL) AS null_quantity,
        count(*) FILTER (WHERE volume IS NULL) AS null_volume,
        count(*) FILTER (WHERE source_file IS NULL) AS null_source_file
    FROM ticks
    GROUP BY 1, 2
    ORDER BY 1, 2
) TO '/artifacts/partition_quality.csv'
(FORMAT CSV, HEADER true);

COPY (
    SELECT
        asset,
        source_schema,
        source_file,
        count(*) AS rows,
        min(event_ts) AS min_event_ts,
        max(event_ts) AS max_event_ts,
        min(price) AS min_price,
        max(price) AS max_price,
        count(*) FILTER (WHERE is_edit = true) AS edited_rows
    FROM ticks
    GROUP BY 1, 2, 3
    ORDER BY 1, 2, 3
) TO '/artifacts/source_quality.csv'
(FORMAT CSV, HEADER true);

COPY (
    SELECT
        version() AS duckdb_version,
        current_localtimestamp() AS completed_at,
        count(*) AS total_rows,
        count(DISTINCT asset) AS assets,
        count(DISTINCT source_schema) AS source_schemas,
        count(DISTINCT source_file) AS source_files,
        min(event_ts) AS min_event_ts,
        max(event_ts) AS max_event_ts
    FROM ticks
) TO '/artifacts/run_summary.csv'
(FORMAT CSV, HEADER true);
