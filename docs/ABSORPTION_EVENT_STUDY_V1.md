# Absorption event study v1

**Status:** pilot completed; no strategy promotion
**Date:** 2026-08-06
**Experiment:** `absorption_event_study_v1`

## Question

Does an extreme aggressive-flow minute followed by an unusually small
contemporaneous price move show a different forward markout from aggressive
flow without the absorption condition?

This is an event study, not a trading strategy. It does not calculate PnL,
contracts, costs, slippage, entries, exits or the five-trades-per-week target.

## Frozen definition

- Assets are run independently: `WDOFUT` and `WINFUT`.
- Only `AggressorBuyer` and `AggressorSeller` are included.
- `RLP`, `CrossTrade`, `Auction` and invalid trade types are excluded.
- The unit is one observed minute inside one session.
- Signed aggressive quantity is buyer quantity minus seller quantity.
- Extreme aggression is the 95th percentile of absolute signed quantity in
  the training sample.
- Absorption is extreme aggression plus contemporaneous absolute
  close-minus-open movement at or below the 25th percentile of the training
  sample.
- Forward markouts are measured at exactly 1, 5 and 15 minutes within the
  same session. Missing future minutes remain missing.
- Validation is compared with both extreme-aggression and all-directional
  aggression baselines.

## Data boundary

The pilot used only the historical months present in the expanded sample:

- training: `2012-04`, `2016-01`, `2020-01`;
- validation: `2024-01`;
- excluded: 2025+ and all 2026 files;
- holdout accessed: `false`.

The sample is not the complete five-year development snapshot. Therefore the
pilot cannot promote, reject definitively or calibrate a live strategy.

## Results

Mean markout in points, followed by mean markout in basis points:

| Asset | Horizon | Absorption events | Absorption | Extreme baseline | Positive rate |
|---|---:|---:|---:|---:|---:|
| WDO | 1m | 218 | +0.257 / +0.457 bps | -0.037 / -0.064 bps | 46.3% |
| WDO | 5m | 218 | +0.160 / +0.285 bps | -0.072 / -0.127 bps | 47.2% |
| WDO | 15m | 217 | +0.317 / +0.557 bps | -0.063 / -0.112 bps | 48.8% |
| WIN | 1m | 55 | +5.200 / +0.371 bps | -0.271 / -0.023 bps | 49.1% |
| WIN | 5m | 55 | +5.478 / +0.378 bps | +1.762 / +0.128 bps | 50.9% |
| WIN | 15m | 55 | -5.200 / -0.392 bps | +1.297 / +0.093 bps | 50.9% |

The WDO pilot is directionally interesting but small and concentrated in one
validation month. The WIN pilot is internally inconsistent across horizons.
Neither result is a candidate for promotion.

## Runs and evidence

- WDO run: `b27db3b4-c061-410b-bf3e-ab0024457a5c`
- WIN run: `4ceaa057-b0f8-4ece-ad03-893fe90e58f0`
- artifacts: `/srv/labs/projects/lab_automatizado/runs/control_plane/<run_id>/`
- artifact files include `config.json`, thresholds, daily results, summary and
  run summary; all hashes are recorded in `lab_automatizado.artifacts`.
- the first engineering attempt was rejected by DuckDB because a quantile
  parameter was not constant; it was not used as evidence and the corrected
  runs are the only scientific outputs above.

## Next gate

Do not add thresholds or horizons from this result. First materialize and
audit the complete non-holdout development snapshot, then rerun this same
frozen study with a pre-registered null/control procedure. Only after that
review should a new hypothesis or strategy simulation be considered.
