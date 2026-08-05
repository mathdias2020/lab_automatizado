PRAGMA threads=2;
PRAGMA memory_limit='1GB';
PRAGMA enable_progress_bar=false;

WITH raw AS (
    SELECT
        regexp_replace(filename, '^/data/', '') AS source_file,
        CASE
            WHEN ts IS NOT NULL THEN CAST(ts AS TIMESTAMP)
            ELSE CAST(CAST(date AS VARCHAR) || ' ' || time AS TIMESTAMP)
        END AS event_ts
    FROM read_parquet('/data/*/*.parquet', union_by_name=true, filename=true)
), canonical AS (
    SELECT *
    FROM read_parquet('/out/**/*.parquet', union_by_name=true, hive_partitioning=true, filename=true)
), raw_stats AS (
    SELECT source_file, count(*) AS raw_rows, min(event_ts) AS raw_min_event_ts, max(event_ts) AS raw_max_event_ts
    FROM raw
    GROUP BY 1
), canonical_stats AS (
    SELECT source_file, count(*) AS canonical_rows, min(event_ts) AS canonical_min_event_ts, max(event_ts) AS canonical_max_event_ts
    FROM canonical
    GROUP BY 1
)
SELECT
    r.source_file,
    r.raw_rows,
    c.canonical_rows,
    r.raw_min_event_ts,
    c.canonical_min_event_ts,
    r.raw_max_event_ts,
    c.canonical_max_event_ts,
    r.raw_rows = c.canonical_rows AS rows_match,
    r.raw_min_event_ts = c.canonical_min_event_ts AS min_match,
    r.raw_max_event_ts = c.canonical_max_event_ts AS max_match
FROM raw_stats r
JOIN canonical_stats c USING (source_file)
ORDER BY 1;

SELECT
    asset,
    source_schema,
    count(*) AS rows,
    count(DISTINCT source_file) AS source_files,
    count(*) FILTER (WHERE event_ts IS NULL) AS null_event_ts,
    count(*) FILTER (WHERE ticker IS NULL) AS null_ticker,
    count(*) FILTER (WHERE trade_number IS NULL) AS null_trade_number,
    count(*) FILTER (WHERE price IS NULL) AS null_price,
    count(*) FILTER (WHERE quantity IS NULL) AS null_quantity,
    count(*) FILTER (WHERE volume IS NULL) AS null_volume,
    count(*) FILTER (WHERE source_file IS NULL) AS null_source_file
FROM read_parquet('/out/**/*.parquet', union_by_name=true, hive_partitioning=true, filename=true)
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT
    'aggregate' AS check_name,
    count(*) AS total_rows,
    count(DISTINCT source_file) AS source_files,
    count(DISTINCT asset) AS assets,
    count(DISTINCT source_schema) AS source_schemas,
    min(event_ts) AS min_event_ts,
    max(event_ts) AS max_event_ts
FROM read_parquet('/out/**/*.parquet', union_by_name=true, hive_partitioning=true, filename=true);
