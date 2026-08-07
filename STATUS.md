# Status do projeto

**Data:** 2026-08-07
**Fase:** 6 — ciclo autônomo de desenvolvimento e catálogo de candidatos
**Estado:** infraestrutura do ciclo publicada e pausada; pronta para iniciar pelo painel
**Última decisão:** o objetivo é R$ 1.000 bruto por contrato/mês por ativo; custos e slippage ficam desativados nesta fase.

## Concluído

- [x] Escopo inicial separado da execução com ProfitDLL.
- [x] Objetivo por contrato e portfólio por ativo registrado; o enquadramento por capital foi removido.
- [x] Documento do objetivo de portfólio criado em `docs/PORTFOLIO_OBJECTIVE_V1.md`.
- [x] Desenho do sistema Hermes criado em `docs/HERMES_RESEARCH_SYSTEM_V1.md`.
- [x] Objetivo de frequência tratado como média, não quota.
- [x] WDO e WIN definidos como validações separadas.
- [x] Holdout e divisão de dados definidos conceitualmente.
- [x] Base futura registrada por operação: WDO 10 e WIN 50 contratos.
- [x] Arquivos canônicos iniciais criados.
- [x] VPS Hostinger confirmada com Ubuntu 24.04.4 e Docker.
- [x] Acesso SSH por chave validado com labadmin.
- [x] Firewall do sistema ativado permitindo somente SSH.
- [x] Swap de 2 GB configurado.
- [x] Diretórios globais de datasets e projetos criados.
- [x] Arquitetura dos dois laboratórios registrada.
- [x] Inventário dos 341 Parquets concluído.
- [x] Tamanho, linhas, cobertura, partição ausente e variantes de schema registrados.
- [x] Relatório JSON e Markdown gerado em outputs.
- [x] Amostra com quatro combinações de ativo/schema transferida para a VPS.
- [x] SHA-256 da amostra conferido na origem e no destino.
- [x] Amostra remota marcada como somente leitura.

## Snapshot integral na VPS — 2026-08-06

- [x] 341 Parquets sincronizados para `/srv/labs/datasets/raw/full`.
- [x] WDOFUT: 170 arquivos; WINFUT: 171 arquivos.
- [x] Total remoto conferido: 76.586.834.396 bytes, igual à origem local.
- [x] Dataset bruto fechado como `root:root`, diretórios `0555` e arquivos `0444`.
- [x] Nenhuma camada normalizada integral foi criada; a KVM2 preserva espaço para os runs.

## Limites conscientes antes do play

- [x] O executor recebe uma hipótese executável congelada e testa entradas/saídas determinísticas em modo bruto.
- [x] O Hermes tem o snapshot `raw/full` montado em leitura e recebe seus fatos de disponibilidade no contexto.
- [ ] O profiler DuckDB que transforma microestrutura bruta em tabelas de descoberta ainda precisa ser ativado para o Hermes; o modelo não deve tratar texto ou contagem de arquivos como evidência de padrão.
- [x] O laço de busca de até 500 variantes e 5 gerações está persistido e será iniciado somente quando o usuário clicar em play.

## Validação do container mínimo — 2026-08-05

- [x] Imagem oficial `duckdb/duckdb` executada na VPS.
- [x] Amostra montada em `/data:ro`, sem rede, com limite de 1,5 CPU, 2 GB de memória e 128 PIDs.
- [x] Quatro arquivos lidos com `union_by_name=true`.
- [x] 400.000 linhas consolidadas: 200.000 do schema legado e 200.000 do schema recente.
- [x] Datas convertidas para `event_ts` sem perda na leitura: arquivos de março e abril de 2026 foram identificados corretamente.
- [x] Container temporário removido após a execução; nenhum container DuckDB permaneceu criado.
- [x] Nenhum Parquet original foi alterado.

## Camada canônica da amostra — 2026-08-05

