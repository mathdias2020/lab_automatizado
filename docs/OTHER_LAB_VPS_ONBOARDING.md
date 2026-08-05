# Onboarding do outro laboratório na VPS

Este documento é o contrato para o laboratório do outro chat executar na mesma Hostinger sem interferir no Laboratório Automatizado.

## Regra principal

O outro laboratório deve possuir um identificador técnico próprio. Até que ele seja confirmado, a pasta reservada é `/srv/labs/projects/lab-b`. Ele não deve escrever em `/srv/labs/projects/lab_automatizado`, nem alterar o schema `lab_automatizado`, nem reutilizar o worker `lab-automatizado-vps-linux`.

## Estrutura obrigatória

```text
/srv/labs/datasets/                         # global, somente leitura
/srv/labs/projects/lab-b/                  # código e configuração do outro laboratório
/srv/labs/projects/lab-b/runs/             # artefatos de execução
/srv/labs/projects/lab-b/logs/             # logs do próprio laboratório
/srv/labs/projects/lab-b/work/             # temporários e DuckDB do próprio laboratório
```

Os Parquets e camadas canônicas devem ser montados nos containers em modo `read_only`. Nenhum laboratório deve modificar a camada global de dados.

## O que o outro chat precisa entregar

Antes de iniciar uma execução na VPS, ele deve registrar no próprio repositório e devolver ao coordenador:

1. `project_id` e nome técnico do laboratório;
2. repositório Git e branch de execução;
3. schema Supabase exclusivo e seu MCP/projeto;
4. caminho do projeto na VPS;
5. `compose.yaml`, serviços e comando de entrada;
6. diretórios de leitura e escrita;
7. manifesto de dataset usado;
8. limites de CPU, memória, PIDs e rede;
9. nomes do projeto Docker Compose e do worker;
10. comando de healthcheck e comando de parada segura.

## Restrições de execução

- não usar `--privileged`;
- não montar `/var/run/docker.sock`;
- não abrir portas públicas sem aprovação;
- usar `network_mode: none` quando a pesquisa não precisar de rede;
- manter cada DuckDB, cache, log e artefato dentro da pasta do próprio laboratório;
- não copiar o dataset completo novamente sem medir espaço e tempo;
- não iniciar dois jobs pesados simultaneamente na KVM2 sem fila, porque a VPS tem 2 vCPU e aproximadamente 8 GB de RAM;
- não executar ProfitDLL, replay, simulador ou ordens nesta fase.

## Primeiro teste

O primeiro teste deve ser um job pequeno e reproduzível, com entrada conhecida, artefato com hash e relatório de sucesso/erro. O laboratório só poderá passar para descoberta autônoma depois de provar que consegue iniciar, acompanhar, interromper e repetir uma execução sem contaminar o outro projeto.
