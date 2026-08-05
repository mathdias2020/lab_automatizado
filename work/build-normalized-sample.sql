PRAGMA threads=2;
PRAGMA memory_limit='1GB';
PRAGMA enable_progress_bar=false;

CREATE OR REPLACE VIEW normalized_sample AS
WITH raw AS (
    SELECT *
    FROM read_parquet('/data/*/*.parquet', union_by_name=true, filename=true)
)
SELECT
    CASE
        WHEN ts IS NOT NULL THEN CAST(ts AS TIMESTAMP)
        ELSE CAST(CAST(date AS VARCHAR) || ' ' || time AS TIMESTAMP)
    END AS event_ts,
    upper(split_part(regexp_replace(filename, '^/data/', ''), '/', 1)) AS asset,
    COALESCE(CAST(ticker AS VARCHAR), upper(split_part(regexp_replace(filename, '^/data/', ''), '/', 1))) AS ticker,
    CAST(trade_number AS BIGINT) AS trade_number,
    CAST(price AS DOUBLE) AS price,
    CAST(COALESCE(quantity, qty) AS BIGINT) AS quantity,
    CAST(COALESCE(volume, vol) AS DOUBLE) AS volume,
    CAST(buy_agent AS VARCHAR) AS buy_agent_raw,
    CAST(sell_agent AS VARCHAR) AS sell_agent_raw,
    CAST(trade_type AS VARCHAR) AS trade_type_raw,
    CAST(aft AS VARCHAR) AS aft_raw,
    CAST(is_edit AS BOOLEAN) AS is_edit,
    CASE WHEN ts IS NOT NULL THEN 'recent' ELSE 'legacy' END AS source_schema,
    regexp_replace(filename, '^/data/', '') AS source_file
FROM raw;

COPY (
    SELECT * FROM normalized_sample
    WHERE source_file = 'wdofut/legacy_2026-03.parquet'
) TO '/out/wdofut/legacy_2026-03.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);

COPY (
    SELECT * FROM normalized_sample
    WHERE source_file = 'wdofut/recent_2026-04.parquet'
) TO '/out/wdofut/recent_2026-04.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);

COPY (
    SELECT * FROM normalized_sample
    WHERE source_file = 'winfut/legacy_2026-03.parquet'
) TO '/out/winfut/legacy_2026-03.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);

COPY (
    SELECT * FROM normalized_sample
    WHERE source_file = 'winfut/recent_2026-04.parquet'
) TO '/out/winfut/recent_2026-04.parquet'
(FORMAT PARQUET, COMPRESSION ZSTD);

SELECT 'normalized_rows' AS check_name, count(*) AS rows
FROM normalized_sample;
