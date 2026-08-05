PRAGMA threads=2;
PRAGMA memory_limit='1GB';
PRAGMA enable_progress_bar=false;

SELECT 'duckdb_version' AS check_name, version() AS value;

WITH sample AS (
    SELECT *,
        CASE
            WHEN ts IS NOT NULL THEN CAST(ts AS TIMESTAMP)
            ELSE CAST(CAST(date AS VARCHAR) || ' ' || time AS TIMESTAMP)
        END AS event_ts
    FROM read_parquet('/data/*/*.parquet', union_by_name=true, filename=true)
)
SELECT
    regexp_replace(filename, '^/data/', '') AS file,
    count(*) AS rows,
    min(event_ts) AS min_event_ts,
    max(event_ts) AS max_event_ts,
    count(*) FILTER (WHERE ts IS NOT NULL) AS recent_schema_rows,
    count(*) FILTER (WHERE date IS NOT NULL) AS legacy_schema_rows
FROM sample
GROUP BY 1
ORDER BY 1;

WITH sample AS (
    SELECT *
    FROM read_parquet('/data/*/*.parquet', union_by_name=true, filename=true)
)
SELECT
    'aggregate' AS check_name,
    count(*) AS total_rows,
    count(DISTINCT filename) AS files,
    count(*) FILTER (WHERE ts IS NOT NULL) AS recent_schema_rows,
    count(*) FILTER (WHERE date IS NOT NULL) AS legacy_schema_rows
FROM sample;

DESCRIBE SELECT *
FROM read_parquet('/data/*/*.parquet', union_by_name=true, filename=true);
