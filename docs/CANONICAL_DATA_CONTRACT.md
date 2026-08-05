# Contrato de dados canônico — v1

**Projeto:** Laboratório Automatizado (`lab_automatizado`)  
**Status:** contrato inicial validado somente na amostra  
**Artefato testado:** `normalized_sample_v1`

## Princípios

1. Os Parquets de origem permanecem imutáveis e são a fonte de verdade.
2. A camada canônica é derivada, versionada e acompanhada de manifesto e hashes.
3. WDOFUT e WINFUT continuam identificados separadamente pelo campo `asset`.
4. Campos ausentes em uma variante de schema permanecem `NULL`; não são preenchidos com zero ou com um significado inventado.
5. O contrato normaliza nomes e tipos, mas não interpreta agressão, player, lado ou sinal de trade sem uma regra de pesquisa explicitamente validada.

## Schema v1

| Campo | Tipo | Origem/regra | Observação |
|---|---|---|---|
| `event_ts` | `TIMESTAMP` | recente: `ts`; legado: `date + time` | Sem timezone armazenado; interpretado operacionalmente no horário de mercado de São Paulo. Nenhuma conversão foi aplicada. |
| `asset` | `VARCHAR` | primeiro diretório do arquivo de origem | `WDOFUT` ou `WINFUT`. |
| `ticker` | `VARCHAR` | recente: `ticker`; legado: fallback para `asset` | O fallback não afirma que o arquivo legado carregava um ticker explícito. |
| `trade_number` | `BIGINT` | `trade_number` | Tipo comum para as duas variantes. |
| `price` | `DOUBLE` | `price` | Preservado numericamente. |
| `quantity` | `BIGINT` | recente: `quantity`; legado: `qty` | Nome canônico. |
| `volume` | `DOUBLE` | recente: `volume`; legado: `vol` | Nome canônico. |
| `buy_agent_raw` | `VARCHAR` | `buy_agent` | IDs recentes são representados como texto para não misturar tipos nem inferir semântica. |
| `sell_agent_raw` | `VARCHAR` | `sell_agent` | Mesma regra de preservação. |
| `trade_type_raw` | `VARCHAR` | `trade_type` | Preservado como valor bruto; não convertido em lado/agressor. |
| `aft_raw` | `VARCHAR` | `aft` | `NULL` no schema recente, pois o campo não existe nele. |
| `is_edit` | `BOOLEAN` | `is_edit` | `NULL` no schema legado, pois o campo não existe nele. |
| `source_schema` | `VARCHAR` | presença de `ts` | `legacy` ou `recent`. |
| `source_file` | `VARCHAR` | caminho relativo do input | Proveniência do registro dentro do snapshot. |

## Artefato da amostra

O teste foi executado sobre quatro arquivos, com 100.000 negócios por arquivo:

- `wdofut/legacy_2026-03.parquet`;
- `wdofut/recent_2026-04.parquet`;
- `winfut/legacy_2026-03.parquet`;
- `winfut/recent_2026-04.parquet`.

Os arquivos derivados estão na VPS em:

```text
/srv/labs/datasets/canonical/normalized_sample_v1/
```

Eles foram gravados com compressão ZSTD, marcados como somente leitura (`0444`) e validados contra a origem por quantidade de linhas e intervalo temporal por arquivo.

## Limites do contrato

- A amostra ainda não representa o dataset completo.
- A normalização não resolve a ausência da partição WDOFUT 2017-06.
- A normalização não valida timezone contra uma fonte externa.
- A normalização não cria barras, fluxo assinado, agressão, players, sinais ou labels.
- Qualquer transformação sem cobertura suficiente deve usar `NULL` ou `SEM_COBERTURA_ESTRUTURAL` no estágio apropriado.
- A camada canônica ainda não é autorização para backtest de promoção; antes disso, o mesmo contrato precisa ser aplicado e auditado no snapshot completo escolhido.
