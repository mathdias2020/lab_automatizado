PRAGMA threads=1;
PRAGMA memory_limit='1500MB';
PRAGMA preserve_insertion_order=false;
PRAGMA temp_directory='/tmp';
-- A varredura do snapshot completo pode precisar de mais de 20 GB de
-- temporario. O limite fica abaixo do espaco livre observado na VPS e o
-- wrapper garante que apenas um backtest ocupe esse espaco por vez.
PRAGMA max_temp_directory_size='40GB';
PRAGMA enable_progress_bar=false;

CREATE OR REPLACE TEMP TABLE config AS
SELECT * FROM read_json_auto('/runner/config.json');

CREATE OR REPLACE TEMP TABLE execution AS
SELECT
  json_extract_string(execution_spec, '$.feature.kind') AS feature_kind,
  CAST(json_extract(execution_spec, '$.feature.aggression_quantile') AS DOUBLE) AS aggression_quantile,
  CAST(json_extract(execution_spec, '$.feature.absorption_move_quantile') AS DOUBLE) AS absorption_move_quantile,
  CAST(json_extract(execution_spec, '$.exit.stop_ticks') AS INTEGER) AS stop_ticks,
  CAST(json_extract(execution_spec, '$.exit.target_ticks') AS INTEGER) AS target_ticks,
  CAST(json_extract(execution_spec, '$.exit.time_stop_minutes') AS INTEGER) AS time_stop_minutes,
  CAST(json_extract(execution_spec, '$.exit.break_even.enabled') AS BOOLEAN) AS break_even_enabled,
  CAST(json_extract(execution_spec, '$.exit.break_even.activate_ticks') AS INTEGER) AS break_even_activate_ticks,
  CAST(json_extract(execution_spec, '$.exit.break_even.offset_ticks') AS INTEGER) AS break_even_offset_ticks,
  CAST(json_extract(execution_spec, '$.exit.trailing.enabled') AS BOOLEAN) AS trailing_enabled,
  CAST(json_extract(execution_spec, '$.exit.trailing.activate_ticks') AS INTEGER) AS trailing_activate_ticks,
  CAST(json_extract(execution_spec, '$.exit.trailing.distance_ticks') AS INTEGER) AS trailing_distance_ticks,
  CAST(json_extract(execution_spec, '$.exit.partial.enabled') AS BOOLEAN) AS partial_enabled,
  CAST(json_extract(execution_spec, '$.exit.partial.fraction') AS DOUBLE) AS partial_fraction,
  CAST(json_extract(execution_spec, '$.exit.partial.target_ticks') AS INTEGER) AS partial_target_ticks,
  CASE WHEN asset = 'WDOFUT' THEN 0.5 ELSE 5.0 END AS tick_size,
  CASE WHEN asset = 'WDOFUT' THEN 10.0 ELSE 0.2 END AS point_value,
  CASE WHEN asset = 'WDOFUT' THEN 10 ELSE 50 END AS contracts
FROM config;

CREATE OR REPLACE TEMP TABLE raw_ticks AS
SELECT
  CAST(CAST(date AS VARCHAR) || ' ' || CAST(time AS VARCHAR) AS TIMESTAMP) AS event_ts,
  CASE WHEN regexp_extract(filename, 'ticker=([^/\\]+)', 1) = ''
       THEN (SELECT asset FROM config)
       ELSE upper(regexp_extract(filename, 'ticker=([^/\\]+)', 1)) END AS asset,
  CAST(price AS DOUBLE) AS price,
  abs(CAST(COALESCE(quantity, qty) AS DOUBLE)) AS quantity,
  CAST(trade_type AS VARCHAR) AS trade_type_raw,
  CAST(trade_number AS BIGINT) AS trade_number,
  filename AS source_file
FROM read_parquet('/data/**/*.parquet', union_by_name=true, filename=true)
WHERE (regexp_extract(filename, 'ticker=([^/\\]+)', 1) = ''
       OR upper(regexp_extract(filename, 'ticker=([^/\\]+)', 1)) = (SELECT asset FROM config))
  AND CAST(CAST(date AS VARCHAR) || ' ' || CAST(time AS VARCHAR) AS TIMESTAMP) >= (SELECT data_start_exclusive::TIMESTAMP FROM config)
  AND CAST(CAST(date AS VARCHAR) || ' ' || CAST(time AS VARCHAR) AS TIMESTAMP) < (SELECT data_end_exclusive::TIMESTAMP FROM config)
  AND source_file NOT LIKE '%2025%'
  AND source_file NOT LIKE '%2026%';

CREATE OR REPLACE TEMP TABLE minute_features AS
SELECT
  asset,
  CAST(event_ts AS DATE) AS session_date,
  date_trunc('minute', event_ts) AS minute_ts,
  arg_min(price, event_ts) AS open_price,
  arg_max(price, event_ts) AS close_price,
  sum(CASE WHEN trade_type_raw = 'AggressorBuyer' THEN quantity
           WHEN trade_type_raw = 'AggressorSeller' THEN -quantity ELSE 0 END) AS signed_aggression_qty,
  sum(CASE WHEN trade_type_raw IN ('AggressorBuyer', 'AggressorSeller') THEN quantity ELSE 0 END) AS aggressive_qty,
  count(*) AS trade_count
