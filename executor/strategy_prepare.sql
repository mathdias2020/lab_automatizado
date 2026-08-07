PRAGMA threads=1;
PRAGMA memory_limit='1500MB';
PRAGMA preserve_insertion_order=false;
PRAGMA temp_directory='/tmp';
PRAGMA max_temp_directory_size='70GB';
PRAGMA enable_progress_bar=false;

CREATE OR REPLACE TEMP TABLE config AS
SELECT * FROM read_json_auto('/runner/config.json');

CREATE OR REPLACE TEMP TABLE minute_features AS
SELECT
  upper(regexp_extract(filename, 'ticker=([^/\\]+)', 1)) AS asset,
  CAST(
    CASE WHEN ts IS NOT NULL THEN CAST(ts AS TIMESTAMP)
         ELSE CAST(CAST(date AS VARCHAR) || ' ' || CAST(time AS VARCHAR) AS TIMESTAMP)
    END AS DATE
  ) AS session_date,
  date_trunc(
    'minute',
    CASE WHEN ts IS NOT NULL THEN CAST(ts AS TIMESTAMP)
         ELSE CAST(CAST(date AS VARCHAR) || ' ' || CAST(time AS VARCHAR) AS TIMESTAMP)
    END
  ) AS minute_ts,
  arg_min(CAST(price AS DOUBLE),
    CASE WHEN ts IS NOT NULL THEN CAST(ts AS TIMESTAMP)
         ELSE CAST(CAST(date AS VARCHAR) || ' ' || CAST(time AS VARCHAR) AS TIMESTAMP)
    END
  ) AS open_price,
  arg_max(CAST(price AS DOUBLE),
    CASE WHEN ts IS NOT NULL THEN CAST(ts AS TIMESTAMP)
         ELSE CAST(CAST(date AS VARCHAR) || ' ' || CAST(time AS VARCHAR) AS TIMESTAMP)
    END
  ) AS close_price,
  sum(CASE WHEN CAST(trade_type AS VARCHAR) = 'AggressorBuyer' THEN abs(CAST(COALESCE(quantity, qty) AS DOUBLE))
           WHEN CAST(trade_type AS VARCHAR) = 'AggressorSeller' THEN -abs(CAST(COALESCE(quantity, qty) AS DOUBLE)) ELSE 0 END) AS signed_aggression_qty
FROM read_parquet('/data/**/*.parquet', union_by_name=true, filename=true)
WHERE upper(regexp_extract(filename, 'ticker=([^/\\]+)', 1)) = (SELECT asset FROM config)
  AND CASE WHEN ts IS NOT NULL THEN CAST(ts AS TIMESTAMP)
           ELSE CAST(CAST(date AS VARCHAR) || ' ' || CAST(time AS VARCHAR) AS TIMESTAMP)
      END >= (SELECT train_start::TIMESTAMP FROM config)
  AND CASE WHEN ts IS NOT NULL THEN CAST(ts AS TIMESTAMP)
           ELSE CAST(CAST(date AS VARCHAR) || ' ' || CAST(time AS VARCHAR) AS TIMESTAMP)
      END < (SELECT train_end_exclusive::TIMESTAMP FROM config)
  AND filename NOT LIKE '%2025%'
  AND filename NOT LIKE '%2026%'
GROUP BY asset, session_date, minute_ts;

COPY (
  SELECT
    (SELECT asset FROM config) AS asset,
    CASE
      WHEN (SELECT execution_spec.feature.aggression_quantile FROM config) <= 0.90 THEN quantile_cont(abs(signed_aggression_qty), 0.90)
      WHEN (SELECT execution_spec.feature.aggression_quantile FROM config) <= 0.95 THEN quantile_cont(abs(signed_aggression_qty), 0.95)
      WHEN (SELECT execution_spec.feature.aggression_quantile FROM config) <= 0.975 THEN quantile_cont(abs(signed_aggression_qty), 0.975)
      ELSE quantile_cont(abs(signed_aggression_qty), 0.99)
    END AS aggression_abs_threshold,
    CASE
      WHEN (SELECT execution_spec.feature.absorption_move_quantile FROM config) <= 0.25 THEN quantile_cont(abs(close_price - open_price), 0.25)
      WHEN (SELECT execution_spec.feature.absorption_move_quantile FROM config) <= 0.50 THEN quantile_cont(abs(close_price - open_price), 0.50)
      WHEN (SELECT execution_spec.feature.absorption_move_quantile FROM config) <= 0.75 THEN quantile_cont(abs(close_price - open_price), 0.75)
      ELSE quantile_cont(abs(close_price - open_price), 0.90)
    END AS absorption_move_abs_threshold,
    (SELECT train_start FROM config) AS train_start,
    (SELECT train_end_exclusive FROM config) AS train_end_exclusive
  FROM minute_features
) TO '/artifacts/thresholds.csv' (FORMAT CSV, HEADER true);
