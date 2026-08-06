# Objetivo de Portfólio por Ativo — V1

**Data:** 2026-08-06
**Status:** vigente como objetivo de pesquisa; banda inicial sujeita a calibração com dados completos
**Escopo:** Laboratório Automatizado, WDO e WIN separados

## 1. Objetivo

O laboratório não será avaliado por um capital de referência. O objetivo é
encontrar, para cada ativo, um portfólio de estratégias intraday independentes
que alcance, em média, **R$ 1.000 por contrato operado por mês**.

| Ativo | Base por operação | Referência mensal bruta na base |
|---|---:|---:|
| WDO | 10 contratos | R$ 10.000 |
| WIN | 50 contratos | R$ 50.000 |

Os valores da última coluna são apenas uma escala de referência. O resultado
real do portfólio será calculado com os contratos efetivamente executados,
incluindo operações simultâneas, sobreposição, recusas e capacidade de mercado.

WDO e WIN não se compensam. Um ativo não resgata o outro.

## 2. Bruto e unidade de medição

O alvo central é medido no retorno bruto. O executor desta fase não aplica custos
nem slippage, e deve registrar essas duas flags como `false` para impedir que um
resultado de pesquisa seja confundido com uma estimativa operacional:

```text
retorno_bruto_por_contrato_mes = PnL bruto / contratos executados
custos_aplicados = false
slippage_aplicado = false
```

O resultado bruto não autoriza promoção operacional. Custos, slippage, liquidez e
execução serão tratados em um gate posterior, com outro contrato versionado.

O denominador é a soma de `filled_quantity` no mês. A pesquisa não deve
confundir quantidade planejada com contratos efetivamente executados.

## 3. Banda mensal

A banda inicial de monitoramento é:

- centro: R$ 1.000 por contrato/mês;
- limite inferior suave: R$ 700;
- limite superior diagnóstico: R$ 1.300.
- limite de drawdown diagnóstico: R$ 5.000 por contrato.

A banda não é um corredor que todos os meses precisam respeitar.

- Um mês abaixo de R$ 700 gera `REVIEW_MENSAL`, não invalidação.
- Um mês acima de R$ 1.300 gera `REVIEW_DE_ATRIBUICAO`, para verificar se o resultado é real, concentrado ou causado por erro de dados.
- Drawdown acima de R$ 5.000 por contrato rejeita a configuração para o gate corrente, sem transformar um mês isolado abaixo da banda em invalidação automática.
- A invalidação exige evidência acumulada: deterioração em janelas móveis, perda de estabilidade, quebra estrutural, resultado líquido negativo persistente ou falha em controles.
- A média deve ser avaliada sobre uma amostra temporal suficiente, preferencialmente pelo menos 12 meses válidos de avaliação fora da amostra, e não por um único mês.

O veredito deve combinar média, mediana, distribuição mensal, concentração do
PnL, drawdown, sequência de perdas e estabilidade por regime. A média de R$
1.000 não pode ser produzida por um único mês excepcional.

## 4. Critérios mínimos de portfólio

Cada ativo deverá reportar, separadamente:

- PnL bruto por mês e por contrato;
- média, mediana e intervalo de incerteza;
- meses positivos e meses abaixo da banda;
- janelas móveis de 3 e 6 meses;
- drawdown e sequência de meses fracos;
- concentração do resultado por estratégia, dia, horário e regime;
- correlação e sobreposição entre estratégias;
- contratos simultâneos e exposição máxima;
- flags de custos/slippage desativados e limites conhecidos do estudo;
- comparação com cada estratégia isolada.

Uma estratégia não entra no portfólio apenas por ter maior PnL. Ela precisa
contribuir com retorno bruto estável ou reduzir risco, instabilidade ou concentração.

## 5. Políticas de saída pesquisáveis

Entradas e saídas serão avaliadas como componentes versionados. O Hermes pode
propor e comparar políticas dentro de uma grade previamente registrada:

- stop fixo e alvo fixo;
- break-even por ativação, offset e prazo;
- trailing stop por distância, passo e ativação;
- saída parcial por fração e nível;
- time stop;
- encerramento obrigatório da sessão;
- saída por invalidação do contexto da hipótese.

Cada política deve preservar a sequência tick a tick, o preço possível e a
quantidade restante. Não será aceito um backtest que use o
melhor preço do candle sem provar que a ordem poderia ter sido executada.

MAE, MFE, tempo em posição, motivo de saída e contratos restantes serão
registrados para explicar se o ganho veio da entrada ou apenas de uma saída
otimizada retrospectivamente.

## 6. Próximo gate

Antes de avaliar R$ 1.000 por contrato em escala completa, o laboratório deve:

1. fechar o snapshot histórico de desenvolvimento sem holdout;
2. executar hipóteses de entrada com políticas de saída versionadas em bruto;
3. formar portfólios por ativo e medir contribuição marginal;
4. validar 12 meses ou mais de avaliação temporal conforme o split congelado;
5. abrir o holdout somente após configuração congelada e aprovação do gate;
6. só então estimar custos, slippage, liquidez e capacidade em contrato separado.

Este objetivo não autoriza operação real, ProfitDLL ou envio de ordens.
