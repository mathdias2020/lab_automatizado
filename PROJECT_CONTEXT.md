# Laboratório de Estratégias IA — Contexto do Projeto

**Status:** Fase 4 — motor de propostas do sistema Hermes
**Data de referência:** 2026-08-06
**Nome do laboratório:** Laboratório Automatizado  
**ID técnico:** lab_automatizado  
**Fonte de verdade:** este arquivo, [DECISIONS.md](DECISIONS.md), [STATUS.md](STATUS.md), [docs/PORTFOLIO_OBJECTIVE_V1.md](docs/PORTFOLIO_OBJECTIVE_V1.md), [docs/HERMES_RESEARCH_SYSTEM_V1.md](docs/HERMES_RESEARCH_SYSTEM_V1.md) e [docs/VALIDATION_PROTOCOL.md](docs/VALIDATION_PROTOCOL.md).

## Objetivo

Construir um laboratório autônomo para descobrir, testar e comparar estratégias intraday para WDO e WIN, preservando rigor estatístico, rastreabilidade e controle humano na promoção de estratégias.

O laboratório deve responder se uma hipótese possui evidência suficiente para ser considerada candidata à operação futura. Ele não deve presumir que uma estratégia é boa apenas porque apresentou um backtest rentável.

## Fase atual

Esta fase é exclusivamente de pesquisa histórica sobre os dados Parquet disponíveis.

Inclui:

- inventário e validação dos datasets;
- execução reproduzível de experimentos;
- descoberta de hipóteses por agentes;
- validação fora da amostra;
- custos, slippage e análise de robustez;
- relatórios e registro de decisões.

Não inclui:

- ProfitDLL;
- VPS Windows;
- replay de mercado;
- simulador operacional;
- envio de ordens;
- operação com dinheiro real;
- promoção automática de estratégia;
- autoalteração de estratégia em produção.

## Decisões já estabelecidas

- O objetivo financeiro não é mais definido por um capital de referência.
- Cada ativo terá um portfólio independente de estratégias intraday.
- O alvo central é uma média de R$ 1.000 por contrato operado por mês em cada ativo.
- A banda mensal inicial de monitoramento é R$ 700–R$ 1.300 por contrato; ela é diagnóstica, não um filtro mensal rígido.
- O resultado bruto será preservado como métrica de pesquisa, e o resultado líquido após custos, slippage e execução será obrigatório para promoção operacional.
- Operação exclusivamente intraday.
- Objetivo de atividade: média de cinco operações por semana somando WDO e WIN; não é uma quota que force entradas ruins.
- WDO e WIN serão validados separadamente.
- O resultado final será um portfólio de estratégias independentes.
- O laboratório pode gerar hipóteses, código e experimentos de forma autônoma dentro de um espaço de busca controlado.
- A promoção de uma estratégia exige aprovação humana.
- O Hermes poderá explorar dados de desenvolvimento, propor e criticar hipóteses e iniciar pesquisas permitidas pelo control plane; não terá acesso iterativo ao holdout nem poderá promover estratégias.
- A descoberta prioriza as variáveis disponíveis nos cinco anos de histórico confiável.
- Os trinta dias úteis com dados mais ricos de microestrutura serão usados como fonte secundária de hipóteses e testes específicos, não como substituto da validação de longo prazo.
- A série histórica preferida é contínua e ajustada.
- O holdout mais recente, aproximadamente doze meses, permanece cego durante a descoberta e a validação.
- Ausência de cobertura é registrada como `NULL` ou `SEM_COBERTURA_ESTRUTURAL`, nunca como zero ou veredito fabricado.

## Base de contratos para a fase futura

A referência de dimensionamento é definida por operação, sem vínculo com um capital fixo:

| Ativo | Base por operação |
|---|---:|
| WDO | 10 |
| WIN | 50 |

Operações simultâneas mantêm dimensionamento independente. A exposição agregada será observada por uma camada global de risco, mas não altera silenciosamente a quantidade definida para cada operação.

Essa referência não é um filtro de pesquisa nem substitui a análise de liquidez, custos, slippage, drawdown, correlação e exposição agregada. O PnL do portfólio será normalizado por contratos efetivamente executados.

## Arquitetura pretendida

### Agora

```text
Dados Parquet
    -> executor reproduzível de experimentos
    -> métricas e artefatos versionados
    -> relatório auditável
```

### Depois do primeiro experimento reproduzível

```text
Supabase gerenciado: metadados, estados, auditoria e controle
Hostinger Linux: agentes, jobs, Parquet e processamento
VPS Windows separada: ProfitDLL e execução futura
```

### Sistema de pesquisa com Hermes

```text
Hermes explora dados de desenvolvimento em leitura
    -> formaliza uma hipótese versionada
    -> revisão adversarial
    -> executor determinístico
    -> métricas brutas/líquidas e artefatos
    -> Hermes escolhe a próxima pesquisa
```

O contrato detalhado está em `docs/HERMES_RESEARCH_SYSTEM_V1.md`. O Hermes é
autônomo na descoberta e na análise, mas o holdout, o executor de avaliação e
a promoção permanecem independentes.

O Supabase não será usado inicialmente como depósito de todos os ticks. Os dados pesados permanecem em Parquet/DuckDB ou armazenamento de objetos; o banco registra manifestos, hashes, resultados e estados.

O control plane deste laboratório foi criado no schema privado `lab_automatizado`. As funções RPC server-side prefixadas com `lab_automatizado_` controlam a fila sem expor as tabelas ao navegador. O worker Linux é separado do executor DuckDB e não recebe Docker socket.

## Estado atual da VPS

A VPS Hostinger 1556867 está configurada como worker Linux para os laboratórios:

