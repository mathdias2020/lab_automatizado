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

`bridge.py` roda como `root`, lê somente o heartbeat validado e usa a chave
server-side já protegida em `/etc/lab-automatizado/worker.env` para chamar a
RPC allowlisted `lab_automatizado_heartbeat_agent`.

O estado enviado é sempre `observing`/`observation`. A integração de LLM,
propostas de hipóteses e enfileiramento de testes são etapas posteriores e
separadas.
