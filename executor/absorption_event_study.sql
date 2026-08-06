PRAGMA threads=1;
PRAGMA memory_limit='1500MB';
PRAGMA preserve_insertion_order=false;
PRAGMA temp_directory='/tmp';
PRAGMA max_temp_directory_size='20GB';
PRAGMA enable_progress_bar=false;

CREATE OR REPLACE TEMP TABLE config AS
SELECT
    experiment_id::VARCHAR AS experiment_id,
    version::VARCHAR AS version,
    asset::VARCHAR AS asset,
    train_start::TIMESTAMP AS train_start,
    train_end_exclusive::TIMESTAMP AS train_end_exclusive,
    validation_start::TIMESTAMP AS validation_start,
    validation_end_exclusive::TIMESTAMP AS validation_end_exclusive,
    aggression_quantile::DOUBLE AS aggression_quantile,
    absorption_move_quantile::DOUBLE AS absorption_move_quantile,
    horizons_minutes::VARCHAR AS horizons_minutes,
    trade_types::VARCHAR AS trade_types,
    evidence_level::VARCHAR AS evidence_level,
    costs_applied::BOOLEAN AS costs_applied,
    trading_simulation::BOOLEAN AS trading_simulation,
    holdout_accessed::BOOLEAN AS holdout_accessed,
    holdout_policy::VARCHAR AS holdout_policy,
    input_manifest::VARCHAR AS input_manifest,
    source_timezone::VARCHAR AS source_timezone
FROM read_json_auto('/runner/config.json');

CREATE OR REPLACE TEMP VIEW ticks AS
SELECT
    event_ts,
    asset,
    price::DOUBLE AS price,
    abs(quantity::DOUBLE) AS quantity,
    trade_type_raw,
    source_file
FROM read_parquet('/data/**/*.parquet', union_by_name=true, hive_partitioning=true)
WHERE asset = (SELECT asset FROM config)
  AND event_ts >= (SELECT train_start FROM config)
  AND event_ts < (SELECT validation_end_exclusive FROM config)
  AND trade_type_raw IN ('AggressorBuyer', 'AggressorSeller')
  AND source_file NOT LIKE '%2025%'
  AND source_file NOT LIKE '%2026%';

CREATE OR REPLACE TEMP TABLE minute_features AS
SELECT
    asset,
    CAST(event_ts AS DATE) AS session_date,
    date_trunc('minute', event_ts) AS minute_ts,
    arg_min(price, event_ts) AS open_price,
    arg_max(price, event_ts) AS close_price,
    sum(CASE WHEN trade_type_raw = 'AggressorBuyer' THEN quantity ELSE -quantity END) AS signed_aggression_qty,
    sum(quantity) AS aggressive_qty,
    count(*) AS aggressive_trades,
    close_price - open_price AS contemporaneous_move_points
FROM ticks
GROUP BY asset, CAST(event_ts AS DATE), date_trunc('minute', event_ts);

CREATE OR REPLACE TEMP TABLE thresholds AS
SELECT
    c.asset,
    c.train_start,
    c.train_end_exclusive,
    c.validation_start,
    c.validation_end_exclusive,
    c.aggression_quantile,
    c.absorption_move_quantile,
    -- DuckDB exige quantis constantes; os mesmos valores ficam congelados no config.json.
    quantile_cont(abs(m.signed_aggression_qty), 0.95) AS aggression_abs_threshold,
    quantile_cont(abs(m.contemporaneous_move_points), 0.25) AS absorption_move_abs_threshold,
    count(*) AS train_minutes,
    count(DISTINCT m.session_date) AS train_days
FROM minute_features m
CROSS JOIN config c
WHERE m.minute_ts >= c.train_start
  AND m.minute_ts < c.train_end_exclusive
GROUP BY ALL;

CREATE OR REPLACE TEMP TABLE validation_minutes AS
SELECT
    m.*,
    t.aggression_abs_threshold,
    t.absorption_move_abs_threshold,
    CASE
        WHEN abs(m.signed_aggression_qty) >= t.aggression_abs_threshold
         AND abs(m.contemporaneous_move_points) <= t.absorption_move_abs_threshold
         AND m.signed_aggression_qty <> 0
        THEN true ELSE false
    END AS is_absorption_event,
    CASE
        WHEN abs(m.signed_aggression_qty) >= t.aggression_abs_threshold
         AND m.signed_aggression_qty <> 0
        THEN true ELSE false
    END AS is_aggression_extreme
FROM minute_features m
JOIN thresholds t ON t.asset = m.asset
WHERE m.minute_ts >= t.validation_start
  AND m.minute_ts < t.validation_end_exclusive;

CREATE OR REPLACE TEMP TABLE horizon_marks AS
SELECT v.*, 1 AS horizon_minutes, h.close_price AS future_close_price
FROM validation_minutes v
LEFT JOIN minute_features h
  ON h.asset = v.asset
 AND h.session_date = v.session_date
 AND h.minute_ts = v.minute_ts + INTERVAL '1 minute'
UNION ALL
SELECT v.*, 5 AS horizon_minutes, h.close_price AS future_close_price
FROM validation_minutes v
LEFT JOIN minute_features h
  ON h.asset = v.asset
 AND h.session_date = v.session_date
 AND h.minute_ts = v.minute_ts + INTERVAL '5 minutes'