FROM raw_ticks
GROUP BY asset, CAST(event_ts AS DATE), date_trunc('minute', event_ts);

CREATE OR REPLACE TEMP TABLE thresholds AS
SELECT
  CAST((SELECT aggression_abs_threshold FROM read_csv_auto('/runner/thresholds.csv')) AS DOUBLE) AS aggression_abs_threshold,
  CAST((SELECT absorption_move_abs_threshold FROM read_csv_auto('/runner/thresholds.csv')) AS DOUBLE) AS absorption_move_abs_threshold;

-- Reduce the eligible minutes before joining to entry ticks. The previous
-- shape joined every later tick and discarded almost all rows afterwards.
CREATE OR REPLACE TEMP TABLE signal_candidates AS
SELECT
  m.asset,
  m.session_date,
  m.minute_ts AS signal_minute,
  m.signed_aggression_qty,
  CASE WHEN m.signed_aggression_qty > 0 THEN 1 ELSE -1 END AS side
FROM minute_features m
JOIN thresholds th ON true
WHERE abs(m.signed_aggression_qty) >= th.aggression_abs_threshold
  AND abs(m.close_price - m.open_price) <= th.absorption_move_abs_threshold
  AND m.signed_aggression_qty <> 0
  AND m.minute_ts >= (SELECT signal_start_exclusive::TIMESTAMP FROM config)
  AND m.minute_ts < (SELECT signal_end_exclusive::TIMESTAMP FROM config)
QUALIFY row_number() OVER (PARTITION BY m.session_date ORDER BY m.minute_ts) = 1;

-- Uma posição por estratégia/ativo por sessão nesta primeira implementação.
-- O primeiro sinal elegível da sessão é escolhido; não há sobreposição.
CREATE OR REPLACE TEMP TABLE entries AS
SELECT
  s.asset,
  s.session_date,
  s.signal_minute,
  s.signed_aggression_qty,
  s.side,
  date_trunc('minute', t.event_ts) AS entry_minute,
  t.price AS entry_price
FROM signal_candidates s
JOIN raw_ticks t
  ON t.asset = s.asset
 AND t.event_ts >= s.signal_minute + INTERVAL '1 minute'
 AND t.event_ts < s.signal_minute + INTERVAL '2 minutes'
QUALIFY row_number() OVER (PARTITION BY s.session_date ORDER BY t.event_ts, t.trade_number) = 1;

