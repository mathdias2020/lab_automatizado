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

O painel inicial está em `panel/`. Ele oferece a visão de execuções e o comando de enfileirar `quality_benchmark`, mas ainda não deve ser publicado como aplicação pública:

- o `service_role` só é lido em rotas server-side;
- em produção, a API exige `PANEL_INTERNAL_TOKEN` até configurarmos Supabase Auth;
- o Vercel só deve ser vinculado depois que a autenticação e as variáveis server-side estiverem configuradas;
- a interface não deve permitir `research` arbitrário antes de existir um executor aprovado para esse tipo.
