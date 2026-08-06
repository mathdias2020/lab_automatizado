# Control plane do Laboratório Automatizado

**Estado:** contrato v0.1 criado e aplicado no Supabase em 2026-08-05.

O control plane registra comandos, execuções, eventos, artefatos e heartbeats. Ele não armazena ticks, Parquets ou dados de mercado brutos.

## Limites

- O schema `lab_automatizado` é privado e possui RLS habilitado.
- O acesso server-side ocorre por funções RPC prefixadas em `public`.
- As funções RPC exigem `service_role` e não devem ser chamadas pelo navegador.
- A chave `SUPABASE_SERVICE_ROLE_KEY` só pode existir no ambiente do worker ou em rotas server-side do painel.
- Nesta fase o único comando executável é `quality_benchmark`.
- Não existe qualquer caminho para ProfitDLL, simulador, replay ou envio de ordens.

## Objetos do schema privado

| Objeto | Finalidade |
|---|---|
| `runs` | Estado e configuração declarativa de uma execução |
| `commands` | Fila idempotente de comandos |
| `events` | Log append-only da execução |
| `artifacts` | Referências e hashes de resultados fora do Postgres |
| `workers` | Heartbeat, versão e capacidades do worker |

## RPC server-side

- `lab_automatizado_heartbeat_worker`
- `lab_automatizado_enqueue_run`
- `lab_automatizado_claim_next_command`
- `lab_automatizado_finish_command`
- `lab_automatizado_register_artifact`
- `lab_automatizado_list_runs`

O worker deve usar o RPC de claim para obter uma única tarefa por vez. A função usa `FOR UPDATE SKIP LOCKED`, impedindo que dois workers reivindiquem o mesmo comando.

## Fluxo pretendido

```text
painel server-side
    -> lab_automatizado_enqueue_run
    -> commands.status = queued
    -> worker Linux reivindica a fila
    -> wrapper root-owned chama apenas o executor DuckDB permitido
    -> worker finaliza run e registra evento
    -> painel consulta lab_automatizado_list_runs
```

O worker não acessa o Docker socket. O executor continua sendo um container descartável, sem rede, com Parquet somente leitura e limite próprio de CPU/memória.

## Ativação na VPS

O serviço foi ativado depois do teste controlado. A chave server-side está em `/etc/lab-automatizado/worker.env`, fora do Git, com proprietário `root:root` e permissão `600`.

O teste inicial executou um único `quality_benchmark` pelo worker automático. O run terminou com sucesso, o heartbeat foi confirmado e os três CSVs foram registrados com SHA-256. O serviço agora faz polling contínuo, mas só aceita `quality_benchmark`.

## Painel

O painel inicial está em `panel/` e foi publicado em [lab-automatizado-panel.vercel.app](https://lab-automatizado-panel.vercel.app/). Ele oferece a visão de execuções e os comandos de enfileirar `quality_benchmark` ou `absorption_event_study_v1` com WDO e WIN separados.

- o `service_role` só é lido em rotas server-side;
- o navegador usa `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` e envia o bearer token da sessão;
- a API server-side valida a sessão em `/auth/v1/user` antes de chamar as RPCs com `SUPABASE_SERVICE_ROLE_KEY`;
- as variáveis de produção e preview estão configuradas no projeto Vercel; a chave privilegiada está marcada como sensível;
- `PANEL_ALLOWED_EMAILS` está configurado para restringir este painel ao usuário autorizado deste laboratório;
- o SSO de Deployment Protection da Vercel foi desativado para não interpor uma segunda autenticação antes da sessão do Supabase; o acesso continua protegido por Supabase Auth e pela allowlist server-side;
- a interface não deve permitir `research` arbitrário antes de existir um executor aprovado para esse tipo.
- o worker aceita somente `absorption_event_study_v1` dentro de `research`; a configuração é transportada no payload e validada antes de iniciar o runner.

O primeiro usuário foi criado e o fluxo foi validado: login, leitura, enfileiramento pelo painel, execução no worker Docker e finalização `succeeded`. O painel ainda não cria contas, não envia convites e não deve receber a `service_role` no browser.

## Registry do Hermes — V1

O monitoramento do Hermes usa objetos separados dentro do mesmo schema privado
do laboratório:

| Objeto | Finalidade |
|---|---|
| `agents` | identidade, estado, modo, capacidades e heartbeat do agente |
| `hypotheses` | propostas formais e estado da revisão humana |
| `agent_events` | eventos e mensagens operacionais do agente |

As funções RPC específicas são `lab_automatizado_list_agents`,
`lab_automatizado_list_hypotheses`, `lab_automatizado_review_hypothesis`,
`lab_automatizado_heartbeat_agent` e `lab_automatizado_record_hypothesis`.
Todas exigem `service_role`; não há leitura direta das tabelas pelo navegador.

O bootstrap do Hermes está instalado em `/srv/labs/projects/lab_automatizado/hermes`
com dois serviços systemd:

- `hermes-runtime.service`: usuário `labadmin`, sem rede, sem `service_role`,
  sem Docker socket; lê somente a camada de desenvolvimento e grava um
  heartbeat atômico no workspace próprio;
- `hermes-bridge.service`: serviço separado e allowlisted, responsável por
  ler o heartbeat e chamar a RPC privilegiada no Supabase.

O painel mostra o Hermes como `observing`/`observation` enquanto o heartbeat é
recente. A revisão humana no painel não dispara execução:
`approved_for_test` é apenas uma autorização para uma etapa futura do control
plane.
