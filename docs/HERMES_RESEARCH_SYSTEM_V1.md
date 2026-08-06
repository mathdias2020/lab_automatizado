# Hermes Research System — V1

**Data:** 2026-08-06
**Status:** motor de propostas V1 ativo; revisão humana pendente
**Função:** descoberta adaptativa, crítica e priorização de pesquisas

## 1. Papel do Hermes

O Hermes será o pesquisador adaptativo do Laboratório Automatizado. Ele deve
usar os dados para construir entendimento próprio do mercado, explicar falhas,
propor novas hipóteses e escolher quais testes merecem o próximo orçamento de
pesquisa.

Ele não será o avaliador final da própria hipótese. A avaliação financeira e
estatística continuará em executores determinísticos, com configurações,
hashes, custos e divisões temporais registrados.

## 2. Acesso a dados

O Hermes terá:

- leitura dos Parquets brutos e da camada canônica de desenvolvimento;
- consultas por negócio, minuto, sessão, horário, agressão, volume e preço;
- acesso aos logs, artefatos e resultados de estudos anteriores;
- permissão para gerar tabelas derivadas e gráficos em seu workspace;
- memória das hipóteses aprovadas, rejeitadas e inconclusivas.

O Hermes não terá:

- escrita nos Parquets originais;
- acesso iterativo ao holdout;
- acesso a `service_role`, Docker socket, sudo, ProfitDLL ou corretora;
- permissão para alterar o executor, custo, split, métrica ou gate;
- permissão para enviar ordens ou promover estratégia.

O acesso será amplo na descoberta, mas o holdout ficará atrás de um avaliador
separado que só devolve o resultado agregado após a hipótese estar congelada.

## 3. Ciclo de pesquisa

```text
1. Explorar dados de desenvolvimento
2. Descrever observação e mecanismo esperado
3. Formalizar hipótese em JSON
4. Enumerar falsificadores e controles
5. Revisar adversarialmente
6. Executar estudo determinístico
7. Avaliar bruto, líquido, robustez e capacidade
8. Registrar resultado completo
9. Escolher a próxima pesquisa
```

O Hermes pode descobrir uma hipótese olhando para os dados. Isso é permitido e
é desejável. A separação entre descoberta e confirmação impede que a mesma
observação seja tratada como prova independente.

## 4. Contrato mínimo de hipótese

Cada proposta deve conter:

```json
{
  "hypothesis_id": "H-...",
  "asset": "WDOFUT|WINFUT",
  "family": "entry|exit|portfolio",
  "observation": "o que foi observado",
  "mechanism": "por que deveria existir",
  "entry_definition": "regra mensurável",
  "exit_policy_id": "fixed|break_even|trailing|partial|time_stop|...",
  "horizons": [1, 5, 15],
  "primary_metric": "net_pnl_per_contract_month",
  "baselines": [],
  "falsifiers": [],
  "data_scope": "development-only",
  "max_variants": 0,
  "parent_hypothesis_id": null
}
```

O JSON é compilado pelo control plane. Texto livre nunca vira executor
diretamente.

## 5. Revisão adversarial

Antes do teste, o Hermes deve responder:

- que observação poderia ser apenas acaso;
- quais decisões foram tomadas depois de olhar os dados;
- quais regimes podem quebrar o efeito;
- qual baseline poderia explicar o resultado;
- qual placebo ou permutação deve falhar;
- qual resultado faria o agente abandonar a hipótese.

Quando possível, a crítica será executada em uma sessão/contexto separado. A
revisão adversarial não substitui o nulo estatístico.

### 5.1 Conversa humana com o Hermes

O painel mantém uma thread append-only por hipótese. O humano pode enviar uma
objeção, pergunta ou pedido de esclarecimento; a bridge privada reivindica essa
mensagem e a entrega ao engine sem expor `service_role` ao engine. O Hermes
responde com `response`, `revision_proposal` ou `abandonment`, sempre registrando
o payload de incertezas e testes sugeridos.

