# Registro de decisões

Registro append-only das decisões tomadas nos grills e durante a execução do laboratório. Uma decisão nova não apaga a anterior; ela a substitui explicitamente quando necessário.

## D-023 — Autenticação do painel com Supabase Auth

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** o painel usa Supabase Auth com e-mail/senha; o cliente usa apenas uma chave publishable e as rotas server-side validam o bearer token antes de chamar as RPCs privilegiadas.
- **Motivo:** permitir controle pelo painel publicado sem expor a `service_role` e sem criar uma segunda camada de credenciais compartilhadas.
- **Impacto:** o primeiro usuário precisa ser criado manualmente em `Authentication → Users`; uma allowlist por e-mail pode ser ativada via `PANEL_ALLOWED_EMAILS` quando os usuários dos dois laboratórios forem conhecidos.

## D-024 — Painel publicado em projeto Vercel separado

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** o painel do Laboratório Automatizado usa o projeto Vercel `lab-automatizado-panel`, separado do código do worker e dos demais laboratórios.
- **Motivo:** manter a interface de controle independente, com variáveis sensíveis server-side e deploys reproduzíveis a partir da pasta `panel/`.
- **Impacto:** o perfil `lab-automatizado` agora vincula GitHub, Supabase e Vercel; o endpoint de produção é `https://lab-automatizado-panel.vercel.app/`.

## D-025 — Acesso do painel por Supabase Auth e allowlist

- **Data:** 2026-08-06
- **Status:** vigente
- **Decisão:** o painel usa Supabase Auth como autenticação única de aplicação e mantém `PANEL_ALLOWED_EMAILS` configurado para este laboratório; a Deployment Protection SSO da Vercel permanece desativada.
- **Motivo:** evitar uma segunda conta/proteção da Vercel bloqueando as rotas antes da autenticação do painel, sem deixar o gateway exposto a usuários anônimos.
- **Impacto:** login, API autenticada, enqueue, worker Docker e finalização `succeeded` foram validados ponta a ponta; credenciais não são armazenadas no repositório nem nos logs.

## D-026 — Primeiro estudo de absorção como event study

- **Data:** 2026-08-06
- **Status:** vigente para o piloto; sem promoção
- **Decisão:** o primeiro executor de pesquisa testa `absorption_event_study_v1` em runs independentes de WDO e WIN, usando agressão extrema mais movimento contemporâneo pequeno, com horizontes de 1/5/15 minutos e baselines explícitos.
- **Motivo:** validar o ciclo científico completo antes de permitir descoberta autônoma ou simulação operacional.
- **Impacto:** os dois runs concluíram com artefatos e hashes, sem acessar 2025+/holdout; a amostra parcial não sustenta promoção e deve ser expandida antes de novos ajustes.

## D-027 — Objetivo por contrato e portfólio por ativo

- **Data:** 2026-08-06
- **Status:** vigente; substitui D-003 e D-010
- **Decisão:** remover do objetivo do projeto o capital de referência de R$ 1 milhão, o limite de perda de R$ 100 mil e o retorno percentual sobre capital. Cada ativo terá um portfólio independente, buscando média de R$ 1.000 por contrato operado por mês. A referência por operação será WDO 10 contratos e WIN 50 contratos.
- **Critério de aceitação:** a média de longo prazo é a métrica principal. A faixa mensal inicial de monitoramento é R$ 700–R$ 1.300 por contrato; um mês abaixo da faixa gera diagnóstico e não invalida o portfólio. Resultado bruto será reportado para pesquisa; resultado líquido após custos e slippage é obrigatório para promoção operacional.
- **Motivo:** medir a qualidade econômica do portfólio por unidade operacional, sem amarrar a pesquisa a um capital arbitrário nem reagir de forma excessiva a um único mês.
- **Impacto:** WDO e WIN não se compensam. O PnL escalado usa contratos efetivamente executados; a referência 10/50 não oculta liquidez, correlação, exposição simultânea ou capacidade.

## D-028 — Hermes como sistema adaptativo de pesquisa

- **Data:** 2026-08-06
- **Status:** vigente no desenho V1; implementação ainda pendente
- **Decisão:** o Hermes terá acesso de leitura aos dados brutos de desenvolvimento e poderá explorar, explicar falhas, propor hipóteses e sugerir variantes de entrada e saída. Hipóteses serão formalizadas, revisadas adversarialmente e executadas por um avaliador determinístico. Break-even, trailing stop, saída parcial, time stop e encerramento de sessão entram como políticas de saída versionadas e limitadas.
- **Restrições:** memória do Hermes não é fonte científica; o holdout fica protegido; o agente não altera métricas, splits, executor, dados brutos ou critérios de promoção e não recebe acesso a ordens, ProfitDLL, Docker socket, sudo ou `service_role`.
- **Motivo:** usar a capacidade de exploração e interpretação do agente sem permitir que ele selecione o próprio gabarito ou transforme uma narrativa pós-resultado em evidência.
- **Impacto:** o próximo entregável é o contrato do sistema Hermes, com registry de hipóteses, orçamento de experimentos, revisão adversarial, métricas do agente e ferramentas allowlisted.