- [x] Contrato v1 documentado em `docs/CANONICAL_DATA_CONTRACT.md`.
- [x] Quatro arquivos normalizados gerados em `/srv/labs/datasets/canonical/normalized_sample_v1`.
- [x] Linhas, intervalos temporais e nulidades essenciais conferidos contra a origem.
- [x] Saídas derivadas marcadas como somente leitura (`0444`).
- [x] Manifesto com hashes criado em `outputs/normalized-sample-v1-manifest.json`.

Relatório: `outputs/normalized-sample-validation-2026-08-05.md`.

## Amostra ampliada — 2026-08-05

- [x] 16 arquivos transferidos, cobrindo oito meses e a transição de schema.
- [x] SHA-256 de origem e destino conferido em todos os arquivos.
- [x] 697.179.363 linhas normalizadas em quatro partições por ativo e schema.
- [x] Contagens e intervalos temporais conferidos por arquivo.
- [x] Saída reduzida de 4,97 GB para 2,96 GB e marcada como somente leitura.
- [x] Container removido após a execução; nenhum job permanente iniciado.
- [!] A materialização excedeu o timeout operacional de 15 minutos; a validação posterior levou aproximadamente 91 segundos.

Relatório: `outputs/expanded-sample-validation-2026-08-05.md`.

## Primeiro executor reproduzível — 2026-08-05

- [x] Executor DuckDB criado em `executor/` e instalado na VPS.
- [x] Compose validado com rede desabilitada, dados somente leitura e artefatos isolados.
- [x] Run `quality_expanded_v1` concluído em 79,96 segundos.
- [x] 697.179.363 registros conferidos contra o manifesto de entrada.
- [x] Artefatos CSV e manifesto do run gerados e marcados como somente leitura.
- [x] Diretório temporário limpo e container descartado.

## Control plane inicial — 2026-08-05

- [x] Perfil do projeto vinculado ao repositório `mathdias2020/lab_automatizado`.
- [x] Schema privado `lab_automatizado` criado no Supabase compartilhado.
- [x] Tabelas de runs, commands, events, artifacts e workers criadas com RLS.
- [x] Fila idempotente com `FOR UPDATE SKIP LOCKED` criada.
- [x] Gateway RPC server-side prefixado criado e restrito a `service_role`.
- [x] Worker Python e wrapper seguro do executor documentados em `worker/`.
- [x] Painel mínimo criado em `panel/`, com fila de benchmark e tabela de auditoria.
- [x] Painel compilado com Next 16.3.0 e dependências sem vulnerabilidades no `npm audit`.
- [x] Chave server-side instalada na VPS sem entrar no Git.
- [x] Serviço worker instalado, testado automaticamente e habilitado no boot.
- [x] Benchmark automático concluído com `succeeded`, três artefatos e hashes registrados.
- [x] Supabase Auth integrado ao painel; `service_role` permanece apenas server-side.
- [x] Painel vinculado ao projeto Vercel `lab-automatizado-panel`, com produção publicada.
- [x] Primeiro usuário autorizado criado e login validado via Supabase Auth.
- [x] `PANEL_ALLOWED_EMAILS` configurado para restringir o painel deste laboratório.
- [x] Deployment Protection SSO da Vercel desativado; o limite de acesso agora é o Supabase Auth do painel.
- [x] Fluxo ponta a ponta validado: login → API autenticada → enqueue → worker Docker → `succeeded`.

## Monitoramento Hermes V1 — 2026-08-06

