# Validação da camada canônica `normalized_sample_v1`

**Data:** 2026-08-05  
**Projeto:** Laboratório Automatizado (`lab_automatizado`)  
**Fonte:** `/srv/labs/datasets/canonical/transfer_sample_v1`  
**Destino:** `/srv/labs/datasets/canonical/normalized_sample_v1`

## Resultado

A camada derivada foi criada com o contrato [CANONICAL_DATA_CONTRACT.md](../docs/CANONICAL_DATA_CONTRACT.md), usando DuckDB `v1.5.5` em container temporário.

- 4 arquivos de saída;
- 400.000 linhas;
- 2 ativos: WDOFUT e WINFUT;
- 2 schemas de origem: `legacy` e `recent`;
- contagem de linhas igual à origem em cada arquivo;
- `min(event_ts)` e `max(event_ts)` iguais à origem em cada arquivo;
- zero nulos em `event_ts`, `ticker`, `trade_number`, `price`, `quantity`, `volume` e `source_file`;
- campos estruturalmente ausentes preservados como `NULL` (`aft_raw` no recente e `is_edit` no legado);
- arquivos de saída com permissão `0444`.

## Conclusão

O contrato canônico é tecnicamente executável e não alterou a fonte. A camada é adequada para o próximo teste de leitura e cálculo de features, mas ainda é uma amostra de transporte/compatibilidade. Ela não autoriza backtest de promoção nem a transferência integral dos aproximadamente 76,59 GB.