- Ubuntu 24.04.4 LTS;
- KVM 2, com 2 vCPU, aproximadamente 8 GB de RAM e aproximadamente 96 GB de disco utilizável;
- Docker e Docker Compose instalados;
- usuário administrativo labadmin criado com a chave SSH do projeto;
- UFW ativo, com entrada liberada somente para SSH;
- swap de 2 GB configurado;
- worker systemd do Laboratório Automatizado ativo e habilitado no boot; os containers do executor continuam sendo efêmeros;
- O dataset completo ainda não foi transferido; somente a amostra de validação foi copiada.
- A camada derivada `normalized_sample_v1` foi criada e validada na VPS em `/srv/labs/datasets/canonical/normalized_sample_v1`.

Estrutura inicial no servidor:

    /srv/labs/
    ├── datasets/
    │   ├── canonical/
    │   ├── manifests/
    │   └── holdout/
    └── projects/
        ├── lab-a/
        └── lab-b/

/srv/labs/datasets é uma camada de dados global e deverá ser tratada como somente leitura pelos containers. Cada laboratório terá seus próprios códigos, configurações, artefatos, logs e banco/metadados.

## Inventário atual dos dados

Origem local:

    C:\Users\Windows 11\Desktop\Projeto-Fluxo-WDO-WIN\dados_parquet

O inventário de 2026-08-05 encontrou:

- 341 arquivos Parquet;
- aproximadamente 76,59 GB;
- WDOFUT: 170 arquivos e aproximadamente 1,69 bilhão de linhas;
- WINFUT: 171 arquivos e aproximadamente 8,21 bilhões de linhas;
- cobertura de 2012-04 a 2026-06;
- ausência da partição WDOFUT 2017-06;
- dois schemas diferentes nos dois ativos;
- schema recente nos meses 2026-04, 2026-05 e 2026-06, com ts, quantity, volume, IDs numéricos de agentes e is_edit;
- schema histórico nos demais meses, com date, time, qty, vol, nomes textuais de agentes e aft.

O dataset completo não será transferido antes de aplicarmos o contrato a uma fração maior, medirmos o custo da camada derivada e fecharmos o snapshot de pesquisa.

A amostra transferida em 2026-08-05 contém 100.000 negócios de cada combinação de ativo e schema:

- WDOFUT legacy de 2026-03;
- WDOFUT recente de 2026-04;
- WINFUT legacy de 2026-03;
- WINFUT recente de 2026-04.

Ela está em /srv/labs/datasets/canonical/transfer_sample_v1 na VPS, com arquivos somente leitura. Os quatro SHA-256 foram conferidos entre a origem e o destino. O manifesto está em /srv/labs/datasets/manifests/transfer-sample-v1-manifest.json.

A camada canônica da amostra está em /srv/labs/datasets/canonical/normalized_sample_v1, com manifesto local em `outputs/normalized-sample-v1-manifest.json` e contrato em `docs/CANONICAL_DATA_CONTRACT.md`. Ela é derivada e não substitui os Parquets originais.

Uma amostra ampliada de 16 arquivos, cobrindo os meses 2012-04, 2016-01, 2020-01, 2024-01 e 2026-03 a 2026-06, está em `/srv/labs/datasets/canonical/expanded_sample_v1`. Ela contém 697.179.363 negócios, foi normalizada em quatro partições e validada por arquivo. A materialização excedeu 15 minutos na KVM2; o executor deverá usar fila ou processamento por partição.

O executor mínimo está em `/srv/labs/projects/lab_automatizado/executor`, com o run `quality_expanded_v1` em `/srv/labs/projects/lab_automatizado/runs/quality_expanded_v1`. O primeiro run de qualidade terminou em 79,96 segundos, gerou artefatos somente leitura e não acessou Supabase nem execução de ordens.

## Control plane e painel

O schema privado `lab_automatizado` no Supabase abriga o estado de runs, commands, events, artifacts e workers. O worker da VPS usa `/etc/lab-automatizado/worker.env`; a chave privilegiada não entra no Git.

O painel Next.js está em `panel/` e usa Supabase Auth no navegador. As rotas server-side validam a sessão e chamam as RPCs com `SUPABASE_SERVICE_ROLE_KEY`. O deploy está no projeto Vercel `lab-automatizado-panel`, com produção em `https://lab-automatizado-panel.vercel.app/`. O acesso está restrito por Supabase Auth e `PANEL_ALLOWED_EMAILS`. O painel permite iniciar o quality benchmark e o estudo `absorption_event_study_v1` separadamente para WDO e WIN.

O monitoramento Hermes V1 também está publicado: a tela mostra o estado do
agente, modo, heartbeat e fila de hipóteses. A revisão humana pode marcar uma
hipótese como `approved_for_test`, mas não inicia execução e não promove
estratégia. O bootstrap e o motor de propostas estão ativos na VPS em
`/srv/labs/projects/lab_automatizado/hermes`; o motor não possui
`service_role`, holdout, Docker socket ou permissão para iniciar runs.

O primeiro estudo de pesquisa foi executado em 2026-08-06 sobre a amostra histórica parcial. Os resultados e limites estão em `docs/ABSORPTION_EVENT_STUDY_V1.md`; eles não autorizam promoção nem operação.

## Regra de atualização do contexto

Toda decisão que altere objetivo, escopo, dados, protocolo, risco ou arquitetura deve:

1. ser registrada em `DECISIONS.md`;
2. atualizar este arquivo se mudar o estado vigente;
3. atualizar `STATUS.md` se mudar a próxima ação;
4. incluir data, motivo e impacto.

Nenhum segredo, token, senha ou chave privada deve ser colocado neste repositório.