- [x] Registry privado de agentes, hipóteses e eventos aplicado no Supabase.
- [x] RPCs do Hermes restritas a `service_role`.
- [x] Estado inicial `hermes-supervisor = offline/disabled` registrado.
- [x] APIs server-side de leitura e revisão humana adicionadas ao painel.
- [x] Cards de estado, heartbeat, hipóteses vazias e revisão adicionados à UI.
- [x] Painel publicado em produção com o monitoramento Hermes V1.
- [x] Aprovação humana não dispara run nem promoção automática.
- [x] Controle play/pause persistido no Supabase com estado pausado por padrão.
- [x] Fila persistente de variantes, até 500 por hipótese e até 5 gerações.
- [x] Avaliador determinístico registra candidatos separados por WDOFUT/WINFUT.
- [x] Scheduler autônomo instalado e habilitado no boot da VPS.
- [x] Painel mostra controle, candidatos e slots de portfólio sem promoção automática.
- [x] Runtime observacional instalado em `/srv/labs/projects/lab_automatizado/hermes`.
- [x] Bridge privilegiada separada instalada para registrar heartbeat via RPC allowlisted.
- [x] `hermes-runtime.service` e `hermes-bridge.service` habilitados no boot.
- [x] Heartbeat confirmado no Supabase com quatro Parquets canônicos disponíveis.
- [x] Motor de raciocínio conectado em modo `proposal`, sem execução.
- [x] Primeira proposta WDOFUT e primeira proposta WINFUT registradas no Supabase.
- [ ] Revisar humanamente as duas propostas no painel.

## Primeiro experimento de pesquisa — 2026-08-06

- [x] Contrato `absorption_event_study_v1` congelado no repositório.
- [x] Execução separada para WDO e WIN, com thresholds calculados somente no treino.
- [x] Horizontes de 1, 5 e 15 minutos e baselines de agressão registrados.
- [x] Holdout 2025+ excluído; `holdout_accessed=false` nos dois runs.
- [x] Runs WDO `b27db3b4-c061-410b-bf3e-ab0024457a5c` e WIN `4ceaa057-b0f8-4ece-ad03-893fe90e58f0` concluídos com artefatos e hashes.
- [!] Resultado ainda é piloto: amostra histórica parcial, sem promoção; o contrato bruto mantém custos/slippage desativados por decisão.

Relatório: `docs/ABSORPTION_EVENT_STUDY_V1.md`.

## Thread de revisão Hermes–humano — 2026-08-06

- [x] Tabela privada `hypothesis_messages` criada com RLS e grants somente para `service_role`.
- [x] RPCs de leitura, postagem, claim, resposta e falha aplicadas no Supabase.
- [x] Fila pendente é fechada quando a hipótese é aprovada, rejeitada ou arquivada antes da resposta.
- [x] Smoke test transacional postar → claim → responder executado sem persistir dados de teste.
- [x] Endpoint autenticado do painel para listar e enviar mensagens implementado.
- [x] UI com thread, objeção, pergunta, resposta pendente e gate separado de aprovação implementada.
- [x] Engine Hermes preparado para responder mensagens por inbox/outbox sem receber `service_role`.
- [x] Bridge Hermes preparada para entregar e validar respostas por RPC.
- [x] Publicar estes arquivos na VPS e reiniciar `hermes-bridge.service`/`hermes-engine.service`.
- [x] Publicar o painel no Vercel e validar a tela autenticada em produção.

Relatório: `outputs/quality-expanded-v1-run-2026-08-05.md`.

Relatório resumido: `outputs/container-sample-validation-2026-08-05.md`.

## Próxima etapa

1. clicar em **Iniciar laboratório** no painel;
2. acompanhar a fila, o worker e os candidatos de WDO/WIN;
3. revisar os candidatos brutos com os artefatos e hashes do run;
4. aprovar humanamente uma etapa de validação fora da amostra;
5. avaliar correlação e preencher no máximo cinco slots por ativo somente após aprovação.

## Fora do escopo atual

- VPS Windows;
- ProfitDLL;
- replay;
- simulador operacional;
- ordens reais ou simuladas via corretora;
- painel de trading ao vivo;
- promoção automática;
- alteração de estratégia sem aprovação humana.

## Riscos conhecidos

- O tamanho total dos dados pode exigir armazenamento externo ou mais de uma VPS.
- Séries ajustadas podem ocultar detalhes necessários para algumas hipóteses de microestrutura.
- A pesquisa autônoma pode gerar resultados espúrios por múltiplos testes.
- Um backtest positivo não prova capacidade operacional futura.

## Regra de continuidade

Qualquer sessão futura deve começar lendo:

1. `PROJECT_CONTEXT.md`;
2. `DECISIONS.md`;
3. `STATUS.md`;
4. `docs/VALIDATION_PROTOCOL.md`.
