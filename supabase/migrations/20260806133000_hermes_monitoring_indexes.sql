create index if not exists hypotheses_source_run_idx
  on lab_automatizado.hypotheses (source_run_id)
  where source_run_id is not null;