O botão **Aprovar para teste** é separado de **Enviar ao Hermes**. Aprovar apenas
autoriza uma futura especificação congelada a entrar no executor determinístico;
não executa, não promove e não transforma a resposta textual em evidência.

## 6. Políticas de saída

Break-even, trailing stop, saída parcial, time stop e encerramento de sessão
serão uma biblioteca de políticas versionadas. O Hermes pode sugerir variantes,
mas cada família terá uma grade e orçamento pré-registrados.

O avaliador deve preservar a trajetória intraday e registrar MAE, MFE, tempo em
posição, motivo de saída, quantidade restante, custos e slippage. O Hermes não
pode escolher uma saída depois de ver o resultado e apagar as demais tentativas.

## 7. Memória e fonte de verdade

Existem duas camadas:

1. memória operacional do Hermes, útil para contexto e procedimentos;
2. registry científico no Supabase/Git, fonte de verdade para hipóteses,
   configurações, consultas, tentativas, artefatos e vereditos.

Skills criadas automaticamente pelo Hermes entram em staging. Elas não podem
alterar o protocolo científico ou o executor sem revisão.

## 8. Orçamento e objetivo do agente

O Hermes não otimiza o maior backtest. A prioridade de uma hipótese considera:

- valor esperado líquido fora da amostra;
- estabilidade por tempo, regime e ativo;
- simplicidade e interpretabilidade;
- contribuição marginal para o portfólio;
- capacidade na base de 10 WDO e 50 WIN;
- custo computacional e número de tentativas;
- penalidade por sensibilidade de parâmetros e concentração.

O control plane limitará variantes por família, runs simultâneos e custo de
processamento. Na KVM2, o padrão inicial será fila serializada.

## 9. Promoção

O Hermes pode gerar `CANDIDATE_FOR_REVIEW`, nunca `PROMOTED`.

Uma promoção exige, no mínimo:

- resultado bruto e líquido;
- amostra temporal suficiente;
- custos e slippage aplicados;
- estabilidade mensal e por regime;
- controle de multiplicidade;
- ausência de look-ahead;
- capacidade e exposição verificadas;
- comparação com o melhor componente isolado;
- aprovação humana explícita.

## 10. Como medir se o Hermes ajudou

O sistema registrará:

- tempo entre uma falha e uma nova hipótese testável;
- taxa de hipóteses que sobrevivem fora da amostra;
- taxa de falsos padrões;
- número de tentativas por candidato válido;
- diversidade de famílias pesquisadas;
- contribuição marginal para o portfólio;
- custo de LLM e de processamento.

O Hermes será considerado útil se aumentar a qualidade e a velocidade da
descoberta, não apenas o número de backtests executados.

## 11. Monitoramento V1 no painel

O painel publicado acompanha o registro do Hermes sem conceder execução
autônoma:

- `agents` registra estado, modo, versão, capacidades e heartbeat;
- `hypotheses` registra propostas, origem, mecanismo, payload e revisão humana;
- `agent_events` fica reservado para o diário operacional do agente;
- `hypothesis_messages` registra a conversa humana/Hermes e seu estado técnico de entrega;
- o estado inicial é `offline`/`disabled`;
- uma aprovação no painel apenas muda a hipótese para `approved_for_test`; ela
  não inicia um run nem promove uma estratégia;
- as APIs usam sessão do Supabase Auth e chamam RPCs server-side com
  `service_role`; as tabelas permanecem privadas e sem grants para o navegador.

O bootstrap observacional e o motor de propostas estão instalados em
`/srv/labs/projects/lab_automatizado/hermes`. O runtime roda sem rede, sem
`service_role` e sem Docker socket. O `hermes-engine.service` recebe somente a
credencial do modelo, lê o contexto de desenvolvimento e grava propostas JSON;
uma bridge separada registra heartbeats e hipóteses allowlisted no Supabase.
O primeiro ciclo gerou uma proposta para WDOFUT e uma para WINFUT. Qualquer
execução continua limitada ao control plane e depende de aprovação humana.
