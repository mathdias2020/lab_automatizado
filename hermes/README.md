# Hermes runtime — bootstrap V1

Este diretório contém o bootstrap isolado do Hermes do Laboratório Automatizado.

O bootstrap deliberadamente não chama um modelo, não cria hipóteses e não
inicia pesquisas. Ele valida somente:

- acesso de leitura ao dataset de desenvolvimento;
- escrita no workspace próprio;
- emissão de heartbeat local;
- ponte privilegiada separada para registrar o estado no Supabase.

## Separação de privilégios

`runtime.py` roda como `labadmin`, sem `SUPABASE_SERVICE_ROLE_KEY`, sem acesso
ao Docker socket e sem rede. Ele grava um único arquivo atômico em `outbox/`.

`bridge.py` roda como `root`, lê somente heartbeats e propostas validadas e usa
a chave server-side já protegida em `/etc/lab-automatizado/worker.env` para
chamar as RPCs allowlisted `lab_automatizado_heartbeat_agent` e
`lab_automatizado_record_hypothesis`.

`engine.py` roda como `labadmin`, recebe somente a credencial do modelo em
`/etc/lab-automatizado/hermes.env`, lê o contexto científico e grava propostas
JSON. O serviço inicia em modo `proposal`, com uma proposta por ativo por hash
de contexto; não executa runs e não promove estratégias.

O estado enviado é sempre `observing`/`observation`. A integração de LLM,
propostas de hipóteses e enfileiramento de testes são etapas posteriores e
separadas.