CREATE OR REPLACE TEMP TABLE path AS
SELECT
  e.asset, e.session_date, e.signal_minute, e.entry_minute, e.entry_price, e.side,
  r.event_ts, r.trade_number, r.price,
  max(CASE WHEN e.side = 1 THEN (r.price - e.entry_price) / x.tick_size
           ELSE (e.entry_price - r.price) / x.tick_size END)
    OVER (PARTITION BY e.session_date ORDER BY r.event_ts, r.trade_number ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS mfe_ticks,
  x.*
FROM entries e
JOIN raw_ticks r ON r.asset = e.asset
  AND r.event_ts >= e.entry_minute
  AND r.event_ts < e.entry_minute + (SELECT time_stop_minutes FROM execution) * INTERVAL '1 minute'
CROSS JOIN execution x;

CREATE OR REPLACE TEMP TABLE managed_path AS
SELECT
  p.*,
  CASE
    WHEN break_even_enabled AND mfe_ticks >= break_even_activate_ticks
      THEN break_even_offset_ticks
    ELSE -stop_ticks
  END AS break_even_stop_ticks,
  CASE
    WHEN trailing_enabled AND mfe_ticks >= trailing_activate_ticks
      THEN mfe_ticks - trailing_distance_ticks
    ELSE -stop_ticks
  END AS trailing_stop_ticks
FROM path p;

CREATE OR REPLACE TEMP TABLE partial_hits AS
SELECT * FROM managed_path
WHERE partial_enabled
  AND ((side = 1 AND (price - entry_price) / tick_size >= partial_target_ticks)
    OR (side = -1 AND (entry_price - price) / tick_size >= partial_target_ticks))
QUALIFY row_number() OVER (PARTITION BY session_date ORDER BY event_ts, trade_number) = 1;

CREATE OR REPLACE TEMP TABLE hits AS
SELECT p.* FROM managed_path p
LEFT JOIN partial_hits ph ON ph.session_date = p.session_date
WHERE (ph.event_ts IS NULL OR p.event_ts > ph.event_ts)
  AND ((p.side = 1 AND ((p.price - p.entry_price) / p.tick_size >= p.target_ticks
                 OR (p.price - p.entry_price) / p.tick_size <= greatest(p.break_even_stop_ticks, p.trailing_stop_ticks)))
   OR (p.side = -1 AND ((p.entry_price - p.price) / p.tick_size >= p.target_ticks
                  OR (p.entry_price - p.price) / p.tick_size <= -greatest(p.break_even_stop_ticks, p.trailing_stop_ticks))));

CREATE OR REPLACE TEMP TABLE first_hits AS
SELECT * FROM hits
QUALIFY row_number() OVER (PARTITION BY session_date ORDER BY event_ts, trade_number) = 1;

CREATE OR REPLACE TEMP TABLE last_marks AS
SELECT
  session_date,
  max(event_ts) AS last_event_ts,
  arg_max(price, event_ts) AS last_price
FROM path
GROUP BY session_date;

CREATE OR REPLACE TEMP TABLE exits AS
SELECT
  e.*,
  ph.event_ts AS partial_ts,
  ph.price AS partial_price,
  coalesce(h.event_ts, l.last_event_ts) AS exit_ts,
  coalesce(h.price, l.last_price) AS exit_price,
  CASE WHEN h.event_ts IS NULL AND ph.event_ts IS NOT NULL THEN 'partial_then_time_stop'
       WHEN h.event_ts IS NULL THEN 'time_stop'
       WHEN e.side = 1 AND (h.price - e.entry_price) / x.tick_size >= x.target_ticks THEN 'target'
       WHEN e.side = -1 AND (e.entry_price - h.price) / x.tick_size >= x.target_ticks THEN 'target'
       WHEN x.break_even_enabled AND h.mfe_ticks >= x.break_even_activate_ticks THEN 'break_even_or_trailing'
       ELSE 'stop' END AS exit_reason
FROM entries e
CROSS JOIN execution x
JOIN last_marks l ON l.session_date = e.session_date
LEFT JOIN partial_hits ph ON ph.session_date = e.session_date
LEFT JOIN first_hits h
  ON h.session_date = e.session_date;

CREATE OR REPLACE TEMP TABLE trades AS
SELECT
  e.asset, e.session_date, e.signal_minute, e.entry_minute, e.entry_price,
  x.contracts, x.tick_size, x.point_value, e.side,
  partial_ts, partial_price, exit_ts, exit_price, exit_reason,
  CASE WHEN x.partial_enabled AND partial_price IS NOT NULL THEN
         x.partial_fraction * CASE WHEN e.side = 1 THEN (partial_price - entry_price) * x.point_value ELSE (entry_price - partial_price) * x.point_value END
         + (1 - x.partial_fraction) * CASE WHEN e.side = 1 THEN (exit_price - entry_price) * x.point_value ELSE (entry_price - exit_price) * x.point_value END
       WHEN e.side = 1 THEN (exit_price - entry_price) * x.point_value
       ELSE (entry_price - exit_price) * x.point_value END AS gross_pnl_per_contract,
  CASE WHEN x.partial_enabled AND partial_price IS NOT NULL THEN
         (x.partial_fraction * CASE WHEN e.side = 1 THEN (partial_price - entry_price) * x.point_value ELSE (entry_price - partial_price) * x.point_value END
         + (1 - x.partial_fraction) * CASE WHEN e.side = 1 THEN (exit_price - entry_price) * x.point_value ELSE (entry_price - exit_price) * x.point_value END) * x.contracts
       WHEN e.side = 1 THEN (exit_price - entry_price) * x.point_value * x.contracts
       ELSE (entry_price - exit_price) * x.point_value * x.contracts END AS gross_pnl_position,
  false AS costs_applied,
  false AS slippage_applied,
  false AS holdout_accessed
FROM exits e CROSS JOIN execution x;

COPY (
  SELECT * FROM trades ORDER BY session_date, entry_minute
) TO '/artifacts/trades.csv' (FORMAT CSV, HEADER true);

COPY (
  SELECT
    asset,
    date_trunc('month', session_date) AS month,
    count(*) AS trades,
    sum(gross_pnl_position) AS gross_pnl_position,
    sum(gross_pnl_per_contract) / nullif(sum(contracts), 0) AS gross_pnl_per_contract,
    avg(gross_pnl_per_contract) AS mean_trade_pnl_per_contract,
    median(gross_pnl_per_contract) AS median_trade_pnl_per_contract,
    avg(CASE WHEN gross_pnl_per_contract > 0 THEN 1.0 ELSE 0.0 END) AS win_rate,
    false AS holdout_accessed,
    false AS costs_applied,
    false AS slippage_applied
  FROM trades
  GROUP BY asset, date_trunc('month', session_date)
  ORDER BY month
) TO '/artifacts/monthly_metrics.csv' (FORMAT CSV, HEADER true);

COPY (
  SELECT
    (SELECT executor_id FROM config) AS executor_id,
    (SELECT version FROM config) AS executor_version,
    (SELECT asset FROM config) AS asset,
    (SELECT phase FROM config) AS phase,
    count(*) AS trades,
    sum(gross_pnl_per_contract) AS gross_pnl_per_contract_total,
    avg(gross_pnl_per_contract) AS mean_trade_gross_pnl_per_contract,
    count(DISTINCT session_date) AS trading_days,
    min(session_date) AS first_session,
    max(session_date) AS last_session,
    false AS holdout_accessed,
    false AS costs_applied,
    false AS slippage_applied,
    'gross-only deterministic backtest; one position per strategy/asset/session; no orders' AS operational_scope
  FROM trades
) TO '/artifacts/run_summary.csv' (FORMAT CSV, HEADER true);