UNION ALL
SELECT v.*, 15 AS horizon_minutes, h.close_price AS future_close_price
FROM validation_minutes v
LEFT JOIN minute_features h
  ON h.asset = v.asset
 AND h.session_date = v.session_date
 AND h.minute_ts = v.minute_ts + INTERVAL '15 minutes';

CREATE OR REPLACE TEMP TABLE marks AS
SELECT
    h.*,
    'absorption_event' AS population,
    sign(h.signed_aggression_qty) * (h.future_close_price - h.close_price) AS markout_points,
    sign(h.signed_aggression_qty) * (h.future_close_price - h.close_price) / nullif(h.close_price, 0) * 10000 AS markout_bps
FROM horizon_marks h
WHERE h.is_absorption_event AND h.future_close_price IS NOT NULL
UNION ALL
SELECT
    h.*,
    'aggression_extreme_baseline' AS population,
    sign(h.signed_aggression_qty) * (h.future_close_price - h.close_price) AS markout_points,
    sign(h.signed_aggression_qty) * (h.future_close_price - h.close_price) / nullif(h.close_price, 0) * 10000 AS markout_bps
FROM horizon_marks h
WHERE h.is_aggression_extreme AND h.future_close_price IS NOT NULL
UNION ALL
SELECT
    h.*,
    'all_directional_aggression_baseline' AS population,
    sign(h.signed_aggression_qty) * (h.future_close_price - h.close_price) AS markout_points,
    sign(h.signed_aggression_qty) * (h.future_close_price - h.close_price) / nullif(h.close_price, 0) * 10000 AS markout_bps
FROM horizon_marks h
WHERE h.signed_aggression_qty <> 0 AND h.future_close_price IS NOT NULL;

COPY (
    SELECT
        (SELECT experiment_id FROM config) AS experiment_id,
        asset,
        population,
        horizon_minutes,
        count(*) AS events,
        count(DISTINCT session_date) AS days,
        avg(markout_points) AS mean_markout_points,
        median(markout_points) AS median_markout_points,
        quantile_cont(markout_points, 0.25) AS p25_markout_points,
        quantile_cont(markout_points, 0.75) AS p75_markout_points,
        avg(markout_bps) AS mean_markout_bps,
        median(markout_bps) AS median_markout_bps,
        avg(CASE WHEN markout_points > 0 THEN 1.0 ELSE 0.0 END) AS positive_rate,
        (SELECT validation_start FROM config) AS validation_start,
        (SELECT validation_end_exclusive FROM config) AS validation_end_exclusive,
        false AS holdout_accessed,
        false AS costs_applied,
        false AS trading_simulation
    FROM marks
    GROUP BY asset, population, horizon_minutes
    ORDER BY asset, horizon_minutes, population
) TO '/artifacts/absorption_summary.csv' (FORMAT CSV, HEADER true);

COPY (
    SELECT
        asset,
        population,
        horizon_minutes,
        session_date,
        count(*) AS events,
        avg(markout_points) AS mean_markout_points,
        avg(markout_bps) AS mean_markout_bps,
        avg(CASE WHEN markout_points > 0 THEN 1.0 ELSE 0.0 END) AS positive_rate
    FROM marks
    WHERE population = 'absorption_event'
    GROUP BY asset, population, horizon_minutes, session_date
    ORDER BY asset, horizon_minutes, session_date
) TO '/artifacts/absorption_daily.csv' (FORMAT CSV, HEADER true);

COPY (
    SELECT
        (SELECT experiment_id FROM config) AS experiment_id,
        t.*,
        (SELECT evidence_level FROM config) AS evidence_level,
        (SELECT input_manifest FROM config) AS input_manifest,
        (SELECT source_timezone FROM config) AS source_timezone,
        (SELECT holdout_policy FROM config) AS holdout_policy,
        false AS holdout_accessed,
        false AS costs_applied,
        false AS trading_simulation
    FROM thresholds t
) TO '/artifacts/absorption_thresholds.csv' (FORMAT CSV, HEADER true);

COPY (
    SELECT
        (SELECT experiment_id FROM config) AS experiment_id,
        (SELECT version FROM config) AS version,
        (SELECT asset FROM config) AS asset,
        (SELECT train_start FROM config) AS train_start,
        (SELECT train_end_exclusive FROM config) AS train_end_exclusive,
        (SELECT validation_start FROM config) AS validation_start,
        (SELECT validation_end_exclusive FROM config) AS validation_end_exclusive,
        (SELECT count(*) FROM minute_features WHERE minute_ts < (SELECT validation_start FROM config)) AS train_minutes,
        (SELECT count(*) FROM minute_features WHERE minute_ts >= (SELECT validation_start FROM config)) AS validation_minutes,
        (SELECT count(DISTINCT session_date) FROM minute_features WHERE minute_ts < (SELECT validation_start FROM config)) AS train_days,
        (SELECT count(DISTINCT session_date) FROM minute_features WHERE minute_ts >= (SELECT validation_start FROM config)) AS validation_days,
        (SELECT count(*) FROM marks WHERE population = 'absorption_event') AS absorption_markouts,
        (SELECT horizons_minutes FROM config) AS horizons_minutes,
        (SELECT trade_types FROM config) AS trade_types,
        (SELECT evidence_level FROM config) AS evidence_level,
        false AS holdout_accessed,
        false AS costs_applied,
        false AS trading_simulation,
        'event study only; no orders, PnL or strategy promotion' AS operational_scope
) TO '/artifacts/research_run_summary.csv' (FORMAT CSV, HEADER true);
