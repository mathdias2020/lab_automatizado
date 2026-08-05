# Registro de decisões

Registro append-only das decisões tomadas nos grills e durante a execução do laboratório. Uma decisão nova não apaga a anterior; ela a substitui explicitamente quando necessário.

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

## D-003 — Objetivo financeiro e limite de parada

- **Data:** 2026-08-04
- **Status:** vigente
- **Decisão:** capital de referência de R$ 1 milhão, perda máxima de 10% e objetivo de 25% bruto.
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

## D-010 — Contratos por operação

- **Data:** 2026-08-04
- **Status:** vigente para a fase futura
- **Decisão:** por cada R$ 100 mil e por operação: WDO 5/10/20; WIN 10/20/40 contratos, respectivamente mínimo/padrão/máximo.
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
