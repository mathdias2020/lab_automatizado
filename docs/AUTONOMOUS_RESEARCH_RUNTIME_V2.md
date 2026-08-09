# Runtime autonomo de pesquisa - V2

## Objetivo

O runtime V2 mantem o laboratorio rodando de forma continua sem confundir
triagem com validacao final. Ele pesquisa WDOFUT e WINFUT, registra todos os
artefatos e deixa a promocao de portfolio sob controle humano.

## Dois estagios

1. Triagem: cada variante usa somente dados de desenvolvimento de 2018-01-01
   (inclusivo) a 2023-01-01 (exclusivo). Cada hipotese executavel gera ate 96
   variantes. A triagem serve para descartar rapidamente parametrizacoes fracas.
2. Desenvolvimento completo: quando todas as variantes de triagem terminam,
   as oito melhores por hipotese sao promovidas automaticamente para uma fila
   de desenvolvimento. Essa fila usa o periodo completo disponivel de
   desenvolvimento, sem acessar o holdout.

## Regras operacionais

- O worker continua sendo o unico processo autorizado a executar o backtest.
- O orquestrador prepara filas, promove resultados de triagem e agenda a proxima
  variante; ele nao calcula evidencia nem promove estrategia para portfolio.
- A fila alterna WDOFUT e WINFUT sempre que houver trabalho elegivel dos dois
  ativos, evitando que um ativo monopolize a unica vaga da KVM2.
- O limite efetivo de cada run e 7.200 segundos e vem do systemd e do Supabase.
- Custos e slippage continuam desativados, conforme o protocolo deste projeto.
- Runs antigos da fila V1 foram preservados como historico e marcados como
  superseded/cancelled_reconfiguration ou infra_timeout; eles nao voltam para
  execucao.

## Falhas e observabilidade

Cada falha recebe uma categoria: `infra_timeout`, `infra_artifact`,
`infra_runner`, `infra_permission`, `validation`, `cancelled_reconfiguration`,
`superseded` ou `unknown`. O endpoint do painel tambem consulta a saude do
laboratorio, incluindo fila por estagio, falhas das ultimas 24 horas, worker e
run ativo.

## Promocao

Uma hipotese so pode entrar na fila quando possui contrato Hermes executavel e
`execution_spec` estruturado. Um `strategy_candidate` continua sendo evidencia
de desenvolvimento. Holdout, slots de portfolio e qualquer operacao real
continuam bloqueados e exigem decisao humana.
