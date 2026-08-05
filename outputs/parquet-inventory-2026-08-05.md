# Inventário dos Parquets

- Gerado em UTC: 2026-08-05T14:29:29Z
- Origem: C:\Users\Windows 11\Desktop\Projeto-Fluxo-WDO-WIN\dados_parquet
- Arquivos: 341
- Tamanho total: 71.33 GB

## Resumo por ativo

| Ativo | Arquivos | Linhas | Tamanho | Período | Meses ausentes | Schemas |
|---|---:|---:|---:|---|---|---|
| wdofut | 170 | 1,687,559,300 | 12.30 GB | 2012-04 a 2026-06 | 2017-06 | legacy_date_time_named_agents: 167, event_ts_numeric_agents: 3 |
| winfut | 171 | 8,213,130,999 | 59.03 GB | 2012-04 a 2026-06 | nenhum | legacy_date_time_named_agents: 168, event_ts_numeric_agents: 3 |

## Variantes de schema

### legacy_date_time_named_agents

Campos históricos com date, time, qty, vol e nomes textuais de agentes.

### event_ts_numeric_agents

Campos recentes com ts, quantity, volume, IDs numéricos de agentes e is_edit.

## Arquivos com schema recente

### wdofut — event_ts_numeric_agents
- ticker=wdofut/ano=2026/mes=04/data_0.parquet
- ticker=wdofut/ano=2026/mes=05/data_0.parquet
- ticker=wdofut/ano=2026/mes=06/data_0.parquet

### winfut — event_ts_numeric_agents
- ticker=winfut/ano=2026/mes=04/data_0.parquet
- ticker=winfut/ano=2026/mes=05/data_0.parquet
- ticker=winfut/ano=2026/mes=06/data_0.parquet

## Alertas

- O WDOFUT não possui a partição 2017-06.
- WDOFUT e WINFUT mudam de schema entre março e abril de 2026.
- O dataset completo não deve ser transferido antes de decidirmos se a normalização ocorrerá na origem, na leitura ou em uma camada derivada.
- O tamanho bruto de aproximadamente 76,59 GB deixa pouca folga na KVM2 para DuckDBs, artefatos e temporários.

## Próxima decisão

Escolher a estratégia de compatibilização dos dois schemas e selecionar uma amostra pequena de cada ativo e variante para transferência e validação.