## D-029 — Monitoramento Hermes V1 separado da execução

- **Data:** 2026-08-06
- **Status:** vigente
- **Decisão:** o painel deste laboratório terá uma integração própria para monitorar o Hermes e revisar hipóteses, usando as tabelas `agents`, `hypotheses` e `agent_events` no schema privado `lab_automatizado`. O estado inicial do agente é `offline`/`disabled`.
- **Restrições:** a aprovação humana no painel apenas registra `approved_for_test`; ela não inicia um run, não altera o executor e não promove estratégia. O runtime do Hermes será instalado separadamente na área deste laboratório e não compartilhará estado operacional com o outro laboratório.
- **Motivo:** permitir acompanhar e governar a descoberta desde o início, mantendo a barreira entre inteligência exploratória, avaliação determinística e promoção.
- **Impacto:** o próximo passo técnico é instalar o runtime isolado, emitir heartbeat e registrar a primeira proposta formal; a execução continua fora do escopo até esse contrato ser validado.

## D-030 — Bootstrap Hermes sem credencial no runtime

- **Data:** 2026-08-06
- **Status:** vigente
- **Decisão:** o bootstrap do Hermes roda na VPS em `hermes-runtime.service`, como `labadmin`, somente em `observation`, sem rede, sem Docker socket, sem `service_role` e sem geração de hipóteses. Uma `hermes-bridge.service` separada lê o heartbeat validado e chama somente `lab_automatizado_heartbeat_agent`.
- **Motivo:** validar a presença do agente e a telemetria antes de conectar um motor de raciocínio ou conceder capacidade de proposta.
- **Impacto:** o Supabase já recebe heartbeat recorrente; a próxima mudança de escopo será conectar o motor de raciocínio em modo `observation`/`proposal`, com uma chave de modelo isolada e sem acesso ao holdout.

## D-015 — Control plane privado e worker sem Docker socket

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** o laboratório usa o schema Supabase privado `lab_automatizado`; o acesso operacional ocorre por RPCs prefixadas, restritas a `service_role`.
- **Motivo:** compartilhar o projeto Supabase sem misturar os dois laboratórios e sem expor a fila de execução ao navegador.
- **Impacto:** o painel será server-side e a chave `service_role` ficará somente em ambientes protegidos. O worker Linux não montará Docker socket; ele chamará apenas um wrapper root-owned para o executor DuckDB permitido.

## D-016 — Fila serializada na KVM2

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** jobs pesados deverão ser reivindicados por fila com `FOR UPDATE SKIP LOCKED` e executados com limites explícitos de CPU, memória, PIDs e rede.
- **Motivo:** a VPS possui 2 vCPU e aproximadamente 8 GB de RAM; concorrência irrestrita prejudicaria a validade e a estabilidade dos experimentos.
- **Impacto:** o worker inicial só aceita `quality_benchmark`; pesquisa autônoma e outros tipos entrarão por contratos posteriores.

## D-017 — Painel sem publicação pública antes de autenticação

- **Data:** 2026-08-05
- **Status:** superada por D-023
- **Decisão:** o painel inicial pode ser desenvolvido e testado localmente, mas não será publicado como aplicação pública enquanto a autenticação e as variáveis server-side não estiverem configuradas.
- **Motivo:** a interface dispara comandos que consomem recursos da VPS; nenhum visitante anônimo deve alcançar o gateway `service_role`.
- **Impacto histórico:** o painel exigia `PANEL_INTERNAL_TOKEN` até a implementação do Supabase Auth; a regra vigente está em D-023.

## D-001 — Separar pesquisa de execução

- **Data:** 2026-08-04
- **Status:** vigente
- **Decisão:** a primeira fase não terá VPS Windows, ProfitDLL, replay, simulador operacional ou envio de ordens.
- **Motivo:** validar primeiro se existe uma hipótese robusta antes de assumir a complexidade operacional da execução.
- **Impacto:** o laboratório inicial trabalhará com dados históricos e experimentos reproduzíveis.

## D-002 — Documentar antes de provisionar infraestrutura

