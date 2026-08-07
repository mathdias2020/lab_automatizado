# Executor mínimo do Laboratório Automatizado

Este componente executa apenas verificações reproduzíveis de qualidade, cobertura e leitura dos Parquets normalizados. Ele não descobre estratégias, não acessa o Supabase e não envia ordens.

## Contrato operacional

- entrada montada em `/data` somente leitura;
- artefatos gravados em `/artifacts`;
- rede desabilitada;
- container somente leitura, sem Docker socket;
- limite de 1,5 vCPU, 2 GB de RAM e 128 PIDs;
- imagem DuckDB fixada por digest;
- execução descartável com `docker compose run --rm`.

## Execução na VPS

```bash
cd /srv/labs/projects/lab_automatizado/executor
mkdir -p /srv/labs/projects/lab_automatizado/runs/quality_expanded_v1
DATA_ROOT=/srv/labs/datasets/canonical/expanded_sample_v1/normalized \
RUN_ROOT=/srv/labs/projects/lab_automatizado/runs/quality_expanded_v1 \
TMP_ROOT=/srv/labs/projects/lab_automatizado/runs/quality_expanded_v1/tmp sudo -n -E docker compose -f compose.yaml run --rm quality-benchmark
```

`TMP_ROOT` deve apontar para uma pasta temporária exclusiva do run, fora do dataset e dos artefatos finais. Ela pode ser removida depois da validação.

O arquivo `benchmark-expanded-v1.json` é a configuração declarativa do run. O resultado deve ser conferido contra o manifesto `expanded_sample_v1` antes de qualquer experimento de estratégia.

## Backtest de estrategia em desenvolvimento

O runner de estrategia usa duas etapas. Primeiro, `strategy-prepare` calcula os
thresholds no periodo de treino completo. Depois, `strategy-backtest` roda um
mes de cada vez, incluindo margem suficiente para o time stop, e consolida
`trades.csv`, `monthly_metrics.csv` e `run_summary.csv` no diretorio principal
da run. Assim o caminho de ticks de todos os anos nao fica materializado ao
mesmo tempo.

Os Parquets continuam somente leitura, custos e slippage permanecem desligados
no desenvolvimento e o holdout continua bloqueado.
