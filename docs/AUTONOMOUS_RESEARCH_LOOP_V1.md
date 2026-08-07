# Ciclo autônomo de pesquisa — V1

## O que o botão play faz

O painel altera `lab_automatizado.lab_control.enabled` para `true`. Um serviço
independente na VPS consulta esse estado, prepara as variantes permitidas das
hipóteses executáveis e coloca no máximo um backtest bruto por vez na fila.

O worker continua sendo o único processo que executa DuckDB. O orquestrador não
monta Docker socket, não altera Parquets e não promove estratégias.

## Ciclo contínuo

1. Hermes lê contexto e dados de desenvolvimento e registra propostas no
   Supabase.
2. O orquestrador encontra propostas executáveis e cria uma grade persistente
   de até 500 variantes, distribuída em até 5 gerações.
3. A fila registra cada variante antes da execução. Se a VPS reiniciar, o
   próximo ciclo retoma a fila sem perder a posição.
4. O worker reivindica um comando, roda o backtest bruto com custos e slippage
   desativados e registra hashes dos artefatos.
5. O avaliador determinístico calcula retorno mensal por contrato, meses
   positivos, mediana, trades e drawdown mensal informativo.
6. Cada resultado concluído vira um `strategy_candidate` separado por ativo.
7. O resumo dos candidatos volta ao contexto do Hermes para orientar propostas
   futuras. O resumo não é evidência primária; os artefatos do run continuam
   sendo a fonte de auditoria.

## Gates que continuam humanos

- `development_candidate` não é estratégia validada;
- validação fora da amostra não é liberada automaticamente;
- slots de portfólio não são preenchidos automaticamente;
- nenhuma ordem, replay, simulador ou ProfitDLL é iniciado por este ciclo.

O painel mostra até cinco slots por ativo como objetivo de portfólio, mas o
preenchimento exige uma decisão humana com evidência de robustez e correlação.

## Parâmetros vigentes

- alvo: R$ 1.000 brutos por contrato/mês por ativo;
- banda diagnóstica: R$ 700–R$ 1.300;
- drawdown mensal por contrato: métrica informativa inicial de R$ 5.000;
- base futura: 10 contratos WDO e 50 contratos WIN;
- execução: uma variante por vez na KVM2;
- estado inicial do botão: pausado.

