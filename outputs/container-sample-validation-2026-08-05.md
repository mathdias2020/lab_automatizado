# Validação da amostra em container DuckDB

**Data:** 2026-08-05  
**Projeto:** Laboratório Automatizado (`lab_automatizado`)  
**VPS:** Hostinger KVM2 — Ubuntu 24.04.4  
**Amostra:** `/srv/labs/datasets/canonical/transfer_sample_v1`

## Execução

- Imagem: `duckdb/duckdb:latest` (DuckDB `v1.5.5`).
- Container: temporário, com `--rm`.
- Dados: montados em `/data:ro`.
- Rede: desabilitada (`--network none`).
- Limites: 1,5 CPU, 2 GB de memória e 128 PIDs.
- Banco DuckDB: somente em memória (`:memory:`); nenhum arquivo de banco foi persistido.

## Resultado

| Arquivo | Linhas | Schema | Evento inicial | Evento final |
|---|---:|---|---|---|
| `wdofut/legacy_2026-03.parquet` | 100.000 | legado | 2026-03-02 09:29:58 | 2026-03-02 17:11:24 |
| `wdofut/recent_2026-04.parquet` | 100.000 | recente | 2026-04-01 09:00:48.300 | 2026-04-01 09:42:03.232 |
| `winfut/legacy_2026-03.parquet` | 100.000 | legado | 2026-03-02 09:01:07 | 2026-03-02 09:47:00 |
| `winfut/recent_2026-04.parquet` | 100.000 | recente | 2026-04-01 09:02:52.476 | 2026-04-01 09:04:44.244 |

Totais: **4 arquivos**, **400.000 linhas**, sendo **200.000 do schema legado** e **200.000 do schema recente**.

## Conclusão

A VPS consegue ler a amostra compartilhada por DuckDB, reconhecer as duas variantes de schema e produzir um `event_ts` comum sem modificar os Parquets. O container foi removido ao terminar e não ficou nenhum container DuckDB criado.

Esta validação não autoriza ainda a transferência dos aproximadamente 76,59 GB nem define a camada normalizada. A próxima decisão é testar e documentar o contrato canônico derivado, preservando os Parquets originais como fonte imutável.