- **Data:** 2026-08-04
- **Status:** vigente
- **Decisão:** criar o contexto, o registro de decisões, o status e o protocolo de validação antes de configurar a Hostinger.
- **Motivo:** evitar que a infraestrutura defina prematuramente o desenho do projeto.
- **Impacto:** a primeira entrega deste projeto é documental e metodológica; a VPS virá depois do inventário dos dados.

## D-003 — Objetivo financeiro e limite de parada — decisão histórica

- **Data:** 2026-08-04
- **Status:** superada por D-027
- **Decisão histórica:** capital de referência de R$ 1 milhão, perda máxima de 10% e objetivo de 25% bruto. Esta formulação não é mais usada no objetivo, no sizing ou nos gates do projeto.
- **Motivo:** estabelecer o que o sistema precisa proteger e o que se deseja alcançar.
- **Impacto:** o limite de perda será uma barreira de desligamento; o retorno não será usado sozinho para promover estratégias.

## D-004 — Frequência desejada sem quota forçada

- **Data:** 2026-08-04
- **Status:** vigente
- **Decisão:** buscar média de cinco operações semanais somando WDO e WIN, sem obrigar entradas para cumprir a meta.
- **Motivo:** preservar a intenção de validar atividade sem transformar frequência em incentivo a overtrading.

## D-005 — Validação separada por ativo

- **Data:** 2026-08-04
- **Status:** vigente
- **Decisão:** WDO e WIN serão pesquisados e validados separadamente.
- **Motivo:** evitar que uma série, escala ou comportamento de microestrutura mascare o resultado da outra.

## D-006 — Portfólio de estratégias independentes

- **Data:** 2026-08-04
- **Status:** vigente
- **Decisão:** o objetivo é formar um portfólio de estratégias independentes; não existe número fixo obrigatório de estratégias.
- **Motivo:** adicionar estratégias pela evidência e contribuição marginal, não por uma meta arbitrária de quantidade.

## D-007 — Autonomia do laboratório com promoção humana

- **Data:** 2026-08-04
- **Status:** vigente
- **Decisão:** agentes podem gerar hipóteses, código e experimentos dentro do espaço permitido; promoção para qualquer fase operacional exige aprovação humana.
- **Motivo:** permitir exploração em escala sem delegar a decisão irreversível de produção.

## D-008 — Dados e holdout

- **Data:** 2026-08-04
- **Status:** vigente
- **Decisão:** usar cinco anos de histórico confiável e sincronizado como base principal, preservar aproximadamente os doze meses mais recentes como holdout cego e usar os trinta dias úteis ricos em microestrutura de forma complementar.
- **Motivo:** separar descoberta de confirmação e evitar que detalhes disponíveis somente no período curto sejam apresentados como evidência de longo prazo.

## D-009 — Séries contínuas ajustadas

- **Data:** 2026-08-04
- **Status:** vigente
- **Decisão:** séries contínuas ajustadas são a representação principal da pesquisa; detalhes de contratos individuais serão tratados como robustez operacional futura, quando aplicável.
- **Motivo:** manter o protocolo alinhado aos dados históricos disponíveis sem inventar granularidade ausente.

## D-010 — Contratos por operação — decisão histórica

- **Data:** 2026-08-04
- **Status:** superada por D-027
- **Decisão histórica:** por cada R$ 100 mil e por operação: WDO 5/10/20; WIN 10/20/40 contratos, respectivamente mínimo/padrão/máximo. Esta regra foi substituída pela base independente de capital de WDO 10 e WIN 50 em D-027.
- **Motivo:** o WIN utiliza o dobro da quantidade definida para o WDO.
- **Impacto:** duas operações simultâneas conservam sizing independente; a camada global continua monitorando risco agregado.

## D-011 — Supabase como plano de controle posterior

- **Data:** 2026-08-04
- **Status:** planejada, não implementada
- **Decisão:** usar Supabase gerenciado para metadados, estados, auditoria e controle do laboratório depois que o contrato de experimento estiver definido.
- **Motivo:** preservar histórico e permitir painel sem transformar o banco em armazenamento primário de ticks.

## D-012 — Hostinger Linux como worker posterior

- **Data:** 2026-08-04
- **Status:** planejada, não implementada
- **Decisão:** usar a Hostinger Linux para agentes e processamento após medir volume, tempo de execução e necessidade de disco.
- **Motivo:** dimensionar a infraestrutura a partir de uma carga real e manter a VPS Windows/ProfitDLL fora da fase de pesquisa.

## D-013 — Dataset global e imutável

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** os dois laboratórios compartilharão uma única camada global de Parquets na VPS, montada nos containers em modo somente leitura.
- **Motivo:** evitar duplicação de dezenas de GB e garantir que os projetos partam do mesmo snapshot de dados.
- **Impacto:** datasets terão manifestos e hashes; resultados, configurações, logs e artefatos permanecerão separados por projeto.

