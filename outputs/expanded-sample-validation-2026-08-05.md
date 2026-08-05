# Validação da amostra ampliada `expanded_sample_v1`

**Data:** 2026-08-05  
**Projeto:** Laboratório Automatizado (`lab_automatizado`)  
**VPS:** Hostinger KVM2, Ubuntu 24.04.4, 2 vCPU, 8 GB RAM

## Seleção

Foram selecionados oito meses por ativo para cobrir períodos antigos, intermediários e a transição de schema:

`2012-04`, `2016-01`, `2020-01`, `2024-01`, `2026-03`, `2026-04`, `2026-05` e `2026-06`.

O conjunto contém 16 Parquets, 4.969.732.663 bytes e 697.179.363 negócios.

## Resultado da normalização

- Origem: `/srv/labs/datasets/canonical/expanded_sample_v1/raw`.
- Derivado: `/srv/labs/datasets/canonical/expanded_sample_v1/normalized`.
- Saída: quatro partições por ativo e schema (`WDOFUT/WINFUT × legacy/recent`).
- Saída normalizada: 2.959.681.727 bytes, redução de 40,45% sobre a origem transferida.
- Linhas preservadas: 697.179.363.
- WDOFUT: 44.604.437 legacy e 34.495.669 recent.
- WINFUT: 303.622.373 legacy e 314.456.884 recent.

## Validação

Todos os 16 arquivos apresentaram:

- mesma quantidade de linhas na origem e na camada canônica;
- mesmo `min(event_ts)`;
- mesmo `max(event_ts)`;
- zero nulos nos campos essenciais (`event_ts`, `ticker`, `trade_number`, `price`, `quantity`, `volume` e `source_file`).

A validação DuckDB consumiu aproximadamente 91,21 segundos com limite de 1,5 vCPU, 2 GB de memória e rede desabilitada.

## Limitação operacional observada

A materialização inicial excedeu o timeout de 15 minutos do comando remoto. Os quatro arquivos derivados foram encontrados completos e passaram integralmente na validação, mas o resultado indica que a normalização de centenas de milhões de linhas não deve concorrer com jobs de pesquisa na KVM2. O executor futuro deverá usar fila, processamento por partição ou uma máquina de preparação dedicada.

## Conclusão

O contrato canônico funciona em meses antigos, intermediários e na transição `legacy → recent`. O conjunto ampliado é suficiente para decidir a forma do executor, mas ainda não justifica transferir os 76,59 GB completos nem iniciar agentes autônomos.