## D-014 — Dois laboratórios isolados por Docker

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** cada laboratório terá seu próprio projeto Docker Compose, rede, volumes graváveis e configurações.
- **Motivo:** permitir evolução independente sem misturar dependências ou resultados.
- **Impacto:** os containers não poderão gravar no dataset global, acessar o Docker socket ou compartilhar credenciais por padrão.

## D-015 — Baseline da VPS

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** a KVM2 foi preparada com Ubuntu 24.04.4, Docker, Compose, usuário labadmin, UFW limitado a SSH e swap de 2 GB.
- **Motivo:** estabelecer uma base mínima antes de transferir dados ou executar agentes.
- **Impacto:** nenhum container ou Parquet foi iniciado/transferido nesta etapa.

## D-016 — Identidade do laboratório

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** este projeto se chama Laboratório Automatizado e usa o identificador técnico lab_automatizado.
- **Motivo:** o segundo laboratório também pesquisa WDO e WIN; os ativos não podem ser usados como identidade do projeto.
- **Impacto:** o nome técnico será usado no Docker, no Supabase e nos artefatos deste laboratório.

## D-017 — Inventário dos Parquets

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** o inventário deve preceder a transferência para a VPS; o dataset completo não será enviado enquanto a transição de schema não for tratada.
- **Motivo:** existem 341 arquivos, aproximadamente 76,59 GB, uma partição WDOFUT ausente e duas assinaturas de schema.
- **Impacto:** a próxima etapa é escolher a amostra e definir se a compatibilização ocorrerá na origem, na leitura ou em uma camada derivada.

## D-018 — Amostra de transferência

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** transferir primeiro uma amostra de 100.000 negócios por ativo e por schema, preservando os arquivos derivados sem alterar os originais.
- **Motivo:** validar transporte, hashes, permissões e compatibilidade antes de mover aproximadamente 71,33 GiB.
- **Impacto:** a amostra está na VPS em transfer_sample_v1; o dataset completo continua bloqueado até a decisão de normalização.

## D-020 — Contrato canônico inicial

- **Data:** 2026-08-05
- **Status:** vigente para a amostra; sujeito a auditoria em meses adicionais
- **Decisão:** usar `normalized_sample_v1` como camada derivada de leitura para experimentos, com `event_ts`, `asset`, `ticker`, `trade_number`, `price`, `quantity`, `volume`, campos brutos de agentes/tipo, flags de origem e `source_file`.
- **Motivo:** unificar as duas variantes sem alterar a fonte nem inventar semântica de agressão, player ou lado.
- **Impacto:** a camada foi validada em 400.000 linhas; a aplicação ao dataset completo e a definição do snapshot de pesquisa continuam pendentes.

## D-021 — Amostra ampliada e capacidade de processamento

- **Data:** 2026-08-05
- **Status:** vigente para o planejamento do executor
- **Decisão:** usar uma amostra de 16 arquivos, oito meses por ativo, como referência de compatibilidade; manter a normalização pesada em fila ou por partição na KVM2.
- **Motivo:** o contrato passou por meses antigos, intermediários e pela transição `legacy → recent`, preservando 697.179.363 linhas. A materialização ultrapassou 15 minutos, embora o resultado tenha passado na validação posterior.
- **Impacto:** a KVM2 é adequada como worker de pesquisa controlada, mas não deve normalizar o snapshot inteiro enquanto houver concorrência com os dois laboratórios.

## D-022 — Primeiro executor reproduzível

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** o Laboratório Automatizado usará um executor DuckDB descartável, fixado por digest, com rede desabilitada, Parquets somente leitura, artefatos por run e spill temporário isolado.
- **Motivo:** o run `quality_expanded_v1` processou 697.179.363 registros em 79,96 segundos e produziu evidências auditáveis sem escrita externa.
- **Impacto:** o próximo trabalho passa a ser definir uma primeira feature/métrica de pesquisa e um baseline reproduzível; Supabase e agentes continuam fora desta etapa.

## D-019 — Leitura remota da amostra

- **Data:** 2026-08-05
- **Status:** vigente
- **Decisão:** a amostra pode ser lida por DuckDB em container temporário, com os Parquets montados em modo somente leitura e com `union_by_name` para a transição inicial entre schemas.
- **Motivo:** o teste remoto confirmou transporte, permissões, leitura dos quatro arquivos e consolidação de 400.000 linhas sem alterar a fonte.
- **Impacto:** ainda não está decidido se o laboratório usará leitura direta dos Parquets, uma camada normalizada derivada ou ambos; o dataset completo permanece bloqueado até essa decisão.
